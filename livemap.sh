#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 tidybitz
#
# livemap.sh - install, check, update, remove and inspect the Live World Map wallpaper and its companion
# widget for KDE Plasma 6. Everything is per user; no root is needed. Safe to run more than once.
#
#   livemap.sh doctor [--report]           check every dependency; --report prints what a bug report needs
#   livemap.sh install [livemap.zip]       check dependencies, then install or update wallpaper + widget
#   livemap.sh update                      same as install
#   livemap.sh activate                    make Live World Map the wallpaper on every desktop
#   livemap.sh deactivate                  switch every desktop back to the stock image wallpaper
#   livemap.sh remove                      deactivate, take the widget off panels, uninstall both packages
#   livemap.sh purge                       remove + delete the data folder and the saved settings
#   livemap.sh status                      what is installed, running and stored
#   livemap.sh help [command]
#
# Options:  --force   install even when a required dependency is missing (you are on your own)
#           --yes     do not ask before purge
#
# The install stops when a required dependency is missing and prints the package names to install for
# your distribution. Run `livemap.sh doctor` at any time to see the same list.
set -u

VERSION_SCRIPT="0.45"
WALLPAPER_ID="io.github.tidybitz.livemap.wallpaper"
WIDGET_ID="io.github.tidybitz.livemap.events"
OLD_WALLPAPER_ID="org.livemap.wallpaper"          # ids used before 0.44; remove/purge clean those up too
OLD_WIDGET_ID="org.livemap.events"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/livemap"
WP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/$WALLPAPER_ID"
WG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$WIDGET_ID"
APPLETSRC="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
FORCE=0; YES=0

# ---- output ---------------------------------------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=; G=; Y=; R=; D=; N=; fi
say()  { printf '%s%s%s\n' "$B" "$*" "$N"; }
note() { printf '  %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
dim()  { printf '  %s%s%s\n' "$D" "$*" "$N"; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- distribution and package names -------------------------------------------------------------
# Package names differ per distribution; these are the usual ones. When a name is wrong for yours, search
# your package manager for the QML module path shown next to the missing item (e.g. "QtQuick/Shapes").
distro() {
    local id like
    id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
    like="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}")"
    case "$id $like" in
        *fedora*|*rhel*|*centos*|*nobara*)        echo fedora ;;
        *arch*|*manjaro*|*endeavouros*|*cachyos*) echo arch ;;
        *suse*|*opensuse*)                        echo suse ;;
        *neon*|*ubuntu*|*debian*|*tuxedo*)        echo debian ;;
        *)                                        echo unknown ;;
    esac
}
DISTRO="$(distro)"
PKGS_NEEDED=()

