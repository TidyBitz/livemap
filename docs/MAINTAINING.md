# Maintaining Live World Map

The point of this page: the project should survive a pause. Someone (including a future us) who has not touched
it for a year should be able to see what broke, find the line that reads the broken thing, fix it, prove the fix,
and ship it - without re-learning the whole program. This is the map of where everything lives and the routine
that keeps it alive.

## What breaks, and how you find out

Nothing in the wallpaper is computed from the internet except what the sources send, so the things that break are
sources: a feed moves, changes its field names, starts answering with an HTML outage page, or rate-limits. Three
layers notice:

1. **The daily probe** - `.github/workflows/sources.yml` runs `livemap-helper status` and `feed` against the live
   internet every morning (06:17 UTC). A source that errors, or answers but yields no records, opens or updates one
   GitHub issue, "Source probe: a live source is not answering as expected", with the server's own words. The
   issue closes itself when the source is back.
2. **The scheduled fixer** - a scheduled task on the maintainer's claude.ai account runs after the probe and
   turns the issue into a pull request on a `fix/source-probe-<source>` branch (or a comment, when the source
   is merely down). It never touches `main`; a human merges.
3. **On the desktop** - the widget's Map controls › Sources list, the wallpaper's Settings › Status page, and the
   corner notice for the few sources with nowhere else to go, all from the same `status` command. Stale data is
   kept and shown with its age rather than dropped.

## Where things live

```
livemap/contents/helper/livemap_helper/      the Python helper: every source has a module
  common.py     HTTP (_http, fetch_json: names the content type and the server's own error when not JSON),
                units, the data folder (DATA), layers.json (what the wallpaper tells the helper)
  quakes.py  storms.py  fires.py  floods.py  warnings.py  tsunami.py  volcanoes.py  vaac.py  alerts.py
                one source family each: URLs at the top, a fetch_* function, a parse_* function
  space.py passes.py   satellites, crews, launches; ISS/Tiangong passes over home
  maritime.py   UKMTO maritime incidents (the Royal Navy's API behind ukmto.org)
  sky.py        the widget's Sky tab (Open-Meteo, NOAA SWPC)
  radar.py      the Sky tab's rain radar loop (RainViewer tiles over a Natural Earth base)
  live.py       YouTube channel /live pages -> the broadcast on now (the widget's Live tab)
  feed.py       the widget's event list: one record shape for every kind, the facts rows, pictures
  status.py     the Status checks: one chk_* per source, the names the settings and sources.json refer to
  fetch.py      imagery: the monthly maps, GIBS, the frames cut for the screen
  clouds.py borders.py infra.py net.py   the cloud image and its stitched fallback; Natural Earth and PB2002; platforms and refineries; sockets and GeoIP
  coverage.py styles.py power.py widget.py   the coverage matrix from sources.json; saved styles; load guard, battery, layers.json; the widget's install state
  cli.py        every command; `livemap-helper --help` lists them
livemap/contents/data/sources.json            every source once: hazard, regions, cadence, licence, attribution,
                                              the Status check it maps to (the Coverage page and docs/COVERAGE.md are made from it)
livemap/contents/ui/                          the wallpaper (QML); one *Layer.qml per layer, config.qml the settings
livemap-widget/contents/ui/                   the widget: main.qml (Events, Live, Map controls with Sources and This widget), SkyTab.qml,
                                              LiveWeb.qml (the embedded stream); contents/icons/ the kind icons drawn in the theme colour
tests/test_parsers.py  tests/fixtures/        a recorded answer per source and a test that parses it
tests/test_consistency.py                     config keys, settings aliases, status names, sources.json agree
scripts/check.py                              "all good": versions, metadata, geo.js, the consistency checks
```

## The routine when a source breaks

1. Read the probe issue (or the Status row). It quotes what the server answered - an OGC exception, an HTML
   title, "no records" - which usually says what changed.
2. Fetch the source yourself with the helper's own function so you see what it sees:
   `python3 -c "from livemap_helper.common import fetch_json; print(fetch_json('<url>'))"` from
   `livemap/contents/helper/`, or `_http` for non-JSON.
3. Fix the parser in its module. Keep the record shape the feed and the widget rely on (the `kind`, `when`,
   `lat`/`lon`, `title`, `facts` keys); everything downstream reads those, not the source's names.
4. Save the real answer as a fixture under `tests/fixtures/` and make the test in `tests/test_parsers.py` read it:
   the test is what stops the next change from breaking it silently.
5. `python3 scripts/check.py` must say "all good"; the tests must pass (`python3 -m pytest tests/`).
6. A line under Unreleased in CHANGELOG.md, commit, push, install:
   `cd ~/Documents/Projects/livemap && ./livemap.sh install`.

