"""Downloads and image work: NASA maps, city lights, GIBS frames, GeoIP."""
import gzip
import json
import re
import shutil
import sys
import time
from datetime import date

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import BORDERS, DATA, GEOIP, MAX_DOWNLOAD, MONTHS, NASA, NIGHT_URL, _http, download, emit, have_hires


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
