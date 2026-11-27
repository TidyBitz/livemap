"""Wildfires: GDACS events, NASA FIRMS hotspots, NIFC / CWFIS / EFFIS incidents."""
import json
import os
import re
import time
import urllib.error
import urllib.request

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, MAX_BODY, UA, _places_index, emit, haversine_km, last_good, remember_events, \
    stale_note, fetch_json
from .floods import _ring_centre, flood_area
from .storms import gdacs_list


# ------------------------------------------------------------ wildfires -----
def fetch_fires():
    """Current wildfires from the same GDACS list as the storms (eventtype WF): one point per fire event with
    GDACS's alert level (Green / Orange / Red), the burned area in hectares and the dates."""
    import time
    from datetime import datetime
    body = json.dumps(gdacs_list()).encode()
    now, fires, seen = time.time(), [], set()
    for f in json.loads(body).get("features", []):
        pr = f.get("properties") or {}
        if pr.get("eventtype") != "WF" or str(pr.get("iscurrent", "true")).lower() != "true":
            continue
        lon, lat = (f.get("geometry") or {}).get("coordinates", [0, 0])[:2]
        sev = pr.get("severitydata") or {}
        hours, since = None, ""
        try:
            hours = round((now - datetime.strptime(str(pr.get("datemodified") or pr.get("todate"))[:19], "%Y-%m-%dT%H:%M:%S").timestamp()) / 3600, 1)
        except (ValueError, TypeError):
            pass
        try:
            since = datetime.strptime(str(pr.get("fromdate"))[:10], "%Y-%m-%d").strftime("%Y %b %d")
        except (ValueError, TypeError):
            pass
        name = re.sub(r"^(forest )?fires? in ", "", str(pr.get("name") or pr.get("description") or ""), flags=re.I).strip() or pr.get("country") or "Wildfire"
        fid = pr.get("eventid")
        if fid in seen:
            continue
        seen.add(fid)
        fires.append({"id": fid, "name": name, "country": pr.get("country", ""), "lat": lat, "lon": lon,
                      "alert": str(pr.get("alertlevel") or "green").lower(), "area_ha": round(float(sev.get("severity") or 0)),
                      "since": since, "hours": hours})
    return fires


def cmd_fires(args):
    note, fires = "", []
    data, stale_h, err = last_good("fires", fetch_fires)
    if err:
        note = stale_note("Wildfires", stale_h, err, args.stale)
    try:
        fires = remember_events("fire", data or [], lambda fr: fr["id"], args.keep, sig_of=lambda fr: fr["alert"])
    except Exception as e:
        note = note or "Wildfires: %s" % e
    if args.table:
        print(note or "%d current wildfire events (GDACS)" % len(fires))
        for fr in sorted(fires, key=lambda fr: -fr["area_ha"]):
            print("  %-34s %-7s %8d ha  at %.1f, %.1f  since %s  first seen %s%s%s" % (
                fr["name"][:34], fr["alert"], fr["area_ha"], fr["lat"], fr["lon"], fr["since"] or "?",
                "%.0f h ago" % fr["first_hours"] if fr.get("first_hours") is not None else "unknown",
                "  CHANGED from %s %.0f h ago" % (fr["changed_from"], fr["changed_hours"]) if fr.get("changed_from") else "",
                "  GONE (%.0f h ago)" % fr["hours"] if fr.get("gone") else ""))
    else:
        emit({"fires": fires, "note": note})


# NASA FIRMS: the world's active-fire detections of the last 24 hours as one CSV, no key for the 24 h files.
# VIIRS on NOAA-21 (375 m, NOAA's primary) first, NOAA-20 second; MODIS on Terra/Aqua last - Suomi NPP's delivery
# ends on 2 November 2026 and MODIS collection in 2027, so the list is the order of preference and each file is
# tried on both FIRMS hosts (NASA has moved between them to get around delivery delays).
FIRMS_FILES = ["noaa-21-viirs-c2/csv/J2_VIIRS_C2_Global_24h.csv", "noaa-20-viirs-c2/csv/J1_VIIRS_C2_Global_24h.csv", "modis-c6.1/csv/MODIS_C6_1_Global_24h.csv"]


FIRMS_HOSTS = ["https://firms.modaps.eosdis.nasa.gov/data/active_fire/", "https://firms2.modaps.eosdis.nasa.gov/data/active_fire/"]


