# Data sources

Every feed Live World Map reads, what it gives, why it is the one used, the format that arrives, and what the
helper (`livemap/contents/helper/livemap-helper.py`) turns it into. The wallpaper's QML never fetches anything
itself: it runs the helper, which answers with JSON on stdout, so this file is also the map of the helper.

Conventions that hold for every source:

- HTTPS only; the body is capped (`MAX_BODY`) so a broken or hostile server cannot fill memory; XML is parsed
  with DOCTYPE and ENTITY declarations refused (`safe_xml`); strings that end up on the desktop are rendered as
  plain text. The user agent is `livemap-wallpaper/<version>`.
- `last_good(name, fetch)` wraps each live feed: a successful fetch is cached in `~/.local/share/livemap/last-<name>.json`;
  when the fetch raises, the cached data is returned with its age, and the layer shows a "stale" note after
  the hours set in `StaleHours`. A feed that has never answered gives `(None, None, error)`.
- `remember_events(kind, items, key_of, keep_hours, ...)` keeps per-event memory (`events-<kind>.json`): when
  this computer first saw each event (`first_hours`), whether it has dropped out of the feed (`gone`, kept for
  `keep_hours` so it ages out instead of vanishing), signature changes (`changed_from`, an alert level or a
  storm category) and, for storms, a trail of positions.
- Positions are `lon, lat` in degrees; polylines and rings are flat `[lon, lat, lon, lat, ...]` lists rounded
  to 0.01° (the map is 5 400 px for 360°, so finer is wasted); every line is split at the antimeridian (`_split`).

---

## Base map

### NASA Blue Marble Next Generation (monthly), Black Marble (night)
- **What:** twelve monthly 5 400 × 2 700 px true-colour composites (land, snow, ocean colour) and the 2016
  night-lights composite; the 21 600 px set optionally for regions.
- **Why:** public domain, seasonally correct, the standard whole-Earth picture.
- **Format:** JPEG, downloaded once (`fetch-maps`, `fetch-maps --hires`) to `base/01..12.jpg`, `base/hires01..12.jpg`,
  `night.jpg`. URLs: `assets.science.nasa.gov/content/dam/science/esd/eo/images/...`.
- **Processing:** the month pair for today is blended in the wallpaper (`Seasonal`, `SeasonalBlend`); a region is cut
  from the 21 600 px set when present (`frames/<key>/base.jpg`, key = frame bounds and width).

