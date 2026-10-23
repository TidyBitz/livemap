"""Cloud cover: the stitched fallback from the geostationary satellites."""
import json
import urllib.error
import urllib.request

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, MAX_BODY, UA, _age, _http, emit


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
