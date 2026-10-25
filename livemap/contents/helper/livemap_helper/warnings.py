"""Official flood warnings outside the United States, in the NWS alert's shape so the flood layer and the widget
treat them alike: MeteoAlarm (the 38 European national weather services, CC BY 4.0), Environment and Climate
Change Canada (GeoMet's ALERTS layer, Open Government Licence - Canada), the UK Environment Agency (England,
Open Government Licence v3). Each source is cached on its own and fetched on its own clock; a source that is
down keeps its last answer like every other feed. The records are
  {id, source, event, name, counties, office, lat, lon, alert (green/orange/red), onset, until, headline, url, area}
"""
import json
import re
import time
import unicodedata

from .common import DATA, PKG, UA, _http, _split, fetch_json, last_good, safe_xml  # noqa: F401

# which official warning sources join the flood layer: a bitmask like the fire sources (NWS is its own switch)
WARN_METEOALARM, WARN_ECCC, WARN_EA = 2, 4, 8
WARN_NAMES = {WARN_METEOALARM: "MeteoAlarm", WARN_ECCC: "ECCC", WARN_EA: "EA"}

# ---- MeteoAlarm --------------------------------------------------------------------------------------------
# One JSON per country: every current warning as a CAP alert (English and local infos), with the awareness type
# and level as parameters and the regions as EMMA_ID geocodes with names; no geometry. The regions are placed by
# name on Natural Earth's admin-1 units (contents/data/europe-regions.json: names, a centre, thinned rings),
# with the country's centre as the fallback.
METEOALARM = "https://feeds.meteoalarm.org/api/v1/warnings/feeds-%s"
METEOALARM_COUNTRIES = {           # feed slug -> (ISO 3166-1 alpha-2, name, centre lon, lat)
    "austria": ("AT", "Austria", 14.1, 47.6), "belgium": ("BE", "Belgium", 4.5, 50.6), "bosnia-herzegovina": ("BA", "Bosnia and Herzegovina", 17.8, 44.2),
    "bulgaria": ("BG", "Bulgaria", 25.5, 42.7), "croatia": ("HR", "Croatia", 16.4, 45.1), "cyprus": ("CY", "Cyprus", 33.2, 35.0),
    "czechia": ("CZ", "Czechia", 15.5, 49.8), "denmark": ("DK", "Denmark", 10.0, 56.0), "estonia": ("EE", "Estonia", 25.0, 58.6),
    "finland": ("FI", "Finland", 26.0, 64.0), "france": ("FR", "France", 2.5, 46.6), "germany": ("DE", "Germany", 10.4, 51.1),
    "greece": ("GR", "Greece", 22.5, 39.0), "hungary": ("HU", "Hungary", 19.4, 47.2), "iceland": ("IS", "Iceland", -18.5, 65.0),
    "ireland": ("IE", "Ireland", -8.0, 53.3), "israel": ("IL", "Israel", 35.0, 31.5), "italy": ("IT", "Italy", 12.5, 42.5),
    "latvia": ("LV", "Latvia", 24.9, 56.9), "lithuania": ("LT", "Lithuania", 23.9, 55.2), "luxembourg": ("LU", "Luxembourg", 6.1, 49.8),
    "malta": ("MT", "Malta", 14.4, 35.9), "moldova": ("MD", "Moldova", 28.5, 47.2), "montenegro": ("ME", "Montenegro", 19.3, 42.7),
    "netherlands": ("NL", "Netherlands", 5.3, 52.2), "republic-of-north-macedonia": ("MK", "North Macedonia", 21.7, 41.6),
    "norway": ("NO", "Norway", 9.0, 61.5), "poland": ("PL", "Poland", 19.4, 52.1), "portugal": ("PT", "Portugal", -8.2, 39.6),
    "romania": ("RO", "Romania", 25.0, 45.9), "serbia": ("RS", "Serbia", 20.9, 44.2), "slovakia": ("SK", "Slovakia", 19.7, 48.7),
    "slovenia": ("SI", "Slovenia", 14.8, 46.1), "spain": ("ES", "Spain", -3.7, 40.2), "sweden": ("SE", "Sweden", 15.0, 62.0),
    "switzerland": ("CH", "Switzerland", 8.2, 46.8), "ukraine": ("UA", "Ukraine", 31.5, 49.0), "united-kingdom": ("GB", "United Kingdom", -2.5, 54.0)}