### NASA GIBS (satellite view, relief and bathymetry)
- **What:** WMS tiles of VIIRS SNPP corrected reflectance (today's satellite picture) and `BlueMarble_ShadedRelief_Bathymetry`.
- **Format:** `image/jpeg` via WMS 1.1.1, EPSG:4326, requested in 2 048 px chunks (`GIBS_CHUNK`) and stitched.
- **Processing:** written under `frames/<key>/`; the satellite image is fetched once per day per frame.

### Natural Earth vectors (coast, borders, rivers, lakes, names, places, time zones)
- **What:** public-domain cartographic vectors at 1:110m and 1:50m (1:10m for places, state label points, time zones).
- **Why:** the only free, consistent, world-wide set with the political lines and names a wallpaper needs.
- **Format:** GeoJSON from `raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/` (`NE_FILES`,
  about 12 MB, `fetch-borders`); the lakes and marine-polygon files are fetched once on first use when an older
  install lacks them.
- **Processing (`cmd_borders`):**
  - `_lines(name, step)`: LineString / MultiLineString / Polygon parts to flat lists, dropping a point closer than
    `step` degrees to the last kept (0.04 for the 1:50m lines, 0.02 for rivers and lakes).
  - `_river_mouths()`: with 1:50m rivers over the 1:110m coast, each river mouth that ends inside the coarse land
    (the 1:50m coast runs up every estuary) is carried on to the 1:110m coast - along the same-named 1:110m river
    where one reaches the sea, otherwise straight ahead to the nearest coast point or to a reach just drawn. A
    name alias map handles `Yangtze → Chang`, `Mackenzie → Peace`.
  - `_names()`: country names from `LABEL_X/LABEL_Y`, ranked by `LABELRANK`; `_state_names()` from the admin-1
    label points; `_places()` from populated places by capital status and population.
  - `_water_names()`: lake names from the lakes file (scalerank 0–1 the great lakes, up to 6 all), sea names from
    `ne_50m_geography_marine_polys` (0 oceans, 1 seas, 2 gulfs and bays, 4 everything; `river` and `reef` classes
    skipped; ALL-CAPS names title-cased). The label sits on the centroid of the biggest polygon, or the widest
    row of water through the shape when that is 25 % wider or the centroid is on land (`_spans_at`); the water's
    width on that row is handed over so the layer can skip a name that would not fit.
  - `_zones()`: time zone polygons with one label per polygon, the offset in force now computed locally.
- **Regular expressions:** `frame_key` strips `[^A-Za-z0-9]` from the variant; none in the parsing.

### PB2002 plate boundaries
- **What:** Peter Bird's 2003 plate boundary model as GeoJSON (Hugo Ahlenius / Nordpil, ODC-By).
- **Format:** `PB2002_boundaries.json` from `raw.githubusercontent.com/fraxen/tectonicplates`, downloaded with the borders.
- **Processing:** `_lines(PLATES_FILE, 0.0)`.

---

## Weather

### Clouds - Matt Eason's live cloud maps (primary)
- **What:** a 4 096 × 2 048 global cloud alpha mask built from EUMETSAT and GOES imagery, refreshed about every 3 h.
- **Format:** PNG with alpha, `clouds.matteason.co.uk/images/4096x2048/clouds-alpha.png?t=<3-hour stamp>`, loaded
  by the wallpaper directly as an `Image`.

### Clouds - stitched fallback (NASA GIBS, EUMETView)
- **What:** the five geostationary views (GOES-East, GOES-West, Himawari via GIBS WMS; Meteosat 0° and IODC via
  EUMETView WMS) stitched into one equirectangular mask when the web image fails or is chosen (`CloudSource`).
- **Format:** WMS `image/png` per satellite; the result `clouds-stitched.png` (2 048 × 1 024 with Pillow,
  1 024 × 512 without).
- **Processing (`stitch_clouds`):** brightness is mapped to alpha between `lo=120` and `hi=235`; each satellite's
  strip is feathered at its edges; the sources that failed are reported in `cloud-state.json` and shown on the
  Status tab.

### Day / night
- Computed locally from the sun's position (`Geo.sun`), no source.

---

## Events

### Earthquakes - USGS Earthquake Hazards Program, with EMSC (`quakes.py`)
- **What:** USGS's summary GeoJSON feeds `2.5_day`, `4.5_day` (default) or `significant_week` (`QuakeFeed`), plus
  the EMSC-CSEM real-time catalogue through its FDSN event service
  (`seismicportal.eu/fdsnws/event/1/query?format=json&minmag=<floor>&start=<window>`), the floor and window
  taken from the USGS feed's name (`FEED_SPAN`).
- **Why:** USGS is the authority for M4.5+ worldwide and everything in the US, minutes after an event; EMSC
  collects the national networks' reports and lists the smaller quakes outside the US that USGS carries late
  or not at all. `QuakeSources` is a mask (1 USGS, 2 EMSC, default both).
- **Format:** USGS GeoJSON (`properties.mag`, `place`, `time` in ms, `url`); EMSC's FDSN JSON (`properties.mag`,
  `magtype`, `time` ISO, `lat`, `lon`, `depth`, `flynn_region`, `unid`), reshaped into USGS's feature shape with
  `source: "EMSC"` and a seismicportal link.
- **Processing (`quakes_cached`, `merge`):** the two lists are merged - an EMSC event within 120 km and 90 s of
  a USGS one is the same quake and USGS's record wins - sorted newest first and cached five minutes in
  `quakes.json` (feed and mask recorded, so a change re-fetches). When one source fails its part comes from the
  cache and the problem is reported; when both fail, the cached list is shown with its age. The quake layer and
  the widget read the same command (`quakes --feed --sources`).

### Tropical storms - GDACS (worldwide)
- **What:** the UN/EU Global Disaster Alert and Coordination System event list, `EVENTS4APP`, filtered to
  `eventtype == "TC"` and `iscurrent == true`.
