"""The companion widget, from the wallpaper's settings: is it installed, is it on a desktop, put it there.

Plasma's shell scripting (the same interface `plasma-apply-*` and the desktop scripting console use) runs through
D-Bus: org.kde.plasmashell /PlasmaShell evaluateScript. `widget` reports; `widget --add` places one on the current
screen's desktop (every desktop containment on screen 0, which is where the settings dialog opens from).
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

from .common import emit

WIDGET_ID = "io.github.tidybitz.livemap.events"
STORE_URL = "https://store.kde.org/search?search=Live%20World%20Map"

LIST_SCRIPT = """
var out = [];
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
    var d = ds[i], ids = d.widgetIds;
    for (var j = 0; j < ids.length; j++) { var w = d.widgetById(ids[j]); if (w && w.type === "%s") out.push(d.screen); }
}
print(JSON.stringify(out));
""" % WIDGET_ID

ADD_SCRIPT = """
var done = false;
var ds = desktops();
for (var i = 0; i < ds.length && !done; i++) {
    var d = ds[i];
    if (d.screen !== 0) continue;
    var w = d.addWidget("%s");
    if (w) done = true;
}
if (!done && ds.length > 0) { ds[0].addWidget("%s"); done = true; }
print(done ? "added" : "no desktop");
""" % (WIDGET_ID, WIDGET_ID)


def installed():
    home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    for base in (home / "plasma/plasmoids", Path("/usr/share/plasma/plasmoids"), Path("/usr/local/share/plasma/plasmoids")):
        if (base / WIDGET_ID / "metadata.json").exists():
            return True
    return False


def evaluate(script):
    """Run a shell script in plasmashell and return what it printed; None when the shell is not reachable."""
    if shutil.which("gdbus"):
        cmd = ["gdbus", "call", "--session", "--dest", "org.kde.plasmashell", "--object-path", "/PlasmaShell",
               "--method", "org.kde.PlasmaShell.evaluateScript", script]
    else:
        qdbus = shutil.which("qdbus6") or shutil.which("qdbus")
        if not qdbus:
            return None
        cmd = [qdbus, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    out = r.stdout.strip()
    if cmd[0] == "gdbus":                      # gdbus prints ('...',)
        if out.startswith("('") and out.endswith("',)"):
            out = out[2:-3].encode("utf-8").decode("unicode_escape")
        elif out.startswith("(") and out.endswith(",)"):
            out = out[1:-2].strip("'\"")
    return out


def placed_on():
    out = evaluate(LIST_SCRIPT)
    if out is None:
        return None
    try:
        return json.loads(out.strip())
    except ValueError:
        return None


def cmd_widget(args):
    """`widget` -> {installed, placed (screens it is on, or null when plasmashell could not be asked), store};
    `widget --add` places it on the desktop and reports again."""
    result = {"installed": installed(), "store": STORE_URL, "id": WIDGET_ID}
    if getattr(args, "add", False):
        if not result["installed"]:
            result["error"] = "The widget is not installed: install it first (livemap.sh install, or the KDE Store)"
        else:
            out = evaluate(ADD_SCRIPT)
            if out is None:
                result["error"] = "plasmashell could not be asked (D-Bus): add the widget from the desktop's Add Widgets panel"
            elif "added" not in out:
                result["error"] = "No desktop to put it on: " + out
            else:
                result["added"] = True
    result["placed"] = placed_on()
    emit(result)