# pkg <key>: the package for a dependency key on this distribution
pkg() {
    case "$DISTRO:$1" in
        fedora:plasma)     echo plasma-workspace ;;
        fedora:kpackage)   echo kf6-kpackage ;;
        fedora:qdbus)      echo qt6-qttools ;;
        fedora:python)     echo python3 ;;
        fedora:unzip)      echo unzip ;;
        fedora:qtquick)    echo qt6-qtdeclarative ;;
        fedora:p5support)  echo plasma5support ;;
        fedora:kirigami)   echo kf6-kirigami ;;
        fedora:kquick)     echo kf6-kdeclarative ;;
        fedora:libplasma)  echo libplasma ;;
        fedora:webengine)  echo qt6-qtwebengine ;;
        fedora:maxminddb)  echo python3-maxminddb ;;
        fedora:pillow)     echo python3-pillow ;;
        fedora:numpy)      echo python3-numpy ;;
        arch:plasma)       echo plasma-workspace ;;
        arch:kpackage)     echo kpackage ;;
        arch:qdbus)        echo qt6-tools ;;
        arch:python)       echo python ;;
        arch:unzip)        echo unzip ;;
        arch:qtquick)      echo qt6-declarative ;;
        arch:p5support)    echo plasma5support ;;
        arch:kirigami)     echo kirigami ;;
        arch:kquick)       echo kdeclarative ;;
        arch:libplasma)    echo libplasma ;;
        arch:webengine)    echo qt6-webengine ;;
        arch:maxminddb)    echo python-maxminddb ;;
        arch:pillow)       echo python-pillow ;;
        arch:numpy)        echo python-numpy ;;
        suse:plasma)       echo plasma6-workspace ;;
        suse:kpackage)     echo kf6-kpackage-tools ;;
        suse:qdbus)        echo qt6-tools ;;
        suse:python)       echo python3 ;;
        suse:unzip)        echo unzip ;;
        suse:qtquick)      echo qt6-declarative-imports ;;
        suse:p5support)    echo plasma5support ;;
        suse:kirigami)     echo kf6-kirigami-imports ;;
        suse:kquick)       echo kf6-kdeclarative-imports ;;
        suse:libplasma)    echo libplasma6-components ;;
        suse:webengine)    echo qt6-webengine-imports ;;
        suse:maxminddb)    echo python3-maxminddb ;;
        suse:pillow)       echo python3-Pillow ;;
        suse:numpy)        echo python3-numpy ;;
        debian:plasma)     echo plasma-workspace ;;
        debian:kpackage)   echo kpackagetool6 ;;
        debian:qdbus)      echo qt6-tools-dev-tools ;;
        debian:python)     echo python3 ;;
        debian:unzip)      echo unzip ;;
        debian:qtquick)    echo "qml6-module-qtquick-shapes qml6-module-qtquick-effects qml6-module-qtquick-dialogs qml6-module-qtquick-layouts qml6-module-qtquick-controls qml6-module-qtcore" ;;
        debian:p5support)  echo qml6-module-org-kde-plasma5support ;;
        debian:kirigami)   echo qml6-module-org-kde-kirigami ;;
        debian:kquick)     echo qml6-module-org-kde-kquickcontrols ;;
        debian:libplasma)  echo qml6-module-org-kde-plasma-core ;;
        debian:webengine)  echo qml6-module-qtwebengine ;;
        debian:maxminddb)  echo python3-maxminddb ;;
        debian:pillow)     echo python3-pil ;;
        debian:numpy)      echo python3-numpy ;;
        *)                 echo "$1" ;;
    esac
}
install_hint() {
    [ ${#PKGS_NEEDED[@]} -gt 0 ] || return 0
    local list; list="$(printf '%s\n' "${PKGS_NEEDED[@]}" | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')"
    case "$DISTRO" in
        fedora) note "sudo dnf install $list" ;;
        arch)   note "sudo pacman -S --needed $list" ;;
        suse)   note "sudo zypper install $list" ;;
        debian) note "sudo apt install $list" ;;
        *)      note "install these with your package manager: $list" ;;
    esac
}

# ---- the checks -----------------------------------------------------------------------------------
qml_dirs() {
    # every place Qt 6 looks for QML modules
    local d
    if have qtpaths6; then d="$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null)"; [ -n "$d" ] && echo "$d"; fi
    for d in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml /usr/lib/aarch64-linux-gnu/qt6/qml /usr/lib/qt/qml; do
        [ -d "$d" ] && echo "$d"
    done
    [ -n "${QML2_IMPORT_PATH:-}" ] && tr ':' '\n' <<<"$QML2_IMPORT_PATH"
    [ -n "${QML_IMPORT_PATH:-}" ] && tr ':' '\n' <<<"$QML_IMPORT_PATH"
    return 0
}
QML_DIRS="$(qml_dirs | awk '!seen[$0]++')"
qml_module() {
    # $1: module path such as QtQuick/Shapes -> 0 when installed (its qmldir exists in an import path)
    local d
    while read -r d; do
        [ -n "$d" ] && [ -e "$d/$1/qmldir" ] && return 0
    done <<<"$QML_DIRS"
    return 1
}
py_module() { python3 -c "import $1" >/dev/null 2>&1; }
plasma_version() { plasmashell --version 2>/dev/null | sed -n 's/^plasmashell *//p' | head -1; }
python_ok() { python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; }