- **Why:** the one feed that lists every basin; its alert level (green / orange / red) rates the humanitarian impact.
- **Format:** GeoJSON; `properties.eventid`, `eventname`, `alertlevel`, `severitydata.severity` (km/h),
  `severitytext`, `datemodified`, `todate`, `url.geometry` (the episode geometry: past track, forecast, cone).
- **Processing (`fetch_storms`):** one entry per storm even when several episodes are listed; the name is the part
  before the first `-`, title-cased; `storm_kind(wind, lat, lon)` gives the type and Saffir-Simpson category
  (Typhoon north of the equator between 100°E and 180°, Hurricane in the Atlantic / eastern Pacific, Cyclone
  elsewhere; 63 / 119 / 154 / 178 / 209 / 252 km/h thresholds). The episode geometry gives `past`, `forecast`,
  `cone` and `dots`.
- **Caveat the code carries:** GDACS's severity is the storm's *peak* wind over the episode, so the record is
  marked `wind_is_peak: True` and the label says "peak"; the breadcrumb trail records no wind for such a storm.
  A storm's current wind, type and intensity-coloured track come from the centres below.
- **Regular expressions:** the severity text is read for a wind when the number is missing:
  `(\d+)\s*(?:kt\b|knots)`, else `(\d+)\s*mph`, else the first `[\d.]+`.

### Tropical storms - NOAA National Hurricane Center (Atlantic, eastern and central Pacific)
- **What:** `nhc.noaa.gov/CurrentStorms.json` (the active storms with intensity and links), the forecast-track and
  cone KMZ files, and the ATCF best track (b-deck) at `ftp.nhc.noaa.gov/atcf/btk/b<id>.dat`.
- **Why:** the authority for those basins: the wind *now*, a fix every six hours with wind and type, forecast points
  with their winds, the cone of uncertainty.
- **Format:** JSON (`id` like `ep222026`, `name`, `intensity` in knots, `latitudeNumeric`, `longitudeNumeric`,
  `lastUpdate`, `forecastTrack.kmzFile`, `trackCone.kmzFile`); KMZ (zipped KML - `_kml_coords` takes every
  `<coordinates>` list tagged by its geometry, `_kml_placemarks` the point placemarks with whatever intensity
  their text carries); the b-deck is comma-separated ATCF: field 2 `YYYYMMDDHH`, field 4 `BEST`, field 6 lat
  as `203N` (tenths), field 7 lon as `1260E`, field 8 wind in knots, field 10 the type code (`TD TS TY ST TC HU`
  count as tropical - `TROPICAL_TYPES`).
- **Processing (`fetch_storms_nhc`, `nhc_best_track`):** knots × 1.852 to km/h; the record carries `track`
  as `[[lon, lat, wind_kmh, unix_time, tropical], ...]` oldest first, `dots` as `[[lon, lat, wind_kmh], ...]`,
  `forecast` as a split polyline, `cone` as rings.

