"""Tropical storms: GDACS, NHC, JTWC (with UCAR's ATCF decks), merged; impacts."""
import json
import re
import sys
from collections import Counter

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import _http, _split, emit, haversine_km, last_good, remember_events, safe_xml, stale_note, storm_kind, fetch_json
from .infra import _remember_impacts, impact_text, storm_impacts


# --------------------------------------------------------------- storms -----
GDACS = "https://www.gdacs.org/gdacsapi/api/events/geteventlist/EVENTS4APP"


def _when(props):
    """First thing in a feature's properties that parses as a date -> unix time, else None."""
    from datetime import datetime
    for k, v in props.items():
        if "date" in k.lower() and isinstance(v, str) and len(v) >= 10:
            for fmt in ("%Y-%m-%dT%H:%M:%S", "%d/%m/%Y %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%d %b %Y %H:%M:%S"):
                try:
                    return datetime.strptime(v[:19], fmt).timestamp()
                except ValueError:
                    pass
    return None


def storm_shape(geo, now):
    """Turn GDACS's getgeometry FeatureCollection into past track, forecast track, forecast points and cone.
    Dated points are trusted most: sorted by time they give the past and the forecast. Lines are the fallback."""
    pts, lines, cone, classes = [], [], [], Counter()
    for f in geo.get("features", []):
        g, pr = f.get("geometry") or {}, f.get("properties") or {}
        kind, c, cls = g.get("type"), g.get("coordinates") or [], str(pr.get("Class", ""))
        classes[cls + " (" + str(kind) + ")"] += 1
        if kind == "Point":
            t = _when(pr)
            if t is not None:
                pts.append((t, c[0], c[1]))
        elif kind == "LineString":
            lines.append([(x[0], x[1]) for x in c])
        elif kind == "MultiLineString":
            lines += [[(x[0], x[1]) for x in part] for part in c]
        elif kind in ("Polygon", "MultiPolygon") and "cone" in cls.lower():
            for ring in ([c[0]] if kind == "Polygon" else [poly[0] for poly in c]):
                cone += _split([(x[0], x[1]) for x in ring])
    pts.sort()
    past = [(lo, la) for t, lo, la in pts if t <= now]
    future = [(lo, la) for t, lo, la in pts if t > now]
    if past and future:
        future = [past[-1]] + future
    shape = {"past": _split(past), "forecast": _split(future), "cone": cone,
             "dots": [[round(lo, 2), round(la, 2)] for lo, la in future[1:]]}
    if not pts:                                   # no dated points: draw whatever lines there are as the track
        shape["past"] = [seg for ln in lines for seg in _split(ln)]
    return shape, classes


def gdacs_list():
    """The GDACS event list, with a 20 s budget and one retry: the service is often slow rather than down."""
    last = None
    for attempt in range(2):
        try:
            return fetch_json(GDACS, timeout=20)
        except Exception as e:
            last = e
    raise last


