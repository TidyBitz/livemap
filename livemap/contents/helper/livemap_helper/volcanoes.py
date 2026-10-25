"""Volcanoes: Smithsonian weekly report and eruption database, USGS alert levels."""
import json
import time
import os
import re
import urllib.error
import urllib.request
from collections import Counter

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, EVENTS, MAX_BODY, PKG, UA, VERSION, _http, _plain, emit, last_good, remember_events, safe_xml, \
    stale_note, fetch_json


# ------------------------------------------------------------ volcanoes -----
GVP_FEEDS = ["https://volcano.si.edu/news/WeeklyVolcanoRSS.xml", "https://volcano.si.edu/news/WeeklyVolcanoCAP.xml"]


def parse_volcano_feed(xml_text):
    """Volcanoes from the weekly report's RSS or CAP feed. Coordinates are looked for wherever such feeds
    put them (georss:point "lat lon", geo:lat + geo:long, cap:circle "lat,lon radius"), whatever the namespace."""
    import xml.etree.ElementTree as ET
    local = lambda el: el.tag.rsplit("}", 1)[-1].lower()
    rows, tags = [], Counter()
    for item in ET.fromstring(safe_xml(xml_text)).iter():
        if local(item) not in ("item", "entry", "info"):
            continue
        f, lat, lon = {}, None, None
        for el in item.iter():
            k, v = local(el), (el.text or "").strip()
            tags[k] += 1
            if not v:
                continue
            f.setdefault(k, v)
            nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", v)]
            if k in ("point", "circle") and len(nums) >= 2:
                lat, lon = nums[0], nums[1]
            elif k == "lat" and nums:
                lat = nums[0]
            elif k in ("long", "lon") and nums:
                lon = nums[0]
        title = f.get("title") or f.get("headline") or f.get("event") or ""
        m = re.match(r"\s*(.+?)\s*\((.+?)\)", title)
        name, country = (m.group(1), m.group(2)) if m else (title.split(" - ")[0].strip(), "")
        if not name:
            continue
        fresh = bool(re.search(r"\bnew\b", " ".join([title, f.get("category", ""), f.get("description", "")[:160]]), re.I))
        reported = None
        try:
            from email.utils import parsedate_to_datetime
            reported = int(parsedate_to_datetime(f.get("pubdate") or f.get("sent") or "").timestamp())
        except Exception:
            pass
        rows.append({"name": name, "country": country, "lat": lat, "lon": lon, "new": fresh, "reported": reported, "since": "",
                     "status": "new" if fresh else "continuing"})
    seen, out = set(), []
    for r in rows:                                 # a volcano can appear twice (RSS item + CAP info)
        if r["name"] not in seen:
            seen.add(r["name"])
            out.append(r)
    return out, tags


def report_table(html):
    """{volcano: (eruption start date, status)} from the table on the weekly report's web page: the feeds do not
    carry the start date. Pure enrichment - if the page changes and nothing is found, the layer works without it.
    Columns: Name, Country, Volcanic Region, Eruption Start Date, Report Type ("New Eruptive Activity",
    "Continuing Eruptive Activity", "Other Observations")."""
    import html as htmllib
    out = {}
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", html, flags=re.S | re.I):
        cells = [" ".join(htmllib.unescape(re.sub(r"<[^>]+>", " ", c)).split())
                 for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, flags=re.S | re.I)]
        if len(cells) < 4:
            continue
        kind = next((c.lower() for c in cells if re.match(r"(new|continuing|other)\b", c.lower())), "")
        if not kind:
            continue
        status = kind.split()[0]
        m = next((re.match(r"(\d{4}(?: \w{3}(?: \d{1,2})?)?)$", c) for c in cells if re.match(r"\d{4}", c)), None)
        out[cells[0].lower()] = (m.group(1) if m else "", status)
    return out


# USGS volcano alert levels (Hazard Alert Notification System, public API, no key). Levels: NORMAL (green),
# ADVISORY (yellow), WATCH (orange), WARNING (red). Only the elevated ones are listed; US volcanoes only.
USGS_HANS = "https://volcanoes.usgs.gov/hans-public/api/"