### Tropical storms - Joint Typhoon Warning Center (western Pacific, Indian Ocean, southern hemisphere)
- **What:** the US Navy's warnings for the basins NHC does not cover. The RSS feed lists the active storms and
  their products; the warning text gives the position and 1-minute wind now and the forecast positions with
  winds; the best track is the ATCF b-deck, read from NCAR/UCAR's real-time tropical cyclone guidance mirror
  (`hurricanes.ral.ucar.edu/realtime/plots/<basin folder>/<year>/<id>/b<id>.dat`, every basin during the
  season; NHC's own ATCF directory carries only al/ep/cp) with JTWC's `products/best-tracks/<year>/<year>s-b<basin>/b<id>.dat`
  as the fallback.
- **Why:** per-fix winds, so these storms get the same intensity-coloured track, current wind and coloured
  forecast as the Atlantic ones instead of a single peak-wind colour.
- **Format:** RSS (`metoc.navy.mil/jtwc/rss/jtwc.rss`), plain-text warnings
  (`metoc.navy.mil/jtwc/products/<basin><nn><yy>web.txt`), ATCF b-deck as above. Basin folders on the UCAR
  mirror: `wp → northwestpacific`, `io → northindian`, `sh → southernhemisphere` (`UCAR_BASIN`).
- **Processing (`fetch_storms_jtwc`, `jtwc_warning`, `jtwc_best_track`):** every product link in the RSS is
  attributed to the storm last named before it; the eastern / central Pacific items (`ep`, `cp`) are skipped
  because NHC feeds those. The storm id is `<basin><nn>20<yy>` (`wp292026`; a southern-hemisphere storm carries
  the season year, `sh022027`). The warning's day/hour/minute times are completed with the current month, moving
  a month back or forward when the day number would land more than 20 days away. Winds knots × 1.852. The
  merge (below) takes JTWC's forecast points over GDACS's because they carry winds.
- **Regular expressions:**
  - storm heads in the RSS: `(Super Typhoon|Typhoon|Hurricane|Tropical Storm|Tropical Depression|Tropical Cyclone|Subtropical Storm)\s+(\d{2}[A-Z])\s*(?:\(([^)]*)\))?`
  - product links: `products/(wp|io|sh|ep|cp)(\d{2})(\d{2})web\.txt`
  - a position line: `(\d{2})(\d{2})(\d{2})Z\s*-+\s*(?:NEAR\s+)?(\d{1,2}\.\d)([NS])\s+(\d{1,3}\.\d)([EW])`
    (the first is the warning position, the rest forecasts; the text is cut at `REMARKS:` because the remarks
    repeat the position without the dashes)
  - the wind after each: `MAX SUSTAINED WINDS\s*-\s*(\d{2,3})\s*KT`

### How the storm feeds are merged (`fetch_storms_merged`)
GDACS is the list; NHC and JTWC records are matched to it by name (lower-cased), or failing that to the nearest
unmatched GDACS storm within 250 km (the feeds rename a storm at different moments: "Twenty-E" becomes "Rachel").
A match takes the centre's wind, type, category, `wind_is_peak: False`, its track / forecast / cone / dots where
GDACS has none, and a `source` of `GDACS+NHC` or `GDACS+JTWC`; an unmatched centre storm is added on its own.
`cmd_storms` then runs `remember_events` with a trail (position and wind every look) and builds `track` from the
best track or, failing that, from the trail; `storm_impacts` works out what each storm crossed.

### Floods - GDACS
- **What:** the same event list, `eventtype == "FL"`, with the Sendai summary (people dead, evacuated,
  displaced) and the affected-area polygons for orange and red events.
- **Format:** GeoJSON; the area polygons from `url.geometry`, thinned (`flood_area`).
- **Processing (`fetch_floods`):** the name has a leading `floods? in ` stripped (`re.sub(r"^floods? in ", "", ..., re.I)`);
  `days` since the event started; green events are hidden by default (`FloodMinLevel`).

### US flood alerts - National Weather Service (api.weather.gov)
- **What:** active alerts of the events `Flash Flood Warning, Flood Warning, Coastal Flood Warning, Flood Watch,
  Flash Flood Watch, Flood Advisory`, `status=actual`.
- **Why:** minutes after issue, with counties, the end time and a polygon; GDACS has nothing at this scale.
- **Format:** GeoJSON (`Accept: application/geo+json`, the user agent names the project as the API asks);
  `properties.event`, `areaDesc` (`;`-separated counties), `senderName` (`NWS <office>`), `onset`, `ends` /
  `expires`, `headline`, `affectedZones` (zone URLs), `geometry` for storm-based warnings.
- **Processing (`fetch_nws_floods`, `group_nws`):** level by event (`NWS_LEVEL`: flash flood warning red, flood
  and coastal flood warnings orange, watches and advisories green); the area is the warning's own polygon, else
  its forecast zones' polygons, fetched at most `NWS_ZONES_PER_RUN = 40` per refresh and cached for good in
  `nws-zones/<id>.json` (the id with `[^A-Za-z0-9]` stripped); the mark sits at the vertex mean of the rings
  (`_ring_centre`). Alerts are grouped per office and event unless `--each`: one item `Flood Warning · 9 counties ·
  Greenville-Spartanburg` with the union of areas (24 rings at most), the earliest onset and the latest end; the
  group id is `nws:` + office and event with `[^A-Za-z0-9]+` collapsed to `-`.
- **Cache:** `last-nws-floods.json`, 10 minutes.

### Tsunami bulletins - tsunami.gov (PTWC, NTWC)
- **What:** the Pacific Tsunami Warning Center (the Pacific, the Caribbean, and threat messages for the Indian
  Ocean and the rest of the world) and the National Tsunami Warning Center (US and Canadian coasts) evaluate
  every large undersea earthquake within minutes: an information statement when no threat is found, else a
  watch, advisory, warning or threat message with the threatened coast.
- **Why:** the one gap no other feed closes - GDACS opens no event for a tsunami threat, and USGS only flags
  that a quake *may* have one.
- **Format:** CAP 1.2 XML at `tsunami.gov/events/xml/PHEBCAP.xml` (PTWC) and `PAAQCAP.xml` (NTWC). **Each file
  holds one message - the centre's latest product of any kind** - so an information statement two hours later
  overwrites a threat message. `info/event` names the level, `parameter`s carry `EventLocationName`,
  `EventPreliminaryMagnitude(Type)`, `EventOriginTime`, `EventDepth`, `EventLatLon`; `area/circle` the epicentre;
  a `resource` links the bulletin's JSON (`segments[]` with breakpoint start/end lat/lon and `category`,
  `alerts.areaList`). The files are XMLDSig-signed (DSA-SHA1); the signature is not verified - TLS is the trust boundary.
