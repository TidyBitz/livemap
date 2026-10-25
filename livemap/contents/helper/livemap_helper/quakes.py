"""Earthquakes: USGS's summary feed (the authority for M4.5+ worldwide, minutes after an event), with the
EMSC-CSEM real-time catalogue merged in for the smaller quakes outside the US that USGS lists late or not at all
(Europe, the Mediterranean, Latin America, Indonesia; the national networks EMSC collects). One list in USGS's
GeoJSON shape, cached five minutes, read by the quake layer and the widget alike."""
import json
import time
from datetime import datetime, timezone

from .common import DATA, _age, _http, haversine_km, fetch_json

USGS = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/%s.geojson"
EMSC = "https://www.seismicportal.eu/fdsnws/event/1/query?format=json&orderby=time&limit=600&minmag=%s&start=%s"
QUAKES = DATA / "quakes.json"
QUAKE_USGS, QUAKE_EMSC = 1, 2
# what the USGS feed names cover, for EMSC's query: (minimum magnitude, days back)
FEED_SPAN = {"2.5_day": (2.5, 1), "4.5_day": (4.5, 1), "significant_week": (6.0, 7), "all_day": (1.0, 1), "1.0_day": (1.0, 1), "2.5_week": (2.5, 7), "4.5_week": (4.5, 7)}
SAME_KM, SAME_SECONDS = 120, 90                   # the same quake in both catalogues: within this distance and time


def fetch_usgs(feed):
    body = fetch_json(USGS % feed, timeout=12)
    if "features" not in body:
        raise ValueError("not a USGS feed")
    for f in body["features"]:
        (f.setdefault("properties", {}))["source"] = "USGS"
    return body["features"]


def parse_emsc(body):
    """EMSC's FDSN event JSON -> USGS-shaped features (mag, place, time in ms, url, source)."""
    out = []
    for f in body.get("features") or []:
        p = f.get("properties") or {}
        c = (f.get("geometry") or {}).get("coordinates") or []
        try:
            lon, lat = float(p.get("lon", c[0])), float(p.get("lat", c[1]))
            t = datetime.strptime(str(p.get("time"))[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
            mag = float(p.get("mag"))
        except (TypeError, ValueError, IndexError):
            continue
        depth = p.get("depth")
        region = str(p.get("flynn_region") or "").title()
        uid = str(p.get("unid") or p.get("source_id") or f.get("id") or "")
        out.append({"type": "Feature", "id": "emsc" + uid,
                    "properties": {"mag": mag, "place": region, "time": int(t * 1000), "updated": int(t * 1000), "tsunami": 0, "magType": p.get("magtype"),
                                   "url": "https://www.seismicportal.eu/eventdetails.html?unid=" + uid, "source": "EMSC", "title": "M %.1f - %s" % (mag, region)},
                    "geometry": {"type": "Point", "coordinates": [lon, lat, float(depth) if depth is not None else 0]}})
    return out


def fetch_emsc(feed):
    minmag, days = FEED_SPAN.get(feed, (4.5, 1))
    start = datetime.fromtimestamp(time.time() - days * 86400, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    body = json.loads(_http(EMSC % (minmag, start), timeout=15)[2].decode("utf-8", "replace") or "{}")
    return parse_emsc(body)


def merge(usgs, emsc):
    """USGS's list plus the EMSC events that are not in it (the same quake is one within SAME_KM and SAME_SECONDS)."""
    out = list(usgs)
    for e in emsc:
        ec, et = e["geometry"]["coordinates"], e["properties"]["time"]
        dup = False
        for u in usgs:
            uc, ut = (u.get("geometry") or {}).get("coordinates") or [0, 0], (u.get("properties") or {}).get("time") or 0
            if abs(ut - et) <= SAME_SECONDS * 1000 and haversine_km(uc[1], uc[0], ec[1], ec[0]) <= SAME_KM:
                dup = True
                break
        if not dup:
            out.append(e)
    out.sort(key=lambda f: -((f.get("properties") or {}).get("time") or 0))
    return out


def quakes_cached(feed, sources=QUAKE_USGS | QUAKE_EMSC, max_age=300):
    """(features, problems): the merged list, from the cache while it is younger than max_age seconds."""
    now = time.time()
    try:
        c = json.loads(QUAKES.read_text(encoding="utf-8"))
        if c.get("feed") == feed and c.get("sources") == sources and now - c.get("at", 0) < max_age and c.get("features"):
            return c["features"], c.get("problems", [])
    except (OSError, ValueError):
        c = {}
    problems, usgs, emsc = [], None, []
    if sources & QUAKE_USGS:
        try:
            usgs = fetch_usgs(feed)
        except Exception as e:
            problems.append("quakes: USGS not answering (%s)" % e)
    if sources & QUAKE_EMSC:
        try:
            emsc = fetch_emsc(feed)
        except Exception as e:
            problems.append("quakes: EMSC not answering (%s)" % str(e)[:60])
    if usgs is None and not emsc:
        if c.get("features"):
            problems.append("quakes: showing the list from %s ago" % _age(now - c.get("at", now)))
            return c["features"], problems
        raise RuntimeError("; ".join(problems) or "no earthquake source answered")
    features = merge(usgs or [f for f in c.get("features", []) if (f.get("properties") or {}).get("source") == "USGS"], emsc)
    try:
        QUAKES.parent.mkdir(parents=True, exist_ok=True)
        tmp = QUAKES.with_suffix(".tmp")
        tmp.write_text(json.dumps({"feed": feed, "sources": sources, "at": now, "features": features, "problems": problems}, separators=(",", ":")), encoding="utf-8")
        tmp.replace(QUAKES)
    except OSError:
        pass
    return features, problems


def cmd_quakes(args):
    from .common import emit
    try:
        features, problems = quakes_cached(args.feed, args.sources, args.max_age)
    except Exception as e:
        emit({"features": [], "problems": [str(e)], "note": "Earthquakes: %s" % e})
        return
    if args.table:
        print("%d earthquakes (%s; sources %d)%s" % (len(features), args.feed, args.sources, "; " + "; ".join(problems) if problems else ""))
        for f in features[:40]:
            p, c = f["properties"], f["geometry"]["coordinates"]
            print("  M%.1f %-5s %-40s %7.2f %8.2f  %s" % (p.get("mag") or 0, p.get("source", ""), (p.get("place") or "")[:40], c[1], c[0], _age(time.time() - p["time"] / 1000)))
    else:
        emit({"features": features, "problems": problems, "note": problems[0] if problems else ""})


def chk_emsc():
    emsc = fetch_emsc("4.5_day")
    return "ok", "%d events M4.5+ in the last day in EMSC's catalogue%s" % (len(emsc), "; newest M%.1f %s" % (emsc[0]["properties"]["mag"], emsc[0]["properties"]["place"]) if emsc else "")