REQUIRED_MISSING=0; OPTIONAL_MISSING=0
req() {
    # req <ok:0/1> <label> <pkgkey> <what breaks>
    if [ "$1" = 0 ]; then ok "$2"; else bad "$2  -  $4"; PKGS_NEEDED+=("$(pkg "$3")"); REQUIRED_MISSING=$((REQUIRED_MISSING + 1)); fi
}
opt() {
    if [ "$1" = 0 ]; then ok "$2"; else warn "$2  -  $4  ($(pkg "$3"))"; OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1)); fi
}

cmd_doctor() {
    local report=0
    [ "${1:-}" = "--report" ] && report=1
    PKGS_NEEDED=(); REQUIRED_MISSING=0; OPTIONAL_MISSING=0
    say "Live World Map doctor  (script $VERSION_SCRIPT, $(date '+%Y-%m-%d %H:%M'))"
    dim "distribution: $(. /etc/os-release 2>/dev/null; printf '%s %s' "${NAME:-?}" "${VERSION_ID:-}")  ->  package names for: $DISTRO"

    say "Required"
    local pv; pv="$(plasma_version)"
    if [ -n "$pv" ] && [ "${pv%%.*}" -ge 6 ] 2>/dev/null; then req 0 "KDE Plasma $pv"; else req 1 "KDE Plasma 6 (found: ${pv:-none})" plasma "this is a Plasma 6 wallpaper"; fi
    have kpackagetool6;      req $? "kpackagetool6 (installs Plasma packages)" kpackage "cannot install the packages"
    have unzip;              req $? "unzip" unzip "cannot open the download"
    if have python3 && python_ok; then req 0 "python3 $(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"; else req 1 "python3 3.9 or newer" python "the helper that fetches every feed is Python"; fi
    if have qdbus6 || have qdbus-qt6 || have qdbus || have gdbus; then req 0 "a D-Bus command line tool (qdbus6 / qdbus-qt6 / gdbus)"; else req 1 "qdbus6 or gdbus" qdbus "activate/remove cannot talk to plasmashell"; fi
    note "QML modules the wallpaper and widget import:"
    qml_module QtQuick/Shapes;                  req $? "QtQuick.Shapes    (QtQuick/Shapes)" qtquick "tracks, cones and arcs cannot draw"
    qml_module QtQuick/Effects;                 req $? "QtQuick.Effects   (QtQuick/Effects)" qtquick "the wallpaper fails to load"
    qml_module QtQuick/Dialogs;                 req $? "QtQuick.Dialogs   (QtQuick/Dialogs)" qtquick "the settings page fails to load"
    qml_module QtQuick/Layouts;                 req $? "QtQuick.Layouts   (QtQuick/Layouts)" qtquick "the settings page and widget fail to load"
    qml_module QtQuick/Controls;                req $? "QtQuick.Controls  (QtQuick/Controls)" qtquick "the settings page and widget fail to load"
    qml_module QtCore;                          req $? "QtCore            (QtCore)" qtquick "the wallpaper fails to load"
    qml_module org/kde/plasma/plasma5support;   req $? "org.kde.plasma.plasma5support" p5support "no layer can run the helper: the map stays empty"
    qml_module org/kde/kirigami;                req $? "org.kde.kirigami" kirigami "the settings page and widget fail to load"
    qml_module org/kde/kquickcontrols;          req $? "org.kde.kquickcontrols" kquick "the colour buttons in the settings fail"
    qml_module org/kde/plasma/components;       req $? "org.kde.plasma.components (+ extras, core, plasmoid)" libplasma "the widget fails to load"

    say "Optional (features that are off by default)"
    py_module maxminddb;          opt $? "python maxminddb" maxminddb "the Network layer (your own connections on the map) stays off"
    qml_module QtWebEngine;       opt $? "QtWebEngine QML module" webengine "the widget cannot embed the ISS / launch streams (players and browser still work)"
    py_module PIL;                opt $? "python Pillow" pillow "cloud stitching runs at half resolution and takes longer"
    py_module numpy;              opt $? "python numpy" numpy "the 'make-lights' helper command is unavailable"

    say "Environment"
    local free; free="$(df -Pk "${XDG_DATA_HOME:-$HOME/.local/share}" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')"
    if [ -n "$free" ] && [ "$free" -ge 700 ]; then ok "free space: ${free} MB (maps and borders need about 350 MB)"; else warn "free space: ${free:-?} MB - the map downloads need about 350 MB"; fi
    if [ "${XDG_SESSION_TYPE:-}" = wayland ] || [ "${XDG_SESSION_TYPE:-}" = x11 ]; then ok "session: ${XDG_SESSION_TYPE}"; else dim "session type unknown (not running inside a desktop session?)"; fi
    if python3 - <<'PY' >/dev/null 2>&1
import urllib.request
urllib.request.urlopen("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_day.geojson", timeout=6).read(64)
PY
    then ok "network: earthquake.usgs.gov reachable"; else warn "network: earthquake.usgs.gov not reachable right now (the map keeps its last data; check later)"; fi

    if [ "$report" = 1 ]; then
        say "Report (paste this into a bug report)"
        note "script $VERSION_SCRIPT, wallpaper $(version_of "$WP_DIR" || echo 'not installed'), widget $(version_of "$WG_DIR" || echo 'not installed')"
        note "plasma $(plasma_version), qt $(qtpaths6 --qt-version 2>/dev/null || qmake6 -query QT_VERSION 2>/dev/null || echo '?'), kernel $(uname -r), session ${XDG_SESSION_TYPE:-?}"
        note "gpu: $(lspci 2>/dev/null | grep -iE 'vga|3d|display' | sed 's/^[0-9a-f:.]* //' | head -2 | tr '\n' ';')"
        note "screens: $(have kscreen-doctor && kscreen-doctor -o 2>/dev/null | grep -oE '[0-9]+x[0-9]+@[0-9]+' | tr '\n' ' ' || echo '?')"
        note "data: $([ -d "$DATA" ] && du -sh "$DATA" 2>/dev/null | cut -f1 || echo none)"
        if [ -f "$WP_DIR/contents/helper/livemap-helper.py" ]; then
            note "helper status (offline):"
            python3 "$WP_DIR/contents/helper/livemap-helper.py" status --offline 2>/dev/null | python3 -c '
import json, sys
try:
    for c in json.load(sys.stdin).get("checks", []): print("    %-5s %s: %s" % (c["state"], c["name"], c["detail"]))
except Exception as e: print("    (no status:", e, ")")'
        fi
        if have journalctl; then
            note "last log lines:"
            journalctl --user -b -o cat 2>/dev/null | grep -i 'livemap' | tail -8 | sed 's/^/    /'
        fi
    fi

    echo
    if [ "$REQUIRED_MISSING" -gt 0 ]; then
        say "$REQUIRED_MISSING required dependenc$([ "$REQUIRED_MISSING" = 1 ] && echo y || echo ies) missing. Install with:"
        install_hint
        note "then run this again. (Package names are the usual ones for $DISTRO; if one is wrong, search your"
        note "package manager for the module path shown in brackets.)"
        return 2
    fi
    if [ "$OPTIONAL_MISSING" -gt 0 ]; then
        say "Everything required is present. $OPTIONAL_MISSING optional item(s) missing - only needed for the features named above."
    else
        say "Everything is present."
    fi
    return 0
}

