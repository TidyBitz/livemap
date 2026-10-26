"""The health report: one check per source, the wallpaper's log."""
import json
import time
import re
import shutil
import subprocess
from collections import Counter
from datetime import date
from pathlib import Path

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .alerts import chk_air_alerts
from .clouds import chk_cloud_stitch
from .common import DATA, GEOIP, NASA, VERSION, _age, _http, emit, have_hires
from .feed import chk_power
from .fetch import chk_frames
from .fires import chk_cwfis, chk_effis, chk_fires, chk_hotspots, chk_nifc
from .quakes import chk_emsc
from .warnings import chk_meteoalarm, chk_eccc, chk_ea
from .floods import chk_floods, chk_nws_floods
from .infra import chk_borders, chk_infrastructure, chk_plates
from .net import connections, lookup
from .space import chk_launches, chk_sats
from .storms import chk_storms, chk_storms_jtwc, chk_storms_nhc
from .tsunami import chk_tsunami
from .vaac import chk_vaac
from .volcanoes import chk_geonet, chk_jma, chk_eruptions, chk_usgs_alerts, chk_volcanoes, chk_weekly_page


def chk_maps():
    have = [f for f in ((DATA / "base" / ("%02d.jpg" % i)) for i in range(1, 13)) if f.exists()]
    if len(have) == 12:
        mb = sum(f.stat().st_size for f in have) / 1e6
        return "ok", "12 of 12 monthly images (%.0f MB), downloaded %s" % (mb, date.fromtimestamp(have[0].stat().st_mtime))
    if have:
        return "warn", "%d of 12 monthly images - run: livemap-helper fetch-maps" % len(have)
    return "warn", "not downloaded, so the fallback image is shown - run: livemap-helper fetch-maps"


def chk_hires():
    if have_hires():
        mb = sum((DATA / "base" / ("hires%02d.jpg" % i)).stat().st_size for i in range(1, 13)) / 1e6
        return "ok", "12 of 12 monthly images at 21 600 px (%.0f MB): regions are cut from these" % mb
    have = sum((DATA / "base" / ("hires%02d.jpg" % i)).exists() for i in range(1, 13))
    return "warn", ("%d of 12 - run: livemap-helper fetch-maps --hires" % have) if have else \
        "not downloaded: a region is cut from the 5 400 px maps, which are soft beyond about 2x (press Download, about 330 MB)"


def _sky_entry(key):
    """The Sky tab's cache (sky.json): the age and the last error of one of its sources."""
    try:
        c = json.loads((DATA / "sky.json").read_text(encoding="utf-8"))
        return c.get(key) or {}
    except (OSError, ValueError):
        return {}


def chk_open_meteo():
    """Not probed live: the Sky tab asks every 20 min and its cache says how that went (a probe here would be a
    second request per check for a source that is only used when the tab is open)."""
    e = _sky_entry("forecast")
    if not e:
        return "ok", "not asked yet - the widget's Sky tab fetches it when opened (no home place: nothing to ask)"
    age = (_age(time.time() - e["good_at"]) + " ago") if e.get("good_at") else "never"
    if e.get("error"):
        return ("warn" if e.get("data") else "error"), "last answer %s; the latest request failed: %s" % (age, e["error"])
    return "ok", "forecast for the home place, fetched %s" % age


def chk_swpc():
    e = _sky_entry("kp")
    if not e:
        return "ok", "not asked yet - fetched with the Sky tab"
    age = (_age(time.time() - e["good_at"]) + " ago") if e.get("good_at") else "never"
    if e.get("error"):
        return ("warn" if e.get("data") else "error"), "last answer %s; the latest request failed: %s" % (age, e["error"])
    return "ok", "planetary K index %s, fetched %s" % ((e.get("data") or {}).get("kp", "?"), age)


def chk_live():
    """The widget's Live tab: what each channel /live page resolved to (live-urls.json), so the parsing can be seen."""
    try:
        c = json.loads((DATA / "live-urls.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "ok", "no channel page asked yet - the Live tab asks when a channel /live stream is chosen"
    parts, bad = [], 0
    for url, r in sorted(c.items()):
        short = url.replace("https://www.youtube.com/", "")
        if r.get("error"):
            bad += 1; parts.append("%s: %s" % (short, r["error"][:60]))
        elif r.get("video"):
            parts.append("%s -> %s (%s, %s ago)" % (short, r["video"], r.get("how", "?"), _age(time.time() - r.get("at", 0))))
        else:
            parts.append("%s: nothing live (%s ago)" % (short, _age(time.time() - r.get("at", 0))))
    return ("warn" if bad else "ok"), "; ".join(parts)


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


def status_jobs(offline=False, feed="4.5_day"):
    """The checks, in the order the settings page shows them: (name, callable). The names are what the settings
    sections and contents/data/sources.json refer to."""
    jobs = [("Seasonal maps (NASA Blue Marble)", chk_maps), ("Hi-res seasonal maps (NASA Blue Marble, for regions)", chk_hires),
            ("City lights (NASA Black Marble)", chk_night), ("Map style imagery (frames)", chk_frames),
            ("Borders (Natural Earth)", chk_borders), ("Plate boundaries (PB2002)", chk_plates), ("Oil and gas infrastructure (BSEE, OpenStreetMap)", chk_infrastructure), ("GeoIP database (DB-IP)", chk_geoip), ("Connections (ss)", chk_sockets),
            ("Power and load", chk_power)]
    if not offline:
        jobs += [("Storms (GDACS)", chk_storms), ("Storms, secondary (NHC)", chk_storms_nhc), ("Storms, secondary (JTWC)", chk_storms_jtwc), ("Wildfires (GDACS)", chk_fires), ("US fire incidents (NIFC)", chk_nifc), ("Canadian fires (CWFIS)", chk_cwfis), ("European burnt areas (EFFIS)", chk_effis), ("Floods (GDACS)", chk_floods), ("Air raid alerts (alerts.in.ua)", chk_air_alerts), ("US flood alerts (NWS)", chk_nws_floods), ("European warnings (MeteoAlarm)", chk_meteoalarm), ("Canadian alerts (Environment Canada)", chk_eccc), ("England flood warnings (Environment Agency)", chk_ea), ("Tsunami bulletins (PTWC / NTWC)", chk_tsunami), ("Volcanoes (Smithsonian / USGS)", chk_volcanoes), ("Volcano alert levels (USGS)", chk_usgs_alerts), ("Volcano alert levels (GeoNet)", chk_geonet), ("Volcano alert levels (JMA)", chk_jma), ("Ash advisories (Washington VAAC)", chk_vaac), ("Eruption database (Smithsonian)", chk_eruptions), ("Weekly report page (Smithsonian)", chk_weekly_page),
                 ("Fire hotspots (NASA FIRMS)", chk_hotspots), ("Satellite elements (CelesTrak)", chk_sats), ("Weather at home (Open-Meteo)", chk_open_meteo), ("Space weather (NOAA SWPC)", chk_swpc), ("Live streams (YouTube channel pages)", chk_live),
                 ("Launches (The Space Devs)", chk_launches), ("Earthquake feed (USGS)", lambda: chk_usgs(feed)), ("Earthquakes, secondary (EMSC)", chk_emsc), ("Cloud image (matteason.co.uk)", chk_clouds), ("Cloud stitching (NASA GIBS, EUMETView)", chk_cloud_stitch),
                 ("NASA image server", chk_nasa)]
    return jobs


def cmd_status(args):
    from concurrent.futures import ThreadPoolExecutor
    jobs = status_jobs(args.offline, args.feed)
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
