#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Static checks for the wallpaper and widget, run by CI and before every release.

  - the Python helper parses
  - every <entry> in the wallpaper's main.xml has a cfg_ alias in config.qml, and every cfg_ alias has an entry
  - every cfg.<Key> read anywhere in the QML exists in main.xml
  - brackets balance in every QML file (a rough check that catches most editing slips)
  - no duplicate ids inside one QML file, and no property named after a reserved Item property
  - the versions agree: metadata.json, the helper's VERSION, and main.qml's log lines
  - geo.js loads under node (when node is present)

Exit status 1 on any problem, so CI fails.
"""
import ast
import collections
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WP = os.path.join(ROOT, "livemap")
WG = os.path.join(ROOT, "livemap-widget")
RESERVED = ("layer", "clip", "states", "data", "status", "scale", "source", "spacing", "state", "parent",
            "children", "enabled", "visible", "width", "height", "x", "y", "z", "opacity", "anchors")
problems = []


def problem(msg):
    problems.append(msg)
    print("  ✗ " + msg)


def strip_code(s):
    """QML with comments, strings and regex literals removed, for bracket counting."""
    s = s.replace("\\/", "").replace("\\'", "").replace('\\"', "")      # escaped slashes and quotes inside regex literals
    s = re.sub(r"\.replace\(/[^\n]*?/[gimsuy]*,", ".replace(", s)       # .replace(/regex/, ...)
    s = re.sub(r"/\^[^\n]*?/\.test", "", s)                             # /^regex/.test(
    return re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', "", s, flags=re.S)


def check_python():
    p = os.path.join(WP, "contents", "helper", "livemap-helper.py")
    try:
        ast.parse(open(p, encoding="utf-8").read())
        print("  ✓ helper parses")
    except SyntaxError as e:
        problem("helper: %s" % e)


def check_schema(pkg, label):
    xml = open(os.path.join(pkg, "contents", "config", "main.xml"), encoding="utf-8").read()
    schema = set(re.findall(r'<entry name="(\w+)"', xml))
    cfgs = glob.glob(os.path.join(pkg, "contents", "ui", "config*.qml")) + glob.glob(os.path.join(pkg, "contents", "config", "*.qml"))
    aliases = set()
    for f in cfgs:
        s = open(f, encoding="utf-8").read()
        aliases |= set(re.findall(r"property (?:alias|int|real|bool|string|var|color) cfg_(\w+)", s))
    reads = set()
    for f in glob.glob(os.path.join(pkg, "contents", "ui", "*.qml")):
        reads |= set(re.findall(r"\bcfg\.(\w+)", open(f, encoding="utf-8").read()))
        reads |= set(re.findall(r"\bconfiguration\.(\w+)", open(f, encoding="utf-8").read()))
    for k in sorted(schema - aliases):
        if pkg == WP:
            problem("%s: setting %s has no cfg_%s in config.qml" % (label, k, k))
    for k in sorted(aliases - schema):
        problem("%s: cfg_%s in config.qml has no <entry> in main.xml" % (label, k))
    for k in sorted(reads - schema):
        problem("%s: cfg.%s is read but not in main.xml" % (label, k))
    print("  ✓ %s: %d settings, %d aliases, %d read" % (label, len(schema), len(aliases), len(reads)))


def check_qml(pkg, label):
    for f in sorted(glob.glob(os.path.join(pkg, "contents", "**", "*.qml"), recursive=True)):
        name = os.path.relpath(f, ROOT)
        s = open(f, encoding="utf-8").read()
        s2 = strip_code(s)
        for a, b in ("{}", "()", "[]"):
            if s2.count(a) != s2.count(b):
                problem("%s: unbalanced %s%s (%d vs %d)" % (name, a, b, s2.count(a), s2.count(b)))
        ids = re.findall(r"\bid:\s*(\w+)", s)
        for k, n in collections.Counter(ids).items():
            if n > 1:
                problem("%s: id %s used %d times" % (name, k, n))
        for m in re.finditer(r"\bproperty \w+ (\w+)", s):
            if m.group(1) in RESERVED:
                problem("%s: property named '%s' shadows an Item property" % (name, m.group(1)))
    print("  ✓ %s: QML brackets, ids and property names" % label)


def check_versions():
    meta = re.search(r'"Version": *"([^"]+)"', open(os.path.join(WP, "metadata.json"), encoding="utf-8").read()).group(1)
    helper = re.search(r'^VERSION = "([^"]+)"', open(os.path.join(WP, "contents", "helper", "livemap-helper.py"), encoding="utf-8").read(), re.M).group(1)
    main = set(re.findall(r"livemap:? (\d+\.\d+)[: ]", open(os.path.join(WP, "contents", "ui", "main.qml"), encoding="utf-8").read()))
    if helper != meta:
        problem("helper VERSION %s != metadata %s" % (helper, meta))
    if main and main != {meta}:
        problem("main.qml mentions %s, metadata says %s" % (sorted(main), meta))
    wmeta = re.search(r'"Version": *"([^"]+)"', open(os.path.join(WG, "metadata.json"), encoding="utf-8").read()).group(1)
    log = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    if ("## %s " % meta) not in log:
        problem("CHANGELOG.md has no entry for wallpaper %s" % meta)
    if ("## widget %s " % wmeta) not in log:
        problem("CHANGELOG.md has no entry for widget %s" % wmeta)
    print("  ✓ versions: wallpaper %s, widget %s" % (meta, wmeta))


def check_geojs():
    if not shutil.which("node"):
        print("  - geo.js: node not present, skipped")
        return
    src = open(os.path.join(WP, "contents", "ui", "geo.js"), encoding="utf-8").read()
    src = re.sub(r"^\.pragma.*$", "", src, flags=re.M)
    r = subprocess.run(["node", "-e", src + "\nif (typeof spanText !== 'function') throw new Error('spanText missing');"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        problem("geo.js: %s" % r.stderr.strip().splitlines()[-1])
    else:
        print("  ✓ geo.js loads under node")


if __name__ == "__main__":
    print("livemap checks")
    check_python()
    check_schema(WP, "wallpaper")
    check_schema(WG, "widget")
    check_qml(WP, "wallpaper")
    check_qml(WG, "widget")
    check_versions()
    check_geojs()
    if problems:
        print("%d problem(s)" % len(problems))
        sys.exit(1)
    print("all good")