# ---- talk to the running shell (Plasma scripting API) -------------------------------------------
shell_script() {
    # $1: a Plasma desktop script; runs inside plasmashell, so it changes the live session and its config
    local script="$1"
    if have qdbus6; then
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1
    elif have qdbus-qt6; then
        qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1
    elif have qdbus; then
        qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1
    elif have gdbus; then
        gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
            --method org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1
    else
        return 1
    fi
}

set_wallpaper_plugin() {
    shell_script "var ds = desktops(); for (var i = 0; i < ds.length; i++) { ds[i].wallpaperPlugin = '$1'; }" \
        || note "could not reach plasmashell over D-Bus; change the wallpaper by hand (right-click the desktop)"
}

replace_old_widget_instances() {
    # every old-id widget on a panel or desktop is removed and a new-id one added in its place (same container)
    shell_script "
        var cs = panels().concat(desktops());
        for (var i = 0; i < cs.length; i++) {
            var ws = cs[i].widgets('$OLD_WIDGET_ID');
            if (ws.length === 0) continue;
            for (var k = 0; k < ws.length; k++) { ws[k].remove(); }
            cs[i].addWidget('$WIDGET_ID');
        }" \
        || note "could not reach plasmashell over D-Bus; swap the widget by hand (remove it, then Add Widgets > Live World Map Events)"
}

