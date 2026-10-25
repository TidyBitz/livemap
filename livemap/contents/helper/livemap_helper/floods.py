"""Floods: GDACS events and NWS flood alerts."""
import json
import re
import urllib.error
import urllib.request

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, MAX_BODY, NWS_UA, VERSION, _http, _nws_get, _split, emit, last_good, remember_events, \
    stale_note, fetch_json
from .storms import gdacs_list


# ---------------------------------------------------------------- floods ----
# Floods from the same GDACS list (eventtype FL): one event per river basin or region, rated green / orange / red on
# the people exposed, with the dates. For the orange and red ones (what the map shows by default) two more small
# requests: the event data, whose "sendai" entries say what happened to people (deaths, displaced, evacuated,
# rescued), and the geometry, whose polygons are the affected area, drawn as a faint fill under the mark.
SENDAI_ORDER = ("death", "dead", "killed", "missing", "injured", "evacuated", "displaced", "homeless", "affected", "rescued")


FLOOD_POLY_POINTS = 160                          # per ring, after thinning; the fill is a hint, not a survey


def _sendai_summary(details):
    """'3 dead, 1 200 evacuated' from the event data's sendai entries: the latest figure per kind, worst first."""
    best = {}
    for e in (details.get("properties") or {}).get("sendai") or []:
        name = str(e.get("sendainame") or "").lower().strip()
        try:
            v = int(float(str(e.get("sendaivalue") or "0").replace(",", "")))
        except ValueError:
            continue
        if not name or v <= 0:
            continue
        if e.get("latest") or name not in best or v > best[name]:
            best[name] = max(v, best.get(name, 0)) if not e.get("latest") else v
    rank = {k: i for i, k in enumerate(SENDAI_ORDER)}
    parts = sorted(best.items(), key=lambda kv: (rank.get(kv[0], 99), -kv[1]))
    return [[k, v] for k, v in parts[:3]]


def _thin(ring, keep):
    if len(ring) <= keep:
        return ring
    step = len(ring) / float(keep)
    return [ring[int(i * step)] for i in range(keep)] + [ring[-1]]


def flood_area(geo):
    """The affected-area polygons of a GDACS flood geometry, thinned, as flat [lon, lat, ...] rings."""
    rings = []
    for f in geo.get("features", []):
        g, pr = f.get("geometry") or {}, f.get("properties") or {}
        kind, c = g.get("type"), g.get("coordinates") or []
        if kind == "Polygon":
            polys = [c]
        elif kind == "MultiPolygon":
            polys = c
        else:
            continue
        for poly in polys:
            if not poly:
                continue
            ring = [(x[0], x[1]) for x in poly[0]]
            if len(ring) < 4:
                continue
            for part in _split(_thin(ring, FLOOD_POLY_POINTS)):
                rings.append(part)
    rings.sort(key=lambda r: -len(r))
    return rings[:12]


def fetch_floods(detail_levels=("orange", "red")):
    import time
    from datetime import datetime
    body = json.dumps(gdacs_list()).encode()
    now, floods, seen = time.time(), [], set()
    for f in json.loads(body).get("features", []):
        pr = f.get("properties") or {}
        if pr.get("eventtype") != "FL" or str(pr.get("iscurrent", "true")).lower() != "true":
            continue
        fid = pr.get("eventid")
        if fid in seen:
            continue
        seen.add(fid)
        lon, lat = (f.get("geometry") or {}).get("coordinates", [0, 0])[:2]
        hours, since, days = None, "", None
        try:
            hours = round((now - datetime.strptime(str(pr.get("datemodified") or pr.get("todate"))[:19], "%Y-%m-%dT%H:%M:%S").timestamp()) / 3600, 1)
        except (ValueError, TypeError):
            pass
        try:
            start = datetime.strptime(str(pr.get("fromdate"))[:19], "%Y-%m-%dT%H:%M:%S")
            since = start.strftime("%Y %b %d")
            days = max(0, round((now - start.timestamp()) / 86400, 1))
        except (ValueError, TypeError):
            pass
        name = re.sub(r"^floods? in ", "", str(pr.get("name") or pr.get("description") or ""), flags=re.I).strip() or pr.get("country") or "Flood"
        countries = [c.get("countryname") for c in pr.get("affectedcountries") or [] if c.get("countryname")]
        fl = {"id": fid, "episode": pr.get("episodeid"), "name": name, "country": pr.get("country", ""), "countries": countries[:4],
              "lat": lat, "lon": lon, "alert": str(pr.get("alertlevel") or "green").lower(), "score": pr.get("alertscore"),
              "since": since, "days": days, "hours": hours, "people": [], "area": []}
        if fl["alert"] in detail_levels:
            urls = pr.get("url") or {}
            try:
                fl["people"] = _sendai_summary(fetch_json(urls.get("details"), timeout=12))
            except Exception as e:
                fl["problem"] = "details: %s" % e
            try:
                fl["area"] = flood_area(fetch_json(urls.get("geometry"), timeout=15, limit=MAX_BODY))
            except Exception as e:
                fl["problem"] = "geometry: %s" % e
        floods.append(fl)
    return floods


