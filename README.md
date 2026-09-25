# Live World Map

A live situational-awareness wallpaper for KDE Plasma 6, with a companion panel widget.

One equirectangular world map, and on it - each layer its own tick box - the day/night line and city
lights, live clouds, earthquakes, volcanoes with their alert history, tropical storms with their track
coloured by intensity, wildfires, the ISS, Hubble and Tiangong gliding along their orbits, the next rocket
launches counting down on their pads, time zones, borders, and (optionally, never leaving your machine)
where your own computer is connected to right now.

It is built to sit on a desktop for weeks: every feed keeps its last good data and only says something when
it has been stale for hours, the clouds fall back to imagery stitched locally from five geostationary
satellites when the usual source is down, and a load guard pauses the animation - or hides the live
layers entirely - when the CPU or GPU is busy with something else, so a game or a build never fights the
wallpaper for frames.

<!-- screenshots/overview.png, screenshots/storms.png, screenshots/widget.png -->

## Install

Requirements: KDE Plasma 6 on Linux, Python 3.9 or newer, and the QML modules Plasma normally ships with.
`livemap.sh doctor` checks every one of them and prints the exact packages to install for Fedora, Arch,
openSUSE and Debian/Ubuntu/KDE neon; `install` refuses to continue while a required one is missing.

Download `livemap.zip` from the latest release, then:

    bash livemap.sh doctor                          # what is missing, if anything
    bash livemap.sh install ~/Downloads/livemap.zip
    bash livemap.sh activate                        # make it the wallpaper on every desktop

Then right-click the desktop > *Configure Desktop and Wallpaper* > **Status** > *Download maps and border
data* (about 350 MB from NASA and Natural Earth, once). Until then the map shows the single image you pick
in the settings. The widget is under *Add Widgets* as **Live World Map Events**.

Everything is per user and nothing runs in the background: the wallpaper is QML inside plasmashell, and the
helper is a Python script (standard library only) that runs for a few seconds per fetch.

Optional extras, each for a feature that is off by default: `python3-maxminddb` for the Network layer,
QtWebEngine for the embedded ISS and launch streams in the widget, Pillow for faster cloud stitching.

## The script

    livemap.sh doctor [--report]         check every dependency; --report adds versions, GPU, logs for a bug report
    livemap.sh install [livemap.zip]     check, then install or update the wallpaper and the widget
    livemap.sh activate | deactivate     switch every desktop to the map / back to the stock image
    livemap.sh remove                    deactivate, remove the widget from panels, uninstall both packages
    livemap.sh purge [--yes]             remove, then delete the data folder and the saved settings
    livemap.sh status                    what is installed, active, running and stored
    livemap.sh help [command]

## Layers and sources

| Layer | Source | Refresh |
|---|---|---|
| Base map, seasons, city lights | NASA Blue Marble Next Generation, Black Marble (downloaded once) | monthly blend, computed locally |
| Day / night, twilight | computed locally from the sun's position | every 2 min |
| Clouds | Matt Eason's live-cloud-maps (EUMETSAT); fallback stitched from GOES-East/West, Himawari (NASA GIBS) and Meteosat (EUMETView) | every 3 h |
| Borders, coasts, names, time zones | Natural Earth (downloaded once) | - |
| Earthquakes | USGS Earthquake Hazards Program | every 5 min |
| Volcanoes | Smithsonian Global Volcanism Program (eruption database, weekly report), USGS alert levels (HANS) | hourly |
| Storms | GDACS worldwide; NOAA NHC for current intensity, best track and forecast in the Atlantic and Pacific | every 30 min |
| Wildfires | GDACS events, NASA FIRMS hotspots (MODIS) | hourly |
| ISS, Hubble, Tiangong | CelesTrak orbital elements, propagated locally (Kepler + J2) | position every second |
| Launches | The Space Devs, Launch Library 2 | hourly |
| Network (off by default) | this machine's sockets, DB-IP Lite geolocation, all local | every 10 s |

Every source is fetched over HTTPS only, capped in size, parsed as data and never executed; strings that end
up on the desktop are filtered and rendered as plain text. The data folder is `~/.local/share/livemap`.

## Companion widget

**Live World Map Events** lists the newest events with links to their sources (sorted by time, severity, kind
or "what is next"; NEW / SOON / LIVE tags), embeds or opens the ISS and launch webcasts, controls the map
(pause, plain map, hide layers, clouds on/off and opacity) and shows the status of every data source. It
uses the wallpaper's helper and caches; nothing is fetched twice.

## Repository layout

    livemap/            the wallpaper package (Plasma/Wallpaper)
      contents/ui/        QML: main.qml and one file per layer; geo.js for the maths
      contents/helper/    livemap-helper.py: every fetch, cache and calculation the QML cannot do
      contents/config/    main.xml, one <entry> per setting
      contents/images/    spacecraft, launch-pad and storm icons (CC BY 4.0)
    livemap-widget/     the companion widget package (Plasma/Applet)
    livemap.sh          install / doctor / activate / remove / purge / status
    scripts/check.py    static checks (settings ↔ config page, brackets, ids, versions); CI runs it
    scripts/package.sh  builds livemap.zip
    CHANGELOG.md        every release, newest first

Adding a layer: a new `FooLayer.qml`, an `<entry name="ShowFoo">` in main.xml, a `cfg_ShowFoo` alias and a
tick box in config.qml, and a `Loader` in main.qml. Layers exist only while ticked. `livemap/README.md`
has the developer notes (how the day/night shade avoids a shader, the `layer` id trap, and so on).

## If something does not show up

    bash livemap.sh doctor --report                       # dependencies, versions, the helper's status, last log lines
    journalctl --user -f | grep -i -E "livemap|qml"      # QML errors as they happen
    livemap-helper status | python3 -m json.tool          # the health report the settings page shows

Please open an issue with the output of `livemap.sh doctor --report`.

## Licence

GNU General Public License v3.0 or later - see [LICENSE](LICENSE). The storm icon set and the spacecraft
and launch-pad pictures are by tidybitz, CC BY 4.0. Copyright (C) 2026 tidybitz.

## Credits

NASA Earth Observatory (Blue Marble Next Generation, Black Marble 2016) · Made with Natural Earth ·
USGS Earthquake Hazards Program · Smithsonian Institution Global Volcanism Program · USGS Volcano Hazards
Program (HANS) · Global Disaster Alert and Coordination System (GDACS) · NOAA National Hurricane Center ·
NASA FIRMS (MODIS, LANCE/EOSDIS) · CelesTrak · The Space Devs (Launch Library 2) · Matt Eason's
live-cloud-maps (EUMETSAT data) · NASA GIBS (GOES, Himawari) · EUMETSAT EUMETView (Meteosat) ·
IP Geolocation by DB-IP (https://db-ip.com, CC BY 4.0) · issinfo.net (who is in space).
