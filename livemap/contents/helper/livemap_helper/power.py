"""Battery, load guard, the widget's mode file, the layers file."""
import json
import os
import subprocess
import sys
import time

# Python tries a host's addresses one after another and waits for each to time out. On a network
# where IPv6 is advertised but does not actually work, that turned every download into a ~50 s
# wait (seen in the field). Trying IPv4 first fixes that; IPv6 stays available as the fallback.
from .common import LOAD_STATE, MODE, emit, on_battery, read_mode, write_layers


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


def cmd_power(args):
    """One line of JSON for the wallpaper's 20-second poll: power source, load, and the widget's mode file.
    `--layers quakes,storms,...` is the wallpaper telling the widget which event layers it shows (layers.json)."""
    if getattr(args, "layers", None) is not None:
        write_layers(args.layers, getattr(args, "units", None), getattr(args, "fire_focus", None), getattr(args, "flood_level", None), getattr(args, "nws_each", None), getattr(args, "fire_sources", None), getattr(args, "flood_sources", None), getattr(args, "quake_sources", None),
                     getattr(args, "home", None), getattr(args, "passes", None), getattr(args, "saving", None), getattr(args, "why", None))
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