def fetch_storms(debug=False):
    import time
    body = json.dumps(gdacs_list()).encode()
    now, storms, seen = time.time(), [], {}
    for f in json.loads(body).get("features", []):
        pr = f.get("properties") or {}
        if pr.get("eventtype") != "TC" or str(pr.get("iscurrent", "true")).lower() != "true":
            continue
        lon, lat = (f.get("geometry") or {}).get("coordinates", [0, 0])[:2]
        # GDACS's "severity" is the storm's maximum wind over the episode, not the wind now; its text does say
        # the current class, though ("Tropical Storm (maximum wind speed of 130 km/h)"). NHC fills in the real
        # current wind for the Atlantic and eastern Pacific below.
        sev = pr.get("severitydata") or {}
        wind = float(sev.get("severity") or 0)
        kind, cat = storm_kind(wind, lat, lon)
        sevtext = str(sev.get("severitytext") or "").lower()
        if "tropical storm" in sevtext:
            kind, cat = "Tropical storm", 0
        elif "depression" in sevtext:
            kind, cat = "Tropical depression", 0
        hours = None                                  # age of the latest advisory, for fading old ones out
        try:
            from datetime import datetime
            hours = round((now - datetime.strptime(str(pr.get("datemodified") or pr.get("todate"))[:19], "%Y-%m-%dT%H:%M:%S").timestamp()) / 3600, 1)
        except (ValueError, TypeError):
            pass
        st = {"id": pr.get("eventid"), "name": str(pr.get("eventname") or pr.get("name") or "").split("-")[0].title(),
              "kind": kind, "cat": cat, "wind": round(wind), "wind_is_peak": True, "lat": lat, "lon": lon, "alert": pr.get("alertlevel", ""), "hours": hours,
              "source": pr.get("source", ""), "past": [], "forecast": [], "cone": [], "dots": []}
        try:
            _c, _h, gbody, _t = _http((pr.get("url") or {}).get("geometry"))
            shape, classes = storm_shape(json.loads(gbody), now)
            st.update(shape)
            if debug:
                st["classes"] = dict(classes)
        except Exception as e:
            st["problem"] = "%s: %s" % (type(e).__name__, e)
        if st["id"] not in seen:                  # one entry per storm, even if GDACS lists several episodes
            seen[st["id"]] = True
            storms.append(st)
    return storms


# Secondary source for storms: the US National Hurricane Center (Atlantic, eastern and central Pacific).
# CurrentStorms.json gives position and intensity; the forecast track and cone come as small KMZ files.
NHC = "https://www.nhc.noaa.gov/CurrentStorms.json"


def _kml_coords(kmz_bytes):
    """Every <coordinates> list in a KMZ/KML, as [(lon, lat), ...] lists, tagged with the geometry it sits in."""
    import io, zipfile
    import xml.etree.ElementTree as ET
    try:
        with zipfile.ZipFile(io.BytesIO(kmz_bytes)) as z:
            name = next(n for n in z.namelist() if n.lower().endswith(".kml"))
            if z.getinfo(name).file_size > 8 * 1024 * 1024:
                raise ValueError("KML inside the KMZ is unreasonably large")
            xml_text = z.read(name)
    except zipfile.BadZipFile:
        xml_text = kmz_bytes
    out = []
    root = ET.fromstring(safe_xml(xml_text))
    for el in root.iter():
        tag = el.tag.rsplit("}", 1)[-1]
        if tag in ("Point", "LineString", "Polygon"):
            for c in el.iter():
                if c.tag.rsplit("}", 1)[-1] == "coordinates" and c.text:
                    pts = []
                    for tok in c.text.split():
                        try:
                            lon, lat = tok.split(",")[:2]
                            pts.append((float(lon), float(lat)))
                        except ValueError:
                            pass
                    if pts:
                        out.append((tag, pts))
    return out


# Tropical ATCF storm types; anything else (DB disturbance, LO low, EX extratropical, PT post-tropical...) is
# drawn in the "not tropical" colour, as on NHC's own charts.
TROPICAL_TYPES = ("TD", "TS", "TY", "ST", "TC", "HU")


def nhc_best_track(sid):
    """NHC's best track for a storm id like ep172026, from the public ATCF b-deck: one fix every 6 hours with
    position, wind (knots) and storm type. -> [[lon, lat, wind_kmh, unix_time, tropical(1/0)], ...] oldest first."""
    from datetime import datetime, timezone
    body = _http("https://ftp.nhc.noaa.gov/atcf/btk/b%s.dat" % sid.lower(), timeout=15)[2].decode("ascii", "replace")
    seen, out = set(), []
    for line in body.splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) < 11 or f[4] != "BEST" or f[2] in seen:
            continue
        try:
            t = datetime.strptime(f[2], "%Y%m%d%H").replace(tzinfo=timezone.utc).timestamp()
            lat = int(f[6][:-1]) / 10 * (1 if f[6][-1] == "N" else -1)
            lon = int(f[7][:-1]) / 10 * (1 if f[7][-1] == "E" else -1)
            wind = round(int(f[8]) * 1.852)
        except (ValueError, IndexError):
            continue
        seen.add(f[2])
        out.append([round(lon, 2), round(lat, 2), wind, round(t), 1 if f[10] in TROPICAL_TYPES else 0])
    out.sort(key=lambda p: p[3])
    return out


