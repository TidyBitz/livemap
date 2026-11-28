# Publishing to the KDE Store

The KDE Store (store.kde.org) is what feeds the *Get New Plugins...* button next to **Wallpaper type** and
the *Get New Widgets...* button in *Add Widgets* inside Plasma itself. A listing there puts Live World Map
one click away for every Plasma user; GitHub alone reaches the people who already know to look. This is
the routine, start to finish, and the text to paste.

## The listings, as published (27 November 2026)

- Wallpaper: https://store.kde.org/p/2382950/ - *Plasma 6 Wallpaper Plugins*, "Live World Map"
- Widget: https://store.kde.org/p/2382952/ - *Plasma 6 Applets*, "Live World Map Events"

## Once: the account

1. Create an account at https://store.kde.org (the store is run on OpenDesktop/Pling; one login serves
   store.kde.org, opendesktop.org and pling.com). A free account is all that is needed to publish.
2. Fill in the profile with the GitHub handle and the repository link, so the two can be found from
   each other.

## Each release: the files

Every GitHub release from 0.48 on carries three assets, built by `scripts/package.sh` and attached by CI:

| Asset | What it is | Goes to |
|---|---|---|
| `livemap.zip` | both packages plus `livemap.sh` - the GitHub download the README's install line uses | GitHub only |
| `livemap-wallpaper-<version>.tar.gz` | the wallpaper package alone, `metadata.json` at the archive root | the **wallpaper plugin** listing |
| `livemap-widget-<version>.tar.gz` | the widget package alone | the **widget** listing |

The Store wants one archive per package with `metadata.json` at its root; that is what Plasma hands to
`kpackagetool6` when someone clicks *Install*. `livemap.zip` is not that shape (it holds two packages and a
script) and must not be uploaded to the Store. Download the two tarballs from the release page - do not
rebuild them locally for upload, so what is on the Store is byte-for-byte what is on GitHub.

## Once: the two listings

Two products, because Plasma installs wallpaper plugins and widgets through different categories
(*Plasma 6 Wallpaper Plugins* and *Plasma 6 Applets*). A product form is lost on a reload until it has been saved
once - press *Save* at the foot of page 1 before going on. Tags are limited to five.
Each product has a *Files* tab (upload the tarball, set its version), a *Screenshots* tab, and the
description. Link each listing to the other in its description.

### Product 1 - the wallpaper plugin

- **Category:** Plasma 6 Wallpaper Plugins
- **Title:** Live World Map
- **Version:** the release's (0.48)
- **Licence:** GPLv3
- **Source:** https://github.com/TidyBitz/livemap
- **Tags:** wallpaper, plasma6, map, earthquakes, hurricanes, iss, live, situational-awareness, satellite
- **Screenshots** (from `docs/screenshots/`, in this order - the first is the thumbnail):
  1. `world-day-clouds.webp` - the day side with the live clouds
  2. `europe-night-air-raid.webp`
  3. `world-classic-blue-marble.webp` - storms on their tracks
  4. `settings-essentials.webp` - every layer is a switch
  5. `world-matrix.webp`
  6. `world-time-zones-clouds.webp`
