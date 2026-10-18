#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 tidybitz
"""livemap-helper - the parts of Live World Map that QML cannot do itself.

  livemap-helper net                 JSON of where this machine is connected to (the wallpaper calls this)
  livemap-helper net --table         same, human readable, for checking
  livemap-helper where HOST...       where the map would draw a host (resolves it, looks each address up)
  livemap-helper forget              clear the memory of places seen before
  livemap-helper storms [--table]    active tropical cyclones with track and forecast, from GDACS (the wallpaper calls this)
  livemap-helper volcanoes [--table] volcanoes in this week's Smithsonian / USGS activity report (the wallpaper calls this)
  livemap-helper feed [--since T --until T]  the widget's event list; with a range (epoch seconds), past events from history.json
  livemap-helper power               prints "battery" or "mains" (the wallpaper calls this)
  livemap-helper status              JSON health report on every data source (the settings page calls this)
  livemap-helper make-lights         turn night.jpg into lights.png: only the lights, transparent elsewhere (numpy + pillow)
  livemap-helper fetch-borders       download Natural Earth coastlines, borders, rivers, names, places (~12 MB, public domain)
                                     and the PB2002 plate boundaries (~1 MB, ODC-By)
  livemap-helper borders             the border lines as compact JSON (the wallpaper calls this)
  livemap-helper plates              tectonic plate boundaries (PB2002) as compact JSON (the wallpaper calls this)
  livemap-helper fetch-infrastructure download offshore platforms (BSEE Gulf of Mexico, OpenStreetMap) and refineries (OpenStreetMap)
  livemap-helper infrastructure      the platforms and refineries as compact JSON (the wallpaper calls this)
  livemap-helper fetch-geoip         download the free DB-IP City Lite database (~20 MB, monthly)
  livemap-helper fetch-maps          download NASA's 12 monthly Blue Marble images + night lights (~35 MB)
      --ocean-from IMAGE             keep the dark ocean of IMAGE (your current wallpaper); needs numpy + pillow
      --hires                        the 21600x10800 monthly set beside the small one, for regions (~330 MB)
  livemap-helper frame | fetch-frame --style S --north N --south S --west W --east E --width PX
                                     is the imagery for that view and style there / build it (the wallpaper calls both;
                                     styles: seasonal, viirs, relief, dark [--land --ocean --detail]); needs pillow
  livemap-helper zone-tint           draw zones-tint.png, the time zone polygons in a colour cycle (needs pillow)
  livemap-helper fires | incidents | floods | nws-floods | air-alerts | hotspots | launches | sats | clouds   the other layers' data (the wallpaper calls these; --table to read)
  livemap-helper mode --pause on|off --plain on|off --hide a,b --clouds on|off|auto --full on|off   the widget's overrides
  livemap-helper where-city NAME     offline city search in Natural Earth's places (the home setting)

Everything is stored in $XDG_DATA_HOME/livemap (usually ~/.local/share/livemap).
`net` never touches the network: it reads `ss` and an offline database.
"""
import argparse
import gzip
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from datetime import date
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
VERSION = "0.47"
UA = {"User-Agent": "livemap-wallpaper/" + VERSION}
NE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
BORDERS = DATA / "borders"
NE_FILES = ["ne_110m_coastline", "ne_110m_admin_0_boundary_lines_land", "ne_110m_admin_0_countries", "ne_50m_admin_0_countries",
            "ne_50m_coastline", "ne_50m_admin_0_boundary_lines_land", "ne_50m_admin_1_states_provinces_lines",
            "ne_10m_time_zones", "ne_10m_populated_places_simple",    # time zone polygons; cities, capitals, home search
            "ne_10m_admin_1_label_points",                              # state and province names (label points with a rank)
            "ne_110m_rivers_lake_centerlines", "ne_50m_rivers_lake_centerlines"]   # major rivers
# Tectonic plate boundaries: Peter Bird's PB2002 model (2003), GeoJSON conversion by Hugo Ahlenius (Nordpil),
# Open Data Commons Attribution licence. Downloaded with the border data, drawn under the Earthquakes settings.
PLATES_URL = "https://raw.githubusercontent.com/fraxen/tectonicplates/master/GeoJSON/PB2002_boundaries.json"
PLATES_FILE = "PB2002_boundaries"                                     # stored next to the Natural Earth files


# ------------------------------------------------------------------ net -----
SEEN = DATA / "seen.json"          # the connection memory: every place this machine has talked to, first/last time
LIVE = ("ESTAB", "SYN-SENT", "CLOSE-WAIT")            # the rest (TIME-WAIT, FIN-WAIT-x ...) are connections winding down


def parse_ss(text):
    """Yield (proto, state, remote_ip, process, rtt_ms) from `ss -Htunpi state connected`.

    Handles both column layouts (with and without a State column) and the indented TCP-info
    line that -i adds under each socket, which is where the kernel's measured round trip lives."""
    rows = []
    for line in text.splitlines():
        if line[:1] in (" ", "\t"):                       # continuation: TCP info of the row above
            m = re.search(r"\brtt:([\d.]+)/", line)
            if m and rows:
                rows[-1][4] = float(m.group(1))
            continue
        f = line.split()
        if len(f) < 5 or f[0] not in ("tcp", "udp"):
            continue
        state, off = ("ESTAB", 1) if f[1].isdigit() else (f[1], 2)
        if len(f) < off + 4:
            continue
        host = f[off + 3].rpartition(":")[0].strip("[]").split("%")[0]
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            continue
        if getattr(ip, "ipv4_mapped", None):
            ip = ip.ipv4_mapped
        if not ip.is_global:
            continue                                      # LAN, loopback, link-local, CGNAT...
        m = re.search(r'\(\("([^"]+)"', line)
        rows.append([f[0], state, str(ip), m.group(1) if m else "", None])
    return [tuple(r) for r in rows]


def connections():
    # "connected" = every state except listening and closed, so connection attempts (SYN-SENT) and
    # connections that closed within the last minute (TIME-WAIT) are seen too, not only open ones.
    out = subprocess.run(["ss", "-H", "-t", "-u", "-n", "-p", "-i", "state", "connected"],
                         capture_output=True, text=True, timeout=5)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "ss failed")
    return parse_ss(out.stdout)


def lookup(reader, ip):
    """(key, lat, lon, 'City, CC', 'CC') for an address, or None if the database has no location for it."""
    rec = reader.get(ip) or {}
    loc = rec.get("location") or {}
    if "latitude" not in loc:
        return None
    city = ((rec.get("city") or {}).get("names") or {}).get("en", "")
    city = re.sub(r"\s*\(.*?\)", "", city)                # "San Francisco (Financial District)" -> "San Francisco"
    cc = (rec.get("country") or {}).get("iso_code", "")
    return ("%.1f,%.1f" % (loc["latitude"], loc["longitude"]), loc["latitude"], loc["longitude"],
            ", ".join(x for x in (city, cc) if x), cc)


def remember(places, now, linger, new_window, path=None):
    """Update the connection memory. Returns {key: memory entry} for every place that should be drawn as
    recently closed, and sets p["fresh"] on every place: "" | "place" | "country" (first time ever).

    A place seen only through sockets that are winding down (TIME-WAIT etc.) counts as "just closed":
    that is how a connection that opened and closed between two looks still gets onto the map."""
    path = path or SEEN
    try:
        mem = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = None
    first_run = mem is None                     # nothing is "new" the first time: that run is the baseline
    mem = mem or {"since": now, "places": {}, "countries": {}}
    ghosts = {}
    for key, p in places.items():
        old = mem["places"].get(key)
        if old is None:
            old = mem["places"][key] = {"first": 0 if first_run else now, "last": now}
        if p["live"] or "lat" not in old:
            old.update(lat=p["lat"], lon=p["lon"], place=p["place"], proc=p["proc"] or old.get("proc", ""), cc=p["cc"])
        if p["live"]:
            old["last"] = now
        else:
            ghosts[key] = old
        if p["cc"] and p["cc"] not in mem["countries"]:
            mem["countries"][p["cc"]] = 0 if first_run else now
    for key, old in mem["places"].items():      # closed since the last look, no socket left at all
        if key not in places and 0 < now - old.get("last", 0) <= linger:
            ghosts[key] = old
    for key, old in list(mem["places"].items()):
        fresh = ("country" if now - mem["countries"].get(old.get("cc"), 0) < new_window
                 else "place" if now - old.get("first", 0) < new_window else "")
        if key in places:
            places[key]["fresh"] = fresh
        if key in ghosts:
            ghosts[key] = dict(old, fresh=fresh)
    if len(mem["places"]) > 5000:               # keep the file small: forget the places not seen for longest
        for k in sorted(mem["places"], key=lambda k: mem["places"][k].get("last", 0))[:500]:
            del mem["places"][k]
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps(mem), encoding="utf-8")
        tmp.replace(path)                       # atomic: two screens may run this at the same moment
    except OSError:
        pass
    return ghosts


def locate(conns, reader, limit=40, home_lon=None, linger=90, new_window=3600, now=None, memory=None):
    """Group connections by place (one arc per city, not per socket) and attach state, latency and novelty."""
    import time
    now = int(now if now is not None else time.time())
    places = {}
    for _proto, state, ip, proc, rtt in conns:
        hit = lookup(reader, ip)
        if hit is None:
            continue
        key, lat, lon, place, cc = hit
        p = places.setdefault(key, {"lat": lat, "lon": lon, "place": place, "cc": cc, "n": 0, "live": 0,
                                    "trying": 0, "procs": Counter(), "rtt": None, "fresh": ""})
        if state in LIVE:
            p["live"] += 1
            p["n"] += 1
            p["trying"] += state == "SYN-SENT"
            if rtt is not None and state != "SYN-SENT":       # an unanswered attempt has nothing measured yet
                p["rtt"] = rtt if p["rtt"] is None else min(p["rtt"], rtt)
        if proc:
            p["procs"][proc] += 1
    for p in places.values():
        top = p["procs"].most_common(1)
        p["proc"] = top[0][0] if top else ""
    ghosts = remember(places, now, linger, new_window, memory)

    rows = []
    for key, p in places.items():
        if p["live"]:
            rows.append((key, p["lat"], p["lon"], p["n"], p["place"], p["proc"], p["rtt"],
                         "connecting" if p["trying"] == p["live"] else "live", 0, p["fresh"]))
    if linger > 0:
        for key, g in ghosts.items():
            rows.append((key, g["lat"], g["lon"], 0, g.get("place", ""), g.get("proc", ""), None,
                         "closed", max(1, now - g.get("last", now)), g.get("fresh", "")))
    rows.sort(key=lambda r: (r[7] == "closed", -r[3]))          # live ones first, busiest first

    # Labels: one character is about 1.2 deg of longitude wide and a line about 2.6 deg of latitude tall at
    # the wallpaper's font size. A label goes on the side of its dot facing away from home (the arc arrives
    # from the home side); one that would run into an earlier label is dropped, arc and dot are still drawn.
    peers, boxes = [], []
    for key, lat, lon, n, place, proc, rtt, life, ago, fresh in rows[:limit]:
        text = place + (" \u00b7 " + proc if proc else "") + (" \u00b7 000 ms" if rtt is not None else "")
        west_of_home = home_lon is not None and ((lon - home_lon + 540) % 360) - 180 < 0
        span = 1.5 + 1.2 * len(text)
        left, right = (lon - span, lon) if west_of_home else (lon, lon + span)
        clash = any(abs(lat - la) < 2.6 and left < r and l < right for la, l, r in boxes)
        if not clash:
            boxes.append((lat, left, right))
        peers.append({"key": key, "lat": lat, "lon": lon, "n": n, "place": place, "proc": proc,
                      "show": not clash, "side": "left" if west_of_home else "right",
                      "rtt": -1 if rtt is None else round(rtt, 1), "life": life, "ago": ago, "fresh": fresh})
    return peers


def cmd_net(args):
    note, peers = "", []
    try:
        import maxminddb
    except ImportError:
        maxminddb = None
        note = "install the python 'maxminddb' module (python3-maxminddb / python-maxminddb)."
    if maxminddb and not GEOIP.exists():
        note = "no GeoIP database yet - Status > Update GeoIP database, or run: livemap-helper fetch-geoip"
    elif maxminddb:
        try:
            with maxminddb.open_database(str(GEOIP)) as reader:
                peers = locate(connections(), reader, max(1, args.max), args.home_lon, args.linger, args.new_window)
        except Exception as e:                       # show it on the desktop instead of failing silently
            note = "%s" % e
    if args.table:
        print(note or "%d places" % len(peers))
        for p in peers:
            print("%4d  %8.2f %8.2f  %-9s %s%s%s%s%s" % (
                p["n"], p["lat"], p["lon"], p["life"] + ("" if not p["ago"] else " %ds" % p["ago"]), p["place"],
                " \u00b7 " + p["proc"] if p["proc"] else "", "  %g ms" % p["rtt"] if p["rtt"] >= 0 else "",
                "  NEW " + p["fresh"].upper() if p["fresh"] else "", "" if p["show"] else "   [no label: would overlap]"))
    else:
        emit({"peers": peers, "note": note})


def cmd_where(args):
    """Where would the map draw this host? Answers 'why did my .za site not show up in South Africa'."""
    import maxminddb
    with maxminddb.open_database(str(GEOIP)) as reader:
        for host in args.hosts:
            try:
                ips = sorted({ai[4][0] for ai in socket.getaddrinfo(host, None)})
            except OSError as e:
                print("%s: %s" % (host, e))
                continue
            for ip in ips:
                hit = lookup(reader, ip) if ipaddress.ip_address(ip).is_global else None
                print("%-28s %-40s %s" % (host, ip, "%s  (%.2f, %.2f)" % (hit[3], hit[1], hit[2]) if hit else "not in the database / not public"))


def cmd_forget(_args):
    SEEN.unlink(missing_ok=True)
    print("Connection memory cleared: the next run becomes the new baseline.")


