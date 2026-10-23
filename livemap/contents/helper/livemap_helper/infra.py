"""Oil and gas infrastructure: BSEE platforms, OpenStreetMap platforms and refineries."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import BORDERS, DATA, EVENTS, MAX_BODY, MAX_DOWNLOAD, NE_FILES, PLATES_FILE, UA, _http, _in_ring, \
    _lines, _near_path, _plain, emit, haversine_km


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
