"""Styles: JSON snapshots of the wallpaper's settings in buckets."""
import json
import os
import re
import time
from pathlib import Path

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import DATA, PKG, emit


# ----------------------------------------------------------------------------------------------------------------
# Styles: a style is a JSON snapshot of some of the wallpaper's settings. Every setting sits in one of four buckets:
# base (what the map is), look (how every object is drawn), layers (what is on), machine (this computer - never in
# a style). Built-in styles ship with the package as the keys that differ from main.xml's defaults; the helper fills
# in the rest so applying one resets the whole base and look. User styles are full snapshots of the buckets they
# include, in ~/.local/share/livemap/styles/. "previous" is written before every apply so nothing is lost.
STYLES = DATA / "styles"


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
