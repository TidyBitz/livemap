# Changelog

All notable changes to Live World Map. Newest first. Versions before 0.16 were reconstructed from the
release notes written at the time; their dates are the day the version was handed over.

## 0.47 - unreleased

### Added
- Floods, from the same GDACS list as the storms and wildfires: one event per river basin or region, rated
  green / orange / red on the people exposed, drawn as a wave mark in the alert colour with the affected
  districts as a faint fill underneath and a label saying what happened to people (GDACS's Sendai figures:
  dead, evacuated, displaced, rescued) and how long the flood has run. Orange and red only by default -
  GDACS always lists a dozen green basins at seasonal high water - with "All levels" and "Red only" as the
  other choices; the Events widget follows the same filter and keeps a Floods header when there are none. Green
  floods keep the flood colour; orange and red take GDACS's. The usual colour, label, pulse and layer
  opacity controls; `floods --table` from a terminal.
- Styles. A style is a snapshot of the wallpaper's settings. The six built-in ones are each base map with
  its recommended colours (Seasonal, Satellite today, Relief, Dark cartographic, Dark Matter, Matrix):
  picking one sets the base and every colour and leaves your sizes, line widths, opacities and label styles
  alone. Yours are saved from the page as it is ("Save as", sizes and widths included) and kept as JSON in
  `~/.local/share/livemap/styles/`, where they can be exported, imported and shared. Nothing is lost by
  trying styles: before every apply the settings are saved as a dated snapshot (the last 20, listed at the
  bottom of the Style list, "More" has the way back), and the settings as they were the first time the
  page opened with styles are kept as "Original" for good. Changing anything a style set marks it
  "modified", with Save and Reset beside it. Every setting sits in one of four buckets - map base,
  colours/lines/labels, layers, machine - and the "A style covers" boxes say which an apply touches and a
  save captures: layers are left out unless ticked, and the machine bucket (home place, units, frame,
  profile, data folder) is never part of one. Replaces the one-way "Set every line and label to..."
  button; the Map section's combo is now the base map of the current style. Helper: `styles
  keys|list|read|save|delete|export|import`.
- Two more map styles, both drawn like the dark cartographic one (no imagery, the border download, the
  lightest on the GPU): "Dark Matter" - land in dark grey over a near-black ocean, the flat dark basemap
  look - and "Matrix" - black ocean, land in the darkest green, a faint graticule every 10 degrees, every
  label in a monospace face with a green glow, and scanlines over the whole screen. Set the line and label
  colours to greys or greens to complete either (the built-in style of the same name does it), or keep your own. On
  the flat styles the night shade is not drawn over the land (it made the land two tones): the city lights
  alone say where it is night.
- Wildfire focus (under Wildfires, on by default as "Near people"): most of what the satellites see burning is
  the savanna, harvest and forestry fires of the season, so the map looked on fire everywhere. "Near people"
  keeps the fires that can mean evacuations - GDACS orange and red events (rated on the people exposed) and
  satellite hotspot clusters within 50 km of a city of 100 000 or on such an event; "Orange and red events
  only" drops the hotspots altogether; "Everything the filters below allow" is the old behaviour. The
  Events widget follows the same choice (`power --fire-focus`, `hotspots --people`).
- The settings page says when the companion widget is overriding the map - hiding layers, pausing, plain
  map - with a button to clear the overrides, since a layer switched on in the settings stayed off the map
  while the widget hid it and nothing said why.

### Fixed
- The band is a scale of the standard zones, every hour from UTC-12 to UTC+14 plus the half-hour zones
  a country uses (India, Iran, Afghanistan, Myanmar, central Australia - not Lord Howe or Chatham), each
  on its own meridian the way a printed time zone map is laid out; a zone observing summer time shows
  its clock an hour on and says "DST". Keyed by the polygons it drifted: a zone whose main place was on
  summer time landed in the wrong column, UTC-6 went missing, and two columns shared a clock.
  "Abbreviations" adds CST / CET / JST to the captions, CDT / BST / CEST in summer.
- Time zone captions are the offset in force now, summer time included, like the clock beside them:
  Chicago reads "UTC-5 · 8:41 pm" today and "UTC-6" in winter. The standard offset as a caption next to a
  summer-time clock made neighbours look like duplicates and marked the wrong column as home.
- Time zone labels in one row: a region that did not reach the row's latitude (Europe with the row at the
  equator) showed none; the row moves to the bottom of what is on screen in that case. UTC+2 and UTC+11
  were missing from the row where the zone has no land at that latitude: a whole-hour zone without one
  takes its nominal meridian band, so the row is a complete scale.

### Changed
- "Time zone style" is one dropdown: Classic (labels inside each zone), One row, D3 (the band), D1 (tinted
  zones), D1 + D3. The tint: each zone filled with a colour cycle, like a time zone map, at a chosen opacity (12 %
  by default), under the lines - the extent of a zone reads from the colour where the boundaries get busy,
  so the outlines can be faint and the labels large and translucent. Drawn once by the helper from the
  time zone data (`livemap-helper zone-tint`, python3-pillow).
- The band's extras (each its own box): day and night along the band - warm where the sun is up, cool
  where it is night at the band's latitude, graded through twilight - with cursors where it is noon and
  midnight right now, all sliding along through the day; the hours from this computer's zone under each
  clock ("+6 h", "you"). All computed locally.
- D3, the band: a translucent strip across the map with a tick at each zone edge, and in
  it the time large, the offset small above it, and the date only where it is not this computer's date (the
  one time it is news), with its own opacity and this computer's zone marked in amber. "In one row" stays
  as it was.
- City lights in a region are cut from NASA's 13 500 px night picture for exactly the view on screen (the
  whole-world lights, 4 096 px, were stretched eight times across Europe and came out as blobs). The
  picture is kept by `fetch-maps` from now on (night-hires.jpg); an install from before shows a note on the
  City lights status row until the maps are downloaded again.

## 0.46 - 2026-10-09

### Added
- Map styles. "Map style" under Map: the seasonal Blue Marble as before; today's satellite view - the real
  picture from the last day's orbits (NASA GIBS, Suomi NPP VIIRS corrected reflectance: clouds, snow, smoke
  and sea ice as they were yesterday, seams and polar night included), fetched once a day; Blue Marble with
  shaded relief and bathymetry (GIBS, fetched once); and dark cartographic - no imagery, the land from the
  border download drawn in a land colour over an ocean colour (Map colours) by the helper, as an image for
  the frame on screen like the other styles (as vector shapes it had locked the desktop for seconds on
  every change), the best contrast for the data. "Map tone" desaturates or tints any imagery style: muted, monochrome,
  blue-tinted, sepia. The GIBS styles need python3-pillow; the wallpaper builds the imagery itself
  (`livemap-helper fetch-frame`) and says so in the corner while it does; Status row "Map style imagery".
- Regions. The frame (Map > Show) can be any part of the world at least 10° by 5°, with presets for the
  Americas, North America, the United States, Central America and the Caribbean, South America, Europe,
  Europe-Middle East-Africa, the Middle East, Africa, Asia, South Asia, East Asia, South-east Asia and
  Oceania, Australia and New Zealand. A region fills the screen at up to about 8x (Europe), with imagery
  cut from the monthly maps for exactly that frame - the 5 400 px set is soft beyond about 2x, so the Map
  section offers the 21 600 px set as a second source line, "Hi-res seasonal maps" (about 330 MB, kept
  beside the small set; once it is there every view is cut from it, the whole world included, unless
  "Cut every view from the hi-res maps" under Base map is unticked; `fetch-maps --hires`) - or fetched from
  GIBS for the other styles - built for what is on screen, edge to edge, not for the frame, so Fit mode's
  spare space is as sharp as the region and nothing is cut off (the monthly map shows softly only while
  the picture is on its way).
  Marks and labels keep their screen size whatever the zoom (they used to grow with it), and the still
  layer's texture is the screen's part of the map, which is what lifted the old 2x limit. A frame cannot
  cross the date line yet.
- Oil and gas infrastructure: fixed offshore platforms (every structure on the US Gulf of Mexico shelf from
  BSEE, public domain; elsewhere from OpenStreetMap) and refineries (OpenStreetMap), as still marks - a
  square, a triangle on a base - with names through the label pass, own colour, size and label style. Off by
  default; its own section and switch; "Download" on its source line (a minute or two, Overpass is slow).
  Fixed structures only: mobile rigs are in no free feed. `livemap-helper fetch-infrastructure`, `infrastructure`;
  Status row "Oil and gas infrastructure (BSEE, OpenStreetMap)".
- Storms and infrastructure: for every active storm the helper finds the platforms and refineries inside its
  forecast cone (or, for a storm without a cone, within 120 km of its position and forecast track). The
  storm's label says "· 14 platforms, 2 refineries in the cone · crossed 3 facilities", the widget's row too;
  a threatened facility is drawn larger with a ring, and faintly ringed once the storm has passed it. The
  split is what the storm has already crossed (within 100 km of its past track or its position now) and
  what lies in its path; the widget lists both under the storm's row, facility by facility - refineries by
  name, platforms by name where they have one, the rest counted - and keeps the list on a storm that has
  gone. "Infrastructure shown" chooses between only what a storm threatens (the default: with no storm near
  any facility nothing is drawn) and everything always; "Infrastructure threatened: Named on the map with
  their storm" (off by default) prints "Pascagoula Refinery · Isaias" beside the mark. `storms --table`
  prints THREATENS lines. The Status row counts the platforms by region (Gulf of Mexico, North Sea,
  Mediterranean, West Africa, Persian Gulf, Asia-Pacific) so an incomplete download is plain to see.
- A source that downloaded fine shows a small refresh button on its Source line to download it again (the
  infrastructure file is worth refreshing monthly); an incomplete download is a yellow row with the Download
  button, not a green one.
- Under Countries: state and province names (Natural Earth's admin-1 label points, 4 600 regions, with a
  density choice) and places - country capitals (a ringed dot), state and province capitals (a dot) and
  cities over 500 000 / 1 / 5 / 10 million people (a small dot, or one sized by population). Each of the four
  has its own colour, size, text colour or style row, and the places choose dot and name / dot only / name
  only. Country names are placed first, then capitals and cities by size, then state names, then time zone
  labels, so nothing prints over anything more important. Two more files in the border download (about
  6 MB); existing installs show a Download button on the Countries source line.
- Rivers: a new section under Geographic layers - Natural Earth's major rivers and lake centrelines at the
  Countries detail level, own colour, opacity and thickness, under the coastlines.
- Time zone labels can carry the clock: "Time zone labels" chooses UTC offset / offset and local time /
  offset, time and date / local time / time and date (the date on a second line), 24- or 12-hour. The time is
  the real one of each zone's main place, summer time included: the helper takes the place Natural Earth
  names for the zone (`tz_name1st`) and asks the system's tz database for its offset now and the next
  change, so the labels flip on the night of the change without any download. Updated every minute.
- Every row on the settings page says what it changes: "Border line colour", "Tectonic line thickness",
  "Earthquake ring size", "Storm label style", "Time zone label placement" and so on, the same pattern in
  every section, instead of "Colour", "Labels" and "Line thickness" meaning something different each time.
- "Full speed" override from the companion widget: the wallpaper ignores its on-battery policy and the load
  guard while it is set, so the map can be brought back on demand - for a talk, a stream, or just to look -
  without touching the settings. Either until switched off or for 1 / 4 / 8 hours; a timed one is dropped by
  the helper when its time is up, so a laptop cannot be left at full speed by accident. The widget's own
  Pause and Plain map still apply on top. The corner notice says "Full speed from the widget" while it is
  overriding something. `livemap-helper mode --full on|off [--full-hours N]`; `full` and `full_until` in
  mode.json.
- Fault lines: the tectonic plate boundaries (Peter Bird's PB2002 model, GeoJSON by Hugo Ahlenius / Nordpil,
  ODC-By) as still vector lines under the borders, with their own colour, opacity and thickness - under
  Earthquakes in the settings, where they explain the ring clusters. Off by default. The file (about 0.2 MB)
  comes down with "Download border data"; Status row "Plate boundaries (PB2002)"; `livemap-helper plates`.
- The helper keeps a record of every event the widget's feed has shown (`history.json`, 90 days, written as a
  side effect of `feed`, nothing extra is fetched); `feed --since T --until T` answers from it. The widget's
  "past events" view reads this, so it fills from the moment this version first runs.

### Fixed
- Switching Countries off left the capitals, cities and state names on the map (they are rows of that
  section, so its switch is theirs); the Rivers or Time zones switch kept the layer alive and they drew on.
- Time zone labels in one row went missing wherever the row ran through a country name or a city (UTC to
  UTC+3 across Africa at the equator): they were fitted last and lost. The row is placed first now, and the
  names and places make way for it; a zone too narrow for its label at that latitude still gets one unless a
  neighbour's label is in the way. "Time zone label text" row: a plate, the text following the line colour
  or its own colour; the label opacity is the style row's alone, no longer tied to the line opacity.
- `livemap.sh` looked frozen on the network check: a stalled DNS lookup or proxy could hold "reaching
  earthquake.usgs.gov" for minutes with nothing on screen. It now says what it is doing, and gives up after
  8 seconds with a warning.
- The widget ignored the wallpaper's units: a storm read "194 km/h" with the map set to mph, a fire "5 032 ha"
  with the map in acres. The wallpaper hands its Units and Storm wind choices to the helper with the layers
  (`power --units`), and the feed's titles follow them.
- The widget's live list lost the storms: the feed kept the 60 newest items, and a storm first seen three
  days ago fell off the end behind a day of quakes and fire clusters, although it was still on the map.
  Storms, volcanoes, launches and satellites now always stay; the cap falls on quakes and fires only.
- Oil and gas infrastructure drawn from the first download for ever: the layer only re-read the file while
  it had nothing, so a second Download (the one that brought the North Sea and the Mediterranean) changed
  the Status line and not the map until plasmashell restarted. It looks again every five minutes (every
  minute while empty) and redraws when the file's own timestamp has changed.
- Launches: a site with several launches queued (Vandenberg, the Cape) showed only the earliest with nothing
  to say the others existed; the label now ends "· +2 more here", and pads are grouped by site so the Cape's
  neighbouring pads do not print over each other.
- The Countries "Line thickness" slider also set the time zone lines (they had no thickness of their own);
  time zones have "Time zone line thickness" now.
- The border download gains Natural Earth's 1:50m country polygons (the dark cartographic style's land at
  the Countries detail level); existing installs show a Download button on the Countries source line.
- `livemap.sh install` on a desktop still using the pre-0.44 package ids (`org.livemap.*`) installed the new
  packages beside them and said nothing, so the map kept running the old code whatever was installed. It
  now migrates: desktops are switched to the new wallpaper id, each old widget on a panel or desktop is
  replaced by the new one in the same place, and the old packages are removed. `status` warns when the old
  ids are still in use. Settings start from the defaults under the new id (Plasma keys them by package id);
  the data folder is shared.

### Changed
- Earthquake rings are half the size they were: an M6 is about 16 px across on a 1920-wide screen (it was
  28), an M4 about 7, and the ripple runs out to twice the ring instead of two and a half times. The
  "Earthquake ring size" percentage still scales from there, and now goes down to 10 % (it stopped at 40).
- Storm labels put the facilities on a second line ("Isaias · Hurricane cat 3 · 120 mph" over "5 refineries
  in the cone · crossed 13 facilities"), and launch labels put the mission on one ("Falcon 9 Block 5 ·
  T−13 h 06 min · +2 more here" over "SDA Tranche 1 Transport Layer A"): one line had grown too long to read.
  Both are settings: "Storm label facilities" (what it threatens, and whether on a line of its own) and
  "Launch label mission: on a line of its own". Storm labels have a fourth choice, "Name and wind", for
  when the icon already says the class; storm labels follow the style row's Bold instead of always being
  bold; every label size goes down to 4 px (it stopped at 6).
- Every event layer has a "layer opacity" row - Earthquake, Volcano, Storm, Wildfire, Satellite, Launch,
  Network and Infrastructure - for the marks, tracks and rings as a whole (10-100 %); the labels keep their
  own text opacity. A storm track and icon at 50 % sits back behind the rest.
- Gulf of Mexico platforms are named the way the Gulf names them, "MC 807 A" (area, block, structure),
  instead of the bare structure letter or number BSEE's file carries ("A", "1"); download the
  infrastructure again to pick the names up.
- The wallpaper tells the helper which event layers it shows (`power --layers`, `layers.json`) so the
  widget can list only those.
- The settings page folds: every section is one line - a switch (its Show box), the name, and a sentence
  saying what it is set to ("Magnitude 4.5+, past day · rings 100 % · labels: magnitude, place and age · pulse:
  newly reported or significant · tectonic plates") with a dot for the state of its sources - and opens to
  the full controls with the chevron or a click on the line. "Expand all" / "Collapse all" at the top. The
  page starts folded, so the whole map is one screen of lines. Clouds and Tectonic plates are sections of
  their own (they were rows under Day and night and Earthquakes), so each has its own switch and the plates
  no longer look like part of the earthquake layer.
- Label style is the same for every label type: one "Label style" row - Bold, Capitals, letter spacing (with
  capitals), text opacity and the dark outline drawn when there is no plate - under Earthquakes, Volcanoes,
  Storms, Wildfires, Satellites, Launches, Network activity and Time zones, exactly the five choices country
  names had. The country-name controls are the same row now. Defaults keep every label as it was.

## widget 0.44 - 2026-10-09

### Added
- Map controls: a "Power" section with a Full speed switch and a duration choice (until switched off, 1, 4
  or 8 hours), with the time left while it runs.
- A storm's row lists the oil and gas facilities it has crossed ("✓ Crossed · 2 facilities") and those in its
  path ("→ In its path · 5 facilities"), each refinery and named platform on its own line, unnamed platforms
  counted; the list stays on the storm once it has gone, so the record says what it hit.
- Past events: a range chooser next to the sort order - on the map now, past 24 hours, 7 days, 30 days, or
  two dates - lists what has already left the map (quakes that aged out, storms that dissipated, launches
  that flew) with the date and time of each, from the helper's own 90-day record.

- Wildfires and satellites have an icon of their own in the list - a flame, a satellite - drawn in the
  theme's text colour (small SVGs in the widget package) instead of the ♦ and ◆ glyphs, which did not
  read as anything.
- Events in groups: one block per kind - launches, storms, volcanoes, earthquakes, wildfires, satellites -
  with a header that says how many and the one fact that matters ("next in 12 h", "strongest M7.7",
  "3 active"); a click folds a group away, a button at the top folds or opens them all. A kind the wallpaper
  has switched off keeps its header ("off on the map · 6 hidden") instead of vanishing, so the list says why
  it is empty. The sort order applies inside each group. A storm's facilities are two chips - "✓ crossed 23 ·
  MC 807 A, Thunder Horse, +21" and "→ ahead 5 · …" - and a click on a chip unfolds the full list under
  the storm, facility by facility, another folds it away. The sort choice lost "By kind" (the groups are
  that); next to it a choice between "On the map" (only the kinds the wallpaper has switched on) and
  "Every kind". "Events listed: in groups by kind" switches the flat list back on.
- Notification sound: off, a bubble pop, a chime, a zing, or a sound file of your own, played when a severe
  event arrives (a magnitude 6+ quake, a category 3+ storm, a red alert - the red rows) or a launch is within
  its last minutes (15 by default). One sound per refresh however many arrive together; nothing for what was
  already on the list when the widget started. Played with pw-play, paplay or aplay, whichever is there;
  "Play" on the settings page tries it.
- "Events listed: only the kinds the wallpaper shows" (on by default): a kind switched off in the wallpaper's
  settings - wildfires, say - is left out of the list, so the widget matches the map. The widget's own Show
  boxes still apply on top; with it off the list shows every kind as before.

### Changed
- Status tab: the list of sources is there at once (grey dot, "checking…" on each row) instead of an empty tab
  while every source is contacted, and a re-check keeps the last answers on screen, dimmed, until the new
  ones arrive. `livemap-helper status --names` lists the rows without running anything.

## 0.45 - 2026-09-24

### Added
- Feed items can carry extra links; the ISS and Tiangong entries link to "Who is in space right now"
  (issinfo.net) next to their tracking page.

## widget 0.43 - 2026-09-24

### Added
- Extra links show as small icon buttons on an event row (hover for the label), and the Live tab has a
  "Who is aboard" button.

## 0.44 - 2026-09-23

### Changed
- Wildfire hotspots are rated instead of counted. The helper gives every half-degree cell a tier - needs
  attention, notable, background - from what makes a fire matter: sitting on a GDACS orange or red event,
  being near a city, burning for days in isolation, being very large, or a usually quiet cell flaring far
  above its own month. A burning season (a carpet of burning cells: savanna, harvest) is recognised on the
  first day by its neighbourhood and stays notable at most, so it no longer covers the map in "N detections"
  labels; with a fortnight of history a cell that burns most days counts the same way. "Hotspots" under
  Wildfires chooses Needs attention only (default) / Notable and up / Everything; attention cells get the
  flame, the pulse and a label that says why ("29 km from Sydney · 3 d · 1.3 GW"); notable ones are dots.
  The widget lists attention clusters as events. `hotspots --min-tier`, `--table` shows the rating.
- Package ids are now `io.github.tidybitz.livemap.wallpaper` and `io.github.tidybitz.livemap.events`
  (reverse-DNS of the project's home, as Plasma packages are expected to be). This is a new package as far as
  Plasma is concerned: run `livemap.sh purge` (or `remove` to keep the data folder) before installing 0.44,
  then `install` and `activate`; the settings start from the defaults. `livemap.sh` removes and purges the
  old `org.livemap.*` packages and their settings as well as the new ones. The data folder
  (`~/.local/share/livemap`) and the log prefix are unchanged.

## widget 0.42 - 2026-09-23

### Changed
- New package id (see above); the widget looks for the helper under the wallpaper's new id.

## 0.43 - 2026-09-23

### Changed
- Licence: GNU GPL v3.0 or later, with the full text in `LICENSE` and SPDX headers on the main files;
  the icon set and pictures under CC BY 4.0. Author and project website (github.com/tidybitz/livemap) in the
  package metadata. The old `install.sh` is gone; `livemap.sh` is the one way in.
- `livemap.sh doctor`: checks Plasma 6, kpackagetool6, unzip, Python 3.9+, a D-Bus tool, and every QML
  module the wallpaper and widget import (by their qmldir in Qt's import paths), then the optional extras
  (maxminddb, QtWebEngine, Pillow, numpy) with what each one is for, free disk space and whether USGS is
  reachable. Missing required items come with one install command for Fedora, Arch, openSUSE or
  Debian/Ubuntu/neon. `doctor --report` adds versions, GPU, screens, the helper's status and the last log
  lines for a bug report.
- `livemap.sh install` runs the doctor first and refuses to install while a required dependency is missing
  (`--force` overrides). `purge` asks before deleting (`--yes` skips), `status` says whether the map is
  active, `help <command>` explains each command, and `qdbus-qt6` is accepted alongside `qdbus6`/`gdbus`.

## widget 0.41 - 2026-09-23

### Changed
- Licence and metadata as above (GPL-3.0-or-later, author, website).

## 0.42 - 2026-09-23

### Fixed
- A storm that was renamed when it strengthened (GDACS and NHC call a depression "Twenty-E" or "Nine" and
  then "Rachel" or "Isaias") no longer splits into an old name that ages out as "no longer tracked" and a
  new one that starts from scratch: the two feeds' event ids travel with the storm, a storm is matched by
  id (or, when the feeds rename at different moments, by position within 250 km), the memory - first seen,
  breadcrumbs - moves to the new name, and the NHC name wins. The widget says "was Twenty-E" for a while.
- Time zone labels were placed at the centre of each zone's bounding box, so a ragged zone got its "UTC-7"
  somewhere odd, sometimes outside the zone, and nothing kept it off a country name. Each label now sits in
  its zone area on the widest stretch of the area's middle, and the country names are laid out first and
  the zone labels around them. New under Time zones: "Placed: In one row, at latitude" puts every offset on
  one line of latitude the way printed time-zone maps do (55° S runs through open ocean for all 25 zones).
- Satellite labels jumped every 20 seconds while the picture glided: the label is still laid out against the
  20-second position (a full label relayout is the expensive part), but between relayouts it now slides with
  the marker, recomputed once a second from a handful of numbers. Leader lines follow too.

## 0.41 - 2026-09-23

### Fixed
- Satellites and their ground tracks were drawn under launches, wildfires, earthquakes and the network layer,
  so a passing station could slip behind a quake ring. The satellite layer now sits above every ground-level
  layer; labels still sit above everything.

## 0.40 - 2026-09-23

### Added
- The companion widget can switch the cloud layer off and set its opacity on top of the wallpaper's settings
  (`mode --clouds on|off|auto`, `--cloud-opacity 0-100|auto`); the wallpaper picks the change up within
  20 seconds like the other overrides, and "Clear all overrides" drops it.

## widget 0.40 - 2026-09-23

### Added
- Map controls: a "Clouds" section with a show/hide box and an opacity slider (with an undo button back to
  the wallpaper's own value).
- A Status tab: every data source and local file as the wallpaper's own Status section checks them - green
  working, yellow something to download or a slow/stale source, red not working - with when it was last
  checked and a refresh button. It checks when first opened and again after five minutes.

## 0.39 - 2026-09-23

### Added
- Storm tracks in intensity colours, the way storm-tracking sites draw them: each piece of the track takes the
  colour of the wind the storm had reached at that fix - not tropical purple, depression blue, tropical storm
  green, category 1-5 yellow, orange, red, pink, magenta - with a dot at every fix and a ring where the storm
  was first fixed, labelled "<name> · first fix 3 d ago" when that point is far enough from the storm.
  Forecast points and the forecast line use the forecast wind the same way.
- Where it comes from: NHC's best track (the public ATCF b-deck, one fix every 6 hours with wind and storm
  type) for the Atlantic and eastern/central Pacific, and the forecast intensity read from NHC's forecast KML.
  For storms only GDACS knows (western Pacific, Indian Ocean, southern hemisphere) the wallpaper now keeps
  its own breadcrumbs - every position it has seen since it first met the storm - so those tracks grow while
  it runs. GDACS-only winds are peak values, so those pieces stay in the storm's own colour.
- Two settings under Storms: "Track and forecast in the intensity at each fix" and "Mark where the storm was
  first fixed". The marker and label colours moved to the same 8-step scale (they were 4 steps).

### Changed
- Tracks with intensity are drawn as short pieces instead of one line, so they cost a few dozen tiny items per
  storm and nothing while idle; the old single-colour line remains for storms without fixes.

## 0.38 - 2026-09-23

### Security
- Everything the helper fetches is now treated as untrusted data, not just parsed: downloads are capped
  (64 MB per feed, 300 MB per map/border file, 8 MB per KML inside a KMZ), only `https://` links are ever
  fetched, XML with DOCTYPE or entity declarations is refused (no entity-expansion tricks), and every
  string handed to the wallpaper or widget passes through one filter that drops non-printable characters
  and `<`/`>`, caps names and notes at 160 characters, and keeps links only when they are complete
  `https://` URLs. Webcast links from the launch feed are kept only when they are `https://`.
