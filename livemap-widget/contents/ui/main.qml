// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 tidybitz
/*
 * Live World Map Events: a panel or desktop widget that lists the newest events the wallpaper tracks
 * (earthquakes, storms, floods, volcanoes, wildfires, launches, satellites), each opening its source in the
 * browser, plus quick controls for the map. It reuses the wallpaper's helper script and caches: nothing
 * is fetched twice. The controls write mode.json in the data folder; the wallpaper reads it within 20 s.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // The wallpaper's helper, wherever kpackagetool put the wallpaper: the user's data dir first, then the
    // system one. The executable engine runs through a shell, so the lookup is a shell one-liner.
    readonly property string helperShell: 'f="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/io.github.tidybitz.livemap.wallpaper/contents/helper/livemap-helper.py"; '
        + '[ -f "$f" ] || f=/usr/share/plasma/wallpapers/io.github.tidybitz.livemap.wallpaper/contents/helper/livemap-helper.py; '
        + '[ -f "$f" ] || { echo "helper not found: install the Live World Map wallpaper first" >&2; exit 3; }; python3 "$f" '
    readonly property string helper: "wallpaper's livemap-helper.py"
    property var items: []
    property var problems: []
    property string version: ""
    property string problem: ""
    property bool busy: false
    property var mode: ({})
    property int unread: 0
    property var checks: []                       // from `livemap-helper status`, for the Sources section of Map controls and the chips' dots
    property string statusVersion: ""
    property real statusAt: 0
    property bool statusBusy: false
    property string statusProblem: ""
    property real lastSeen: 0                     // newest event time the user has looked at
    readonly property string feedName: Plasmoid.configuration.QuakeFeed || "4.5_day"

    readonly property var kindIcon: ({ quake: "◎", storm: "☁", volcano: "△", fire: "♦", flood: "≋", tsunami: "〰", alert: "⚠", launch: "↑", sat: "◆" })   // text fallbacks
    function kindIconUrl(kind) { return kind === "fire" || kind === "sat" ? Qt.resolvedUrl("../icons/" + kind + ".svg") : "" }   // icons/<kind>.svg, drawn as a mask; the rest keep their glyph
    readonly property var kindName: ({ quake: "Earthquake", storm: "Storm", volcano: "Volcano", fire: "Wildfire", flood: "Flood", tsunami: "Tsunami", alert: "Air raid alert", launch: "Launch", sat: "Satellite" })
    // the Map controls chips: each live layer with the Status names of its sources (the same the wallpaper uses)
    readonly property var layerChips: [
        { layer: "quakes", name: "Earthquakes", sources: ["Earthquake feed (USGS)", "Earthquakes, secondary (EMSC)"] },
        { layer: "volcanoes", name: "Volcanoes", sources: ["Volcanoes (Smithsonian / USGS)", "Eruption database (Smithsonian)", "Weekly report page (Smithsonian)", "Volcano alert levels (USGS)", "Volcano alert levels (GeoNet)", "Volcano alert levels (JMA)", "Ash advisories (Washington VAAC)"] },
        { layer: "storms", name: "Storms", sources: ["Storms (GDACS)", "Storms, secondary (NHC)", "Storms, secondary (JTWC)"] },
        { layer: "fires", name: "Wildfires", sources: ["Wildfires (GDACS)", "US fire incidents (NIFC)", "Canadian fires (CWFIS)", "European burnt areas (EFFIS)", "Fire hotspots (NASA FIRMS)"] },
        { layer: "floods", name: "Floods", sources: ["Floods (GDACS)", "US flood alerts (NWS)", "European warnings (MeteoAlarm)", "Canadian alerts (Environment Canada)", "England flood warnings (Environment Agency)"] },
        { layer: "tsunami", name: "Tsunami", sources: ["Tsunami bulletins (PTWC / NTWC)"] },
        { layer: "alerts", name: "Air raid alerts", sources: ["Air raid alerts (alerts.in.ua)"] },
        { layer: "sats", name: "Satellites", sources: ["Satellite elements (CelesTrak)"] },
        { layer: "launches", name: "Launches", sources: ["Launches (The Space Devs)"] },
        { layer: "network", name: "Network", sources: ["Connections (ss)", "GeoIP database (DB-IP)"] } ]
    function layerHealth(layer) {                 // "", ok, warn or error: the worst of the layer's sources in the last status check
        var chip = layerChips.find(function (c) { return c.layer === layer; });
        if (!chip || checks.length === 0) return "";
        var ok = 0, bad = 0, warn = 0;
        for (var i = 0; i < chip.sources.length; i++) {
            var c = checks.find(function (x) { return x.name === chip.sources[i]; });
            if (!c) continue;
            if (c.state === "error") bad++; else if (c.state === "warn") warn++; else ok++;
        }
        if (ok + bad + warn === 0) return "";
        if (bad > 0) return ok > 0 ? "warn" : "error";
        return warn > 0 ? "warn" : "ok";
    }
    readonly property var layerOf: ({ quake: "quakes", storm: "storms", volcano: "volcanoes", fire: "fires", flood: "floods", tsunami: "tsunami", alert: "alerts", launch: "launches", sat: "sats" })
    property var layers: null                     // the event layers the wallpaper shows (layers.json via the feed); null until it has said
    property int saving: 0                        // what the wallpaper holds back: 0 nothing, 1 animations paused, 2 live layers off
    property string savingWhy: ""                 // and why: "load guard: CPU 63 %, GPU ?", "on battery", "paused from the widget"
    readonly property string savingText: saving === 0 ? "" : (saving === 2 ? "Live layers off on the map" : "Animations paused on the map") + (savingWhy ? " \u00b7 " + savingWhy : "")
    property var alertStrip: ({ hours: 6, rows: [] })   // the air raid alerts of the last hours, one row per oblast (the strip under the group header)
    property var ages: ({})                       // minutes since each kind's source was last read: "as of", so an empty kind says whether it was reached
    function asOf(k) { var m = ages[k]; return m === undefined ? "no data yet" : m < 1.5 ? "as of now" : m < 90 ? "as of " + Math.round(m) + " min ago" : "as of " + (m / 60).toFixed(m < 600 ? 1 : 0) + " h ago"; }
    function wanted(kind) {
        var c = Plasmoid.configuration;
        var own = kind === "quake" ? c.ShowQuakes : kind === "volcano" ? c.ShowVolcanoes : kind === "storm" ? c.ShowStorms
                : kind === "fire" ? c.ShowFires : kind === "flood" ? c.ShowFloods : kind === "tsunami" ? c.ShowTsunami : kind === "alert" ? c.ShowAlerts : kind === "launch" ? c.ShowLaunches : kind === "sat" ? c.ShowSats : true;
        if (!own) return false;
        if (c.FollowMap && layers !== null && layerOf[kind]) return layers.indexOf(layerOf[kind]) >= 0;   // only what the map shows
        return true;
    }
    // ---- notification sound: one per refresh, for a severe event arriving or a launch in its last minutes ----
    property var alerted: ({})                    // keys already sounded for (or on the list when the widget started)
    property bool primed: false
    function soundCommand() {
        var c = Plasmoid.configuration, id = c.Sound || "none";
        var f = id === "custom" ? String(c.SoundFile || "").trim() : String(Qt.resolvedUrl("../sounds/" + id + ".wav")).replace(/^file:\/\//, "");
        if (id === "none" || !/^(pop|chime|zing|custom)$/.test(id) || f === "") return "";
        var q = "'" + f.replace(/'/g, "'\\''") + "'";
        return "f=" + q + "; pw-play \"$f\" 2>/dev/null || paplay \"$f\" 2>/dev/null || aplay -q \"$f\" 2>/dev/null";
    }
    function alertKeys() {
        var c = Plasmoid.configuration, out = [], mins = Math.max(1, c.SoundLaunchMinutes || 15) * 60;
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (it.pin || !wanted(it.kind)) continue;
            if (c.SoundSevere && !it.future && (it.level || 0) >= 3 && isNew(it)) out.push(it.key || (it.kind + ":" + it.when));
            if (c.SoundLaunch && it.future && it.when - nowSec <= mins && it.when - nowSec > -120) out.push("soon:" + (it.key || it.when));
        }
        return out;
    }
    function alertCheck() {
        var keys = alertKeys(), fresh = false, seen = alerted;
        for (var i = 0; i < keys.length; i++) {
            if (!seen[keys[i]]) { seen[keys[i]] = true; fresh = true; }
        }
        alerted = seen;
        if (!primed) { primed = true; return; }     // what was there when the widget started is not news
        var cmd = soundCommand();
        if (fresh && cmd !== "") exec.connectSource(cmd + " # " + Date.now());
    }
    readonly property int sortMode: Plasmoid.configuration.SortMode      // 0 newest, 1 severity, 2 kind, 3 soonest launch
    // Past events: 0 live (what is on the map now), 1 past 24 h, 2 past 7 days, 3 past 30 days, 4 custom dates.
    // Answered from the helper's history.json, which keeps everything the feed has shown for 90 days.
    property int range: 0
    property var pastItems: []
    property bool pastBusy: false
    property real historyFrom: 0
    property string fromText: ""                  // custom range, "YYYY-MM-DD"
    property string toText: ""
    function parseDay(t, endOfDay) {
        var m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(String(t).trim());
        if (!m) return NaN;
        var d = new Date(+m[1], +m[2] - 1, +m[3], endOfDay ? 23 : 0, endOfDay ? 59 : 0, endOfDay ? 59 : 0);
        return d.getTime() / 1000;
    }
    readonly property real rangeSince: range === 1 ? nowSec - 86400 : range === 2 ? nowSec - 7 * 86400 : range === 3 ? nowSec - 30 * 86400
                                     : range === 4 ? parseDay(fromText, false) : 0
    readonly property real rangeUntil: range === 4 ? parseDay(toText, true) : nowSec
    readonly property bool rangeValid: range < 4 || (!isNaN(rangeSince) && !isNaN(rangeUntil) && rangeSince <= rangeUntil)
    function refreshPast() {
        if (range === 0 || !rangeValid) return;
        pastBusy = true;
        exec.connectSource(helperShell + "feed --feed " + feedName + " --limit 500 --since " + Math.floor(rangeSince) + " --until " + Math.ceil(rangeUntil) + " # " + Date.now());
    }
    onRangeChanged: { pastItems = []; refreshPast(); }
    readonly property real newSeconds: Math.max(1, Plasmoid.configuration.NewMinutes) * 60
    property real nowSec: Date.now() / 1000
    // Links come from the feeds: only plain web links are ever handed to the browser or a player.
    function webUrl(u) { u = String(u || "").trim(); return /^https?:\/\/[^\s'"<>]+$/.test(u) ? u : "" }
    function openWeb(u) { u = webUrl(u); if (u !== "") Qt.openUrlExternally(u) }
    // a launch slides into its last minutes between two refreshes: look again every minute, no helper call
    Timer { interval: 60000; running: Plasmoid.configuration.SoundLaunch && (Plasmoid.configuration.Sound || "none") !== "none"; repeat: true
            onTriggered: { root.nowSec = Date.now() / 1000; root.alertCheck(); } }
    Timer { interval: 30000; running: root.expanded; repeat: true; onTriggered: {
        root.nowSec = Date.now() / 1000;
        if (root.mode.full && root.mode.full_until && root.nowSec >= root.mode.full_until) root.refreshMode();   // the helper drops a timed full-speed override when it is over
    } }
    // new: first seen by this computer within the window (a quake reported late is news when it arrives)
    function isNew(it) { return !it.pin && !it.future && !it.nonew && root.nowSec - (it.seen || it.when) < root.newSeconds }
    function isSoon(it) { return !!it.future && it.when - root.nowSec < 3600 && it.when - root.nowSec > -1800 }
    readonly property var kindOrder: ({ tsunami: 0, alert: 1, launch: 2, storm: 3, flood: 4, volcano: 5, quake: 6, fire: 7, sat: 8 })
    readonly property var shown: (function () {
        var list = (range > 0 ? pastItems : items).filter(function (it) { return wanted(it.kind); });
        var mode = sortMode;
        // "newest" is news, not the event's clock: when this computer first saw the event or its latest change
        // (a launch slipping or entering its last hour, a storm's category) - the helper's `updated`, so a
        // launch five days out does not head the list for being in the future
        function news(it) { return it.updated || it.seen || it.when; }
        list.sort(function (a, b) {
            // whatever the order, a launch inside its last hour goes to the very top; the pinned satellites,
            // in orbit for years and never news, go last
            var sa = isSoon(a) ? 0 : a.pin ? 2 : 1, sb = isSoon(b) ? 0 : b.pin ? 2 : 1;
            if (sa !== sb) return sa - sb;
            if (mode === 1) { if ((b.level || 0) !== (a.level || 0)) return (b.level || 0) - (a.level || 0); return news(b) - news(a); }
            if (mode === 2) { var ka = kindOrder[a.kind] || 9, kb = kindOrder[b.kind] || 9; if (ka !== kb) return ka - kb; return news(b) - news(a); }
            if (mode === 3) { var fa = a.future ? 0 : 1, fb = b.future ? 0 : 1; if (fa !== fb) return fa - fb; return a.future ? a.when - b.when : news(b) - news(a); }
            return news(b) - news(a) || b.when - a.when;
        });
        return list;
    })()
    // ---- groups: one collapsible block per kind, with a count and the one fact that matters ----------------
    readonly property bool grouped: Plasmoid.configuration.Grouped
    readonly property var kindPlural: ({ tsunami: "Tsunami bulletins", alert: "Air raid alerts", launch: "Launches", storm: "Storms", flood: "Floods", volcano: "Volcanoes", quake: "Earthquakes", fire: "Wildfires", sat: "Satellites" })
    property var closed: ({})                     // kinds folded away, by the user; the header stays
    readonly property var kindList: ["tsunami", "alert", "launch", "storm", "flood", "volcano", "quake", "fire", "sat"]
    function toggleKind(k) { var c = Object.assign({}, closed); if (c[k]) delete c[k]; else c[k] = true; closed = c; }
    readonly property bool anyOpen: rows.some(function (r) { return r.head && r.open; })
    function toggleAll() {
        var c = {};
        if (anyOpen) for (var i = 0; i < kindList.length; i++) c[kindList[i]] = true;
        closed = c;
    }
    // kinds the widget's own boxes want but the map has switched off (with "only the kinds the wallpaper shows")
    readonly property var hiddenKinds: (function () {
        var src = range > 0 ? pastItems : items, out = {};
        for (var i = 0; i < src.length; i++) {
            var k = src[i].kind, c = Plasmoid.configuration;
            var own = k === "quake" ? c.ShowQuakes : k === "volcano" ? c.ShowVolcanoes : k === "storm" ? c.ShowStorms : k === "fire" ? c.ShowFires : k === "flood" ? c.ShowFloods : k === "tsunami" ? c.ShowTsunami : k === "alert" ? c.ShowAlerts : k === "launch" ? c.ShowLaunches : k === "sat" ? c.ShowSats : true;
            if (own && !wanted(k)) out[k] = (out[k] || 0) + 1;
        }
        return Object.keys(out).map(function (k) { return { kind: k, count: out[k] }; });
    })()
    readonly property var problemWords: ({ quake: "quakes", storm: "storms", volcano: "volcano", fire: "fire", flood: "flood", tsunami: "tsunami", alert: "air alerts", launch: "launch", sat: "sat" })
    function emptyFact(k) {
        var w = problemWords[k] || k, p = problems.find(function (t) { return String(t).toLowerCase().indexOf(w) === 0; });
        return p ? "source not answering" : (k === "flood" ? "none at the map's level" : "none right now") + (ages[k] !== undefined ? " \u00b7 " + asOf(k) : " \u00b7 no data yet");
    }
    function kindFact(k, list) {
        if (list.length === 0) return emptyFact(k);
        if (k === "launch") { var next = list.filter(function (it) { return it.future && it.when > nowSec; }).sort(function (a, b) { return a.when - b.when; })[0]; return next ? "next " + ago(next.when) : ""; }
        if (k === "quake") { var top = 0; for (var i = 0; i < list.length; i++) { var m = parseFloat(String(list[i].title).replace(/^M/, "")); if (m > top) top = m; } return top > 0 ? "strongest M" + top.toFixed(1) : ""; }
        if (k === "storm") { var live = list.filter(function (it) { return !/no longer tracked/.test(it.title); }).length; return live + " active"; }
        if (k === "fire") { var big = list.filter(function (it) { return (it.level || 0) >= 3; }).length, hot = list.filter(function (it) { return /^Fire hotspots/.test(it.title); }).length; return [big ? big + " over 10k ha" : "", hot ? hot + " hotspot clusters" : ""].filter(function (t) { return t !== ""; }).join(" · "); }
        if (k === "alert") { var sev = list.filter(function (it) { return (it.level || 0) >= 3; }).length; return list.length + " oblast" + (list.length === 1 ? "" : "s") + (sev ? " · " + sev + " beyond air raid" : ""); }
        if (k === "flood") { var red = list.filter(function (it) { return (it.level || 0) >= 3; }).length; return red ? red + " red" : ""; }
        if (k === "tsunami") { var th = list.filter(function (it) { return (it.level || 0) >= 2; }).length; return th ? th + " threat" + (th > 1 ? "s" : "") + " active" : "no threat"; }
        if (k === "sat") return "live on the map";
        return "";
    }
    readonly property var rows: (function () {
        if (!grouped) return shown;
        var out = [], byKind = {};
        for (var i = 0; i < shown.length; i++) (byKind[shown[i].kind] = byKind[shown[i].kind] || []).push(shown[i]);
        var hidden = {};
        for (var h = 0; h < hiddenKinds.length; h++) hidden[hiddenKinds[h].kind] = hiddenKinds[h].count;
        for (var k = 0; k < kindList.length; k++) {
            var kind = kindList[k], list = byKind[kind] || [];
            // a kind the map shows keeps its header even with nothing to list, saying none (or that its source is down)
            if (list.length === 0 && !hidden[kind] && !(wanted(kind) && layers !== null && layerOf[kind] && layers.indexOf(layerOf[kind]) >= 0)) continue;
            var open = list.length > 0 && !closed[kind];
            out.push({ head: true, kind: kind, count: hidden[kind] || list.length, hidden: !!hidden[kind] && list.length === 0, fact: kindFact(kind, list), open: open });
            if (open && kind === "alert" && alertStrip.rows && alertStrip.rows.length > 0) out.push({ strip: true, kind: "alert", key: "strip:alert" });
            if (open) out = out.concat(list);
        }
        return out;
    })()
    property var openFacilities: ({})             // storms whose facility lists are unfolded, by key
    function toggleFacilities(key) { var o = Object.assign({}, openFacilities); if (o[key]) delete o[key]; else o[key] = true; openFacilities = o; }
    // Facilities as chips: "✓ crossed 23 · MC 807 A, Thunder Horse, +21"; the full list in the tooltip.
    function facilityChips(f) {
        if (!f) return [];
        var out = [];
        function chip(list, crossed, label) {
            if (!list || list.length === 0) return;
            var n = 0, names = [], all = [];
            for (var i = 0; i < list.length; i++) {
                n += list[i].count || 1;
                all.push(list[i].name + (list[i].count ? "" : list[i].kind === "refinery" ? " (refinery)" : " (platform)"));
                if (!list[i].count && names.length < 2) names.push(list[i].name);
            }
            var rest = n - names.length;
            out.push({ crossed: crossed, text: (crossed ? "\u2713 " : "\u2192 ") + label + " " + n + (names.length ? " \u00b7 " + names.join(", ") + (rest > 0 ? ", +" + rest : "") : ""), all: (crossed ? "Crossed" : "In its path") + ":\n" + all.join("\n") });
        }
        chip(f.crossed, true, "crossed");
        chip(f.ahead, false, "ahead");
        return out;
    }
    // launches with a webcast, for the Live tab
    readonly property var webcasts: items.filter(function (it) { return it.kind === "launch" && it.videos && it.videos.length > 0; })
    // Rows under a storm for its facilities: a heading per group, then each named facility, unnamed ones counted.
    function facilityRows(f) {
        if (!f) return [];
        var rows = [];
        function group(list, crossed, label) {
            if (!list || list.length === 0) return;
            var n = 0;
            for (var i = 0; i < list.length; i++) n += list[i].count || 1;
            rows.push({ head: true, crossed: crossed, text: label + " · " + n + (n === 1 ? " facility" : " facilities") });
            var shown = 0;
            for (var j = 0; j < list.length; j++) {
                if (shown >= 40 && j < list.length - 1 && !list[j].count) {
                    var rest = 0;
                    for (var k = j; k < list.length; k++) rest += list[k].count || 1;
                    rows.push({ head: false, crossed: crossed, kind: "", text: "+" + rest + " more" });
                    break;
                }
                rows.push({ head: false, crossed: crossed, kind: list[j].kind, text: list[j].name + (list[j].count ? "" : list[j].kind === "refinery" ? " · refinery" : " · platform") });
                shown++;
            }
        }
        group(f.crossed, true, "Crossed");
        group(f.ahead, false, "In its path");
        return rows;
    }
    function ago(t) {
        var s = Date.now() / 1000 - t;
        if (s < 0) return "in " + (-s < 3600 ? Math.round(-s / 60) + " min" : -s < 172800 ? Math.round(-s / 3600) + " h" : Math.round(-s / 86400) + " d");
        return s < 3600 ? Math.max(1, Math.round(s / 60)) + " min ago" : s < 172800 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago";
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf('" feed ') >= 0 && source.indexOf(" --since ") >= 0) {
                root.pastBusy = false;
                try {
                    var pr = JSON.parse(data.stdout);
                    root.pastItems = pr.items || [];
                    root.historyFrom = pr.history_from || 0;
                } catch (e) { root.problem = "The helper did not answer: " + String(data.stderr || data.stdout).trim().split("\n").pop(); }
            } else if (source.indexOf('" feed ') >= 0) {
                root.busy = false;
                try {
                    var r = JSON.parse(data.stdout);
                    root.items = r.items || [];
                    root.layers = r.layers === undefined ? null : r.layers;
                    root.saving = r.saving || 0; root.savingWhy = r.why || "";
                    root.ages = r.ages || ({});
                    root.alertStrip = r.alert_strip || ({ hours: 6, rows: [] });
                    root.problems = r.problems || [];
                    root.version = r.version || "";
                    root.problem = "";
                    var newest = 0;
                    for (var i = 0; i < root.items.length; i++) if (!root.items[i].pin && !root.items[i].future && root.items[i].when > newest) newest = root.items[i].when;
                    root.unread = root.items.filter(function (it) { return !it.pin && !it.future && it.when > root.lastSeen && root.wanted(it.kind); }).length;
                    root.nowSec = Date.now() / 1000;
                    root.alertCheck();
                } catch (e) {
                    root.problem = "The helper did not answer: " + String(data.stderr || data.stdout).trim().split("\n").pop();
                }
            } else if (source.indexOf('" mode ') >= 0) {
                try { root.mode = JSON.parse(data.stdout); } catch (e) {}
                refreshMode();
            } else if (source.indexOf('" power ') >= 0) {
                try { root.mode = JSON.parse(data.stdout).mode || ({}); } catch (e) {}
            } else if (source.indexOf('" status --names') >= 0) {
                // the rows, before any check has run: each shows "checking" until its own answer arrives
                try {
                    var nm = JSON.parse(data.stdout);
                    if (root.checks.length === 0)
                        root.checks = (nm.names || []).map(function (n) { return { name: n, state: "", detail: "" }; });
                    root.statusVersion = nm.version || root.statusVersion;
                } catch (e) {}
            } else if (source.indexOf('" status ') >= 0) {
                root.statusBusy = false;
                try {
                    var st = JSON.parse(data.stdout);
                    root.checks = st.checks || [];
                    root.statusVersion = st.version || "";
                    root.statusAt = Date.now() / 1000;
                    root.statusProblem = "";
                } catch (e) {
                    root.statusProblem = "The helper did not answer: " + String(data.stderr || data.stdout).trim().split("\n").pop();
                }
            }
        }
    }
    function refresh() {
        busy = true;
        exec.connectSource(helperShell + "feed --feed " + feedName + " # " + Date.now());
    }
    function refreshMode() { exec.connectSource(helperShell + "power # " + Date.now()) }
    function setMode(args) { exec.connectSource(helperShell + "mode " + args + " # " + Date.now()) }
    function checkStatus() {
        if (statusBusy) return;
        statusBusy = true;
        if (checks.length === 0) exec.connectSource(helperShell + "status --names # " + Date.now());   // rows first, answers later
        exec.connectSource(helperShell + "status --feed " + feedName + " # " + Date.now());
    }
    function markSeen() { lastSeen = Date.now() / 1000; unread = 0; }

    Component.onCompleted: { refresh(); refreshMode(); }
    Timer { interval: Math.max(1, Plasmoid.configuration.RefreshMinutes) * 60000; running: true; repeat: true; onTriggered: { root.refresh(); root.refreshPast(); } }
    onFeedNameChanged: refresh()
    onExpandedChanged: { if (root.expanded) { refresh(); refreshMode(); markSeen(); } else bubbleAway(bubbleRow); }

    toolTipMainText: "Live World Map"
    toolTipSubText: unread > 0 ? unread + " new events" : (shown.length ? shown.length + " events" : "no events yet")
    switchWidth: Kirigami.Units.gridUnit * 18
    switchHeight: Kirigami.Units.gridUnit * 14

    // a small upper-case heading and a greyed note, as the Map controls tab uses them (inline components live at the root)
    component Heading: PC3.Label {
        font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.6
        Layout.topMargin: Kirigami.Units.smallSpacing
    }
    component Note: PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }

    // ---- the preview bubble: what the feed knows about one event, beside the widget, after a short hover ----
    // 0 off (the plain link tooltip instead), 1 details, 2 details and the source's picture where it has one
    readonly property int previewMode: Plasmoid.configuration.Preview === undefined ? 2 : Plasmoid.configuration.Preview
    property var bubbleItem: ({})
    property Item bubbleRow: null
    function bubbleFor(row, it) { bubbleRow = row; bubbleItem = it || ({}); bubbleTimer.restart(); }
    function bubbleAway(row) { if (bubbleRow === row) { bubbleTimer.stop(); bubble.visible = false; bubbleRow = null; } }
    Timer { id: bubbleTimer; interval: 550; onTriggered: if (root.bubbleRow) { bubble.visualParent = root.bubbleRow; bubble.visible = true; } }
    PlasmaCore.Dialog {
        id: bubble
        type: PlasmaCore.Dialog.Tooltip
        location: PlasmaCore.Types.LeftEdge        // beside the widget (Plasma flips it to the other side at a screen edge)
        backgroundHints: PlasmaCore.Dialog.SolidBackground   // opaque: a see-through bubble over the map is hard to read
        hideOnWindowDeactivate: false
        visible: false
        mainItem: ColumnLayout {
            id: bubbleBody
            readonly property var it: root.bubbleItem
            readonly property var facts: it.facts || []
            readonly property string picture: root.previewMode >= 2 ? (it.image || "") : ""
            width: Kirigami.Units.gridUnit * 22
            height: implicitHeight                     // the dialog takes the item's size, and a layout does not size itself
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    Layout.preferredWidth: 9; Layout.preferredHeight: 9; radius: 5
                    color: bubbleBody.it.level >= 3 ? Kirigami.Theme.negativeTextColor : bubbleBody.it.level === 2 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.highlightColor
                }
                PC3.Label { Layout.fillWidth: true; text: bubbleBody.it.title || ""; textFormat: Text.PlainText; font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
            }
            PC3.Label { Layout.fillWidth: true; text: (root.kindName[bubbleBody.it.kind] || "") + (bubbleBody.it.detail ? " \u00b7 " + bubbleBody.it.detail : ""); textFormat: Text.PlainText; opacity: 0.7; wrapMode: Text.Wrap; font.pointSize: Kirigami.Theme.smallFont.pointSize }
            Image {
                id: picture
                visible: bubbleBody.picture !== "" && status !== Image.Error
                Layout.fillWidth: true
                Layout.preferredHeight: status === Image.Ready ? Math.round(width * implicitHeight / Math.max(1, implicitWidth)) : Kirigami.Units.gridUnit * 4
                source: bubbleBody.picture
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize.width: Kirigami.Units.gridUnit * 44
                PC3.BusyIndicator { anchors.centerIn: parent; visible: picture.status === Image.Loading; running: visible }
                // a picture the helper has not fetched yet (it fetches a few per feed run and hands over files) is loaded from
                // the source directly; past ten seconds say so, so a spinner is never the whole story
                Timer { id: slow; interval: 10000; running: picture.status === Image.Loading; onTriggered: slowNote.visible = true }
                onStatusChanged: if (status !== Image.Loading) slowNote.visible = false
            }
            PC3.Label { visible: bubbleBody.picture !== "" && picture.status === Image.Ready && !!bubbleBody.it.picture_note; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: bubbleBody.it.picture_note || "" }
            PC3.Label { id: slowNote; visible: false; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: "Still loading from " + bubbleBody.picture.replace(/^https?:\/\/([^/]+).*$/, "$1") + "\u2026 the helper will keep a copy for next time" }
            PC3.Label { visible: bubbleBody.picture !== "" && picture.status === Image.Error; text: "The picture could not be loaded" + (bubbleBody.picture.indexOf("file://") === 0 ? " (the helper's copy is unreadable: Map controls > Sources > Bubble pictures)" : " from " + bubbleBody.picture.replace(/^https?:\/\/([^/]+).*$/, "$1")); opacity: 0.6; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 1; columnSpacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: bubbleBody.facts
                    delegate: PC3.Label {
                        required property var modelData
                        required property int index
                        Layout.row: index; Layout.column: 0
                        Layout.alignment: Qt.AlignTop | Qt.AlignRight
                        text: modelData[0]; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
                Repeater {
                    model: bubbleBody.facts
                    delegate: PC3.Label {
                        required property var modelData
                        required property int index
                        Layout.row: index; Layout.column: 1
                        Layout.fillWidth: true
                        // a time row carries its timestamp: "Sat 24 Oct 21:27 · 2 h ago", ticking with the widget's clock
                        text: modelData[1] + (modelData.length > 2 && modelData[2] ? " \u00b7 " + root.ago(modelData[2]) : "")
                        textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }
            PC3.Label { visible: bubbleBody.facts.length === 0; text: "Nothing more is known about this one."; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
            // when this record last changed here (the feed's own bookkeeping) and when its source was last read
            PC3.Label {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                visible: !bubbleBody.it.pin
                textFormat: Text.PlainText; wrapMode: Text.Wrap; opacity: 0.55; font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: (bubbleBody.it.updated ? "Record updated " + root.ago(bubbleBody.it.updated) : "")
                    + (bubbleBody.it.seen && bubbleBody.it.seen !== bubbleBody.it.updated ? " \u00b7 first seen " + root.ago(bubbleBody.it.seen) : "")
                    + (root.ages[bubbleBody.it.kind] !== undefined ? (bubbleBody.it.updated ? " \u00b7 " : "") + "source " + root.asOf(bubbleBody.it.kind).replace("as of now", "read just now").replace("as of ", "read ") : "")
            }
            PC3.Label { visible: !!bubbleBody.it.url; Layout.fillWidth: true; text: "Click to open " + (root.webUrl(bubbleBody.it.url || "") || ""); textFormat: Text.PlainText; elide: Text.ElideMiddle; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }
    }

    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon { anchors.fill: parent; source: "globe"; active: parent.containsMouse }
        Rectangle {                                       // unread badge
            visible: root.unread > 0
            anchors { right: parent.right; top: parent.top }
            width: Math.max(badge.implicitWidth + 6, height); height: Math.round(Kirigami.Units.gridUnit * 0.9); radius: height / 2
            color: Kirigami.Theme.highlightColor
            PC3.Label { id: badge; anchors.centerIn: parent; text: root.unread; font.pointSize: Kirigami.Theme.smallFont.pointSize; color: Kirigami.Theme.highlightedTextColor }
        }
    }

    // On the desktop the widget draws its own frame (Plasma's usual one), so the frame and what is in it fade
    // together once the pointer has been away for a while, and come back as it arrives; or hold one opacity, with
    // the fade off. In a panel the popup keeps Plasma's own background and is never faded.
    readonly property bool onDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    Plasmoid.backgroundHints: onDesktop ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    fullRepresentation: Item {
        id: full
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22 + frame.fixedMargins.left + frame.fixedMargins.right
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18 + frame.fixedMargins.top + frame.fixedMargins.bottom
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26 + frame.fixedMargins.left + frame.fixedMargins.right
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28 + frame.fixedMargins.top + frame.fixedMargins.bottom
        readonly property real restOpacity: Math.max(5, Math.min(100, Plasmoid.configuration.IdleOpacity || 100)) / 100
        readonly property bool fades: root.onDesktop && Plasmoid.configuration.FadeIdle && restOpacity < 1
        property bool idle: false
        onFadesChanged: if (!fades) idle = false
        HoverHandler { id: hover; onHoveredChanged: { if (hovered) full.idle = false; else root.bubbleAway(root.bubbleRow); } }
        Timer { interval: Math.max(1, Plasmoid.configuration.IdleSeconds || 3) * 1000; running: full.fades && !hover.hovered; onTriggered: full.idle = true }
        opacity: !root.onDesktop ? 1 : full.fades ? (full.idle ? full.restOpacity : 1) : full.restOpacity
        Behavior on opacity { NumberAnimation { duration: full.idle ? 600 : 150; easing.type: Easing.InOutQuad } }
        KSvg.FrameSvgItem { id: frame; anchors.fill: parent; imagePath: "widgets/background"; visible: root.onDesktop }
        ColumnLayout {
            anchors.fill: parent
            // the frame's own margins plus a little air, so the text does not sit on the edge of the window
            anchors.leftMargin: (root.onDesktop ? frame.fixedMargins.left : 0) + Kirigami.Units.largeSpacing
            anchors.rightMargin: (root.onDesktop ? frame.fixedMargins.right : 0) + Kirigami.Units.largeSpacing
            anchors.topMargin: (root.onDesktop ? frame.fixedMargins.top : 0) + Kirigami.Units.smallSpacing
            anchors.bottomMargin: (root.onDesktop ? frame.fixedMargins.bottom : 0) + Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            PC3.TabBar {
                id: tabs
                Layout.fillWidth: true
                PC3.TabButton { text: "Events" }
                PC3.TabButton { text: "Live" }
                PC3.TabButton { text: "Sky" }
                PC3.TabButton { text: "Map controls" }
                onCurrentIndexChanged: if (currentIndex === 3 && (root.checks.length === 0 || Date.now() / 1000 - root.statusAt > 300)) root.checkStatus()
            }

            // ---- Events -------------------------------------------------------------
            ColumnLayout {
                visible: tabs.currentIndex === 0
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label { text: root.shown.length + (root.range > 0 ? " past" : "") + " events"; opacity: 0.7; elide: Text.ElideRight }
                    PC3.ComboBox {                            // the groups already sort by kind; "By kind" (2) reads as newest first
                        Layout.fillWidth: true
                        model: ["Newest first", "Most severe first", "Soonest launch first"]
                        currentIndex: root.sortMode === 1 ? 1 : root.sortMode === 3 ? 2 : 0
                        onActivated: function (i) { Plasmoid.configuration.SortMode = [0, 1, 3][i] }
                    }
                    PC3.ComboBox {                            // which kinds: what the map shows (its Show switches), or every kind
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 7.5
                        model: ["On the map", "Every kind"]
                        currentIndex: Plasmoid.configuration.FollowMap ? 0 : 1
                        onActivated: function (i) { Plasmoid.configuration.FollowMap = i === 0 }
                        PC3.ToolTip.text: "On the map: only the kinds the wallpaper has switched on. Every kind: all of them, whatever the map shows."; PC3.ToolTip.visible: hovered
                    }
                    PC3.ComboBox {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                        model: ["On the map now", "Past 24 hours", "Past 7 days", "Past 30 days", "Custom dates\u2026"]
                        currentIndex: root.range
                        onActivated: function (i) { root.range = i }
                        PC3.ToolTip.text: "Past events: everything the feed has shown, kept for 90 days, including what has left the map"; PC3.ToolTip.visible: hovered
                    }
                    PC3.ToolButton { icon.name: root.grouped ? "view-list-tree" : "view-list-details"; text: root.grouped ? "Groups" : "List"; display: PC3.AbstractButton.TextBesideIcon
                                     checkable: true; checked: root.grouped
                                     onToggled: Plasmoid.configuration.Grouped = checked
                                     PC3.ToolTip.text: root.grouped ? "In groups by kind (click for one list in the sort order)" : "One list in the sort order (click for groups by kind)"; PC3.ToolTip.visible: hovered }
                    PC3.ToolButton { visible: root.grouped; icon.name: root.anyOpen ? "collapse-all" : "expand-all"; onClicked: root.toggleAll()
                                     PC3.ToolTip.text: root.anyOpen ? "Collapse every group" : "Expand every group"; PC3.ToolTip.visible: hovered }
                    PC3.ToolButton { icon.name: "view-refresh"; enabled: !root.busy && !root.pastBusy; onClicked: { root.refresh(); root.refreshPast(); } PC3.ToolTip.text: "Refresh"; PC3.ToolTip.visible: hovered }
                    PC3.BusyIndicator { running: root.busy || root.pastBusy; visible: running; implicitHeight: Kirigami.Units.gridUnit * 1.2; implicitWidth: implicitHeight }
                }
                RowLayout {                                   // custom range
                    visible: root.range === 4
                    Layout.fillWidth: true
                    PC3.Label { text: "From" }
                    PC3.TextField { id: fromField; placeholderText: "YYYY-MM-DD"; text: root.fromText; Layout.preferredWidth: Kirigami.Units.gridUnit * 7; onAccepted: applyRange.clicked() }
                    PC3.Label { text: "to" }
                    PC3.TextField { id: toField; placeholderText: "YYYY-MM-DD"; text: root.toText; Layout.preferredWidth: Kirigami.Units.gridUnit * 7; onAccepted: applyRange.clicked() }
                    PC3.Button { id: applyRange; text: "Show"; icon.name: "view-filter"; onClicked: { root.fromText = fromField.text; root.toText = toField.text; root.refreshPast(); } }
                    PC3.Label { Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                                text: !root.rangeValid && (root.fromText !== "" || root.toText !== "") ? "dates as YYYY-MM-DD, from before to" : "" }
                }
                PC3.Label {
                    visible: root.range > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: "Past events from this computer's own record, kept 90 days" + (root.historyFrom > 0 ? ", since " + Qt.formatDate(new Date(root.historyFrom * 1000), "d MMM yyyy") : "") + ". Sorted as chosen above."
                }
                PC3.Label { visible: root.problem !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: root.problem; color: Kirigami.Theme.negativeTextColor }
                PC3.Label { visible: root.problems.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; opacity: 0.7; text: root.problems.join("; ") }
                PlasmaExtras.PlaceholderMessage {
                    visible: root.shown.length === 0 && !root.busy && !root.pastBusy && root.problem === ""
                    Layout.fillWidth: true; Layout.fillHeight: true
                    iconName: root.range > 0 ? "view-history" : "globe"
                    text: root.range > 0 ? "Nothing in this range" : "No events yet"
                    explanation: root.range > 0 ? "The record starts when this version first ran and only holds what the feed has shown since."
                                                : "Is the Live World Map wallpaper installed and running? The widget reads its caches."
                }
                PC3.ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: root.shown.length > 0 || root.hiddenKinds.length > 0
                    ListView {
                        id: list
                        model: root.rows
                        spacing: 2
                        clip: true
                        onContentYChanged: root.bubbleAway(root.bubbleRow)       // the row under the pointer changed: no stale bubble
                        delegate: Loader {
                            required property var modelData
                            required property int index
                            width: list.width
                            sourceComponent: modelData.head ? headerRow : modelData.strip ? stripRow : eventRow
                            onLoaded: { item.modelData = modelData; item.width = Qt.binding(function () { return list.width; }); }
                        }
                    }
                }
                // The air raid strip: under the group's header, one row per oblast that was under alert in the last
                // six hours, newest on the right - bright red for an alert still on (brightest when new or renewed),
                // dull red for one that ended, ochre for the frontline, on for days. The helper keeps the history.
                Component {
                    id: stripRow
                    Item {
                        property var modelData: ({})
                        readonly property var strip: root.alertStrip
                        readonly property real hours: strip.hours || 6
                        readonly property real now: strip.now || root.nowSec
                        readonly property real nameW: Kirigami.Units.gridUnit * 6.5
                        implicitHeight: stripCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                        ColumnLayout {
                            id: stripCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Kirigami.Units.gridUnit * 1.4; rightMargin: Kirigami.Units.smallSpacing; topMargin: Kirigami.Units.smallSpacing }
                            spacing: 2
                            Repeater {
                                model: (strip.rows || []).slice(0, 14)
                                RowLayout {
                                    id: stripLine
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    PC3.Label {
                                        Layout.preferredWidth: nameW; elide: Text.ElideRight; textFormat: Text.PlainText
                                        text: modelData.name; font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: modelData.active ? 0.95 : 0.6; font.bold: modelData.active && !modelData.long
                                    }
                                    Item {
                                        id: track
                                        Layout.fillWidth: true; implicitHeight: 9
                                        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06) }
                                        Repeater {
                                            model: modelData.spans || []
                                            Rectangle {
                                                required property var modelData
                                                readonly property real t0: Math.max(0, (modelData[0] - (now - hours * 3600)) / (hours * 3600))
                                                readonly property real t1: modelData[1] === null || modelData[1] === undefined ? 1 : Math.min(1, (modelData[1] - (now - hours * 3600)) / (hours * 3600))
                                                readonly property bool on: modelData[1] === null || modelData[1] === undefined
                                                readonly property bool freshNow: on && (now - Math.max(modelData[0], modelData[2] || 0)) < 15 * 60
                                                x: t0 * track.width; width: Math.max(2, (t1 - t0) * track.width); height: parent.height; radius: 2
                                                color: !on ? Qt.rgba(0.78, 0.25, 0.23, 0.45) : stripLine.modelData.long ? "#9a6a2a" : freshNow ? "#ff3b30" : "#c8403a"
                                                Rectangle { visible: freshNow; anchors.fill: parent; radius: 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 0.4, 0.35, 0.9) }
                                            }
                                        }
                                    }
                                    PC3.Label {
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2.6; horizontalAlignment: Text.AlignRight
                                        text: modelData.active ? (modelData.on_minutes >= 60 ? Math.round(modelData.on_minutes / 60) + " h" : modelData.on_minutes + " m") : "clear"
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: modelData.active ? 0.8 : 0.45
                                    }
                                }
                            }
                            RowLayout {                                             // the axis
                                Layout.fillWidth: true
                                spacing: 0
                                Item { Layout.preferredWidth: nameW + Kirigami.Units.smallSpacing }
                                PC3.Label { text: "\u2212" + Math.round(hours) + " h"; font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9; opacity: 0.4 }
                                Item { Layout.fillWidth: true }
                                PC3.Label { text: "\u2212" + Math.round(hours / 2) + " h"; font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9; opacity: 0.4 }
                                Item { Layout.fillWidth: true }
                                PC3.Label { text: "now"; font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9; opacity: 0.4 }
                                Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 2.6 + Kirigami.Units.smallSpacing }
                            }
                            PC3.Label {
                                visible: (strip.rows || []).length > 14
                                text: "+" + ((strip.rows || []).length - 14) + " more oblasts in the last " + Math.round(hours) + " h"; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                }
                // A group's header: chevron, the kind, how many, and the one fact that matters
                Component {
                    id: headerRow
                    PC3.ItemDelegate {
                        property var modelData: ({})           // set by the Loader once created
                        readonly property bool open: !!modelData.open
                        onClicked: root.toggleKind(modelData.kind)
                        background: Rectangle { color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06); radius: 3 }
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon { source: open ? "arrow-down" : "arrow-right"; implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth; opacity: 0.7 }
                            Kirigami.Icon {                          // wildfires and satellites have an icon of their own (icons/<kind>.svg)
                                visible: root.kindIconUrl(modelData.kind) !== ""
                                source: root.kindIconUrl(modelData.kind); isMask: true; color: Kirigami.Theme.textColor; opacity: 0.85
                                implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                            }
                            PC3.Label { visible: root.kindIconUrl(modelData.kind) === ""; text: root.kindIcon[modelData.kind] || "•"; Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2; horizontalAlignment: Text.AlignHCenter; opacity: 0.8 }
                            PC3.Label { text: root.kindPlural[modelData.kind] || modelData.kind; font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            PC3.Label { Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize; horizontalAlignment: Text.AlignRight
                                        text: modelData.hidden ? "off on the map \u00b7 " + modelData.count + " hidden" : modelData.count + (modelData.fact ? " \u00b7 " + modelData.fact : "") }
                        }
                    }
                }
                Component {
                    id: eventRow
                    PC3.ItemDelegate {
                        id: row
                        property var modelData: ({})           // set by the Loader once created
                        readonly property bool facilitiesOpen: !!root.openFacilities[modelData.key]
                        readonly property bool fresh: root.isNew(modelData)
                        readonly property bool soon: root.isSoon(modelData)
                        readonly property color accent: soon ? "#ffb347" : modelData.level >= 3 ? Kirigami.Theme.negativeTextColor
                                                      : modelData.level === 2 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.highlightColor
                        background: Rectangle {
                            color: soon ? Qt.rgba(1, 0.7, 0.28, 0.16) : fresh ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12) : "transparent"
                            radius: 3
                            Rectangle {                           // accent bar: new or imminent items get their colour on the left edge
                                visible: fresh || soon
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: 3; radius: 1
                                color: accent
                            }
                        }
                        onClicked: root.openWeb(modelData.url)
                        // a plain tooltip with the link when previews are off; otherwise the preview bubble, after a short hover
                        PC3.ToolTip.text: (modelData.url ? "Open: " + modelData.url : "No link") + (modelData.lat !== null && modelData.lat !== undefined ? "\n" + Number(modelData.lat).toFixed(2) + ", " + Number(modelData.lon).toFixed(2) : "")
                        PC3.ToolTip.visible: hovered && root.previewMode === 0
                        onHoveredChanged: {
                            if (hovered && root.previewMode > 0) root.bubbleFor(row, modelData);
                            else if (!hovered) root.bubbleAway(row);
                        }
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                visible: !root.grouped && root.kindIconUrl(modelData.kind) !== ""   // in groups the header carries the kind's icon
                                source: root.kindIconUrl(modelData.kind); isMask: true
                                color: modelData.level >= 3 ? Kirigami.Theme.negativeTextColor : modelData.level === 2 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium; implicitHeight: implicitWidth
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                            }
                            PC3.Label {
                                visible: !root.grouped && root.kindIconUrl(modelData.kind) === ""
                                text: root.kindIcon[modelData.kind] || "•"
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                                color: modelData.level >= 3 ? Kirigami.Theme.negativeTextColor : modelData.level === 2 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Rectangle {                              // in groups: a small severity dot instead of the icon
                                visible: root.grouped
                                Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4
                                Layout.leftMargin: Kirigami.Units.smallSpacing
                                color: modelData.level >= 3 ? Kirigami.Theme.negativeTextColor : modelData.level === 2 ? Kirigami.Theme.neutralTextColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.35)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    PC3.Label { Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; elide: Text.ElideRight; font.bold: fresh || soon }
                                    Rectangle {                   // "NEW" / "SOON" / "LIVE" tag
                                        visible: fresh || soon || !!modelData.webcast_live
                                        radius: 3; implicitHeight: tag.implicitHeight + 2; implicitWidth: tag.implicitWidth + 8
                                        color: modelData.webcast_live ? "#e53935" : accent
                                        PC3.Label { id: tag; anchors.centerIn: parent; text: modelData.webcast_live ? "LIVE" : soon ? "SOON" : "NEW"; font.pointSize: Kirigami.Theme.smallFont.pointSize; font.bold: true; color: "white" }
                                    }
                                }
                                PC3.Label {
                                    Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.7; textFormat: Text.PlainText
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    text: (root.grouped ? "" : (root.kindName[modelData.kind] || "") + " \u00b7 ") + (modelData.pin ? modelData.detail
                                          : (modelData.nonew ? "" : (root.range > 0 ? Qt.formatDateTime(new Date(modelData.when * 1000), "d MMM hh:mm") + " (" + root.ago(modelData.when) + ")" : root.ago(modelData.when)) + " \u00b7 ") + modelData.detail)
                                }
                                // a storm's oil and gas facilities: a chip for what it crossed, one for what lies in its
                                // path; a click on a chip unfolds the full list under the storm, another folds it back
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: Kirigami.Units.smallSpacing
                                    visible: root.facilityChips(modelData.facilities).length > 0
                                    Repeater {
                                        model: root.facilityChips(modelData.facilities)
                                        Rectangle {
                                            required property var modelData
                                            radius: height / 2
                                            implicitHeight: chip.implicitHeight + 4; implicitWidth: chip.implicitWidth + 14
                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, chipHover.containsMouse ? 0.16 : 0.08)
                                            border.width: 1; border.color: modelData.crossed ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                                            PC3.Label { id: chip; anchors.centerIn: parent; text: modelData.text; font.pointSize: Kirigami.Theme.smallFont.pointSize; textFormat: Text.PlainText }
                                            PC3.ToolTip.text: facilitiesOpen ? "Fold the list away" : "Unfold the full list"; PC3.ToolTip.visible: !!(chipHover && chipHover.containsMouse)
                                            HoverHandler { id: chipHover }
                                            TapHandler { onTapped: root.toggleFacilities(row.modelData.key) }
                                        }
                                    }
                                }
                                Repeater {                            // the unfolded list: a heading per group, then each facility
                                    model: facilitiesOpen ? root.facilityRows(modelData.facilities) : []
                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.leftMargin: Kirigami.Units.gridUnit * 0.6
                                        spacing: Kirigami.Units.smallSpacing
                                        PC3.Label {
                                            text: modelData.head ? (modelData.crossed ? "\u2713" : "\u2192") : (modelData.kind === "refinery" ? "\u25b2" : "\u25a0")
                                            opacity: modelData.head ? 0.8 : 0.55
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.9
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        PC3.Label {
                                            Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText
                                            text: modelData.text
                                            opacity: modelData.head ? 0.8 : 0.65
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            font.italic: modelData.head
                                        }
                                    }
                                }
                            }
                            Repeater {                                // extra links an item carries (e.g. who is aboard the ISS)
                                model: modelData.links || []
                                PC3.ToolButton {
                                    required property var modelData
                                    icon.name: modelData.icon || "internet-web-browser"
                                    display: PC3.AbstractButton.IconOnly
                                    PC3.ToolTip.text: modelData.label + "\n" + modelData.url; PC3.ToolTip.visible: hovered
                                    onClicked: root.openWeb(modelData.url)
                                }
                            }
                            Kirigami.Icon { source: "internet-web-browser"; visible: !!modelData.url; implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth; opacity: 0.6 }
                        }
                    }
                }
            }

            // ---- Live ---------------------------------------------------------------
            ColumnLayout {
                id: liveTab
                visible: tabs.currentIndex === 1
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing
                // a saved copy of an earlier default (NASA's old broadcast awQzjn72bI0, or its October 2026 one with the playlist, which
                // was the default for two days) is read as today's default, Sen's 4K view; the NASA stream stays in the list below
                readonly property string savedUrl: Plasmoid.configuration.LiveUrl || ""
                readonly property bool savedIsOldDefault: savedUrl.indexOf("awQzjn72bI0") >= 0 || (savedUrl.indexOf("ROboUHfPUrU") >= 0 && savedUrl.indexOf("list=PL2aBZuCeDwlQMf6xMgQAUAY_nbHAgW5jz") >= 0)
                readonly property string liveUrl: savedIsOldDefault ? "https://www.youtube.com/@sen/live" : savedUrl
                readonly property string nasaHd: "https://www.youtube.com/watch?v=ROboUHfPUrU&list=PL2aBZuCeDwlQMf6xMgQAUAY_nbHAgW5jz"
                function idOf(u) {
                    var m = u.match(/[?&]v=([\w-]{6,})/) || u.match(/youtu\.be\/([\w-]{6,})/) || u.match(/\/live\/([\w-]{6,})/);
                    return m ? m[1] : "";
                }
                // a channel's /live page (youtube.com/@NASA/live) names no video: the page is read once and its canonical
                // watch link gives the stream that is on now, so these embed like a fixed id
                property var resolved: ({})
                property string resolving: ""
                readonly property bool channelLive: /youtube\.com\/(@[\w.-]+|channel\/[\w-]+|c\/[\w-]+|user\/[\w-]+)\/live\/?(\?.*)?$/.test(chosenUrl)
                function resolve(u, fresh) {
                    if (!channelLive || resolving === u) return;
                    // an earlier empty answer is not final: the next time this stream is chosen it is asked again, fresh, once
                    if (resolved[u] !== undefined && !fresh) { if (resolved[u] === "" && !retried[u]) { retried[u] = true; fresh = true; } else return; }
                    resolving = u;
                    liveExec.connectSource(root.helperShell + "live-url '" + u.replace(/'/g, "") + "'" + (fresh ? " --fresh" : "") + " # " + Date.now());
                }
                property string resolveNote: ""
                property var retried: ({})
                Timer { id: retryTimer; property string url: ""; interval: 4000; onTriggered: if (liveTab.chosenUrl === url) liveTab.resolve(url, true) }
                P5Support.DataSource {
                    id: liveExec
                    engine: "executable"
                    connectedSources: []
                    onNewData: function (source, data) {
                        disconnectSource(source);
                        var r = {}; for (var k in liveTab.resolved) r[k] = liveTab.resolved[k];
                        try {
                            var a = JSON.parse(data.stdout);
                            r[a.url] = a.video || "";                       // "" = asked, nothing on now
                            liveTab.resolveNote = a.error ? "YouTube could not be asked: " + a.error : "";
                            // an empty first answer is asked again once, fresh, a few seconds later: YouTube's first reply to
                            // a new session sometimes names nothing (this used to need a Reload after every install)
                            if (!a.video && !a.cached && !liveTab.retried[a.url]) { liveTab.retried[a.url] = true; retryTimer.url = a.url; retryTimer.restart(); }
                        } catch (e) {
                            liveTab.resolveNote = "The helper did not answer: " + String(data.stderr || data.stdout).trim().split("\n").pop();
                        }
                        liveTab.resolved = r; liveTab.resolving = "";
                    }
                }
                onChosenUrlChanged: resolve(chosenUrl)
                onVisibleChanged: if (visible) resolve(chosenUrl)
                readonly property string videoId: idOf(chosenUrl) || (channelLive ? (resolved[chosenUrl] || "") : "")
                readonly property string playlist: (function () { var m = chosenUrl.match(/[?&]list=([\w-]{10,})/); return m ? m[1] : ""; })()
                property bool playHere: false              // "Play here" on the placeholder: embed for this popup session
                readonly property bool embed: (Plasmoid.configuration.LiveEmbed || playHere) && root.expanded && visible
                property int chosen: 0                     // 0 = the ISS stream from the settings; then the launches with a webcast
                readonly property var extra: String(Plasmoid.configuration.LiveExtra || "").split("\n").map(function (line) {
                    var i = line.indexOf("|");
                    return i > 0 ? { title: line.substring(0, i).trim(), url: line.substring(i + 1).trim() } : { title: line.trim(), url: line.trim() };
                }).filter(function (c) { return c.url.indexOf("http") === 0; })
                readonly property var choices: (function () {
                    var first = { title: liveUrl.indexOf("@sen") >= 0 ? "Sen 4K Earth views (Columbus module)" : "ISS live view", url: liveUrl };
                    var list = [first].concat(root.webcasts.map(function (L) {
                        return { title: (L.webcast_live ? "LIVE · " : "") + L.title + " · " + root.ago(L.when), url: L.videos[0].url };
                    }));
                    // the saved extras, without a second copy of the first stream; a saved list from before the change gains NASA's HD stream
                    var seen = {}; seen[first.url] = true;
                    var more = extra.filter(function (c) { if (seen[c.url] || (first.url.indexOf("@sen") >= 0 && c.url.indexOf("@sen") >= 0)) return false; seen[c.url] = true; return true; });
                    if (savedIsOldDefault && !more.some(function (c) { return c.url.indexOf("ROboUHfPUrU") >= 0; })) more.unshift({ title: "NASA HD Earth views (Harmony camera)", url: nasaHd });
                    return list.concat(more);
                })()
                readonly property string chosenUrl: (choices[Math.min(chosen, choices.length - 1)] || {}).url || ""
                PC3.ComboBox {
                    Layout.fillWidth: true
                    model: liveTab.choices.map(function (c) { return c.title })
                    currentIndex: Math.min(liveTab.chosen, liveTab.choices.length - 1)
                    onActivated: function (i) { liveTab.chosen = i }
                }
                Loader {
                    id: liveWeb
                    Layout.fillWidth: true; Layout.fillHeight: true
                    active: liveTab.embed && liveTab.videoId !== ""
                    source: "LiveWeb.qml"
                    onLoaded: { item.playlist = Qt.binding(function () { return liveTab.playlist }); item.videoId = Qt.binding(function () { return liveTab.videoId }) }
                }
                PlasmaExtras.PlaceholderMessage {
                    visible: !liveWeb.active || liveWeb.status === Loader.Error
                    Layout.fillWidth: true; Layout.fillHeight: true
                    iconName: "camera-video"
                    text: liveWeb.status === Loader.Error ? "Embedded player unavailable"
                        : liveTab.channelLive && liveTab.videoId === "" ? (liveTab.resolving !== "" ? "Looking for the stream that is on now…" : "Nothing live on that channel right now")
                        : liveTab.chosenUrl !== "" && liveTab.videoId === "" ? "Not a YouTube stream" : Plasmoid.configuration.LiveEmbed ? "Player starts when the popup is open" : "Stream not embedded"
                    explanation: liveWeb.status === Loader.Error ? "QtWebEngine's QML module is not installed (qt6-qtwebengine). Use a player below."
                               : liveTab.channelLive && liveTab.videoId === "" ? (liveTab.resolving !== "" ? "" : (liveTab.resolveNote !== "" ? liveTab.resolveNote + " " : "The channel's /live page named no broadcast. ") + "Open it in the browser, or try again later.")
                               : liveTab.chosenUrl !== "" && liveTab.videoId === "" ? "Only YouTube streams can be embedded; use a player or the browser for this one."
                               : Plasmoid.configuration.LiveEmbed ? "" : "Play it here (a browser engine runs inside the widget while the popup is open), in a player, or in the browser."
                    helpfulAction: Kirigami.Action {
                        visible: !Plasmoid.configuration.LiveEmbed && liveWeb.status !== Loader.Error && liveTab.videoId !== ""
                        text: "Play here"; icon.name: "media-playback-start"
                        onTriggered: liveTab.playHere = true
                    }
                }
                RowLayout {
                    PC3.Button {
                        text: "Open in player"; icon.name: "media-playback-start"
                        enabled: root.webUrl(liveTab.chosenUrl) !== ""
                        onClicked: exec.connectSource((Plasmoid.configuration.LivePlayer || "mpv") + " '" + root.webUrl(liveTab.chosenUrl) + "' >/dev/null 2>&1 & # " + Date.now())
                        PC3.ToolTip.text: "Runs: " + (Plasmoid.configuration.LivePlayer || "mpv") + " <url>  (mpv needs yt-dlp for YouTube)"
                        PC3.ToolTip.visible: hovered
                    }
                    PC3.Button { text: "Open in browser"; icon.name: "internet-web-browser"; enabled: root.webUrl(liveTab.chosenUrl) !== ""; onClicked: root.openWeb(liveTab.chosenUrl) }
                    PC3.Button { text: "Who is aboard"; icon.name: "user-group-new"; onClicked: root.openWeb("https://issinfo.net/whos-in-space"); PC3.ToolTip.text: "issinfo.net: everyone in space right now, by station"; PC3.ToolTip.visible: hovered }
                    PC3.Button {
                        visible: liveWeb.status === Loader.Ready || (liveTab.channelLive && liveTab.videoId === "" && liveTab.resolving === "")
                        text: "Reload"; icon.name: "view-refresh"
                        onClicked: { if (liveTab.channelLive) liveTab.resolve(liveTab.chosenUrl, true); if (liveWeb.item) liveWeb.item.show() }
                    }
                }
                PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                            text: liveTab.chosenUrl + (root.webcasts.length === 0 ? "   ·   no launch webcasts listed yet (they appear a day or so before lift-off)" : "") }
            }

            // ---- Sky: the weather, sun, moon and tonight's sky at the home place (SkyTab.qml) ----
            SkyTab {
                visible: tabs.currentIndex === 2
                active: visible && root.expanded
                helperShell: root.helperShell
                Layout.fillWidth: true; Layout.fillHeight: true
            }

            // ---- Map controls: quick settings on top of the wallpaper's own (mode.json, read within 20 s) ----
            PC3.ScrollView {
                id: mapScroll
                visible: tabs.currentIndex === 3
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: availableWidth
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                onVisibleChanged: if (visible && root.checks.length === 0) root.checkStatus()   // the chips' health dots
            ColumnLayout {
                id: mapControls
                width: mapScroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                // what the wallpaper is holding back right now, and why - this used to be a line in the map's corner
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: root.saving > 0
                    type: Kirigami.MessageType.Information
                    text: root.savingText + (root.savingWhy.indexOf("load guard") === 0 ? "  \u2014  Full speed below overrides it for a while; Settings > Performance and power sets the thresholds." : "")
                }
                Heading { text: "Quick settings \u00b7 the widget's own" }
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Switch {
                        text: "Clouds"
                        checked: root.mode.clouds !== false
                        onToggled: root.setMode("--clouds " + (checked ? "auto" : "off"))
                    }
                    Item { Layout.fillWidth: true }
                    PC3.Slider {
                        id: cloudOpacity
                        enabled: root.mode.clouds !== false
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                        from: 0; to: 100; stepSize: 5
                        value: root.mode.cloud_opacity !== undefined && root.mode.cloud_opacity !== null ? root.mode.cloud_opacity : 100
                        onMoved: cloudSend.restart()
                        Timer { id: cloudSend; interval: 400; onTriggered: root.setMode("--cloud-opacity " + Math.round(cloudOpacity.value)) }
                        PC3.ToolTip.text: "Cloud opacity, on top of the wallpaper's own"; PC3.ToolTip.visible: hovered
                    }
                    PC3.Label { text: Math.round(cloudOpacity.value) + " %"; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5; enabled: root.mode.clouds !== false }
                    PC3.ToolButton {
                        icon.name: "edit-undo"; visible: root.mode.cloud_opacity !== undefined && root.mode.cloud_opacity !== null
                        PC3.ToolTip.text: "Back to the wallpaper's own opacity"; PC3.ToolTip.visible: hovered
                        onClicked: root.setMode("--cloud-opacity auto")
                    }
                }
                PC3.Switch {
                    text: "Pulses and animation"
                    checked: !root.mode.pause
                    onToggled: root.setMode("--pause " + (checked ? "off" : "on"))
                }
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Switch {
                        id: fullSpeed
                        text: "Full speed"
                        checked: !!root.mode.full
                        onToggled: root.setMode(checked ? "--full on --full-hours " + [0, 1, 4, 8][fullHours.currentIndex] : "--full off")
                        PC3.ToolTip.text: "Ignore the wallpaper's on-battery policy and its load guard for a while"; PC3.ToolTip.visible: hovered
                    }
                    PC3.ComboBox {
                        id: fullHours
                        model: ["until switched off", "for 1 hour", "for 4 hours", "for 8 hours"]
                        currentIndex: 1
                        enabled: !fullSpeed.checked
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    }
                    PC3.Label {
                        Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: !root.mode.full ? "" : root.mode.full_until ? "(load guard overridden, " + Math.max(1, Math.round((root.mode.full_until - root.nowSec) / 60)) + " min left)" : "(load guard overridden)"
                    }
                }

                Heading { text: "Layers on the map" }
                // a chip per layer: on when the wallpaper shows it and the widget is not hiding it; the dot is its
                // sources' health, as the Sources section below sees them. A click hides or shows it from here.
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: root.layerChips
                        Rectangle {
                            id: lchip
                            required property var modelData
                            readonly property bool hiddenHere: !!(root.mode.hide && root.mode.hide.indexOf(modelData.layer) >= 0)
                            readonly property bool onMap: root.layers === null || root.layers.indexOf(modelData.layer) >= 0
                            readonly property bool on: onMap && !hiddenHere
                            readonly property string worst: root.layerHealth(modelData.layer)
                            radius: height / 2
                            implicitHeight: lchipRow.implicitHeight + 8; implicitWidth: lchipRow.implicitWidth + 20
                            color: on ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, lchipHover.containsMouse ? 0.35 : 0.22)
                                      : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, lchipHover.containsMouse ? 0.14 : 0.07)
                            border.width: 1; border.color: on ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.7) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                            RowLayout {
                                id: lchipRow
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle {
                                    Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4
                                    color: lchip.worst === "ok" ? Kirigami.Theme.positiveTextColor : lchip.worst === "warn" ? Kirigami.Theme.neutralTextColor
                                         : lchip.worst === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                                }
                                PC3.Label { text: lchip.modelData.name; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: lchip.on ? 1 : 0.6 }
                            }
                            PC3.ToolTip.text: (!lchip.onMap ? "Off in the wallpaper's settings" : lchip.hiddenHere ? "Hidden from here \u00b7 click to show" : "Shown \u00b7 click to hide from here")
                                              + (lchip.worst === "warn" ? "\nSome of its sources are not answering" : lchip.worst === "error" ? "\nNone of its sources are answering" : "")
                            PC3.ToolTip.visible: lchipHover.containsMouse
                            MouseArea {
                                id: lchipHover
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var hide = (root.mode.hide || []).filter(function (h) { return h !== lchip.modelData.layer; });
                                    if (!lchip.hiddenHere) hide.push(lchip.modelData.layer);
                                    root.setMode("--hide '" + hide.join(",") + "'");
                                }
                            }
                        }
                    }
                }
                PC3.Switch {
                    text: "Plain map only (every live layer off)"
                    checked: !!root.mode.plain
                    onToggled: root.setMode("--plain " + (checked ? "on" : "off"))
                }
                Note { text: "A chip is the same layer as the wallpaper's switch: grey, the wallpaper has it off; outlined, hidden from here. Everything on this tab sits on top of the wallpaper's own settings, reaches it within 20 seconds and stays until changed here." }
                RowLayout {
                    PC3.Button { text: "Clear overrides"; icon.name: "edit-clear"; enabled: !!root.mode.pause || !!root.mode.plain || !!root.mode.full || root.mode.clouds === false || (root.mode.hide || []).length > 0 || (root.mode.cloud_opacity !== undefined && root.mode.cloud_opacity !== null); onClicked: root.setMode("--clear") }
                    PC3.ToolButton { icon.name: "view-refresh"; PC3.ToolTip.text: "Re-read the overrides"; PC3.ToolTip.visible: hovered; onClicked: root.refreshMode() }
                }
                Heading { text: "This widget" }
                // the widget's own behaviour, the same settings as its configuration page (Plasmoid.configuration writes through)
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Switch {
                        text: "Fade when idle"
                        checked: Plasmoid.configuration.FadeIdle
                        onToggled: Plasmoid.configuration.FadeIdle = checked
                        PC3.ToolTip.text: "On the desktop: the whole widget fades to the opacity on the right once the pointer has been away for a few seconds"; PC3.ToolTip.visible: hovered
                    }
                    Item { Layout.fillWidth: true }
                    PC3.Slider {
                        id: idleOpacityQuick
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                        from: 5; to: 100; stepSize: 5
                        value: Plasmoid.configuration.IdleOpacity
                        onMoved: Plasmoid.configuration.IdleOpacity = Math.round(value)
                        PC3.ToolTip.text: "Idle opacity (100 %: the plain look)"; PC3.ToolTip.visible: hovered
                    }
                    PC3.Label { text: Math.round(idleOpacityQuick.value) + " %"; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label { text: "Preview on hover" }
                    Item { Layout.fillWidth: true }
                    PC3.ComboBox {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                        model: ["Off", "Details", "Details and pictures"]
                        currentIndex: root.previewMode
                        onActivated: function (i) { Plasmoid.configuration.Preview = i }
                    }
                }
                // ---- Sources: every data source and local file, as the wallpaper's own Status section sees them - the
                // former Status tab, folded under the controls; the header line is the summary, it opens by itself on a problem
                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }
                property bool sourcesOpen: false
                readonly property int problemCount: root.checks.filter(function (c) { return c.state === "error" }).length
                onProblemCountChanged: if (problemCount > 0) sourcesOpen = true
                RowLayout {
                    Layout.fillWidth: true
                    PC3.ToolButton {
                        icon.name: mapControls.sourcesOpen ? "arrow-down" : "arrow-right"
                        onClicked: mapControls.sourcesOpen = !mapControls.sourcesOpen
                        PC3.ToolTip.text: mapControls.sourcesOpen ? "Hide the sources" : "Show every source"; PC3.ToolTip.visible: hovered
                    }
                    Heading { text: "Sources"; Layout.topMargin: 0; MouseArea { anchors.fill: parent; onClicked: mapControls.sourcesOpen = !mapControls.sourcesOpen } }
                    PC3.Label {
                        Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: root.statusBusy ? (root.statusAt > 0 ? "Checking again\u2026 (last answers shown)" : "Checking every source\u2026") : root.checks.length === 0 ? "Not checked yet"
                            : (root.checks.filter(function (c) { return c.state === "error" }).length + " problems, "
                               + root.checks.filter(function (c) { return c.state === "warn" }).length + " notes"
                               + " \u00b7 checked " + root.ago(root.statusAt) + (root.statusVersion ? " \u00b7 helper " + root.statusVersion : ""))
                    }
                    PC3.BusyIndicator { visible: root.statusBusy; running: visible; implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth }
                    PC3.ToolButton { icon.name: "view-refresh"; enabled: !root.statusBusy; onClicked: root.checkStatus(); PC3.ToolTip.text: "Check again"; PC3.ToolTip.visible: hovered }
                }
                PC3.Label { visible: mapControls.sourcesOpen && root.statusProblem !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: root.statusProblem; color: Kirigami.Theme.negativeTextColor }
                // the list at its full height: the tab scrolls, not the list
                ColumnLayout {
                        visible: mapControls.sourcesOpen
                        Layout.fillWidth: true
                        spacing: 2
                        Repeater {
                        model: root.checks
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            readonly property bool pending: modelData.state === ""          // no answer yet
                            Rectangle {
                                Layout.alignment: Qt.AlignTop; Layout.topMargin: 5
                                width: 9; height: 9; radius: 4.5
                                color: pending ? Kirigami.Theme.disabledTextColor : modelData.state === "ok" ? Kirigami.Theme.positiveTextColor : modelData.state === "warn" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                                opacity: root.statusBusy ? 0.5 : 1
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    PC3.Label { Layout.fillWidth: true; text: modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; font.bold: !pending && modelData.state !== "ok" }
                                    PC3.Label { visible: root.statusBusy; text: "checking\u2026"; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                                }
                                PC3.Label { Layout.fillWidth: true; visible: !pending; text: modelData.detail; textFormat: Text.PlainText; wrapMode: Text.Wrap; opacity: root.statusBusy ? 0.4 : 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            }
                        }
                        }
                    }
                PC3.Label { visible: mapControls.sourcesOpen; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                            text: "Green: working. Yellow: something to download or a source that is slow or stale (the map keeps its last good data). Red: a source or file that is not working." }
                PC3.Button {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: "Open the wallpaper settings\u2026"; icon.name: "configure"
                    onClicked: exec.connectSource(root.helperShell + "widget --configure # " + Date.now())
                }
            }
            }

        }
    }
}
