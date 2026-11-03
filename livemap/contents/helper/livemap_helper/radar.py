"""Rain radar round the home place: RainViewer's composite of the national weather radars, as a short loop."""
import json
import math
import os
import time

from .common import BORDERS, DATA, UA, _age, _http, emit, fetch_json, read_layers_str

# RainViewer collects the public radar composites of the national weather services (NEXRAD in the US, the
# European services, Japan, Australia, Canada, parts of Latin America and Asia) into one world mosaic, a frame
# every ten minutes, and serves the last two hours as map tiles from a keyless public index. Free for
# non-commercial use with attribution ("Radar: RainViewer"); the index is asked at most every five minutes and
# a frame's tiles are fetched once (the frame path is a content hash: the same frame is never fetched twice).
# Where no service shares a radar - the oceans, most of Africa, much of Asia - a tile is simply empty, which the
# tiles cannot tell apart from "no rain"; the widget says so in words.
INDEX = "https://api.rainviewer.com/public/weather-maps.json"
TILE = "%s%s/%d/%d/%d/%d/%d/%d_%d.png"            # host, path, size, z, x, y, colour scheme, smooth, snow
TILE_SIZE = 256
COLOUR = 2                                        # RainViewer's "universal blue" scheme, readable on a dark map
SMOOTH, SNOW = 1, 1
FRAMES = 7                                        # an hour: six steps of ten minutes, and now
ZOOM = 6                                          # 3 x 3 tiles at zoom 6: about 1 500 km across at mid-latitudes
INDEX_KEEP = 5 * 60
TILE_KEEP = 3 * 3600                              # a frame older than this leaves the folder

RADAR = DATA / "radar"
RADAR_INDEX = DATA / "radar-index.json"


def tile_of(lat, lon, z):
    """Web Mercator tile column and row (floats) for a point."""
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    phi = math.radians(max(-85.05, min(85.05, lat)))
    y = (1.0 - math.log(math.tan(phi) + 1.0 / math.cos(phi)) / math.pi) / 2.0 * n
    return x, y


def tile_bounds(x, y, z):
    """(west, south, east, north) of a tile in degrees."""
    n = 2 ** z
    west, east = x / n * 360.0 - 180.0, (x + 1) / n * 360.0 - 180.0
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return west, south, east, north


def read_index(now=None):
    """RainViewer's index: the frames of the last two hours (and a nowcast when they publish one), cached."""
    now = now if now is not None else time.time()
    try:
        c = json.loads(RADAR_INDEX.read_text(encoding="utf-8"))
        if now - c.get("at", 0) < INDEX_KEEP:
            return c["index"]
    except (OSError, ValueError, KeyError):
        pass
    index = fetch_json(INDEX, timeout=10, what="RainViewer index")
    try:
        RADAR_INDEX.parent.mkdir(parents=True, exist_ok=True)
        RADAR_INDEX.write_text(json.dumps({"at": now, "index": index}), encoding="utf-8")
    except OSError:
        pass
    return index


def frames_of(index, count=FRAMES):
    """[(time, path)] newest last: the last `count` past frames, then the nowcast if any."""
    radar = index.get("radar") or {}
    past = [(int(f["time"]), str(f["path"])) for f in (radar.get("past") or []) if isinstance(f, dict) and "path" in f]
    cast = [(int(f["time"]), str(f["path"])) for f in (radar.get("nowcast") or []) if isinstance(f, dict) and "path" in f]
    past.sort()
    return past[-count:] + cast[:3], len(cast[:3])


