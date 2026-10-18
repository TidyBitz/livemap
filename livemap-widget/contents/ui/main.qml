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
    property var checks: []                       // from `livemap-helper status`, for the Status tab
    property string statusVersion: ""
    property real statusAt: 0
    property bool statusBusy: false
    property string statusProblem: ""
    property real lastSeen: 0                     // newest event time the user has looked at
    readonly property string feedName: Plasmoid.configuration.QuakeFeed || "4.5_day"

    readonly property var kindIcon: ({ quake: "◎", storm: "☁", volcano: "△", fire: "♦", flood: "≋", alert: "⚠", launch: "↑", sat: "◆" })   // text fallbacks
    function kindIconUrl(kind) { return kind === "fire" || kind === "sat" ? Qt.resolvedUrl("../icons/" + kind + ".svg") : "" }   // icons/<kind>.svg, drawn as a mask; the rest keep their glyph
    readonly property var kindName: ({ quake: "Earthquake", storm: "Storm", volcano: "Volcano", fire: "Wildfire", flood: "Flood", alert: "Air raid alert", launch: "Launch", sat: "Satellite" })
    readonly property var layerOf: ({ quake: "quakes", storm: "storms", volcano: "volcanoes", fire: "fires", flood: "floods", alert: "alerts", launch: "launches", sat: "sats" })
    property var layers: null                     // the event layers the wallpaper shows (layers.json via the feed); null until it has said
    function wanted(kind) {
        var c = Plasmoid.configuration;
        var own = kind === "quake" ? c.ShowQuakes : kind === "volcano" ? c.ShowVolcanoes : kind === "storm" ? c.ShowStorms
                : kind === "fire" ? c.ShowFires : kind === "flood" ? c.ShowFloods : kind === "alert" ? c.ShowAlerts : kind === "launch" ? c.ShowLaunches : kind === "sat" ? c.ShowSats : true;
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
    readonly property var kindOrder: ({ alert: 0, launch: 1, storm: 2, flood: 3, volcano: 4, quake: 5, fire: 6, sat: 7 })
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
    readonly property var kindPlural: ({ alert: "Air raid alerts", launch: "Launches", storm: "Storms", flood: "Floods", volcano: "Volcanoes", quake: "Earthquakes", fire: "Wildfires", sat: "Satellites" })
    property var closed: ({})                     // kinds folded away, by the user; the header stays
    readonly property var kindList: ["alert", "launch", "storm", "flood", "volcano", "quake", "fire", "sat"]
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
            var own = k === "quake" ? c.ShowQuakes : k === "volcano" ? c.ShowVolcanoes : k === "storm" ? c.ShowStorms : k === "fire" ? c.ShowFires : k === "flood" ? c.ShowFloods : k === "alert" ? c.ShowAlerts : k === "launch" ? c.ShowLaunches : k === "sat" ? c.ShowSats : true;
            if (own && !wanted(k)) out[k] = (out[k] || 0) + 1;
        }
        return Object.keys(out).map(function (k) { return { kind: k, count: out[k] }; });
    })()
    readonly property var problemWords: ({ quake: "quakes", storm: "storms", volcano: "volcano", fire: "fire", flood: "flood", alert: "air alerts", launch: "launch", sat: "sat" })
    function emptyFact(k) {
        var w = problemWords[k] || k, p = problems.find(function (t) { return String(t).toLowerCase().indexOf(w) === 0; });
        return p ? "source not answering" : k === "flood" ? "none at the map's level" : "none right now";
    }
    function kindFact(k, list) {
        if (list.length === 0) return emptyFact(k);
        if (k === "launch") { var next = list.filter(function (it) { return it.future && it.when > nowSec; }).sort(function (a, b) { return a.when - b.when; })[0]; return next ? "next " + ago(next.when) : ""; }
        if (k === "quake") { var top = 0; for (var i = 0; i < list.length; i++) { var m = parseFloat(String(list[i].title).replace(/^M/, "")); if (m > top) top = m; } return top > 0 ? "strongest M" + top.toFixed(1) : ""; }
        if (k === "storm") { var live = list.filter(function (it) { return !/no longer tracked/.test(it.title); }).length; return live + " active"; }
        if (k === "fire") { var big = list.filter(function (it) { return (it.level || 0) >= 3; }).length, hot = list.filter(function (it) { return /^Fire hotspots/.test(it.title); }).length; return [big ? big + " over 10k ha" : "", hot ? hot + " hotspot clusters" : ""].filter(function (t) { return t !== ""; }).join(" · "); }
        if (k === "alert") { var sev = list.filter(function (it) { return (it.level || 0) >= 3; }).length; return list.length + " oblast" + (list.length === 1 ? "" : "s") + (sev ? " · " + sev + " beyond air raid" : ""); }
        if (k === "flood") { var red = list.filter(function (it) { return (it.level || 0) >= 3; }).length; return red ? red + " red" : ""; }
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
    onExpandedChanged: if (expanded) { refresh(); refreshMode(); markSeen(); }

    toolTipMainText: "Live World Map"
    toolTipSubText: unread > 0 ? unread + " new events" : (shown.length ? shown.length + " events" : "no events yet")
    switchWidth: Kirigami.Units.gridUnit * 18
    switchHeight: Kirigami.Units.gridUnit * 14

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

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        PC3.TabBar {
            id: tabs
            Layout.fillWidth: true
            PC3.TabButton { text: "Events" }
            PC3.TabButton { text: "Live" }
            PC3.TabButton { text: "Map controls" }
            PC3.TabButton { text: "Status" }
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
                    delegate: Loader {
                        required property var modelData
                        required property int index
                        width: list.width
                        sourceComponent: modelData.head ? headerRow : eventRow
                        onLoaded: { item.modelData = modelData; item.width = Qt.binding(function () { return list.width; }); }
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
                    PC3.ToolTip.text: (modelData.url ? "Open: " + modelData.url : "No link") + (modelData.lat !== null && modelData.lat !== undefined ? "\n" + Number(modelData.lat).toFixed(2) + ", " + Number(modelData.lon).toFixed(2) : "")
                    PC3.ToolTip.visible: hovered
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
                                        PC3.ToolTip.text: facilitiesOpen ? "Fold the list away" : "Unfold the full list"; PC3.ToolTip.visible: chipHover.containsMouse
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
            readonly property string liveUrl: Plasmoid.configuration.LiveUrl || ""
            readonly property string videoId: (function () {
                var u = chosenUrl;
                var m = u.match(/[?&]v=([\w-]{6,})/) || u.match(/youtu\.be\/([\w-]{6,})/) || u.match(/\/live\/([\w-]{6,})/);
                return m ? m[1] : "";
            })()
            property bool playHere: false              // "Play here" on the placeholder: embed for this popup session
            readonly property bool embed: (Plasmoid.configuration.LiveEmbed || playHere) && root.expanded && visible
            property int chosen: 0                     // 0 = the ISS stream from the settings; then the launches with a webcast
            readonly property var extra: String(Plasmoid.configuration.LiveExtra || "").split("\n").map(function (line) {
                var i = line.indexOf("|");
                return i > 0 ? { title: line.substring(0, i).trim(), url: line.substring(i + 1).trim() } : { title: line.trim(), url: line.trim() };
            }).filter(function (c) { return c.url.indexOf("http") === 0; })
            readonly property var choices: [{ title: "ISS live view", url: liveUrl }].concat(root.webcasts.map(function (L) {
                return { title: (L.webcast_live ? "LIVE · " : "") + L.title + " · " + root.ago(L.when), url: L.videos[0].url };
            })).concat(extra)
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
                onLoaded: item.videoId = Qt.binding(function () { return liveTab.videoId })
            }
            PlasmaExtras.PlaceholderMessage {
                visible: !liveWeb.active || liveWeb.status === Loader.Error
                Layout.fillWidth: true; Layout.fillHeight: true
                iconName: "camera-video"
                text: liveWeb.status === Loader.Error ? "Embedded player unavailable" : liveTab.chosenUrl !== "" && liveTab.videoId === "" ? "Not a YouTube stream" : Plasmoid.configuration.LiveEmbed ? "Player starts when the popup is open" : "Stream not embedded"
                explanation: liveWeb.status === Loader.Error ? "QtWebEngine's QML module is not installed (qt6-qtwebengine). Use a player below."
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
                    visible: liveWeb.status === Loader.Ready
                    text: "Reload"; icon.name: "view-refresh"; onClicked: liveWeb.item.show()
                }
            }
            PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: liveTab.chosenUrl + (root.webcasts.length === 0 ? "   ·   no launch webcasts listed yet (they appear a day or so before lift-off)" : "") }
        }

        // ---- Map controls -------------------------------------------------------
        ColumnLayout {
            visible: tabs.currentIndex === 2
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing
            PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7; text: "These reach the wallpaper within 20 seconds and stay until changed here. They sit on top of the wallpaper's own settings." }
            PC3.CheckBox {
                text: "Pause animations"
                checked: !!root.mode.pause
                onToggled: root.setMode("--pause " + (checked ? "on" : "off"))
            }
            PC3.CheckBox {
                text: "Plain map only (live layers off)"
                checked: !!root.mode.plain
                onToggled: root.setMode("--plain " + (checked ? "on" : "off"))
            }
            PC3.Label { text: "Hide layers:"; font.bold: true; Layout.topMargin: Kirigami.Units.smallSpacing }
            GridLayout {
                columns: 2
                Repeater {
                    model: [["quakes", "Earthquakes"], ["volcanoes", "Volcanoes"], ["storms", "Storms"], ["fires", "Wildfires"], ["floods", "Floods"], ["alerts", "Air raid alerts"], ["sats", "Satellites"], ["launches", "Launches"], ["network", "Network"]]
                    PC3.CheckBox {
                        required property var modelData
                        text: modelData[1]
                        checked: !!(root.mode.hide && root.mode.hide.indexOf(modelData[0]) >= 0)
                        onToggled: {
                            var hide = (root.mode.hide || []).filter(function (h) { return h !== modelData[0]; });
                            if (checked) hide.push(modelData[0]);
                            root.setMode("--hide '" + hide.join(",") + "'");
                        }
                    }
                }
            }
            PC3.Label { text: "Clouds:"; font.bold: true; Layout.topMargin: Kirigami.Units.smallSpacing }
            RowLayout {
                Layout.fillWidth: true
                PC3.CheckBox {
                    text: "Show clouds"
                    tristate: false
                    checked: root.mode.clouds !== false
                    onToggled: root.setMode("--clouds " + (checked ? "auto" : "off"))
                }
                PC3.Label { text: root.mode.clouds === false ? "(hidden from here)" : "(as set in the wallpaper)"; opacity: 0.6 }
            }
            RowLayout {
                Layout.fillWidth: true
                enabled: root.mode.clouds !== false
                PC3.Label { text: "Opacity" }
                PC3.Slider {
                    id: cloudOpacity
                    Layout.fillWidth: true
                    from: 0; to: 100; stepSize: 5
                    value: root.mode.cloud_opacity !== undefined && root.mode.cloud_opacity !== null ? root.mode.cloud_opacity : 100
                    onMoved: cloudSend.restart()
                    Timer { id: cloudSend; interval: 400; onTriggered: root.setMode("--cloud-opacity " + Math.round(cloudOpacity.value)) }
                }
                PC3.Label { text: Math.round(cloudOpacity.value) + " %"; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5 }
                PC3.ToolButton {
                    icon.name: "edit-undo"; visible: root.mode.cloud_opacity !== undefined && root.mode.cloud_opacity !== null
                    PC3.ToolTip.text: "Back to the wallpaper's own opacity"; PC3.ToolTip.visible: hovered
                    onClicked: root.setMode("--cloud-opacity auto")
                }
            }
            PC3.Label { text: "Power:"; font.bold: true; Layout.topMargin: Kirigami.Units.smallSpacing }
            RowLayout {
                Layout.fillWidth: true
                PC3.CheckBox {
                    id: fullSpeed
                    text: "Full speed"
                    checked: !!root.mode.full
                    onToggled: root.setMode(checked ? "--full on --full-hours " + [0, 1, 4, 8][fullHours.currentIndex] : "--full off")
                    PC3.ToolTip.text: "Ignore the wallpaper's on-battery policy and its load guard for a while. Pause and Plain map above still apply."
                    PC3.ToolTip.visible: hovered
                }
                PC3.ComboBox {
                    id: fullHours
                    model: ["until switched off", "for 1 hour", "for 4 hours", "for 8 hours"]
                    currentIndex: 2
                    enabled: !fullSpeed.checked
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                }
            }
            PC3.Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6
                text: !root.mode.full ? "Battery policy and load guard as set in the wallpaper."
                    : root.mode.full_until ? "Full speed until " + Qt.formatTime(new Date(root.mode.full_until * 1000), "hh:mm") + " (" + Math.max(1, Math.round((root.mode.full_until - root.nowSec) / 60)) + " min left), then back to the wallpaper's settings."
                    : "Full speed until switched off here: the battery policy and the load guard are ignored."
            }
            RowLayout {
                PC3.Button { text: "Clear all overrides"; icon.name: "edit-clear"; onClicked: root.setMode("--clear") }
                PC3.Button { text: "Re-read"; icon.name: "view-refresh"; onClicked: root.refreshMode() }
            }
            Item { Layout.fillHeight: true }
            PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: "Uses the " + root.helper + " and its data folder; nothing is fetched twice." }
        }

        // ---- Status: every data source and local file, as the wallpaper's own Status section sees them ----
        ColumnLayout {
            visible: tabs.currentIndex === 3
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.7
                    text: root.statusBusy ? (root.statusAt > 0 ? "Checking again\u2026 (last answers shown)" : "Checking every source\u2026") : root.checks.length === 0 ? "Not checked yet"
                        : (root.checks.filter(function (c) { return c.state === "error" }).length + " problems, "
                           + root.checks.filter(function (c) { return c.state === "warn" }).length + " notes"
                           + " \u00b7 checked " + root.ago(root.statusAt) + (root.statusVersion ? " \u00b7 helper " + root.statusVersion : ""))
                }
                PC3.BusyIndicator { visible: root.statusBusy; running: visible; implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth }
                PC3.ToolButton { icon.name: "view-refresh"; enabled: !root.statusBusy; onClicked: root.checkStatus(); PC3.ToolTip.text: "Check again"; PC3.ToolTip.visible: hovered }
            }
            PC3.Label { visible: root.statusProblem !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: root.statusProblem; color: Kirigami.Theme.negativeTextColor }
            PC3.ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: availableWidth
                ListView {
                    model: root.checks
                    spacing: 2
                    clip: true
                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
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
            PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: "Green: working. Yellow: something to download or a source that is slow or stale (the map keeps its last good data). Red: a source or file that is not working." }
        }
    }
}
