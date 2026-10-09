# Security

Live World Map runs as your user, inside plasmashell, and fetches public data over HTTPS. There is no
server side and nothing is sent anywhere; the only data about you is the Network layer, which is off by
default and never leaves your machine.

## What is in scope

- The helper (`livemap/contents/helper/livemap-helper.py`): parsing of every feed it fetches (USGS, GDACS,
  NHC, Smithsonian, FIRMS, CelesTrak, Launch Library, cloud imagery, Natural Earth, PB2002, DB-IP). Feeds are
  size-capped, parsed as data and never executed; XML with DOCTYPE or entities is refused; every string handed
  to the wallpaper passes a filter (printable characters, no `<` / `>`, 160 characters, `https://` links only).
- The wallpaper and widget QML: anything that could make a feed string render as rich text, open a non-web
  link, or reach a shell (the player command only ever receives a validated URL).
- `livemap.sh`: it installs into your home directory only and never needs root.

A way for a feed, a crafted file in the data folder, or a malicious URL to break any of those is a security
issue.

## Reporting

Use GitHub's private vulnerability reporting on this repository (Security tab > Report a vulnerability)
rather than a public issue. You will get a reply within a week. There is no bug bounty; credit in the
changelog if you want it.

## Supported versions

The latest release only. `livemap.sh install` updates in place.