- Labels on the map render as plain text (`textFormat: PlainText`), so a feed string can never be read as
  rich-text markup.
- No behaviour change for good data; the helper's Python still uses the standard library only and never
  executes anything it downloads.

## widget 0.39 - 2026-09-23

### Security
- Event links open in the browser only when they are plain `http(s)://` URLs; the "Open in player" and
  "Open in browser" buttons accept the same, and the player command only ever receives a validated URL
  (quotes and whitespace can no longer reach the shell line). Pop-ups requested by the embedded player go
  to the browser only when they are web links. Titles and details render as plain text.

## 0.37 - 2026-09-23

### Fixed
- Satellite markers ran ahead of their ground track (a "tail" up to 20 s long): the line's start was only
  refreshed every 20 s. The first piece of the track now starts at the marker's exact position and follows
  it every second; the rest still refreshes every 20 s, so the cost is unchanged.

## 0.36 - 2026-09-22

### Fixed
- Storm labels stood far from the icon for strong storms: the gap was still sized for the old ring that grew
  with the category. With the icon set it is now half the icon, whatever the category.

## widget 0.38 - 2026-09-22

### Added
- Live tab: "More streams" in the widget settings, one per line as `Title | URL`, listed after the ISS view
  and the launch webcasts (defaults: NASA TV, CGTN for Tiangong events). Channel "/live" pages open in the
  player or the browser; only a plain YouTube video/stream URL can be embedded.

