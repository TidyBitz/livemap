# Live World Map Events (companion widget)

A Plasma 6 widget for the Live World Map wallpaper. It needs the wallpaper installed: it runs the
wallpaper's own helper script and reads the caches the wallpaper keeps, so nothing is fetched twice.

Install: `livemap.sh install` installs it together with the wallpaper. By hand:

    kpackagetool6 -t Plasma/Applet -i livemap-widget      # first time
    kpackagetool6 -t Plasma/Applet -u livemap-widget      # updates

Then "Add Widgets..." -> "Live World Map Events". In a panel it is an icon with an unread badge; on the
desktop or in its popup it shows two tabs:

- Events: newest first across earthquakes, storms, volcanoes, wildfires, launches and the three satellites;
  a click opens the source (USGS event page, GDACS report, Smithsonian volcano page, Launch Library, N2YO).
- Live: the ISS live stream (any YouTube URL in the settings). Embedded playback is optional (it needs the
  QtWebEngine QML module and costs a browser engine's worth of memory while the popup is open); "Open in
  player" runs mpv (with yt-dlp) in a small always-on-top window, "Open in browser" always works.
- Map controls: pause animations, plain map only, hide layers, clear. These are written to
  ~/.local/share/livemap/mode.json and the wallpaper picks them up within 20 seconds; they sit on top of the
  wallpaper's own settings until cleared.

Widget settings: which kinds to list, the earthquake feed, refresh interval.

## Licence

GNU General Public License v3.0 or later (see `LICENSE`). Copyright (C) 2026 tidybitz -
https://github.com/tidybitz/livemap