- **Processing (`parse_tsunami_cap`, `tsunami_segments`, `fetch_tsunami`):** every message is remembered by
  centre and incident in `tsunami.json` for 36 h; a newer message for the same event replaces the older, and
  one whose level is "information" or a `Cancel` after a threat marks the threat `ended`. Levels: warning /
  threat 3, advisory 2, watch 1, information 0 (`TSUNAMI_LEVELS`, matched as words in the event name). A
  message stays `TSUNAMI_KEEP_HOURS` past its own `expires` (6 h for an information statement, 24 h for a
  threat). Cached 5 minutes (`last-tsunami.json`); the layer asks every 5 minutes.

### Official flood warnings beyond the US (`warnings.py`)
Three sources in the NWS alert's shape, each cached and fetched on its own clock, joined to the flood layer by
the `FloodWarnSources` mask (2 MeteoAlarm, 4 Environment Canada, 8 Environment Agency; NWS is bit 1 via
`FloodNws`) and grouped per office or country and event like the NWS ones.
- **MeteoAlarm** - `feeds.meteoalarm.org/api/v1/warnings/feeds-<country-slug>`, one JSON per country (38 feeds,
  `Accept: */*`), every current warning as a CAP alert with English and local `info`s. Kept: `awareness_type`
  7 coastal event, 10 rain, 12 flooding, 13 rain-flood; `awareness_level` 2 yellow → green tier, 3 orange,
  4 red (1 green is no warning). No geometry: each `areaDesc` is placed on `contents/data/europe-regions.json`
  (Natural Earth 10m admin-1 units and their regions for the 38 countries: normalised names, a centre, rings
  thinned to 0.05°), matched exactly or on the longest shared name start of 5+ characters; unknown areas fall
  back to the country's centre. Licence CC BY 4.0 (EUMETNET). Every 30 minutes.
- **Environment and Climate Change Canada** - GeoMet WFS `typename=ALERTS` as GeoJSON with polygons; kept where
  the headline matches `flood|rainfall|rain\b|storm surge`; level red for a flash flood, orange for a warning,
  green otherwise. Open Government Licence - Canada. Every 15 minutes. (The property names are read
  tolerantly - `headline`, `alert_type`, `area`, `expires`, `url` - and should be confirmed against the live layer.)
- **Environment Agency** - `environment.data.gov.uk/flood-monitoring/id/floods`: `severityLevel` 1 severe (red),
  2 warning (orange), 3 alert (green), 4 no longer in force (dropped); each flood area's polygon is fetched once
  (`EA_AREAS_PER_RUN = 25` per refresh) and kept in `ea-areas/`. OGL v3 with the attribution line the Agency
  requires (in `sources.json`). England only. Every 15 minutes.

### Wildfires - GDACS (worldwide events)
- As for floods with `eventtype == "WF"`; the name has `^(forest )?fires? in ` stripped.