## 0.35 - 2026-09-22 (wallpaper) / widget 0.37

### Added
- Launch final approach on the map: in the last ten minutes the countdown reads mm:ss and ticks every
  second, the label grows and turns amber, the marker grows by half and the ripple is bigger and brighter;
  "LIFT-OFF" for two minutes after T-0, then the lift-off picture.
- Widget: sort order (newest / most severe / by kind / soonest launch), remembered. New items (younger than
  "Highlight as new", default 60 min) get a tinted row, an accent bar and a NEW tag; a launch inside its last
  hour is pinned to the top with a SOON tag; a launch whose webcast is live shows LIVE.
- Widget Live tab: a stream chooser - the ISS view plus every upcoming launch that has a webcast listed
  (Launch Library's vidURLs; they usually appear a day or so before lift-off), embedded, in the player or
  in the browser. A launch's row in Events opens its webcast when it has one.

## 0.36 - 2026-09-22 (widget)

### Fixed
- Embedded live stream showed YouTube's "error 153": the player refuses a top-level embed with no referrer.
  It is now placed inside a small page of the widget's own, which carries a referrer.

## 0.35 - 2026-09-22 (widget)

### Added
- Widget "Live" tab: the ISS live stream. Off-widget by default: "Open in player" runs mpv (needs yt-dlp)
  as a small always-on-top window, "Open in browser" opens the page; embedding the player inside the widget
  is a setting (needs qt6-qtwebengine; a browser engine's memory and GPU time while the popup is open, and
  it only plays while the popup is open). The stream URL and the player command are settings.

## 0.34 - 2026-09-22

### Added
- livemap.sh: install / update / activate / deactivate / remove / purge / status from a terminal, covering
  the wallpaper, the widget, running helpers, the data folder and the saved settings.
- One download: livemap.zip now holds the wallpaper, the companion widget and livemap.sh together, and
  `livemap.sh install` installs both.
- Storm icon set (images/storm, from the supplied "1g outlined number" SVGs): the cyclone symbol with the
  category number inside (D, S, 1-5), a dark or light halo, mirrored south of the equator, and the dashed
  "P" once a storm has left the feed. Now the default marker; the drawn symbol remains a choice. The SVGs
  were made Qt-friendly (oklch colours converted, text baseline fixed, metadata dropped).

## 0.33 - 2026-09-21

### Changed
- Every feed keeps its last good data (last-<feed>.json in the data folder): when a fetch fails the map
  keeps drawing from it, and a desktop notice appears only once a source has had no successful update for
  "Complain after" hours (Map section, default 6). Status keeps the full detail.
- Storm intensity: GDACS's "severity" is a storm's peak wind over its episode, not the wind now (Polo showed
  cat 4 winds while it was a cat 1). The storm class now follows GDACS's own text, the label says "peak"
  for such winds, and NHC's current intensity, class and track are merged in for the Atlantic and eastern
  Pacific whenever it answers (same storm by name), not only when GDACS is down.
- The desktop notice is a third of its former size: one short line per problem, at most three, no border.

## 0.32 - 2026-09-21

### Added
- Secondary storm source: when GDACS does not answer, the US National Hurricane Center's CurrentStorms list
  with its forecast track and cone (KMZ) takes over for the Atlantic and the eastern / central Pacific. A
  storm keeps its identity across the two sources (storm memory is now keyed by name). Status row
  "Storms, secondary (NHC)".
- Marker size (Markers and labels): one slider scaling every event marker; launch and spacecraft pictures
  also keep their own size, with smaller defaults (18 / 22 px).

### Changed
- GDACS is given 20 s and one retry instead of 6 s; it is usually slow rather than down. A layer now shows
  data that arrives together with a note (e.g. "showing NHC") instead of discarding it, and the wildfire
  layer no longer posts a desktop notice for a GDACS hiccup while the satellite hotspots are on.

## 0.31 - 2026-09-21

### Added
- Picture markers: the ISS, Hubble and Tiangong can be drawn as pictures of the spacecraft (contents/images,
  keyed from the supplied stickers) instead of the symbol, and a launch as the rocket on its pad, switching
  to a lift-off picture once T-0 has passed. "Marker" choice and picture size under Satellites and Launches;
  pictures are the default. The colour setting still drives track, ring and label.

## 0.30 - 2026-09-21

### Added
- Cloud fallback: when the ready-made cloud image cannot be loaded (or always, by choice), the helper
  stitches the current cloud cover itself from five geostationary satellites - GOES-East, GOES-West and
  Himawari (NASA GIBS) and Meteosat 0 degrees and Indian Ocean (EUMETView) - all public WMS services that
  already deliver this map's projection, so no reprojection is needed. Infrared cloud-top brightness becomes
  cloud opacity. A source that fails keeps its last picture, so one outage only stales one region; the
  result is cached 2.5 h. Works without Pillow (pure-Python PNG codec, 1024 px) and better with it (2048 px).
  Setting "Cloud source" under Day and night, Status row "Cloud stitching", button "Stitch clouds now",
  `livemap-helper clouds --stitch`.

## 0.29 - 2026-09-21

### Added
- Profiles (top of the settings): High performance / Balanced / Power saving set the levers that cost CPU
  and GPU time in one go (animation rate, line animation, pulse modes, hotspot threshold, border detail,
  satellite track, load guard thresholds); changing any of them by hand shows "Custom".
- Layers checklist at the top of the settings, mirrored with each section's Show box.
- Load guard (Performance and power): animations pause when CPU or GPU stays above a threshold for two
  20-second polls, the live layers unload above a second threshold, and both resume after a quiet minute.
  GPU busy comes from sysfs on AMD, nvidia-smi on NVIDIA; Intel offers no busy figure without root, so its
  clock at the top of its range stands in; with no GPU reading the CPU decides. A missing or failing reading
  never triggers the guard. The corner notice says when the guard is on. Status row "Power and load".
- Companion widget "Live World Map Events" (livemap-widget.zip): the newest events with links to their
  sources, and pause / plain map / hide-layer switches that reach the wallpaper through mode.json.
- Helper commands: `power` now answers JSON (battery, cpu, gpu, mode), `mode`, `feed`.

## 0.28 - 2026-09-21

### Changed
- One level scale for every volcano: yellow = active (listed in the weekly report, or USGS Advisory),
  orange = USGS Watch or a "New" eruption in the report, red = USGS Warning. Non-US volcanoes are coloured
  too. A volcano pulses when it first appears and when its level changes (the new default), then sits
  steady; "significant" (orange and red keep pulsing) remains a choice.
- Less work per frame: label sizes are cached between layouts instead of re-measured; the satellite track
  and label move every 20 s (the marker still every second); ordinary hotspot cells are plain dots and only
  significant ones get the drawn flame; the helper only hands over the hotspot cells the setting asks for.
  New installs default to 20 animation updates a second.

## 0.27 - 2026-09-21

### Fixed
- Volcanoes without a real date showed "1 min": 0.26 changed what counts as a status change, which reset the
  "first seen" clock of every volcano, and that clock was used as a last resort for the duration. The
  duration now comes only from real dates (USGS level date or Smithsonian eruption start); otherwise nothing
  is shown. The memory is converted without a reset.
- Long durations read as years ("Dukono 93 y") instead of thousands of days.

## 0.26 - 2026-09-21

### Added
- Eruption start dates now come from the Smithsonian's own eruption database (Volcanoes of the World web
  service: every eruption still marked continuing, with its start date), cached for a day. The weekly
  report page is only consulted for the New / Continuing type and for volcanoes the database lacks.
  Status row "Eruption database (Smithsonian)".