def _kml_placemarks(kmz_bytes):
    """Point placemarks of a KMZ/KML with whatever intensity they carry: [(lon, lat, wind_kmh or None), ...]."""
    import io, re, zipfile
    import xml.etree.ElementTree as ET
    try:
        with zipfile.ZipFile(io.BytesIO(kmz_bytes)) as z:
            name = next(n for n in z.namelist() if n.lower().endswith(".kml"))
            if z.getinfo(name).file_size > 8 * 1024 * 1024:
                raise ValueError("KML inside the KMZ is unreasonably large")
            xml_text = z.read(name)
    except zipfile.BadZipFile:
        xml_text = kmz_bytes
    out = []
    for pm in ET.fromstring(safe_xml(xml_text)).iter():
        if pm.tag.rsplit("}", 1)[-1] != "Placemark":
            continue
        pt, wind, text = None, None, []
        for el in pm.iter():
            tag = el.tag.rsplit("}", 1)[-1]
            if tag == "Point":
                for c in el.iter():
                    if c.tag.rsplit("}", 1)[-1] == "coordinates" and c.text:
                        try:
                            lon, lat = c.text.split()[0].split(",")[:2]
                            pt = (float(lon), float(lat))
                        except (ValueError, IndexError):
                            pass
            elif tag == "Data":                                   # <Data name="intensity"><value>100</value></Data>
                nm = str(el.get("name") or "").lower()
                val = "".join(v.text or "" for v in el if v.tag.rsplit("}", 1)[-1] == "value").strip()
                if val and ("intens" in nm or "wind" in nm) and "mph" not in nm and "kph" not in nm and "kmh" not in nm:
                    try:
                        wind = wind or round(float(re.findall(r"[\d.]+", val)[0]) * 1.852)
                    except (ValueError, IndexError):
                        pass
            elif tag in ("description", "name") and el.text:
                text.append(el.text)
        if pt is None:
            continue
        if wind is None:                                          # "Maximum Wind: 100 knots" / "85 kt" / "115 mph" in the text
            blob = " ".join(text)
            m = re.search(r"(\d+)\s*(?:kt\b|knots)", blob, re.I)
            if m:
                wind = round(int(m.group(1)) * 1.852)
            else:
                m = re.search(r"(\d+)\s*mph", blob, re.I)
                if m:
                    wind = round(int(m.group(1)) * 1.609)
        out.append((pt[0], pt[1], wind))
    return out