def chk_memory():
    try:
        mem = json.loads(SEEN.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "ok", "empty - it starts with the next look at the connections"
    return "ok", "%d places in %d countries remembered since %s (kept only on this computer)" % (
        len(mem["places"]), len(mem["countries"]), date.fromtimestamp(mem.get("since", 0)))


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
    rivers = _lines("ne_%s_rivers_lake_centerlines" % river_scale, 0.02 if river_scale == "50m" else 0.0) if args.rivers else []
    if rivers and river_scale == "50m" and scale == "110m":   # finer rivers than coast: carry the mouths on to the coast
        rivers = rivers + _river_mouths(0.02)
    res = {"coast": _lines("ne_%s_coastline" % scale, step),
           "borders": _lines("ne_%s_admin_0_boundary_lines_land" % scale, step),
           "states": _lines("ne_50m_admin_1_states_provinces_lines", 0.04) if args.states else [],
           "rivers": rivers,
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


# ------------------------------------------------- oil and gas infrastructure -----
# Fixed structures only: offshore platforms and refineries. Two public sources, both fetched on demand:
#   BSEE / BOEM "Platforms" shapefile: every structure on the US Gulf of Mexico shelf (public domain, monthly)
#   OpenStreetMap via the Overpass API: man_made=offshore_platform worldwide and industrial=refinery
#   (c) OpenStreetMap contributors, ODbL. Mobile drilling rigs are in no free feed and are not here.
INFRA = DATA / "infrastructure.json"
BSEE_PLATFORMS = "https://www.data.bsee.gov/Mapping/Files/platform.zip"
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]   # the second is a mirror
# the world in longitude bands: one global query times out (504) on the public servers, eight smaller ones do not
WORLD_BANDS = [(-180, -120), (-120, -60), (-60, 0), (0, 40), (40, 80), (80, 120), (120, 180)]


def _shp_points(shp_bytes):
    """Point coordinates from an ESRI shapefile's .shp (shape type 1), in file order. The format is fixed
    width: a 100-byte header, then per record an 8-byte big-endian header and the little-endian shape."""
    import struct
    if len(shp_bytes) < 100 or struct.unpack(">i", shp_bytes[:4])[0] != 9994:
        raise ValueError("not a shapefile")
    shape_type = struct.unpack("<i", shp_bytes[32:36])[0]
    if shape_type not in (1, 11, 21):                       # Point, PointZ, PointM
        raise ValueError("shapefile is not a point layer (type %d)" % shape_type)
    pts, pos = [], 100
    while pos + 8 <= len(shp_bytes):
        length = struct.unpack(">i", shp_bytes[pos + 4:pos + 8])[0] * 2
        rec = shp_bytes[pos + 8:pos + 8 + length]
        if len(rec) >= 20 and struct.unpack("<i", rec[:4])[0] in (1, 11, 21):
            x, y = struct.unpack("<dd", rec[4:20])
            pts.append((x, y))
        else:
            pts.append(None)                                # a null shape keeps the record count aligned
        pos += 8 + length
    return pts


def _dbf_rows(dbf_bytes, wanted):
    """The named columns of a dBASE III/IV table, one dict per record, decoded as latin-1 (the BSEE files)."""
    import struct
    n_rec, hdr_len, rec_len = struct.unpack("<IHH", dbf_bytes[4:12])
    fields, pos = [], 32
    while pos + 32 <= hdr_len and dbf_bytes[pos] != 0x0D:
        name = dbf_bytes[pos:pos + 11].split(b"\0")[0].decode("latin-1").strip().upper()
        size = dbf_bytes[pos + 16]
        fields.append((name, size)); pos += 32
    rows, pos = [], hdr_len
    for _ in range(n_rec):
        rec = dbf_bytes[pos:pos + rec_len]; pos += rec_len
        if len(rec) < rec_len:
            break
        row, off = {}, 1                                    # byte 0 is the deletion flag
        for name, size in fields:
            if name in wanted:
                row[name] = rec[off:off + size].decode("latin-1", "replace").strip()
            off += size
        rows.append(None if rec[:1] == b"*" else row)
    return rows


def fetch_bsee_platforms():
    """Gulf of Mexico structures from the BSEE shapefile: [lon, lat, name]. Removed structures are left out."""
    import io, zipfile
    _c, _h, body, _t = _http(BSEE_PLATFORMS, timeout=60, limit=MAX_DOWNLOAD)
    z = zipfile.ZipFile(io.BytesIO(body))
    shp = next((n for n in z.namelist() if n.lower().endswith(".shp")), None)
    dbf = next((n for n in z.namelist() if n.lower().endswith(".dbf")), None)
    if not shp or not dbf:
        raise ValueError("platform.zip holds no .shp/.dbf")
    pts = _shp_points(z.read(shp))
    rows = _dbf_rows(z.read(dbf), {"STRUCTURE_NAME", "REMOVAL_DATE", "STRUCTURE_", "REMOVAL_DA", "COMPLEX_ID",
                                   "AREA_CODE", "BLOCK_NUMBER", "BLOCK_NUMB", "BUS_ASC_NAME", "BUS_ASC_NA"})
    out = []
    for pt, row in zip(pts, rows):
        if pt is None or row is None:
            continue
        removed = (row.get("REMOVAL_DATE") or row.get("REMOVAL_DA") or "").strip()
        if removed and removed not in ("0", "00000000"):
            continue
        # "MC 807 A": area, block and structure, the way the Gulf refers to a platform (a bare "A" or "1" says nothing)
        struct = (row.get("STRUCTURE_NAME") or row.get("STRUCTURE_") or "").strip()
        area, block = (row.get("AREA_CODE") or "").strip(), (row.get("BLOCK_NUMBER") or row.get("BLOCK_NUMB") or "").strip().lstrip("0")
        name = " ".join(t for t in (area, block, struct) if t)
        if -100 < pt[0] < -80 and 24 < pt[1] < 31:          # the Gulf; a stray record elsewhere is noise
            out.append([round(pt[0], 4), round(pt[1], 4), name[:40]])
    return out


def fetch_overpass(query, bbox=None, log=print):
    """One Overpass query (POST), optionally inside a (south, west, north, east) box, answered as JSON; elements
    with a centre: [lon, lat, name]. The English name is preferred for the label. Tries each server once,
    then once more after a pause: the public servers answer 504 when busy."""
    import time
    box = "(%s,%s,%s,%s)" % bbox if bbox else ""
    q = "[out:json][timeout:180];" + query.replace(";", box + ";", 1) + "out center;"
    data = ("data=" + urllib.request.quote(q)).encode()
    last = None
    for attempt in range(2):
        for server in OVERPASS:
            try:
                req = urllib.request.Request(server, data=data, headers=dict(UA, **{"Content-Type": "application/x-www-form-urlencoded"}), method="POST")
                with urllib.request.urlopen(req, timeout=200) as r:
                    body = r.read(MAX_BODY + 1)
                if len(body) > MAX_BODY:
                    raise ValueError("Overpass answer larger than expected")
                out = []
                for el in json.loads(body).get("elements", []):
                    c = el if el.get("type") == "node" else el.get("center") or {}
                    lon, lat = c.get("lon"), c.get("lat")
                    if lon is None or lat is None:
                        continue
                    tags = el.get("tags") or {}
                    name = tags.get("name:en") or tags.get("int_name") or tags.get("name") or tags.get("ref") or ""
                    out.append([round(float(lon), 4), round(float(lat), 4), str(name)[:40]])
                return out
            except Exception as e:
                last = e
                log("  %s: %s" % (server.split("/")[2], e))
        time.sleep(15)
    raise last


def fetch_overpass_world(query, log=print):
    """The query over the whole world, band by band; a band the server cannot answer (the Gulf of Mexico's
    thousands of platforms as ways answer 500) is split in half and tried again, down to 15 degrees; what still
    fails is reported and the rest kept."""
    out, failed = [], []
    def band(west, east):
        try:
            got = fetch_overpass(query, (-85, west, 85, east), log=log)
            out.extend(got)
            log("  %s: %d in %d..%d" % (query[:40], len(got), west, east))
        except Exception as e:
            if east - west > 15:
                mid = (west + east) // 2
                log("  %d..%d failed (%s): splitting" % (west, east, e))
                band(west, mid); band(mid, east)
            else:
                failed.append("%d..%d: %s" % (west, east, e))
    for west, east in WORLD_BANDS:
        band(west, east)
    seen, uniq = set(), []
    for p in out:                                 # an element on a band edge can come back twice
        k = (p[0], p[1])
        if k not in seen:
            seen.add(k); uniq.append(p)
    return uniq, failed


def cmd_fetch_infrastructure(_args):
    """Download the platforms and refineries into infrastructure.json (a minute or two: Overpass is slow)."""
    import time
    result, problems = {"platforms": [], "refineries": [], "at": time.time()}, []
    try:
        gulf = fetch_bsee_platforms()
        result["platforms"] += gulf
        print("  BSEE: %d Gulf of Mexico structures" % len(gulf))
    except Exception as e:
        problems.append("BSEE platforms: %s" % e); print("  BSEE failed: %s" % e)
    try:
        osm, failed = fetch_overpass_world('nwr["man_made"="offshore_platform"];')
        if failed:
            problems.append("OSM platforms, some areas missing: " + "; ".join(failed))
        before = len(result["platforms"])
        # the Gulf is covered by BSEE in full: OSM platforms within 2 km of a BSEE one are the same structure
        for p in osm:
            if -100 < p[0] < -80 and 24 < p[1] < 31 and any(haversine_km(p[1], p[0], g[1], g[0]) < 2 for g in result["platforms"][:before]):
                continue
            result["platforms"].append(p)
        print("  OpenStreetMap: %d offshore platforms (%d outside the BSEE set)" % (len(osm), len(result["platforms"]) - before))
    except Exception as e:
        problems.append("OSM platforms: %s" % e); print("  OSM platforms failed: %s" % e)
    try:
        result["refineries"], failed = fetch_overpass_world('nwr["industrial"="refinery"];')
        if failed:
            problems.append("OSM refineries, some areas missing: " + "; ".join(failed))
        print("  OpenStreetMap: %d refineries" % len(result["refineries"]))
    except Exception as e:
        problems.append("OSM refineries: %s" % e); print("  OSM refineries failed: %s" % e)
    if not result["platforms"] and not result["refineries"]:
        sys.exit("Nothing downloaded: " + "; ".join(problems))
    result["problems"] = problems
    INFRA.parent.mkdir(parents=True, exist_ok=True)
    tmp = INFRA.with_suffix(".tmp%d" % os.getpid())
    tmp.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    tmp.replace(INFRA)
    print("Done. Platforms: BSEE (public domain) and (c) OpenStreetMap contributors (ODbL); refineries: OpenStreetMap.")


def cmd_infrastructure(_args):
    """Platforms and refineries for the wallpaper, from infrastructure.json."""
    try:
        d = json.loads(INFRA.read_text(encoding="utf-8"))
        emit({"platforms": d.get("platforms", []), "refineries": d.get("refineries", []), "at": d.get("at", 0), "note": ""})
    except (OSError, ValueError):
        emit({"platforms": [], "refineries": [], "note": "Oil and gas infrastructure: no data yet - press Download in the settings, "
                                                          "or run: livemap-helper fetch-infrastructure"})


def chk_infrastructure():
    try:
        d = json.loads(INFRA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "warn", "not downloaded - press Download (or run: livemap-helper fetch-infrastructure); a minute or two"
    age = (time.time() - d.get("at", 0)) / 86400
    extra = "; incomplete, download again: " + "; ".join(d["problems"]) if d.get("problems") else ""
    regions = (("Gulf of Mexico", -100, 18, -80, 31), ("North Sea", -5, 50, 12, 65), ("Mediterranean", -6, 30, 37, 46),
               ("West Africa", -20, -20, 15, 10), ("Persian Gulf", 47, 23, 58, 31), ("Asia-Pacific", 90, -45, 180, 45))
    counts = {}
    for p in d.get("platforms", []):
        for name, w, so, e, no in regions:
            if w <= p[0] <= e and so <= p[1] <= no:
                counts[name] = counts.get(name, 0) + 1
                break
        else:
            counts["elsewhere"] = counts.get("elsewhere", 0) + 1
    where = ", ".join("%s %d" % (k, counts[k]) for k in [r[0] for r in regions] + ["elsewhere"] if counts.get(k))
    return ("warn" if age > 120 or d.get("problems") else "ok"), "%d platforms (%s), %d refineries, downloaded %d days ago%s" % (
        len(d.get("platforms", [])), where or "none", len(d.get("refineries", [])), age, extra)


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


def _facility_list(hits):
    """Facilities for the widget: named ones by name, the unnamed ones (most platforms) counted."""
    out, unnamed = [], {0: 0, 1: 0}
    for lon, lat, kind, name in hits:
        if name:
            out.append({"name": name, "kind": "refinery" if kind == 1 else "platform", "lat": round(lat, 3), "lon": round(lon, 3)})
        else:
            unnamed[kind] += 1
    out.sort(key=lambda f: (f["kind"] != "refinery", f["name"]))
    for kind in (1, 0):
        if unnamed[kind]:
            out.append({"name": "%d unnamed %s" % (unnamed[kind], ("refiner" + ("y" if unnamed[kind] == 1 else "ies")) if kind else ("platform" + ("" if unnamed[kind] == 1 else "s"))),
                        "kind": "refinery" if kind == 1 else "platform", "count": unnamed[kind]})
    return out


def storm_impacts(storms, corridor_km=120, crossed_km=100):
    """Which platforms and refineries each storm threatens, split into what it has already crossed (within
    crossed_km of its past track or its position now) and what lies ahead (inside its forecast cone, or - for a
    storm without a cone - within corridor_km of a forecast point). Adds st["impact"] = {platforms, refineries,
    names, how, crossed, ahead} and returns the facilities for the map: [lon, lat, kind, name, storm, crossed].
    Runs after the track is assembled, so a storm this wallpaper has followed itself gets its breadcrumbs too."""
    try:
        d = json.loads(INFRA.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    facilities = [(p[0], p[1], 0, p[2]) for p in d.get("platforms", [])] + [(r[0], r[1], 1, r[2]) for r in d.get("refineries", [])]
    out = []
    for st in storms:
        past = [(p[0], p[1]) for p in (st.get("track") or [])]
        if not st.get("gone"):
            past.append((st["lon"], st["lat"]))
        rings = [] if st.get("gone") else [r for r in (st.get("cone") or []) if len(r) >= 8]
        boxes = [(min(r[0::2]), min(r[1::2]), max(r[0::2]), max(r[1::2])) for r in rings]
        anchors = [] if rings or st.get("gone") else [(f[i], f[i + 1]) for f in (st.get("forecast") or []) for i in range(0, len(f) - 1, 2)]
        crossed, ahead = [], []
        for lon, lat, kind, name in facilities:
            if past and _near_path(lon, lat, past, crossed_km):
                crossed.append((lon, lat, kind, name))
            elif rings:
                if any(bx[0] <= lon <= bx[2] and bx[1] <= lat <= bx[3] and _in_ring(lon, lat, r) for r, bx in zip(rings, boxes)):
                    ahead.append((lon, lat, kind, name))
            elif anchors and abs(lat - st["lat"]) < 15 and any(haversine_km(lat, lon, a[1], a[0]) <= corridor_km for a in anchors):
                ahead.append((lon, lat, kind, name))
        if not crossed and not ahead:
            st.pop("impact", None)
            continue
        names = [h[3] for h in ahead if h[2] == 1 and h[3]][:4]
        st["impact"] = {"platforms": sum(1 for h in ahead if h[2] == 0), "refineries": sum(1 for h in ahead if h[2] == 1),
                        "names": names, "how": "cone" if rings else "track",
                        "crossed": _facility_list(crossed), "ahead": _facility_list(ahead),
                        "crossed_n": len(crossed), "ahead_n": len(ahead)}
        out += [[h[0], h[1], h[2], h[3], st["name"], 0] for h in ahead] + [[h[0], h[1], h[2], h[3], st["name"], 1] for h in crossed]
    return out


def impact_text(im):
    """'5 refineries, 12 platforms in the cone · crossed 2 platforms' for a storm label or a feed title."""
    if not im:
        return ""
    parts = []
    if im.get("platforms"):
        parts.append("%d platform%s" % (im["platforms"], "" if im["platforms"] == 1 else "s"))
    if im.get("refineries"):
        parts.append("%d refiner%s" % (im["refineries"], "y" if im["refineries"] == 1 else "ies"))
    ahead = (", ".join(parts) + (" in the cone" if im.get("how") == "cone" else " near the track")) if parts else ""
    crossed = ("crossed %d facilit%s" % (im["crossed_n"], "y" if im["crossed_n"] == 1 else "ies")) if im.get("crossed_n") else ""
    return " \u00b7 ".join(t for t in (ahead, crossed) if t)


def _remember_impacts(storms):
    """Keep each storm's impact in its memory entry, so the feed (and so the widget) lists the facilities a storm
    crossed and those ahead - also once the storm is gone and only the memory is left."""
    try:
        mem = json.loads(EVENTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return
    bucket = mem.get("storm") or {}
    changed = False
    for st in storms:
        e = bucket.get(str(st.get("name", "")).lower())
        if not isinstance(e, dict) or not isinstance(e.get("item"), dict):
            continue
        if e["item"].get("impact") != st.get("impact"):
            if st.get("impact"):
                e["item"]["impact"] = st["impact"]
            else:
                e["item"].pop("impact", None)
            changed = True
    if changed:
        try:
            tmp = EVENTS.with_suffix(".tmp%d" % os.getpid())
            tmp.write_text(json.dumps(mem), encoding="utf-8")
            tmp.replace(EVENTS)
        except OSError:
            pass


def cmd_plates(_args):
    """Tectonic plate boundaries as flat polylines for the wallpaper (same shape as `borders`)."""
    lines = _lines(PLATES_FILE, 0.0)
    emit({"plates": lines or [],
          "note": "" if lines is not None else "Plate boundaries: no data yet - press 'Download border data' in the "
                                               "settings, or run: livemap-helper fetch-borders"})


def chk_plates():
    f = BORDERS / (PLATES_FILE + ".geojson")
    if f.exists():
        return "ok", "PB2002 plate boundaries (%.1f MB)" % (f.stat().st_size / 1e6)
    return "warn", "not downloaded - press 'Download border data' (or run: livemap-helper fetch-borders)"


def cmd_where_city(args):
    """Offline city search in Natural Earth's populated places (about 7 000 towns and cities), for the home setting."""
    f = BORDERS / "ne_10m_populated_places_simple.geojson"
    if not f.exists():
        emit({"places": [], "note": "No city list yet - press 'Download border data' in the Status section first"})
        return
    q = _plain(args.query.strip())
    hits = []
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        p = feat.get("properties") or {}
        name = str(p.get("name") or "")
        plain = _plain(name)
        if q and (plain.startswith(q) or q in plain or q in _plain("%s, %s" % (name, p.get("adm0name") or ""))):
            c = (feat.get("geometry") or {}).get("coordinates") or [p.get("longitude"), p.get("latitude")]
            hits.append({"name": name, "region": p.get("adm1name") or "", "country": p.get("adm0name") or "",
                         "lat": round(float(c[1]), 4), "lon": round(float(c[0]), 4), "pop": int(p.get("pop_max") or 0),
                         "exact": plain == q})
    hits.sort(key=lambda h: (not h["exact"], -h["pop"]))
    emit({"places": hits[:12], "note": ""})


def chk_borders():
    have = [n for n in NE_FILES if (BORDERS / (n + ".geojson")).exists()]
    if len(have) == len(NE_FILES):
        mb = sum((BORDERS / (n + ".geojson")).stat().st_size for n in have) / 1e6
        return "ok", "%d of %d Natural Earth layers (%.1f MB)" % (len(have), len(NE_FILES), mb)
    return "warn", "%d of %d layers - press 'Download border data' (or run: livemap-helper fetch-borders)" % (len(have), len(NE_FILES))


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


# --------------------------------------------------------------- storms -----
GDACS = "https://www.gdacs.org/gdacsapi/api/events/geteventlist/EVENTS4APP"


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
            return json.loads(_http(GDACS, timeout=20)[2])
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
    body = json.loads(_http(NHC, timeout=15)[2].decode("utf-8", "replace"))
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
    if not storms and not nhc:
        raise RuntimeError("; ".join(errors))
    for st in storms:
        st["ids"] = ["gdacs:%s" % st["id"]] if st.get("id") else []
    for n in nhc:
        n["ids"] = ["nhc:%s" % n["id"]] if n.get("id") else []
    by_name = {st["name"].lower(): st for st in storms}
    matched = set()
    for n in nhc:
        st = by_name.get(n["name"].lower())
        if st is None:                                  # the two feeds rename a storm at different moments ("Twenty-E" ->
            best, best_km = None, 250                   # "Rachel"): the same storm is the one within 250 km that no name matched
            for cand in storms:
                if id(cand) in matched or cand.get("source", "").endswith("NHC"):
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
            st["was_named"] = st["name"]                # the NHC name is the official one
            st["name"] = n["name"]
        st.update(wind=n["wind"], kind=n["kind"], cat=n["cat"], wind_is_peak=False, source=(st.get("source") or "GDACS") + "+NHC")
        if n.get("hours") is not None and (st.get("hours") is None or n["hours"] < st["hours"]):
            st["hours"] = n["hours"]
        for k in ("forecast", "cone", "dots", "track"):
            if not st.get(k) and n.get(k):
                st[k] = n[k]
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


FIRMS = "https://firms.modaps.eosdis.nasa.gov/data/active_fire/modis-c6.1/csv/MODIS_C6_1_Global_24h.csv"
HOTSPOTS = DATA / "hotspots.csv"
HOTSPOT_MEMORY = DATA / "hotspot-days.json"    # per half-degree cell: which of the last 30 days it burned, and how hard


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
    """NASA FIRMS active fire detections (MODIS, last 24 h, no key needed; a few MB), cached for three hours."""
    import time
    if not HOTSPOTS.exists() or time.time() - HOTSPOTS.stat().st_mtime > max_age_h * 3600:
        req = urllib.request.Request(FIRMS, headers=UA)
        tmp = HOTSPOTS.with_suffix(".part")
        HOTSPOTS.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
            data = r.read(MAX_BODY + 1)
            if len(data) > MAX_BODY:
                raise ValueError("FIRMS file larger than expected")
            f.write(data)
        tmp.replace(HOTSPOTS)
    return HOTSPOTS.read_text(encoding="utf-8", errors="replace")


def cluster_hotspots(csv_text, cell=0.5, min_conf=50, now=None):
    """Detections -> cells of `cell` degrees: [{lat, lon, n, frp, hours}] with the fire radiative power summed (MW)
    and the age of the newest detection. Low-confidence detections are ignored."""
    import csv, io, time
    from datetime import datetime, timezone
    now = now or time.time()
    cells = {}
    for row in csv.DictReader(io.StringIO(csv_text)):
        try:
            if float(row.get("confidence") or 0) < min_conf:
                continue
            lat, lon, frp = float(row["latitude"]), float(row["longitude"]), float(row.get("frp") or 0)
            t = datetime.strptime(row["acq_date"] + row["acq_time"].zfill(4), "%Y-%m-%d%H%M").replace(tzinfo=timezone.utc).timestamp()
        except (KeyError, ValueError):
            continue
        k = (int(lat // cell), int(lon // cell))
        c = cells.setdefault(k, {"lat": 0.0, "lon": 0.0, "n": 0, "frp": 0.0, "t": 0})
        c["n"] += 1; c["frp"] += frp; c["lat"] += lat; c["lon"] += lon; c["t"] = max(c["t"], t)
    out = []
    for c in cells.values():
        out.append({"lat": round(c["lat"] / c["n"], 2), "lon": round(c["lon"] / c["n"], 2), "n": c["n"],
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
        print(note or "%d hotspot clusters (0.5 degree cells, tier %d and up, NASA FIRMS MODIS 24 h)" % (len(spots), args.min_tier))
        for c in spots[:60]:
            print("  %7.2f, %7.2f  %4d detections  %6d MW  newest %.0f h ago  %s  %s" % (
                c["lat"], c["lon"], c["n"], c["frp"], c["hours"], ["background", "notable", "ATTENTION"][c["tier"]], c["why"]))
    else:
        emit({"hotspots": spots, "note": note})


def chk_hotspots():
    spots = cluster_hotspots(fetch_hotspots())
    big = [c for c in spots if c["n"] >= 25]
    return "ok", "%d detections in %d cells (MODIS, last 24 h), %d cells with 25+ detections; strongest %s MW at %.1f, %.1f" % (
        sum(c["n"] for c in spots), len(spots), len(big), spots[0]["frp"] if spots else 0, spots[0]["lat"] if spots else 0, spots[0]["lon"] if spots else 0)


def chk_fires():
    fires = fetch_fires()
    hot = [fr for fr in fires if fr["alert"] in ("orange", "red")]
    return "ok", "%d current wildfire events, %d orange or red%s" % (
        len(fires), len(hot), ": " + ", ".join("%s (%s)" % (fr["name"], fr["alert"]) for fr in hot[:6]) if hot else "")


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
                fl["people"] = _sendai_summary(json.loads(_http(urls.get("details"), timeout=12)[2]))
            except Exception as e:
                fl["problem"] = "details: %s" % e
            try:
                fl["area"] = flood_area(json.loads(_http(urls.get("geometry"), timeout=15, limit=MAX_BODY)[2]))
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
NWS_UA = dict(UA, Accept="application/geo+json")
NWS_UA["User-Agent"] = "livemap-wallpaper/" + VERSION + " (github.com/TidyBitz/livemap)"
NWS_LEVEL = {"Flash Flood Warning": "red", "Flood Warning": "orange", "Coastal Flood Warning": "orange",
             "Flood Watch": "green", "Flash Flood Watch": "green", "Flood Advisory": "green"}
NWS_ZONES_PER_RUN = 40                           # new zone polygons fetched per refresh; the rest come next time (cached for good)


def _nws_get(url, timeout=12):
    import time
    with urllib.request.urlopen(urllib.request.Request(url, headers=NWS_UA), timeout=timeout) as r:
        body = r.read(MAX_BODY + 1)
        if len(body) > MAX_BODY:
            raise ValueError("response too large")
        return json.loads(body)


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
                    "counties": len(counties), "office": str(pr.get("senderName") or "").replace("NWS ", ""), "lat": round(lat, 3), "lon": round(lon, 3),
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
            g = groups[k] = dict(a, members=[], area=[], counties_list=[], lats=[], lons=[], counties=0)
            g["id"] = "nws:" + re.sub(r"[^A-Za-z0-9]+", "-", a["office"] + "-" + a["event"]).strip("-").lower()
        g["members"].append(a["id"])
        g["counties"] += a.get("counties") or 0
        g["area"] = (g["area"] + a["area"])[:24]
        g["counties_list"] += [c.strip() for c in a["name"].replace(", +", ";+").split(";") if c.strip() and not c.strip().startswith("+")]
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
        g["counties"] = max(len(counties), g["counties"])   # the sum of the alerts' counts, or the named ones
        g["name"] = ("%d counties" % g["counties"] if g["counties"] > 2 else "; ".join(counties)) + (" \u00b7 " + g["office"] if g["office"] else "")
        g["url"] = "https://alerts.weather.gov/search?area=" + urllib.request.quote(g["office"]) if n > 1 else g["url"]
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


def cmd_nws_floods(args):
    note, alerts = "", []
    data, stale_h, err = nws_floods_cached(args.max_age)
    if err:
        note = stale_note("US flood alerts", stale_h, err, args.stale)
    try:
        alerts = remember_events("nwsflood", data or [], lambda a: a["id"], 0.5, sig_of=lambda a: a["alert"])
        alerts = [a for a in alerts if not a.get("gone")]       # an alert that ended is simply gone: no ageing out
        if not args.each:
            alerts = group_nws(alerts)
    except Exception as e:
        note = note or "US flood alerts: %s" % e
    if args.table:
        import time
        print(note or "%d active NWS flood alerts" % len(alerts))
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
EFFIS = ("https://maps.effis.emergency.copernicus.eu/effis?service=WFS&version=1.1.0&request=GetFeature&typename=ms:modis.ba.poly"
         "&outputformat=geojson&maxfeatures=1500&FILTER=%%3CFilter%%3E%%3CPropertyIsGreaterThanOrEqualTo%%3E%%3CPropertyName%%3Efiredate%%3C%%2FPropertyName%%3E"
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
    geo = json.loads(_http(NIFC, timeout=40, limit=MAX_BODY)[2])
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
    fires = json.loads(_http(CWFIS_FIRES, timeout=30)[2]).get("features", [])
    try:
        since_day = datetime.utcfromtimestamp(now - 14 * 86400).strftime("%Y-%m-%d")
        perims = json.loads(_http(CWFIS_PERIMS % since_day, timeout=40, limit=MAX_BODY)[2]).get("features", [])
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
    geo = json.loads(_http(EFFIS % since_day, timeout=40, limit=MAX_BODY)[2])
    out = []
    for f in geo.get("features", []):
        pr = f.get("properties") or {}
        rings = flood_area({"features": [f]})
        lat, lon = _poly_centre(rings)
        if lat is None:
            continue
        since, days, hours = "", None, 0
        try:
            t = datetime.strptime(str(pr.get("firedate"))[:10], "%Y-%m-%d").timestamp()
            since = datetime.utcfromtimestamp(t).strftime("%Y %b %d")
            days = max(0, round((now - t) / 86400, 1))
        except (ValueError, TypeError):
            pass
        try:
            hours = round((now - datetime.strptime(str(pr.get("lastupdate"))[:19], "%Y-%m-%d %H:%M:%S").timestamp()) / 3600, 1)
        except (ValueError, TypeError):
            pass
        name = ", ".join(x for x in (pr.get("commune"), pr.get("province")) if x) or str(pr.get("country") or "Fire")
        out.append(_incident("effis", pr.get("id") or f.get("id"), name, lat, lon, float(pr.get("area_ha") or 0), rings,
                             since=since, days=days, hours=hours, region=str(pr.get("country") or ""),
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
    for src in wanted:
        data, stale_h, err = incidents_cached(src, args.max_age)
        if err:
            notes.append(stale_note({"nifc": "US fire incidents", "cwfis": "Canadian fires", "effis": "European burnt areas"}[src], stale_h, err, args.stale))
        items += [it for it in (data or []) if it["area_ha"] >= args.min_ha]
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


# ---------------------------------------------------------------- air raid alerts ----
# Ukraine's civil air-raid alerts by oblast, from alerts.in.ua (the volunteer API behind most alert apps; a free
# personal token from alerts.in.ua/api-request, 8-10 requests a minute allowed, this asks once a minute) or, with
# no token, a public mirror of the same data at oblast level (ubilling.net.ua, no key, air raid only). The oblast
# polygons ship with the package (Natural Earth 10m admin-1, thinned): data/ukraine-regions.json, keyed by ISO 3166-2.
ALERTS_API = "https://api.alerts.in.ua/v1/alerts/active.json"
ALERTS_MIRROR = "https://ubilling.net.ua/aerialalerts/?json=true"
ALERTS_MEMORY = DATA / "air-alerts.json"
AIR_CLEAR_MINUTES = 30                            # an ended alert stays listed as "all clear" this long
UA_REGIONS = Path(__file__).resolve().parent.parent / "data" / "ukraine-regions.json"
# the oblast names the sources use (Ukrainian), by ISO 3166-2 code; matched on the stem so "м. Київ", "Київ" and
# "Київська область" all land
UA_STEMS = {"UA-43": "крим", "UA-07": "волин", "UA-05": "вінниц", "UA-12": "дніпропетров", "UA-14": "донец", "UA-18": "житомир",
            "UA-21": "закарпат", "UA-23": "запорі", "UA-26": "івано-франків", "UA-30": "київ", "UA-32": "київська", "UA-35": "кіровоград",
            "UA-09": "луган", "UA-46": "львів", "UA-48": "миколаїв", "UA-51": "одес", "UA-53": "полтав", "UA-56": "рівнен",
            "UA-40": "севастополь", "UA-59": "сум", "UA-61": "тернопіл", "UA-63": "харків", "UA-65": "херсон", "UA-68": "хмельниц",
            "UA-71": "черкас", "UA-77": "чернівец", "UA-74": "чернігів"}
ALERT_TYPES = {"air_raid": "air raid", "artillery_shelling": "artillery shelling", "urban_fights": "street fighting",
               "chemical": "chemical threat", "nuclear": "nuclear threat"}


def ua_region_code(title):
    """ISO code for an oblast title in Ukrainian ("Київська область", "м. Київ", "Автономна Республіка Крим")."""
    t = str(title or "").lower().replace("м.", "").replace("область", "").replace("автономна республіка", "").strip()
    if t.startswith("київська") or (t.startswith("київ") and "область" in str(title).lower()):
        return "UA-32"
    for code, stem in UA_STEMS.items():
        if code in ("UA-32",):
            continue
        if t.startswith(stem):
            return code
    return None


def ua_regions():
    try:
        return json.loads(UA_REGIONS.read_text(encoding="utf-8")).get("regions", [])
    except (OSError, ValueError):
        return []


def fetch_air_alerts(token=""):
    """{code: {status, types, since}} for every oblast with something active. status A (the whole oblast),
    P (part of it: a raion, hromada or city) from the API; the mirror only knows A."""
    import time
    now = time.time()
    out = {}
    if token:
        req = urllib.request.Request(ALERTS_API, headers=dict(UA, Authorization="Bearer " + token, Accept="application/json"))
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read(MAX_BODY))
        for a in data.get("alerts", []):
            code = ua_region_code(a.get("location_oblast") or a.get("location_title"))
            if not code:
                continue
            whole = a.get("location_type") == "oblast"
            since = None
            try:
                from datetime import datetime
                since = datetime.fromisoformat(str(a.get("started_at")).replace("Z", "+00:00")).timestamp()
            except (ValueError, TypeError):
                pass
            e = out.setdefault(code, {"status": "N", "types": [], "since": None, "places": []})
            if whole:
                e["status"] = "A"
            elif e["status"] != "A":
                e["status"] = "P"
                if a.get("location_title") and len(e["places"]) < 4:
                    e["places"].append(a.get("location_title_en") or a.get("location_title"))
            t = ALERT_TYPES.get(a.get("alert_type") or "", a.get("alert_type") or "")
            if t and t not in e["types"]:
                e["types"].append(t)
            if since and (e["since"] is None or since < e["since"]):
                e["since"] = since
        source = "alerts.in.ua"
    else:
        data = json.loads(_http(ALERTS_MIRROR, timeout=15)[2])
        for title, st in (data.get("states") or {}).items():
            if not (st or {}).get("alertnow"):
                continue
            code = ua_region_code(title)
            if code:
                out[code] = {"status": "A", "types": ["air raid"], "since": None, "places": []}
        source = "mirror"
    # Our own memory of when each alert started, for the mirror (which does not say). A start is only known when
    # this helper saw the oblast go from quiet to alert; an alert already on at the first look has no known start,
    # and is reported with since = null rather than a made-up time. The memory also says when the last look was,
    # so a gap in watching (the machine asleep) resets what counts as "seen begin".
    try:
        mem = json.loads(ALERTS_MEMORY.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    watching = now - float(mem.get("_at", 0)) < 600          # looked within the last ten minutes: a new alert is a seen start
    for code, e in out.items():
        m = mem.get(code)
        if e["since"] is not None:
            mem[code] = {"since": e["since"], "known": True, "first_seen": (m or {}).get("first_seen", now) if isinstance(m, dict) else now}
        elif isinstance(m, dict):
            e["since"] = m["since"] if m.get("known") else None
            m.setdefault("first_seen", m["since"])
        else:
            mem[code] = {"since": now, "known": watching, "first_seen": now}
            e["since"] = now if watching else None
        e["first_seen"] = mem[code].get("first_seen", now)
    # alerts that ended: kept for AIR_CLEAR_MINUTES as "all clear", so the map can show where one just finished
    cleared = mem.setdefault("_cleared", {})
    for code in list(mem):
        if code.startswith("_") or code in out:
            continue
        cleared[code] = {"ended": now, "since": mem[code].get("since") if mem[code].get("known") else None}
        del mem[code]
    for code in list(cleared):
        if code in out or now - cleared[code]["ended"] > AIR_CLEAR_MINUTES * 60:
            del cleared[code]
    for code, c in cleared.items():
        out[code] = {"status": "C", "types": [], "since": c.get("since"), "places": [], "ended": c["ended"], "first_seen": None}
    mem["_at"] = now
    try:
        ALERTS_MEMORY.parent.mkdir(parents=True, exist_ok=True)
        ALERTS_MEMORY.write_text(json.dumps(mem), encoding="utf-8")
    except OSError:
        pass
    return {"alerts": out, "source": source, "at": now}


def cmd_air_alerts(args):
    """`air-alerts [--token T] [--table]`: the oblasts under alert, with the regions' polygons on request (`--regions`)."""
    import time
    token = args.token or os.environ.get("LIVEMAP_ALERTS_TOKEN", "")
    data, stale_h, err = last_good("air-alerts", lambda: fetch_air_alerts(token))
    note = ""
    if err:
        note = stale_note("Air raid alerts", stale_h, err, args.stale)
    alerts = (data or {}).get("alerts", {})
    regions = ua_regions()
    rows = []
    for r in regions:
        e = alerts.get(r["code"])
        row = {"code": r["code"], "name": r["name"], "lat": r["lat"], "lon": r["lon"],
               "status": e["status"] if e else "N", "types": e["types"] if e else [], "since": e["since"] if e else None, "places": e["places"] if e else [],
               "first_seen": e.get("first_seen") if e else None, "ended": e.get("ended") if e else None}
        if args.regions:
            row["rings"] = r["rings"]
        rows.append(row)
    if args.table:
        print(note or "%d oblasts under alert (%s)" % (sum(1 for a in alerts.values() if a["status"] != "N"), (data or {}).get("source", "?")))
        for row in rows:
            if row["status"] == "N":
                continue
            print("  %-6s %-28s %s  %s  %s%s" % (row["code"], row["name"], row["status"], ", ".join(row["types"]) or ("all clear %.0f min ago" % ((time.time() - row["ended"]) / 60) if row.get("ended") else ""),
                                                 "%.0f min" % ((time.time() - row["since"]) / 60) if row["since"] else "",
                                                 "  (" + ", ".join(row["places"]) + ")" if row["places"] else ""))
    else:
        emit({"regions": rows, "source": (data or {}).get("source", ""), "note": note, "stale_hours": stale_h})


def chk_air_alerts():
    token = os.environ.get("LIVEMAP_ALERTS_TOKEN", "")
    d = fetch_air_alerts(token)
    on = [c for c, a in d["alerts"].items() if a["status"] in ("A", "P")]
    names = {r["code"]: r["name"] for r in ua_regions()}
    return "ok", "%d of 27 oblasts under alert (%s%s)%s" % (len(on), d["source"], "" if token else ": no token, oblast level only",
                                                             ": " + ", ".join(names.get(c, c) for c in on[:8]) if on else "")


# ---------------------------------------------------------------- space -----
# Satellites: two-line elements from CelesTrak (no key), propagated here with a Kepler + J2 model - the
# secular part of SGP4 (nodal and apsidal precession, mean-motion correction) without drag and short-period
# terms. For a low orbit with elements less than a day old that is within a few km of the full model, which
# is well under a pixel on this map. Elements are refreshed every six hours.
CELESTRAK = "https://celestrak.org/NORAD/elements/gp.php?CATNR=%s&FORMAT=TLE"
SATS = [("ISS", "25544", "International Space Station"), ("Hubble", "20580", "Hubble Space Telescope"),
        ("Tiangong", "48274", "Chinese space station")]
TLES = DATA / "tle.json"
MU, RE, J2 = 398600.4418, 6378.137, 1.08262668e-3


def fetch_tles(max_age_h=6):
    import time
    try:
        c = json.loads(TLES.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600 and len(c.get("tles", {})) == len(SATS):
            return c["tles"]
    except (OSError, ValueError):
        c = {}
    tles = dict(c.get("tles") or {})
    for short, catnr, _long in SATS:
        try:
            lines = _http(CELESTRAK % catnr)[2].decode("ascii", "replace").strip().splitlines()
            lines = [l.rstrip() for l in lines if l.strip()]
            if len(lines) >= 3 and lines[-2].startswith("1 ") and lines[-1].startswith("2 "):
                tles[short] = [lines[-3].strip(), lines[-2], lines[-1]]
        except Exception:
            pass
    if tles:
        try:
            TLES.parent.mkdir(parents=True, exist_ok=True)
            TLES.write_text(json.dumps({"at": time.time(), "tles": tles}), encoding="utf-8")
        except OSError:
            pass
    return tles


def parse_tle(l1, l2):
    import math
    from datetime import datetime, timezone, timedelta
    yy = int(l1[18:20]); year = 2000 + yy if yy < 57 else 1900 + yy
    epoch = (datetime(year, 1, 1, tzinfo=timezone.utc) + timedelta(days=float(l1[20:32]) - 1)).timestamp()
    ndot = float(l1[33:43])                                   # rev/day^2 (already halved in the TLE)
    return {"epoch": epoch, "ndot": ndot, "inc": math.radians(float(l2[8:16])), "raan": math.radians(float(l2[17:25])),
            "ecc": float("0." + l2[26:33].strip()), "argp": math.radians(float(l2[34:42])),
            "ma": math.radians(float(l2[43:51])), "n": float(l2[52:63])}


def gmst(t):
    """Greenwich mean sidereal time (radians) for a unix time."""
    import math
    jd = t / 86400.0 + 2440587.5
    T = (jd - 2451545.0) / 36525.0
    g = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T * T - T * T * T / 38710000.0
    return math.radians(g % 360.0)


def propagate(el, t):
    """(lat, lon, altitude km) of a TLE at unix time t. Kepler + J2 secular terms (see the note above)."""
    import math
    dt = t - el["epoch"]
    n0 = el["n"] * 2 * math.pi / 86400.0                       # rad/s (Kozai mean motion)
    e, i = el["ecc"], el["inc"]
    cosi, x = math.cos(i), 1 - e * e
    a1 = (MU / (n0 * n0)) ** (1 / 3)
    d1 = 1.5 * J2 * RE * RE / (a1 * a1) * (3 * cosi * cosi - 1) / (2 * x ** 1.5)
    a0 = a1 * (1 - d1 / 3 - d1 * d1 - 134 * d1 ** 3 / 81)
    d0 = 1.5 * J2 * RE * RE / (a0 * a0) * (3 * cosi * cosi - 1) / (2 * x ** 1.5)
    n = n0 / (1 + d0)                                          # Brouwer mean motion
    a = a0 / (1 - d0)
    p = a * x
    k = 1.5 * J2 * (RE / p) ** 2
    raan = el["raan"] - k * n * cosi * dt
    argp = el["argp"] + 0.5 * k * n * (5 * cosi * cosi - 1) * dt
    mdot = n * (1 + 0.5 * k * math.sqrt(x) * (3 * cosi * cosi - 1))
    m = el["ma"] + mdot * dt + el["ndot"] * 2 * math.pi / 86400.0 ** 2 * dt * dt
    m = m % (2 * math.pi)
    E = m if e < 0.8 else math.pi                               # Kepler's equation, Newton
    for _ in range(12):
        E -= (E - e * math.sin(E) - m) / (1 - e * math.cos(E))
    nu = 2 * math.atan2(math.sqrt(1 + e) * math.sin(E / 2), math.sqrt(1 - e) * math.cos(E / 2))
    r = a * x / (1 + e * math.cos(nu))
    u = argp + nu                                              # argument of latitude
    cu, su, cO, sO, si = math.cos(u), math.sin(u), math.cos(raan), math.sin(raan), math.sin(i)
    X = r * (cO * cu - sO * su * cosi)
    Y = r * (sO * cu + cO * su * cosi)
    Z = r * (su * si)
    lon = (math.degrees(math.atan2(Y, X) - gmst(t)) + 540) % 360 - 180
    lat = math.degrees(math.atan2(Z, math.sqrt(X * X + Y * Y)))
    lat += math.degrees(0.00335 * math.sin(2 * math.radians(lat)))   # geocentric -> geodetic, first order
    return lat, lon, r - RE


def cmd_sats(args):
    """Positions now and a ground track for the next `--ahead` minutes (a point every 30 s), so the wallpaper
    can move the marker itself between two runs of this command."""
    import time
    note, out, now = "", [], time.time()
    try:
        tles = fetch_tles()
    except Exception as e:
        tles, note = {}, "Satellites: %s" % e
    for short, _catnr, longname in SATS:
        tle = tles.get(short)
        if not tle:
            note = note or "Satellites: no orbital elements for %s yet (CelesTrak unreachable?)" % short
            continue
        try:
            el = parse_tle(tle[1], tle[2])
            lat, lon, alt = propagate(el, now)
            track = []
            for k in range(-args.behind * 2, args.ahead * 2 + 1):
                t = now + k * 30
                la, lo, _ = propagate(el, t)
                track.append([round(t), round(lo, 3), round(la, 3)])
            period = 1440.0 / el["n"]
            out.append({"name": short, "long_name": longname, "lat": round(lat, 3), "lon": round(lon, 3), "alt_km": round(alt),
                        "period_min": round(period, 1), "track": track, "tle_age_h": round((now - el["epoch"]) / 3600, 1)})
        except Exception as e:
            note = "Satellites: %s: %s" % (short, e)
    if args.table:
        print(note or "%d satellites (CelesTrak elements, Kepler + J2 propagation)" % len(out))
        for sat in out:
            print("  %-9s at %7.2f, %8.2f  %4d km  period %.1f min  elements %.0f h old" % (sat["name"], sat["lat"], sat["lon"], sat["alt_km"], sat["period_min"], sat["tle_age_h"]))
    else:
        emit({"sats": out, "note": note})


def chk_sats():
    tles = fetch_tles()
    missing = [s[0] for s in SATS if s[0] not in tles]
    import time
    ages = ["%s %.0f h" % (k, (time.time() - parse_tle(v[1], v[2])["epoch"]) / 3600) for k, v in tles.items()]
    return ("warn" if missing else "ok"), "elements for %s%s" % (", ".join(ages) or "nothing", "; missing " + ", ".join(missing) if missing else "")


# Launches: The Space Devs' Launch Library 2 (free, no key, 15 requests an hour), cached for an hour.
LL2 = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=20&hide_recent_previous=true"
LAUNCHES = DATA / "launches.json"


def fetch_launches(max_age_h=1):
    import time
    try:
        c = json.loads(LAUNCHES.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600:
            return c["launches"]
    except (OSError, ValueError):
        pass
    from datetime import datetime, timezone
    body = json.loads(_http(LL2)[2].decode("utf-8", "replace"))
    out = []
    for L in body.get("results", []):
        pad = L.get("pad") or {}
        try:
            lat, lon = float(pad.get("latitude")), float(pad.get("longitude"))
        except (TypeError, ValueError):
            continue
        try:
            net = datetime.strptime(L["net"][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
        except (KeyError, ValueError, TypeError):
            continue
        rocket = ((L.get("rocket") or {}).get("configuration") or {})
        mission = (L.get("mission") or {}).get("name") or ""
        parts = [p.strip() for p in re.split(r",\s*", re.sub(r"\s*\(.*?\)\s*$", "", mission)) if p.strip()]
        if len(parts) > 1 and len(set(parts)) < len(parts):        # "Owlright, Owlright, Owlright" -> "Owlright x3"
            seen = []
            for pnm in parts:
                if pnm not in seen:
                    seen.append(pnm)
            mission = ", ".join("%s \u00d7%d" % (pnm, parts.count(pnm)) if parts.count(pnm) > 1 else pnm for pnm in seen)
        vids = sorted([v for v in (L.get("vidURLs") or []) if isinstance(v, dict) and str(v.get("url", "")).startswith("https://")], key=lambda v: v.get("priority") or 99)
        out.append({"id": L.get("id"), "name": L.get("name", ""), "rocket": rocket.get("full_name") or rocket.get("name") or "",
                    "videos": [{"url": v["url"], "title": v.get("title") or ""} for v in vids][:4], "webcast_live": bool(L.get("webcast_live")),
                    "mission": mission, "orbit": (((L.get("mission") or {}).get("orbit") or {}).get("abbrev") or ""),
                    "provider": ((L.get("launch_service_provider") or {}).get("name") or ""),
                    "status": ((L.get("status") or {}).get("abbrev") or ""), "net": net,
                    "pad": pad.get("name") or "", "site": ((pad.get("location") or {}).get("name") or ""), "lat": lat, "lon": lon})
    try:
        LAUNCHES.parent.mkdir(parents=True, exist_ok=True)
        LAUNCHES.write_text(json.dumps({"at": time.time(), "launches": out}), encoding="utf-8")
    except OSError:
        pass
    return out


def cmd_launches(args):
    import time
    note, launches = "", []
    data, stale_h, err = last_good("launches", fetch_launches)
    launches = data or []
    if err:
        note = stale_note("Launches", stale_h, err, args.stale)
    if args.table:
        print(note or "%d upcoming launches (Launch Library 2, The Space Devs)" % len(launches))
        for L in launches:
            print("  T%+7.1f h  %-6s %-40s %-28s %s" % ((L["net"] - time.time()) / 3600, L["status"], L["name"][:40], L["site"][:28], L["orbit"]))
    else:
        emit({"launches": launches, "note": note})


def chk_launches():
    import time
    launches = fetch_launches()
    soon = [L for L in launches if L["net"] > time.time()]
    nxt = soon[0] if soon else None
    return "ok", "%d upcoming launches%s" % (len(launches), "; next: %s in %.1f h (%s)" % (nxt["name"], (nxt["net"] - time.time()) / 3600, nxt["status"]) if nxt else "")


# --------------------------------------------------------------- clouds -----
# Fallback cloud layer, stitched here from the geostationary satellites when the ready-made image is not
# reachable (or always, if the setting says so). Every source is a public WMS that already delivers the
# equirectangular projection this map uses, so no reprojection is needed: NASA GIBS for GOES-East,
# GOES-West and Himawari (ABI / AHI band 13, clean infrared), EUMETView for Meteosat 0 degrees and Indian
# Ocean (SEVIRI 10.8 um). In an infrared image cold cloud tops are bright, so brightness -> cloud.
CLOUD_SOURCES = [
    ("GOES-East", "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap"
                  "&LAYERS=GOES-East_ABI_Band13_Clean_Infrared&SRS=EPSG:4326&BBOX=-180,-90,180,90&FORMAT=image/png&TRANSPARENT=true"),
    ("GOES-West", "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap"
                  "&LAYERS=GOES-West_ABI_Band13_Clean_Infrared&SRS=EPSG:4326&BBOX=-180,-90,180,90&FORMAT=image/png&TRANSPARENT=true"),
    ("Himawari", "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap"
                 "&LAYERS=Himawari_AHI_Band13_Clean_Infrared&SRS=EPSG:4326&BBOX=-180,-90,180,90&FORMAT=image/png&TRANSPARENT=true"),
    ("Meteosat 0", "https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.1.1&request=GetMap"
                   "&layers=msg_fes:ir108&srs=EPSG:4326&bbox=-180,-90,180,90&format=image/png&transparent=true"),
    ("Meteosat IODC", "https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.1.1&request=GetMap"
                      "&layers=msg_iodc:ir108&srs=EPSG:4326&bbox=-180,-90,180,90&format=image/png&transparent=true"),
]
CLOUDS_RAW = DATA / "clouds-raw.png"       # the composite brightness, kept so a source that fails keeps its last picture
CLOUDS_OUT = DATA / "clouds.png"           # white clouds on transparent, what the wallpaper shows
CLOUD_STATE = DATA / "clouds.json"


# -- a small PNG reader/writer, so the stitching works without Pillow (used when Pillow is missing) --
def _png_read(data):
    """PNG bytes -> (width, height, channels, bytearray of 8-bit samples). Handles the common cases:
    8-bit grey / grey+alpha / RGB / RGBA, non-interlaced, all five filters. Anything else raises."""
    import struct, zlib
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w, h, ch, plte = 8, [], 0, 0, 0, None
    while pos < len(data):
        ln, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if kind == b"IHDR":
            w, h, depth, ctype, _c, _f, inter = struct.unpack(">IIBBBBB", body)
            if depth != 8 or inter != 0 or ctype not in (0, 2, 4, 6):
                raise ValueError("PNG variant not supported (depth %d, type %d)" % (depth, ctype))
            ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
            plte = None
        elif kind == b"PLTE":
            plte = body
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    raw = zlib.decompress(b"".join(idat))
    stride, out, prev = w * ch, bytearray(w * h * ch), bytearray(w * ch)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                line[i] = (line[i] + (((line[i - ch] if i >= ch else 0) + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, out


def _png_write(w, h, rgba):
    """8-bit RGBA samples -> PNG bytes (no filtering: small enough for a soft cloud image)."""
    import struct, zlib
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
    stride = w * 4
    raw = b"".join(b"\x00" + bytes(rgba[y * stride:(y + 1) * stride]) for y in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def _grey_alpha(w, h, ch, px):
    """Any channel layout -> (grey bytearray, alpha bytearray)."""
    n = w * h
    if ch == 1:
        return bytearray(px), bytearray(b"\xff") * n
    if ch == 2:
        return bytearray(px[0::2]), bytearray(px[1::2])
    r, g, b = px[0::ch], px[1::ch], px[2::ch]
    grey = bytearray(n)
    for i in range(n):
        grey[i] = (r[i] * 77 + g[i] * 151 + b[i] * 28) >> 8
    return grey, (bytearray(px[3::4]) if ch == 4 else bytearray(b"\xff") * n)


def stitch_clouds(width=2048, height=1024, lo=120, hi=235, timeout=40, log=print):
    """Fetch every source, lay each over the previous composite where it has coverage, turn brightness into
    cloud opacity, write clouds.png. Returns (ok sources, failed sources)."""
    import time
    try:
        from PIL import Image
        pil = True
    except ImportError:
        pil = False
        width, height = min(width, 1024), min(height, 512)     # pure-Python decoding: keep the pixel count sane
    n, ok, failed = width * height, [], []
    base = bytearray(n)                                       # composite brightness, 0 = clear
    try:                                                      # last composite: a failed source keeps its old picture
        if pil:
            im = Image.open(CLOUDS_RAW).convert("L").resize((width, height))
            base = bytearray(im.tobytes())
        else:
            w0, h0, ch0, px0 = _png_read(CLOUDS_RAW.read_bytes())
            if (w0, h0) == (width, height):
                base = _grey_alpha(w0, h0, ch0, px0)[0]
    except Exception:
        pass
    for name, url in CLOUD_SOURCES:
        t0 = time.time()
        try:
            req = urllib.request.Request(url + "&WIDTH=%d&HEIGHT=%d" % (width, height), headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read(MAX_BODY + 1)
            if len(data) > MAX_BODY:
                raise ValueError("image larger than expected")
            if pil:
                import io
                im = Image.open(io.BytesIO(data)).convert("LA")
                if im.size != (width, height):
                    im = im.resize((width, height))
                raw = im.tobytes()
                grey, alpha = bytearray(raw[0::2]), bytearray(raw[1::2])
            else:
                w1, h1, ch1, px1 = _png_read(data)
                if (w1, h1) != (width, height):
                    raise ValueError("server returned %dx%d instead of %dx%d" % (w1, h1, width, height))
                grey, alpha = _grey_alpha(w1, h1, ch1, px1)
            if pil:                                           # where the source has a picture, it replaces the old one
                mask = Image.frombytes("L", (width, height), bytes(alpha)).point(lambda a: 255 if a > 128 else 0)
                covered = mask.histogram()[255]
                comp = Image.frombytes("L", (width, height), bytes(base))
                comp.paste(Image.frombytes("L", (width, height), bytes(grey)), mask=mask)
                base = bytearray(comp.tobytes())
            else:
                covered = 0
                for i in range(n):
                    if alpha[i] > 128:
                        base[i] = grey[i]
                        covered += 1
            if covered < n // 50:
                raise ValueError("image is empty (%d covered pixels)" % covered)
            ok.append(name)
            log("  %-14s ok, %d%% of the map, %.1f s" % (name, 100 * covered // n, time.time() - t0))
        except Exception as e:
            failed.append(name)
            log("  %-14s failed: %s" % (name, str(e)[:120]))
    if not ok and not any(base):
        raise RuntimeError("no cloud source answered and there is no previous composite")
    # brightness -> opacity: nothing below `lo`, full above `hi`, a soft curve between (cirrus stays thin)
    lut = bytearray(256)
    for v in range(256):
        k = min(1.0, max(0.0, (v - lo) / float(hi - lo)))
        lut[v] = int(255 * k * k * (3 - 2 * k))
    rgba = bytearray(n * 4)
    rgba[0::4] = b"\xff" * n; rgba[1::4] = b"\xff" * n; rgba[2::4] = b"\xff" * n
    rgba[3::4] = bytes(base).translate(bytes(lut))
    CLOUDS_OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = CLOUDS_OUT.with_suffix(".tmp.png")
    if pil:
        Image.frombytes("RGBA", (width, height), bytes(rgba)).save(tmp, "PNG", optimize=False)
        Image.frombytes("L", (width, height), bytes(base)).save(CLOUDS_RAW, "PNG")
    else:
        tmp.write_bytes(_png_write(width, height, rgba))
        greyrgba = bytearray(n * 4)
        greyrgba[0::4] = base; greyrgba[1::4] = base; greyrgba[2::4] = base; greyrgba[3::4] = b"\xff" * n
        CLOUDS_RAW.write_bytes(_png_write(width, height, greyrgba))
    tmp.replace(CLOUDS_OUT)
    try:
        CLOUD_STATE.write_text(json.dumps({"at": time.time(), "ok": ok, "failed": failed, "size": [width, height], "pillow": pil}), encoding="utf-8")
    except OSError:
        pass
    return ok, failed


def cmd_clouds(args):
    """`clouds` (JSON for the wallpaper) / `clouds --stitch` (human readable). Stitches when the file is older
    than --max-age hours or missing, else reports the file. Never raises: the wallpaper reads the result."""
    import time
    quiet = not args.stitch
    log = (lambda *a: None) if quiet else print
    fresh = CLOUDS_OUT.exists() and time.time() - CLOUDS_OUT.stat().st_mtime < args.max_age * 3600
    note = ""
    if not fresh or args.force:
        try:
            log("Stitching clouds from the geostationary satellites (NASA GIBS, EUMETView)...")
            ok, failed = stitch_clouds(log=log)
            note = "" if not failed else "Clouds: stitched without %s" % ", ".join(failed)
        except Exception as e:
            note = "Clouds: stitching failed - %s" % e
    state = {}
    try:
        state = json.loads(CLOUD_STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    res = {"file": str(CLOUDS_OUT) if CLOUDS_OUT.exists() else "", "age_h": round((time.time() - CLOUDS_OUT.stat().st_mtime) / 3600, 2) if CLOUDS_OUT.exists() else None,
           "sources_ok": state.get("ok", []), "sources_failed": state.get("failed", []), "size": state.get("size"), "pillow": state.get("pillow"), "note": note}
    if quiet:
        emit(res)
    else:
        print(note or "Done: %s (%s, %s)" % (CLOUDS_OUT, "x".join(str(v) for v in (res["size"] or [])), "Pillow" if res["pillow"] else "pure Python, half size"))


def chk_cloud_stitch():
    """A tiny request to each satellite source, so the Status panel shows which would answer."""
    good, bad = [], []
    for name, url in CLOUD_SOURCES:
        try:
            code, h, body, took = _http(url + "&WIDTH=64&HEIGHT=32")
            if code == 200 and body[:4] == b"\x89PNG":
                good.append(name)
            else:
                bad.append(name)
        except Exception:
            bad.append(name)
    state = {}
    try:
        state = json.loads(CLOUD_STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    last = (", last stitched %s ago" % _age(int(__import__("time").time() - state["at"]))) if state.get("at") else ", never stitched yet"
    try:
        import PIL  # noqa: F401
        how = "Pillow"
    except ImportError:
        how = "no Pillow: stitching at half size in pure Python (python3-pillow makes it 2048 wide and faster)"
    return ("ok" if len(good) >= 3 else "warn" if good else "error"), "%d of %d satellite sources answer%s%s%s" % (
        len(good), len(CLOUD_SOURCES), " (missing: " + ", ".join(bad) + ")" if bad else "", last, "; " + how)


# ------------------------------------------------------------ volcanoes -----
GVP_FEEDS = ["https://volcano.si.edu/news/WeeklyVolcanoRSS.xml", "https://volcano.si.edu/news/WeeklyVolcanoCAP.xml"]


def parse_volcano_feed(xml_text):
    """Volcanoes from the weekly report's RSS or CAP feed. Coordinates are looked for wherever such feeds
    put them (georss:point "lat lon", geo:lat + geo:long, cap:circle "lat,lon radius"), whatever the namespace."""
    import xml.etree.ElementTree as ET
    local = lambda el: el.tag.rsplit("}", 1)[-1].lower()
    rows, tags = [], Counter()
    for item in ET.fromstring(safe_xml(xml_text)).iter():
        if local(item) not in ("item", "entry", "info"):
            continue
        f, lat, lon = {}, None, None
        for el in item.iter():
            k, v = local(el), (el.text or "").strip()
            tags[k] += 1
            if not v:
                continue
            f.setdefault(k, v)
            nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", v)]
            if k in ("point", "circle") and len(nums) >= 2:
                lat, lon = nums[0], nums[1]
            elif k == "lat" and nums:
                lat = nums[0]
            elif k in ("long", "lon") and nums:
                lon = nums[0]
        title = f.get("title") or f.get("headline") or f.get("event") or ""
        m = re.match(r"\s*(.+?)\s*\((.+?)\)", title)
        name, country = (m.group(1), m.group(2)) if m else (title.split(" - ")[0].strip(), "")
        if not name:
            continue
        fresh = bool(re.search(r"\bnew\b", " ".join([title, f.get("category", ""), f.get("description", "")[:160]]), re.I))
        reported = None
        try:
            from email.utils import parsedate_to_datetime
            reported = int(parsedate_to_datetime(f.get("pubdate") or f.get("sent") or "").timestamp())
        except Exception:
            pass
        rows.append({"name": name, "country": country, "lat": lat, "lon": lon, "new": fresh, "reported": reported, "since": "",
                     "status": "new" if fresh else "continuing"})
    seen, out = set(), []
    for r in rows:                                 # a volcano can appear twice (RSS item + CAP info)
        if r["name"] not in seen:
            seen.add(r["name"])
            out.append(r)
    return out, tags


def report_table(html):
    """{volcano: (eruption start date, status)} from the table on the weekly report's web page: the feeds do not
    carry the start date. Pure enrichment - if the page changes and nothing is found, the layer works without it.
    Columns: Name, Country, Volcanic Region, Eruption Start Date, Report Type ("New Eruptive Activity",
    "Continuing Eruptive Activity", "Other Observations")."""
    import html as htmllib
    out = {}
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", html, flags=re.S | re.I):
        cells = [" ".join(htmllib.unescape(re.sub(r"<[^>]+>", " ", c)).split())
                 for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, flags=re.S | re.I)]
        if len(cells) < 4:
            continue
        kind = next((c.lower() for c in cells if re.match(r"(new|continuing|other)\b", c.lower())), "")
        if not kind:
            continue
        status = kind.split()[0]
        m = next((re.match(r"(\d{4}(?: \w{3}(?: \d{1,2})?)?)$", c) for c in cells if re.match(r"\d{4}", c)), None)
        out[cells[0].lower()] = (m.group(1) if m else "", status)
    return out


# USGS volcano alert levels (Hazard Alert Notification System, public API, no key). Levels: NORMAL (green),
# ADVISORY (yellow), WATCH (orange), WARNING (red). Only the elevated ones are listed; US volcanoes only.
USGS_HANS = "https://volcanoes.usgs.gov/hans-public/api/"
ALERT_COLORS = ("green", "yellow", "orange", "red")


def _plain(t):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFKD", t) if not unicodedata.combining(c)).lower()


def _cap_date(t):
    """'2026-08-25T19:47:11-10:00' -> '2026 Aug 25' (the style the weekly report uses)."""
    from datetime import datetime
    try:
        return datetime.fromisoformat(t).strftime("%Y %b %d")
    except (TypeError, ValueError):
        return ""


def _report_hours(since, now=None):
    """'2024 Dec 23' (or '2024 Dec', '2024') from the weekly table -> hours since, else None."""
    import time
    from datetime import datetime
    now = now or time.time()
    for fmt in ("%Y %b %d", "%Y %b", "%Y"):
        try:
            return round((now - datetime.strptime(since, fmt).timestamp()) / 3600, 1)
        except (TypeError, ValueError):
            pass
    return None


def _cap_hours(t, now):
    from datetime import datetime
    try:
        return round((now - datetime.fromisoformat(t).timestamp()) / 3600, 1)
    except (TypeError, ValueError):
        return None


def fetch_usgs_alerts(now=None):
    """[{name, vnum, lat, lon, alert, level, issued_hours, elevated_since, notice}] for every US volcano at an
    elevated level. Coordinates: from the CAP feed (orange and red), else from the notice the volcano was last
    mentioned in (remembered in events.json so a notice is read once)."""
    import time
    now = now or time.time()
    rows = json.loads(_http(USGS_HANS + "volcano/getElevatedVolcanoes")[2].decode("utf-8", "replace"))
    caps = {}
    try:
        for c in json.loads(_http(USGS_HANS + "volcano/getCapElevated")[2].decode("utf-8", "replace")):
            caps[str(c.get("vnum"))] = c
    except Exception:
        pass
    try:
        mem = json.loads(EVENTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    coords = mem.setdefault("usgs_coords", {})
    out, fetched = [], set()
    for r in rows:
        vnum, cap = str(r.get("vnum")), caps.get(str(r.get("vnum")), {})
        lat, lon = cap.get("latitude"), cap.get("longitude")
        if lat is None and vnum in coords:
            lat, lon = coords[vnum]
        if lat is None and r.get("notice_data") and r["notice_data"] not in fetched:
            fetched.add(r["notice_data"])
            try:                                            # one notice names every volcano it covers, with lat/lng
                notice = json.loads(_http(r["notice_data"])[2].decode("utf-8", "replace"))
                for sec in notice.get("notice_sections") or []:
                    if sec.get("lat") is not None and sec.get("vnum"):
                        coords[str(sec["vnum"])] = [float(sec["lat"]), float(sec["lng"])]
            except Exception:
                pass
            if vnum in coords:
                lat, lon = coords[vnum]
        issued = r.get("sent_unixtime")
        out.append({"name": r.get("volcano_name", ""), "vnum": vnum, "lat": lat, "lon": lon,
                    "alert": (r.get("color_code") or "").lower(), "level": (r.get("alert_level") or "").title(),
                    "issued_hours": round((now - issued) / 3600, 1) if issued else None,
                    # the CAP feed keeps the previous notice: when that one was not elevated, this level dates from then
                    "elevated_since": _cap_date(cap.get("prev_sent_date_cap")) if cap and not cap.get("prev_is_elevated_cap") else "",
                    "elevated_hours": _cap_hours(cap.get("prev_sent_date_cap"), now) if cap and not cap.get("prev_is_elevated_cap") else None,
                    "observatory": r.get("obs_fullname", ""), "notice": r.get("notice_url", "")})
    try:
        EVENTS.parent.mkdir(parents=True, exist_ok=True)
        tmp = EVENTS.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps(mem), encoding="utf-8")
        tmp.replace(EVENTS)
    except OSError:
        pass
    return out


def merge_usgs_alerts(rows, alerts):
    """Attach alert levels to the weekly report's volcanoes (matched by name, accents ignored) and append the
    elevated US volcanoes the report does not mention, so a raised level shows up the day it happens."""
    by_name = {_plain(r["name"]): r for r in rows}
    for a in alerts:
        key = _plain(re.sub(r"\s+volcano$", "", a["name"], flags=re.I))
        r = by_name.get(key) or next((by_name[k] for k in by_name if k.startswith(key) or key.startswith(k)), None)
        if r is None:
            if a["lat"] is None:
                continue
            r = {"name": a["name"], "country": "United States", "lat": a["lat"], "lon": a["lon"], "new": False,
                 "reported": None, "since": "", "status": "alert"}
            rows.append(r)
            by_name[key] = r
        r.update(alert=a["alert"], level=a["level"], alert_hours=a["issued_hours"], alert_since=a["elevated_since"],
                 elevated_hours=a["elevated_hours"], observatory=a["observatory"])
    return rows


def chk_usgs_alerts():
    alerts = fetch_usgs_alerts()
    named = ", ".join("%s %s" % (a["name"], a["alert"]) for a in alerts)
    missing = sum(1 for a in alerts if a["lat"] is None)
    return ("warn" if missing else "ok"), "%d US volcanoes at an elevated level%s%s" % (
        len(alerts), ": " + named if named else "", " - %d without coordinates yet" % missing if missing else "")


def report_table_loose(html, names):
    """Fallback when the page's table markup is not what report_table expects (0 rows although the page
    loaded): for each volcano name from the feed, look for a report type phrase and an eruption start date
    in the stretch of HTML that follows the name. Markup-independent, so it survives a page redesign."""
    import html as htmllib
    text = htmllib.unescape(re.sub(r"<[^>]+>", " ", html))
    text = " ".join(text.split())
    out = {}
    for name in names:
        for m in re.finditer(re.escape(name), text):
            chunk = text[m.end():m.end() + 400]
            kind = re.search(r"\b(New|Continuing|Other)\s+(Eruptive Activity|Observations)", chunk)
            if not kind:
                continue
            date = re.search(r"\b((?:19|20)\d{2}(?: [A-Z][a-z]{2}(?: \d{1,2})?)?)\b", chunk[:kind.start()])
            out[name.lower()] = (date.group(1) if date else "", kind.group(1).lower())
            break
    return out


# The Smithsonian's own eruption database (Volcanoes of the World, WFS, no key): every eruption still marked as
# continuing, with its start date. Structured, unlike the weekly report page, so this is the first place to
# look for "erupting since"; the page is only a fallback.
GVP_WFS = ("https://webservices.volcano.si.edu/geoserver/GVP-VOTW/ows?service=WFS&version=2.0.0&request=GetFeature"
           "&typeName=GVP-VOTW:E3WebApp_Eruptions1960&outputFormat=json&CQL_FILTER=ContinuingEruption%3D%27True%27")
ERUPTIONS = DATA / "eruptions.json"


def gvp_eruptions(max_age_h=24):
    """{plain volcano name: 'YYYY Mon DD'} of continuing eruptions, cached for a day."""
    import time
    from datetime import datetime
    try:
        c = json.loads(ERUPTIONS.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600 and c.get("eruptions"):
            return c["eruptions"]
    except (OSError, ValueError):
        pass
    body = json.loads(_http(GVP_WFS)[2].decode("utf-8", "replace"))
    out = {}
    for f in body.get("features", []):
        p = f.get("properties") or {}
        name = str(p.get("VolcanoName") or "")
        try:
            when = datetime(int(p["StartDateYear"]), int(p.get("StartDateMonth") or 1), int(p.get("StartDateDay") or 1)).strftime("%Y %b %d")
        except (KeyError, TypeError, ValueError):
            continue
        for key in {_plain(name), _plain(" ".join(reversed([t.strip() for t in name.split(",")])))}:   # "Lengai, Ol Doinyo"
            if key and (key not in out or when > out[key]):
                out[key] = when
    if out:
        try:
            ERUPTIONS.parent.mkdir(parents=True, exist_ok=True)
            ERUPTIONS.write_text(json.dumps({"at": time.time(), "eruptions": out}), encoding="utf-8")
        except OSError:
            pass
    return out


def chk_eruptions():
    er = gvp_eruptions()
    return ("ok" if er else "warn"), "%d continuing eruptions with a start date" % len(er)


TABLE_ROWS = -1          # rows found on the weekly report page by the last fetch; -1 = page not read
WEEKLY = DATA / "weekly-report.json"


def weekly_table(max_age_h=24, names=()):
    """The weekly report page's table, cached for a day: the page is slow (often more than the 6 s the feeds get),
    and it only changes on Wednesdays."""
    import time
    try:
        c = json.loads(WEEKLY.read_text(encoding="utf-8"))
        if time.time() - c.get("at", 0) < max_age_h * 3600 and c.get("table"):
            return c["table"]
    except (OSError, ValueError):
        pass
    url, table, page = "https://volcano.si.edu/reports_weekly.cfm", {}, ""
    for headers in (UA, {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) livemap-wallpaper/" + VERSION, "Accept": "text/html"}):
        try:                                            # some front ends refuse a plain script user agent: try a browser-like one
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=25) as r:
                page = r.read(MAX_BODY).decode("utf-8", "replace")
            table = report_table(page)
            if not table and names:
                table = report_table_loose(page, names)
            if table:
                break
        except urllib.error.HTTPError as e:
            if e.code not in (403, 406, 429):
                raise
    if not table and page:
        try:                                            # keep the page for a look: livemap-helper volcanoes --table says where
            (DATA / "weekly-report.html").write_text(page, encoding="utf-8")
        except OSError:
            pass
    if table:
        try:
            WEEKLY.parent.mkdir(parents=True, exist_ok=True)
            WEEKLY.write_text(json.dumps({"at": time.time(), "table": table}), encoding="utf-8")
        except OSError:
            pass
    return table


def chk_weekly_page():
    try:
        names = [r["name"] for r in fetch_volcanoes()[0]]
    except Exception:
        names = []
    table = weekly_table(names=names)
    dated = sum(1 for v in table.values() if v[0])
    return ("ok" if table else "warn"), "%d volcanoes in the report table, %d with an eruption start date" % (len(table), dated)


def fetch_volcanoes():
    last = None
    for url in GVP_FEEDS:                          # the RSS first; the CAP feed if the RSS has no coordinates
        _c, _h, body, _t = _http(url)
        rows, tags = parse_volcano_feed(body.decode("utf-8", "replace"))
        last = (rows, tags, url)
        if any(r["lat"] is not None for r in rows):
            break
    global TABLE_ROWS
    TABLE_ROWS = -1
    try:                                           # eruption start dates: the Smithsonian database first
        er = gvp_eruptions()
        for r in last[0]:
            when = er.get(_plain(r["name"]))
            if when:
                r["since"] = when
    except Exception:
        pass
    try:                                           # report type (New / Continuing) and any date still missing: the page
        table = weekly_table(names=[r["name"] for r in last[0]])
        TABLE_ROWS = len(table)
        for r in last[0]:
            key = r["name"].lower()
            if key not in table:                                       # "Kīlauea" on the page, "Kilauea" in the feed
                import unicodedata
                plain = lambda t: "".join(c for c in unicodedata.normalize("NFKD", t) if not unicodedata.combining(c))
                key = next((k for k in table if plain(k) == plain(key)), key)
            if key in table:
                r["since"], r["status"] = r["since"] or table[key][0], table[key][1]
                r["new"] = r["status"] == "new"      # the table's own New / Continuing beats guessing from the text
    except Exception:
        pass
    return last


def cmd_volcanoes(args):
    note, rows, tags, url = "", [], Counter(), ""
    data, stale_h, err = last_good("volcanoes", lambda: list(fetch_volcanoes()[0]))
    rows = data or []
    if err:
        note = stale_note("Volcanoes", stale_h, err, args.stale)
    else:
        url = GVP_FEEDS[0]
    alerts_note = ""
    adata, astale, aerr = last_good("usgs-alerts", fetch_usgs_alerts)
    if adata:
        rows = merge_usgs_alerts(rows, adata)
    if aerr:
        alerts_note = stale_note("USGS alert levels", astale, aerr, args.stale)
    placed = [r for r in rows if r["lat"] is not None and r["lon"] is not None]
    if rows and not placed:
        note = "Volcanoes: the feed lists %d volcanoes but no coordinates were found in it" % len(rows)
    for r in placed:
        r["hours"] = 0
        r.setdefault("alert", "")
    if placed:
        # a changed alert level or report status counts as newly reported (pulses again, says what it was)
        placed = remember_events("volcano", placed, lambda r: _plain(r["name"]), args.keep,
                                 sig_of=lambda r: "red" if r.get("alert") == "red" else "orange" if r.get("alert") == "orange" or r.get("status") == "new" else "yellow",
                                 raised_of=lambda r: bool(r.get("alert")))
        for r in placed:                           # how long above green: USGS's own date when the CAP feed has it, else as seen from here
            if r.get("alert") and r.get("elevated_hours") is None:
                r["elevated_hours"] = r.get("raised_hours")
            r["since_hours"] = _report_hours(r.get("since", ""))
    if alerts_note and not note:
        note = "" if placed else alerts_note
    if args.table:
        print(note or "%d volcanoes in this week's report (%s)" % (len(placed), url))
        print("  report page: %s" % ("not readable (no since-dates, no New/Continuing)" if TABLE_ROWS < 0 else "%d rows in its table" % TABLE_ROWS
              + ("" if TABLE_ROWS else " - the page as received is in %s" % (DATA / "weekly-report.html"))))
        for r in rows:
            print("  %-28s %-22s %-18s %-11s since %-14s first seen here %-9s %s%s" % (r["name"], r["country"], "%.2f, %.2f" % (r["lat"], r["lon"]) if r["lat"] is not None else "no coordinates",
                  r.get("status", ""), r["since"] or "?", "%.0f h ago" % r["first_hours"] if r.get("first_hours") is not None else "unknown",
                  "USGS %s/%s%s" % (r["level"], r["alert"], " raised %s" % ("%.0f h ago" % r["elevated_hours"] if r.get("elevated_hours") is not None else "? (unknown)")) if r.get("alert") else "",
                  "  CHANGED from %s %.0f h ago" % (r["changed_from"], r["changed_hours"]) if r.get("changed_from") else ""))
        if alerts_note:
            print("  " + alerts_note)
        if not placed:
            print("  tags seen in the feed:", dict(tags.most_common(25)))
    else:
        emit({"volcanoes": placed, "note": note})


def chk_volcanoes():
    rows, _tags, _url = fetch_volcanoes()
    placed = [r for r in rows if r["lat"] is not None]
    if rows and not placed:
        return "warn", "%d volcanoes listed, but no coordinates found in the feed - run: livemap-helper volcanoes --table" % len(rows)
    return "ok", "%d volcanoes in this week's report, %d with new activity" % (len(placed), sum(r["new"] for r in placed))


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
                                   #   "clouds": bool, "cloud_opacity": 0-100, "full": bool, "full_until": epoch seconds}


def cpu_busy():
    """CPU busy percentage since the previous call (state kept in a file: the helper exits between calls).
    None on the first call or when /proc/stat is unreadable."""
    try:
        parts = open("/proc/stat").readline().split()
        vals = [int(x) for x in parts[1:9]]
        idle, total = vals[3] + vals[4], sum(vals)
    except (OSError, ValueError, IndexError):
        return None
    prev = None
    try:
        prev = json.loads(LOAD_STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    try:
        LOAD_STATE.parent.mkdir(parents=True, exist_ok=True)
        LOAD_STATE.write_text(json.dumps({"idle": idle, "total": total}), encoding="utf-8")
    except OSError:
        pass
    if not prev or total <= prev.get("total", 0):
        return None
    dt = total - prev["total"]
    return round(100.0 * (1 - (idle - prev["idle"]) / dt)) if dt > 0 else None


def gpu_busy():
    """(busy percent or None, how it was measured). AMD: sysfs gpu_busy_percent. NVIDIA: nvidia-smi.
    Intel: no busy figure without root, so the GPU clock as a fraction of its maximum is used as an estimate
    (a game pins it at the top; the desktop idles near the bottom). Anything else: None, and the CPU decides."""
    import glob
    for f in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
        try:
            return int(open(f).read().strip()), "amd"
        except (OSError, ValueError):
            pass
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode == 0 and out.stdout.strip():
            return int(float(out.stdout.strip().splitlines()[0])), "nvidia"
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    for cur, mx in (("/sys/class/drm/card*/gt/gt0/rps_cur_freq_mhz", "/sys/class/drm/card*/gt/gt0/rps_max_freq_mhz"),
                    ("/sys/class/drm/card*/gt_cur_freq_mhz", "/sys/class/drm/card*/gt_max_freq_mhz")):
        cs, ms = glob.glob(cur), glob.glob(mx)
        if cs and ms:
            try:
                c, m = int(open(cs[0]).read()), int(open(ms[0]).read())
                if m > 0:
                    return int(round(100.0 * c / m)), "intel-clock"
            except (OSError, ValueError):
                pass
    return None, "none"


LAYERS = DATA / "layers.json"
LAYER_NAMES = ("quakes", "volcanoes", "storms", "fires", "floods", "alerts", "launches", "sats", "network")


def read_layers():
    """The event layers the wallpaper has switched on (written by the wallpaper itself through `power --layers`),
    or None when no wallpaper has said yet. The widget can hide the kinds the map does not show."""
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        return [l for l in d.get("shown", []) if l in LAYER_NAMES] if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def read_units():
    """[distance, wind] as the wallpaper's Units and Storm wind choices (0 km / km/h, 1 mi / mph, 2 nmi / knots),
    for the widget's feed; [0, 0] until the wallpaper has said."""
    try:
        d = json.loads(LAYERS.read_text(encoding="utf-8"))
        u = d.get("units") if isinstance(d, dict) else None
        return [int(u[0]), int(u[1])] if isinstance(u, list) and len(u) == 2 else [0, 0]
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


def write_layers(shown, units=None, fire_focus=None, flood_level=None, nws_each=None, fire_sources=None):
    shown = [l for l in shown.split(",") if l in LAYER_NAMES]
    if units is not None:
        try:
            units = [max(0, min(2, int(x))) for x in units.split(",")][:2]
        except ValueError:
            units = None
    if fire_focus is not None:
        fire_focus = max(0, min(2, int(fire_focus)))
    if flood_level is not None:
        flood_level = max(0, min(2, int(flood_level)))
    if read_layers() == shown and (units is None or read_units() == units) and (fire_focus is None or read_fire_focus() == fire_focus) \
            and (flood_level is None or read_flood_level() == flood_level) and (nws_each is None or read_layers_flag("nws_each") == bool(nws_each)) \
            and (fire_sources is None or read_fire_sources() == int(fire_sources)):
        return
    try:
        LAYERS.parent.mkdir(parents=True, exist_ok=True)
        tmp = LAYERS.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps({"shown": shown, "units": units if units is not None else read_units(),
                                   "fire_focus": fire_focus if fire_focus is not None else read_fire_focus(),
                                   "flood_level": flood_level if flood_level is not None else read_flood_level(),
                                   "nws_each": bool(nws_each) if nws_each is not None else read_layers_flag("nws_each"),
                                   "fire_sources": int(fire_sources) if fire_sources is not None else read_fire_sources(), "at": int(time.time())}), encoding="utf-8")
        tmp.replace(LAYERS)
    except OSError:
        pass


def wind_text(kmh, u):
    return ("%d mph" % round(kmh * 0.621371)) if u == 1 else ("%d kt" % round(kmh / 1.852)) if u == 2 else "%d km/h" % round(kmh)


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


def cmd_power(args):
    """One line of JSON for the wallpaper's 20-second poll: power source, load, and the widget's mode file.
    `--layers quakes,storms,...` is the wallpaper telling the widget which event layers it shows (layers.json)."""
    if getattr(args, "layers", None) is not None:
        write_layers(args.layers, getattr(args, "units", None), getattr(args, "fire_focus", None), getattr(args, "flood_level", None), getattr(args, "nws_each", None), getattr(args, "fire_sources", None))
    cpu, (gpu, how) = cpu_busy(), gpu_busy()
    emit({"battery": on_battery(), "cpu": cpu, "gpu": gpu, "gpu_how": how, "mode": read_mode()})


def cmd_mode(args):
    """Companion widget -> wallpaper: set or clear the overrides. `mode --pause on`, `--plain off`, `--hide quakes,storms`,
    `--clouds off`, `--cloud-opacity 40` (either `auto` to follow the wallpaper's own setting again),
    `--full on [--full-hours 2]` (run at full speed: ignore the on-battery policy and the load guard, for that many
    hours or until `--full off`; the widget's own pause / plain map still apply)."""
    m = read_mode()
    if args.full is not None:
        if args.full == "on":
            m["full"] = True
            hours = args.full_hours if args.full_hours is not None else 0
            if hours > 0:
                m["full_until"] = int(time.time() + hours * 3600)
            else:
                m.pop("full_until", None)
        else:
            m.pop("full", None)
            m.pop("full_until", None)
    if args.pause is not None:
        m["pause"] = args.pause == "on"
    if args.plain is not None:
        m["plain"] = args.plain == "on"
    if args.hide is not None:
        m["hide"] = [h for h in args.hide.split(",") if h]
    if args.clouds is not None:                    # on / off, or auto = follow the wallpaper's own setting
        if args.clouds == "auto":
            m.pop("clouds", None)
        else:
            m["clouds"] = args.clouds == "on"
    if args.cloud_opacity is not None:             # 0-100, or auto
        if str(args.cloud_opacity).lower() == "auto":
            m.pop("cloud_opacity", None)
        else:
            try:
                m["cloud_opacity"] = max(0, min(100, int(float(args.cloud_opacity))))
            except ValueError:
                pass
    if args.clear:
        m = {}
    try:
        MODE.parent.mkdir(parents=True, exist_ok=True)
        tmp = MODE.with_suffix(".tmp%d" % os.getpid())
        tmp.write_text(json.dumps(m), encoding="utf-8")
        tmp.replace(MODE)
    except OSError as e:
        sys.exit("could not write %s: %s" % (MODE, e))
    json.dump(m, sys.stdout)


# ------------------------------------------------------------------ feed -----
def cmd_feed(args):
    """The newest events across every source, with a link each, for the companion widget. Everything comes
    from the caches the wallpaper already keeps, plus one small USGS request (cached 5 min)."""
    import time
    now, items, problems = time.time(), [], []
    # earthquakes
    try:
        qf = DATA / "quakes.json"
        cached_empty = False
        try:                                       # an empty collection (USGS mid-outage) is not worth keeping for five minutes
            cached_empty = qf.exists() and not json.loads(qf.read_text(encoding="utf-8")).get("features")
        except (OSError, ValueError):
            cached_empty = True
        if not qf.exists() or cached_empty or now - qf.stat().st_mtime > 300:
            try:
                body = _http("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/%s.geojson" % args.feed, timeout=12)[2]
                if not json.loads(body).get("features") and not cached_empty and qf.exists():
                    raise ValueError("USGS returned an empty feed")
                qf.parent.mkdir(parents=True, exist_ok=True)
                qf.write_bytes(body)
            except Exception as e:                 # USGS not answering this process: the last file still lists the quakes
                if not qf.exists():
                    raise
                problems.append("quakes: USGS not answering (%s); showing the list from %s ago" % (e, _age(now - qf.stat().st_mtime)))
        for f in json.loads(qf.read_text(encoding="utf-8")).get("features", []):
            p, c = f.get("properties") or {}, (f.get("geometry") or {}).get("coordinates") or [0, 0]
            items.append({"kind": "quake", "when": p.get("time", 0) / 1000, "title": "M%.1f \u00b7 %s" % (p.get("mag") or 0, p.get("place") or ""),
                          "detail": "USGS", "url": p.get("url") or "", "lat": c[1], "lon": c[0], "level": 3 if (p.get("mag") or 0) >= 6 else 2 if (p.get("mag") or 0) >= 5 else 1,
                          "key": "quake:%s" % (f.get("id") or p.get("code") or "%s,%s" % (c[0], c[1]))})
    except Exception as e:
        problems.append("quakes: %s" % e)
    # remembered events: storms, volcanoes, fires (first seen / changed)
    try:
        mem = json.loads(EVENTS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        mem = {}
    units = read_units()                            # the wallpaper's Units and Storm wind choices
    fire_focus = read_fire_focus()                  # and its Wildfire focus
    flood_level = read_flood_level()                # and its flood filter
    for kind, url_of, title_of in (
            ("storm", lambda it: "https://www.gdacs.org/report.aspx?eventid=%s&eventtype=TC" % it.get("id", ""),
             lambda it: "%s \u00b7 %s%s \u00b7 %s%s%s" % (it.get("name", "?"), it.get("kind", ""), " cat %d" % it["cat"] if it.get("cat") else "", wind_text(float(it.get("wind") or 0), units[1]),
                                                           " \u00b7 was %s" % str(it["was_named"]).title() if it.get("was_named") else "",
                                                           " \u00b7 " + impact_text(it["impact"]) if it.get("impact") else "")),
            ("volcano", lambda it: "https://volcano.si.edu/search_volcano.cfm?keyword=%s" % urllib.request.quote(it.get("name", "")),
             lambda it: "%s \u00b7 %s" % (it.get("name", "?"), (it.get("level") + " (" + it.get("alert", "") + ")") if it.get("alert") else "new eruption" if it.get("status") == "new" else "active")),
            ("fire", lambda it: "https://www.gdacs.org/report.aspx?eventid=%s&eventtype=WF" % it.get("id", ""),
             lambda it: "%s \u00b7 %s \u00b7 %s" % (it.get("name", "?"), it.get("alert", ""), area_text(float(it.get("area_ha") or 0), units[0]))),
            ("flood", lambda it: "https://www.gdacs.org/report.aspx?eventid=%s&eventtype=FL" % it.get("id", ""),
             lambda it: "%s \u00b7 %s flood%s" % (it.get("name", "?"), it.get("alert", ""), " \u00b7 " + people_text(it["people"]) if it.get("people") else ""))):
        for key, e in (mem.get(kind) or {}).items():
            it = e.get("item") or {}
            if not it:
                continue
            when = e.get("changed") or e.get("first")
            if when is None:
                continue
            title = title_of(it) + (" \u00b7 was %s" % e.get("was") if e.get("changed") and e.get("was") else " \u00b7 new")
            ev = {"kind": kind, "when": when, "title": title, "detail": "GDACS" if kind != "volcano" else "Smithsonian / USGS",
                  "url": url_of(it), "lat": it.get("lat"), "lon": it.get("lon"), "key": "%s:%s:%s" % (kind, key, int(when)),
                  "level": 3 if it.get("alert") in ("red",) or it.get("cat", 0) >= 3 else 2 if it.get("alert") == "orange" or it.get("cat", 0) >= 1 or it.get("status") == "new" else 1}
            if kind == "fire" and fire_focus >= 1 and it.get("alert") not in ("orange", "red"):
                continue                                   # Wildfire focus: only the events GDACS rates on the people exposed
            if kind == "flood" and ["green", "orange", "red"].index(it.get("alert") or "green") < flood_level:
                continue                                   # the wallpaper's flood filter (green floods are a basin's seasonal high water)
            if kind == "storm" and it.get("impact"):   # the facilities it crossed and those in its path, for the widget
                ev["facilities"] = {"crossed": it["impact"].get("crossed") or [], "ahead": it["impact"].get("ahead") or []}
            items.append(ev)
    # named fire incidents (NIFC, CWFIS, EFFIS: the sources the wallpaper has on; cached half an hour)
    try:
        bits = read_fire_sources()
        for src, bit in (("nifc", 4), ("cwfis", 8), ("effis", 16)):
            if not (bits & bit):
                continue
            data, _h, _e = incidents_cached(src, 30)
            for it in data or []:
                active = it.get("stage") in ("out of control", "being held") or (it.get("contained") is not None and it["contained"] < 100) or (src == "effis" and (it.get("days") or 99) < 7)
                big = it["area_ha"] >= 1000 or it.get("personnel", 0) >= 100 or it.get("stage") == "out of control"
                if fire_focus > 0 and not big:
                    continue
                parts = [it["name"], area_text(float(it["area_ha"]), units[0])]
                if it.get("contained") is not None:
                    parts.append("%d %% contained" % it["contained"])
                elif it.get("stage"):
                    parts.append(it["stage"])
                if it.get("personnel"):
                    parts.append("%d personnel" % it["personnel"])
                items.append({"kind": "fire", "when": now - (it.get("hours") or 0) * 3600, "title": " \u00b7 ".join(parts),
                              "detail": "%s%s" % (src.upper(), " \u00b7 " + it["region"] if it.get("region") else ""), "url": it.get("url", ""),
                              "lat": it["lat"], "lon": it["lon"], "key": it["id"],
                              "level": 3 if active and it["area_ha"] >= 10000 else 2 if active and big else 1})
    except Exception as e:
        problems.append("incidents: %s" % e)
    # air raid alerts: the wallpaper's minute-by-minute cache when fresh (it carries the token's detail), else the mirror
    try:
        f = DATA / "last-air-alerts.json"
        aa = None
        try:
            c = json.loads(f.read_text(encoding="utf-8"))
            if now - c.get("at", 0) < 180:
                aa = c["data"]
        except (OSError, ValueError, KeyError):
            pass
        if aa is None:
            aa, _h, _e = last_good("air-alerts", lambda: fetch_air_alerts(""))
        names = {r["code"]: r for r in ua_regions()}
        for code, a in ((aa or {}).get("alerts") or {}).items():
            r = names.get(code)
            if not r or a.get("status") == "N":
                continue
            if a.get("status") == "C":
                items.append({"kind": "alert", "when": a.get("ended") or now, "title": "All clear \u00b7 %s" % r["name"], "detail": "the alert ended" + (" after " + _age((a.get("ended") or now) - a["since"]) if a.get("since") else ""),
                              "url": "https://alerts.in.ua/en", "lat": r["lat"], "lon": r["lon"], "level": 1, "nonew": True, "key": "clear:%s:%d" % (code, int(a.get("ended") or now))})
                continue
            kinds = a.get("types") or ["air raid"]
            severe = any(k != "air raid" for k in kinds)
            items.append({"kind": "alert", "when": a.get("since") or now, "title": "%s \u00b7 %s%s" % (", ".join(kinds).capitalize(), r["name"], " (part)" if a.get("status") == "P" else ""),
                          "detail": ("alerts.in.ua" if (aa or {}).get("source") != "mirror" else "mirror, oblast level") + (" \u00b7 " + ", ".join(a["places"]) if a.get("places") else "") + ("" if a.get("since") else " \u00b7 on since before the first look"),
                          "nonew": not a.get("since"), "url": "https://alerts.in.ua/en",
                          "lat": r["lat"], "lon": r["lon"], "level": 3 if severe else 2, "key": "alert:%s:%d" % (code, int(a.get("since") or now))})
    except Exception as e:
        problems.append("air alerts: %s" % e)
    # NWS flood alerts (the wallpaper's cache; fetched when it is more than 10 minutes old)
    try:
        nws, _h, _e = nws_floods_cached(10)
        if not read_layers_flag("nws_each"):
            nws = group_nws(nws or [])
        for a in nws or []:
            if ["green", "orange", "red"].index(a["alert"]) < flood_level:
                continue
            items.append({"kind": "flood", "when": a.get("onset") or now, "title": "%s \u00b7 %s" % (a["event"], a["name"]),
                          "detail": "NWS%s \u00b7 until %s" % ("" if a.get("count") else " " + a["office"], time.strftime("%a %H:%M", time.localtime(a["until"])) if a.get("until") else "?"),
                          "url": a["url"], "lat": a["lat"], "lon": a["lon"], "level": 3 if a["alert"] == "red" else 2 if a["alert"] == "orange" else 1, "key": a["id"]})
    except Exception as e:
        problems.append("nws floods: %s" % e)
    # satellite fire clusters that need attention (the helper's rating; the wallpaper's cache, nothing extra fetched when fresh)
    try:
        fires_now, _h, _e = last_good("fires", fetch_fires)
        for c in rate_hotspots(cluster_hotspots(fetch_hotspots()), fires_now or []) if fire_focus < 2 else []:
            if c["tier"] < 2 or (fire_focus == 1 and not c.get("people")):
                continue
            items.append({"kind": "fire", "when": now - c["hours"] * 3600, "title": "Fire hotspots \u00b7 %s \u00b7 %s" % (c["why"], "%.1f GW" % (c["frp"] / 1000) if c["frp"] >= 1000 else "%d MW" % c["frp"]),
                          "detail": "NASA FIRMS \u00b7 %d detections" % c["n"], "url": "https://firms.modaps.eosdis.nasa.gov/map/#d:24hrs;@%.2f,%.2f,7z" % (c["lon"], c["lat"]),
                          "lat": c["lat"], "lon": c["lon"], "level": 2, "key": "hot:%d,%d" % (int(c["lat"] // 0.5), int(c["lon"] // 0.5))})
    except Exception as e:
        problems.append("hotspots: %s" % e)
    # launches
    try:
        for L in fetch_launches():
            if now - 1800 < L["net"] < now + 7 * 86400:
                items.append({"kind": "launch", "when": L["net"], "title": "%s \u00b7 %s" % (L["rocket"], L["mission"] or L["name"]),
                              "detail": "%s \u00b7 %s" % (L["provider"], L["site"]), "url": (L.get("videos") or [{}])[0].get("url") or "https://ll.thespacedevs.com/2.2.0/launch/%s/" % L["id"],
                              "lat": L["lat"], "lon": L["lon"], "level": 3 if L["net"] - now < 900 else 2 if L["net"] - now < 3600 else 1, "future": True,
                              "videos": L.get("videos") or [], "webcast_live": L.get("webcast_live", False), "status": L.get("status", ""),
                              "key": "launch:%s" % L["id"]})
    except Exception as e:
        problems.append("launches: %s" % e)
    # satellites
    try:
        for short, catnr, longname in SATS:
            it = {"kind": "sat", "when": now, "title": longname, "detail": "live position on the map",
                  "url": "https://www.n2yo.com/satellite/?s=%s" % catnr, "lat": None, "lon": None, "level": 0, "pin": True, "links": []}
            if short == "ISS":                            # the people on board, and the station's own news
                it["links"] = [{"label": "Who is in space right now", "icon": "user-group-new", "url": "https://issinfo.net/whos-in-space"}]
            elif short == "Tiangong":
                it["links"] = [{"label": "Who is in space right now", "icon": "user-group-new", "url": "https://issinfo.net/whos-in-space"}]
            items.append(it)
    except Exception:
        pass
    remember_history(items, now)
    if args.since is not None or args.until is not None:          # the past: from the history file, not the live feeds
        since, until = args.since if args.since is not None else 0, args.until if args.until is not None else now + 1
        past = [it for it in read_history().values() if since <= it["when"] <= until]
        for it in past:
            it["past"] = True
            if it.get("future") and it["when"] < now:
                it["future"] = False                                  # a launch that has happened since
        past.sort(key=lambda it: -it["when"])
        emit({"items": past[:args.limit], "problems": problems, "version": VERSION, "history_days": HISTORY_DAYS,
              "history_from": min((it["when"] for it in read_history().values()), default=None)})
        return
    items.sort(key=lambda it: (0 if it.get("pin") else 1, -it["when"]))
    # The cap is for the long tails (a day of quakes, dozens of fire clusters): a storm first seen three days
    # ago is still on the map and must not fall off the end of the list because of them.
    # Floods and named fire incidents are long-lived too (a fire's last update can be days old, so by time it
    # sorts behind every quake of the day); they are already filtered to the ones that matter.
    def kept(it):
        return it["kind"] in ("storm", "volcano", "launch", "sat", "flood", "alert") or str(it.get("key", "")).split(":")[0] in INCIDENT_SOURCES
    # the kept kinds are exempt from the cap, not counted against it: 60 fire incidents must not push out every quake
    keep = [it for it in items if kept(it)]
    rest = [it for it in items if not kept(it)][:max(0, args.limit)]
    items = sorted(keep + rest, key=lambda it: (0 if it.get("pin") else 1, -it["when"]))
    emit({"items": items, "problems": problems, "version": VERSION, "layers": read_layers()})


def read_history():
    try:
        h = json.loads(HISTORY.read_text(encoding="utf-8"))
        return h.get("items", {}) if isinstance(h, dict) else {}
    except (OSError, ValueError):
        return {}


def remember_history(items, now):
    """Every event the feed shows is kept by key (a launch is updated until it has flown, so its final time and
    status win); entries older than HISTORY_DAYS go. Nothing is fetched for this: it is a side effect of `feed`."""
    hist = read_history()
    changed = False
    for it in items:
        key = it.get("key")
        if not key or it.get("pin"):
            continue
        keep = {k: v for k, v in it.items() if k not in ("videos", "webcast_live", "pin", "links")}
        old = hist.get(key)
        if old != keep and (old is None or it.get("future") or old.get("when") != keep["when"] or old.get("title") != keep["title"]
                            or old.get("facilities") != keep.get("facilities")):
            hist[key] = keep
            changed = True
    cutoff = now - HISTORY_DAYS * 86400
    stale = [k for k, v in hist.items() if (v.get("when") or 0) < cutoff]
    for k in stale:
        hist.pop(k, None)
    if changed or stale:
        try:
            HISTORY.parent.mkdir(parents=True, exist_ok=True)
            tmp = HISTORY.with_suffix(".tmp%d" % os.getpid())
            tmp.write_text(json.dumps({"items": hist}, separators=(",", ":")), encoding="utf-8")
            tmp.replace(HISTORY)
        except OSError:
            pass



def chk_power():
    cpu, (gpu, how) = cpu_busy(), gpu_busy()
    return "ok", "%s; CPU %s, GPU %s (%s)" % ("on battery" if on_battery() else "on mains power",
                                              "%d %%" % cpu if cpu is not None else "n/a", "%d %%" % gpu if gpu is not None else "n/a",
                                              {"amd": "sysfs", "nvidia": "nvidia-smi", "intel-clock": "Intel clock estimate", "none": "no reading, CPU decides"}[how])


# --------------------------------------------------------------- status -----
def _age(seconds):
    if seconds < 5400:
        return "%d min" % max(1, seconds // 60)
    if seconds < 172800:
        return "%.1f h" % (seconds / 3600)
    return "%d days" % (seconds // 86400)


def chk_maps():
    have = [f for f in ((DATA / "base" / ("%02d.jpg" % i)) for i in range(1, 13)) if f.exists()]
    if len(have) == 12:
        mb = sum(f.stat().st_size for f in have) / 1e6
        return "ok", "12 of 12 monthly images (%.0f MB), downloaded %s" % (mb, date.fromtimestamp(have[0].stat().st_mtime))
    if have:
        return "warn", "%d of 12 monthly images - run: livemap-helper fetch-maps" % len(have)
    return "warn", "not downloaded, so the fallback image is shown - run: livemap-helper fetch-maps"


def have_hires():
    return all((DATA / "base" / ("hires%02d.jpg" % i)).exists() for i in range(1, 13))


def chk_hires():
    if have_hires():
        mb = sum((DATA / "base" / ("hires%02d.jpg" % i)).stat().st_size for i in range(1, 13)) / 1e6
        return "ok", "12 of 12 monthly images at 21 600 px (%.0f MB): regions are cut from these" % mb
    have = sum((DATA / "base" / ("hires%02d.jpg" % i)).exists() for i in range(1, 13))
    return "warn", ("%d of 12 - run: livemap-helper fetch-maps --hires" % have) if have else \
        "not downloaded: a region is cut from the 5 400 px maps, which are soft beyond about 2x (press Download, about 330 MB)"


def chk_night():
    f, png = DATA / "night.jpg", DATA / "lights.png"
    if png.exists() and not (DATA / "night-hires.jpg").exists():
        return "warn", "lights.png (4 096 px) only: a region's lights are soft - press Download to keep NASA's 13 500 px night picture for them"
    if png.exists():
        return "ok", "lights.png present (%.1f MB): lights glow over the dimmed map" % (png.stat().st_size / 1e6)
    if f.exists():
        return "warn", "night.jpg present but lights.png is not: the night side is replaced by NASA's night picture, " \
                       "hiding clouds. Run: livemap-helper make-lights (needs python3-numpy, python3-pillow)"
    return "warn", "night.jpg missing, the night side is plain shading - run: livemap-helper fetch-maps"


def chk_geoip():
    try:
        import maxminddb
    except ImportError:
        return "error", "python module 'maxminddb' is missing - sudo dnf install python3-maxminddb"
    if not GEOIP.exists():
        return "error", "no database yet - press 'Update GeoIP database' (or run: livemap-helper fetch-geoip)"
    with maxminddb.open_database(str(GEOIP)) as r:
        meta = r.metadata()
    import time
    days = int((time.time() - meta.build_epoch) // 86400)
    text = "%s, built %s (%d days ago)" % (meta.database_type, date.fromtimestamp(meta.build_epoch), days)
    return ("warn", text + " - DB-IP publishes a new one every month") if days > 45 else ("ok", text)


def chk_sockets():
    if not shutil.which("ss"):
        return "error", "the 'ss' tool is missing (package iproute)"
    conns = connections()
    text = "%d connections to public addresses right now" % len(conns)
    try:
        import maxminddb
        if GEOIP.exists():
            with maxminddb.open_database(str(GEOIP)) as r:
                text += ", in %d places" % len({h[0] for h in (lookup(r, c[2]) for c in conns) if h})
    except ImportError:
        pass
    return "ok", text


MAX_BODY = 64 * 1024 * 1024        # no feed we read is anywhere near this; a response that is, is not the feed
MAX_DOWNLOAD = 300 * 1024 * 1024   # the NASA maps are the largest download (about 35 MB in all)


def _http(url, method="GET", timeout=6, limit=MAX_BODY):
    """GET/HEAD with the plugin's user agent, TLS verified by the system store (urllib's default), the body
    capped at `limit` bytes so a broken or hostile server cannot fill memory."""
    import time
    t0 = time.time()
    if not str(url).startswith("https://"):
        raise ValueError("refusing a non-https URL: %s" % str(url)[:80])
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA, method=method), timeout=timeout) as r:
        body = r.read(limit + 1) if method == "GET" else b""
        if len(body) > limit:
            raise ValueError("response larger than %d MB" % (limit // 1048576))
        return r.status, r.headers, body, time.time() - t0


def safe_xml(text):
    """XML from the network goes through the stdlib parser, which is not hardened against entity expansion
    ("billion laughs"); a feed never needs a DOCTYPE or entities, so any is refused outright."""
    head = text[:4096] if isinstance(text, str) else text[:4096].decode("latin-1", "replace")
    if re.search(r"<!(DOCTYPE|ENTITY)", head, re.I):
        raise ValueError("XML with a DOCTYPE or entity declarations is not accepted")
    return text


def clean(obj, maxlen=160):
    """Strings from the network are shown on the desktop: keep them printable, short and free of markup."""
    if isinstance(obj, str):
        t = "".join(ch for ch in obj if ch.isprintable() and ch not in "<>")
        if t.startswith("https://"):
            return t if len(t) <= 512 else ""          # links: keep whole or drop, never truncate
        return t if len(t) <= maxlen else t[:maxlen - 1] + "\u2026"
    if isinstance(obj, dict):
        return {k: clean(v, maxlen) for k, v in obj.items()}
    if isinstance(obj, list):
        return [clean(v, maxlen) for v in obj]
    return obj


def emit(obj):
    json.dump(clean(obj), sys.stdout, separators=(",", ":"))


def chk_usgs(feed):
    import time
    code, _h, body, took = _http("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/%s.geojson" % feed)
    feats = json.loads(body)["features"]
    text = "HTTP %d in %.1f s - %d events in feed '%s'" % (code, took, len(feats), feed)
    if feats:
        p = max(feats, key=lambda f: f["properties"]["time"])["properties"]
        text += "; newest M%.1f %s, %s ago" % (p.get("mag") or 0, p.get("place") or "", _age(int(time.time() - p["time"] / 1000)))
    return "ok", text


def chk_clouds():
    import time
    from email.utils import parsedate_to_datetime
    code, h, _b, took = _http("https://clouds.matteason.co.uk/images/4096x2048/clouds-alpha.png", "HEAD")
    text = "HTTP %d in %.1f s" % (code, took)
    if h.get("Last-Modified"):
        old = int(time.time() - parsedate_to_datetime(h["Last-Modified"]).timestamp())
        text += " - image is %s old (a new one is published every 3 h)" % _age(old)
        if old > 8 * 3600:
            return "warn", text
    return "ok", text


def chk_nasa():
    code, _h, _b, took = _http("%s/bmng/bmng-topography-bathymetry/january/world.topo.bathy.200401.3x5400x2700.jpg" % NASA, "HEAD")
    return "ok", "HTTP %d in %.1f s (only needed while running fetch-maps)" % (code, took)


def wallpaper_log():
    """What the wallpaper wrote to the journal in the last 3 hours, repeats collapsed."""
    try:
        out = subprocess.run(["journalctl", "--user", "-b", "-o", "cat", "--no-pager", "--since", "-3h", "-t", "plasmashell"],
                             capture_output=True, text=True, timeout=8).stdout
    except Exception as e:
        return ["(could not read the journal: %s)" % e]
    counts, order = Counter(), []
    for line in out.splitlines():
        if "livemap" not in line.lower():
            continue
        line = re.sub(r"\b0x[0-9a-f]+", "0x..", line.replace(str(Path.home()), "~"))
        line = re.sub(r"^file://\S*/org\.livemap\.wallpaper/contents/", "", line)
        if line not in counts:
            order.append(line)
        counts[line] += 1
    return [("%s   (x%d)" % (l, counts[l]) if counts[l] > 1 else l) for l in order[-16:]] or \
           ["(nothing from the wallpaper in the journal in the last 3 hours)"]


def cmd_status(args):
    from concurrent.futures import ThreadPoolExecutor
    jobs = [("Seasonal maps (NASA Blue Marble)", chk_maps), ("Hi-res seasonal maps (NASA Blue Marble, for regions)", chk_hires),
            ("City lights (NASA Black Marble)", chk_night), ("Map style imagery (frames)", chk_frames),
            ("Borders (Natural Earth)", chk_borders), ("Plate boundaries (PB2002)", chk_plates), ("Oil and gas infrastructure (BSEE, OpenStreetMap)", chk_infrastructure), ("GeoIP database (DB-IP)", chk_geoip), ("Connections (ss)", chk_sockets),
            ("Power and load", chk_power)]
    if not args.offline:
        jobs += [("Storms (GDACS)", chk_storms), ("Storms, secondary (NHC)", chk_storms_nhc), ("Wildfires (GDACS)", chk_fires), ("US fire incidents (NIFC)", chk_nifc), ("Canadian fires (CWFIS)", chk_cwfis), ("European burnt areas (EFFIS)", chk_effis), ("Floods (GDACS)", chk_floods), ("Air raid alerts (alerts.in.ua)", chk_air_alerts), ("US flood alerts (NWS)", chk_nws_floods), ("Volcanoes (Smithsonian / USGS)", chk_volcanoes), ("Volcano alert levels (USGS)", chk_usgs_alerts), ("Eruption database (Smithsonian)", chk_eruptions), ("Weekly report page (Smithsonian)", chk_weekly_page),
                 ("Fire hotspots (NASA FIRMS)", chk_hotspots), ("Satellite elements (CelesTrak)", chk_sats),
                 ("Launches (The Space Devs)", chk_launches), ("Earthquake feed (USGS)", lambda: chk_usgs(args.feed)), ("Cloud image (matteason.co.uk)", chk_clouds), ("Cloud stitching (NASA GIBS, EUMETView)", chk_cloud_stitch),
                 ("NASA image server", chk_nasa)]
    if args.names:                                  # just the rows, at once: the widget shows them while the checks run
        emit({"version": VERSION, "names": [j[0] for j in jobs]})
        return

    def run(job):
        try:
            state, detail = job[1]()
        except Exception as e:
            state, detail = "error", "%s: %s" % (type(e).__name__, e)
        return {"name": job[0], "state": state, "detail": detail}

    with ThreadPoolExecutor(max_workers=8) as pool:
        checks = list(pool.map(run, jobs))
    emit({"version": VERSION, "checks": checks, "log": wallpaper_log()})


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


def cmd_fetch_geoip(_args):
    today = date.today()
    tries = [(today.year, today.month),
             (today.year - (today.month == 1), (today.month - 2) % 12 + 1)]   # this month, else last
    gz = DATA / "geoip.mmdb.gz"
    for y, m in tries:
        try:
            download("https://download.db-ip.com/free/dbip-city-lite-%d-%02d.mmdb.gz" % (y, m), gz)
            break
        except Exception as e:
            print("  not available (%s)" % e)
    else:
        sys.exit("Could not download. Get the MMDB by hand from https://db-ip.com/db/download/ip-to-city-lite\n"
                 "and save it, unzipped, as %s" % GEOIP)
    with gzip.open(gz, "rb") as src, open(GEOIP, "wb") as dst:
        shutil.copyfileobj(src, dst)
    gz.unlink()
    print("Saved %s  (IP Geolocation by DB-IP, https://db-ip.com, CC BY 4.0)" % GEOIP)


def darken_ocean(monthly_path, ref):
    """Replace the blue NASA ocean with the near-black ocean of a reference image.

    Ocean = where the reference is dark navy AND the monthly image is not bright
    (so sea ice and snow survive). Edges are feathered to hide coastline mismatch.
    """
    import numpy as np
    from PIL import Image, ImageFilter
    img = Image.open(monthly_path).convert("RGB")
    r = np.asarray(ref.resize(img.size, Image.LANCZOS), dtype=np.int16)
    m = np.asarray(img, dtype=np.int16)
    ref_ocean = (r[..., 0] < 28) & (r[..., 1] < 30) & (r[..., 2] < 75) & (r[..., 2] >= r[..., 1])
    not_ice = m.sum(axis=2) < 480
    mask = Image.fromarray(((ref_ocean & not_ice) * 255).astype("uint8"))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
    Image.composite(ref.resize(img.size, Image.LANCZOS), img, mask).save(monthly_path, quality=92)


def lights_rgba(src):
    """The lights alone out of an opaque night picture (a PIL RGB image): brightness becomes opacity, colour a
    warm white, so they can glow on top of the dimmed map and clouds instead of replacing them."""
    import numpy as np
    from PIL import Image
    a = np.asarray(src, dtype=np.float32)
    lum = a[..., 0] * 0.35 + a[..., 1] * 0.45 + a[..., 2] * 0.20     # blue counts least: unlit land is dark blue
    # unlit land is not black in NASA's picture (deserts and snow are lighter), so find its level in this image:
    # at least 95% of the planet is unlit, which puts the 95th percentile at the bright end of "dark"
    floor = max(24.0, float(np.percentile(lum[::4, ::4], 95)) + 8)
    k = np.clip((lum - floor) / (170 - floor), 0, 1) ** 0.75          # lift small towns a little
    out = np.empty(a.shape[:2] + (4,), dtype=np.uint8)
    out[..., 0] = 255
    out[..., 1] = (206 + 40 * k).astype(np.uint8)                     # amber towns -> near-white city cores
    out[..., 2] = (140 + 95 * k).astype(np.uint8)
    out[..., 3] = (k * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA"), float((k > 0.05).mean())


def night_source():
    """The sharpest night picture there is: the 13 500 px original kept by fetch-maps since 0.47, else night.jpg."""
    for name in ("night-hires.jpg", "night.jpg"):
        if (DATA / name).exists():
            return DATA / name
    return None


def make_lights():
    """lights.png for the whole-world view, from night.jpg (the wallpaper paints these at up to 4096 x 2048)."""
    import numpy as np
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    src = Image.open(DATA / "night.jpg").convert("RGB")
    if src.width > 4096:                          # the wallpaper paints the lights at up to 4096 x 2048
        src = src.resize((4096, 2048), Image.LANCZOS)
    img, share = lights_rgba(src)
    img.save(DATA / "lights.png", optimize=True)
    return share



def cmd_make_lights(_args):
    if not (DATA / "night.jpg").exists():
        sys.exit("night.jpg is missing - run: livemap-helper fetch-maps")
    share = make_lights()
    print("Wrote %s (%.1f%% of the map is lit)" % (DATA / "lights.png", share * 100))


# ---- map styles and frames --------------------------------------------------------------------------
# The wallpaper's base imagery for a frame (the part of the world on screen) and a style:
#   seasonal   NASA Blue Marble, the month's image cropped to the frame (from the hi-res set when it is there)
#   viirs      today's (yesterday's, complete) VIIRS true-colour picture from NASA GIBS, fetched for the frame
#   relief     Blue Marble with shaded relief and bathymetry from NASA GIBS
# Each is written under frames/<key>/ as base.jpg (or base01..12.jpg for the seasonal set) plus night.jpg, the
# key being the frame and the width in pixels, so the wallpaper only has to ask for the file.
FRAMES = DATA / "frames"
GIBS_WMS = "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&SRS=EPSG:4326&FORMAT=image/jpeg"
GIBS_LAYERS = {"viirs": "VIIRS_SNPP_CorrectedReflectance_TrueColor", "relief": "BlueMarble_ShadedRelief_Bathymetry"}
GIBS_CHUNK = 2048                           # pixels per WMS request, each way


def frame_key(n, so, w, e, width, variant=""):
    key = "%d_%d_%d_%d_%d" % (round(n), round(so), round(w), round(e), int(width))
    return key + ("_" + re.sub(r"[^A-Za-z0-9]", "", variant)[:24] if variant else "")


def _frame_variant(args):
    """What else than the frame tells the files apart: the dark style's two colours and detail."""
    if args.style == "dark":
        return args.land.lstrip("#") + args.ocean.lstrip("#") + args.detail
    return "hr" if args.style == "seasonal" and use_hires(args) else ""


def use_hires(args):
    """The hi-res monthly set is cut from when it is there and the setting allows (`--lowres` says no)."""
    return have_hires() and not getattr(args, "lowres", False)


def draw_land(n, so, w, e, width, height, land, ocean, detail="50m"):
    """The dark cartographic style: Natural Earth's country polygons filled in the land colour over the ocean
    colour, drawn by Pillow at the frame's resolution. Drawing this as vector shapes in the wallpaper locked
    the desktop for seconds on every change (half a million edges to triangulate); an image is instant."""
    from PIL import Image, ImageDraw
    f = BORDERS / ("ne_%s_admin_0_countries.geojson" % detail)
    if not f.exists():
        f = BORDERS / "ne_110m_admin_0_countries.geojson"
    if not f.exists():
        raise ValueError("the border data is missing - press 'Download border data' in the settings first")
    im = Image.new("RGB", (width, height), ocean)
    d = ImageDraw.Draw(im)
    sx, sy = width / (e - w), height / (n - so)
    for feat in json.loads(f.read_text(encoding="utf-8"))["features"]:
        g = feat.get("geometry") or {}
        kind, c = g.get("type"), g.get("coordinates") or []
        polys = [c] if kind == "Polygon" else c if kind == "MultiPolygon" else []
        for poly in polys:
            if not poly:
                continue
            outer = poly[0]
            xs = [pt[0] for pt in outer]
            if max(xs) < w or min(xs) > e or max(pt[1] for pt in outer) < so or min(pt[1] for pt in outer) > n:
                continue                                    # entirely outside the frame
            pts = [((pt[0] - w) * sx, (n - pt[1]) * sy) for pt in outer]
            if len(pts) >= 3:
                d.polygon(pts, fill=land)
            for hole in poly[1:]:                           # lakes and enclaves cut out of a country
                hp = [((pt[0] - w) * sx, (n - pt[1]) * sy) for pt in hole]
                if len(hp) >= 3:
                    d.polygon(hp, fill=ocean)
    return im


def _frame_args(args):
    n, so, w, e = float(args.north), float(args.south), float(args.west), float(args.east)
    if not (-90 <= so < n <= 90 and -180 <= w < e <= 180):
        raise ValueError("frame must be north > south within 90 and west < east within 180")
    width = max(256, min(16384, int(args.width)))
    height = max(1, int(round(width * (n - so) / (e - w))))
    return n, so, w, e, width, height


def gibs_image(layer, n, so, w, e, width, height, day, log=print):
    """One image of a GIBS layer over the box, stitched from requests of at most GIBS_CHUNK pixels a side."""
    from PIL import Image
    import io
    out = Image.new("RGB", (width, height))
    cols, rows = -(-width // GIBS_CHUNK), -(-height // GIBS_CHUNK)
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * GIBS_CHUNK, r * GIBS_CHUNK
            x1, y1 = min(width, x0 + GIBS_CHUNK), min(height, y0 + GIBS_CHUNK)
            bw, be = w + (e - w) * x0 / width, w + (e - w) * x1 / width
            bn, bs = n - (n - so) * y0 / height, n - (n - so) * y1 / height
            url = "%s&LAYERS=%s&BBOX=%.5f,%.5f,%.5f,%.5f&WIDTH=%d&HEIGHT=%d%s" % (
                GIBS_WMS, layer, bw, bs, be, bn, x1 - x0, y1 - y0, "&TIME=" + day if day else "")
            log("  GIBS %s: %d x %d at %.1f, %.1f" % (layer, x1 - x0, y1 - y0, bw, bn))
            _c, _h, body, _t = _http(url, timeout=120, limit=MAX_DOWNLOAD)
            tile = Image.open(io.BytesIO(body)).convert("RGB")
            if tile.size != (x1 - x0, y1 - y0):
                tile = tile.resize((x1 - x0, y1 - y0), Image.LANCZOS)
            out.paste(tile, (x0, y0))
    return out


def crop_world_image(src, n, so, w, e, width, height):
    """The frame cut out of a whole-world 2:1 image and scaled to width x height."""
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    im = Image.open(src).convert("RGB")
    W, H = im.size
    box = (int((w + 180) / 360 * W), int((90 - n) / 180 * H), int(round((e + 180) / 360 * W)), int(round((90 - so) / 180 * H)))
    return im.crop(box).resize((width, height), Image.LANCZOS)


def cmd_fetch_frame(args):
    """Imagery for one frame and style into frames/<key>/ (see the notes above). Needs python3-pillow."""
    from datetime import date, timedelta
    try:
        from PIL import Image
        Image.MAX_IMAGE_PIXELS = None
    except ImportError:
        sys.exit("python3-pillow is needed to build frame imagery: sudo dnf install python3-pillow")
    n, so, w, e, width, height = _frame_args(args)
    key = frame_key(n, so, w, e, width, _frame_variant(args))
    dest = FRAMES / key
    dest.mkdir(parents=True, exist_ok=True)
    world = (n, so, w, e) == (90, -90, -180, 180)
    day = ""
    if args.style == "dark":
        draw_land(n, so, w, e, width, height, args.land, args.ocean, args.detail).save(dest / "base.png")
        print("  land drawn in %s over %s, %d x %d" % (args.land, args.ocean, width, height))
    elif args.style == "seasonal":
        if world and not use_hires(args):
            sys.exit("the whole world in the seasonal style needs no frame imagery: it uses the monthly maps as they are")
        for i in range(1, 13):
            src = DATA / "base" / ("hires%02d.jpg" % i)
            if not src.exists() or not use_hires(args):
                src = DATA / "base" / ("%02d.jpg" % i)
            if not src.exists():
                sys.exit("month %02d is missing - run: livemap-helper fetch-maps" % i)
            crop_world_image(src, n, so, w, e, width, height).save(dest / ("base%02d.jpg" % i), quality=90)
            print("  month %02d cropped from %s" % (i, src.name))
    elif args.style in GIBS_LAYERS:
        if args.style == "viirs":                  # today's picture is still being taken: yesterday's is whole
            day = (date.today() - timedelta(days=1)).isoformat() if not args.date else args.date
        gibs_image(GIBS_LAYERS[args.style], n, so, w, e, width, height, day).save(dest / "base.jpg", quality=90)
    else:
        sys.exit("unknown style %r" % args.style)
    night = night_source()
    if night is not None and args.style != "dark":
        try:                                      # the city lights for this view, from the 13 500 px picture when it is there
            lw = min(width, 8192); lh = int(round(lw * height / width))
            img, _share = lights_rgba(crop_world_image(night, n, so, w, e, lw, lh))
            img.save(dest / "lights.png", optimize=True)
            print("  city lights cut from %s" % night.name)
        except ImportError:
            print("  numpy missing: no city lights for this view (the whole-world lights are stretched instead)")
    meta = {"style": args.style, "frame": [n, so, w, e], "width": width, "height": height, "day": day, "at": int(time.time())}
    (dest / "frame.json").write_text(json.dumps(meta), encoding="utf-8")
    emit({"key": key, "note": "", **meta})


def frame_state(style, key):
    """What the wallpaper wants to know about a frame's imagery: present, its day, and whether it is stale."""
    try:
        meta = json.loads((FRAMES / key / "frame.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"ready": False, "stale": True}
    ready = meta.get("style") == style and any((FRAMES / key / f).exists() for f in ("base.jpg", "base.png", "base01.jpg"))
    age_h = (time.time() - meta.get("at", 0)) / 3600
    stale = style == "viirs" and age_h > 20       # a new day's picture
    return {"ready": ready, "stale": stale, "day": meta.get("day", ""), "age_hours": round(age_h, 1)}


def cmd_frame(args):
    """`frame --style S --north ... --width W`: is the imagery there? The wallpaper polls this and fetches when not."""
    n, so, w, e, width, _h = _frame_args(args)
    key = frame_key(n, so, w, e, width, _frame_variant(args))
    world = (n, so, w, e) == (90, -90, -180, 180)
    # the whole world in the seasonal style is the monthly maps as they are, unless the hi-res set is there to cut from
    emit(dict(frame_state(args.style, key), key=key, dir=str(FRAMES / key), hires=use_hires(args),
              skip=args.style == "seasonal" and world and not use_hires(args)))


def chk_frames():
    try:
        dirs = [d for d in FRAMES.iterdir() if d.is_dir() and (d / "frame.json").exists()]
    except OSError:
        return "ok", "none built (the whole world in the seasonal style needs none)"
    if not dirs:
        return "ok", "none built (the whole world in the seasonal style needs none)"
    mb = sum(f.stat().st_size for d in dirs for f in d.iterdir()) / 1e6
    return "ok", "%d frame%s (%.0f MB) under frames/ - old ones can be deleted" % (len(dirs), "" if len(dirs) == 1 else "s", mb)


def cmd_fetch_maps(args):
    if args.hires:                                # the 21600 px set, for regions: hires01..12.jpg beside the 5400 px set
        for i, name in enumerate(MONTHS, 1):
            download("%s/bmng/bmng-topography-bathymetry/%s/world.topo.bathy.2004%02d.3x21600x10800.jpg"
                     % (NASA, name, i), DATA / "base" / ("hires%02d.jpg" % i))
        print("Done. The hi-res maps are used when imagery is cut for a region; the frames built so far are rebuilt from them "
              "the next time the wallpaper looks (within a minute).")
        return
    ref = None
    if args.ocean_from:
        from PIL import Image                     # fail early if pillow is missing
        Image.MAX_IMAGE_PIXELS = None
        ref = Image.open(args.ocean_from).convert("RGB")
    for i, name in enumerate(MONTHS, 1):
        dest = DATA / "base" / ("%02d.jpg" % i)
        download("%s/bmng/bmng-topography-bathymetry/%s/world.topo.bathy.2004%02d.3x5400x2700.jpg"
                 % (NASA, name, i), dest)
        if ref is not None:
            darken_ocean(dest, ref)
    night = DATA / "night.jpg"
    download(NIGHT_URL, night)
    try:                                          # 13500x6750 is more than the whole-world view needs, but a region cuts its lights from it
        from PIL import Image
        Image.MAX_IMAGE_PIXELS = None
        shutil.copyfile(night, DATA / "night-hires.jpg")
        Image.open(night).resize((5400, 2700), Image.LANCZOS).save(night, quality=92)
        make_lights()
        print("  city lights extracted to lights.png")
    except ImportError:
        print("  numpy/pillow not installed: city lights will be shown as the plain night image")
    print("Done. Imagery: NASA Earth Observatory (Blue Marble Next Generation, Black Marble 2016).")
    print("If the wallpaper is already running, un-tick and re-tick 'Follow the seasons' to reload.")


# ----------------------------------------------------------------------------------------------------------------
# Styles: a style is a JSON snapshot of some of the wallpaper's settings. Every setting sits in one of four buckets:
# base (what the map is), look (how every object is drawn), layers (what is on), machine (this computer - never in
# a style). Built-in styles ship with the package as the keys that differ from main.xml's defaults; the helper fills
# in the rest so applying one resets the whole base and look. User styles are full snapshots of the buckets they
# include, in ~/.local/share/livemap/styles/. "previous" is written before every apply so nothing is lost.
STYLES = DATA / "styles"
PKG = Path(__file__).resolve().parent.parent
BUILTIN_STYLES = PKG / "styles"
MAIN_XML = PKG / "config" / "main.xml"
BASE_KEYS = {"MapStyle", "MapTone", "Seasonal", "SeasonalBlend", "SeasonalHires", "FillMode", "LandColor", "OceanColor", "MapDim",
             "ShowDayNight", "ShowCityLights", "NightDarkness", "Twilight", "LightsBrightness"}
LAYER_KEYS = {"SatIss", "SatHubble", "SatTiangong", "SatTrack", "InfraPlatforms", "InfraRefineries", "InfraMode", "CityMinPop",
              "FireMinLevel", "FireMinArea", "FireFocus", "HotspotTier", "LaunchWindow", "VolcanoDetail", "QuakeFeed",
              "NetLabels", "NetShowProcess", "FlagFastRtt", "ShowLatency", "NewWindow", "ShowStormCone"}
MACHINE_KEYS = {"BaseImage", "DataDir", "FrameNorth", "FrameSouth", "FrameWest", "FrameEast", "HomeCity", "HomeLat", "HomeLon",
                "DistanceUnits", "StormUnits", "StaleHours", "HintCorner", "AnimationFps", "GuardEnabled", "GuardPause", "GuardPlain",
                "Profile", "CacheStill", "OnBattery", "LightsGpu", "CloudSource", "FireSource", "NetInterval", "NetLinger", "NetMaxPlaces",
                "ShowProxyNote", "HotspotMinCount", "BorderDetail", "SatTrackLength", "ArcAnimation", "QuakePulseMode", "VolcanoPulseMode",
                "StormPulseMode", "FirePulseMode", "PacketSpeed"}
BUCKET_BIT = {"base": 1, "look": 2, "layers": 4}


def bucket_of(key):
    if key in MACHINE_KEYS:
        return "machine"
    if key in BASE_KEYS:
        return "base"
    if key in LAYER_KEYS or key.startswith("Show"):
        return "layers"
    return "look"


def config_defaults():
    """{key: typed default} from main.xml, in the file's order."""
    out = {}
    text = MAIN_XML.read_text(encoding="utf-8")
    for m in re.finditer(r'<entry name="(\w+)" type="(\w+)">\s*<default>([^<]*)</default>', text):
        key, typ, val = m.group(1), m.group(2), m.group(3).strip()
        if typ == "Int":
            val = int(val)
        elif typ == "Bool":
            val = val.lower() == "true"
        elif typ == "Double":
            val = float(val)
        out[key] = val
    return out


def _slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or "style"


SNAPS = STYLES / "history"
SNAPS_KEEP = 20


def _style_path(sid):
    kind, _, slug = sid.partition(":")
    if kind == "builtin":
        return BUILTIN_STYLES / (slug + ".json")
    if kind == "history":
        return SNAPS / (slug + ".json")
    return STYLES / (slug + ".json")


def _is_colour_key(key):
    return key.endswith("Color") or key.endswith("TextFollows") or key in ("StormIntensityColors", "StormTrackColors", "VolcanoAlertColors", "FireAlertColors")


def _load_style(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def list_styles():
    """Built-ins in their declared order, then the user's styles by name, then Previous when it exists."""
    out = []
    for p in sorted(BUILTIN_STYLES.glob("*.json")):
        s = _load_style(p)
        if s:
            out.append({"id": "builtin:" + p.stem, "name": s.get("name", p.stem), "builtin": True, "order": s.get("order", 99),
                        "includes": 3, "base": s.get("values", {}).get("MapStyle", 0)})
    out.sort(key=lambda s: s["order"])
    users = []
    for p in sorted(STYLES.glob("*.json")):
        s = _load_style(p)
        if not s:
            continue
        row = {"id": "user:" + p.stem, "name": s.get("name", p.stem), "builtin": False, "includes": int(s.get("includes", 3)),
               "base": s.get("values", {}).get("MapStyle", -1), "saved": s.get("at", 0)}
        if p.stem in ("previous", "original"):
            continue
        users.append(row)
    users.sort(key=lambda s: s["name"].lower())
    out += users
    # the snapshots taken before every apply, newest first, after "original" (the settings before styles were first used)
    orig = STYLES / "original.json"
    if orig.exists():
        o = _load_style(orig) or {}
        out.append({"id": "user:original", "name": o.get("name", "Original"), "builtin": False, "includes": 7, "base": -1, "saved": o.get("at", 0), "history": True})
    snaps = []
    for p in SNAPS.glob("*.json"):
        s = _load_style(p)
        if s:
            snaps.append({"id": "history:" + p.stem, "name": s.get("name", p.stem), "builtin": False, "includes": 7, "base": -1, "saved": s.get("at", 0), "history": True})
    snaps.sort(key=lambda s: -s["saved"])
    return out + snaps


def read_style(sid):
    """The style with every value it sets. A built-in is completed with main.xml's defaults for the base and look."""
    path = _style_path(sid)
    s = _load_style(path)
    if not s:
        return None
    values = dict(s.get("values", {}))
    if sid.startswith("builtin:"):
        # a built-in recommends colours: it is completed with the colour defaults so applying one resets every colour,
        # and never touches sizes, widths, opacities or label styles - those are the user's (and their screen's)
        for key, val in config_defaults().items():
            if bucket_of(key) == "base" or (bucket_of(key) == "look" and _is_colour_key(key)):
                values.setdefault(key, val)
        includes = 3
    else:
        includes = int(s.get("includes", 3))
    return {"id": sid, "name": s.get("name", path.stem), "builtin": sid.startswith("builtin:"), "includes": includes,
            "at": s.get("at", 0), "values": values}


def cmd_styles(args):
    """`styles keys` - which setting is in which bucket; `styles list`; `styles read --id user:x`;
    `styles save --name N --includes 3 --values <base64 JSON>` (a snapshot the settings page took; `--id user:previous`
    for the dated one taken before every apply, kept as history/<epoch>.json, the last SNAPS_KEEP; `--id user:original`
    for the one taken the first time the page opens, never overwritten); `styles delete --id`; `styles export --id --path`;
    `styles import --path`."""
    act = args.action
    if act == "keys":
        buckets = {"base": [], "look": [], "layers": [], "machine": []}
        for key in config_defaults():
            buckets[bucket_of(key)].append(key)
        buckets["dir"] = str(STYLES)
        emit(buckets)
    elif act == "list":
        emit(list_styles())
    elif act == "read":
        s = read_style(args.id or "")
        if s is None:
            emit({"error": "no such style: " + (args.id or "")})
        else:
            emit(s)
    elif act == "save":
        import base64
        values = json.loads(base64.b64decode(args.values or "e30=").decode("utf-8"))
        includes = int(args.includes or 3)
        keep = {b for b, bit in BUCKET_BIT.items() if includes & bit}
        values = {k: v for k, v in values.items() if bucket_of(k) in keep}
        sid = args.id or ("user:" + _slug(args.name or "style"))
        if sid.startswith("builtin:"):
            emit({"error": "built-in styles cannot be overwritten; save as a new one"})
            return
        if sid == "user:previous":                       # a snapshot before an apply: dated, kept with the last SNAPS_KEEP
            os.makedirs(SNAPS, exist_ok=True)           # two saves can race here (the original and a previous): both tolerate it
            now = int(time.time())
            sid = "history:" + str(now)
            stamp = time.strftime("%a %H:%M", time.localtime(now))
            args.name = (args.name or "Before an apply") + " \u00b7 " + stamp
            old = sorted(SNAPS.glob("*.json"))
            for p in old[:max(0, len(old) - SNAPS_KEEP + 1)]:
                p.unlink()
        if sid == "user:original" and (STYLES / "original.json").exists():
            emit({"id": sid, "kept": True})               # taken once, the first time the page opens with styles: never overwritten
            return
        os.makedirs(STYLES, exist_ok=True)
        path = _style_path(sid)
        name = args.name or path.stem.replace("-", " ").title()
        path.write_text(json.dumps({"name": name, "includes": includes, "at": int(time.time()), "version": 1,
                                    "values": values}, indent=1), encoding="utf-8")
        emit({"id": sid, "name": name, "includes": includes, "count": len(values)})
    elif act == "delete":
        sid = args.id or ""
        if not (sid.startswith("user:") or sid.startswith("history:")):
            emit({"error": "only your own styles can be deleted"})
            return
        try:
            _style_path(sid).unlink()
            emit({"deleted": sid})
        except OSError as e:
            emit({"error": str(e)})
    elif act == "export":
        s = read_style(args.id or "")
        if s is None:
            emit({"error": "no such style"})
            return
        try:
            Path(args.path).write_text(json.dumps({"name": s["name"], "includes": s["includes"], "version": 1, "at": s["at"],
                                                   "values": s["values"]}, indent=1), encoding="utf-8")
            emit({"exported": args.path})
        except OSError as e:
            emit({"error": str(e)})
    elif act == "import":
        s = _load_style(Path(args.path))
        if not s or not isinstance(s.get("values"), dict):
            emit({"error": "not a Live World Map style file"})
            return
        os.makedirs(STYLES, exist_ok=True)
        name = s.get("name") or Path(args.path).stem
        slug = _slug(name)
        if slug == "previous":
            slug = "previous-imported"
        path = STYLES / (slug + ".json")
        s["name"] = name
        s.setdefault("includes", 3)
        s["at"] = int(time.time())
        path.write_text(json.dumps(s, indent=1), encoding="utf-8")
        emit({"id": "user:" + slug, "name": name})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("net"); n.add_argument("--table", action="store_true")
    n.add_argument("--max", type=int, default=40); n.add_argument("--home-lon", type=float, default=None)
    n.add_argument("--linger", type=int, default=90); n.add_argument("--new-window", type=int, default=3600)
    n.set_defaults(fn=cmd_net)
    w = sub.add_parser("where"); w.add_argument("hosts", nargs="+"); w.set_defaults(fn=cmd_where)
    sub.add_parser("forget").set_defaults(fn=cmd_forget)
    st = sub.add_parser("status"); st.add_argument("--feed", default="4.5_day")
    st.add_argument("--offline", action="store_true"); st.add_argument("--names", action="store_true"); st.set_defaults(fn=cmd_status)
    sub.add_parser("fetch-geoip").set_defaults(fn=cmd_fetch_geoip)
    sub.add_parser("fetch-borders").set_defaults(fn=cmd_fetch_borders)
    sub.add_parser("zone-tint").set_defaults(fn=cmd_zone_tint)
    sub.add_parser("plates").set_defaults(fn=cmd_plates)
    sub.add_parser("fetch-infrastructure").set_defaults(fn=cmd_fetch_infrastructure)
    sub.add_parser("infrastructure").set_defaults(fn=cmd_infrastructure)
    sub.add_parser("make-lights").set_defaults(fn=cmd_make_lights)
    pw = sub.add_parser("power"); pw.add_argument("--layers"); pw.add_argument("--units"); pw.add_argument("--fire-focus", dest="fire_focus", type=int)
    pw.add_argument("--flood-level", dest="flood_level", type=int); pw.add_argument("--nws-each", dest="nws_each", type=int)
    pw.add_argument("--fire-sources", dest="fire_sources", type=int)
    pw.set_defaults(fn=cmd_power)
    cl = sub.add_parser("clouds"); cl.add_argument("--stitch", action="store_true"); cl.add_argument("--force", action="store_true")
    cl.add_argument("--max-age", type=float, default=2.5); cl.set_defaults(fn=cmd_clouds)
    mo = sub.add_parser("mode"); mo.add_argument("--pause", choices=["on", "off"]); mo.add_argument("--plain", choices=["on", "off"])
    mo.add_argument("--hide"); mo.add_argument("--clear", action="store_true")
    mo.add_argument("--clouds", choices=["on", "off", "auto"]); mo.add_argument("--cloud-opacity", dest="cloud_opacity")
    mo.add_argument("--full", choices=["on", "off"]); mo.add_argument("--full-hours", dest="full_hours", type=float)
    mo.set_defaults(fn=cmd_mode)
    fe = sub.add_parser("feed"); fe.add_argument("--feed", default="4.5_day"); fe.add_argument("--limit", type=int, default=60)
    fe.add_argument("--since", type=float); fe.add_argument("--until", type=float); fe.set_defaults(fn=cmd_feed)    # epoch seconds: past events from history.json
    vo = sub.add_parser("volcanoes"); vo.add_argument("--table", action="store_true"); vo.add_argument("--keep", type=float, default=48)
    vo.add_argument("--stale", type=float, default=6)
    vo.set_defaults(fn=cmd_volcanoes)
    so = sub.add_parser("storms"); so.add_argument("--table", action="store_true"); so.add_argument("--keep", type=float, default=48)
    so.add_argument("--stale", type=float, default=6)
    so.set_defaults(fn=cmd_storms)
    fi = sub.add_parser("fires"); fi.add_argument("--table", action="store_true"); fi.add_argument("--keep", type=float, default=48)
    fi.add_argument("--stale", type=float, default=6)
    fi.set_defaults(fn=cmd_fires)
    inc = sub.add_parser("incidents"); inc.add_argument("--sources"); inc.add_argument("--min-ha", dest="min_ha", type=float, default=0)
    inc.add_argument("--max-age", dest="max_age", type=float, default=30); inc.add_argument("--keep", type=float, default=48)
    inc.add_argument("--stale", type=float, default=6); inc.add_argument("--table", action="store_true"); inc.set_defaults(fn=cmd_incidents)
    aa = sub.add_parser("air-alerts"); aa.add_argument("--token", default=""); aa.add_argument("--regions", action="store_true")
    aa.add_argument("--stale", type=float, default=1); aa.add_argument("--table", action="store_true"); aa.set_defaults(fn=cmd_air_alerts)
    fd = sub.add_parser("floods"); fd.add_argument("--table", action="store_true"); fd.add_argument("--keep", type=float, default=48)
    fd.add_argument("--stale", type=float, default=6); fd.add_argument("--all", action="store_true")      # details and area for green events too
    fd.set_defaults(fn=cmd_floods)
    nw = sub.add_parser("nws-floods"); nw.add_argument("--table", action="store_true"); nw.add_argument("--stale", type=float, default=1)
    nw.add_argument("--max-age", dest="max_age", type=float, default=10)   # minutes the cache is trusted
    nw.add_argument("--each", action="store_true"); nw.set_defaults(fn=cmd_nws_floods)   # every alert on its own, not one per office and type
    b = sub.add_parser("borders"); b.add_argument("--detail", default="110m", choices=["110m", "50m"])
    b.add_argument("--states", action="store_true"); b.add_argument("--names", action="store_true")
    b.add_argument("--zones", action="store_true"); b.add_argument("--zone-row", dest="zone_row", type=float)
    b.add_argument("--rivers", action="store_true"); b.add_argument("--river-detail", dest="river_detail", choices=["110m", "50m"])   # rivers' own level (default: the borders')
    b.add_argument("--land", action="store_true")
    b.add_argument("--state-names", dest="state_names", action="store_true"); b.add_argument("--capitals", action="store_true")
    b.add_argument("--state-capitals", dest="state_capitals", action="store_true"); b.add_argument("--city-pop", dest="city_pop", type=int, default=0)
    b.set_defaults(fn=cmd_borders)
    wc = sub.add_parser("where-city"); wc.add_argument("query"); wc.set_defaults(fn=cmd_where_city)
    sa = sub.add_parser("sats"); sa.add_argument("--table", action="store_true"); sa.add_argument("--ahead", type=int, default=100)
    sa.add_argument("--behind", type=int, default=15); sa.set_defaults(fn=cmd_sats)
    la = sub.add_parser("launches"); la.add_argument("--table", action="store_true"); la.add_argument("--stale", type=float, default=6)
    la.set_defaults(fn=cmd_launches)
    hs = sub.add_parser("hotspots"); hs.add_argument("--table", action="store_true"); hs.add_argument("--min-count", type=int, default=3)
    hs.add_argument("--min-tier", type=int, default=0, choices=[0, 1, 2])     # 0 everything, 1 notable and up, 2 needs attention
    hs.add_argument("--people", action="store_true")                          # only clusters near people (a city of 100k within 50 km, or an orange/red event)
    hs.set_defaults(fn=cmd_hotspots)
    for name, fn in (("fetch-frame", cmd_fetch_frame), ("frame", cmd_frame)):
        fr = sub.add_parser(name); fr.add_argument("--style", default="seasonal", choices=["seasonal", "viirs", "relief", "dark"])
        fr.add_argument("--land", default="#2b3542"); fr.add_argument("--ocean", default="#0b1119"); fr.add_argument("--detail", default="50m", choices=["110m", "50m"])
        fr.add_argument("--north", type=float, default=90); fr.add_argument("--south", type=float, default=-90)
        fr.add_argument("--west", type=float, default=-180); fr.add_argument("--east", type=float, default=180)
        fr.add_argument("--width", type=int, default=4096); fr.add_argument("--date", default="")
        fr.add_argument("--lowres", action="store_true"); fr.set_defaults(fn=fn)   # the 5 400 px maps even when the hi-res set is there
    m = sub.add_parser("fetch-maps"); m.add_argument("--ocean-from"); m.add_argument("--hires", action="store_true")
    m.set_defaults(fn=cmd_fetch_maps)
    sy = sub.add_parser("styles"); sy.add_argument("action", choices=["keys", "list", "read", "save", "delete", "export", "import"])
    sy.add_argument("--id"); sy.add_argument("--name"); sy.add_argument("--includes", type=int); sy.add_argument("--values"); sy.add_argument("--path")
    sy.set_defaults(fn=cmd_styles)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