def _basemap(west, south, east, north, size):
    """A dark base for the box: land, borders and coasts from the Natural Earth files the wallpaper already has,
    drawn in Web Mercator so the radar tiles land on it exactly."""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (size, size), (10, 16, 26, 255))
    draw = ImageDraw.Draw(im)
    n_w, n_s = _merc(north), _merc(south)

    def to_px(lon, lat):
        return ((lon - west) / (east - west) * size, (_merc(lat) - n_w) / (n_s - n_w) * size)

    def rings(path):
        try:
            d = json.loads((BORDERS / path).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        for f in d.get("features", []):
            g = f.get("geometry") or {}
            t, c = g.get("type"), g.get("coordinates") or []
            polys = c if t == "MultiPolygon" else [c] if t == "Polygon" else []
            lines = c if t == "MultiLineString" else [c] if t == "LineString" else []
            for poly in polys:
                for ring in poly:
                    yield "fill", ring
            for line in lines:
                yield "line", line

    def touches(points):                                       # the ring or line comes near the box at all
        xs = [p[0] for p in points]; ys = [p[1] for p in points]
        return xs and max(xs) >= west - 1 and min(xs) <= east + 1 and max(ys) >= south - 1 and min(ys) <= north + 1

    for kind, ring in rings("ne_50m_admin_0_countries.geojson"):
        if kind == "fill" and len(ring) >= 3 and touches(ring):
            draw.polygon([to_px(p[0], p[1]) for p in ring], fill=(34, 44, 56, 255))   # Pillow clips what falls outside
    for path, colour in (("ne_50m_admin_1_states_provinces_lines.geojson", (62, 72, 86, 255)), ("ne_50m_admin_0_boundary_lines_land.geojson", (110, 118, 130, 255)),
                         ("ne_50m_coastline.geojson", (120, 140, 160, 255))):
        for kind, line in rings(path):
            if kind == "line" and len(line) >= 2 and touches(line):
                draw.line([to_px(p[0], p[1]) for p in line], fill=colour, width=1)
    return im


def _merc(lat):
    phi = math.radians(max(-85.05, min(85.05, lat)))
    return math.log(math.tan(phi) + 1.0 / math.cos(phi))


def fetch_tile(host, path, z, x, y):
    url = TILE % (host, path, TILE_SIZE, z, x, y, COLOUR, SMOOTH, SNOW)
    status, _h, body, _t = _http(url, timeout=10, headers=dict(UA, Accept="image/png"))
    if status != 200 or not body[:4] == b"\x89PNG":
        raise RuntimeError("tile %d/%d/%d: HTTP %s" % (z, x, y, status))
    return body


def build_frame(host, when, path, lat, lon, z, base):
    """One frame: the 3 x 3 tiles round the home place over the base map, saved as a file. Returns (file,
    echoes) - echoes is the share of radar pixels that carry rain, to tell an empty hour from an empty region."""
    from PIL import Image
    import io
    cx, cy = tile_of(lat, lon, z)
    tx, ty = int(cx), int(cy)
    n = 2 ** z
    im = base.copy()
    layer = Image.new("RGBA", (3 * TILE_SIZE, 3 * TILE_SIZE), (0, 0, 0, 0))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            x, y = (tx + dx) % n, ty + dy
            if y < 0 or y >= n:
                continue
            tile = Image.open(io.BytesIO(fetch_tile(host, path, z, x, y))).convert("RGBA")
            layer.paste(tile, ((dx + 1) * TILE_SIZE, (dy + 1) * TILE_SIZE))
    alpha = layer.getchannel("A")
    hist = alpha.histogram()
    echoes = 1 - hist[0] / float(sum(hist))
    layer.putalpha(alpha.point(lambda a: int(a * 0.85)))      # a touch of the map through heavy rain
    im.alpha_composite(layer)
    # the home place: a small ring
    from PIL import ImageDraw
    px, py = (cx - tx + 1) * TILE_SIZE, (cy - ty + 1) * TILE_SIZE
    d = ImageDraw.Draw(im)
    d.ellipse((px - 6, py - 6, px + 6, py + 6), outline=(255, 210, 63, 255), width=2)
    d.ellipse((px - 2, py - 2, px + 2, py + 2), fill=(255, 210, 63, 255))
    RADAR.mkdir(parents=True, exist_ok=True)
    dest = RADAR / ("%d_%s.png" % (when, path.rsplit("/", 1)[-1]))
    tmp = dest.with_suffix(".tmp%d.png" % os.getpid())
    im.convert("RGB").save(tmp, "PNG", optimize=True)
    tmp.replace(dest)
    return dest, echoes


def radar_loop(lat, lon, z=ZOOM, count=FRAMES, now=None):
    """The loop for a place: frames (newest last) as files, the box, and whether anything was seen."""
    now = now if now is not None else time.time()
    index = read_index(now)
    host = str(index.get("host") or "https://tilecache.rainviewer.com")
    frames, cast = frames_of(index, count)
    cx, cy = tile_of(lat, lon, z)
    tx, ty = int(cx), int(cy)
    w, s, _e, _n = tile_bounds(tx - 1, ty + 1, z)
    _w2, _s2, e, n = tile_bounds(tx + 1, ty - 1, z)
    base = None
    out, errors, echoes_max = [], [], 0.0
    for i, (when, path) in enumerate(frames):
        dest = RADAR / ("%d_%s.png" % (when, path.rsplit("/", 1)[-1]))
        if dest.exists():
            out.append({"time": when, "file": dest.as_uri(), "nowcast": i >= len(frames) - cast})
            continue
        try:
            if base is None:
                base = _basemap(w, s, e, n, 3 * TILE_SIZE)
            f, echoes = build_frame(host, when, path, lat, lon, z, base)
            echoes_max = max(echoes_max, echoes)
            out.append({"time": when, "file": f.as_uri(), "nowcast": i >= len(frames) - cast})
        except Exception as ex:                                   # noqa: BLE001 - one frame short, the loop still plays
            errors.append("%s: %s" % (time.strftime("%H:%M", time.gmtime(when)), ex))
    # old frames leave
    try:
        for f in RADAR.glob("*.png"):
            if now - f.stat().st_mtime > TILE_KEEP:
                f.unlink()
    except OSError:
        pass
    return {"frames": out, "box": [w, s, e, n], "zoom": z, "home": [lat, lon], "generated": index.get("generated"),
            "echoes": round(echoes_max, 4), "errors": errors, "attribution": "Radar: RainViewer (rainviewer.com)"}


def cmd_radar(args):
    try:
        lat, lon = float(args.lat), float(args.lon)
    except (TypeError, ValueError):
        try:
            lat, lon = (float(x) for x in read_layers_str("home").split(","))
        except (ValueError, AttributeError):
            emit({"problem": "No home place: set it under Essentials > Where you are"})
            return
    try:
        import PIL  # noqa: F401
    except ImportError:
        emit({"problem": "The radar needs python3-pillow (livemap.sh doctor names the package)"})
        return
    try:
        emit(radar_loop(lat, lon, int(args.zoom), int(args.frames)))
    except Exception as e:                                        # noqa: BLE001 - the widget shows it
        emit({"problem": "Radar: %s" % e})


def chk_radar():
    index = read_index()
    frames, cast = frames_of(index, FRAMES)
    if not frames:
        return "error", "RainViewer's index lists no frames"
    newest = frames[-1 - cast][0] if cast else frames[-1][0]
    age = time.time() - newest
    files = len(list(RADAR.glob("*.png"))) if RADAR.exists() else 0
    return ("warn" if age > 3600 else "ok"), "%d frames in the last two hours, newest %s ago%s; %d frame pictures kept locally" % (
        len((index.get("radar") or {}).get("past") or []), _age(int(age)), ", %d nowcast" % cast if cast else "", files)