### Changed
- Satellite ground tracks are drawn ahead of the satellite only and fade towards their end. A ground track
  never joins up (each orbit runs 23 degrees west of the previous one), so the old fixed-length line looked
  like a loop with a gap; the fade makes it read as "the path this far ahead".
- A volcano's report status flipping between New and Continuing no longer counts as a change (no pulse);
  only a USGS alert level change does.

## 0.25 - 2026-09-21

### Added
- Units (Global settings): kilometres, miles or nautical miles for satellite altitudes; burned areas follow
  (hectares, or acres with miles).
- Satellite track length: next 30 minutes, one orbit or two orbits ahead; the track no longer trails behind.

### Fixed
- The weekly volcano report page loads fine but its table is no longer plain <table> markup, so the parser
  found 0 rows (the Status row said so). A markup-independent fallback now finds each feed volcano's report
  type and eruption start date in the page text; when even that finds nothing the page is saved as
  weekly-report.html in the data folder for inspection (`volcanoes --table` says where).
- Rideshare launch missions no longer repeat the satellite name ("Owlright x3").

## 0.24 - 2026-09-21

### Added
- Space group: Satellites (ISS, Hubble, Tiangong) from CelesTrak's orbital elements, propagated by the helper
  (Kepler + J2, within a few km of SGP4 for these orbits), moving along a ground track once a second, with a
  dashed track line, labels with altitude; and Launches from The Space Devs' Launch Library 2: a rocket on
  the pad with a live countdown for launches inside a chosen window, pulsing in the last hour. Status rows
  for both; `sats --table`, `launches --table`.
