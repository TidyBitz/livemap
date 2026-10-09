// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 tidybitz
/*
 * Live World Map Events: a panel or desktop widget that lists the newest events the wallpaper tracks
 * (earthquakes, storms, volcanoes, wildfires, launches, satellites), each opening its source in the
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

    readonly property var kindIcon: ({ quake: "◎", storm: "☁", volcano: "△", fire: "♦", launch: "↑", sat: "◆" })
    readonly property var kindName: ({ quake: "Earthquake", storm: "Storm", volcano: "Volcano", fire: "Wildfire", launch: "Launch", sat: "Satellite" })
    function wanted(kind) {
        var c = Plasmoid.configuration;
        return kind === "quake" ? c.ShowQuakes : kind === "volcano" ? c.ShowVolcanoes : kind === "storm" ? c.ShowStorms
             : kind === "fire" ? c.ShowFires : kind === "launch" ? c.ShowLaunches : kind === "sat" ? c.ShowSats : true;
    }
    readonly property int sortMode: Plasmoid.configuration.SortMode      // 0 newest, 1 severity, 2 kind, 3 soonest launch
    readonly property real newSeconds: Math.max(1, Plasmoid.configuration.NewMinutes) * 60
    property real nowSec: Date.now() / 1000
    // Links come from the feeds: only plain web links are ever handed to the browser or a player.
    function webUrl(u) { u = String(u || "").trim(); return /^https?:\/\/[^\s'"<>]+$/.test(u) ? u : "" }
    function openWeb(u) { u = webUrl(u); if (u !== "") Qt.openUrlExternally(u) }
    Timer { interval: 30000; running: root.expanded; repeat: true; onTriggered: {
        root.nowSec = Date.now() / 1000;
        if (root.mode.full && root.mode.full_until && root.nowSec >= root.mode.full_until) root.refreshMode();   // the helper drops a timed full-speed override when it is over
    } }
    function isNew(it) { return !it.pin && !it.future && root.nowSec - it.when < root.newSeconds }
    function isSoon(it) { return !!it.future && it.when - root.nowSec < 3600 && it.when - root.nowSec > -1800 }
    readonly property var kindOrder: ({ launch: 0, storm: 1, volcano: 2, quake: 3, fire: 4, sat: 5 })
    readonly property var shown: (function () {
        var list = items.filter(function (it) { return wanted(it.kind); });
        var mode = sortMode;
        list.sort(function (a, b) {
            // whatever the order, a launch inside its last hour goes to the very top, then the pinned satellites
            var sa = isSoon(a) ? 0 : a.pin ? 1 : 2, sb = isSoon(b) ? 0 : b.pin ? 1 : 2;
            if (sa !== sb) return sa - sb;
            if (mode === 1) { if ((b.level || 0) !== (a.level || 0)) return (b.level || 0) - (a.level || 0); return b.when - a.when; }
            if (mode === 2) { var ka = kindOrder[a.kind] || 9, kb = kindOrder[b.kind] || 9; if (ka !== kb) return ka - kb; return b.when - a.when; }
            if (mode === 3) { var fa = a.future ? 0 : 1, fb = b.future ? 0 : 1; if (fa !== fb) return fa - fb; return a.future ? a.when - b.when : b.when - a.when; }
            return b.when - a.when;
        });
        return list;
    })()
    // launches with a webcast, for the Live tab
    readonly property var webcasts: items.filter(function (it) { return it.kind === "launch" && it.videos && it.videos.length > 0; })
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
            if (source.indexOf('" feed ') >= 0) {
                root.busy = false;
                try {
                    var r = JSON.parse(data.stdout);
                    root.items = r.items || [];
                    root.problems = r.problems || [];
                    root.version = r.version || "";
                    root.problem = "";
                    var newest = 0;
                    for (var i = 0; i < root.items.length; i++) if (!root.items[i].pin && !root.items[i].future && root.items[i].when > newest) newest = root.items[i].when;
                    root.unread = root.items.filter(function (it) { return !it.pin && !it.future && it.when > root.lastSeen && root.wanted(it.kind); }).length;
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
    Timer { interval: Math.max(1, Plasmoid.configuration.RefreshMinutes) * 60000; running: true; repeat: true; onTriggered: root.refresh() }
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
                PC3.Label { text: root.shown.length + " events"; opacity: 0.7; elide: Text.ElideRight }
                PC3.ComboBox {
                    Layout.fillWidth: true
                    model: ["Newest first", "Most severe first", "By kind", "Soonest launch first"]
                    currentIndex: root.sortMode
                    onActivated: function (i) { Plasmoid.configuration.SortMode = i }
                }
                PC3.ToolButton { icon.name: "view-refresh"; enabled: !root.busy; onClicked: root.refresh(); PC3.ToolTip.text: "Refresh"; PC3.ToolTip.visible: hovered }
                PC3.BusyIndicator { running: root.busy; visible: root.busy; implicitHeight: Kirigami.Units.gridUnit * 1.2; implicitWidth: implicitHeight }
            }
            PC3.Label { visible: root.problem !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: root.problem; color: Kirigami.Theme.negativeTextColor }
            PC3.Label { visible: root.problems.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; opacity: 0.7; text: root.problems.join("; ") }
            PlasmaExtras.PlaceholderMessage {
                visible: root.shown.length === 0 && !root.busy && root.problem === ""
                Layout.fillWidth: true; Layout.fillHeight: true
                iconName: "globe"
                text: "No events yet"
                explanation: "Is the Live World Map wallpaper installed and running? The widget reads its caches."
            }
            PC3.ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.shown.length > 0
                ListView {
                    id: list
                    model: root.shown
                    spacing: 2
                    clip: true
                    delegate: PC3.ItemDelegate {
                        required property var modelData
                        required property int index
                        width: list.width
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
                            PC3.Label {
                                text: root.kindIcon[modelData.kind] || "•"
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                                color: modelData.level >= 3 ? Kirigami.Theme.negativeTextColor : modelData.level === 2 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                                horizontalAlignment: Text.AlignHCenter
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
                                    text: (root.kindName[modelData.kind] || "") + " · " + (modelData.pin ? modelData.detail : root.ago(modelData.when) + " · " + modelData.detail)
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
            readonly property bool embed: Plasmoid.configuration.LiveEmbed && root.expanded && visible
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
                           : Plasmoid.configuration.LiveEmbed ? "" : "Turn on embedding in the widget settings, or open the stream in a player or the browser."
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
                    model: [["quakes", "Earthquakes"], ["volcanoes", "Volcanoes"], ["storms", "Storms"], ["fires", "Wildfires"], ["sats", "Satellites"], ["launches", "Launches"], ["network", "Network"]]
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