ALERT_COLORS = ("green", "yellow", "orange", "red")


def _cap_date(t):
    """'2026-08-25T19:47:11-10:00' -> '2026 Aug 25' (the style the weekly report uses)."""
    from datetime import datetime
    try:
        return datetime.fromisoformat(t).strftime("%Y %b %d")
    except (TypeError, ValueError):
        return ""


def _report_hours(since, now=None):
    """'2024 Dec 23' (or '2024 Dec', '2024') from the weekly table -> hours since, else None."""
    import time
    from datetime import datetime
    now = now or time.time()
    for fmt in ("%Y %b %d", "%Y %b", "%Y"):
        try:
            return round((now - datetime.strptime(since, fmt).timestamp()) / 3600, 1)
        except (TypeError, ValueError):
            pass
    return None


def _cap_hours(t, now):
    from datetime import datetime
    try:
        return round((now - datetime.fromisoformat(t).timestamp()) / 3600, 1)
    except (TypeError, ValueError):
        return None


def fetch_usgs_alerts(now=None):
    """[{name, vnum, lat, lon, alert, level, issued_hours, elevated_since, notice}] for every US volcano at an
    elevated level. Coordinates: from the CAP feed (orange and red), else from the notice the volcano was last
    mentioned in (remembered in events.json so a notice is read once)."""
    import time
    now = now or time.time()
    rows = fetch_json(USGS_HANS + "volcano/getElevatedVolcanoes")
    caps = {}
    try:
        for c in fetch_json(USGS_HANS + "volcano/getCapElevated"):
            caps[str(c.get("vnum"))] = c
    except Exception:
        pass
    try:
        mem = json.loads(EVENTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    coords = mem.setdefault("usgs_coords", {})
    out, fetched = [], set()
    for r in rows:
        vnum, cap = str(r.get("vnum")), caps.get(str(r.get("vnum")), {})
        lat, lon = cap.get("latitude"), cap.get("longitude")
        if lat is None and vnum in coords:
            lat, lon = coords[vnum]
        if lat is None and r.get("notice_data") and r["notice_data"] not in fetched:
            fetched.add(r["notice_data"])
            try:                                            # one notice names every volcano it covers, with lat/lng
                notice = fetch_json(r["notice_data"])
                for sec in notice.get("notice_sections") or []:
                    if sec.get("lat") is not None and sec.get("vnum"):
                        coords[str(sec["vnum"])] = [float(sec["lat"]), float(sec["lng"])]
            except Exception:
                pass
            if vnum in coords:
                lat, lon = coords[vnum]
        issued = r.get("sent_unixtime")
        out.append({"name": r.get("volcano_name", ""), "vnum": vnum, "lat": lat, "lon": lon,
                    "alert": (r.get("color_code") or "").lower(), "level": (r.get("alert_level") or "").title(),
                    "issued_hours": round((now - issued) / 3600, 1) if issued else None,
                    # the CAP feed keeps the previous notice: when that one was not elevated, this level dates from then
                    "elevated_since": _cap_date(cap.get("prev_sent_date_cap")) if cap and not cap.get("prev_is_elevated_cap") else "",
                    "elevated_hours": _cap_hours(cap.get("prev_sent_date_cap"), now) if cap and not cap.get("prev_is_elevated_cap") else None,
                    "observatory": r.get("obs_fullname", ""), "notice": r.get("notice_url", "")})
    try:
        EVENTS.parent.mkdir(parents=True, exist_ok=True)
        tmp = EVENTS.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps(mem), encoding="utf-8")
        tmp.replace(EVENTS)
    except OSError:
        pass
    return out


# GeoNet (New Zealand): the official Volcanic Alert Level (0-5) and aviation colour code of every monitored
# volcano, GeoJSON, no key. Only raised levels (1 and up) are drawn, in the colour code's colour, like USGS's.
GEONET_VAL = "https://api.geonet.org.nz/volcano/val"
GEONET_HEADERS = dict(UA, Accept="application/vnd.geo+json;version=2")
GEONET_COLOUR = {"green": "green", "yellow": "yellow", "orange": "orange", "red": "red"}