- Country names: bold and capitals switches, letter spacing, text outline thickness (0-300 %), sizes to 40 px.

### Fixed
- The weekly volcano report page is retried with a browser-like user agent when the site refuses the plain
  one (a 403 there meant no eruption start dates and so no durations on non-US volcanoes).

## 0.23 - 2026-09-21

### Added
- Settings are grouped in a hierarchy: Map base (Map, Day and night) / Geographic layers (Countries, Time
  zones) / Natural events (Earthquakes, Volcanoes, Storms, Wildfires) / Network and connectivity (Network
  activity) / Global settings (Label styling, Ageing and pulses, Performance and power, Status). Renamed:
  "Sun and sky" -> "Day and night", "This computer" -> "Network activity", "All labels" -> "Label styling".
- Every section shows the live state of its own data sources ("Source:" line), fed by the Status panel.
- Time zones: Natural Earth's time zone outlines with UTC offsets, own colour, opacity and label size
  (Geographic layers). Part of the border download.
- Wildfires from NASA FIRMS as well: MODIS satellite detections of the last 24 hours (no key, about 3 MB
  every 3 hours) clustered into half-degree cells, drawn as small flames sized by fire power; choose GDACS
  events, hotspots or both, and the minimum detections per cell. Status row "Fire hotspots (NASA FIRMS)".
