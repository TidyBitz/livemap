# Live World Map - wallpaper package

Developer notes for the wallpaper package. The user-facing README, install steps and credits are in the
repository root (../README.md).

## Install

Requirements: KDE Plasma 6 on Linux, Python 3.9 or newer, and the QML modules Plasma ships with
(QtQuick Shapes/Effects/Dialogs, Kirigami, plasma5support, libplasma). `livemap.sh doctor` checks all of
them and prints the exact packages to install for Fedora, Arch, openSUSE, Debian/Ubuntu/KDE neon; the
install refuses to continue while a required one is missing, so "it does not work" always has a list to
point at. Optional extras, only for features that are off by default: `python3-maxminddb` (the Network
layer), QtWebEngine (embedded live streams in the widget), Pillow (faster cloud stitching).

    livemap.sh doctor                     # what is missing, if anything
    livemap.sh install ~/Downloads/livemap.zip
    livemap.sh activate                   # make it the wallpaper on every desktop

Then right-click the desktop > Configure Desktop and Wallpaper > **Status** > *Download maps and border data*
(about 350 MB from NASA and Natural Earth, once). Until the monthly images exist the wallpaper falls back to
the single image you choose in the settings, so you can point that at your current wallpaper straight away.
`livemap-helper fetch-maps --ocean-from ~/Pictures/your-wallpaper.jpg` keeps the near-black ocean of your
own image instead of NASA's blue one (needs numpy + Pillow).

Wallpaper settings in Plasma are per screen and per Activity, so "split by
category" comes for free: same plugin, different boxes ticked on each monitor.

## Managing it: livemap.sh

`livemap.zip` holds the wallpaper (`livemap/`), the companion widget (`livemap-widget/`) and this script.
`livemap.sh` does everything from a terminal, per user, no root:

    livemap.sh doctor [--report]                              check every dependency; --report adds what a bug report needs
    livemap.sh install [livemap.zip] [--force]                check dependencies, then install or update both (looks in . and ~/Downloads)
    livemap.sh activate | deactivate                          switch every desktop to the map / back to the stock image
    livemap.sh remove                                         deactivate, take the widget off the panels, uninstall both
    livemap.sh purge [--yes]                                  remove + delete ~/.local/share/livemap and the saved settings
    livemap.sh status                                         what is installed, running and stored

Nothing runs in the background: the wallpaper is QML inside plasmashell and the helper is a script that
runs for a few seconds per fetch. `remove` leaves only the data folder; `purge` leaves nothing (it restarts
plasmashell once to edit the Plasma config, keeping a backup of it).

## Companion widget

`livemap-widget/` in the download (package io.github.tidybitz.livemap.events, installed by livemap.sh) lists the newest events with links to their
sources and offers pause / plain-map / hide-layer switches; it uses this wallpaper's helper and caches.
Its switches arrive through `~/.local/share/livemap/mode.json`, read by `livemap-helper power` every 20 s.