def people_text(people):
    return ", ".join("%s %s" % (format(v, ",").replace(",", " "), k) for k, v in people)


def cmd_floods(args):
    note, floods = "", []
    levels = ("green", "orange", "red") if args.all else ("orange", "red")
    data, stale_h, err = last_good("floods", lambda: fetch_floods(levels))
    if err:
        note = stale_note("Floods", stale_h, err, args.stale)
    try:
        floods = remember_events("flood", data or [], lambda fl: fl["id"], args.keep, sig_of=lambda fl: fl["alert"])
    except Exception as e:
        note = note or "Floods: %s" % e
    if args.table:
        print(note or "%d current flood events (GDACS)" % len(floods))
        for fl in sorted(floods, key=lambda fl: ("green", "orange", "red").index(fl["alert"]) if fl["alert"] in ("green", "orange", "red") else -1, reverse=True):
            print("  %-30s %-7s at %6.1f, %6.1f  since %s (%s d)  %s  %d rings  first seen %s%s%s" % (
                fl["name"][:30], fl["alert"], fl["lat"], fl["lon"], fl["since"] or "?", fl["days"], people_text(fl["people"]) or "-", len(fl["area"]),
                "%.0f h ago" % fl["first_hours"] if fl.get("first_hours") is not None else "unknown",
                "  CHANGED from %s %.0f h ago" % (fl["changed_from"], fl["changed_hours"]) if fl.get("changed_from") else "",
                "  GONE (%.0f h ago)" % fl["hours"] if fl.get("gone") else ""))
    else:
        emit({"floods": floods, "note": note})


def chk_floods():
    floods = fetch_floods(())
    hot = [fl for fl in floods if fl["alert"] in ("orange", "red")]
    return "ok", "%d current flood events, %d orange or red%s" % (
        len(floods), len(hot), ": " + ", ".join("%s (%s)" % (fl["name"], fl["alert"]) for fl in hot[:6]) if hot else "")


# US flood alerts from the National Weather Service (api.weather.gov, no key, a user agent with a contact is asked
# for): flash flood warnings, flood warnings, watches and advisories, each with the counties it covers, when it
# ends, and a polygon - the warning's own for a storm-based flash flood warning, otherwise the forecast zones
# or counties it names, fetched once each and kept (zones do not change). Minutes after issue, unlike GDACS.
NWS_ALERTS = "https://api.weather.gov/alerts/active?status=actual&event=" + urllib.request.quote(
    "Flash Flood Warning,Flood Warning,Flood Watch,Flash Flood Watch,Flood Advisory,Coastal Flood Warning")


NWS_ZONES = DATA / "nws-zones"


NWS_UA["User-Agent"] = "livemap-wallpaper/" + VERSION + " (github.com/TidyBitz/livemap)"


NWS_LEVEL = {"Flash Flood Warning": "red", "Flood Warning": "orange", "Coastal Flood Warning": "orange",
             "Flood Watch": "green", "Flash Flood Watch": "green", "Flood Advisory": "green"}


NWS_ZONES_PER_RUN = 40                           # new zone polygons fetched per refresh; the rest come next time (cached for good)


def _nws_epoch(text):
    from datetime import datetime
    try:
        return datetime.fromisoformat(str(text)).timestamp()
    except (ValueError, TypeError):
        return None