def parse_geonet(body):
    out = []
    for f in body.get("features") or []:
        p = f.get("properties") or {}
        c = (f.get("geometry") or {}).get("coordinates") or []
        try:
            level = int(p.get("level") or 0)
            lon, lat = float(c[0]), float(c[1])
        except (TypeError, ValueError, IndexError):
            continue
        if level < 1:
            continue
        acc = str(p.get("acc") or "").lower()
        out.append({"name": str(p.get("volcanoTitle") or p.get("volcanoID") or ""), "vnum": "geonet:" + str(p.get("volcanoID") or ""), "lat": lat, "lon": lon,
                    "alert": GEONET_COLOUR.get(acc, "yellow" if level < 3 else "orange" if level < 4 else "red"), "level": "Level %d" % level,
                    "issued_hours": None, "elevated_since": "", "elevated_hours": None, "observatory": "GeoNet", "notice": "https://www.geonet.org.nz/volcano",
                    "activity": str(p.get("activity") or ""), "hazards": str(p.get("hazards") or "")})
    return out


def fetch_geonet_alerts():
    body = fetch_json(GEONET_VAL, timeout=12, headers=GEONET_HEADERS)
    return parse_geonet(body)


def chk_geonet():
    alerts = fetch_geonet_alerts()
    return "ok", "%d New Zealand volcanoes at a raised level%s" % (len(alerts), ": " + ", ".join("%s %s" % (a["name"], a["level"].lower()) for a in alerts) if alerts else "")


# JMA (Japan): the volcanic warnings in force, one entry per volcano with its alert level (1-5) as a two-digit
# code "1<level>" in the first group of volcanoInfos. The file is undocumented and in Japanese; the volcano is
# named in Japanese and matched to contents/data/japan-volcanoes.json (JMA's own list of 111 active volcanoes
# with English names and positions). Levels 2 and up are drawn: 2 yellow, 3 orange, 4-5 red.
JMA_WARNINGS = "https://www.jma.go.jp/bosai/volcano/data/warning.json"
JP_VOLCANOES = PKG / "data" / "japan-volcanoes.json"
JMA_LEVEL_COLOUR = {2: "yellow", 3: "orange", 4: "red", 5: "red"}


def parse_jma(body, table=None):
    if table is None:
        try:
            table = json.loads(JP_VOLCANOES.read_text(encoding="utf-8"))["volcanoes"]
        except (OSError, ValueError, KeyError):
            table = {}
    out = []
    for entry in body if isinstance(body, list) else []:
        level, jp = 0, ""
        for group in entry.get("volcanoInfos") or []:
            for item in group.get("items") or []:
                code = str(item.get("code") or "")
                if len(code) == 2 and code[0] == "1" and code[1].isdigit():
                    level = max(level, int(code[1]))
                    for a in item.get("areas") or []:
                        jp = jp or str(a.get("name") or "")
        if level < 2 or not jp:
            continue
        v = table.get(jp) or next((t for k, t in table.items() if k in jp or jp in k), None)
        if not v:
            continue
        issued = None
        try:
            from datetime import datetime
            issued = datetime.fromisoformat(str(entry.get("reportDatetime"))).timestamp()
        except (ValueError, TypeError):
            pass
        out.append({"name": v["en"], "vnum": "jma:" + str(entry.get("eventId") or jp), "lat": v["lat"], "lon": v["lon"],
                    "alert": JMA_LEVEL_COLOUR.get(level, "red"), "level": "Level %d" % level,
                    "issued_hours": round((time.time() - issued) / 3600, 1) if issued else None, "elevated_since": "", "elevated_hours": None,
                    "observatory": "JMA", "notice": "https://www.jma.go.jp/bosai/map.html#contents=volcano", "japanese": jp})
    return out


def fetch_jma_alerts():
    body = fetch_json(JMA_WARNINGS, timeout=12)
    return parse_jma(body)


