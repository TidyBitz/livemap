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
rm -rf "$tmp"
echo "built $out ($(du -h "$out" | cut -f1)) - wallpaper $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' livemap/metadata.json), widget $(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' livemap-widget/metadata.json)"
