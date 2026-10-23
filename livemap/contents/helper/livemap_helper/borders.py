"""Natural Earth borders, coasts, rivers, lakes, names, places, time zones, plates."""
import contextlib
import json
import sys

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import BORDERS, DATA, NE, NE_FILES, PLATES_FILE, PLATES_URL, _lines, _ring_area, _spans_at, download, \
    emit


def _river_mouths(step):
    """Rivers at 1:50m stop where the 1:50m coast begins, and that coast runs far up the estuaries: the Amazon
    ends 2.7 degrees short of the 1:110m coastline (the St. Lawrence 4, the Yangtze 1.3, over a hundred mouths
    in all), so with the coarse coast drawn the rivers stop in the middle of the land. This carries every such
    mouth on to the 1:110m coast: along the 1:110m river where one of the same name reaches the coast (the
    Amazon, St. Lawrence, Yangtze, Ob...), otherwise straight to the nearest point of the coarse coast when
    that lies ahead of the river. Returns the extensions as flat lists like _lines()."""
    f50, c50, c110, r110 = (BORDERS / (n + ".geojson") for n in ("ne_50m_rivers_lake_centerlines", "ne_50m_coastline", "ne_110m_coastline", "ne_110m_rivers_lake_centerlines"))
    if not all(p.exists() for p in (f50, c50, c110)):
        return []
    import math
    CELL = 0.5

    def parts_of(path):
        for feat in json.loads(path.read_text(encoding="utf-8"))["features"]:
            g = feat.get("geometry") or {}
            kind, c = g.get("type"), g.get("coordinates") or []
            for part in ([c] if kind == "LineString" else c if kind == "MultiLineString" else []):
                yield feat.get("properties") or {}, [(pt[0], pt[1]) for pt in part]

    def grid(points):
        g = {}
        for x, y in points:
            g.setdefault((int(x // CELL), int(y // CELL)), []).append((x, y))
        return g

    def segments(parts):                                      # the coast as segments, in every cell they cross
        g = {}
        for part in parts:
            for (ax, ay), (bx, by) in zip(part, part[1:]):
                n = int(max(abs(bx - ax), abs(by - ay)) // CELL) + 1
                for k in range(n + 1):
                    x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
                    g.setdefault((int(x // CELL), int(y // CELL)), []).append((ax, ay, bx, by))
        return g

    def nearest(g, x, y, reach, heading=None):               # (distance, point) within `reach` degrees
        """The closest point of the grid's points and segments; with a heading (hx, hy) the best point ahead
        instead: distance divided by how well the direction agrees, so a river mouth 0.7 degrees ahead beats
        a stretch of coast 0.6 degrees off to the side."""
        best, at, cells = reach, None, int(reach // CELL) + 1
        hl = math.hypot(*heading) if heading else 0

        def score(px, py):
            nonlocal best, at
            d = math.hypot(px - x, py - y)
            if hl and d:
                cos = ((px - x) * heading[0] + (py - y) * heading[1]) / (d * hl)
                if cos < -0.3:                                # behind the river: never
                    return
                d = d / (0.3 + max(0, cos))
            if d < best:
                best, at = d, (px, py)
        for dx in range(-cells, cells + 1):
            for dy in range(-cells, cells + 1):
                for item in g.get((int(x // CELL) + dx, int(y // CELL) + dy), ()):
                    if len(item) == 2:
                        score(*item)
                    else:                                     # a segment: its closest point (and its ends, when aiming)
                        ax, ay, bx, by = item
                        l2 = (bx - ax) ** 2 + (by - ay) ** 2
                        t = 0 if l2 == 0 else max(0, min(1, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / l2))
                        score(ax + t * (bx - ax), ay + t * (by - ay))
                        if hl:
                            score(ax, ay); score(bx, by)
        return best, at

    coast50 = grid(pt for _, part in parts_of(c50) for pt in part)
    coast110 = segments(part for _, part in parts_of(c110))
    coarse = {}                                               # name -> 1:110m parts
    if r110.exists():
        for p, part in parts_of(r110):
            coarse.setdefault(p.get("name"), []).append(part)
    mouths = []
    for p, part in parts_of(f50):
        if p.get("featurecla") != "River" or len(part) < 2:
            continue
        for end, back in ((part[0], part[1:]), (part[-1], part[-2::-1])):
            if nearest(coast50, end[0], end[1], 0.06)[1] is None:     # not a mouth: the line ends inland
                continue
            gap, at = nearest(coast110, end[0], end[1], 5.0)
            if at is not None and gap >= 0.25:                        # stops short of the coarse coast
                mouths.append((p.get("name"), end, back))
    exts, straight = [], []
    for name, end, back in mouths:                                    # first the coarse rivers' own tails
        ext = None
        for cpart in coarse.get(name, []) + coarse.get({"Yangtze": "Chang", "Mackenzie": "Peace"}.get(name), []):
            for tail in (cpart, cpart[::-1]):
                i = min(range(len(tail)), key=lambda k: math.hypot(tail[k][0] - end[0], tail[k][1] - end[1]))
                if math.hypot(tail[i][0] - end[0], tail[i][1] - end[1]) < 0.4 and nearest(coast110, tail[-1][0], tail[-1][1], 0.35)[1] is not None and len(tail) - i >= 2:
                    ext = [end] + tail[i + 1:]
                    break
            if ext:
                break
        (exts if ext else straight).append(ext or (end, back))
    # then the rest, straight to whatever is nearest: the coarse coast or a tail just drawn (the Xingu joins the
    # Amazon's tail rather than running beside it to the sea), if that lies ahead of the river
    target = {k: list(v) for k, v in coast110.items()}
    for ext in exts:
        for pt in ext[1:]:
            target.setdefault((int(pt[0] // CELL), int(pt[1] // CELL)), []).append(pt)
    for end, back in straight:
        far = next((q for q in back if math.hypot(q[0] - end[0], q[1] - end[1]) > 0.8), back[-1])
        gap, at = nearest(target, end[0], end[1], 5.0, (end[0] - far[0], end[1] - far[1]))
        if at is not None:
            exts.append([end, at])
    out = []
    for ext in exts:
        flat, last = [], None
        for x, y in ext:
            x, y = round(x, 2), round(y, 2)
            if last is None or abs(x - last[0]) >= step or abs(y - last[1]) >= step or (x, y) == (round(ext[-1][0], 2), round(ext[-1][1], 2)):
                flat += [x, y]
                last = (x, y)
        if len(flat) >= 4:
            out.append(flat)
    return out


def _water_names(scale, lake_rank, sea_rank):
    """Names of lakes (from the lakes file at `scale`) and of oceans, seas, gulfs, bays and straits (the 1:50m
    marine polygons), as [name, lon, lat, rank, kind]: kind 0 lake, 1 ocean, 2 sea, 3 gulf, bay, strait or
    channel. The label sits at the centroid of the biggest polygon, or - for a crescent like the Mediterranean
    whose centroid is on land - at the middle of the widest stretch of water on that latitude. A lake rank
    (Natural Earth's scalerank: 0-1 the great lakes, up to 6) or sea rank (0 oceans, 1 the big seas, 2-4
    the rest) below zero leaves that kind out."""
    out = []

    def label_point(geom):
        kind, c = geom.get("type"), geom.get("coordinates") or []
        polys = [c] if kind == "Polygon" else c if kind == "MultiPolygon" else []
        rings = [(poly[0], _ring_area(poly[0])) for poly in polys if poly and len(poly[0]) >= 4]
        if not rings:
            return None, 0
        ring, area = max(rings, key=lambda r: r[1])
        cx = cy = 0.0
        for i in range(len(ring) - 1):
            cross = ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1]
            cx += (ring[i][0] + ring[i + 1][0]) * cross
            cy += (ring[i][1] + ring[i + 1][1]) * cross
        signed = sum(ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1] for i in range(len(ring) - 1)) / 2
        if abs(signed) < 1e-9:
            return None, 0
        cx, cy = cx / (6 * signed), cy / (6 * signed)
        # the row: the centroid's, unless another row through the middle of the shape has much wider water
        # (the Mediterranean's centroid row is cut by Sicily; the row just south runs from Gibraltar to Syria)
        lats = [pt[1] for pt in ring]
        lo, hi = min(lats), max(lats)
        best = None
        for k in range(9):
            lat = lo + (hi - lo) * (0.2 + 0.6 * k / 8)
            for a, b in _spans_at(ring, lat):
                if best is None or b - a > best[0]:
                    best = (b - a, lat, (a + b) / 2)
        spans = _spans_at(ring, cy)
        width = max((b - a for a, b in spans), default=0)
        if best and best[0] > width * 1.25:
            cy, cx, width = best[1], best[2], best[0]
        elif not any(a <= cx <= b for a, b in spans) and spans:      # centroid on land: the widest water on that row
            a, b = max(spans, key=lambda s: s[1] - s[0])
            cx = (a + b) / 2
        return (round(cx, 2), round(cy, 2)), round(width, 2)

    if lake_rank >= 0:
        f = BORDERS / ("ne_%s_lakes.geojson" % scale)
        if not f.exists():
            return None
        for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
            p = feat.get("properties") or {}
            name, rank = p.get("name"), int(p.get("scalerank") or 0)
            if not name or rank > lake_rank:
                continue
            at, width = label_point(feat.get("geometry") or {})
            if at:
                out.append([name, at[0], at[1], rank, 0, width])
    if sea_rank >= 0:
        f = BORDERS / "ne_50m_geography_marine_polys.geojson"
        if not f.exists():
            return None
        for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
            p = feat.get("properties") or {}
            name, rank, cla = p.get("name"), int(p.get("scalerank") or 0), p.get("featurecla") or ""
            if not name or rank > sea_rank or cla in ("river", "reef"):
                continue
            at, width = label_point(feat.get("geometry") or {})
            if at:
                out.append([name.title() if name.isupper() else name, at[0], at[1], rank, 1 if cla == "ocean" else 2 if cla == "sea" else 3, width])
    return sorted(out, key=lambda n: (n[3], -n[5]))


def _names():
    f = BORDERS / "ne_110m_admin_0_countries.geojson"
    if not f.exists():
        return None
    out = []
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        p, box = feat.get("properties") or {}, feat.get("bbox")
        x, y = p.get("LABEL_X"), p.get("LABEL_Y")
        if x is None or y is None:
            if not box:
                continue
            x, y = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        out.append([p.get("NAME") or p.get("ADMIN") or "", round(x, 2), round(y, 2), int(p.get("LABELRANK") or 5)])
    return sorted(out, key=lambda n: n[3])


def _state_names():
    """State and province names: [name, lon, lat, rank] from Natural Earth's admin-1 label points, one per
    region (the file gives big regions several points; the best-ranked one is kept). Rank 2 is a major
    region, 10 a minor one."""
    f = BORDERS / "ne_10m_admin_1_label_points.geojson"
    if not f.exists():
        return None
    best = {}
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        p, c = feat.get("properties") or {}, (feat.get("geometry") or {}).get("coordinates")
        name = p.get("name") or ""
        if not name or not c:
            continue
        key, rank = (p.get("admin") or "", name), int(p.get("scalerank") or 10)
        if key not in best or rank < best[key][3]:
            best[key] = [name, round(float(c[0]), 2), round(float(c[1]), 2), rank]
    return sorted(best.values(), key=lambda n: n[3])


def _places(capitals, state_capitals, min_pop):
    """Capitals and cities: [name, lon, lat, population, kind] with kind 0 country capital, 1 state or province
    capital, 2 city over min_pop people. Country capitals first, then by population, so the overlap layout
    keeps the important ones. min_pop 0 = no cities by size."""
    f = BORDERS / "ne_10m_populated_places_simple.geojson"
    if not f.exists():
        return None
    out = []
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        p = feat.get("properties") or {}
        c = (feat.get("geometry") or {}).get("coordinates") or [p.get("longitude"), p.get("latitude")]
        name, cla, pop = str(p.get("name") or ""), str(p.get("featurecla") or ""), int(p.get("pop_max") or 0)
        if not name or c[0] is None:
            continue
        if capitals and (p.get("adm0cap") == 1 or cla == "Admin-0 capital"):
            kind = 0
        elif state_capitals and cla.startswith("Admin-1"):
            kind = 1
        elif min_pop and pop >= min_pop:
            kind = 2
        else:
            continue
        out.append([name, round(float(c[0]), 2), round(float(c[1]), 2), pop, kind])
    out.sort(key=lambda x: (x[4] != 0, -x[3]))
    return out


def _zones(row_lat=None):
    """Time zone outlines (Natural Earth 10m, thinned) and one label per zone: ["UTC+5:30", lon, lat, width_deg].
    Inside each zone: in its largest piece, on the widest stretch of the piece's own middle latitude, so the
    label sits in the zone rather than at the centre of a ragged outline. With row_lat: every label on that one
    line of latitude, in the widest stretch of the zone there (a classic time-zone map); zones the line misses
    get no label."""
    f = BORDERS / "ne_10m_time_zones.geojson"
    if not f.exists():
        return None, None
    lines, labels = _lines("ne_10m_time_zones", 0.08), []
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        p, g = feat.get("properties") or {}, feat.get("geometry") or {}
        zone = p.get("zone")
        if zone is None:
            continue
        coords = g.get("coordinates") or []
        rings = [coords[0]] if g.get("type") == "Polygon" and coords else [poly[0] for poly in coords if poly] if g.get("type") == "MultiPolygon" else []
        rings = [r for r in rings if len(r) >= 4]
        if not rings:
            continue
        h, m = int(abs(zone)), int(round((abs(zone) % 1) * 60))
        text = "UTC" if zone == 0 else "UTC%s%d%s" % ("+" if zone > 0 else "-", h, ":%02d" % m if m else "")
        best = None                                                  # (width, mid_lon, lat)
        if row_lat is not None:
            for r in rings:
                for a, b in _spans_at(r, row_lat):
                    if best is None or b - a > best[0]:
                        best = (b - a, (a + b) / 2, row_lat)
        else:
            r = max(rings, key=_ring_area)
            ys = [pt[1] for pt in r]
            mid = (min(ys) + max(ys)) / 2
            for lat in (mid, mid + (max(ys) - min(ys)) * 0.2, mid - (max(ys) - min(ys)) * 0.2):   # the middle, or near it
                for a, b in _spans_at(r, lat):
                    if best is None or b - a > best[0]:
                        best = (b - a, (a + b) / 2, lat)
        if (best is None or best[0] <= 0) and row_lat is not None and -12 <= zone <= 14 and zone == int(zone):
            # the row is a scale: a whole-hour zone with no land on the row's latitude (UTC+11 is a few islands,
            # UTC+2 at some latitudes) still gets its label, on its nominal meridian band
            best = (15.0, zone * 15.0, row_lat)
        if best is None or best[0] <= 0:
            continue
        labels.append([text, round(best[1], 2), round(best[2], 2), round(best[0], 2)] + _zone_clock(zone, p.get("tz_name1st") or ""))
    if row_lat is not None:                       # one label per offset in the row (the file has several polygons per zone)
        seen, uniq = set(), []
        for lab in sorted(labels, key=lambda l: -l[3]):
            if lab[0] not in seen:
                seen.add(lab[0]); uniq.append(lab)
        labels = uniq
    return lines, labels


def _zone_clock(zone, tz_name):
    """[offset now, next change, offset after it] for the zone's clock: the real offset of the zone's main
    place (summer time included) from the system's tz database when Natural Earth names one, the nominal
    offset otherwise. The wallpaper switches at the change without asking again; the border data is rebuilt
    on the next download anyway."""
    try:
        from zoneinfo import ZoneInfo
        from datetime import datetime, timedelta, timezone
        tz = ZoneInfo(tz_name)
        now = datetime.now(timezone.utc)
        off = lambda t: t.astimezone(tz).utcoffset().total_seconds() / 3600
        here = off(now)
        t, step = now, timedelta(days=1)
        for _ in range(400):                       # the next change, to the day, then to the minute
            t2 = t + step
            if off(t2) != here:
                lo, hi = t, t2
                while hi - lo > timedelta(minutes=1):
                    mid = lo + (hi - lo) / 2
                    if off(mid) != here:
                        hi = mid
                    else:
                        lo = mid
                return [here, int(hi.timestamp()), off(hi)]
            t = t2
        return [here, 0, here]
    except Exception:
        return [float(zone), 0, float(zone)]


ZONE_TINT = DATA / "zones-tint.png"


ZONE_COLOURS = ["#f67400", "#ffd23f", "#2ecc71", "#3daee9", "#9b59b6", "#da4453", "#1abc9c"]   # timeanddate's kind of cycle


def cmd_zone_tint(_args):
    """zones-tint.png: the time zone polygons filled with a colour cycle, fully opaque, 4096 x 2048 (the
    wallpaper sets the opacity). A flat fill stretches fine over a region, so one world image serves every view."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        sys.exit("python3-pillow is needed for the zone tint: sudo dnf install python3-pillow")
    f = BORDERS / "ne_10m_time_zones.geojson"
    if not f.exists():
        sys.exit("the time zone data is missing - press 'Download border data' first")
    W, H = 4096, 2048
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    n = 0
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        p, g = feat.get("properties") or {}, feat.get("geometry") or {}
        zone = p.get("zone")
        if zone is None:
            continue
        colour = ZONE_COLOURS[int(round(zone)) % len(ZONE_COLOURS)]
        kind, c = g.get("type"), g.get("coordinates") or []
        polys = [c] if kind == "Polygon" else c if kind == "MultiPolygon" else []
        for poly in polys:
            if poly and len(poly[0]) >= 3:
                d.polygon([((pt[0] + 180) / 360 * W, (90 - pt[1]) / 180 * H) for pt in poly[0]], fill=colour)
                n += 1
    im.save(ZONE_TINT, optimize=True)
    emit({"note": "", "zones": n, "file": str(ZONE_TINT)})


def cmd_borders(args):
    scale, step = ("50m", 0.04) if args.detail == "50m" else ("110m", 0.0)
    zones, zone_labels = _zones(args.zone_row) if args.zones else ([], [])
    river_scale = args.river_detail or scale
    # the lakes and marine files are new in 0.48: an install that downloaded earlier fetches just those, once
    for name in (["ne_%s_lakes" % river_scale] if args.lakes or args.lake_names >= 0 else []) + (["ne_50m_geography_marine_polys"] if args.sea_names >= 0 else []):
        if not (BORDERS / (name + ".geojson")).exists() and (BORDERS / "ne_110m_coastline.geojson").exists():
            try:
                with contextlib.redirect_stdout(sys.stderr):          # download() prints the URL; stdout is the JSON answer
                    download(NE + name + ".geojson", BORDERS / (name + ".geojson"))
            except Exception:
                pass
    rivers = _lines("ne_%s_rivers_lake_centerlines" % river_scale, 0.02 if river_scale == "50m" else 0.0) if args.rivers else []
    if rivers and river_scale == "50m" and scale == "110m":   # finer rivers than coast: carry the mouths on to the coast
        rivers = rivers + _river_mouths(0.02)
    res = {"coast": _lines("ne_%s_coastline" % scale, step),
           "borders": _lines("ne_%s_admin_0_boundary_lines_land" % scale, step),
           "states": _lines("ne_50m_admin_1_states_provinces_lines", 0.04) if args.states else [],
           "rivers": rivers,
           # lakes as rings (every polygon of the lakes file at the rivers' level); water names by rank
           "lakes": _lines("ne_%s_lakes" % river_scale, 0.02 if river_scale == "50m" else 0.0) if args.lakes else [],
           "water_names": _water_names(river_scale, args.lake_names, args.sea_names) if (args.lake_names >= 0 or args.sea_names >= 0) else [],
           "names": _names() if args.names else [],
           "state_names": _state_names() if args.state_names else [],
           "places": _places(args.capitals, args.state_capitals, args.city_pop) if (args.capitals or args.state_capitals or args.city_pop) else [],
           "zones": zones, "zone_labels": zone_labels, "zone_tint": str(ZONE_TINT) if ZONE_TINT.exists() else "",
           # country polygons: the land fill of the cartographic style; the 1:50m file is new in 0.46, so an
           # install that has not downloaded again falls back to the 1:110m one it has
           "land": (_lines("ne_%s_admin_0_countries" % scale, step) or _lines("ne_110m_admin_0_countries", 0.0)) if args.land else []}
    missing = [k for k, v in res.items() if v is None]
    res = {k: v or [] for k, v in res.items()}
    res["note"] = ("Borders: no data for %s yet - press 'Download border data' in the settings, "
                   "or run: livemap-helper fetch-borders" % ", ".join(missing)) if missing else ""
    try:                                                      # this computer's offset, for the band's "you are here" mark
        import time as _t
        res["home_offset"] = -(_t.altzone if _t.daylight and _t.localtime().tm_isdst else _t.timezone) / 3600
        res["home_std"] = -_t.timezone / 3600                     # the standard offset: the band's column it belongs to
    except Exception:
        res["home_offset"] = None
        res["home_std"] = None
    emit(res)


def cmd_fetch_borders(_args):
    failed = []
    for name, url in [(n, NE + n + ".geojson") for n in NE_FILES] + [(PLATES_FILE, PLATES_URL)]:
        try:
            download(url, BORDERS / (name + ".geojson"))
        except Exception as e:
            failed.append(name)
            print("  failed: %s" % e)
    if failed:
        sys.exit("Could not download: %s" % ", ".join(failed))
    print("Done. Made with Natural Earth (public domain), naturalearthdata.com; plate boundaries PB2002 (Peter Bird, "
          "Hugo Ahlenius / Nordpil, ODC-By)")