# awareness_type codes that are water: 7 coastal event, 10 rain, 12 flooding, 13 rain-flood (1 wind, 2 snow/ice,
# 3 thunderstorm, 4 fog, 5/6 heat and cold, 8 forest fire, 9 avalanche are not this layer's)
METEOALARM_FLOOD_TYPES = {"7", "10", "12", "13"}
METEOALARM_LEVELS = {"2": "green", "3": "orange", "4": "red"}     # yellow is the watch tier; green (1) is no warning
EU_REGIONS = PKG / "data" / "europe-regions.json"
_eu_regions = None


def _plain(t):
    return re.sub(r"[^a-z0-9]+", " ", "".join(c for c in unicodedata.normalize("NFKD", t or "") if not unicodedata.combining(c)).lower()).strip()


def eu_regions():
    global _eu_regions
    if _eu_regions is None:
        try:
            _eu_regions = json.loads(EU_REGIONS.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _eu_regions = {}
    return _eu_regions


def place_region(iso, area_desc):
    """(lat, lon, rings) of a MeteoAlarm area by its name: the admin-1 unit (or NE's region of units) whose name
    matches, exactly or as the longest common start; None when nothing matches."""
    key = _plain(area_desc)
    if not key:
        return None
    best, score = None, 0
    for u in eu_regions().get(iso, []):
        for n in u["names"]:
            if n == key or key == n:
                return u["lat"], u["lon"], u.get("rings", [])
            s = 0
            if n in key or key in n:
                s = min(len(n), len(key))
            if s > score and s >= 5:
                best, score = u, s
    return (best["lat"], best["lon"], best.get("rings", [])) if best else None


def _cap_params(info):
    return {p.get("valueName", ""): str(p.get("value", "")) for p in info.get("parameter") or [] if isinstance(p, dict)}


def _epoch(t):
    """ISO 8601 with an offset -> epoch; None when unreadable."""
    from datetime import datetime
    try:
        return datetime.fromisoformat(str(t).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def parse_meteoalarm(body, slug):
    """The warnings of one country's feed -> alert records (the flood kinds only), one per warning."""
    iso, cname, clon, clat = METEOALARM_COUNTRIES.get(slug, ("", slug.title(), None, None))
    now = time.time()
    out = []
    for w in (body.get("warnings") or []):
        alert = w.get("alert") or {}
        if alert.get("status", "Actual") != "Actual" or alert.get("msgType") == "Cancel":
            continue
        infos = alert.get("info") or []
        info = next((i for i in infos if str(i.get("language", "")).lower().startswith("en")), infos[0] if infos else None)
        if not info:
            continue
        params = _cap_params(info)
        atype = params.get("awareness_type", "").split(";")[0].strip()
        alevel = params.get("awareness_level", "").split(";")[0].strip()
        if atype not in METEOALARM_FLOOD_TYPES or alevel not in METEOALARM_LEVELS:
            continue
        until = _epoch(info.get("expires"))
        if until is not None and until < now:
            continue
        onset = _epoch(info.get("onset") or info.get("effective") or alert.get("sent"))
        areas = [a.get("areaDesc", "") for a in info.get("area") or [] if a.get("areaDesc")]
        lats, lons, rings = [], [], []
        for a in areas:
            at = place_region(iso, a)
            if at:
                lats.append(at[0]); lons.append(at[1]); rings += at[2][:3]
        if not lats:
            if clat is None:
                continue
            lats, lons = [clat], [clon]
        kind = {"7": "Coastal Flood Warning", "10": "Heavy Rain Warning", "12": "Flood Warning", "13": "Rain and Flood Warning"}[atype]
        aid = alert.get("identifier") or w.get("uuid") or ""
        out.append({"id": "ma:" + re.sub(r"[^A-Za-z0-9]+", "-", aid).strip("-").lower(), "source": "meteoalarm", "event": kind,
                    "name": "; ".join(areas[:3]) + (", +%d" % (len(areas) - 3) if len(areas) > 3 else ""), "counties": len(areas), "places": areas[:60],
                    "office": cname, "lat": round(sum(lats) / len(lats), 3), "lon": round(sum(lons) / len(lons), 3),
                    "alert": METEOALARM_LEVELS[alevel], "severity": info.get("severity", ""), "since": "", "days": None, "hours": 0,
                    "onset": onset, "until": until, "headline": str(info.get("headline") or info.get("event") or "")[:160],
                    "url": str(info.get("web") or "https://www.meteoalarm.org/"), "people": [], "area": rings[:24]})
    return out


def fetch_meteoalarm():
    """Every country's feed; a country that fails is reported, the rest still answer."""
    out, failed = [], []
    for slug in METEOALARM_COUNTRIES:
        try:
            body = fetch_json(METEOALARM % slug, timeout=12, headers=dict(UA, Accept="*/*"))
            out += parse_meteoalarm(body, slug)
        except Exception as e:
            failed.append("%s: %s" % (slug, str(e)[:40]))
    if failed and len(failed) == len(METEOALARM_COUNTRIES):
        raise RuntimeError("MeteoAlarm: " + "; ".join(failed[:3]))
    return {"alerts": out, "failed": failed}


# ---- Environment and Climate Change Canada ----------------------------------------------------------------
# GeoMet's WFS serves every active public alert as GeoJSON with its polygon; the flood ones are the rainfall and
# flood warnings, watches and statements (ECCC's flood *forecasting* is provincial and not in this feed).
# The WFS type is ec-msc:Current-Alerts (the WMS layer is called ALERTS; the two names differ) and the service
# speaks GML only (its outputFormat list is four flavours of XML; every JSON name is refused), so the default
# GML 3.2 answer is read with the stdlib parser, guarded like every other XML feed.
ECCC_WFS = ("https://geo.weather.gc.ca/geomet?service=WFS&version=2.0.0&request=GetFeature&typename=ec-msc:Current-Alerts"
            "&srsName=EPSG:4326&count=2000")
ECCC_FLOOD_RE = re.compile(r"flood|rainfall|rain\b|storm surge", re.I)


def parse_eccc(body):
    now = time.time()
    out = []
    for f in body.get("features") or []:
        pr = f.get("properties") or {}
        text = " ".join(str(pr.get(k) or "") for k in ("headline", "alert_type", "event", "descrip_en", "title", "name", "alert_name", "type", "status", "descrip"))
        head = str(pr.get("headline") or pr.get("alert_type") or pr.get("alert_name") or pr.get("event") or pr.get("type") or "").strip()
        if not ECCC_FLOOD_RE.search(head or text[:200]):
            continue
        until = _epoch(pr.get("expires") or pr.get("expiry") or pr.get("expiry_date") or pr.get("expires_at"))
        if until is not None and until < now:
            continue
        low = (head + " " + str(pr.get("alert_type") or "")).lower()
        level = "red" if "flash" in low else "orange" if "warning" in low else "green"
        from .floods import flood_area, _ring_centre
        rings = flood_area({"features": [f]}) if f.get("geometry") else []
        lat, lon = _ring_centre(rings)
        if lat is None:
            continue
        aid = str(pr.get("identifier") or pr.get("id") or f.get("id") or "")
        area = str(pr.get("area") or pr.get("areaDesc") or pr.get("area_name") or pr.get("region") or pr.get("name") or pr.get("zone") or "")
        out.append({"id": "eccc:" + re.sub(r"[^A-Za-z0-9]+", "-", aid).strip("-").lower(), "source": "eccc", "event": head.title() if head.isupper() else head or "Weather Alert",
                    "name": area, "counties": 1, "places": [area] if area else [], "office": "Environment Canada", "lat": round(lat, 3), "lon": round(lon, 3), "alert": level,
                    "severity": str(pr.get("severity") or ""), "since": "", "days": None, "hours": 0,
                    "onset": _epoch(pr.get("effective") or pr.get("issued") or pr.get("sent") or pr.get("issue_date") or pr.get("effective_date")), "until": until,
                    "headline": head[:160], "url": str(pr.get("url") or "https://weather.gc.ca/warnings/index_e.html"), "people": [], "area": rings[:12]})
    return out


def gml_features(text):
    """A WFS GML answer as GeoJSON-shaped features: every element directly under a member becomes a property
    (its local name, its text), every gml:Polygon a ring. EPSG:4326 in GML 3.2 lists latitude first; a posList
    is read that way and turned round to lon, lat. Field names are not assumed - the alert parser looks for
    the ones it knows among whatever the server sends."""
    import xml.etree.ElementTree as ET
    root = ET.fromstring(safe_xml(text))
    if root.tag.endswith("ExceptionReport"):
        m = re.search(r"<(?:ows:)?ExceptionText>\s*(.*?)\s*</", text, re.S)
        raise ValueError("WFS exception: " + " ".join((m.group(1) if m else text[:200]).split())[:160])

    def local(tag):
        return tag.rsplit("}", 1)[-1]

    def rings_of(el):
        out = []
        for poly in el.iter():
            if local(poly.tag) != "Polygon":
                continue
            for pl in poly.iter():
                if local(pl.tag) not in ("posList", "coordinates"):
                    continue
                nums = [float(x) for x in re.split(r"[\s,]+", (pl.text or "").strip()) if x]
                if local(pl.tag) == "posList":
                    pts = [(nums[i + 1], nums[i]) for i in range(0, len(nums) - 1, 2)]        # lat lon -> lon lat
                else:
                    pts = [(nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)]        # GML 2 coordinates: lon,lat
                if len(pts) >= 4:
                    out.append(pts)
                break                                            # the exterior ring; holes are not needed
        return out

    feats = []
    for member in root:
        if local(member.tag) not in ("member", "featureMember", "featureMembers"):
            continue
        for feat in (list(member) or [member]):
            props, rings = {}, []
            for child in feat:
                name = local(child.tag)
                if any(local(g.tag) == "Polygon" for g in child.iter()):
                    rings += rings_of(child)
                    continue
                if len(child) == 0:
                    props[name] = (child.text or "").strip()
            geom = {"type": "MultiPolygon", "coordinates": [[r] for r in rings]} if rings else None
            feats.append({"type": "Feature", "id": feat.get("{http://www.opengis.net/gml/3.2}id") or feat.get("fid") or "", "properties": props, "geometry": geom})
    return {"type": "FeatureCollection", "features": feats}


def fetch_eccc():
    text = _http(ECCC_WFS, timeout=25)[2].decode("utf-8", "replace")
    return {"alerts": parse_eccc(gml_features(text)), "failed": []}


# ---- UK Environment Agency ---------------------------------------------------------------------------------
# England's flood warnings in force: severity 1 severe flood warning (red), 2 flood warning (orange), 3 flood
# alert (green), 4 no longer in force (dropped). Each names a flood area whose polygon is a separate GeoJSON,
# fetched once and kept (ea-areas/), a few per refresh, like the NWS zones.
EA_FLOODS = "https://environment.data.gov.uk/flood-monitoring/id/floods"
EA_AREAS = DATA / "ea-areas"
EA_AREAS_PER_RUN = 25
EA_LEVEL = {1: "red", 2: "orange", 3: "green"}
EA_ATTRIBUTION = "This uses Environment Agency flood and river level data from the real-time data API (Beta)"


def ea_area_rings(area_id, polygon_url, budget):
    """The flood area's rings (cached for good) and whether this call fetched them."""
    from .floods import flood_area
    EA_AREAS.mkdir(parents=True, exist_ok=True)
    f = EA_AREAS / (re.sub(r"[^A-Za-z0-9]", "", area_id) + ".json")
    try:
        return json.loads(f.read_text(encoding="utf-8")), 0
    except (OSError, ValueError):
        pass
    if budget[0] <= 0 or not polygon_url:
        return [], 0
    budget[0] -= 1
    geo = fetch_json(polygon_url.replace("http://", "https://"), timeout=12)
    rings = flood_area(geo if geo.get("type") == "FeatureCollection" else {"features": [geo]})[:6]
    try:
        f.write_text(json.dumps(rings, separators=(",", ":")), encoding="utf-8")
    except OSError:
        pass
    return rings, 1


def parse_ea(body, budget=None):
    from .floods import _ring_centre
    budget = budget if budget is not None else [EA_AREAS_PER_RUN]
    out = []
    for it in body.get("items") or []:
        try:
            level = EA_LEVEL.get(int(it.get("severityLevel") or 0))
        except ValueError:
            level = None
        if not level:
            continue
        fa = it.get("floodArea") or {}
        area_id = str(it.get("floodAreaID") or fa.get("notation") or it.get("@id", "").rsplit("/", 1)[-1])
        try:
            rings, _n = ea_area_rings(area_id, fa.get("polygon", ""), budget)
        except Exception:
            rings = []
        lat, lon = _ring_centre(rings)
        if lat is None:
            try:
                lat, lon = float(fa.get("lat")), float(fa.get("long"))
            except (TypeError, ValueError):
                continue                                           # placed next time, when its polygon has been fetched
        out.append({"id": "ea:" + re.sub(r"[^A-Za-z0-9]+", "-", area_id).lower(), "source": "ea", "event": str(it.get("severity") or "Flood warning"),
                    "name": str(it.get("description") or fa.get("county") or area_id), "counties": 1,
                    "places": [p.strip() for p in str(fa.get("county") or "").split(",") if p.strip()][:60], "county": str(fa.get("county") or ""),
                    "office": str(it.get("eaAreaName") or "Environment Agency"),
                    "lat": round(lat, 3), "lon": round(lon, 3), "alert": level, "severity": "", "since": "", "days": None, "hours": 0,
                    "onset": _epoch(it.get("timeRaised")), "until": None, "headline": str(it.get("message") or "")[:160],
                    "url": "https://check-for-flooding.service.gov.uk/", "people": [], "area": rings})
    return out


def fetch_ea():
    body = fetch_json(EA_FLOODS, timeout=15)
    return {"alerts": parse_ea(body), "failed": []}


# ---- all together ------------------------------------------------------------------------------------------
SOURCES = {WARN_METEOALARM: ("meteoalarm", fetch_meteoalarm, 30), WARN_ECCC: ("eccc", fetch_eccc, 15), WARN_EA: ("ea", fetch_ea, 15)}


def _cached(name, fetch, max_age_min):
    f = DATA / ("last-%s.json" % name)
    try:
        c = json.loads(f.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_min * 60:
            return c["data"], 0.0, ""
    except (OSError, ValueError, KeyError):
        pass
    return last_good(name, fetch)


def warnings_cached(mask):
    """The alerts of every source in the mask: (alerts, notes) - a note per source that is down or stale."""
    alerts, notes = [], []
    for bit, (name, fetch, minutes) in SOURCES.items():
        if not mask & bit:
            continue
        data, stale_h, err = _cached(name, fetch, minutes)
        if err:
            notes.append("%s: %s" % (WARN_NAMES[bit], err if stale_h is None else "no update for %.0f h" % stale_h))
        for a in (data or {}).get("alerts", []):
            alerts.append(a)
        for fmsg in (data or {}).get("failed", [])[:2]:
            notes.append("%s: %s" % (WARN_NAMES[bit], fmsg))
    return alerts, notes


def chk_meteoalarm():
    d = fetch_meteoalarm()
    warn = [a for a in d["alerts"] if a["alert"] in ("orange", "red")]
    return ("warn" if d["failed"] else "ok"), "%d flood, rain and coastal warnings in force (%d orange or red)%s%s" % (
        len(d["alerts"]), len(warn), ": " + ", ".join("%s (%s)" % (a["office"], a["alert"]) for a in warn[:5]) if warn else "",
        "; not answering: " + ", ".join(f.split(":")[0] for f in d["failed"]) if d["failed"] else "")


def chk_eccc():
    d = fetch_eccc()
    return "ok", "%d flood and rainfall alerts in force%s" % (len(d["alerts"]), ": " + ", ".join(a["name"][:30] for a in d["alerts"][:4]) if d["alerts"] else "")


def chk_ea():
    d = fetch_ea()
    warn = [a for a in d["alerts"] if a["alert"] in ("orange", "red")]
    return "ok", "%d flood alerts and warnings in force in England, %d warnings%s" % (
        len(d["alerts"]), len(warn), ": " + ", ".join(a["name"][:30] for a in warn[:4]) if warn else "")