old_ids_in_use() {
    # 0 when a desktop still draws with the old wallpaper id or a panel still holds the old widget id
    grep -qs "^wallpaperplugin=$OLD_WALLPAPER_ID" "$APPLETSRC" || grep -qs "plugin=$OLD_WIDGET_ID" "$APPLETSRC"
}

migrate_old_ids() {
    # 0.44 renamed the packages. Until the desktop and the panel point at the new ids, every install
    # updates packages nothing is using - the map keeps running the old code. This moves them over.
    if ! old_ids_in_use; then
        # nothing uses them, but leftover old packages are still clutter: drop them quietly
        if kpackagetool6 -t Plasma/Wallpaper -l 2>/dev/null | grep -qx "$OLD_WALLPAPER_ID" \
           || kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$OLD_WIDGET_ID"; then
            echo
            say "Removing the unused pre-0.44 packages"
            remove_package Plasma/Wallpaper "$OLD_WALLPAPER_ID"
            remove_package Plasma/Applet "$OLD_WIDGET_ID"
        fi
        return 0
    fi
    echo
    say "Migrating from the package ids used before 0.44"
    if grep -qs "^wallpaperplugin=$OLD_WALLPAPER_ID" "$APPLETSRC"; then
        set_wallpaper_plugin "$WALLPAPER_ID"; note "desktops switched from $OLD_WALLPAPER_ID to $WALLPAPER_ID"
    fi
    if grep -qs "plugin=$OLD_WIDGET_ID" "$APPLETSRC"; then
        replace_old_widget_instances; note "widget swapped from $OLD_WIDGET_ID to $WIDGET_ID on every panel and desktop"
    fi
    sleep 1
    remove_package Plasma/Wallpaper "$OLD_WALLPAPER_ID"
    remove_package Plasma/Applet "$OLD_WIDGET_ID"
    warn "the settings start from the defaults under the new id (Plasma keys them by package id); the data folder is shared, nothing to download again"
}

remove_widget_instances() {
    shell_script "
        var all = [], ids = ['$WIDGET_ID', '$OLD_WIDGET_ID'];
        for (var n = 0; n < ids.length; n++) {
            var ps = panels(); for (var i = 0; i < ps.length; i++) { all = all.concat(ps[i].widgets(ids[n])); }
            var ds = desktops(); for (var j = 0; j < ds.length; j++) { all = all.concat(ds[j].widgets(ids[n])); }
        }
        for (var k = 0; k < all.length; k++) { all[k].remove(); }" \
        || note "could not reach plasmashell over D-Bus; remove the widget from the panel by hand"
}

