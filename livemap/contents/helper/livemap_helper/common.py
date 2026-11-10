"""Shared by every module: paths, user agent, HTTP with limits, caches, event memory, geometry helpers."""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
import socket


_getaddrinfo = socket.getaddrinfo


socket.getaddrinfo = lambda *a, **k: sorted(_getaddrinfo(*a, **k), key=lambda r: r[0] != socket.AF_INET)


DATA = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "livemap"


GEOIP = DATA / "geoip.mmdb"


NASA = "https://assets.science.nasa.gov/content/dam/science/esd/eo/images"


MONTHS = ["january", "february", "march", "april", "may", "june", "july",
          "august", "september", "october", "november", "december"]


NIGHT_URL = NASA + "/imagerecords/144000/144898/BlackMarble_2016_3km.jpg"


VERSION = "0.48"


UA = {"User-Agent": "livemap-wallpaper/" + VERSION + " (github.com/TidyBitz/livemap)"}   # identifiable, as the APIs ask


NE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"


BORDERS = DATA / "borders"


NE_FILES = ["ne_110m_coastline", "ne_110m_admin_0_boundary_lines_land", "ne_110m_admin_0_countries", "ne_50m_admin_0_countries",
            "ne_50m_coastline", "ne_50m_admin_0_boundary_lines_land", "ne_50m_admin_1_states_provinces_lines",
            "ne_10m_time_zones", "ne_10m_populated_places_simple",    # time zone polygons; cities, capitals, home search
            "ne_10m_admin_1_label_points",                              # state and province names (label points with a rank)
            "ne_110m_rivers_lake_centerlines", "ne_50m_rivers_lake_centerlines",   # major rivers
            "ne_110m_lakes", "ne_50m_lakes", "ne_50m_geography_marine_polys"]       # lakes; oceans, seas, gulfs and bays (names)


# Tectonic plate boundaries: Peter Bird's PB2002 model (2003), GeoJSON conversion by Hugo Ahlenius (Nordpil),
# Open Data Commons Attribution licence. Downloaded with the border data, drawn under the Earthquakes settings.
PLATES_URL = "https://raw.githubusercontent.com/fraxen/tectonicplates/master/GeoJSON/PB2002_boundaries.json"


PLATES_FILE = "PB2002_boundaries"                                     # stored next to the Natural Earth files


# -------------------------------------------------------------- borders -----
def _lines(name, step):
    """Polylines of one Natural Earth layer as flat [lon, lat, lon, lat, ...] lists, 0.01 deg precision.
    `step` thins the detailed layers: a point is dropped if it is closer than that to the last one kept."""
    f = BORDERS / (name + ".geojson")
    if not f.exists():
        return None
    out = []
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        g = feat.get("geometry") or {}
        kind, c = g.get("type"), g.get("coordinates") or []
        parts = [c] if kind == "LineString" else c if kind in ("MultiLineString", "Polygon") else \
                [ring for poly in c for ring in poly] if kind == "MultiPolygon" else []
        for part in parts:
            flat, last = [], None
            for pt in part:
                x, y = round(pt[0], 2), round(pt[1], 2)
                if last is None or abs(x - last[0]) >= step or abs(y - last[1]) >= step or pt is part[-1]:
                    flat += [x, y]
                    last = (x, y)
            if len(flat) >= 4:
                out.append(flat)
    return out


def _ring_area(ring):
    a = 0.0
    for i in range(len(ring) - 1):
        a += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1]
    return abs(a) / 2


def _spans_at(ring, lat):
    """The horizontal spans (lon pairs) where the line of latitude `lat` is inside the ring."""
    xs = []
    for i in range(len(ring) - 1):
        (x1, y1), (x2, y2) = ring[i][:2], ring[i + 1][:2]
        if (y1 <= lat < y2) or (y2 <= lat < y1):
            xs.append(x1 + (lat - y1) * (x2 - x1) / (y2 - y1))
    xs.sort()
    return [(xs[i], xs[i + 1]) for i in range(0, len(xs) - 1, 2)]


