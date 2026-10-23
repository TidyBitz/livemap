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
`net` never touches the network: it reads `ss` and an offline database."""
import argparse

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .alerts import cmd_air_alerts
from .borders import cmd_borders, cmd_fetch_borders, cmd_zone_tint
from .clouds import cmd_clouds
from .quakes import cmd_quakes
from .coverage import cmd_coverage
from .feed import cmd_feed
from .fetch import cmd_fetch_frame, cmd_fetch_geoip, cmd_fetch_maps, cmd_frame, cmd_make_lights
from .fires import cmd_fires, cmd_hotspots, cmd_incidents
from .floods import cmd_floods, cmd_nws_floods
from .infra import cmd_fetch_infrastructure, cmd_infrastructure, cmd_plates, cmd_where_city
from .net import cmd_forget, cmd_net, cmd_where
from .power import cmd_mode, cmd_power
from .space import cmd_launches, cmd_sats
from .status import cmd_status
from .storms import cmd_storms
from .styles import cmd_styles
from .tsunami import cmd_tsunami
from .volcanoes import cmd_volcanoes


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
    pw.add_argument("--fire-sources", dest="fire_sources", type=int); pw.add_argument("--flood-sources", dest="flood_sources", type=int); pw.add_argument("--quake-sources", dest="quake_sources", type=int)
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
    qk = sub.add_parser("quakes"); qk.add_argument("--feed", default="4.5_day"); qk.add_argument("--sources", type=int, default=3)
    qk.add_argument("--max-age", dest="max_age", type=float, default=300); qk.add_argument("--table", action="store_true"); qk.set_defaults(fn=cmd_quakes)
    cv = sub.add_parser("coverage"); cv.add_argument("--markdown", action="store_true"); cv.add_argument("--home", default="")   # "lat,lon"
    cv.set_defaults(fn=cmd_coverage)
    ts = sub.add_parser("tsunami"); ts.add_argument("--table", action="store_true"); ts.add_argument("--stale", type=float, default=2)
    ts.add_argument("--max-age", dest="max_age", type=float, default=5); ts.set_defaults(fn=cmd_tsunami)
    fd = sub.add_parser("floods"); fd.add_argument("--table", action="store_true"); fd.add_argument("--keep", type=float, default=48)
    fd.add_argument("--stale", type=float, default=6); fd.add_argument("--all", action="store_true")      # details and area for green events too
    fd.set_defaults(fn=cmd_floods)
    nw = sub.add_parser("nws-floods"); nw.add_argument("--table", action="store_true"); nw.add_argument("--stale", type=float, default=1)
    nw.add_argument("--max-age", dest="max_age", type=float, default=10)   # minutes the cache is trusted
    nw.add_argument("--each", action="store_true"); nw.set_defaults(fn=cmd_nws_floods)   # every alert on its own, not one per office and type
    nw.add_argument("--sources", type=int, default=1)                                     # 1 NWS, 2 MeteoAlarm, 4 ECCC, 8 EA (a mask)
    b = sub.add_parser("borders"); b.add_argument("--detail", default="110m", choices=["110m", "50m"])
    b.add_argument("--states", action="store_true"); b.add_argument("--names", action="store_true")
    b.add_argument("--zones", action="store_true"); b.add_argument("--zone-row", dest="zone_row", type=float)
    b.add_argument("--rivers", action="store_true"); b.add_argument("--river-detail", dest="river_detail", choices=["110m", "50m"])   # rivers' own level (default: the borders')
    b.add_argument("--lakes", action="store_true")                                                       # lake outlines at the rivers' level
    b.add_argument("--lake-names", dest="lake_names", type=int, default=-1)                              # lakes named up to this scalerank (-1 none)
    b.add_argument("--sea-names", dest="sea_names", type=int, default=-1)                                # oceans, seas, gulfs up to this scalerank
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