def nws_zone_rings(zone_url, budget):
    """The polygon of one forecast zone or county, from the cache or the API (counting against `budget`)."""
    zid = zone_url.rstrip("/").split("/")[-1]
    f = NWS_ZONES / (re.sub(r"[^A-Za-z0-9]", "", zid) + ".json")
    try:
        return json.loads(f.read_text(encoding="utf-8")), False
    except (OSError, ValueError):
        pass
    if budget[0] <= 0:
        return [], False
    budget[0] -= 1
    geo = _nws_get(zone_url)
    rings = flood_area({"features": [geo]})
    NWS_ZONES.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(rings), encoding="utf-8")
    return rings, True


def _ring_centre(rings):
    n, sx, sy = 0, 0.0, 0.0
    for r in rings:
        for i in range(0, len(r) - 1, 2):
            sx += r[i]; sy += r[i + 1]; n += 1
    return (sy / n, sx / n) if n else (None, None)


def fetch_nws_floods():
    import time
    now = time.time()
    data = _nws_get(NWS_ALERTS, timeout=20)
    out, budget, seen = [], [NWS_ZONES_PER_RUN], set()
    for f in data.get("features", []):
        pr = f.get("properties") or {}
        event = pr.get("event") or ""
        level = NWS_LEVEL.get(event)
        if not level or pr.get("status") not in (None, "Actual"):
            continue
        ends = _nws_epoch(pr.get("ends") or pr.get("expires"))
        if ends is not None and ends < now:
            continue
        aid = pr.get("id") or f.get("id")
        if aid in seen:
            continue
        seen.add(aid)
        rings, fetched = [], 0
        g = f.get("geometry")
        if g and g.get("type") in ("Polygon", "MultiPolygon"):
            rings = flood_area({"features": [f]})
        else:
            for z in (pr.get("affectedZones") or [])[:24]:
                try:
                    r, was_fetched = nws_zone_rings(z, budget)
                    rings += r
                    fetched += was_fetched
                except Exception:
                    pass
            rings = rings[:12]
        lat, lon = _ring_centre(rings)
        if lat is None:
            continue                               # nothing to place it by yet (zones still to fetch): next time
        counties = [c.strip() for c in str(pr.get("areaDesc") or "").split(";") if c.strip()]
        onset = _nws_epoch(pr.get("onset") or pr.get("effective") or pr.get("sent"))
        out.append({"id": "nws:" + str(aid).split("/")[-1], "source": "nws", "event": event, "name": "; ".join(counties[:3]) + (", +%d" % (len(counties) - 3) if len(counties) > 3 else ""),
                    "counties": len(counties), "places": counties[:60], "office": str(pr.get("senderName") or "").replace("NWS ", ""), "lat": round(lat, 3), "lon": round(lon, 3),
                    "alert": level, "severity": pr.get("severity"), "since": "", "days": None, "hours": 0,
                    "onset": onset, "until": ends, "headline": pr.get("headline") or "", "url": "https://alerts.weather.gov/search?id=" + str(aid).split("/")[-1],
                    "people": [], "area": rings})
    return out


def group_nws(alerts):
    """One item per office and alert type: a wet week brings an office to issue a flood warning per river gauge,
    and 28 marks and labels in one state say less than 'Flood Warning · 9 counties · Greenville-Spartanburg'."""
    groups = {}
    for a in alerts:
        k = (a["office"], a["event"])
        g = groups.get(k)
        if g is None:
            g = groups[k] = dict(a, members=[], area=[], counties_list=[], lats=[], lons=[], counties=0, places=[])
            g["id"] = "nws:" + re.sub(r"[^A-Za-z0-9]+", "-", a["office"] + "-" + a["event"]).strip("-").lower()
        g["members"].append(a["id"])
        g["counties"] += a.get("counties") or 0
        g["area"] = (g["area"] + a["area"])[:24]
        g["counties_list"] += [c.strip() for c in a["name"].replace(", +", ";+").split(";") if c.strip() and not c.strip().startswith("+")]
        g["places"] += [c for c in (a.get("places") or []) if c not in g["places"]]
        g["lats"].append(a["lat"]); g["lons"].append(a["lon"])
        if a.get("until") and (not g.get("until") or a["until"] > g["until"]):
            g["until"] = a["until"]
        if a.get("onset") and (not g.get("onset") or a["onset"] < g["onset"]):
            g["onset"] = a["onset"]
        if a.get("first_hours") is not None and (g.get("first_hours") is None or a["first_hours"] < g["first_hours"]):
            g["first_hours"] = a["first_hours"]
    out = []
    for g in groups.values():
        n = len(g["members"])
        seen, counties = set(), []
        for c in g["counties_list"]:
            if c not in seen:
                seen.add(c); counties.append(c)
        g["lat"] = round(sum(g["lats"]) / len(g["lats"]), 3); g["lon"] = round(sum(g["lons"]) / len(g["lons"]), 3)
        g["count"] = n
        g["counties"] = max(len(counties), g["counties"], len(g["places"]))   # the sum of the alerts' counts, or the named ones
        if len(g["places"]) < len(counties):
            g["places"] = counties
        g["name"] = ("%d counties" % g["counties"] if g["counties"] > 2 else "; ".join(counties)) + (" \u00b7 " + g["office"] if g["office"] else "")
        g["url"] = ("https://alerts.weather.gov/search?area=" + urllib.request.quote(g["office"])) if n > 1 and g.get("source") in (None, "nws") else g["url"]
        for k in ("members", "counties_list", "lats", "lons"):
            g.pop(k, None)
        out.append(g)
    return out


