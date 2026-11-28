#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds livemap.zip - the download that livemap.sh installs - from this checkout.
#   livemap/          the wallpaper package (livemap.sh, CHANGELOG.md and LICENSE copied in, so the installed
#                     package carries them)
#   livemap-widget/   the companion widget package
#   livemap.sh, CHANGELOG.md, LICENSE
set -eu
cd "$(dirname "$0")/.."
python3 scripts/check.py
out="${1:-livemap.zip}"; case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
tmp="$(mktemp -d)"
cp -r livemap livemap-widget "$tmp/"
cp livemap.sh CHANGELOG.md LICENSE "$tmp/livemap/"
cp LICENSE "$tmp/livemap-widget/"
cp livemap.sh CHANGELOG.md LICENSE "$tmp/"
find "$tmp" -name __pycache__ -prune -exec rm -rf {} +
rm -f "$out"
(cd "$tmp" && zip -qr "$out" livemap livemap-widget livemap.sh CHANGELOG.md LICENSE)
# the KDE Store wants one archive per package, with metadata.json at the archive's root (what "Get New
# Plugins..." / "Get New Widgets..." hand to kpackagetool6): livemap-wallpaper-<v>.tar.gz and livemap-widget-<v>.tar.gz
wv="$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' livemap/metadata.json)"
ww="$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' livemap-widget/metadata.json)"
dir="$(dirname "$out")"
rm -f "$dir/livemap-wallpaper-$wv.tar.gz" "$dir/livemap-widget-$ww.tar.gz"
# the Store copies carry the package and its LICENSE only: no changelog (it is on GitHub, and the Store has its own
# changelog tab) and no livemap.sh (a Store install is kpackagetool's job)
rm -f "$tmp/livemap/CHANGELOG.md" "$tmp/livemap/livemap.sh"
tar -czf "$dir/livemap-wallpaper-$wv.tar.gz" -C "$tmp/livemap" .
tar -czf "$dir/livemap-widget-$ww.tar.gz" -C "$tmp/livemap-widget" .
rm -rf "$tmp"
echo "built $dir/livemap-wallpaper-$wv.tar.gz and $dir/livemap-widget-$ww.tar.gz (the KDE Store uploads)"
echo "built $out ($(du -h "$out" | cut -f1)) - wallpaper $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' livemap/metadata.json), widget $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' livemap-widget/metadata.json)"