FIRMS = FIRMS_HOSTS[0] + FIRMS_FILES[2]          # the legacy name, kept for the status page


HOTSPOT_SOURCE = DATA / "hotspots-source.txt"     # which file the current hotspots.csv came from


HOTSPOTS = DATA / "hotspots.csv"


HOTSPOT_MEMORY = DATA / "hotspot-days.json"    # per half-degree cell: which of the last 30 days it burned, and how hard


def _nearest_place(idx, lat, lon, within_km=50):
    best = None
    bi, bj = int(lat // 1), int(lon // 1)
    for i in (bi - 1, bi, bi + 1):
        for j in (bj - 1, bj, bj + 1):
            for plat, plon, pop, name in idx.get((i, j), ()):
                km = haversine_km(lat, lon, plat, plon)
                if km <= within_km and (best is None or km < best[0]):
                    best = (km, pop, name)
    return best


def rate_hotspots(cells, fires=None, now=None):
    """Which satellite fire clusters deserve attention. Adds to each cell: tier (2 attention, 1 notable,
    0 background), why (a short reason), days (how many of the last 7 it burned), chronic, near (a city).

    Attention: on a GDACS orange/red event; or near a city of 100k+ with real power; or burning for days without
    being a chronic (field / savanna) cell; or very large and not chronic; or a chronic cell flaring well above
    its own month. Notable: the old threshold (25+ detections or 1 GW), a smaller fire near a town, or on a
    GDACS green event. Everything else is the daily background of agricultural burning."""
    import time
    from datetime import datetime, timezone
    now = now or time.time()
    today = datetime.fromtimestamp(now, timezone.utc).strftime("%Y%m%d")
    try:
        mem = json.loads(HOTSPOT_MEMORY.read_text(encoding="utf-8"))
        if not isinstance(mem, dict):
            mem = {}
    except (OSError, ValueError):
        mem = {}
    cutoff = datetime.fromtimestamp(now - 30 * 86400, timezone.utc).strftime("%Y%m%d")
    recent = datetime.fromtimestamp(now - 7 * 86400, timezone.utc).strftime("%Y%m%d")
    places = _places_index()
    seen_days = set()
    for e in mem.values():
        if isinstance(e, dict):
            seen_days.update(d for d in e.get("days", []) if d >= cutoff)
    observed = len(seen_days | {today})                      # how many distinct days this machine has looked, within the month
    # Regional burning (a savanna or harvest season) comes as a carpet of burning cells; a wildfire is isolated.
    # This is known on the first day, before any history exists.
    burning = {(int(c["lat"] // 0.5), int(c["lon"] // 0.5)) for c in cells}
    def neighbours(c):
        i, j = int(c["lat"] // 0.5), int(c["lon"] // 0.5)
        return sum(1 for di in range(-3, 4) for dj in range(-3, 4) if (di or dj) and (i + di, j + dj) in burning)
    for c in cells:
        key = "%d,%d" % (int(c["lat"] // 0.5), int(c["lon"] // 0.5))
        e = mem.get(key)
        if not isinstance(e, dict):
            e = mem[key] = {"days": [], "frp": []}
        if today not in e["days"]:
            e["days"].append(today); e["frp"].append(c["frp"])
        else:
            e["frp"][-1] = max(e["frp"][-1], c["frp"])
        keep = [i for i, d in enumerate(e["days"]) if d >= cutoff]
        e["days"], e["frp"] = [e["days"][i] for i in keep], [e["frp"][i] for i in keep]
        days7 = min(7, sum(1 for d in e["days"] if d >= recent))
        month = len(e["days"])
        avg = sum(e["frp"][:-1]) / max(1, len(e["frp"]) - 1) if len(e["frp"]) > 1 else 0
        regional = neighbours(c) >= 10                       # 10+ of the 48 surrounding half-degree cells also burning
        chronic = regional or (observed >= 14 and month >= 12)   # or burning most days once there is a fortnight to judge by
        flare = chronic and avg > 0 and c["frp"] >= 4 * avg
        near = _nearest_place(places, c["lat"], c["lon"]) if places else None
        on_event = None
        for fr in fires or []:
            if haversine_km(c["lat"], c["lon"], fr["lat"], fr["lon"]) <= 75:
                if on_event is None or {"red": 3, "orange": 2}.get(fr["alert"], 1) > {"red": 3, "orange": 2}.get(on_event["alert"], 1):
                    on_event = fr
        why = []
        tier = 0
        if on_event and on_event["alert"] in ("orange", "red"):
            tier = 2; why.append("%s (GDACS %s)" % (on_event["name"], on_event["alert"]))
        elif near and near[1] >= 100000 and c["frp"] >= (2000 if regional else 300):    # in a burning season a city needs more
            tier = 2; why.append("%d km from %s" % (round(near[0]), near[2]))
        elif days7 >= 3 and c["frp"] >= 2000 and not chronic:
            tier = 2; why.append("%d days running" % days7)
        elif c["frp"] >= 10000 and not chronic:
            tier = 2; why.append("very large")
        elif flare and c["frp"] >= 5000:
            tier = 2; why.append("flaring %dx its month" % round(c["frp"] / avg))
        elif c["n"] >= 25 or c["frp"] >= 1000 or (near and c["frp"] >= 100) or on_event:
            tier = 1
            if on_event: why.append(on_event["name"])
            elif near: why.append("%d km from %s" % (round(near[0]), near[2]))
            if chronic: why.append("regional burning" if regional else "burns most days")
        if days7 >= 2 and "days running" not in " ".join(why):
            why.append("%d d" % days7)
        # "near people": on a GDACS orange or red event (rated on the people exposed), or within 50 km of a city
        # of 100 000 or more - the fires that can mean evacuations, as opposed to the savanna burning season
        people = bool(on_event and on_event["alert"] in ("orange", "red")) or bool(near and near[1] >= 100000 and near[0] <= 50)
        c.update(tier=tier, why=" \u00b7 ".join(why), days=days7, chronic=chronic, near=near[2] if near else "",
                 event=on_event["id"] if on_event else None, people=people)
    stale = [k for k, e in mem.items() if not isinstance(e, dict) or not e.get("days") or e["days"][-1] < cutoff]
    for k in stale:
        mem.pop(k, None)
    try:
        HOTSPOT_MEMORY.parent.mkdir(parents=True, exist_ok=True)
        tmp = HOTSPOT_MEMORY.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps(mem, separators=(",", ":")), encoding="utf-8")
        tmp.replace(HOTSPOT_MEMORY)
    except OSError:
        pass
    return cells


def fetch_hotspots(max_age_h=3):
    """NASA FIRMS active fire detections (VIIRS NOAA-21, else NOAA-20, else MODIS; last 24 h; no key; a few to
    twenty MB), cached for three hours. Returns the CSV text; the source file's name is kept beside it."""
    import time
    if not HOTSPOTS.exists() or time.time() - HOTSPOTS.stat().st_mtime > max_age_h * 3600:
        errors = []
        for name in FIRMS_FILES:
            for host in FIRMS_HOSTS:
                try:
                    req = urllib.request.Request(host + name, headers=UA)
                    tmp = HOTSPOTS.with_suffix(".part")
                    HOTSPOTS.parent.mkdir(parents=True, exist_ok=True)
                    with urllib.request.urlopen(req, timeout=90) as r, open(tmp, "wb") as f:
                        data = r.read(MAX_BODY + 1)
                        if len(data) > MAX_BODY:
                            raise ValueError("FIRMS file larger than expected")
                        if b"latitude" not in data[:200]:
                            raise ValueError("not a FIRMS CSV")
                        f.write(data)
                    tmp.replace(HOTSPOTS)
                    try:
                        HOTSPOT_SOURCE.write_text(name, encoding="utf-8")
                    except OSError:
                        pass
                    errors = []
                    break
                except Exception as e:
                    errors.append("%s: %s" % (name.split("/")[0], str(e)[:60]))
            if not errors:
                break
        if errors and not HOTSPOTS.exists():
            raise RuntimeError("; ".join(errors[-3:]))
    return HOTSPOTS.read_text(encoding="utf-8", errors="replace")


def hotspot_source():
    try:
        return HOTSPOT_SOURCE.read_text(encoding="utf-8").split("/")[0].replace("-c2", "").replace("-c6.1", "").upper().replace("-VIIRS", " VIIRS")
    except OSError:
        return "MODIS"


def cluster_hotspots(csv_text, cell=0.5, min_conf=50, now=None):
    """Detections -> cells of `cell` degrees: [{lat, lon, n, frp, hours}] with the fire radiative power summed (MW)
    and the age of the newest detection. Low-confidence detections are ignored."""
    import csv, io, time
    from datetime import datetime, timezone
    now = now or time.time()
    cells = {}
    # VIIRS (375 m) sees about three detections where MODIS (1 km) saw one, and rates confidence as l / n / h
    # rather than 0-100: a VIIRS detection counts 0.4 so the cell tiers calibrated on MODIS still hold
    for row in csv.DictReader(io.StringIO(csv_text)):
        try:
            conf = row.get("confidence") or "0"
            conf = {"l": 30.0, "n": 60.0, "h": 90.0}.get(conf.strip().lower(), None) if not conf.strip().replace(".", "").isdigit() else float(conf)
            if conf is None or conf < min_conf:
                continue
            weight = 0.4 if "viirs" in (row.get("instrument") or "").lower() or "bright_ti4" in row else 1.0
            lat, lon, frp = float(row["latitude"]), float(row["longitude"]), float(row.get("frp") or 0)
            t = datetime.strptime(row["acq_date"] + row["acq_time"].zfill(4), "%Y-%m-%d%H%M").replace(tzinfo=timezone.utc).timestamp()
        except (KeyError, ValueError):
            continue
        k = (int(lat // cell), int(lon // cell))
        c = cells.setdefault(k, {"lat": 0.0, "lon": 0.0, "n": 0, "frp": 0.0, "t": 0})
        c["n"] += weight; c["raw"] = c.get("raw", 0) + 1; c["frp"] += frp; c["lat"] += lat * weight; c["lon"] += lon * weight; c["t"] = max(c["t"], t)
    out = []
    for c in cells.values():
        out.append({"lat": round(c["lat"] / c["n"], 2), "lon": round(c["lon"] / c["n"], 2), "n": int(round(c["n"])), "raw": c["raw"],
                    "frp": round(c["frp"]), "hours": round((now - c["t"]) / 3600, 1)})
    out.sort(key=lambda c: -c["frp"])
    return out


def cmd_hotspots(args):
    note, spots = "", []
    try:
        spots = cluster_hotspots(fetch_hotspots())
        try:
            fires, _h, _e = last_good("fires", fetch_fires)          # GDACS events, for the linkage; its own cache
        except Exception:
            fires = None
        spots = rate_hotspots(spots, fires or [])
        spots = [c for c in spots if c["tier"] >= args.min_tier and (c["tier"] > 0 or c["n"] >= args.min_count)
                 and (not args.people or c.get("people"))]
    except Exception as e:
        note = "Fire hotspots: %s" % e
    if args.table:
        print(note or "%d hotspot clusters (0.5 degree cells, tier %d and up, NASA FIRMS %s 24 h)" % (len(spots), args.min_tier, hotspot_source()))
        for c in spots[:60]:
            print("  %7.2f, %7.2f  %4d detections  %6d MW  newest %.0f h ago  %s  %s" % (
                c["lat"], c["lon"], c["n"], c["frp"], c["hours"], ["background", "notable", "ATTENTION"][c["tier"]], c["why"]))
    else:
        emit({"hotspots": spots, "note": note})


def chk_hotspots():
    spots = cluster_hotspots(fetch_hotspots())
    big = [c for c in spots if c["n"] >= 25]
    return ("ok" if "VIIRS" in hotspot_source() else "warn"), "%d detections in %d cells (%s, last 24 h%s), %d cells with 25+ (MODIS-equivalent) detections; strongest %s MW at %.1f, %.1f" % (
        sum(c.get("raw", c["n"]) for c in spots), len(spots), hotspot_source(), "" if "VIIRS" in hotspot_source() else "; VIIRS not reachable, MODIS ends in 2027",
        len(big), spots[0]["frp"] if spots else 0, spots[0]["lat"] if spots else 0, spots[0]["lon"] if spots else 0)


def chk_fires():
    fires = fetch_fires()
    hot = [fr for fr in fires if fr["alert"] in ("orange", "red")]
    return "ok", "%d current wildfire events, %d orange or red%s" % (
        len(fires), len(hot), ": " + ", ".join("%s (%s)" % (fr["name"], fr["alert"]) for fr in hot[:6]) if hot else "")


# ---------------------------------------------------------- named fire incidents ----
# The fires the agencies are actually fighting, with names, sizes, containment and (where mapped) the perimeter -
# the layer the satellite hotspots and GDACS's green ratings never give:
#  - NIFC WFIGS (US): the interagency "current perimeters" layer, one polygon per open incident, with acres,
#    percent contained, personnel, discovery date; no key (ArcGIS REST, GeoJSON, simplified server-side).
#  - CWFIS (Canada): the national active-fires list (agency, size in ha, stage of control: out of control /
#    being held / under control) and the M3 perimeter estimates from satellite hotspots, joined by distance.
#  - EFFIS (Europe, Middle East, North Africa): Copernicus's rapid damage assessment burnt areas (MODIS,
#    polygons with country, province, commune, hectares, fire date), the last weeks of them.
NIFC = ("https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_Current/FeatureServer/0/query"
        "?where=attr_IncidentTypeCategory%3D%27WF%27&outFields=attr_IncidentName,attr_IncidentSize,attr_PercentContained,attr_FireDiscoveryDateTime,"
        "attr_ModifiedOnDateTime_dt,attr_TotalIncidentPersonnel,attr_POOState,attr_POOCounty,attr_FireBehaviorGeneral,attr_IrwinID"
        "&outSR=4326&geometryPrecision=3&maxAllowableOffset=0.004&resultRecordCount=2000&f=geojson")


CWFIS_FIRES = ("https://geoserver.cwfif.nrcan.gc.ca/geoserver/wfs?service=WFS&version=2.0.0&request=GetFeature&outputFormat=application/json"
               "&typeName=public:cwfif_national_activefires&count=2000&CQL_FILTER=now()%3E%3Drecord_start%20AND%20now()%3C%3Drecord_end")


CWFIS_PERIMS = ("https://cwfis.cfs.nrcan.gc.ca/geoserver/wfs?service=WFS&version=2.0.0&request=GetFeature&outputFormat=application/json"
                "&typeName=public:m3_polygons_current&srsName=EPSG:4326&count=2000&CQL_FILTER=lastdate%%20%%3E%%20%%27%s%%27")


# The field names are upper case since October 2026 (FIREDATE, LASTUPDATE, COUNTRY, PROVINCE, COMMUNE, AREA_HA; the
# WFS DescribeFeatureType says so). A filter on the old `firedate` fails inside PostGIS and the server answers
# HTTP 502 with an ows:ExceptionReport ("FLTApplyFilterToLayer() failed msPostGISLayerWhichShapes(): Query error"),
# which is what the daily probe saw from 25 October to 10 November 2026. The parser reads either case.
EFFIS = ("https://maps.effis.emergency.copernicus.eu/effis?service=WFS&version=1.1.0&request=GetFeature&typename=ms:modis.ba.poly"
         "&outputformat=geojson&maxfeatures=1500&FILTER=%%3CFilter%%3E%%3CPropertyIsGreaterThanOrEqualTo%%3E%%3CPropertyName%%3EFIREDATE%%3C%%2FPropertyName%%3E"
         "%%3CLiteral%%3E%s%%3C%%2FLiteral%%3E%%3C%%2FPropertyIsGreaterThanOrEqualTo%%3E%%3C%%2FFilter%%3E")


CWFIS_STAGE = {"OC": "out of control", "BH": "being held", "UC": "under control", "EX": "out"}


CWFIS_STALE_DAYS = 14                             # an agency record with no status report for this long is dropped


INCIDENT_SOURCES = ("nifc", "cwfis", "effis")


def _incident(source, iid, name, lat, lon, ha, rings, **more):
    it = {"id": "%s:%s" % (source, iid), "source": source, "name": name, "lat": round(lat, 3), "lon": round(lon, 3),
          "area_ha": round(ha), "area": rings[:12], "contained": None, "stage": "", "personnel": 0, "since": "", "days": None,
          "hours": 0, "region": "", "alert": "incident"}
    it.update(more)
    return it


def _poly_centre(rings):
    lat, lon = _ring_centre(rings)
    return lat, lon


def fetch_nifc():
    """US incidents with perimeters: one per open wildfire (prescribed burns left out by the query)."""
    from datetime import datetime
    geo = fetch_json(NIFC, timeout=40, limit=MAX_BODY)
    if "error" in geo:
        raise ValueError("NIFC: %s" % (geo["error"].get("message") or geo["error"]))
    now, out = time.time(), []
    for f in geo.get("features", []):
        pr = f.get("properties") or {}
        rings = flood_area({"features": [f]})
        lat, lon = _poly_centre(rings)
        if lat is None:
            continue
        since, days = "", None
        t = pr.get("attr_FireDiscoveryDateTime")
        if t:
            since = datetime.utcfromtimestamp(t / 1000).strftime("%Y %b %d")
            days = max(0, round((now - t / 1000) / 86400, 1))
        mod = pr.get("attr_ModifiedOnDateTime_dt")
        acres = float(pr.get("attr_IncidentSize") or 0)
        out.append(_incident("nifc", pr.get("attr_IrwinID") or pr.get("attr_IncidentName"), str(pr.get("attr_IncidentName") or "Fire").title(),
                             lat, lon, acres * 0.4046856, rings,
                             contained=None if pr.get("attr_PercentContained") is None else int(pr["attr_PercentContained"]),
                             personnel=int(pr.get("attr_TotalIncidentPersonnel") or 0), since=since, days=days,
                             hours=round((now - mod / 1000) / 3600, 1) if mod else 0,
                             region=", ".join(x for x in (pr.get("attr_POOCounty"), pr.get("attr_POOState")) if x),
                             behaviour=str(pr.get("attr_FireBehaviorGeneral") or "").lower(),
                             url="https://inciweb.wildfire.gov/"))
    return out


def fetch_cwfis():
    """Canada: the active-fires list joined to the nearest M3 perimeter estimate of the last two weeks."""
    from datetime import datetime
    now = time.time()
    fires = fetch_json(CWFIS_FIRES, timeout=30).get("features", [])
    try:
        since_day = datetime.utcfromtimestamp(now - 14 * 86400).strftime("%Y-%m-%d")
        perims = fetch_json(CWFIS_PERIMS % since_day, timeout=40, limit=MAX_BODY).get("features", [])
    except Exception:
        perims = []
    polys = []
    for f in perims:
        rings = flood_area({"features": [f]})
        lat, lon = _poly_centre(rings)
        if lat is not None:
            polys.append((lat, lon, rings, float((f.get("properties") or {}).get("area") or 0)))
    out = []
    for f in fires:
        pr = f.get("properties") or {}
        if pr.get("fire_was_prescribed"):
            continue
        lat, lon = pr.get("latitude"), pr.get("longitude")
        if lat is None or lon is None:
            continue
        ha = float(pr.get("fire_size") or 0)
        rings = []
        best = None
        for plat, plon, prings, parea in polys:            # the perimeter estimate nearest the agency's point, within 15 km
            d = haversine_km(lat, lon, plat, plon)
            if d < 15 and (best is None or d < best[0]):
                best = (d, prings)
        if best:
            rings = best[1]
        sd = pr.get("status_date") or pr.get("situation_report_date") or ""
        hours = 0
        try:
            hours = round((now - datetime.strptime(str(sd)[:19], "%Y-%m-%dT%H:%M:%S").timestamp()) / 3600, 1)
        except (ValueError, TypeError):
            pass
        stage = CWFIS_STAGE.get(str(pr.get("stage_of_control_status") or ""), "")
        if stage == "out":
            continue
        if hours > CWFIS_STALE_DAYS * 24:
            continue                               # Quebec's list keeps summer fires "out of control" for months: no report in two weeks, not a live fire
        pc = pr.get("percent_contained")
        out.append(_incident("cwfis", pr.get("national_fire_id") or pr.get("id"), "%s fire %s" % (pr.get("agency_code") or "", pr.get("agency_fire_id") or ""),
                             float(lat), float(lon), ha, rings, contained=int(pc) if pc is not None and pc >= 0 else None, stage=stage,
                             hours=hours, region=str(pr.get("agency_code") or ""), url="https://cwfis.cfs.nrcan.gc.ca/interactive-map"))
    return out


def fetch_effis():
    """Europe, Middle East and North Africa: EFFIS burnt areas of the last three weeks (MODIS rapid damage assessment)."""
    from datetime import datetime
    now = time.time()
    since_day = datetime.utcfromtimestamp(now - 21 * 86400).strftime("%Y-%m-%d")
    geo = fetch_json(EFFIS % since_day, timeout=40, limit=MAX_BODY)
    out = []
    for f in geo.get("features", []):
        pr = f.get("properties") or {}

        def field(name):                              # FIREDATE since October 2026, firedate before: either
            v = pr.get(name.upper(), pr.get(name.lower()))
            return "" if v is None or str(v).strip() in ("", "N.A.") else v
        rings = flood_area({"features": [f]})
        lat, lon = _poly_centre(rings)
        if lat is None:
            continue
        since, days, hours = "", None, 0
        try:
            t = datetime.strptime(str(field("firedate"))[:10], "%Y-%m-%d").timestamp()
            since = datetime.utcfromtimestamp(t).strftime("%Y %b %d")
            days = max(0, round((now - t) / 86400, 1))
        except (ValueError, TypeError):
            pass
        try:
            hours = round((now - datetime.strptime(str(field("lastupdate"))[:19], "%Y-%m-%d %H:%M:%S").timestamp()) / 3600, 1)
        except (ValueError, TypeError):
            pass
        name = ", ".join(str(x) for x in (field("commune"), field("province")) if x) or str(field("country") or "Fire")
        out.append(_incident("effis", field("id") or f.get("id"), name, lat, lon, float(field("area_ha") or 0), rings,
                             since=since, days=days, hours=hours, region=str(field("country")),
                             url="https://forest-fire.emergency.copernicus.eu/apps/effis_current_situation/"))
    return out


INCIDENT_FETCH = {"nifc": fetch_nifc, "cwfis": fetch_cwfis, "effis": fetch_effis}


def incidents_cached(source, max_age_min=30):
    f = DATA / ("last-%s.json" % source)
    try:
        c = json.loads(f.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_min * 60:
            return c["data"], 0.0, ""
    except (OSError, ValueError, KeyError):
        pass
    return last_good(source, INCIDENT_FETCH[source])


def cmd_incidents(args):
    """`incidents --sources nifc,cwfis,effis [--min-ha 100] [--table]`: the named fires, with perimeters where mapped."""
    notes, items = [], []
    wanted = [x for x in (args.sources or ",".join(INCIDENT_SOURCES)).split(",") if x in INCIDENT_SOURCES]
    failed, answered = [], 0
    for src in wanted:
        data, stale_h, err = incidents_cached(src, args.max_age)
        if err:
            failed.append(stale_note({"nifc": "US fire incidents", "cwfis": "Canadian fires", "effis": "European burnt areas"}[src], stale_h, err, args.stale))
        else:
            answered += 1
        items += [it for it in (data or []) if it["area_ha"] >= args.min_ha]
    # one source down among several (EFFIS 502 for a day) is a Status matter - the Status page and the widget's
    # Status tab name it; the desktop's corner notice only when no incident source answers at all
    if failed and answered == 0:
        notes += failed
    try:
        items = remember_events("incident", items, lambda it: it["id"], args.keep, sig_of=lambda it: "%s/%s" % (it.get("stage"), (it.get("contained") or 0) // 25))
    except Exception as e:
        notes.append("Fire incidents: %s" % e)
    note = "; ".join(n for n in notes if n)
    if args.table:
        print(note or "%d fire incidents (%s)" % (len(items), ", ".join(wanted)))
        for it in sorted(items, key=lambda it: -it["area_ha"]):
            print("  %-6s %-34s %9d ha  %-14s %s%s  at %.2f, %.2f  %d rings%s" % (
                it["source"], it["name"][:34], it["area_ha"], it.get("stage") or ("%d %% contained" % it["contained"] if it.get("contained") is not None else ""),
                it.get("region", "")[:20], "  %d personnel" % it["personnel"] if it.get("personnel") else "", it["lat"], it["lon"], len(it["area"]),
                "  GONE" if it.get("gone") else ""))
    else:
        emit({"incidents": items, "note": note})


def chk_nifc():
    its = fetch_nifc()
    big = sorted(its, key=lambda it: -it["area_ha"])[:3]
    return "ok", "%d open US wildfire incidents with perimeters%s" % (len(its), ": " + ", ".join("%s %d ha" % (it["name"], it["area_ha"]) for it in big) if big else "")


def chk_cwfis():
    its = fetch_cwfis()
    return "ok", "%d Canadian fires reported on in the last two weeks, %d out of control, %d with a perimeter estimate" % (
        len(its), sum(1 for it in its if it["stage"] == "out of control"), sum(1 for it in its if it["area"]))


def chk_effis():
    its = fetch_effis()
    return "ok", "%d burnt areas mapped in the last three weeks (EFFIS)%s" % (
        len(its), ": " + ", ".join("%s %d ha" % (it["name"], it["area_ha"]) for it in sorted(its, key=lambda it: -it["area_ha"])[:3]) if its else "")