def nws_floods_cached(max_age_min=10):
    """The NWS alerts, refreshed when the cache is older than max_age_min; (data, stale_hours, error)."""
    import time
    f = DATA / "last-nws-floods.json"
    try:
        c = json.loads(f.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_min * 60:
            return c["data"], 0.0, ""
    except (OSError, ValueError, KeyError):
        pass
    return last_good("nws-floods", fetch_nws_floods)


def official_floods(mask, max_age_min=10, stale_limit=6):
    """Every official flood warning source in the mask (1 NWS, 2 MeteoAlarm, 4 ECCC, 8 EA): (alerts, note)."""
    from .warnings import warnings_cached
    alerts, notes = [], []
    nws_note = ""
    if mask & 1:
        data, stale_h, err = nws_floods_cached(max_age_min)
        if err:
            nws_note = stale_note("US flood alerts", stale_h, err, stale_limit)
        alerts += data or []
    if mask & ~1:
        more, more_notes = warnings_cached(mask)
        alerts += more
        if nws_note and not more:
            notes.append(nws_note)                         # NWS down and nothing else answering either
    elif nws_note:
        notes.append(nws_note)                             # NWS is the only official source asked
        # a secondary source that fails (MeteoAlarm's Malta, ECCC answering with something that is not JSON) is a
        # Status matter - the settings' Status page and the widget's Status tab show it per source - not a corner
        # notice on the desktop for days. The desktop hears of it only when every official source is out.
        if more_notes and not more and not (mask & 1 and alerts):
            notes.append("Flood warnings: no official source answering (" + "; ".join(more_notes)[:120] + ")")
    return alerts, "; ".join(n for n in notes if n)


def cmd_nws_floods(args):
    note, alerts = "", []
    data, note = official_floods(args.sources, args.max_age, args.stale)
    try:
        alerts = remember_events("nwsflood", data or [], lambda a: a["id"], 0.5, sig_of=lambda a: a["alert"])
        alerts = [a for a in alerts if not a.get("gone")]       # an alert that ended is simply gone: no ageing out
        if not args.each:
            alerts = group_nws(alerts)
    except Exception as e:
        note = note or "US flood alerts: %s" % e
    if args.table:
        import time
        print(note or "%d active official flood alerts (sources %d)" % (len(alerts), args.sources))
        for a in sorted(alerts, key=lambda a: ("green", "orange", "red").index(a["alert"]), reverse=True):
            print("  %-22s %-7s %-44s %s  until %s  %d rings  first seen %s" % (
                a["event"][:22], a["alert"], a["name"][:44], "" if not args.each else a["office"][:18],
                time.strftime("%a %H:%M", time.localtime(a["until"])) if a.get("until") else "?", len(a["area"]),
                "%.1f h ago" % a["first_hours"] if a.get("first_hours") is not None else "unknown"))
    else:
        emit({"alerts": alerts, "note": note})


def chk_nws_floods():
    alerts = fetch_nws_floods()
    warn = [a for a in alerts if a["alert"] in ("orange", "red")]
    return "ok", "%d active flood alerts, %d warnings%s" % (
        len(alerts), len(warn), ": " + ", ".join("%s (%s)" % (a["name"].split(";")[0], a["event"].replace(" Warning", "")) for a in warn[:5]) if warn else "")