- Home city search: type a city under Network activity, pick from the offline Natural Earth list (about
  7 000 places) and the coordinates are filled in. Nothing is sent anywhere.
- Status row "Weekly report page (Smithsonian)".

### Changed
- All volcano triangles are hollow; colour carries the level, a bolder triangle and the pulse the news.
- The settings page keeps its two-column layout in a narrow window instead of restacking; wide fields are capped.

### Fixed
- Eruption start dates from the weekly report: the page often takes longer than the 6 s the feeds are
  allowed, so it silently failed; it now gets 25 s and its table is cached for a day.

## 0.22 - 2026-09-20

### Changed
- Volcano labels are one standard form: the name, then minutes / hours / days since the volcano went above
  normal (USGS's date for a US level, else the weekly report's eruption start date, else since first seen
  here; nothing when unknown). No more "erupting", "Watch (orange)", "was yellow" or "no longer reported":
  colour, the solid triangle, the pulse and the ageing say those.
- Wildfire labels likewise: place, burned area, time listed. The flame's height follows the burned area
  (GDACS rates nearly every fire green, so colour alone told nothing) and a "Show only" size filter was added.
- The cyclone symbol is redrawn as the proper NHC shape: two tails leaving the core tangentially and
  spiralling out; depressions get a smaller one.

