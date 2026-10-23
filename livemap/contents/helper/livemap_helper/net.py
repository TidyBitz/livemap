"""Where this machine is connected to: sockets, GeoIP, memory of places."""
import ipaddress
import json
import os
import re
import subprocess
from collections import Counter
from datetime import date

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
import socket
from .common import DATA, GEOIP, emit


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