# ---- packages ---------------------------------------------------------------------------------
find_zip() {
    local name="$1" f
    for f in "$name" "./$name" "$HOME/Downloads/$name"; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

install_folder() {
    # $1: type (Plasma/Wallpaper | Plasma/Applet)  $2: unpacked package folder  $3: package id
    local type="$1" folder="$2" id="$3"
    if kpackagetool6 -t "$type" -l 2>/dev/null | grep -qx "$id"; then
        kpackagetool6 -t "$type" -u "$folder" >/dev/null && ok "updated $id" || die "update of $id failed"
    else
        kpackagetool6 -t "$type" -i "$folder" >/dev/null && ok "installed $id" || die "install of $id failed"
    fi
}

install_zip() {
    local zip="$1" tmp found=0
    tmp="$(mktemp -d)"
    unzip -o -q "$zip" -d "$tmp" || { rm -rf "$tmp"; die "could not unpack $zip"; }
    if [ -d "$tmp/livemap" ]; then install_folder Plasma/Wallpaper "$tmp/livemap" "$WALLPAPER_ID"; found=1; fi
    if [ -d "$tmp/livemap-widget" ]; then install_folder Plasma/Applet "$tmp/livemap-widget" "$WIDGET_ID"; found=1; fi
    [ "$found" = 1 ] || { rm -rf "$tmp"; die "$zip holds neither livemap/ nor livemap-widget/"; }
    # replace this script with the packaged one atomically (mv keeps the running copy's inode intact)
    if [ -f "$tmp/livemap.sh" ] && ! cmp -s "$tmp/livemap.sh" "$0"; then
        cp "$tmp/livemap.sh" "$0.new" 2>/dev/null && chmod +x "$0.new" && mv -f "$0.new" "$0" 2>/dev/null && note "livemap.sh itself updated (takes effect next run)"
    fi
    rm -rf "$tmp"
}

remove_package() {
    local type="$1" id="$2"
    if kpackagetool6 -t "$type" -l 2>/dev/null | grep -qx "$id"; then
        kpackagetool6 -t "$type" -r "$id" >/dev/null && ok "uninstalled $id" || warn "kpackagetool6 could not remove $id"
    fi
    local base="${XDG_DATA_HOME:-$HOME/.local/share}/plasma" d
    case "$type" in
        Plasma/Wallpaper) d="$base/wallpapers/$id" ;;
        Plasma/Applet)    d="$base/plasmoids/$id" ;;
    esac
    [ -d "$d" ] && rm -rf "$d" && note "deleted $d"
    return 0
}