### Wildfires - NIFC WFIGS interagency perimeters (United States)
- **What:** ArcGIS FeatureServer query of `WFIGS_Interagency_Perimeters_Current`, `attr_IncidentTypeCategory = 'WF'`.
- **Format:** GeoJSON with `attr_IncidentName`, `attr_IncidentSize` (acres), `attr_PercentContained`,
  `attr_FireDiscoveryDateTime`, `attr_ModifiedOnDateTime_dt`, `attr_TotalIncidentPersonnel`, `attr_POOState`,
  `attr_POOCounty`, `attr_FireBehaviorGeneral`, `attr_IrwinID`; geometry simplified server-side (`maxAllowableOffset=0.004`).
- **Processing (`fetch_nifc`):** acres × 0.4046856 to hectares; `incidentActive` is under 90 % contained; the
  perimeter rings are thinned and capped.

### Wildfires - CWFIS (Canada)
- **What:** two WFS layers: `cwfif_national_activefires` (the agencies' active fires with stage of control) and
  `m3_polygons_current` (M3 perimeter estimates from satellite hotspots), joined by distance.
- **Format:** GeoJSON; stage codes `OC BH UC EX` → "out of control", "being held", "under control", "out"
  (`CWFIS_STAGE`); `CQL_FILTER` keeps records whose `record_start..record_end` spans now and perimeters with
  `lastdate` in the window.
- **Processing:** a record with no status report for `CWFIS_STALE_DAYS = 14` days is dropped (the agencies leave
  old fires listed).

### Wildfires - EFFIS (Europe, Middle East, North Africa)
- **What:** Copernicus rapid damage assessment burnt areas, `ms:modis.ba.poly`, filtered by `firedate` (an OGC
  `<Filter>` in the URL).
- **Format:** GeoJSON with country, province, commune, hectares, fire date.

### Wildfire hotspots - NASA FIRMS (VIIRS, optional)
- **What:** every active-fire detection of the last 24 h as one CSV: VIIRS on NOAA-21 (`noaa-21-viirs-c2/csv/J2_VIIRS_C2_Global_24h.csv`,
  375 m, NOAA's primary) first, NOAA-20 (`J1_VIIRS_C2_...`) second, MODIS Terra/Aqua (`MODIS_C6_1_Global_24h.csv`)
  last. Each is tried on both FIRMS hosts (`firms.` and `firms2.modaps.eosdis.nasa.gov`). Suomi NPP's delivery
  ends on 2 November 2026 and MODIS collection in 2027, so the order is the order of survival; the Status tab
  warns when only MODIS could be read.
- **Format:** CSV (`latitude, longitude, bright_ti4 / brightness, confidence, frp, acq_date, acq_time, satellite,
  instrument, daynight`); VIIRS rates confidence `l / n / h`, MODIS 0-100.
- **Processing (`cluster_hotspots`):** confidence letters map to 30 / 60 / 90 and detections under 50 are
  ignored; a VIIRS detection counts 0.4 (375 m sees about three where MODIS's 1 km saw one) so the cell tiers
  calibrated on MODIS hold; detections are binned into 0.5° cells with count, summed FRP, the nearest populated
  place (Natural Earth, ≥ 50 000 people) and the cell's recent history (`hotspot-days.json`: which of the last
  30 days it burned) rating each into tiers so a burning season does not cover the map. Cached 3 h; the source
  file's name is kept in `hotspots-source.txt`.

### Volcanoes - Smithsonian Global Volcanism Program
- **What:** three things: the Weekly Volcanic Activity Report feeds (RSS and CAP), the eruption database
  (WFS, `E3WebApp_Eruptions1960` with `ContinuingEruption = 'True'`) for "erupting since", and the weekly
  report web page as a fallback for the report's "new / continuing" classification.
- **Format:** RSS / CAP XML (coordinates looked for as `georss:point "lat lon"`, `geo:lat` + `geo:long`, or
  `cap:circle "lat,lon radius"`, whatever the namespace); WFS JSON; HTML.
- **Processing:** `parse_volcano_feed` takes the title as `name (country)` via `\s*(.+?)\s*\((.+?)\)`, marks an
  entry fresh when `\bnew\b` appears in the title, category or first 160 characters; numbers are pulled with
  `-?\d+(?:\.\d+)?`. The page fallback strips tags (`<[^>]+>`), finds each volcano's chunk and reads
  `\b(New|Continuing|Other)\s+(Eruptive Activity|Observations)` and a date `\b((?:19|20)\d{2}(?: [A-Z][a-z]{2}(?: \d{1,2})?)?)\b`;
  table rows via `<tr[^>]*>(.*?)</tr>` and cells `<t[dh][^>]*>(.*?)</t[dh]>`. Names are matched with accents
  stripped (`_plain`, NFKD) and a trailing ` volcano` removed. The eruption database is cached a day.

### Volcano alert levels - USGS HANS
- **What:** `volcanoes.usgs.gov/hans-public/api/` - the alert level (NORMAL / ADVISORY / WATCH / WARNING) and
  colour code of every US volcano; only elevated ones are shown.
- **Processing:** joined to the Smithsonian entries by plain name; a level above green counts as "raised"
  (`raised_of`) so the mark says how long it has been raised as seen from here.

### Air raid alerts - alerts.in.ua (with a token) or the ubilling.net.ua mirror
- **What:** Ukraine's civil alert status per oblast (and raion / hromada with the API): alert type, start time.
- **Why:** the API gives minute-by-minute data with types and partial alerts but needs a personal token; the
  mirror is public, oblast level, air raid only, and carries no start times - so no duration is invented for it.
- **Format:** JSON. API: `alerts[]` with `location_uid`, `location_title`, `location_type`, `alert_type`,
  `started_at`; mirror: `states{ name: { enabled, enabled_at, type } }`.
- **Processing (`fetch_air_alerts`):** names are matched to ISO 3166-2 codes on a Ukrainian stem (`UA_STEMS`:
  "м. Київ", "Київ" and "Київська область" all land) against the oblast polygons shipped in
  `contents/data/ukraine-regions.json` (Natural Earth 10m admin-1, thinned). Memory (`air-alerts.json`) keeps
  known starts, first-seen times and ended alerts (`_cleared`, listed as "all clear" for `AIR_CLEAR_MINUTES = 30`).
  Statuses: `A` active, `P` partial, `N` none, `C` cleared.

### Launches - The Space Devs, Launch Library 2
- **What:** `ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=20`, free, 15 requests an hour; cached an hour.
- **Format:** JSON; `net`, `name`, `rocket.configuration.full_name`, `mission.name`, `launch_service_provider`,
  `pad.latitude/longitude`, `pad.location.name`, `status`, `vidURLs[]`, `webcast_live`.
- **Processing:** the rocket is `rocket.configuration.full_name`; the mission name has a trailing parenthesis
  dropped (`\s*\(.*?\)\s*$`) and is split on `,\s*` so repeated payloads collapse ("Owlright, Owlright,
  Owlright" → "Owlright ×3"); only `https://` video links are kept (four at most, by the library's priority);
  `level` rises in the last hour and the last 15 minutes.

### ISS, Hubble, Tiangong - CelesTrak
- **What:** two-line elements by catalogue number (`25544`, `20580`, `48274`), refreshed every 6 h (`tle.json`).
- **Format:** TLE text.
- **Processing:** propagated locally with the secular part of SGP4 (J2 nodal and apsidal precession, mean-motion
  correction; no drag or short-period terms) - within a few km of the full model for elements under a day old,
  under a pixel on this map; the position is updated every second by the wallpaper.

### Oil and gas infrastructure (optional)
- **What:** BSEE's platform structures shapefile (US Gulf of Mexico, public domain) and OpenStreetMap
  `man_made=offshore_platform` and `industrial=refinery` via the Overpass API (ODbL), the world queried in seven
  longitude bands because one global query times out.
- **Format:** zipped shapefile; Overpass JSON. Downloaded on demand to `infrastructure.json`.

### Network (optional, off by default)
- **What:** this machine's sockets (`ss -Htunpi state connected`) geolocated with the DB-IP City Lite MMDB (CC BY 4.0, downloaded
  once, `fetch-geoip`); nothing leaves the computer.
- **Regular expressions:** `\brtt:([\d.]+)/` for the round-trip time, `\(\("([^"]+)"` for the process name,
  `\s*\(.*?\)` to drop a district from a city name.

---

## Status checks

`livemap-helper status` runs one check per source (`chk_*`) and the Status tab shows them with a dot: green all
answering, orange some of a section's sources failing, red none. The Events widget's "source not answering"
line comes from the same problems list the feeds carry.