def chk_jma():
    alerts = fetch_jma_alerts()
    return "ok", "%d Japanese volcanoes at level 2 or above%s" % (len(alerts), ": " + ", ".join("%s %s" % (a["name"], a["level"].lower()) for a in alerts[:8]) if alerts else "")


def merge_usgs_alerts(rows, alerts):
    """Attach alert levels to the weekly report's volcanoes (matched by name, accents ignored) and append the
    elevated US volcanoes the report does not mention, so a raised level shows up the day it happens."""
    by_name = {_plain(r["name"]): r for r in rows}
    for a in alerts:
        key = _plain(re.sub(r"\s+volcano$", "", a["name"], flags=re.I))
        r = by_name.get(key) or next((by_name[k] for k in by_name if k.startswith(key) or key.startswith(k)), None)
        if r is None:
            if a["lat"] is None:
                continue
            r = {"name": a["name"], "country": {"GeoNet": "New Zealand", "JMA": "Japan"}.get(a.get("observatory"), "United States"), "lat": a["lat"], "lon": a["lon"], "new": False,
                 "reported": None, "since": "", "status": "alert"}
            rows.append(r)
            by_name[key] = r
        r.update(alert=a["alert"], level=a["level"], alert_hours=a["issued_hours"], alert_since=a["elevated_since"],
                 elevated_hours=a["elevated_hours"], observatory=a["observatory"])
    return rows


def chk_usgs_alerts():
    alerts = fetch_usgs_alerts()
    named = ", ".join("%s %s" % (a["name"], a["alert"]) for a in alerts)
    missing = sum(1 for a in alerts if a["lat"] is None)
    return ("warn" if missing else "ok"), "%d US volcanoes at an elevated level%s%s" % (
        len(alerts), ": " + named if named else "", " - %d without coordinates yet" % missing if missing else "")


def report_table_loose(html, names):
    """Fallback when the page's table markup is not what report_table expects (0 rows although the page
    loaded): for each volcano name from the feed, look for a report type phrase and an eruption start date
    in the stretch of HTML that follows the name. Markup-independent, so it survives a page redesign."""
    import html as htmllib
    text = htmllib.unescape(re.sub(r"<[^>]+>", " ", html))
    text = " ".join(text.split())
    out = {}
    for name in names:
        for m in re.finditer(re.escape(name), text):
            chunk = text[m.end():m.end() + 400]
            kind = re.search(r"\b(New|Continuing|Other)\s+(Eruptive Activity|Observations)", chunk)
            if not kind:
                continue
            date = re.search(r"\b((?:19|20)\d{2}(?: [A-Z][a-z]{2}(?: \d{1,2})?)?)\b", chunk[:kind.start()])
            out[name.lower()] = (date.group(1) if date else "", kind.group(1).lower())
            break
    return out


# The Smithsonian's own eruption database (Volcanoes of the World, WFS, no key): every eruption still marked as
# continuing, with its start date. Structured, unlike the weekly report page, so this is the first place to
# look for "erupting since"; the page is only a fallback.
GVP_WFS = ("https://webservices.volcano.si.edu/geoserver/GVP-VOTW/ows?service=WFS&version=2.0.0&request=GetFeature"
           "&typeName=GVP-VOTW:E3WebApp_Eruptions1960&outputFormat=json&CQL_FILTER=ContinuingEruption%3D%27True%27")


ERUPTIONS = DATA / "eruptions.json"