version_of() { sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$1/metadata.json" 2>/dev/null | head -1; }

# ---- saved settings in the Plasma config ---------------------------------------------------------
purge_settings() {
    # Drops the wallpaper's settings groups and the widget's applet groups from the Plasma config.
    # Only while plasmashell is stopped, with a backup.
    [ -f "$APPLETSRC" ] || return 0
    cp -a "$APPLETSRC" "$APPLETSRC.livemap-backup.$(date +%s)"
    python3 - "$APPLETSRC" "$WALLPAPER_ID" "$WIDGET_ID" "$OLD_WALLPAPER_ID" "$OLD_WIDGET_ID" <<'PY'
import re, sys
path = sys.argv[1]
wps, wgs = (sys.argv[2], sys.argv[4]), (sys.argv[3], sys.argv[5])
text = open(path, encoding="utf-8").read()
blocks = re.split(r"(?m)^(?=\[)", text)
keep, applet_groups = [], set()
for b in blocks:
    head = b.split("\n", 1)[0]
    if any("plugin=" + wg in b for wg in wgs):
        m = re.match(r"\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]", head)
        if m:
            applet_groups.add(m.group(0))
for b in blocks:
    head = b.split("\n", 1)[0]
    if any("[Wallpaper][" + wp + "]" in head for wp in wps):
        continue
    if any(head.startswith(g) for g in applet_groups):
        continue
    keep.append(b)
new = "".join(keep)
for wp in wps:
    new = re.sub(r"(?m)^wallpaperplugin=" + re.escape(wp) + r"$", "wallpaperplugin=org.kde.image", new)
ids = {re.search(r"\[Applets\]\[(\d+)\]", g).group(1) for g in applet_groups}
def order(m):
    kept = [i for i in m.group(1).split(";") if i and i not in ids]
    return "AppletOrder=" + ";".join(kept)
new = re.sub(r"(?m)^AppletOrder=(.*)$", order, new)
open(path, "w", encoding="utf-8").write(new)
print("  removed %d settings block(s)" % (len(blocks) - len(keep)))
PY
}

stop_shell()  { have kquitapp6 && kquitapp6 plasmashell >/dev/null 2>&1; sleep 2; }
start_shell() { (setsid kstart plasmashell >/dev/null 2>&1 &) ; sleep 1; }

# ---- commands ---------------------------------------------------------------------------------
cmd_install() {
    local zips=() a z
    for a in "$@"; do [ -f "$a" ] && zips+=("$a"); done
    if [ ${#zips[@]} -eq 0 ]; then
        z="$(find_zip livemap.zip || true)"; [ -n "$z" ] && zips+=("$z")
    fi
    [ ${#zips[@]} -gt 0 ] || die "no livemap.zip found (give the path, or put it in . or ~/Downloads)"
    if ! cmd_doctor; then
        if [ "$FORCE" = 1 ]; then
            warn "continuing anyway because of --force"
        else
            echo
            die "not installing: a required dependency is missing (see above). Install it and run again, or use --force."
        fi
    fi
    echo
    say "Installing"
    for z in "${zips[@]}"; do install_zip "$z"; done
    note "wallpaper $(version_of "$WP_DIR" || echo '-') / widget $(version_of "$WG_DIR" || echo '-')"
    migrate_old_ids
    echo
    if grep -qs "\[Wallpaper\]\[$WALLPAPER_ID\]" "$APPLETSRC"; then
        say "Done. The map is already in use: re-apply it (Desktop settings > Apply) or run:  $0 activate"
    else
        say "Done. Next:"
        note "1. $0 activate                       - make it the wallpaper on every desktop"
        note "2. right-click the desktop > Configure Desktop and Wallpaper > Status > Download maps and border data"
        note "3. right-click a panel > Add Widgets > 'Live World Map Events' for the companion widget"
    fi
}

cmd_activate() {
    [ -d "$WP_DIR" ] || die "wallpaper not installed - run: $0 install"
    say "Activating Live World Map on every desktop"
    set_wallpaper_plugin "$WALLPAPER_ID"
    note "done. Right-click the desktop > Configure Desktop and Wallpaper for the settings."
}

cmd_deactivate() {
    say "Switching every desktop to the stock image wallpaper"
    set_wallpaper_plugin "org.kde.image"
    note "done. The packages stay installed; '$0 activate' brings the map back."
}

cmd_remove() {
    say "Removing Live World Map"
    set_wallpaper_plugin "org.kde.image";  note "desktops switched to the image wallpaper"
    remove_widget_instances;               note "widget instances removed from panels and desktops"
    sleep 1
    pkill -f "livemap-helper.py" 2>/dev/null && note "stopped a running helper" || true
    remove_package Plasma/Wallpaper "$WALLPAPER_ID"
    remove_package Plasma/Applet "$WIDGET_ID"
    remove_package Plasma/Wallpaper "$OLD_WALLPAPER_ID"
    remove_package Plasma/Applet "$OLD_WIDGET_ID"
    note "packages gone. Data folder kept: $DATA  (run '$0 purge' to delete it and the saved settings)"
}

cmd_purge() {
    if [ "$YES" != 1 ]; then
        printf 'This removes the wallpaper, the widget, the data folder (%s) and the saved settings. Continue? [y/N] ' "$DATA"
        read -r ans; case "$ans" in y|Y|yes) ;; *) echo "nothing done"; exit 0 ;; esac
    fi
    cmd_remove
    say "Purging data and settings"
    if [ -d "$DATA" ]; then rm -rf "$DATA" && note "deleted $DATA"; else note "no data folder"; fi
    if grep -qs "$WALLPAPER_ID\|$WIDGET_ID\|$OLD_WALLPAPER_ID\|$OLD_WIDGET_ID" "$APPLETSRC"; then
        note "removing saved settings from $(basename "$APPLETSRC") (plasmashell restarts, a backup is kept)"
        stop_shell
        purge_settings
        start_shell
    else
        note "no saved settings left in the Plasma config"
    fi
    note "nothing of Live World Map remains (the journal keeps its old log lines until it rotates)"
}

cmd_status() {
    say "Live World Map status"
    if [ -d "$WP_DIR" ]; then note "wallpaper: installed, version $(version_of "$WP_DIR")  ($WP_DIR)"; else note "wallpaper: not installed"; fi
    if [ -d "$WG_DIR" ]; then note "widget:    installed, version $(version_of "$WG_DIR")  ($WG_DIR)"; else note "widget:    not installed"; fi
    if grep -qs "\[Wallpaper\]\[$WALLPAPER_ID\]" "$APPLETSRC"; then note "settings:  saved in $(basename "$APPLETSRC")"; else note "settings:  none saved"; fi
    if grep -qs "plugin=$WIDGET_ID" "$APPLETSRC"; then note "widget:    placed on a panel or desktop"; fi
    if grep -qs "^wallpaperplugin=$WALLPAPER_ID" "$APPLETSRC"; then note "active:    yes, on at least one desktop"; else note "active:    no desktop uses it right now ('$0 activate')"; fi
    if old_ids_in_use; then warn "the desktop or a panel still uses the pre-0.44 ids ($OLD_WALLPAPER_ID / $OLD_WIDGET_ID): what you see is the OLD code. Run '$0 install' to migrate."; fi
    if pgrep -f "livemap-helper.py" >/dev/null 2>&1; then note "helper:    running right now ($(pgrep -fc livemap-helper.py) process)"; else note "helper:    not running (it only runs for a few seconds per fetch)"; fi
    if [ -d "$DATA" ]; then note "data:      $DATA ($(du -sh "$DATA" 2>/dev/null | cut -f1))"; else note "data:      none"; fi
    if have journalctl; then
        local last; last="$(journalctl --user -b -o cat 2>/dev/null | grep -i 'livemap:.*loaded' | tail -1)"
        [ -n "$last" ] && note "journal:   $last"
    fi
    note "dependencies: '$0 doctor'"
}

cmd_help() {
    case "${1:-}" in
        doctor)   echo "doctor [--report]: checks Plasma, the tools, python, every QML module the packages import, and the optional extras;"
                  echo "  prints the install command for your distribution when something is missing. --report adds versions, GPU,"
                  echo "  screens, the helper's status and the last log lines, for a bug report." ;;
        install|update) echo "install [livemap.zip] [--force]: runs doctor first and stops when a required dependency is missing; then"
                  echo "  installs or updates the wallpaper and the widget from the zip (looked for in ., then ~/Downloads)." ;;
        activate) echo "activate: sets Live World Map as the wallpaper on every desktop, through plasmashell's scripting interface." ;;
        deactivate) echo "deactivate: sets the stock image wallpaper on every desktop; nothing is uninstalled." ;;
        remove)   echo "remove: deactivate, remove the widget from every panel and desktop, uninstall both packages. Data and settings stay." ;;
        purge)    echo "purge [--yes]: remove, then delete the data folder and the saved settings (plasmashell is restarted; a backup of the"
                  echo "  config file is kept next to it)." ;;
        status)   echo "status: versions, whether the map is active, whether the helper is running, and the data folder size." ;;
        *) sed -n '5,22p' "$0" ;;
    esac
}

# ---- options and dispatch -------------------------------------------------------------------------
ARGS=()
for a in "$@"; do
    case "$a" in
        --force) FORCE=1 ;;
        --yes|-y) YES=1 ;;
        *) ARGS+=("$a") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"
case "${1:-}" in
    doctor)         shift; cmd_doctor "$@" ;;
    install|update) shift; cmd_install "$@" ;;
    activate)   cmd_activate ;;
    deactivate) cmd_deactivate ;;
    remove)     cmd_remove ;;
    purge)      cmd_purge ;;
    status)     cmd_status ;;
    help|-h|--help) shift; cmd_help "$@" ;;
    *) cmd_help; exit 1 ;;
esac