def _in_ring(lon, lat, ring):
    """Ray casting on a flat [lon, lat, ...] ring. Plate carree is fine at a cone's size away from the poles."""
    n, inside = len(ring) // 2, False
    j = n - 1
    for i in range(n):
        xi, yi, xj, yj = ring[2 * i], ring[2 * i + 1], ring[2 * j], ring[2 * j + 1]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def _near_path(lon, lat, pts, km):
    """True when (lon, lat) is within km of the polyline pts [(lon, lat), ...] - points first, then each segment
    sampled every ~25 km, so a facility a storm passed between two fixes still counts."""
    if abs(lat - pts[0][1]) > 20 and all(abs(lat - p[1]) > 20 for p in pts):
        return False
    for i, p in enumerate(pts):
        if haversine_km(lat, lon, p[1], p[0]) <= km:
            return True
        if i:
            q = pts[i - 1]
            seg = haversine_km(q[1], q[0], p[1], p[0])
            n = int(seg // 25)
            for j in range(1, n + 1):
                t = j / (n + 1)
                if haversine_km(lat, lon, q[1] + (p[1] - q[1]) * t, q[0] + (p[0] - q[0]) * t) <= km:
                    return True
    return False


# --------------------------------------------------------- event memory -----
EVENTS = DATA / "events.json"


HISTORY = DATA / "history.json"      # every event the widget's feed has shown, by key, for the widget's past-events view


HISTORY_DAYS = 90                    # older entries are dropped on the next write


def remember_events(kind, items, key_of, keep_hours, now=None, sig_of=None, raised_of=None, trail_of=None, ident_of=None):
    """Track first/last sighting of each item of `kind`. Adds first_hours (since this machine first saw it) and
    gone=False to every item; appends items that dropped out of the feed within keep_hours as gone=True with
    hours = time since last seen. With sig_of, a change of the item's signature (an alert level, a status)
    counts as newly reported again: first_hours restarts and changed_from / changed_hours say what it was.
    With raised_of (True while an item is in a raised state, e.g. an alert level above green), raised_hours says
    how long it has been raised as seen from here (None when it already was at the first look).
    Returns the combined list."""
    import time
    now = now if now is not None else time.time()
    try:
        mem = json.loads(EVENTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    if mem.get("_v") not in (2, 3, 4, 5, 6):                # 0.19 pretended a baseline was "30 days ago"; now it is simply unknown
        for b in mem.values():
            if isinstance(b, dict):
                for e in b.values():
                    if isinstance(e, dict):
                        e["first"] = None
        mem["_v"] = 2
    if mem.get("_v") == 2:                         # 0.20 keyed volcanoes by plain lower-case name: merge old and new entries
        old_v = mem.get("volcano") or {}
        merged = {}
        for k, e in old_v.items():
            if not isinstance(e, dict):
                continue
            key = _plain(k)
            if key in merged:
                m = merged[key]
                m["first"] = None if m.get("first") is None or e.get("first") is None else min(m["first"], e["first"])
                m["last"] = max(m.get("last", 0), e.get("last", 0))
                if e.get("item") and not m.get("item"):
                    m["item"] = e["item"]
            else:
                merged[key] = dict(e)
        for e in merged.values():
            e.pop("changed", None); e.pop("was", None)
        if old_v:
            mem["volcano"] = merged
        mem["_v"] = 3
    if mem.get("_v") in (3, 4):                    # 0.28: the volcano signature is the level (yellow / orange / red)
        for e in (mem.get("volcano") or {}).values():
            if isinstance(e, dict) and isinstance(e.get("sig"), str):
                sig, st = e["sig"].split("/") + [""] if "/" in e["sig"] else [e["sig"], (e.get("item") or {}).get("status", "")]
                e["sig"] = "red" if sig == "red" else "orange" if sig == "orange" or st == "new" else "yellow"
                e.pop("changed", None); e.pop("was", None)
        mem["_v"] = 5
    if mem.get("_v") == 5:                         # 0.32: storms are keyed by name (the same storm from GDACS or NHC)
        old_s = mem.get("storm") or {}
        mem["storm"] = {str((e.get("item") or {}).get("name", k)).lower(): e for k, e in old_s.items() if isinstance(e, dict)}
        mem["_v"] = 6
    bucket = mem.setdefault(kind, {})
    baseline = not bucket                          # first look ever: what is there now was there before we looked
    present = set()
    if ident_of:                                   # entries from before ids were kept: derive them from the stored item
        for oe in bucket.values():                 # (a GDACS id is a number, an NHC id looks like AL092026)
            if isinstance(oe, dict) and "ids" not in oe and (oe.get("item") or {}).get("id"):
                iid = str(oe["item"]["id"])
                oe["ids"] = [("nhc:%s" if (oe["item"].get("source") == "NHC" or not iid.isdigit()) else "gdacs:%s") % iid]
    for it in items:
        k = str(key_of(it))
        present.add(k)
        old = bucket.get(k)
        if ident_of:                               # the same thing under a new key (a storm renamed on upgrade): carry
            ids = [str(i) for i in (ident_of(it) or [])]   # its memory over instead of ageing the old name out as gone
            for ok, oe in list(bucket.items()):
                if ok == k or not isinstance(oe, dict) or not set(oe.get("ids") or []) & set(ids):
                    continue
                if old is None:
                    old = bucket[k] = bucket.pop(ok)
                else:                              # both exist (the new name was seen before the link was known): merge
                    oe_first, o_first = oe.get("first"), old.get("first")
                    old["first"] = None if oe_first is None or o_first is None else min(oe_first, o_first)
                    if len(oe.get("trail") or []) > len(old.get("trail") or []):
                        old["trail"] = oe["trail"]
                    bucket.pop(ok)
                it["was_named"] = it.get("was_named") or ok
            if old is None:
                old = bucket[k] = {"first": None if baseline else now}
            old["ids"] = list(dict.fromkeys((old.get("ids") or []) + ids))[-8:]
        if old is None:
            old = bucket[k] = {"first": None if baseline else now}
        sig, prev_sig = (sig_of(it) if sig_of else None), old.get("sig")
        if sig is not None:
            if prev_sig is not None and prev_sig != sig:        # the status changed: that is news
                old["first"], old["changed"], old["was"] = now, now, prev_sig
            old["sig"] = sig
        if old.get("changed") is not None:
            it["changed_from"] = old.get("was", "")
            it["changed_hours"] = round((now - old["changed"]) / 3600, 2)
        if raised_of:
            if raised_of(it):
                if "raised" not in old:                         # unknown if it already was raised when we first looked
                    old["raised"] = now if prev_sig is not None and prev_sig != sig else None
                it["raised_hours"] = None if old["raised"] is None else round((now - old["raised"]) / 3600, 2)
            else:
                old.pop("raised", None)
        if trail_of:                                            # breadcrumbs: where it was, as seen from here
            p = trail_of(it)
            tr = old.setdefault("trail", [])
            if p and (not tr or abs(tr[-1][1] - p[0]) > 0.05 or abs(tr[-1][2] - p[1]) > 0.05
                      or (now - tr[-1][0] > 5400 and tr[-1][3] != p[2])):
                tr.append([round(now)] + list(p))
                del tr[:-400]
            it["trail"] = tr
        old["last"] = now
        old["item"] = {kk: vv for kk, vv in it.items() if kk not in ("past", "forecast", "cone", "dots", "track", "trail")}
        it["first_hours"] = None if old["first"] is None else round((now - old["first"]) / 3600, 2)
        it["gone"] = False
    out = list(items)
    for k, old in list(bucket.items()):
        age_h = (now - old.get("last", 0)) / 3600
        if k in present:
            continue
        if age_h > keep_hours or "item" not in old:
            del bucket[k]
            continue
        ghost = dict(old["item"])
        ghost.update(first_hours=None if old["first"] is None else round((now - old["first"]) / 3600, 2), gone=True, hours=round(age_h, 1),
                     past=[], forecast=[], cone=[], dots=[], trail=old.get("trail") or [])
        out.append(ghost)
    try:
        EVENTS.parent.mkdir(parents=True, exist_ok=True)
        tmp = EVENTS.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps(mem), encoding="utf-8")
        tmp.replace(EVENTS)
    except OSError:
        pass
    return out


def haversine_km(lat1, lon1, lat2, lon2):
    import math
    p1, p2, dl = math.radians(lat1), math.radians(lat2), math.radians(lon2 - lon1)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(a))