def gvp_eruptions(max_age_h=24):
    """{plain volcano name: 'YYYY Mon DD'} of continuing eruptions, cached for a day."""
    import time
    from datetime import datetime
    try:
        c = json.loads(ERUPTIONS.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600 and c.get("eruptions"):
            return c["eruptions"]
    except (OSError, ValueError):
        pass
    body = fetch_json(GVP_WFS)
    out = {}
    for f in body.get("features", []):
        p = f.get("properties") or {}
        name = str(p.get("VolcanoName") or "")
        try:
            when = datetime(int(p["StartDateYear"]), int(p.get("StartDateMonth") or 1), int(p.get("StartDateDay") or 1)).strftime("%Y %b %d")
        except (KeyError, TypeError, ValueError):
            continue
        for key in {_plain(name), _plain(" ".join(reversed([t.strip() for t in name.split(",")])))}:   # "Lengai, Ol Doinyo"
            if key and (key not in out or when > out[key]):
                out[key] = when
    if out:
        try:
            ERUPTIONS.parent.mkdir(parents=True, exist_ok=True)
            ERUPTIONS.write_text(json.dumps({"at": time.time(), "eruptions": out}), encoding="utf-8")
        except OSError:
            pass
    return out


def chk_eruptions():
    er = gvp_eruptions()
    return ("ok" if er else "warn"), "%d continuing eruptions with a start date" % len(er)


TABLE_ROWS = -1          # rows found on the weekly report page by the last fetch; -1 = page not read


WEEKLY = DATA / "weekly-report.json"


def weekly_table(max_age_h=24, names=()):
    """The weekly report page's table, cached for a day: the page is slow (often more than the 6 s the feeds get),
    and it only changes on Wednesdays."""
    import time
    try:
        c = json.loads(WEEKLY.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600 and c.get("table"):
            return c["table"]
    except (OSError, ValueError):
        pass
    url, table, page = "https://volcano.si.edu/reports_weekly.cfm", {}, ""
    for headers in (UA, {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) livemap-wallpaper/" + VERSION, "Accept": "text/html"}):
        try:                                            # some front ends refuse a plain script user agent: try a browser-like one
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=25) as r:
                page = r.read(MAX_BODY).decode("utf-8", "replace")
            table = report_table(page)
            if not table and names:
                table = report_table_loose(page, names)
            if table:
                break
        except urllib.error.HTTPError as e:
            if e.code not in (403, 406, 429):
                raise
    if not table and page:
        try:                                            # keep the page for a look: livemap-helper volcanoes --table says where
            (DATA / "weekly-report.html").write_text(page, encoding="utf-8")
        except OSError:
            pass
    if table:
        try:
            WEEKLY.parent.mkdir(parents=True, exist_ok=True)
            WEEKLY.write_text(json.dumps({"at": time.time(), "table": table}), encoding="utf-8")
        except OSError:
            pass
    return table


def chk_weekly_page():
    try:
        names = [r["name"] for r in fetch_volcanoes()[0]]
    except Exception:
        names = []
    table = weekly_table(names=names)
    dated = sum(1 for v in table.values() if v[0])
    return ("ok" if table else "warn"), "%d volcanoes in the report table, %d with an eruption start date" % (len(table), dated)


def fetch_volcanoes():
    last = None
    for url in GVP_FEEDS:                          # the RSS first; the CAP feed if the RSS has no coordinates
        _c, _h, body, _t = _http(url)
        rows, tags = parse_volcano_feed(body.decode("utf-8", "replace"))
        last = (rows, tags, url)
        if any(r["lat"] is not None for r in rows):
            break
    global TABLE_ROWS
    TABLE_ROWS = -1
    try:                                           # eruption start dates: the Smithsonian database first
        er = gvp_eruptions()
        for r in last[0]:
            when = er.get(_plain(r["name"]))
            if when:
                r["since"] = when
    except Exception:
        pass
    try:                                           # report type (New / Continuing) and any date still missing: the page
        table = weekly_table(names=[r["name"] for r in last[0]])
        TABLE_ROWS = len(table)
        for r in last[0]:
            key = r["name"].lower()
            if key not in table:                                       # "Kīlauea" on the page, "Kilauea" in the feed
                import unicodedata
                plain = lambda t: "".join(c for c in unicodedata.normalize("NFKD", t) if not unicodedata.combining(c))
                key = next((k for k in table if plain(k) == plain(key)), key)
            if key in table:
                r["since"], r["status"] = r["since"] or table[key][0], table[key][1]
                r["new"] = r["status"] == "new"      # the table's own New / Continuing beats guessing from the text
    except Exception:
        pass
    return last


def cmd_volcanoes(args):
    note, rows, tags, url = "", [], Counter(), ""
    data, stale_h, err = last_good("volcanoes", lambda: list(fetch_volcanoes()[0]))
    rows = data or []
    primary_note = stale_note("Volcanoes", stale_h, err, args.stale) if err else ""
    if not err:
        url = GVP_FEEDS[0]
    alerts_note = ""
    adata, astale, aerr = last_good("usgs-alerts", fetch_usgs_alerts)
    # the Smithsonian feed down (a 403 for days) while USGS's alert levels answer: Status says so, the map keeps
    # its last list and the levels; the corner notice only when both are out
    if primary_note and (aerr or not adata):
        note = primary_note
    for cache, fetch in (("geonet-alerts", fetch_geonet_alerts), ("jma-alerts", fetch_jma_alerts)):
        more, _s, _e = last_good(cache, fetch)
        if more:
            rows = merge_usgs_alerts(rows, more)
    try:                                                              # ash advisories: an eruption in progress, within the hour
        from .vaac import vaac_cached, merge_vaac
        vdata, _vs, _ve = vaac_cached()
        if vdata and vdata.get("advisories"):
            rows = merge_vaac(rows, vdata["advisories"])
    except Exception:
        pass
    if adata:
        rows = merge_usgs_alerts(rows, adata)
    if aerr and not rows:                                  # a secondary source: the corner only when the primary is out too
        alerts_note = stale_note("USGS alert levels", astale, aerr, args.stale)
    placed = [r for r in rows if r["lat"] is not None and r["lon"] is not None]
    if rows and not placed:
        note = "Volcanoes: the feed lists %d volcanoes but no coordinates were found in it" % len(rows)
    for r in placed:
        r["hours"] = 0
        r.setdefault("alert", "")
    if placed:
        # a changed alert level or report status counts as newly reported (pulses again, says what it was)
        placed = remember_events("volcano", placed, lambda r: _plain(r["name"]), args.keep,
                                 sig_of=lambda r: "red" if r.get("alert") == "red" else "orange" if r.get("alert") == "orange" or r.get("status") == "new" else "yellow",
                                 raised_of=lambda r: bool(r.get("alert")))
        for r in placed:                           # how long above green: USGS's own date when the CAP feed has it, else as seen from here
            if r.get("alert") and r.get("elevated_hours") is None:
                r["elevated_hours"] = r.get("raised_hours")
            r["since_hours"] = _report_hours(r.get("since", ""))
    if alerts_note and not note:
        note = "" if placed else alerts_note
    if args.table:
        print(note or "%d volcanoes in this week's report (%s)" % (len(placed), url))
        print("  report page: %s" % ("not readable (no since-dates, no New/Continuing)" if TABLE_ROWS < 0 else "%d rows in its table" % TABLE_ROWS
              + ("" if TABLE_ROWS else " - the page as received is in %s" % (DATA / "weekly-report.html"))))
        for r in rows:
            print("  %-28s %-22s %-18s %-11s since %-14s first seen here %-9s %s%s" % (r["name"], r["country"], "%.2f, %.2f" % (r["lat"], r["lon"]) if r["lat"] is not None else "no coordinates",
                  r.get("status", ""), r["since"] or "?", "%.0f h ago" % r["first_hours"] if r.get("first_hours") is not None else "unknown",
                  "USGS %s/%s%s" % (r["level"], r["alert"], " raised %s" % ("%.0f h ago" % r["elevated_hours"] if r.get("elevated_hours") is not None else "? (unknown)")) if r.get("alert") else "",
                  "  CHANGED from %s %.0f h ago" % (r["changed_from"], r["changed_hours"]) if r.get("changed_from") else ""))
        if alerts_note:
            print("  " + alerts_note)
        if not placed:
            print("  tags seen in the feed:", dict(tags.most_common(25)))
    else:
        emit({"volcanoes": placed, "note": note})


def chk_volcanoes():
    rows, _tags, _url = fetch_volcanoes()
    placed = [r for r in rows if r["lat"] is not None]
    if rows and not placed:
        return "warn", "%d volcanoes listed, but no coordinates found in the feed - run: livemap-helper volcanoes --table" % len(rows)
    return "ok", "%d volcanoes in this week's report, %d with new activity" % (len(placed), sum(r["new"] for r in placed))