## Parsing rules, learned the hard way

- **Never derive an identity by truncating a string.** GDACS names storms "IN-FA-25"; cutting at the first hyphen
  to drop the year turned Typhoon In-Fa into "In", a second storm beside the JTWC record. Strip only the suffix you
  can name (`re.sub(r"-\d{1,2}$", "", ...)`), keep the source's own string in the record, and compare names
  leniently (`storms.same_name_key`: case, hyphens, spaces and apostrophes do not count).
- **Splitting on a delimiter is fine only when the format defines it** (KML coordinate triples, CAP's "code;
  description"), and then inside a try/except with a fixture that has the odd case.
- **When two sources describe one thing, match by position with time in mind.** Records can be a day apart; the
  reach grows with the age gap (`storms.same_storm_reach`). What still does not merge is reported, not hidden
  (`storms.twins` -> a feed problem -> Status and the daily probe), because a silent duplicate only shows on the map.
- **Every parser has a fixture with the real answer**, and the fixture gets the strange cases as they are met:
  a hyphenated name, an accented place, a missing optional field, an empty list, a 0 that means "none".
- **Downstream reads the record shape, never the source's field names.** `kind`, `when`, `lat`/`lon`, `title`,
  `facts` are the contract; a source change is contained in its module.

## Adding a source

A new source is: a module (or a function in the family's module) with its URL at the top and a parser; a
`chk_*` in status.py and a line in `status_jobs`; a record in `sources.json` naming that check; a fixture and a
test; a line in docs/SOURCES.md. The consistency test will tell you what you forgot.

## Things that look like bugs and are not

- **"Nothing live on that channel"** on the Live tab: YouTube's first answer to a new session sometimes names no
  broadcast; the widget asks again once after a few seconds and the helper tries the channel's streams tab. Map
  controls › Sources › "Live streams" shows what each channel page resolved to.
- **Imagery looks old after a change**: frames are cut once per view and style and cached under the data folder's
  `frames/`; Status › "Map style imagery" lists them; deleting a frame folder forces a rebuild.
- **The widget and the wallpaper never talk directly**: they share files in the data folder. mode.json (the widget's
  Map controls, read by the wallpaper within 20 s); layers.json (the wallpaper's switches, units, the maritime window,
  home, passes, and what it is holding back and why - for the feed and the widget); focus.json (the hovered row,
  written by the widget at most every 120 ms, read by the wallpaper's FocusLayer through a `cat` every 400 ms while
  the popup is open and every 2 s otherwise - Qt 6 refuses file:// XMLHttpRequests in plasmashell); pictures/ and
  pictures.json (fetched by the helper, loaded by the widget as files); sky.json and live-urls.json (the helper's
  caches for the Sky and Live tabs). A new channel between them is another small file, not D-Bus or a shared
  singleton.
- **Auto fit trims the sides on a laptop**: by design - it stretches up to 12 % and crops beyond, so a 16:10 panel
  loses a little of the Pacific instead of squeezing the continents. Essentials > Fit to screen has the other modes.
- **A quake bubble shows a satellite picture, not a ShakeMap**: USGS publishes ShakeMaps only for quakes that were
  felt or above about M5.5; the bubble says it is the satellite's view of the area. A fresh quake is re-asked for
  36 hours.
- **A "possible twin" row in Status (storms)**: two sources describe one storm with records that did not merge
  (names too different, positions too far for their age gap); it is reported rather than hidden so the duplicate
  on the map gets looked at, not missed.
- **Amber or red ages on the Sky tab**: the source's last answer is older than an hour or three; the reason is in
  the ages row when a fetch failed. The data shown is the last good answer, not nothing.
- **Oblasts missing from the air raid layer**: long-running alerts can be hidden by choice until something new
  happens inside the oblast (Air raid alerts > Long-running alerts); the widget's strip still shows them.
- **Settings differ between screens**: Plasma keeps a wallpaper configuration per screen. Styles ("Saved as") are
  shared through the data folder; the rest is per screen by design.

## Libraries

docs/DEPENDENCIES.md lists every library, QML module and program in use and the rules: standard library plus
three optional distro packages, no pip, nothing downloaded is code. A new import goes there first.

## Keys, accounts, licences

None required. Every source is free and key-less by choice; the licences and attributions are in `sources.json`
and shown on the Coverage page. The one optional token is alerts.in.ua's (a free personal one unlocks alert types
and start times; without it the public mirror is read). A source that starts requiring a key is replaced, not keyed.
