# Changelog

All notable changes to Live World Map. Newest first. Versions before 0.16 were reconstructed from the
release notes written at the time; their dates are the day the version was handed over.

## 0.50 - unreleased

### Fixed
- The widget's settings page scrolls: it is a KCM page now (the way Plasma 6 applets lay out their settings), with the
  form inside, so the wheel moves it and a scroll bar appears when the page is taller than the dialog.
- The Live tab plays on the desktop: the embedded player, the Sky tab's fetching, the hover ring and the 30 s
  refresh were all gated on the popup being open, a flag a desktop widget never sets - so "Play here" did nothing
  there. The desktop counts as shown now. The placeholder says "Player not started" on the desktop, and its
  Play here button is offered whenever a stream could be embedded.
- The widget's settings page kept its width to the dialog: the explanatory notes and the streams box asked the
  form for their full one-line width, so the page grew past the window, labels dropped under their fields and the
  right edge was cut off. Capped, so the notes wrap and the labels sit beside their fields again.
- Hovering down the Events list no longer stutters: the hover handshake with the wallpaper (which event to ring on
  the map) was a shell `printf` to write focus.json and a `cat` to read it - two forks of plasmashell, with its 13 GB
  of address space to map, for every row the pointer crossed. Both sides now go through Qt's Settings (focus.ini,
  no process), the widget writes only once the pointer has rested on a row for 150 ms and only when the target
  changed, and the wallpaper's watcher reads the file in-process. A sweep down the list now costs nothing.

## 0.49 - 2026-11-27

The release to take if your desktop slowed down a day or two after 0.48: see the first entry under Fixed.

### Added
- On the KDE Store: the wallpaper (store.kde.org/p/2382950) and the widget (p/2382952), so both install from inside
  Plasma. The README's install section leads with that route and a KDE Store badge; docs/PUBLISHING.md carries the
  links and the Store's category names.
- "Not a warning system": the README's "What it is not", both Store listings and the foot of the Essentials page say
  that the map is for general awareness only and no replacement for official alerts.
- docs/PUBLISHING.md: the KDE Store routine - account, the two listings with their text, screenshots and tags, the
  update per release, what a Store install does not do. `scripts/package.sh` also builds the two Store archives
  (`livemap-wallpaper-<v>.tar.gz`, `livemap-widget-<v>.tar.gz`, metadata.json at the root) and CI attaches them
  to every release beside livemap.zip.

### Changed
- The Store archives carry the package and its LICENSE only - no CHANGELOG.md, no livemap.sh; the Status page's
  "what changed" line points at the changelog on GitHub, which is right for both install routes.

### Fixed
- The CPU that crept back after a day or two - and vanished when the widget was re-added or the settings closed -
  was Plasma's executable DataSource leaking: every command string run through one adds a property to its data
  map for good, and the map's meta-object is rebuilt, at a cost growing with the count, on every add and every
  removal. A poll every 20 s with a fresh string each time reaches thousands of entries, and plasmashell's main
  thread spends itself rebuilding them (three gdb samples, all in DataSource::removeSource ->
  QQmlPropertyMap::clear -> QMetaObjectBuilder::toMetaObject). Every command now runs through a small Exec
  component that gives each run a DataSource of its own, destroyed when its output arrives; nothing accumulates.
- Maritime cluster labels read "3 robberies" or "3 × suspicious activity", not "3 robbery/theft ×"; the layer's Show box names all
  three sources.

## 0.48 - 2026-11-26

The first release since 0.46: everything under 0.47 below (never tagged on its own) ships with it.

### Added
- Maritime incidents: a new layer and widget kind from UKMTO (United Kingdom Maritime Trade Operations), the
  Royal Navy's point of contact for merchant shipping in the Indian Ocean, the Red Sea, the Gulf of Aden, the
  Arabian Gulf and the Strait of Hormuz. ukmto.org holds no data itself: its page reads the Royal Navy's API
  (`sccd.royalnavy.mod.uk/api/ukmto/all`), which answers plain JSON to anyone, no key or cookie, so the helper
  reads the same (`maritime.py`, every 15 minutes, last answer kept). Every incident - attack, attempted or
  illegal boarding, hijack, kidnap, suspicious activity, electronic interference, advisory - is a diamond with
  an anchor at the reported position, coloured by what happened (red: hijack, kidnap, or an attack UKMTO itself
  pins red; orange: attack or boarding; yellow: the rest), full size while fresh (24 h) and pulsing while newly reported (the shared window), shrinking
  and fading over the window shown (Settings > Maritime incidents: 1 to 30 days, 14 by default; colours;
  labels "Attack · tanker · Strait of Hormuz · 3 h" for attacks and worse, all, or none). The widget lists the
  same incidents (Events, its own Show box, Map controls chip and Sources row) with the vessel type, UKMTO's
  number and pin colour, the position, when it happened and was published, and the full report as UKMTO wrote
  it. The window is shared through layers.json (`maritime_days`), so the list and the map agree. Status:
  "Maritime incidents (UKMTO)"; sources.json: hazard "Maritime security", Crown copyright. Fixtures from the
  real API (41 incidents of October 2026, and the filters list) and four tests.