### Fixed
- Earthquake labels dropped the direction from USGS's open-ocean names, so a quake "south of Africa" read
  "Africa" while sitting in the Southern Ocean (its true position). Only the "57 km SSE of" part is dropped now.
- The storm symbol was drawn under its own forecast dots; it is now on top, and dots under it are hidden.

## 0.21 - 2026-09-20

### Added
- Wildfires: GDACS wildfire events (same list as the storms, no key) as a flame symbol coloured by GDACS's
  alert level (green, orange, red; or one colour), with a level filter, labels (place, burned area, how long
  listed), the usual label controls, pulse choice and ageing. Status row "Wildfires (GDACS)";
  `livemap-helper fires --table`.
- Storms drawn as the NHC-style tropical cyclone symbol, coloured and shaped by intensity: depression
  blue-grey with a small open swirl, tropical storm green-cyan with an open swirl, hurricane (cat 1-2) amber
  with a solid centre, major hurricane (cat 3+) red with heavier arms; mirrored south of the equator.
  Tracks, cone and label follow the intensity colour. Untick "Colour and symbol by intensity" for one colour.

## 0.20 - 2026-09-20

### Added
- USGS volcano alert levels (Advisory / Watch / Warning) from the USGS HANS public API, checked hourly: US
  volcanoes in the weekly report carry their level, and elevated US volcanoes the report does not mention
  are added to the map. Triangles and labels use the USGS colours (yellow, orange, red; can be turned off
  under Volcanoes). Where the CAP feed records the previous, non-elevated notice, the label says since when
  the level has been raised ("Watch (orange) since 2026 Aug 25"); otherwise how old the last update is.
- A change of alert level or report status counts as newly reported again: the volcano pulses and its label
  says "was yellow" for two days. Watch and Warning count as significant, like a "New" eruption.
- Status panel row "Volcano alert levels (USGS)".
- After a USGS level the label shows how long the volcano has been above green ("Watch (orange) 26 d"):
  USGS's own date where the CAP feed has it, otherwise counted from when this machine first saw it raised;
  nothing when unknown. The "first seen" wording is gone.
- Pulse choice per element (earthquakes, volcanoes, storms): nothing, newly reported, significant, or either.
  Significant means a quake at or above the chosen magnitude, a volcano the weekly report marks "New", a
  storm of hurricane strength (category 1 and up). Newly reported means first seen less than the shared
  "Newly reported" hours ago.
- Label layout (All labels): one line, name above the details, or automatic, which keeps one line where it
  fits and switches a label to two lines when the wide form would leave the screen or hit a neighbour.
  Earthquakes put the place on the first line and magnitude and age on the second.
- `volcanoes --table` says how many rows it found on the weekly report page, so a missing since-date can be
  told apart from a page that could not be read.

### Changed
- Earthquake rings are smaller (M6 about 28 px instead of 46 on a 1920-wide screen); the size slider still scales them.
- Labels default to one line again; the two-line layouts remain a choice under All labels.
- The first time the helper sees a feed, what is already there is treated as of unknown age rather than
  "30 days ago": no fake "first seen 30 d ago" and no pulsing of things that were there all along. Existing
  events.json memories are converted on the next run.

### Fixed
- 0.20's first build keyed the volcano memory differently, which made a ghost "no longer reported" twin and a
  "first seen 1 min ago" of every volcano; the memory is merged on the next run.
- USGS colours were handed to the colour blend as text, so US triangles did not change colour.
- A transient "TypeError: Value is undefined" from the packet animation when a connection's path changed.
- The weekly report table parser now copes with header cells in the name column, HTML entities and line
  breaks inside cells, and any column order.
- A "New" volcano that was already listed when the helper first looked did not pulse; with the new
  "significant" choice it does.

## 0.19 - 2026-09-20

### Added
- One life cycle for every event: it pulses while newly reported ("Newly reported" hours, default 3),
  sits steady while its source still lists it, then drifts towards the aged colour and is removed once
  fully aged. Storms and volcanoes now pulse when they first appear (storms have a pulse switch of their
  own); earthquakes can still pulse for strength as well ("Also strong ones, from magnitude ...").
- The helper remembers when it first saw each storm and volcano (events.json), so a volcano label can say
  "first seen 5 d ago" even when the weekly report gives no date, and an event that drops out of its feed
  ages out instead of vanishing ("no longer reported" / "no longer tracked").
- Volcano labels say what the report says: "new eruption" (the report's "New": an eruption after at least
  three months of quiet), "erupting" (continuing) or "activity", with "since <eruption start date>" where
  the weekly table gives one.

### Changed
- Settings regrouped by element, in the same order every time: Map, Sun and sky, Countries, Earthquakes,
  Volcanoes, Storms, This computer, then the shared All labels, Ageing and pulses, Performance and power,
  Status. Inside each element: show, look, labels (content, size, plate, text colour), behaviour.
- The settings page no longer breaks in a narrow window: at most three controls per row, sliders shrink,
  explanations wrap instead of stretching the page, and long checkbox texts were shortened.

### Fixed
- Eruption start dates never showed: the weekly table's last column reads "New Eruptive Activity" /
  "Continuing ...", not "New", so the parser found no match. Names are now compared without accents
  (Kīlauea) and "—" or "Unknown" dates are left blank.

## 0.18 - 2026-09-20

### Added
- "Labels" settings: plate colour, plate opacity and text opacity for all labels; per label type (network,
  earthquakes, storms, volcanoes, country names) a plate on/off switch and a text colour, which can follow
  the layer's colour or be set by hand.
- "Ageing and pulses" settings: earthquakes and storms drift towards a chosen colour (and fade a little)
  as they age, from a start age to a fully-aged age, both adjustable; pulse rings have an expand time and
  a repeat period, shared by earthquakes and volcanoes.