def fetch_storms_nhc():
    import time
    from datetime import datetime, timezone
    now, storms = time.time(), []
    body = fetch_json(NHC, timeout=15)
    for st in body.get("activeStorms") or []:
        try:
            lat, lon = float(st["latitudeNumeric"]), float(st["longitudeNumeric"])
            wind = float(st.get("intensity") or 0) * 1.852                    # knots -> km/h
        except (KeyError, TypeError, ValueError):
            continue
        kind, cat = storm_kind(wind, lat, lon)
        hours = None
        try:
            hours = round((now - datetime.strptime(st["lastUpdate"][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()) / 3600, 1)
        except (KeyError, ValueError, TypeError):
            pass
        rec = {"id": st.get("id"), "name": str(st.get("name") or "").title(), "kind": kind, "cat": cat, "wind": round(wind), "lat": lat, "lon": lon,
               "alert": "", "hours": hours, "source": "NHC", "past": [], "forecast": [], "cone": [], "dots": []}
        try:                                                                  # forecast track: a line plus the advisory points
            kmz = _http((st.get("forecastTrack") or {}).get("kmzFile"), timeout=15)[2]
            geoms = _kml_coords(kmz)
            lines = [pts for tag, pts in geoms if tag == "LineString"]
            points = [pts[0] for tag, pts in geoms if tag == "Point"]
            future = lines[0] if lines else points
            if future and (abs(future[0][0] - lon) > 0.01 or abs(future[0][1] - lat) > 0.01):
                future = [(lon, lat)] + list(future)
            rec["forecast"] = _split(future)
            winds = {}                                                        # forecast intensity per point, when the KML says
            try:
                for lo, la, w in _kml_placemarks(kmz):
                    winds[(round(lo, 2), round(la, 2))] = w
            except Exception:
                pass
            rec["dots"] = [[round(lo, 2), round(la, 2), winds.get((round(lo, 2), round(la, 2)))]
                           for lo, la in points if abs(lo - lon) > 0.01 or abs(la - lat) > 0.01]
        except Exception as e:
            rec["problem"] = "track: %s" % e
        try:                                                                  # where it has been, with intensity: the best track
            rec["track"] = nhc_best_track(str(st.get("id") or ""))
        except Exception as e:
            rec["track"] = []
            rec["problem"] = (rec.get("problem", "") + "; " if rec.get("problem") else "") + "best track: %s" % e
        try:
            geoms = _kml_coords(_http((st.get("trackCone") or {}).get("kmzFile"), timeout=15)[2])
            for tag, pts in geoms:
                if tag == "Polygon":
                    rec["cone"] += _split(pts)
        except Exception:
            pass
        storms.append(rec)
    return storms


def chk_storms_nhc():
    storms = fetch_storms_nhc()
    return "ok", "%d active in the Atlantic / eastern Pacific%s" % (len(storms), ": " + ", ".join("%s (%s)" % (s["name"], s["kind"].lower()) for s in storms) if storms else "")


# JTWC (Joint Typhoon Warning Center, Pearl Harbor): the US Navy's warnings for the western Pacific, the Indian
# Ocean and the southern hemisphere - the basins NHC does not cover. Its RSS lists the active storms with their
# warning products; the warning text carries the position and 1-minute wind now and the forecast positions with
# winds; the best track (one fix every 6 hours with wind) is the ATCF b-deck, relayed through NHC's public ATCF
# directory like the Atlantic ones (JTWC's own copy is the fallback). All public domain (US government).
JTWC_RSS = "https://www.metoc.navy.mil/jtwc/rss/jtwc.rss"


JTWC_PRODUCTS = "https://www.metoc.navy.mil/jtwc/products/"


JTWC_BASINS = {"wp": "W", "io": "B", "sh": "S"}           # the b-deck basin letter and the storm number's letter


# the RSS: "Typhoon 29W (Champi) Warning #31" ... "products/wp2926web.txt"
JTWC_STORM_RE = re.compile(r"(Super Typhoon|Typhoon|Hurricane|Tropical Storm|Tropical Depression|Tropical Cyclone|Subtropical Storm)\s+"
                           r"(\d{2}[A-Z])\s*(?:\(([^)]*)\))?", re.I)


JTWC_PRODUCT_RE = re.compile(r"products/(wp|io|sh|ep|cp)(\d{2})(\d{2})web\.txt", re.I)


# the warning text: "220000Z --- NEAR 20.3N 126.0E" (position now), "221200Z --- 21.3N 124.7E" (a forecast),
# "MAX SUSTAINED WINDS - 115 KT" after each
JTWC_POSIT_RE = re.compile(r"(\d{2})(\d{2})(\d{2})Z\s*-+\s*(?:NEAR\s+)?(\d{1,2}\.\d)([NS])\s+(\d{1,3}\.\d)([EW])", re.I)


JTWC_WIND_RE = re.compile(r"MAX SUSTAINED WINDS\s*-\s*(\d{2,3})\s*KT", re.I)


def jtwc_warning(text, now):
    """The position and wind now and the forecast points from a JTWC warning: (lon, lat, wind_kmh, issued_epoch,
    [[lon, lat, wind_kmh], ...]). The text's times are day/hour/minute of the current month."""
    from datetime import datetime, timedelta, timezone
    fixes = []
    text = text.split("REMARKS:")[0]                              # the remarks repeat the position without dashes
    for m in JTWC_POSIT_RE.finditer(text):
        w = JTWC_WIND_RE.search(text, m.end())
        if not w:
            continue
        day, hour, minute = int(m.group(1)), int(m.group(2)), int(m.group(3))
        lat = float(m.group(4)) * (1 if m.group(5).upper() == "N" else -1)
        lon = float(m.group(6)) * (1 if m.group(7).upper() == "E" else -1)
        t = datetime.fromtimestamp(now, timezone.utc)
        try:
            when = t.replace(day=day, hour=hour, minute=minute, second=0, microsecond=0)
        except ValueError:
            continue
        if when.timestamp() - now > 20 * 86400:                   # a day number from last month
            when = (when.replace(day=1) - timedelta(days=1)).replace(day=day)
        elif now - when.timestamp() > 20 * 86400:                 # ... or next month
            when = (when.replace(day=28) + timedelta(days=4)).replace(day=day)
        fixes.append((round(lon, 2), round(lat, 2), round(int(w.group(1)) * 1.852), round(when.timestamp())))
        if len(fixes) > 12:
            break
    if not fixes:
        raise ValueError("no position in the warning")
    lon, lat, wind, issued = fixes[0]
    return lon, lat, wind, issued, [[f[0], f[1], f[2]] for f in fixes[1:]], [round((f[3] - issued) / 3600) for f in fixes[1:]]


# NCAR/UCAR's real-time tropical cyclone guidance site mirrors the ATCF decks of every basin during the season;
# NHC's ATCF directory carries only the Atlantic and eastern / central Pacific
UCAR_DECKS = "https://hurricanes.ral.ucar.edu/realtime/plots/%s/%s/%s/b%s.dat"


UCAR_BASIN = {"wp": "northwestpacific", "io": "northindian", "sh": "southernhemisphere", "ep": "northeastpacific", "cp": "northcentralpacific", "al": "northatlantic"}


def jtwc_best_track(sid):
    """The b-deck for a JTWC storm id like wp292026 (a southern-hemisphere one carries its season year,
    sh022027): UCAR's real-time mirror first, JTWC's own best-track directory second."""
    year, basin = sid[-4:], sid[:2]
    errors = []
    for url in (UCAR_DECKS % (UCAR_BASIN.get(basin, basin), year, sid, sid),
                "%sbest-tracks/%s/%ss-b%s/b%s.dat" % (JTWC_PRODUCTS, year, year, basin, sid)):
        try:
            track = _parse_bdeck(_http(url, timeout=15)[2].decode("ascii", "replace"))
            if track:
                return track
            errors.append("empty")
        except Exception as e:
            errors.append(str(e))
    raise RuntimeError("; ".join(errors))


def _parse_bdeck(body):
    from datetime import datetime, timezone
    seen, out = set(), []
    for line in body.splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) < 11 or f[4] != "BEST" or f[2] in seen:
            continue
        try:
            t = datetime.strptime(f[2], "%Y%m%d%H").replace(tzinfo=timezone.utc).timestamp()
            lat = int(f[6][:-1]) / 10 * (1 if f[6][-1] == "N" else -1)
            lon = int(f[7][:-1]) / 10 * (1 if f[7][-1] == "E" else -1)
            wind = round(int(f[8]) * 1.852)
        except (ValueError, IndexError):
            continue
        seen.add(f[2])
        out.append([round(lon, 2), round(lat, 2), wind, round(t), 1 if f[10] in TROPICAL_TYPES else 0])
    out.sort(key=lambda p: p[3])
    return out


# JTWC publishes no cone of uncertainty. Its own 5-year mean track errors (nautical miles at each forecast hour,
# western Pacific; the other basins are close) give one: a circle of that radius round each forecast point,
# the circles joined into one outline - the way NHC's cone is built from its errors.
JTWC_ERROR_NM = {0: 0, 12: 38, 24: 60, 36: 85, 48: 110, 72: 160, 96: 220, 120: 290}


def estimated_cone(lon, lat, dots, hours):
    """A cone polygon as a flat [lon, lat, ...] ring from the forecast points `dots` ([lon, lat, wind], ...) at
    the forecast `hours` ([12, 24, ...]); empty with fewer than one forecast point."""
    import math
    if not dots:
        return []
    pts = [(lon, lat, 0)] + [(d[0], d[1], h) for d, h in zip(dots, hours)]
    left, right = [], []
    for i, (x, y, h) in enumerate(pts):
        keys = sorted(JTWC_ERROR_NM)
        lo = max([k for k in keys if k <= h] or [0]); hi = min([k for k in keys if k >= h] or [keys[-1]])
        r_nm = JTWC_ERROR_NM[lo] if hi == lo else JTWC_ERROR_NM[lo] + (JTWC_ERROR_NM[hi] - JTWC_ERROR_NM[lo]) * (h - lo) / (hi - lo)
        r = r_nm * 1.852 / 111.0                                   # degrees of latitude
        if i == 0:
            r = max(r, 0.15)
        nx, ny = pts[min(i + 1, len(pts) - 1)][:2]
        px, py = pts[max(i - 1, 0)][:2]
        dx, dy = (nx - px) * math.cos(math.radians(y)), ny - py       # the track's direction here, in km-ish units
        L = math.hypot(dx, dy) or 1
        ox, oy = -dy / L * r / math.cos(math.radians(y)), dx / L * r   # the perpendicular, back in degrees
        left.append((x + ox, y + oy)); right.append((x - ox, y - oy))
    # a rounded end at the last point
    x, y, h = pts[-1]
    r_nm = JTWC_ERROR_NM.get(h) or JTWC_ERROR_NM[max(k for k in JTWC_ERROR_NM if k <= h)]
    r = r_nm * 1.852 / 111.0
    ox, oy = left[-1][0] - x, left[-1][1] - y
    a0 = math.atan2(oy, ox / math.cos(math.radians(y)))
    cap = [(x + r * math.cos(a0 - math.pi * k / 8) / math.cos(math.radians(y)), y + r * math.sin(a0 - math.pi * k / 8)) for k in range(1, 8)]
    ring = left + cap + right[::-1]
    ring.append(ring[0])
    return [round(v, 2) for pt in ring for v in pt]



def fetch_storms_jtwc():
    """The active storms in JTWC's basins (western Pacific, Indian Ocean, southern hemisphere) in the same shape
    as fetch_storms_nhc(): wind now, forecast points with winds, the best track. The eastern/central Pacific
    items are skipped: NHC and CPHC are the authority there and already feed in."""
    import time
    now, storms, seen = time.time(), [], set()
    rss = _http(JTWC_RSS, timeout=15)[2].decode("utf-8", "replace")
    # every product link belongs to the storm last named before it in the text
    heads = [(m.start(), m) for m in JTWC_STORM_RE.finditer(rss)]
    for pm in JTWC_PRODUCT_RE.finditer(rss):
        basin, num, yy = pm.group(1).lower(), pm.group(2), pm.group(3)
        if basin not in JTWC_BASINS or (basin, num, yy) in seen:
            continue
        seen.add((basin, num, yy))
        head = None
        for pos, m in heads:
            if pos < pm.start():
                head = m
        if head is None or head.group(2)[:2] != num:
            continue
        name = (head.group(3) or "").strip().title() or head.group(2)
        sid = "%s%s20%s" % (basin, num, yy)
        try:
            text = _http(JTWC_PRODUCTS + "%s%s%sweb.txt" % (basin, num, yy), timeout=15)[2].decode("ascii", "replace")
            lon, lat, wind, issued, dots, hours = jtwc_warning(text, now)
        except Exception as e:
            storms.append({"_problems": ["JTWC %s - %s" % (head.group(2), e)]})
            continue
        kind, cat = storm_kind(wind, lat, lon)
        rec = {"id": sid, "name": name, "number": head.group(2), "kind": kind, "cat": cat, "wind": wind, "lat": lat, "lon": lon,
               "alert": "", "hours": round((now - issued) / 3600, 1), "source": "JTWC", "past": [], "cone": [], "dots": dots,
               "forecast": _split([(lon, lat)] + [(d[0], d[1]) for d in dots]) if dots else [], "cone_estimated": bool(dots)}
        try:
            rec["cone"] = _split([(cone[i], cone[i + 1]) for i in range(0, len(cone), 2)]) if (cone := estimated_cone(lon, lat, dots, hours)) else []
        except Exception:
            rec["cone"] = []
        try:
            rec["track"] = jtwc_best_track(sid)
        except Exception as e:
            rec["track"] = []
            rec["problem"] = "best track: %s" % e
        storms.append(rec)
    return storms


def chk_storms_jtwc():
    storms = [s for s in fetch_storms_jtwc() if "_problems" not in s]
    return "ok", "%d active in the western Pacific / Indian Ocean / southern hemisphere%s" % (
        len(storms), ": " + ", ".join("%s (%s%s)" % (s["name"], s["kind"].lower(), "" if s.get("track") else ", no best track") for s in storms) if storms else "")


def fetch_storms_merged(debug=False):
    """GDACS worldwide, with NHC's current intensity (and its track when GDACS has none) merged in where the
    two describe the same storm; NHC alone when GDACS is down. Raises only when neither answers."""
    storms, errors = [], []
    try:
        storms = fetch_storms(debug)
    except Exception as e:
        errors.append("GDACS - %s" % e)
    try:
        nhc = fetch_storms_nhc()
    except Exception as e:
        nhc = []
        errors.append("NHC - %s" % e)
    try:                                                # JTWC for the basins NHC does not cover; a storm it could not
        jt = fetch_storms_jtwc()                        # read is a problem, not a failure of the feed
        errors += [p for st in jt if "_problems" in st for p in st["_problems"]]
        nhc += [st for st in jt if "_problems" not in st]
    except Exception as e:
        errors.append("JTWC - %s" % e)
    if not storms and not nhc:
        raise RuntimeError("; ".join(errors))
    for st in storms:
        st["ids"] = ["gdacs:%s" % st["id"]] if st.get("id") else []
    for n in nhc:
        n["ids"] = ["%s:%s" % (n.get("source", "nhc").lower(), n["id"])] if n.get("id") else []
    by_name = {st["name"].lower(): st for st in storms}
    matched = set()
    for n in nhc:
        st = by_name.get(n["name"].lower())
        if st is None:                                  # the two feeds rename a storm at different moments ("Twenty-E" ->
            best, best_km = None, 250                   # "Rachel"): the same storm is the one within 250 km that no name matched
            for cand in storms:
                if id(cand) in matched or cand.get("source", "").endswith(("NHC", "JTWC")):
                    continue
                km = haversine_km(cand["lat"], cand["lon"], n["lat"], n["lon"])
                if km < best_km:
                    best, best_km = cand, km
            st = best
        if st is None:
            storms.append(n)
            continue
        matched.add(id(st))
        st["ids"] = list(dict.fromkeys((st.get("ids") or []) + (n.get("ids") or [])))
        if st["name"].lower() != n["name"].lower():
            st["was_named"] = st["name"]                # the centre's name is the official one
            st["name"] = n["name"]
        st.update(wind=n["wind"], kind=n["kind"], cat=n["cat"], wind_is_peak=False, source=(st.get("source") or "GDACS") + "+" + n.get("source", "NHC"))
        if n.get("hours") is not None and (st.get("hours") is None or n["hours"] < st["hours"]):
            st["hours"] = n["hours"]
        for k in ("forecast", "cone", "dots", "track"):
            if not st.get(k) and n.get(k):
                st[k] = n[k]
        if n.get("dots") and n.get("source") == "JTWC":   # JTWC's forecast points carry winds; GDACS's do not
            st["dots"], st["forecast"] = n["dots"], n["forecast"]
            if not st.get("cone") or n.get("cone"):
                st["cone"], st["cone_estimated"] = n.get("cone", []), True
    if errors:
        storms.append({"_problems": errors})      # carried to the caller, stripped below
    return storms


def cmd_storms(args):
    note, storms = "", []
    data, stale_h, err = last_good("storms", lambda: fetch_storms_merged(args.table))
    problems = []
    if data is not None:
        storms = [st for st in data if "_problems" not in st]
        problems = [p for st in data if "_problems" in st for p in st["_problems"]]
    if err:
        note = stale_note("Storms", stale_h, err, args.stale)
    elif problems and not any("GDACS" in p for p in problems):
        pass                                        # NHC only failed: GDACS covers everything, nothing to say
    elif problems:
        note = "Storms: GDACS unreachable, showing NHC (Atlantic and Pacific only)" if args.stale <= 0 else ""
    try:
        storms = remember_events("storm", storms, lambda st: st["name"].lower(), args.keep,
                                 trail_of=lambda st: [round(st["lon"], 2), round(st["lat"], 2), None if st.get("wind_is_peak") else st.get("wind"), 1],
                                 ident_of=lambda st: st.get("ids") or [])
    except Exception as e:
        note = note or "Storms: %s" % e
    import time
    now = time.time()
    for st in storms:
        # The track with intensity: NHC's best track where it exists, otherwise the breadcrumbs this wallpaper
        # has collected itself since it first saw the storm (any basin). It replaces the plain past-track line.
        trail = st.pop("trail", None) or []
        if not st.get("track") and trail:
            st["track"] = [[p[1], p[2], p[3], p[0], p[4] if len(p) > 4 else 1] for p in trail]
        track = st.get("track") or []
        if track:
            st["since_hours"] = round((now - track[0][3]) / 3600, 1)
            pts = [(p[0], p[1]) for p in track]
            if not st.get("gone"):
                pts.append((st["lon"], st["lat"]))
            if len(pts) >= 2:
                st["past"] = _split(pts)
    impacted = []                                   # after the track: what each storm crossed needs its past fixes
    try:
        impacted = storm_impacts(storms)
        _remember_impacts(storms)
    except Exception as e:
        print("impacts: %s" % e, file=sys.stderr)
    if args.table:
        print(note or "%d active tropical cyclones (GDACS)" % len(storms))
        for st in storms:
            print("  %-12s %-20s cat %d  %4d km/h  at %.1f, %.1f  past %d pts, forecast %d pts, cone %d rings  first seen %s%s  %s  %s" % (
                st["name"], st["kind"], st["cat"], st["wind"], st["lat"], st["lon"], sum(len(p) // 2 for p in st["past"]),
                sum(len(p) // 2 for p in st["forecast"]), len(st["cone"]), "%.0f h ago" % st["first_hours"] if st.get("first_hours") is not None else "unknown",
                "  GONE (last advisory %.0f h ago)" % st["hours"] if st.get("gone") else "", st.get("problem", ""),
                ("THREATENS " + impact_text(st["impact"])) if st.get("impact") else ""))
            for k, n in sorted(st.get("classes", {}).items()):
                print("        %3d x %s" % (n, k))
    else:
        emit({"storms": storms, "impacted": impacted, "note": note})


def chk_storms():
    storms = fetch_storms()
    names = ", ".join("%s (%s)" % (st["name"], st["kind"].lower()) for st in storms)
    return "ok", "%d active tropical cyclones%s" % (len(storms), ": " + names if names else "")
