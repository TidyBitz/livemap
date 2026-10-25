"""When the ISS and Tiangong pass over the home place, and whether it can be seen.

A pass is visible when three things hold at once: the station is above the horizon, the observer's sky is
dark (sun more than 6 degrees down: civil twilight or later), and the station itself is still in sunlight -
it has no light of its own, you see the sun on it. That is why the good passes come an hour or two after
dusk and before dawn, and why a daytime pass is invisible. Everything here comes from the orbital elements
the wallpaper already keeps (CelesTrak) and the sun's position; nothing is fetched.

Cloud cover over the home place is read from the wallpaper's own cloud image where it is present, as a hint
beside the pass - it is coarse and hours old, so it never hides a pass.
"""
import json
import math
import time

from .common import DATA
from .space import SATS, fetch_tles, parse_tle, propagate

PASSES = DATA / "passes.json"
RE_KM = 6371.0
STEP = 10                                     # seconds between samples while searching
DAYS = 3                                      # how far ahead to look
MIN_PEAK = 10                                 # degrees: a pass whose highest point is lower is not worth listing


def sun_position(t):
    """Sub-solar latitude and longitude at unix time t (the same formulas as geo.js's sun())."""
    import datetime
    d = datetime.datetime.utcfromtimestamp(t)
    start = datetime.datetime(d.year, 1, 1)
    doy = (d - start).days + 1
    hours = d.hour + d.minute / 60 + d.second / 3600
    g = 2 * math.pi / 365 * (doy - 1 + (hours - 12) / 24)
    eot = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
            - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
    lon = -((hours * 60 + eot) / 4 - 180)
    lon = ((lon + 180) % 360 + 360) % 360 - 180
    return math.degrees(decl), lon


def elevation_of_sun(lat, lon, t):
    slat, slon = sun_position(t)
    e = (math.sin(math.radians(lat)) * math.sin(math.radians(slat))
         + math.cos(math.radians(lat)) * math.cos(math.radians(slat)) * math.cos(math.radians(lon - slon)))
    return math.degrees(math.asin(max(-1, min(1, e))))


def look_angles(lat, lon, slat, slon, alt):
    """Elevation and azimuth (degrees) of a satellite at (slat, slon, alt km) seen from (lat, lon), and its range."""
    la, lo, sa, so = map(math.radians, (lat, lon, slat, slon))
    rs = RE_KM + alt
    # observer and satellite in Earth-fixed cartesian
    ox, oy, oz = RE_KM * math.cos(la) * math.cos(lo), RE_KM * math.cos(la) * math.sin(lo), RE_KM * math.sin(la)
    sx, sy, sz = rs * math.cos(sa) * math.cos(so), rs * math.cos(sa) * math.sin(so), rs * math.sin(sa)
    dx, dy, dz = sx - ox, sy - oy, sz - oz
    # to the observer's local east / north / up
    east = -math.sin(lo) * dx + math.cos(lo) * dy
    north = -math.sin(la) * math.cos(lo) * dx - math.sin(la) * math.sin(lo) * dy + math.cos(la) * dz
    up = math.cos(la) * math.cos(lo) * dx + math.cos(la) * math.sin(lo) * dy + math.sin(la) * dz
    rng = math.sqrt(dx * dx + dy * dy + dz * dz)
    el = math.degrees(math.asin(up / rng))
    az = (math.degrees(math.atan2(east, north)) + 360) % 360
    return el, az, rng


def satellite_sunlit(slat, slon, alt, t):
    """Is the satellite in sunlight? It is in shadow when it is on the night side and inside the Earth's cylinder."""
    sun_lat, sun_lon = sun_position(t)
    # angle between the satellite's position vector and the sun direction
    a = (math.sin(math.radians(slat)) * math.sin(math.radians(sun_lat))
         + math.cos(math.radians(slat)) * math.cos(math.radians(sun_lat)) * math.cos(math.radians(slon - sun_lon)))
    a = max(-1, min(1, a))
    if a >= 0:
        return True                                        # on the day side
    rs = RE_KM + alt
    return rs * math.sqrt(1 - a * a) > RE_KM               # night side, but outside the shadow cylinder


def compass(az):
    return ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"][int((az + 11.25) // 22.5) % 16]


