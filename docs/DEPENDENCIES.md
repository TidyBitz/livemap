# Dependencies and the supply chain

Everything the wallpaper and the widget run, load or call, and the rules that keep that list short. The point
of the list: a library is a way into a machine, so there should be few of them, all from the distribution's
own packages, none fetched by the project itself. (Checked against the code on 31 October 2026; the tests and
`scripts/check.py` keep the code honest, this page is kept by hand when a line changes.)

## The short version

- **No package manager is involved at runtime.** Nothing is installed with pip, npm or cargo; the repository
  vendors no third-party code. The helper is Python standard library plus three optional libraries that come
  from your distribution (`dnf`, `pacman`, `zypper`, `apt`), each of which turns one feature on when present
  and off when not.
- **Nothing downloaded is code.** The downloads are images (JPEG, PNG), GeoJSON,
  CSV, JSON and XML. They are parsed as data by the standard library and never executed, imported or
  evaluated; XML with a DOCTYPE or entity declarations is refused (`common.safe_xml`); every string that will
  be shown is stripped of unprintable characters and markup and cut to length (`common.clean`); every fetch is
  HTTPS only and size-capped (`common.MAX_BODY`).
- **QML never touches the network.** Every fetch goes through the helper, a separate short-lived process; the
  wallpaper and the widget read the files it leaves and parse its JSON on stdout. The one exception is the
  widget's optional embedded video player, which is a browser engine by nature (see below).
- **The install script copies two folders and restarts plasmashell.** It runs no downloaded code either: the zip
  it installs is the repository's own `livemap/` and `livemap-widget/` folders.

## Runtime: the helper (Python)

Python 3.9 or newer. From the standard library: `argparse, base64, calendar, collections, concurrent.futures,
contextlib, csv, datetime, email, glob, gzip, hashlib, html, http, io, ipaddress, json, math, os, pathlib, re,
shutil, socket, struct, subprocess, sys, time, unicodedata, urllib, xml.etree, zoneinfo`.

Optional, from the distribution's packages (`livemap.sh doctor` names the package for Fedora, Arch, openSUSE
and Debian/Ubuntu/neon; the feature is simply off without it):

| Library | Package (Fedora) | Used for | Without it |
|---|---|---|---|
| Pillow (`PIL`) | `python3-pillow` | cutting map frames for regions and the non-seasonal styles, the time-zone tint, downscaling bubble pictures, the black-tile check on satellite snapshots, the rain radar frames, faster cloud stitching | seasonal style only at native size; pictures kept as fetched; no radar pop-up (it says so); cloud fallback slower |
| NumPy | `python3-numpy` | extracting the city lights from the Black Marble image | city lights not extracted |
| maxminddb | `python3-maxminddb` | reading the DB-IP GeoIP database for the Network layer | Network layer unavailable (off by default anyway) |

Programs the helper runs, all found on `PATH`, none required: `ss` (the Network layer's own sockets),
`nvidia-smi` (GPU load, only when present), `journalctl` (the Status page's log excerpt), `gdbus` or `qdbus`
(the settings page asking plasmashell whether the widget is on a desktop). Each is called with a fixed
argument list, never through a shell, with a timeout.

## Runtime: the wallpaper and the widget (QML)

Qt 6 modules: `QtQuick`, `QtQuick.Window`, `QtQuick.Shapes`, `QtQuick.Controls`, `QtQuick.Layouts`,
`QtQuick.Effects`, `QtQuick.Dialogs`, `QtCore`, `Qt.labs.folderlistmodel` (the focus-file watcher; polling
takes over without it).

KDE modules: `org.kde.plasma.plasmoid`, `org.kde.plasma.core`, `org.kde.plasma.components`,
`org.kde.plasma.extras`, `org.kde.plasma.plasma5support` (the executable data engine that runs the helper),
`org.kde.kirigami`, `org.kde.ksvg`, `org.kde.kquickcontrols`. All of these ship with Plasma 6.

Optional: `QtWebEngine` (`qt6-qtwebengine` on Fedora) for the widget's embedded ISS and launch streams. This is
a full Chromium engine and the one component here that renders remote content; it is loaded only while the
Live tab is open with embedding on, runs in its own sandboxed `QtWebEngineProcess`, is given a page of our
own containing a single YouTube iframe with `referrerpolicy=origin`, and has plugins and pop-ups disabled.
Without it the Live tab offers "Open in player" and "Open in browser" instead.

Programs the QML side runs through the executable data engine (a `/bin/sh -c`): `python3` with the helper's
path for every data request; `cat` to read focus.json; `printf` and `mv` to write it. Optional and only on a
click: the player set in the widget's settings (`mpv` by default) for "Open in player"; `pw-play`, `paplay` or
`aplay` for the notification sound; the system browser through `Qt.openUrlExternally` for every link. Links
handed to the browser or the player are accepted only when they match `^https?://` with no quotes or
whitespace (`webUrl`), and the player command runs with the URL in single quotes.

## Install and maintenance

`livemap.sh` uses `kpackagetool6` (install the packages), `plasmashell`, `kquitapp6` and `kstart` (the
restart), `qdbus6`/`qdbus` or `gdbus` (activate the wallpaper through plasmashell's scripting), `unzip`, `python3`
and ordinary coreutils. It installs from the zip or the checkout it was given, nothing else.

## Development and CI (not on users' machines)

GitHub Actions on `ubuntu-latest`: `actions/checkout`, `actions/setup-python`, `actions/setup-node`,
`actions/upload-artifact`, `softprops/action-gh-release`, pinned to major versions; Dependabot proposes their
updates. Installed there with pip for the checks only: `ruff`, `pytest`, `pillow`; `qmllint` from the Qt
packages. None of this is in the zip.

## What to watch

- A new `import` in the helper that is not standard library needs a line in the table above, a `doctor` hint
  in `livemap.sh`, and a graceful "without it" path. Three rows is the budget; a convenience library (an HTTP
  client, a geometry or astronomy package) is not worth a row when the standard library can do the job in a
  page of code.
- A new QML `import` of a module Plasma does not ship by default belongs behind a `Loader`, like QtWebEngine
  and the folder watcher, so its absence costs one feature and not the wallpaper.
- The data sources (docs/SOURCES.md) are the larger attack surface: a feed can send anything. The defences are
  in `common.py` - HTTPS, size caps, data-only parsing, `safe_xml`, `clean` - and every parser works from a
  recorded fixture so a change in a feed's shape fails a test, not a desktop.
- Security reports: see [SECURITY.md](../SECURITY.md).