def storm_kind(wind_kmh, lat, lon):
    """(type, category) from 1-minute sustained wind, Saffir-Simpson; the name of the thing depends on the ocean."""
    big = "Typhoon" if lat > 0 and 100 <= lon <= 180 else "Hurricane" if lat > 0 and (lon < -20 or lon > 180) else "Cyclone"
    if wind_kmh < 63:
        return "Tropical depression", 0
    if wind_kmh < 119:
        return "Tropical storm", 0
    for cat, top in ((1, 154), (2, 178), (3, 209), (4, 252)):
        if wind_kmh < top:
            return big, cat
    return big, 5


def _split(path):
    """Break a [(lon, lat), ...] path where it jumps across the antimeridian; return flat lists."""
    out, cur = [], []
    for lon, lat in path:
        if cur and abs(lon - cur[-2]) > 180:
            out.append(cur)
            cur = []
        cur += [round(lon, 2), round(lat, 2)]
    out.append(cur)
    return [c for c in out if len(c) >= 4]


def _places_index(min_pop=50000):
    """Populated places (Natural Earth, already downloaded for the home search) with at least min_pop people,
    bucketed by whole degree so a cluster only looks at its neighbourhood. None when the file is missing."""
    f = BORDERS / "ne_10m_populated_places_simple.geojson"
    if not f.exists():
        return None
    idx = {}
    try:
        for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
            p = feat.get("properties") or {}
            pop = int(p.get("pop_max") or 0)
            if pop < min_pop:
                continue
            c = (feat.get("geometry") or {}).get("coordinates") or [p.get("longitude"), p.get("latitude")]
            lat, lon = float(c[1]), float(c[0])
            idx.setdefault((int(lat // 1), int(lon // 1)), []).append((lat, lon, pop, str(p.get("name") or "")))
    except (OSError, ValueError, TypeError, KeyError):
        return None
    return idx


NWS_UA = dict(UA, Accept="application/geo+json")


def _nws_get(url, timeout=12):
    """api.weather.gov wants a GeoJSON Accept header and an identifiable user agent."""
    return fetch_json(url, timeout=timeout, headers=NWS_UA)


def _plain(t):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFKD", t) if not unicodedata.combining(c)).lower()


# ---------------------------------------------------------------- power -----
def on_battery(root="/sys/class/power_supply"):
    """True if a system battery is discharging. Batteries of mice, headsets etc. (scope=Device) are ignored."""
    try:
        for d in Path(root).iterdir():
            read = lambda n: (d / n).read_text().strip() if (d / n).exists() else ""
            if read("type") == "Battery" and read("scope") != "Device" and read("status") == "Discharging":
                return True
    except OSError:
        pass
    return False


# Last good data per feed. A fetch that fails hands back what the previous successful fetch returned, with
# its age, so a layer keeps drawing and only says something once the data is genuinely stale.
def last_good(name, fetch):
    """(data, stale_hours, error): fresh data with 0 h, or the cached data and its age when fetch() raises.
    With nothing cached either, (None, None, error)."""
    import time
    f = DATA / ("last-%s.json" % name)
    try:
        data = fetch()
        try:
            f.parent.mkdir(parents=True, exist_ok=True)
            tmp = f.with_suffix(".tmp%d" % os.getpid())
            tmp.write_text(json.dumps({"at": time.time(), "data": data}), encoding="utf-8")
            tmp.replace(f)
        except (OSError, TypeError, ValueError):
            pass
        return data, 0.0, ""
    except Exception as e:
        err = "%s" % e
        try:
            c = json.loads(f.read_text(encoding="utf-8"))
            return c["data"], round((time.time() - c.get("at", 0)) / 3600, 1), err
        except (OSError, ValueError, KeyError):
            return None, None, err


def stale_note(what, stale_h, err, limit_h):
    """The desktop notice for a failed fetch: nothing while the last good data is younger than limit_h."""
    if stale_h is None:
        return "%s: %s" % (what, err)
    if stale_h >= limit_h:
        return "%s: no update for %s (%s)" % (what, _age(int(stale_h * 3600)), err[:80])
    return ""


LOAD_STATE = DATA / "load-state.json"


MODE = DATA / "mode.json"          # written by the companion widget: {"pause": bool, "plain": bool, "hide": [...],


LAYERS = DATA / "layers.json"


LAYER_NAMES = ("quakes", "volcanoes", "storms", "fires", "floods", "tsunami", "alerts", "maritime", "launches", "sats", "network")


def read_layers():
    """The event layers the wallpaper has switched on (written by the wallpaper itself through `power --layers`),
    or None when no wallpaper has said yet. The widget can hide the kinds the map does not show."""
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return [l for l in d.get("shown", []) if l in LAYER_NAMES] if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def read_units():
    """[distance, wind, clock12, temp] as the wallpaper's Units choices (distance 0 km, 1 mi, 2 nmi; wind 0 km/h,
    1 mph, 2 knots; clock 0 24-hour, 1 12-hour; temperature 0 follows the distance unit, 1 °C, 2 °F), for the widget's
    feed and the Sky tab; [0, 0] until the wallpaper has said (older wallpapers send two)."""
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        u = d.get("units") if isinstance(d, dict) else None
        if isinstance(u, list) and len(u) >= 2:
            return [int(x) for x in u[:4]]        # [distance, wind] and, since 0.49, [.., clock12, temp]
        return [0, 0]
    except (OSError, ValueError, TypeError):
        return [0, 0]


def read_fire_focus():
    """The wallpaper's "Wildfire focus" (0 everything, 1 near people, 2 orange and red events only), for the feed."""
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return int(d.get("fire_focus", 1)) if isinstance(d, dict) else 1
    except (OSError, ValueError, TypeError):
        return 1


def read_flood_level():
    """The wallpaper's flood filter (0 all levels, 1 orange and red, 2 red only), for the feed."""
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return int(d.get("flood_level", 1)) if isinstance(d, dict) else 1
    except (OSError, ValueError, TypeError):
        return 1


def read_layers_flag(name, default=False):
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return bool(d.get(name, default)) if isinstance(d, dict) else default
    except (OSError, ValueError, TypeError):
        return default


def read_fire_sources():
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return int(d.get("fire_sources", 29)) if isinstance(d, dict) else 29
    except (OSError, ValueError, TypeError):
        return 29


def read_layers_int(key, default):
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return int(d.get(key, default)) if isinstance(d, dict) else default
    except (OSError, ValueError, TypeError):
        return default


def read_layers_list(key):
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        v = d.get(key) if isinstance(d, dict) else None
        return [str(x) for x in v] if isinstance(v, list) else []
    except (OSError, ValueError):
        return []


def read_layers_str(key, default=""):
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        v = d.get(key) if isinstance(d, dict) else None
        return str(v) if v is not None else default
    except (OSError, ValueError):
        return default


def write_layers(shown, units=None, fire_focus=None, flood_level=None, nws_each=None, fire_sources=None, flood_sources=None, quake_sources=None,
                 home=None, passes=None, saving=None, why=None, home_name=None, maritime_days=None, pulsing=None, fps=None):
    shown = [l for l in shown.split(",") if l in LAYER_NAMES]
    if pulsing is not None:
        pulsing = [l for l in pulsing.split(",") if l in LAYER_NAMES]
    if why is not None:
        why = why.strip()[:120]
    if units is not None:
        try:
            units = [max(0, min(2, int(x))) for x in units.split(",")][:4]   # distance, wind, clock (0 24 h, 1 12 h), temperature (0 follow distance, 1 °C, 2 °F)
        except ValueError:
            units = None
    if fire_focus is not None:
        fire_focus = max(0, min(2, int(fire_focus)))
    if flood_level is not None:
        flood_level = max(0, min(2, int(flood_level)))
    if read_layers() == shown and (units is None or read_units() == units) and (fire_focus is None or read_fire_focus() == fire_focus) \
            and (flood_level is None or read_flood_level() == flood_level) and (nws_each is None or read_layers_flag("nws_each") == bool(nws_each)) \
            and (fire_sources is None or read_fire_sources() == int(fire_sources)) and (flood_sources is None or read_layers_int("flood_sources", 15) == int(flood_sources)) \
            and (quake_sources is None or read_layers_int("quake_sources", 3) == int(quake_sources)) \
            and (home is None or read_layers_str("home") == home) and (passes is None or read_layers_int("passes", 0) == int(passes)) \
            and (saving is None or read_layers_int("saving", 0) == int(saving)) and (why is None or read_layers_str("why") == why) \
            and (home_name is None or read_layers_str("home_name") == home_name) \
            and (maritime_days is None or read_layers_int("maritime_days", 14) == int(maritime_days)) \
            and (pulsing is None or read_layers_list("pulsing") == pulsing) and (fps is None or read_layers_int("fps", 0) == int(fps)):
        return
    try:
        LAYERS.parent.mkdir(parents=True, exist_ok=True)
        tmp = LAYERS.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps({"shown": shown, "units": units if units is not None else read_units(),
                                   "fire_focus": fire_focus if fire_focus is not None else read_fire_focus(),
                                   "flood_level": flood_level if flood_level is not None else read_flood_level(),
                                   "nws_each": bool(nws_each) if nws_each is not None else read_layers_flag("nws_each"),
                                   "fire_sources": int(fire_sources) if fire_sources is not None else read_fire_sources(),
                                   "flood_sources": int(flood_sources) if flood_sources is not None else read_layers_int("flood_sources", 15),
                                   "quake_sources": int(quake_sources) if quake_sources is not None else read_layers_int("quake_sources", 3),
                                   "home": home if home is not None else read_layers_str("home"),          # "lat,lon" of the home place
                                   "home_name": home_name if home_name is not None else read_layers_str("home_name"),
                                   "passes": int(passes) if passes is not None else read_layers_int("passes", 0),   # 0 off, 1 visible passes, 2 every pass
                                   # what the wallpaper is holding back and why (0 nothing, 1 animations paused, 2 live layers off):
                                   # the widget and the Status check say so, the map itself no longer does
                                   "saving": int(saving) if saving is not None else read_layers_int("saving", 0),
                                   "why": why if why is not None else read_layers_str("why"),
                                   "maritime_days": int(maritime_days) if maritime_days is not None else read_layers_int("maritime_days", 14),
                                   # the layers keeping the pulse clock running (every tick redraws the whole screen) and the rate: the first
                                   # thing to look at when plasmashell is busy; Status > Power and load and the widget's Map controls say it
                                   "pulsing": pulsing if pulsing is not None else read_layers_list("pulsing"),
                                   "fps": int(fps) if fps is not None else read_layers_int("fps", 0),   # the window the maritime layer shows; the widget lists the same
                                   "at": int(time.time())}), encoding="utf-8")
        tmp.replace(LAYERS)
    except OSError:
        pass


def wind_text(kmh, u):
    return ("%d mph" % round(kmh * 0.621371)) if u == 1 else ("%d kt" % round(kmh / 1.852)) if u == 2 else "%d km/h" % round(kmh)


def dist_text(km, u, digits=0):
    """A length in the wallpaper's distance unit (0 km, 1 miles, 2 nautical miles)."""
    v, unit = (km * 0.621371, "mi") if u == 1 else (km / 1.852, "nmi") if u == 2 else (km, "km")
    return ("%.*f %s" % (digits, v, unit)) if v < 100 or digits else "%s %s" % ("{:,}".format(round(v)).replace(",", "\u202f"), unit)


def speed_text(kmh, u):
    """A speed in the wallpaper's speed unit (0 km/h, 1 mph, 2 knots), thousands spaced."""
    v, unit = (kmh * 0.621371, "mph") if u == 1 else (kmh / 1.852, "kn") if u == 2 else (kmh, "km/h")
    return "%s %s" % ("{:,}".format(round(v)).replace(",", "\u202f"), unit)


def area_text(ha, u):
    v, unit = (ha * 2.47105, "ac") if u == 1 else (ha, "ha")
    return ("%dk %s" % (round(v / 1000), unit)) if v >= 100000 else ("%.1fk %s" % (v / 1000, unit)) if v >= 10000 else "%d %s" % (round(v), unit)


def read_mode():
    """The widget's overrides. A timed "full speed" override that has run out is dropped here, so both the
    wallpaper and the widget see it end at the same moment (and the file is tidied on the next write)."""
    try:
        m = json.loads(MODE.read_text(encoding="utf-8"))
        if not isinstance(m, dict):
            return {}
    except (OSError, ValueError):
        return {}
    until = m.get("full_until")
    if m.get("full") and isinstance(until, (int, float)) and time.time() >= until:
        m.pop("full", None)
        m.pop("full_until", None)
    return m


# --------------------------------------------------------------- status -----
def _age(seconds):
    if seconds < 5400:
        return "%d min" % max(1, seconds // 60)
    if seconds < 172800:
        return "%.1f h" % (seconds / 3600)
    return "%d days" % (seconds // 86400)


def have_hires():
    return all((DATA / "base" / ("hires%02d.jpg" % i)).exists() for i in range(1, 13))


MAX_BODY = 64 * 1024 * 1024        # no feed we read is anywhere near this; a response that is, is not the feed


MAX_DOWNLOAD = 300 * 1024 * 1024   # the NASA maps are the largest download (about 35 MB in all)


def _http(url, method="GET", timeout=6, limit=MAX_BODY, headers=None):
    """GET/HEAD with the plugin's user agent (plus `headers`, for the sources that want an Accept or a key), TLS
    verified by the system store (urllib's default), the body capped at `limit` bytes so a broken or hostile
    server cannot fill memory."""
    import time
    t0 = time.time()
    if not str(url).startswith("https://"):
        raise ValueError("refusing a non-https URL: %s" % str(url)[:80])
    h = dict(UA)
    if headers:
        h.update(headers)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h, method=method), timeout=timeout) as r:
            body = r.read(limit + 1) if method == "GET" else b""
            if len(body) > limit:
                raise ValueError("response larger than %d MB" % (limit // 1048576))
            return r.status, r.headers, body, time.time() - t0
    except urllib.error.HTTPError as e:
        # the same error, with the server's own words when it gave any: an OGC ExceptionReport inside a 502 names
        # the failing query ("FLTApplyFilterToLayer() failed", EFFIS, October 2026) where "Bad Gateway" named nothing
        gist = error_gist(e)
        if gist and gist.lower() not in (str(e.msg).lower(), "%s %s" % (e.code, str(e.msg).lower())):

            raise urllib.error.HTTPError(e.url, e.code, "%s - %s" % (e.msg, gist), e.headers, None) from None
        raise


def error_gist(err):
    """The first thing an HTTP error's body says: an ows:ExceptionText, else a <title>, else nothing ("")."""
    try:
        text = err.read(4000).decode("utf-8", "replace")
    except Exception:
        return ""
    m = re.search(r"<(?:ows:)?ExceptionText>\s*(.*?)\s*</", text, re.S) or re.search(r"<title>\s*(.*?)\s*</title>", text, re.S | re.I)
    return " ".join(m.group(1).split())[:140] if m else ""


def fetch_json(url, timeout=6, limit=MAX_BODY, headers=None, what=""):
    """GET a JSON document, and when it is not one say what came back instead: the content type and the first
    line of the body - an OGC ExceptionReport names its own error, an HTML page names the outage. "Expecting
    value: line 1 column 1" told nobody that Environment Canada's WFS did not know the type name."""
    status, hdrs, body, _t = _http(url, timeout=timeout, limit=limit, headers=headers)
    try:
        return json.loads(body)
    except ValueError:
        ctype = str(hdrs.get("Content-Type", "") if hasattr(hdrs, "get") else "").split(";")[0].strip() or "unknown type"
        text = body[:4000].decode("utf-8", "replace")
        m = re.search(r"<(?:ows:)?ExceptionText>\s*(.*?)\s*</", text, re.S) or re.search(r"<title>\s*(.*?)\s*</title>", text, re.S | re.I)
        gist = " ".join((m.group(1) if m else text.strip().splitlines()[0] if text.strip() else "empty body").split())[:140]
        raise ValueError("%snot JSON (%s, HTTP %s): %s" % ((what + ": ") if what else "", ctype, status, gist))


def safe_xml(text):
    """XML from the network goes through the stdlib parser, which is not hardened against entity expansion
    ("billion laughs"); a feed never needs a DOCTYPE or entities, so any is refused outright."""
    head = text[:4096] if isinstance(text, str) else text[:4096].decode("latin-1", "replace")
    if re.search(r"<!(DOCTYPE|ENTITY)", head, re.I):
        raise ValueError("XML with a DOCTYPE or entity declarations is not accepted")
    return text


LONG_FACTS = ("Report",)                 # fact rows that carry a whole narrative (a UKMTO report): paragraphs, up to LONG_LEN


LONG_LEN = 1200


def clean(obj, maxlen=160):
    """Strings from the network are shown on the desktop: keep them printable, short and free of markup.
    Line breaks stay (a facts value may be a list, or paragraphs); a fact row named in LONG_FACTS may be long."""
    if isinstance(obj, str):
        t = "".join(ch for ch in obj if (ch.isprintable() or ch == "\n") and ch not in "<>")
        if t.startswith("https://"):
            return t if len(t) <= 512 else ""          # links: keep whole or drop, never truncate
        return t if len(t) <= maxlen else t[:maxlen - 1] + "\u2026"
    if isinstance(obj, dict):
        return {k: clean(v, maxlen) for k, v in obj.items()}
    if isinstance(obj, list):
        if len(obj) in (2, 3) and obj[0] in LONG_FACTS and isinstance(obj[1], str):
            return [obj[0], clean(obj[1], LONG_LEN)] + obj[2:]
        return [clean(v, maxlen) for v in obj]
    return obj


def emit(obj):
    json.dump(clean(obj), sys.stdout, separators=(",", ":"))


# ---------------------------------------------------------------- fetch -----
def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    print("  %s" % url)
    if not str(url).startswith("https://"):
        raise ValueError("refusing a non-https URL")
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r, open(tmp, "wb") as f:
        total = 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_DOWNLOAD:
                f.close(); tmp.unlink(missing_ok=True)
                raise ValueError("download larger than %d MB, stopped" % (MAX_DOWNLOAD // 1048576))
            f.write(chunk)
    tmp.replace(dest)


PKG = Path(__file__).resolve().parent.parent.parent      # the package's contents/ folder