def find_passes(el, lat, lon, start, days=DAYS, step=STEP):
    """Every pass above MIN_PEAK in the window: [{rise, peak, set, max_el, rise_az, set_az, visible, lit_seconds}]."""
    out, t, end = [], start, start + days * 86400
    above, cur = False, None
    while t < end:
        slat, slon, alt = propagate(el, t)
        e, az, _ = look_angles(lat, lon, slat, slon, alt)
        if e > 0 and not above:
            above, cur = True, {"rise": t, "rise_az": az, "max_el": e, "peak": t, "peak_az": az, "lit": 0, "dark_and_lit": 0}
        if above:
            dark = elevation_of_sun(lat, lon, t) < -6
            lit = satellite_sunlit(slat, slon, alt, t)
            if lit:
                cur["lit"] += step
            if dark and lit:
                cur["dark_and_lit"] += step
            if e > cur["max_el"]:
                cur["max_el"], cur["peak"], cur["peak_az"] = e, t, az
            if e <= 0:
                above = False
                cur["set"], cur["set_az"] = t, az
                if cur["max_el"] >= MIN_PEAK:
                    cur["visible"] = cur["dark_and_lit"] >= 30            # at least half a minute you could see it
                    cur["duration"] = cur["set"] - cur["rise"]
                    out.append(cur)
                cur = None
        # coarse steps while far below the horizon: the station cannot rise within a minute from -30 degrees
        t += step if e > -15 else 60
    return out


def cloud_over(lat, lon):
    """Cloud cover over a place from the wallpaper's cloud image (0..100), or None when there is none."""
    from .clouds import CLOUDS_RAW, _png_read
    try:
        w, h, ch, px = _png_read(CLOUDS_RAW.read_bytes())
    except Exception:
        return None
    x = int((lon + 180) / 360 * w) % w
    y = min(h - 1, max(0, int((90 - lat) / 180 * h)))
    tot, n = 0, 0
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            yy, xx = min(h - 1, max(0, y + dy)), (x + dx) % w
            tot += px[(yy * w + xx) * ch]; n += 1
    return round(tot / n / 255 * 100)


# the stations are the worthwhile targets: Tiangong (41.5 degrees inclination, about as bright as a bright star)
# covers the same latitudes; Hubble (28.5 degrees, dim) stays low in a mid-latitude sky and is not predicted
PASS_SATS = ("ISS", "Tiangong")


def passes_for(lat, lon, now=None, which=PASS_SATS, days=DAYS):
    now = now if now is not None else time.time()
    tles = fetch_tles()
    out = []
    for short, catnr, longname in SATS:
        if short not in which or short not in tles:
            continue
        el = parse_tle(tles[short][1], tles[short][2])
        for p in find_passes(el, lat, lon, now - 600, days):
            out.append({"sat": short, "name": longname, "rise": round(p["rise"]), "peak": round(p["peak"]), "set": round(p["set"]),
                        "duration": round(p["duration"]), "max_el": round(p["max_el"]), "rise_dir": compass(p["rise_az"]),
                        "peak_dir": compass(p["peak_az"]), "set_dir": compass(p["set_az"]), "visible": p["visible"],
                        "visible_seconds": p["dark_and_lit"]})
    out.sort(key=lambda p: p["rise"])
    return out


def cmd_passes(args):
    """`passes --lat L --lon L [--days 3] [--all] [--table]`: the station's passes over a place, visible ones
    unless --all. Cached for an hour per place (the elements change slowly)."""
    from .common import emit
    try:
        lat, lon = float(args.lat), float(args.lon)
    except (TypeError, ValueError):
        emit({"error": "a home place is needed: --lat and --lon (Essentials > Where you are)"}); return
    now = time.time()
    key = "%.2f,%.2f,%d" % (lat, lon, args.days)
    try:
        c = json.loads(PASSES.read_text(encoding="utf-8"))
        if c.get("key") == key and now - c.get("at", 0) < 3600:
            passes = c["passes"]
        else:
            raise ValueError
    except (OSError, ValueError, KeyError):
        passes = passes_for(lat, lon, now, days=args.days)
        try:
            PASSES.parent.mkdir(parents=True, exist_ok=True)
            PASSES.write_text(json.dumps({"key": key, "at": now, "passes": passes}), encoding="utf-8")
        except OSError:
            pass
    passes = [p for p in passes if p["set"] > now and (args.all or p["visible"])]
    cloud = cloud_over(lat, lon)
    if args.table:
        print("%d passes over %.2f, %.2f in the next %d days%s" % (len(passes), lat, lon, args.days, " · cloud now %d %%" % cloud if cloud is not None else ""))
        for p in passes:
            print("  %s  %s  %s -> %s  max %2d° %s  %d s%s" % (time.strftime("%a %d %b %H:%M", time.localtime(p["rise"])), p["sat"], p["rise_dir"], p["set_dir"],
                                                           p["max_el"], p["peak_dir"], p["duration"], "  VISIBLE %d s" % p["visible_seconds"] if p["visible"] else ""))
    else:
        emit({"passes": passes, "cloud": cloud, "lat": lat, "lon": lon, "at": now})
