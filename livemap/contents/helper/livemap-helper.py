#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 tidybitz
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
`net` never touches the network: it reads `ss` and an offline database.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from livemap_helper.cli import main  # noqa: E402

if __name__ == "__main__":
    main()