- **Description** (plain text; the Store's editor keeps line breaks):

```
The planet on your desktop. Live. Free. Yours.

A wallpaper for KDE Plasma 6 that shows what the Earth is doing right now - and keeps doing it for months
without asking anything of you.

ON THE MAP
- Earthquakes (USGS and EMSC), volcanoes with alert levels and ash advisories, tsunami bulletins, tectonic plates
- Tropical storms from NHC, JTWC and GDACS with intensity-coloured tracks and a forecast cone for every one
- Wildfires with their perimeters (NIFC, CWFIS, EFFIS) and NASA FIRMS hotspots
- Floods (GDACS) and official flood warnings from the NWS, MeteoAlarm, Environment Canada and the Environment Agency
- Ukraine's air raid alerts by oblast, every minute, as edge lights
- Maritime incidents - attacks, boardings, hijacks, kidnaps - from UKMTO, MDAT-GoG and ReCAAP
- ISS, Hubble and Tiangong on their orbits; the next launches counting down on their pads
- Live clouds from the geostationary satellites, the day/night line, city lights, time zones with their clocks
- Seven map styles, from NASA's seasonal Blue Marble to a Matrix terminal; every colour, size and label yours

BUILT TO BE LEFT ALONE
- Every feed keeps its last good data and shows its age; nothing ever goes blank
- Two sources where one would do; clouds stitched from five satellites when the usual mosaic is down
- A load guard pauses the animation when your CPU or GPU is busy; a plain map on battery
- No keys, no accounts, no telemetry. Every source is free and public; nothing about you leaves the machine

REQUIREMENTS
Plasma 6 and Python 3.9 or newer (already on every Plasma system). Optional: python3-pillow for the regional
frames and the time-zone tint, python3-numpy for the city lights. The first run downloads about 50 MB of maps
and borders; after that the traffic is a few hundred KB an hour.

THE COMPANION WIDGET
"Live World Map Events" lists what the map is showing, newest first, with the facts, the full report and the
satellite's view in a bubble, the ISS live stream, your local weather, air quality, aurora and rain radar.
Get it from Add Widgets or from https://store.kde.org/p/2382952/

NOT A WARNING SYSTEM
Live World Map is for general awareness only. It is not a warning system and no replacement for official alerts: feeds can be delayed, incomplete or unavailable. For anything affecting your safety, rely on your national and local authorities and the original sources.

Full documentation, every source and its licence, and the changelog: https://github.com/TidyBitz/livemap
```

### Product 2 - the widget

- **Category:** Plasma 6 Applets (the Store's name for widgets)
- **Title:** Live World Map Events
- **Version / Licence / Source / Tags:** as above, tags `widget, plasmoid, plasma6, events, iss, weather`
- **Screenshots:** `widget-maritime-bubble.webp`, `widget-storm-bubble.webp`, `widget-iss-crew.webp`,
  `widget-air-raid-strip.webp`, `widget-opaque.webp`, `widget-faded.webp`
- **Description:**

```
The companion widget for the Live World Map wallpaper: the list behind the map.

Four tabs. EVENTS - everything the map is showing, newest first, with NEW / SOON / LIVE tags and a link to
the source for every row; rest the pointer on a row and the event lights up on the map while a bubble carries
the facts, the full report, the satellite's view and - for ships ReCAAP names - the ship's own photograph.
LIVE - Earth from the ISS in 4K, NASA's feeds, launch webcasts. SKY - your weather and the week ahead, air
quality, aurora, sun and moon, tonight's sky, passes over your home, and the last hour of rain radar.
MAP CONTROLS - every layer's switch and every source's health. It fades out of the way when you are not
using it.

It needs the Live World Map wallpaper, which does the fetching:
https://store.kde.org/p/2382950/  -  or from Plasma: Wallpaper type > Get New Plugins...

For general awareness only: not a warning system and no replacement for official alerts - for anything affecting your
safety, rely on your national and local authorities and the original sources.

No keys, no accounts, nothing sent anywhere. GPL-3.0. Documentation and sources:
https://github.com/TidyBitz/livemap
```


## Each release: the update

1. Tag the release on GitHub (`git tag -a vX.Y -m "Live World Map X.Y" && git push origin vX.Y`); wait
   for CI to publish it with the three assets.
2. On each Store product: *Files* > upload the new tarball, set its version to X.Y, remove or leave the
   previous one (leaving one older file is kind to people on older Plasma).
3. Update the product's *Version* field and paste the release's changelog section into the *Changelog*
   tab, trimmed to what a user would notice.
4. Plasma's *Get New Plugins...* dialog shows an *Update* button to everyone who installed from the Store
   within a day or so.

## What a Store install does not do

`livemap.sh install` is not run by a Store install, so three of its jobs do not happen:

- **`doctor`**: nothing checks for Python 3.9+ or the optional packages. The wallpaper still runs; a
  missing Pillow means the Seasonal style and the whole-world views only (no regional frames), a missing
  NumPy means no city lights. Both are listed under Requirements in the description and the wallpaper's
  Status page says which is missing.
- **The plasmashell restart**: the settings page appears after the next login or `plasmashell --replace`;
  the map itself works at once.
- **Removing the pre-0.44 package ids**: only matters for people who installed by hand before 0.44, who
  will have used the script.

Everything else - the helper, the first-run downloads, the widget finding the wallpaper's helper - works
the same, because both are inside the packages.

## Checking a Store install

On a second desktop (or after `livemap.sh remove`): *Wallpaper type* > *Get New Plugins...* > search
"Live World Map" > *Install*; then *Add Widgets* > *Get New Widgets...* > *Download New Plasma Widgets* >
"Live World Map Events" > *Install*. Set the wallpaper, add the widget, open Status. The two should match
`kpackagetool6 -t Plasma/Wallpaper -l` and `-t Plasma/Applet -l` showing `io.github.tidybitz.livemap.wallpaper`
and `io.github.tidybitz.livemap.events`.
