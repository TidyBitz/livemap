"""Volcanic Ash Advisories from the Washington VAAC (NOAA OSPO): the fastest public sign that a volcano in the
Americas and the eastern Pacific is erupting - an advisory within the hour, every six hours while the ash
continues - with the ash cloud's outline and height. The index page lists the advisories of the past 24 hours;
each is an IWXXM XML with the volcano, its position, the issue time, the observed ash polygon and the forecast
ones. Advisories are fetched once by file name and remembered (vaac.json) for a day. Public domain (US government).
The other eight VAACs (Toulouse, London, Tokyo, Darwin, Anchorage, Wellington, Buenos Aires, Montreal) have no
comparable index; they are not read."""
import json
import re
import time
from datetime import datetime, timezone

from .common import DATA, _http, safe_xml

VAAC_INDEX = "https://www.ospo.noaa.gov/products/atmosphere/vaac/messages.html"
VAAC_XML = "https://www.ospo.noaa.gov/products/atmosphere/vaac/volcanoes/xml_files/%s.xml"
VAAC_STATE = DATA / "vaac.json"
VAAC_KEEP_HOURS = 24
VAAC_PER_RUN = 12                                 # new advisories read per refresh
INDEX_XML_RE = re.compile(r"xml_files/(FVXX\d{2}_\d{8}_\d{4})\.xml", re.I)


def parse_vaac_index(html):
    """The advisory file names on the index page, newest first, each once."""
    seen, out = set(), []
    for m in INDEX_XML_RE.finditer(html):
        name = m.group(1).upper()
        if name not in seen:
            seen.add(name)
            out.append(name)
    return out


def _local(el):
    return el.tag.rsplit("}", 1)[-1]