- Maritime incidents from the Gulf of Guinea too: MDAT-GoG (Maritime Domain Awareness for Trade - Gulf of
  Guinea, run by the French and Royal Navies) publishes its events on SEVERINE, whose map reads a public API
  (`severine-ext.vigie.defense.gouv.fr/api/events/markers`, then `/api/events/<id>` for each event's record),
  no key or cookie. The helper reads the markers of the window plus a week, fetches each new event's record
  once (at most 20 a run) and keeps them in `mdat-events.json`, since a published record never changes. The
  same diamond and anchor, with the MDAT type (piracy, kidnapping, sea robbery, sea theft, illegal and attempted
  boardings, suspicious activity) and its parent category in the label and the widget's "Incident" row, the
  place after the type ("off Bata, Equatorial Guinea"), MDAT's own pin colour and the event's page on
  SEVERINE as the link. UKMTO and MDAT-GoG are read together; the layer fails only when both do, and a source
  down on its own is a feed problem line. Settings and the widget's Show box name both sources; Status:
  "Maritime incidents (MDAT-GoG)"; sources.json `mdat-gog`. Fixtures from the real API (12 markers, 8
  records, the type list) and two tests.
- Maritime incidents from Asia too: ReCAAP ISC (the Regional Cooperation Agreement on Combating Piracy and
  Armed Robbery against Ships in Asia, Singapore) publishes its verified incidents on a public "Interactive
  Incident Reports" page whose table and map read one JSON list for a date range from the portal's own API
  (`portal.recaap.org/recaap-api-be/api/v1/openMap/fetchInteractiveIncidents`), no key or cookie. The helper
  asks for the window every run (one request; the server ignores paging). Same diamond and anchor; ReCAAP's
  grading sets the level (CAT 1, crew or ship taken: red; CAT 2, armed or violent: orange; CAT 3 and 4 and
  attempts: yellow; a hijack or kidnap is red whatever the category). ReCAAP names the ship, so the label and
  the widget carry the vessel type and name, flag and IMO number, the sea area as ReCAAP names it ("Straits of
  Malacca & Singapore", "Philippines (Ports/Anchorages)"), the category and the incident number, and the
  narrative; the link opens the interactive reports page. Three sources now feed one layer: a source down on
  its own is a feed problem line, the layer fails only when all three do. Settings, the Show box, Status
  ("Maritime incidents (ReCAAP)") and sources.json (`recaap`) name it. ReCAAP publishes after verification,
  so an incident appears days to two weeks after it happened; with a short window the Singapore Strait can
  look quiet when it is not. Fixture from the real API (56 incidents of 2026) and two tests.
- The ship's photograph in a ReCAAP incident's bubble, from Wikimedia Commons, which files ship photographs by
  hull in a category per IMO number (kept by the ship-spotting community; the number follows the hull through
  renames). One keyless query per named ship, a few per feed run, hits kept for good, misses retried weekly;
  the thumbnail travels the usual bubble-pictures path. The note under the picture names the ship and the
  photo's author and licence and links to the file's page on Commons; when the photo was taken under an earlier
  name, the note says so ("“Salsa” (as Leopard, 2010)"), since that is the name on the hull. Nothing for UKMTO and MDAT-GoG, which
  withhold names; nothing when Commons has no photo of that hull.
- Highlight styles for the event the widget points at (Essentials > Events widget > Highlight): Ring, Ring
  and pulse (as before, the default), Glow (a breathing halo), Spotlight (the rest of the screen dims by a
  chosen amount and a clear disc stays around the event), Reticle (four ticks slide in and lock on, then hold
  still), and Beacon (a radar sweep inside the ring), with a strength
  setting for size and weight, the colour button for all but Spotlight, and Spotlight's own dim amount (10-70 %). The animated ones keep their own clock, so they breathe on a quiet map too, and
  stop the moment nothing is highlighted.
- Cluster labels, one switch per layer (Earthquakes > Swarms, Maritime incidents > Runs; both on by default): three or
  more earthquakes or maritime incidents within a few label heights of each other get one label instead of a pile - the strongest quake keeps
  its label and says "+2 nearby"; a run of incidents reads "11 attacks · tanker, tug · Strait of Hormuz · 5–11 d"
  (mixed types say "incidents"). The marks are all still drawn; `Geo.clusterGroups` and `Geo.spanRange` do it.
- Widget: the maritime kind's anchor is an icon drawn in the theme's text colour (icons/maritime.svg, like the
  fire and satellite ones) rather than a glyph the font turned into a coloured emoji.
- Helper: a facts row named in `common.LONG_FACTS` ("Report") may carry up to 1200 characters and its line
  breaks, where every other value is cut at 160; line breaks in any value now survive `emit` (they were
  stripped as non-printable, which flattened the bullet lists of flood areas).
- Hover a row in the widget and its event is marked on the map: by default a steady ring with a slow pulse
  running out of it in a colour of your choice (the other styles are below), and when the event is off screen a
  ring at the nearest edge with an arrow and the event's name, since a wallpaper cannot pan. The widget writes
  focus.json in the data folder (a shell printf, no interpreter) at most every 120 ms; the wallpaper's FocusLayer
  reads it through a `cat` on the executable engine (Qt 6 refuses file:// XMLHttpRequests in plasmashell) every
  400 ms while the popup is open and every two seconds otherwise, so nothing in the event layers is touched and
  the cost is one small item moving. Two switches: Essentials > Events widget "Mark on the map the event the
  widget's list is pointing at" (with the colour) on the wallpaper, and Map controls > This widget "Ring the
  hovered event on the map" in the widget.
- Widget: a Sky tab, between Live and Map controls, about your sky at the home place from Essentials. Now
  (temperature, conditions, feels-like, today's high and low, wind, humidity, cloud, pressure and its trend); the
  next seven days, one 24-hour strip each - colour for the temperature hour by hour, the night ends darkened,
  hatched bands where rain (blue) or snow (white) is forecast with the chance as their strength, ticks at 6 / 12 /
  18, a white line for now on today, and a bubble with the hour's line when hovered; sun and moon (sunrise, sunset,
  day length, the hours dark enough for satellite spotting, moon phase and illumination, UV); tonight's sky (cloud
  cover through the dark hours, the next visible ISS or Tiangong pass, aurora from the planetary K index with
  whether it is plausible at your latitude, air quality). Under the place name, how old each source's answer is -
  plain under an hour, amber to three, red beyond, with the reason when a fetch failed - so stale data cannot pass
  for fresh. Sources: Open-Meteo (forecast, air quality) and NOAA SWPC (Kp), each fetched at most every 20 minutes
  by the helper (`sky`) and kept, so an outage shows the last answer with its age; sun, moon and passes are
  computed locally. New Status rows "Weather at home (Open-Meteo)" and "Space weather (NOAA SWPC)" read that cache.
- Sky tab: a "?" beside Air quality, Aurora, UV index, Dark for satellites, Moon, Cloud cover tonight, Next
  visible pass and Pressure opens an opaque bubble saying what the scale means - the AQI bands in colour (the US
  EPA scale with miles, the European EEA scale otherwise, and the line now says which), Kp against the latitude
  the aurora reaches, the WHO UV bands, what civil dusk is, what a falling pressure means.
- Units: Temperature (follow the distance unit - miles means °F - or Celsius or Fahrenheit) and the one Clock
  setting (12- or 24-hour), which the Sky tab, the time zone labels and the band all follow; the 12-hour checkbox
  left the Time zones row for it. Rain is in inches with miles, millimetres otherwise; pressure in inches of
  mercury with miles, hectopascals otherwise. The wallpaper passes four units to the helper now (layers.json).
- Essentials: a frame picker. The world (the Classic picture) with the frame drawn on it: drag inside the box to
  move it, its edges and corners to resize, the wheel to zoom about the pointer, drag outside to draw a fresh
  box; everything outside dims. Dashed outlines show what each screen really displays once Fit to screen has had
  its say - this screen in the highlight colour, every other screen in amber - so a laptop panel's trimming is
  seen here, not on the desktop. "Keep the box in this screen's shape" makes resizing a zoom with nothing
  trimmed or stretched. The Show presets place the box; the degree fields on the Map page are the same box in
  numbers (FramePicker.qml). The Map page's Show, North to south, West to east and Fit to screen rows have gone:
  the picker, the Show presets and Fit to screen live on Essentials only, and the Map page is about the imagery.
- Fit to screen: Auto, now the default. Stretch while it hardly shows (up to 12 % taller or wider than true) and
  Crop beyond that, so the 72°N-56°S view fills a 2.4:1 monitor as before while a 16:10 laptop panel trims the
  sides instead of squeezing the continents to 60 % of their width. The settings preview says what a screen
  gets ("shapes drawn 112 % as tall as true and the sides trimmed"). Stretch, Fit, Crop and Fill stay as choices.
- A seventh base map, "Classic Blue Marble (NASA 2002, static)": the original composite the wallpaper was built
  around - the same in every season, with the ice and the deep blue ocean - shipped with the package at 5 400 px
  (a bigger copy saved as base/classic.jpg in the data folder is used instead), cut to the frame like the
  monthly maps, with the map tone and the night side applying. Also a built-in style of that name. The picture
  ships byte for byte as supplied and its frames are written as full-colour JPEGs at quality 96 (no chroma
  subsampling), so the only loss between the file and the screen is the scaling to the screen's size.
- ISS and Tiangong passes over your home place. Satellites > "Passes over you": from the same orbital elements,
  when a station will cross your sky - rise, highest point and set with compass directions and how long you
  can see it - in the widget's Satellites group an hour ahead (SOON when minutes away; the launch sound covers
  it) and the next three in the station's bubble. A pass counts as visible only when your sky is dark and the
  station is still in sunlight, which is physics, not a setting; daytime passes are left out unless you ask for
  every pass. Cloud over your home from the live cloud image is shown as a hint and never hides a pass.
  Helper: `passes --lat --lon [--all] [--table]`.
- A new base map or view takes up to a minute to build, and it used to look like nothing happened. Now a banner
  across the top of the settings page (KDE's inline message, with a progress bar) says it is building, how far
  along, and that the map keeps its previous picture meanwhile; it turns green for a moment when the picture
  lands and red with the reason if it failed. On the map itself a toast in the lower middle shows the same
  progress - after Apply the eyes are there, not on the dialog - and fades once the new picture is in. The
  helper reports tiles and months as it goes (`frame-state`).
- Air raid alerts: "Long-running alerts" has a fourth choice, "Hidden until something new happens there" - a
  frontline oblast under alert for weeks disappears from the map (outline like any quiet oblast, no label), and
  comes back as new when a raion or city inside it gets its own alert or a type is added (shelling on top of
  the air raid), which the helper now tracks as a renewal; the label then says "renewed 4 min". The oblast
  alert itself is never re-issued while on, and only alerts.in.ua (with a token) reports what happens inside.
- Air raid alert labels vanished at 6 px and below: the label's gap from its anchor fell under the placement
  padding, so every position failed the "not over the mark" test. Fixed.
- Tsunami: PTWC and NTWC each send a message about the same earthquake; the two now show as one event,
  both centres named, with every area and coast segment of either.
- The daily source probe on GitHub now also runs the feed and flags a kind with no records at all - the quiet
  failure, a source answering 200 OK with a changed record shape - and on any failure opens one GitHub issue
  ("Source probe: ...") with the failing lines and what each server answered, adding to it each day it persists
  and closing it when every source answers again.
- Units: the Units page now holds Speed as well as Distance (the same choice as Storms' wind unit, shown in both
  places), and the widget's bubbles follow them: depths, altitudes and orbital speeds in the units you chose.
- Widget: a flood warning's bubble lists every county or area it covers - "6 counties" and then one line each -
  for NWS (the grouped office marks too), MeteoAlarm, Environment Canada and the Environment Agency. Only the
  first three names used to reach the feed.
- Widget: every bubble carries a dated row with its age - storms their last fix as a time, volcanoes their ash
  advisory, and anything else "Reported" from the event's own time - so no kind is without one.
- Widget: every time in a bubble (when a quake struck, when a bulletin was sent, a flood's from and until, an
  alert's since, a launch) also says how long ago or how far ahead that is - "Sat 24 Oct 21:27 · 2 h ago" -
  ticking with the widget's clock.
- Widget: a preview bubble. Rest the pointer on an event and a bubble beside the widget says what the feed knows:
  a storm's class, wind, position, last fix, centre and what lies in its path; a quake's depth, felt reports,
  intensity and PAGER alert; a flood's level, area, issuer and when it ends; a volcano's level, observatory and
  ash height; a launch's rocket, orbit, pad and status - and a picture where the centre publishes one at a fixed
  address (NHC's five-day cone, JTWC's warning chart, the launch's picture). Settings: Off / Details / Details
  and pictures (the default). The feed carries the facts (`facts`, `image` per item), so the widget draws no
  conclusions of its own. The three spacecraft get one too: where it is right now, altitude, speed, one orbit's
  length and the age of the elements, with the wallpaper's own marker art as the picture; Tiangong is now
  "Tiangong Chinese Space Station" in the list.
- Widget: the spacecraft bubbles say who is aboard - name, country and how long they have been up (Launch Library
  2's list of people in space, kept four hours; CMSA crews on Tiangong, the rest on the ISS). Pictures for
  earthquakes (USGS's ShakeMap intensity map, looked up once per quake, a few per feed run) and for the storms
  GDACS alone tracks (NASA Worldview's latest true-colour satellite pass round the storm, the same imagery the
  clouds come from).
- Widget: the Map controls tab in the shape of the design: Quick settings (clouds and their opacity, pulses and
  animation, full speed) as switches, the layers as chips - on, grey when the wallpaper has the layer off,
  outlined when hidden from here, each with its sources' health dot - and an "Open the wallpaper settings"
  button that asks plasmashell to open the desktop's settings (helper `widget --configure`).
- Widget: on the desktop it fades to 45 % once the pointer has been away for three seconds - the whole widget, frame
  included, to an opacity of your choice, so the map shows through - and come back as the pointer arrives; or
  hold a fixed opacity. Settings, "On the desktop". It draws its own (Plasma's usual) frame there for that.
- A forecast cone for the storms JTWC covers (the western Pacific, Indian Ocean and southern hemisphere), which
  publishes none: built from JTWC's own mean track errors round each forecast point, drawn like every other cone.
- Settings: a "Find a setting" box at the top of the page - type a word (tsunami, label size, clouds) and only the
  sections that mention it stay, opened; the Coverage section ends with every data source's attribution and
  licence, as the providers ask.
- Volcanoes in hours, not days: the Washington VAAC's ash advisories (the Americas and the eastern Pacific -
  an advisory within the hour of an eruption, with the ash cloud's outline, height and forecast drawn on the
  map and "ash to FL150 · 2 h" in the label), JMA's alert levels for Japan's volcanoes (matched to JMA's list
  of 111, shipped with the package) and GeoNet's for New Zealand, all beside USGS's, with the weekly report as
  the catalogue.
- EMSC as a second earthquake source: the Euro-Mediterranean Seismological Centre's real-time catalogue (the
  national networks' reports) merged with USGS's feed - the same quake within 120 km and 90 s is one, USGS's
  record wins - so the smaller quakes outside the US that USGS lists late or not at all appear within minutes.
  Earthquake sources are a pair of boxes under Earthquakes; the quake layer and the widget now read one shared
  list from the helper (`quakes`), one request instead of two.
- Official flood warnings beyond the US: MeteoAlarm (the 38 European national weather services - flood, rain
  and coastal warnings by region, placed on Natural Earth's regions by name), Environment Canada's rainfall and
  flood alerts with their polygons, and the Environment Agency's flood alerts and warnings for England with each
  flood area's outline, all in the flood layer and the widget beside the NWS alerts, grouped per country or
  office and type; three new boxes under Floods, on by default. The coverage matrix's Floods row is now
  "minutes" for Europe, Canada and England.
- Tsunami bulletins: every large undersea earthquake the Pacific and National Tsunami Warning Centers evaluate
  (tsunami.gov), as a ringed mark at the epicentre coloured by the level - no threat found (quiet blue-grey),
  watch, advisory, warning or threat message - with rings running out while a threat stands and the threatened
  coast drawn between the centres' breakpoints; a threat stood down by a later message fades over three hours,
  an evaluation leaves after six. tsunami.gov publishes only each centre's latest message, so the helper
  remembers every bulletin by event. The widget lists tsunami bulletins first; new "Tsunami bulletins" section.
- Coverage: what covers where, and how fast. One file (`contents/data/sources.json`) lists every source with
  its hazard, regions or country, lead time, cadence, licence and attribution; the Coverage page shows it as a
  matrix (hazards by world region, each cell the best source, green within minutes, amber hours, grey a weekly
  report) with the details on click, and a "Where you are" summary for the home city - which says plainly
  that official flood warnings are US only, fire incidents by name US / Canada / EFFIS, volcano alert levels US
  only. `docs/COVERAGE.md` is generated from the same file (`livemap-helper coverage --markdown`).
- The Events widget says how old each kind's data is: an empty kind reads "none right now · as of 3 min ago"
  when the source was reached, "no data yet" when it never was - so nothing happening and a source down are
  told apart.
- What keeps the map animating is now said where you can see it: Status > Power and load reads "pulse clock
  running at 30 fps for storms, maritime" (or "idle"), and the widget's Map controls tab has the same line under
  the power notice. Every tick of that clock redraws the whole screen, so when plasmashell is busy this is the
  first thing to look at; Ageing and pulses > Newly reported is the knob (layers.json: `pulsing`, `fps`).
- Sky tab: a Radar button opens the last hour of weather radar round the home place as a loop - RainViewer's
  composite of the national services' radars (NEXRAD, the European, Japanese, Australian, Canadian services and
  more; keyless, free for non-commercial use with attribution), seven frames ten minutes apart, nine tiles each
  composed by the helper over a dark base cut from the Natural Earth files the wallpaper already has, with a ring
  at home; about 1 500 km across. Play/pause, a scrubber, the frame's time, a refresh; fetched only while the
  pop-up is open and every ten minutes after, a frame fetched once (its path is a content hash) and kept three
  hours. The pop-up says plainly when nothing is on the radar, since an empty tile cannot tell dry from
  uncovered (the oceans, most of Africa and much of Asia have no shared radar). Needs python3-pillow.
  `livemap-helper radar`, Status "Rain radar (RainViewer)", a sources.json record, fixtures and tests.
- Live tab: a ? beside the stream list opens a note about the chosen stream - whose camera it is and where it
  points, how far behind real time the picture runs and what that means against the marker on the map, when it
  goes dark - for Sen's 4K cameras, NASA's HD and cabin feeds, NASA TV and CGTN, with a general note for any
  other stream. Same bubble as the Sky tab's: opens on hover, a click keeps it.
- docs/DEPENDENCIES.md: every library, QML module and program the wallpaper, the widget and the install script
  use, what each optional one is for and what happens without it, and the supply-chain rules (standard library
  plus three optional distro packages; no package manager; nothing downloaded is code; QML never fetches).
- Night mode (Day and night > Night): the terminator as before, the whole map at night always, or at night during
  your own night - civil dusk to dawn at the home place - so the city lights are the picture through the
  evening wherever the sun is.
- Widget: opaque pop-ups. The Sky tab's hour bubble is drawn last over every row with a solid theme colour and
  the event preview bubble has a solid background; a see-through bubble over the map was hard to read.

### Changed
- README as a landing page: the hero picture, one line, badges and a nav line; install in three lines; the map's six
  areas in a grid; the widget, the styles, "Built to be left alone" and "What it is not"; credits folded. The
  reference half (the full feature table, the first-run downloads, where things live, the script, the repository
  layout, troubleshooting) moves to docs/GUIDE.md. The hero is the daylight screenshot until a clip is recorded.
- Widget, Live tab: Sen's 4K Earth view is the default stream (the best picture); NASA's HD stream, its
  inside-and-out stream, NASA TV and CGTN follow in the menu. An empty first answer from a channel page is asked
  again once a few seconds later, and the helper also reads the channel's streams tab, so the tab no longer needs
  a Reload after every install; "nothing live" is kept only a minute. Map controls > Sources gains "Live streams
  (YouTube channel pages)" showing what each page resolved to and how.
- docs/MAINTAINING.md: the map of where every parser lives, what notices a broken source (the daily probe, the
  scheduled fixer, the Status rows) and the routine for fixing one, so the project survives a pause.
- Widget: the Status tab is now a Sources section at the foot of Map controls, next to the chips whose health
  dots come from the same check: one header line with the summary (problems, notes, when checked, refresh),
  opening to the full list on a click and by itself when a source is failing. The tabs are Events, Live, Sky
  and Map controls.
- Air raid alerts redrawn. Edge lights (new default): an oblast under alert has its border glow in the alert
  colour and the imagery inside it - the city lights, the terrain - stays as it is; a new alert breathes
  brightest, a settled one holds a steady edge, part of an oblast is dashed, a long-running one a thin dashed
  edge in its own colour, an ended one a dotted cool edge fading out. Fills remain a choice ("Drawn as"). The
  palette is turned round: red is the alarm - the newest alert the brightest red (#ff3b30), settled alerts a
  steady red (#e03a3a), the frontline's long-running ones ochre (#d68c28, their own colour setting) so a fresh
  alert next to them stands out, all-clear cool blue. A "Default colours" button sets these.
- Widget: a six-hour strip under the Air raid alerts header - one row per oblast under alert in the last six
  hours, a bar for every alert, newest on the right: bright red while on (framed when new or renewed), dull red
  once ended, ochre for the frontline, with how long the current one has been on. The helper keeps a day of
  alert spans per oblast (air-alerts-history.json) and the feed carries the last six hours.
- The settings page has a new shape, the one KDE's own System Settings uses: a sidebar on the left lists every
  layer as one row - its on/off switch, its name and the health of its sources - grouped as Map, Natural events,
  Civil/space/network and Shared, with "Find a setting" above; the right side shows one page at a time. The
  first page, Essentials, holds the handful of choices most people make (style, profile, home place, what part
  of the world is on screen) and says how the data is doing; the layers' own pages are unchanged inside. The
  old collapsible sections, the Layers checklist and Expand/Collapse all are gone - the sidebar is all three.
  Essentials is laid out in labelled sub-sections (Look, Profile, Where you are, On screen, Events widget) with a
  swatch per style to click, and an Events widget card: one button puts the widget on this desktop (through
  plasmashell's scripting interface; helper `widget --add`), the Store link when it is not installed, a tick
  when it is already there.
- The helper is a package: `livemap_helper/` with one module per feed and `common.py` for what they share;
  `livemap-helper.py` stays the entry point, so nothing the layers run has changed. Tests (`tests/`, pytest)
  run every parser against recorded responses and check that config keys, settings aliases, status names,
  `sources.json`, the versions and the changelog agree - they caught a mismatched status name on the first
  run. CI runs ruff, the tests and qmllint beside the existing static checks and the zip; bug and feature
  templates ask for the version and install method.
- NASA FIRMS hotspots come from VIIRS on NOAA-21 (375 m), NOAA-20 as the fallback and MODIS last: Suomi NPP's
  data delivery ends on 2 November 2026 and MODIS collection in 2027. VIIRS confidence letters are mapped and a
  VIIRS detection weighs 0.4 so the cell tiers calibrated on MODIS hold; Status warns when only MODIS
  could be read. Each file is tried on both FIRMS hosts.
- Every request carries an identifiable user agent (`livemap-wallpaper/<version> (github.com/TidyBitz/livemap)`),
  as the APIs ask.
- Wallpaper and widget 0.48.

### Fixed
- A frame rebuilt under the same file name (a new day's picture, a newer classic.jpg) is shown instead of the old one: the
  frame URL carries a build counter as its fragment, so the image cache treats each rebuild as a new picture.
- European burnt areas (EFFIS) answered HTTP 502 to every probe from 25 October to 10 November 2026. Not an
  outage: the WFS's field names are upper case now (FIREDATE, LASTUPDATE, COUNTRY, PROVINCE, COMMUNE, AREA_HA -
  DescribeFeatureType says so), and the filter on the old `firedate` fails inside PostGIS, which the server
  reports as a 502 carrying an ows:ExceptionReport ("FLTApplyFilterToLayer() failed msPostGISLayerWhichShapes():
  Query error"). The filter asks for FIREDATE (197 burnt areas of the last three weeks, 1.3 s, on 10 Nov) and the
  parser reads either case, so a 200 with the old names still parses; a COMMUNE of "N.A." is not a name. Fixture
  from the real answer (three records of October 2026, rings trimmed) and a test. And an HTTP error that comes
  with an OGC ExceptionReport or a titled page now carries the server's words in Status ("HTTP Error 502: Bad
  Gateway - msWFSGetFeature(): ... FLTApplyFilterToLayer() failed"), where "Bad Gateway" alone had the probe
  down as a passing outage for sixteen days.
- The daily source probe found failures on its first two runs but never opened its issue: `gh issue create`
  refuses a label the repository does not have ("could not add label: 'sources' not found"), and the findings
  went with it. The label is now created on first use (and the issue opened without one if that is not
  allowed). The probe also flagged "feed: storm empty" every day: the feed lists storms, volcanoes and GDACS's
  fires and floods from the events memory the wallpaper's own runs build up (first seen, changed), which a
  fresh runner never has, so that kind is no longer judged from the feed - the Storms (GDACS) row is.
- Pulses cost every event on the map, not just the pulsing ones. Each event's ripple ring read the shared clock
  on every tick whether it was pulsing or not - its bindings re-ran thirty to sixty times a second for hundreds
  of quakes, warnings and fires that showed nothing, which on a map with Europe's flood warnings up was most of
  a core on plasmashell's main thread. A ring now reads the clock only while it pulses (a QML binding re-runs
  only for what it last read), so an idle ring costs nothing per tick; every layer with rings.
- Black satellite pictures, third time: the check that rejects a mostly black snapshot was inside the same
  try/except as the Pillow downscaling, whose fallback is "keep the bytes as they came" - so the rejection was
  caught and the black tile kept anyway (Peru, 16 November: the western third of the box not imaged). The check
  is on its own now, its bar is a sixth of the box rather than a third, and a black tile is no longer the end:
  the helper tries the same day from NOAA-21 and Suomi NPP (a granule missing from one satellite's composite is
  usually there on another's), then the day before from NOAA-20, before giving up until the next hour. "Today"
  is asked for from 19:00 solar time, after the afternoon pass has been processed. Tests for all of it.
- A launch that happened while nobody was looking vanished from the list half an hour after T-0 - a Plesetsk
  launch announced the day before, a night launch - so it looked as if it had never been listed. The helper
  now also reads Launch Library's last launches (`/launch/previous/`, same hourly fetch) and the widget lists
  a launch for a day afterwards as "lifted off · success · provider · site" with the outcome in the bubble;
  the map keeps the rocket on its pad for twelve hours, labelled "lift-off 5 h ago". The upcoming page asks
  for 50 launches instead of 20, so a busy week does not push the seventh day off the end.
- Sky tab: the Fetch again button now asks the sources again (`sky --fresh`), not just the helper's 20-minute cache,
  so the ages really return to zero; at most once a minute. Opening the tab and the 20-minute timer keep the cache.
- A launch row with no webcast listed yet opened the raw Launch Library API record (a page of JSON). It now opens
  the webcast when LL2 lists one, else the provider's own page for the launch (SpaceX's, Rocket Lab's), else
  Space Launch Now's page for it, which embeds the webcast once there is one. And the launch list is refreshed
  every quarter of an hour while a launch is inside the next two hours (hourly otherwise), since the webcast
  link usually appears in the last hour.
- The Spotlight highlight's canvas - the whole screen, eleven million pixels on a 5K monitor - was a permanent
  item whatever style was chosen, and repainted itself on every read of the focus file, because with nothing
  highlighted its centre was not a number and "changed" every time: a hundred milliseconds or more of the GUI
  thread per read (every second while the widget was open, every ten seconds otherwise) and an error line in
  the journal each time (`createRadialGradient(): Incorrect arguments`). It now exists only while the spotlight is
  actually showing, paints off the GUI thread, and never paints without a target.
- Widget: the refresh spinner turns on the refresh button itself (Events, and the Sources check) instead of appearing
  beside it and pushing the button sideways while it turns.
- Blank satellite pictures in the bubbles. The Worldview snapshot's date was chosen from the UTC clock: late in
  the evening west of Greenwich the UTC date had already turned, "today" had no pass processed yet, and NASA
  answered a black tile - which the picture cache then kept for a fortnight. The date is now the place's own
  solar date (the afternoon pass is ready from about 17:00 solar time), and a snapshot that was fetched before
  its date's pass could exist is fetched again once it can (`snapshot_premature`). And a snapshot that comes
  back mostly black anyway - near the date line a day's swath arrives last, sometimes a strip of real imagery
  along one edge and nothing else, which no date arithmetic foresees - is not kept at all (`mostly_black`,
  with Pillow): it is asked for again after the usual hour. Tests for all three.
- Widget: a spinner that never stopped. The "busy" flag behind the refresh spinner (and the Status one) cleared
  only when the helper answered; a run cut short by a wallpaper reload or a plasmashell restart never did, and a
  spinner is an animation at the screen's frame rate for as long as it turns - a steady tenth of a core, until
  the widget was removed and added back. Every busy flag now has a watchdog (two minutes for the feed, three
  for the checks) that drops it and says the helper did not answer; spinners only turn while they can be seen.
- Focus file: the wallpaper no longer polls focus.json with a `cat` every 400 ms while the popup is open and
  every 2 s otherwise. A file-system watcher (FocusWatch.qml, Qt.labs.folderlistmodel) says when the widget
  has written it, and only then is it read; a slow safety read remains (every second while open, every 10 s
  otherwise), and on a system without the module the old polling stays. An idle desktop spawns nothing.
- Settings: while the settings window was open, the Imagery banner asked the helper for the frame state every
  2.5 seconds - a Python start each time, inside plasmashell, a steady few percent of a core for as long as the
  window stayed open, which made the wallpaper look busier than it is when measured with the settings up. It
  now asks every 15 s, and every 2.5 s only while a build runs, has just finished, or a frame lever was moved.
- The maritime layer kept the whole map's pulse clock running around the clock: it pulsed every attack of the
  last 24 hours, and UKMTO lists an attack most days, so some ring was always running and the screen was
  redrawn at full rate all day (the other layers pulse only while an event is newly reported, 3 h by default).
  It now pulses an attack for the shared "Newly reported" window (Ageing and pulses) like every other layer;
  the 24 h "fresh" window only sets the mark's size.
- Widget: the ring on the map could stay on an event after the pointer had left the widget. When the list was
  rebuilt under the pointer (a refresh, a launch countdown ticking over, a sort), the hovered row was destroyed
  without reporting the hover's end, so the wallpaper kept ringing it until another row was hovered. The
  pointer leaving the list now clears the focus whatever the rows did, and a row kept under the pointer renews
  the stamp every minute so a long look does not expire either.
- Storms: a GDACS name is "IN-FA-25", the name and a two-digit year, and the name was cut at the first hyphen, so
  Typhoon In-Fa was "In" on the map and in the widget, beside the JTWC record of the same storm as a second
  system. Only the year comes off now, and the two records merge as they should. Beyond the one case: two
  sources' names for a storm are compared leniently (hyphens, spaces, case), the distance within which two
  records count as one storm grows with the time between their fixes (GDACS can be a day behind the centre),
  and any two records from different sources that still sit within reach of each other are reported as a
  possible twin - in Status and in the daily probe - instead of silently drawn twice.
- Widget bubbles: some ShakeMaps and storm charts never finished loading (a spinner for good). The widget was
  fetching each picture itself from the source, with no timeout and no word about what went wrong; the helper
  now fetches them (its user agent, a 12 s timeout, an 8 MB cap, scaled to 1 200 px when pillow is there), keeps
  them under pictures/ for a fortnight and hands the widget a file, a few per feed run. A picture not fetched yet
  is still loaded directly, and past ten seconds the bubble says so; a failure is named ("could not be loaded from
  earthquake.usgs.gov"). Map controls > Sources > "Bubble pictures" counts the kept pictures and names the failures.
  Quakes without a ShakeMap yet are asked again every 20 minutes for a day and a half (a miss used to wait six
  hours, so a fresh quake stayed pictureless), newest first; one that has none shows the satellite's view of the
  place, as storms without a chart do.
- The last notices still drawn in the map's corner - "Live layers off: load guard…", "Animations paused…", "Full
  speed from the widget" - have moved where the others went: the widget's Map controls tab shows the state and
  the reason above the quick settings (with the way out: Full speed, or the thresholds in Performance and power),
  and Settings > Status > Power and load turns amber with the same words. The wallpaper passes the state to the
  helper with its layers (layers.json: saving, why) and the feed carries it to the widget.
- Widget, Live tab: NASA ended its ISS broadcast awQzjn72bI0 on 22 October 2026 and restarted it as ROboUHfPUrU,
  so the tab had shown "Video unavailable" for days. The default now names the new broadcast together with NASA's
  "Space Station Views" playlist (&list=), so the embedded player moves on by itself the next time NASA rotates
  the id; a saved copy of the old default is read as the new one. A channel's /live page (youtube.com/@NASA/live,
  @sen/live) is now embeddable too: the page is read once and its canonical watch link names the broadcast that is
  on now ("Looking for the stream that is on now…", "Nothing live on that channel right now", Reload asks again).
  More streams by default: NASA's inside-and-out stream (M3HKLzjvKPc) and Sen's 4K Earth views. The /live page is
  read by the helper (`live-url`, browser headers, the redirect followed, canonical link or the player's
  "isLiveNow" read, answers kept ten minutes) - the widget's own request got a consent page and said "Nothing live".
- The map imagery was rebuilt at every login, with the toast to say so: the view settles in steps as the desktop
  comes up (the panel appears, the screen scale lands) and each step asked for a frame of its own. A change of
  view now waits until it has held still for a moment, and the toast only appears for a build that takes
  longer than three seconds.
- The same rule for every layer with several sources: one failing among them (EFFIS 502, the Smithsonian 403,
  USGS alert levels) is shown in Status, and the desktop's corner notice only speaks when none of a layer's
  sources answers. The corner is for what needs a hand; Status is the full picture.
- A secondary flood-warning source failing (ECCC answering with something that is not JSON, a MeteoAlarm
  country down) no longer sits in the desktop's corner notice for days: it is a Status matter - the settings'
  Status page and the widget's Map controls > Sources name the source and the error. The desktop hears of it only when no
  official source answers at all.
- Widget: the Map controls tab ends with "This widget" - fade when idle with its opacity, and the preview on
  hover choice - the same settings as the configuration page, in reach.
- Environment Canada's alerts never loaded: the request named the WMS layer (ALERTS) where the WFS wants its own
  type name, ec-msc:Current-Alerts - and the service speaks GML only (every JSON output name is refused). The
  helper now reads the GML 3.2 answer with the same guarded XML parser as the other feeds.
- The NWS flood alerts, MeteoAlarm and GeoNet readers all failed on the desktop with "_http() got an unexpected
  keyword argument 'headers'": the sources that send an Accept header or a key passed it to a fetcher that did
  not take one. The tests had a stand-in fetcher that did, so they passed; the real one takes it now and a test
  compares the two.
- Focus highlight: the Beacon style was drawn with a conical gradient that Plasma's shape renderer filled solid,
  so it showed as an opaque sector; it is built from plain wedges now (a sharp leading line, a fading trail). A
  Ripples style tried at the same time drew nothing on the same renderer and was dropped.

## 0.47 - not tagged; released with 0.48

### Added
- Storms in the western Pacific, the Indian Ocean and the southern hemisphere get what the Atlantic ones had:
  the wind now instead of GDACS's episode peak, the forecast points with their winds, and the best track with
  a wind at every fix - so the track and forecast are coloured by intensity in every basin. Source: the Joint
  Typhoon Warning Center (its RSS, warning texts and ATCF best tracks), merged with GDACS like NHC is, listed as
  a secondary storm source on the Status tab.
- `docs/SOURCES.md`: every data source - what it provides, why it is used, the format ingested, how the helper
  reshapes it, the regular expressions involved, caching and caveats.
- Lakes: outlines in the river colour at the river detail level (the 24 great lakes, or 412 lakes and
  reservoirs), with a fill opacity (0 % for outlines only). Lake names (the great lakes, or every named
  lake) and sea names (the oceans; and the seas; and the gulfs and bays; or everything down to the straits),
  in their own text style - italic by map convention, the river colour or their own, size, bold, capitals,
  spacing, opacity, outline. A name goes only where the water is wide enough for it (a sea's may overhang a
  little, a lake's by half) and after the country names, places and state names, so the great oceans and
  seas label a world view and the small lakes appear as a region is zoomed in. Natural Earth lakes and
  marine polygons; fetched once on first use for installs that downloaded the border data earlier.
- A fourth fit mode, "Fill, true proportions, trimming the edges": Fit without bars. The chosen area at true
  proportions with more map around it where the screen has room, zoomed in only as far as the world's edges
  demand - so a region fills the screen with its surroundings, and the whole world on a 16:10 screen loses
  the middle of the Pacific (on a wide screen, the poles), like a printed map.

### Fixed
- Events widget, "Newest first": the order was the events' own clock, so a launch five days out headed the
  list for being in the future and the satellites sat above everything. The feed now records when this
  computer first saw each event and when it last changed (a launch slipping or entering its last hour, a
  storm's category, a volcano's level), and "newest" is that: the latest news first, whatever the event's
  date. The satellites, in orbit for years, go last in every order; a launch inside its last hour still goes
  to the very top. The NEW badge follows the same clock, so a quake reported late is new when it arrives.
- Rivers at the full (1:50m) level stopped short of the coast when the borders were at the plain (1:110m)
  level - the Amazon 300 km inland, the St. Lawrence at Montreal, the Yangtze, the Ob, the Thames, the Seine,
  69 mouths in all - because Natural Earth's detailed coastline runs up every estuary and its rivers end
  where that coast begins. The helper now carries each such mouth on to the coarse coast: along the 1:110m
  river where one of the same name reaches the sea, otherwise straight ahead to the nearest coast (a
  tributary joins the main river's new reach rather than running beside it). Rivers and borders at the same
  level were never affected.
- `livemap.sh install` run from a source checkout now does `git pull` first, re-runs itself if the script
  changed, and installs the livemap/ and livemap-widget/ folders as they are; it used to install whatever
  livemap.zip lay in the folder, so pulls changed the source while the installed packages stayed put.
  `--no-pull` skips the pull. The zip route is unchanged for releases.
- CPU: the eight event layers each ran their own pulse timer at the profile's rate, unsynchronised, and
  every tick of every timer redrew the whole screen; with storms, floods and fire incidents all pulsing that
  was up to five times the frames the profile asks for (77 % of a core on a 5120 px screen). One clock in
  main.qml now drives every layer's pulses, so the screen is drawn at most the profile's rate. And the Balanced
  profile (and the defaults) now pulse on news only: a hurricane or a red flood that pulsed for its whole life
  kept the screen redrawing 20 times a second for days; with nothing new, the wallpaper is still, and still
  costs nothing. 'Newly reported or significant' remains a choice per layer.

### Added
- Air raid alerts: Ukraine's civil alerts by oblast, under a new "Civil alerts" group. The oblast fills in the
  alert colour while an alert is on and breathes slowly; with a personal alerts.in.ua token (free, requested
  on their site) the layer also knows the alert type (air raid, artillery shelling, street fighting, chemical,
  nuclear), when it started, and alerts on part of an oblast, drawn lighter and labelled with the place;
  without a token it reads a public mirror of the same data, air raid only, oblast level. Every oblast can be
  outlined faintly. Once a minute; off until switched on. The oblast polygons ship with the package (Natural
  Earth, public domain).
  The Events widget lists the oblasts under alert; shelling or fighting counts as severe for the sound.
  `air-alerts --table`.
- Named wildfire incidents with perimeters, from the agencies fighting them: NIFC's interagency perimeters
  (every open US wildfire, with acres, percent contained, personnel, discovery date; prescribed burns left
  out), CWFIS's active-fires list joined to its satellite perimeter estimates (Canada: size, stage of control)
  and EFFIS's burnt areas of the last three weeks (Europe, the Middle East, North Africa). A flame sized by
  area over the perimeter as a faint fill, labelled "Bouquet · 1.0k ac · 35 % contained · 600 personnel · 3 d";
  size and "not yet contained" filters. The wildfire sources are now a set of boxes (GDACS, the three incident
  sources, FIRMS hotspots); the incidents are on and the hotspots off by default, which is what makes the
  layer quiet enough to leave on. The Events widget lists the big or uncontained ones. `incidents --table`.
- Floods, from the same GDACS list as the storms and wildfires: one event per river basin or region, rated
  green / orange / red on the people exposed, drawn as a wave mark in the alert colour with the affected
  districts as a faint fill underneath and a label saying what happened to people (GDACS's Sendai figures:
  dead, evacuated, displaced, rescued) and how long the flood has run. Orange and red only by default -
  GDACS always lists a dozen green basins at seasonal high water - with "All levels" and "Red only" as the
  other choices; the Events widget follows the same filter and keeps a Floods header when there are none. Green
  floods keep the flood colour; orange and red take GDACS's. The usual colour, label, pulse and layer
  opacity controls; `floods --table` from a terminal.
- US flood alerts from the National Weather Service (api.weather.gov, no key) in the same Floods layer,
  minutes after issue: flash flood warnings (red), flood warnings (orange), watches and advisories (green),
  labelled with the counties and when the alert ends, the warning's own polygon or its forecast zones as the
  area (zones fetched once and kept in `nws-zones/`). Looked at every 10 minutes; the flood filter applies
  (warnings only by default). A wet week has an office issue a flood warning per river gauge, so by default
  one office's warnings of a type are one mark, one label and one area ("Flood Warning · 9 counties ·
  Greenville-Spartanburg"), with "Every alert on its own" as the option; flood labels gain "Red only" so the
  text can stay on flash floods. The Events widget lists them with a link. `nws-floods --table [--each]`.
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

## widget 0.47 - not tagged; released with 0.48

### Added
- Floods and air raid alerts as kinds of their own (groups, filters, Hide layers), one row per NWS forecast
  office and alert type, one per oblast under alert with how long it has been on; named fire incidents
  with size, containment or stage of control and personnel.
- A Groups / List toggle in the toolbar: the groups by kind, or one list in the sort order.
- Every kind the map shows keeps its header, saying none or that its source is down.
- The Live tab's placeholder has a "Play here" button; embedding is on by default for new installs.

### Fixed
- The feed's cap no longer counts the long-lived kinds (storms, floods, incidents, alerts), which had pushed
  every earthquake off the list; an empty cached quake file is refetched at once.
- Installed copies are checked against the source and plasmashell's compiled-QML cache is dropped on
  install, so a new build is what runs.

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