- Notices (missing downloads, feed problems) are now a small box in a corner of your choosing, or off.

### Changed
- All event labels are drawn by one pass above every layer, so no cone, arc or ring can cover them, and
  labels from different layers no longer print over each other (network first, then storms, earthquakes,
  volcanoes). A label flips to the other side of its mark when it would run off the screen or into
  another label, and is nudged back on screen at the top and bottom edges.
- Storm and volcano layers keep their last data when a fetch fails, instead of showing an error and nothing.
- Label layout measures the real text width, tries above and below as well as left and right, never lets
  a nudged label sit on its own mark, and draws a thin leader line when a label had to move away from it.
- Volcano labels no longer repeat the report date ("reported 4 d ago" was the same on every one); they say
  "erupting" or "new activity", plus "since <date>" when the weekly report gives a start date.

## 0.17 - 2026-09-20

### Added
- Volcanoes with new activity ripple like strong earthquakes (same ring, the volcano colour); can be switched off.
- Volcano labels can say since when: "Krakatau · new activity since 2026 Sep 14", taken from the eruption start
  date in the weekly report's table, or "reported 4 d ago" from the feed when the table has no date.

### Changed
- "New" versus "continuing" now comes from the report's own table instead of being guessed from the text.
- The volcano layer moved out of the cached part of the map (it animates now); it is a few dozen small items.

## 0.16 - 2026-09-20

### Added
- Volcano layer: volcanoes in the current Smithsonian / USGS Weekly Volcanic Activity Report (updated every
  Wednesday, about 16 volcanoes a week), as triangles with optional names; new activity is drawn solid and
  can be the only thing labelled. `livemap-helper volcanoes --table` shows what was parsed.
- This changelog, and the version number in the Status section and in copied reports.

## 0.15 - 2026-09-18

storm tracker: active tropical cyclones worldwide from GDACS (no key): position, name, type and Saffir-Simpson category, wind, past track, forecast track and points, forecast cone. `livemap-helper storms --table` shows what was parsed, including the feature classes GDACS sent. The "answered locally" note under the home ring is now optional (off by default).

## 0.14 - 2026-09-18

framing: choose which part of the world must be on screen (presets "without Antarctica", "where people live", or custom north/south/west/east limits); Stretch / Fit / Crop now apply to that frame. Every layer follows automatically because they all live in the map item's coordinates.

## 0.13 - 2026-09-18

stripes on fractionally scaled screens, second attempt: the shade and lights strips are now painted with additive blending, so neighbouring strips that share a device pixel add up to exactly the right darkness at any scale factor, whether or not antialiasing is in effect (switching it off in 0.12 did not cure it on the machine that showed it). The journal line for the shade now carries the version and the screen scale.

## 0.12 - 2026-09-18

fixed vertical stripes across the night side on screens with fractional scaling (antialiased 1-px strips blended with their neighbours; antialiasing is now off for the shade and lights canvases). Latency is hidden as soon as two far hosts answer in under 2 ms (clear sign of a local proxy/VPN), not only when most do. Unanswered connection attempts no longer show a round trip.

## 0.11 - 2026-09-18

polish: earthquake labels get the same dark plate as network labels; "<0.1 ms" instead of "0.0 ms"; when most round trips are answered locally (a VPN or proxy such as Portmaster's SPN), latency is hidden and the home ring says so once, instead of a tag on every label.

## 0.10 - 2026-09-17

earthquake labels (magnitude, or magnitude + place + age; from a chosen magnitude; strongest first, overlapping ones dropped). Country names are de-cluttered the same way ("All that fit"), drawn with a real halo (HaloText.qml) and get size and opacity settings. Round-trip times that beat the speed of light for the distance are flagged: "(answered locally)" under 2 ms, otherwise "(nearer than mapped)" - a sign of a VPN, proxy or a CDN node close by.

## 0.9 - 2026-09-17

network layer: round-trip time per place (the kernel's own measurement, via `ss -i`, no pinging); a memory of every place and country seen before (`seen.json`, local only, "Forget connection history" in Status) so first-time places and countries are highlighted; closed connections change colour and fade out over a configurable time instead of vanishing; connection attempts and connections that closed between two polls (TIME-WAIT) are now seen as well. `livemap-helper where HOST` shows where a host would be drawn.

## 0.8 - 2026-09-17

performance and power. The still part of the map (images, clouds, shade, lights, borders) is rendered once into a texture and reused, so an animation no longer forces the whole stack to be redrawn every frame. Animations run from a clock the settings can set to 10-60 updates a second, and it stops when there is nothing to animate. "On battery" policy: keep running / pause animations and poll once a minute / plain map only. `livemap-helper power` reads the state.

## 0.7 - 2026-09-17

network labels are drawn above all arcs, on the side of the dot facing away from home, with an optional dark plate and without "(district)" suffixes; arc animation is a menu (packets / pulsing glow / both / none). Hints about missing data moved to one block that is always on screen (in Crop mode the old ones were outside it). Helper tries IPv4 first: on a network with broken IPv6 every request took ~50 s.

## 0.6 - 2026-09-17

city lights reworked: the helper extracts just the lights (`lights.png`, brightness -> opacity) so they glow over the dimmed map and clouds instead of replacing the night side; drawn by a Canvas ("source-in" against the night mask) with the GPU mask as an opt-in. Downloads are picked up within two minutes, no restart; an on-screen hint says when ticked features have no data yet; Status gets a "Download NASA maps and city lights" button. Defaults: night 78 %, clouds 50 %.

## 0.5 - 2026-09-17

vector outlines: coastlines, country borders, states/provinces and country names from Natural Earth (public domain), with colour, opacity, thickness and detail settings. Data: `livemap-helper fetch-borders` or the button in Status.

## 0.4 - 2026-09-17

settings page: appearance controls for every layer (imagery dimming, night darkness, dusk width, city-light brightness, cloud opacity, earthquake colour / size / pulse, arc colour / thickness / glow, packet speed, label size, hide program names, maximum places) and a Status section that health-checks every data source and shows what the wallpaper wrote to the journal.

## 0.3 - 2026-09-17

night shade painted with plain rectangles/gradients and shown directly (the pixel-written, texture-routed version drew nothing); diagnostic lines in the journal (`grep livemap`) for settings, base map, shade, lights and quakes.

## 0.2.1 - 2026-09-17

`net --table` always prints place names; label overlap test uses the label's real length instead of a fixed box.

## 0.2 - 2026-09-17

overlays drew nothing (id `layer` shadowed inside delegates); night side rebuilt so the shading no longer depends on an invisible Canvas being painted.

## 0.1 - 2026-09-17

First version: seasonal base map, day/night with city lights, clouds, earthquakes, network arcs, settings page.