def parse_vaac_xml(xml_text, file_name=""):
    """One advisory -> {name, number, lat, lon, country, issued, advisory, top_fl, details, observed [rings],
    forecast [rings], remarks, next, file} or None."""
    import xml.etree.ElementTree as ET
    root = ET.fromstring(safe_xml(xml_text))
    rec = {"file": file_name, "observed": [], "forecast": [], "top_fl": None, "details": "", "remarks": "", "next": "", "country": "", "advisory": ""}
    in_forecast = False
    for el in root.iter():
        tag = _local(el)
        text = (el.text or "").strip()
        if tag == "issueTime" and "issued" not in rec:
            when = text or next((((c.text or "").strip()) for c in el.iter() if _local(c) == "timePosition"), "")
            try:
                rec["issued"] = datetime.strptime(when[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
            except ValueError:
                pass
        elif tag == "name" and "name" not in rec and text:
            m = re.match(r"\s*(.+?)\s+(\d{6,7})\s*$", text)                  # "REVENTADOR 352010"
            rec["name"], rec["number"] = (m.group(1), m.group(2)) if m else (text, "")
            rec["name"] = rec["name"].title()
        elif tag == "pos" and "lat" not in rec and text:
            try:
                lat, lon = (float(x) for x in text.split()[:2])
                rec["lat"], rec["lon"] = lat, lon
            except ValueError:
                pass
        elif tag == "stateOrRegion" and text:
            rec["country"] = text.title()
        elif tag == "advisoryNumber" and text:
            rec["advisory"] = text
        elif tag == "eruptionDetails" and text:
            rec["details"] = text
        elif tag == "remarks" and text:
            rec["remarks"] = " ".join(text.split())[:300]
        elif tag == "nextAdvisoryTime":
            rec["next"] = text or next((((c.text or "").strip()) for c in el.iter() if _local(c) == "timePosition"), "")
        elif tag == "VolcanicAshForecastConditions":
            in_forecast = True
        elif tag == "VolcanicAshObservedOrEstimatedConditions":
            in_forecast = False
        elif tag == "upperLimit" and text and not in_forecast:
            try:
                rec["top_fl"] = max(rec["top_fl"] or 0, int(re.sub(r"\D", "", text) or 0))
            except ValueError:
                pass
        elif tag == "posList" and text:
            nums = [float(x) for x in text.split()]
            ring = []
            for i in range(0, len(nums) - 1, 2):
                ring += [round(nums[i + 1], 2), round(nums[i], 2)]        # lat lon -> lon lat
            if len(ring) >= 8:
                (rec["forecast"] if in_forecast else rec["observed"]).append(ring)
    if "name" not in rec or "lat" not in rec or "issued" not in rec:
        return None
    return rec


def fetch_vaac():
    """Read the index, fetch the advisories not yet seen, fold them into the memory, return the live ones."""
    now = time.time()
    try:
        state = json.loads(VAAC_STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        state = {}
    seen = state.get("advisories") or {}
    html = _http(VAAC_INDEX, timeout=15)[2].decode("utf-8", "replace")
    names = parse_vaac_index(html)
    failed, fetched = [], 0
    for name in names:
        if name in seen or fetched >= VAAC_PER_RUN:
            continue
        fetched += 1
        try:
            rec = parse_vaac_xml(_http(VAAC_XML % name, timeout=12)[2].decode("utf-8", "replace"), name)
            seen[name] = rec or {"file": name, "unreadable": True, "issued": now}
        except Exception as e:
            failed.append("%s: %s" % (name, str(e)[:40]))
    cutoff = now - VAAC_KEEP_HOURS * 3600
    seen = {k: v for k, v in seen.items() if (v.get("issued") or 0) >= cutoff}
    try:
        VAAC_STATE.parent.mkdir(parents=True, exist_ok=True)
        tmp = VAAC_STATE.with_suffix(".tmp")
        tmp.write_text(json.dumps({"advisories": seen, "read": now}, separators=(",", ":")), encoding="utf-8")
        tmp.replace(VAAC_STATE)
    except OSError:
        pass
    # one record per volcano: its latest advisory, with how many it had in the day
    latest = {}
    for v in seen.values():
        if v.get("unreadable"):
            continue
        key = v["name"]
        if key not in latest or v["issued"] > latest[key]["issued"]:
            latest[key] = dict(v, count=0)
    for v in seen.values():
        if not v.get("unreadable"):
            latest[v["name"]]["count"] += 1
    out = sorted(latest.values(), key=lambda v: -v["issued"])
    for v in out:
        v["hours"] = round((now - v["issued"]) / 3600, 2)
    return {"advisories": out, "failed": failed}


def vaac_cached(max_age_min=20):
    from .common import last_good
    f = DATA / "last-vaac.json"
    try:
        c = json.loads(f.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_min * 60:
            return c["data"], 0.0, ""
    except (OSError, ValueError, KeyError):
        pass
    return last_good("vaac", fetch_vaac)


def merge_vaac(rows, advisories):
    """Attach the latest advisory to the weekly report's volcano of the same name, or add the volcano: an ash
    advisory is an eruption in progress, whatever the weekly report says."""
    from .common import _plain
    by_name = {_plain(r["name"]): r for r in rows}
    for a in advisories:
        key = _plain(a["name"])
        r = by_name.get(key) or next((by_name[k] for k in by_name if k.startswith(key) or key.startswith(k)), None)
        if r is None:
            r = {"name": a["name"], "country": a.get("country", ""), "lat": a["lat"], "lon": a["lon"], "new": a["hours"] < 6,
                 "reported": int(a["issued"]), "since": "", "status": "ash advisory"}
            rows.append(r)
            by_name[key] = r
        r.update(ash_hours=a["hours"], ash_top_fl=a.get("top_fl"), ash_count=a.get("count", 1), ash_rings=a.get("observed", [])[:4],
                 ash_forecast=a.get("forecast", [])[:4], ash_advisory=a.get("advisory", ""), ash_details=a.get("details", ""))
        if r.get("alert") is None and a["hours"] < 12:
            r["ash"] = True
    return rows


def chk_vaac():
    d = fetch_vaac()
    names = ", ".join("%s (%s, FL%s)" % (a["name"], "%d adv." % a["count"], a.get("top_fl") or "?") for a in d["advisories"][:6])
    return ("warn" if d["failed"] else "ok"), "%d volcanoes with ash advisories in the last 24 h (Washington VAAC)%s%s" % (
        len(d["advisories"]), ": " + names if names else "", "; failed: " + "; ".join(d["failed"][:2]) if d["failed"] else "")