## How it fits together

    contents/ui/main.qml        base map, clouds, night side, Loaders for overlays
    contents/ui/geo.js          sun position, month blending, great-circle arcs (pure JS)
    contents/ui/QuakeLayer.qml  template for "fetch JSON, draw points"
    contents/ui/NetLayer.qml    template for "ask a local helper, draw arcs"
    contents/ui/BorderLayer.qml vector outlines; the helper turns GeoJSON into polylines
    contents/ui/config.qml      the settings page
    contents/ui/HaloText.qml    text with a scalable dark halo, for labels that sit on the map
    contents/ui/MapLabel.qml    one label: text over an optional plate (all labels share this look)
    contents/ui/LabelPass.qml   draws every event label last, above all layers; Geo.placeLabels lays them out
    contents/ui/StormLayer.qml  tropical cyclones with track and cone; StormGlyph.qml draws the NHC-style symbol
    contents/ui/VolcanoLayer.qml weekly report + USGS alert levels
    contents/ui/FireLayer.qml   GDACS wildfire events + NASA FIRMS hotspots; FireGlyph.qml draws the flame
    contents/ui/CitySearch.qml  offline home-city lookup for the settings page
    contents/ui/SatLayer.qml    ISS, Hubble, Tiangong along a helper-computed ground track
    contents/ui/LaunchLayer.qml upcoming launches on their pads; LaunchGlyph.qml draws the rocket
    contents/ui/PowerWatch.qml  asks the helper every 20 s: battery, CPU/GPU load (load guard), widget mode file
    contents/ui/CloudWatch.qml  fallback clouds: has the helper stitch five geostationary satellites into one image
    contents/ui/StatusPanel.qml the Status section (own file, so a fault there cannot break the page)
    contents/config/main.xml    one <entry> per setting
    contents/helper/            python: sockets -> places, and the downloaders
    contents/images/            spacecraft and launch-pad pictures, and storm/ icons, used as markers (owner's artwork)

Adding a layer = a new `FooLayer.qml`, an `<entry name="ShowFoo">` in main.xml,
a `cfg_ShowFoo` alias + CheckBox in config.qml, and a `Loader` in main.qml.
Layers are only instantiated while ticked, so disabled ones cost nothing.

The day/night blend avoids a custom shader on purpose (Qt 6 shaders must be
precompiled with `qsb`). The shade is a 360x180 Canvas painted with one gradient
per column and stretched over the map. The city lights are a second, larger
Canvas: it paints the same night mask, then draws `lights.png` with the
"source-in" operator so the lights survive only where it is night. The shade
repaints every two minutes, the lights every ten.

One QML trap worth knowing when you add overlays: never call an id `layer`.
Every Item already has a `layer` property (the one behind `layer.enabled`), and
inside a Repeater delegate that property wins over your id. 0.1 did exactly that.

## If something does not show up

    journalctl --user -f | grep -i -E "livemap|qml"     # QML errors as they happen
    journalctl --user -b -o cat | grep -i livemap | sort | uniq -c   # everything since login, de-duplicated
    livemap-helper net --table                           # what the network layer sees
    livemap-helper status | python3 -m json.tool         # the same health report the settings page shows

- Blank map: the base image path is wrong, or `fetch-maps` has not been run.
- Network layer missing entirely: the `org.kde.plasma.plasma5support` QML module
  is not installed (package `plasma5support`). Only that layer depends on it.
- Arcs end in odd places: CDNs and anycast addresses (Cloudflare, Google, ...)
  geolocate to wherever the block is registered, often not the server you hit.
  The free DB-IP database is also only city-accurate at best.
- Process names only appear for your own processes (`ss -p` without root).
- `ping`, traceroute and mtr never show up: ICMP has no socket with a remote address
  that an unprivileged program could list. Only TCP and (connected) UDP are visible.
- A foreign website often is not foreign: `livemap-helper where example.co.za`
  shows where its servers (usually a CDN edge near you) really are.

## Changes

See [CHANGELOG.md](CHANGELOG.md). Every release adds an entry there (Added / Changed / Fixed).

## Licence

Live World Map is free software: GNU General Public License v3.0 or later (see `LICENSE`). The storm icon
set and the satellite and launch pictures in `contents/images` are by tidybitz and released under
CC BY 4.0. Copyright (C) 2026 tidybitz - https://github.com/tidybitz/livemap

## Credits

NASA Earth Observatory (Blue Marble Next Generation, Black Marble 2016) ·
Made with Natural Earth (naturalearthdata.com) ·
Global Disaster Alert and Coordination System, GDACS (storms, wildfires) · NOAA National Hurricane Center (storms, secondary) ·
Smithsonian Institution Global Volcanism Program (Volcanoes of the World database, Weekly Volcanic Activity Report with USGS) ·
USGS Volcano Hazards Program alert levels (HANS public API) ·
NASA FIRMS active fire data (MODIS, LANCE / EOSDIS) ·
Orbital elements by CelesTrak · launch data by The Space Devs (Launch Library 2) ·
USGS Earthquake Hazards Program · clouds by Matt Eason's live-cloud-maps
(EUMETSAT data), or stitched from NOAA GOES / JMA Himawari imagery via NASA GIBS and EUMETSAT Meteosat
imagery via EUMETView · IP Geolocation by DB-IP (https://db-ip.com, CC BY 4.0).
