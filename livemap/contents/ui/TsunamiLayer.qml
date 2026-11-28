/*
 * Tsunami bulletins from the Pacific and National Tsunami Warning Centers (tsunami.gov): every evaluated
 * earthquake as a ringed mark at the epicentre, the threat level as its colour - an evaluation with no threat
 * in a quiet blue-grey, a watch in yellow, an advisory in orange, a warning or threat message in red with
 * rings that run out from the epicentre while it stands - and the coast under threat as thick lines between
 * the centre's breakpoints. Labelled "Tsunami threat · M7.6 Panama · 23 min". A threat stood down by a later
 * message fades over its last hours; an information statement leaves after six.
 * The helper remembers every message by event, because tsunami.gov serves only the latest one per centre.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import "geo.js" as Geo

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    property bool slow: false

    readonly property real unit: Math.max(1, Screen.width / 1920)
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property bool showInfo: cfg ? cfg.TsunamiShowInfo : true           // evaluations that found no threat
    readonly property real infoHours: cfg ? cfg.TsunamiInfoHours : 6
    readonly property color infoInk: cfg ? cfg.TsunamiInfoColor : "#8fb6d6"
    readonly property color watchInk: cfg ? cfg.TsunamiWatchColor : "#ffd23f"
    readonly property color advisoryInk: cfg ? cfg.TsunamiAdvisoryColor : "#ff8c00"
    readonly property color warnInk: cfg ? cfg.TsunamiColor : "#ff3b3b"
    function inkOf(e) { return e.level >= 3 ? warnInk : e.level === 2 ? advisoryInk : e.level === 1 ? watchInk : infoInk }
    readonly property bool showCoast: cfg ? cfg.TsunamiCoast : true
    readonly property int labelMode: cfg ? cfg.TsunamiLabels : 2                // 0 none, 1 threats only, 2 all
    readonly property int labelPx: Math.round((cfg ? cfg.TsunamiLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.TsunamiLabelPlate : true
    readonly property color labelColor: cfg && !cfg.TsunamiTextFollows ? cfg.TsunamiTextColor : warnInk
    function labelInkOf(e) { return cfg && !cfg.TsunamiTextFollows ? labelColor : inkOf(e) }
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: Math.round((cfg ? cfg.TsunamiLabelSize : 10) * 1.4 * unit * markScale)
    readonly property bool pulse: cfg ? cfg.TsunamiPulse : true
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    property var events: []
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    property real clock: 0
    property real nowSec: Date.now() / 1000
    Timer { interval: 60000; running: overlay.events.length > 0; repeat: true; onTriggered: overlay.nowSec = Date.now() / 1000 }
    // an information statement leaves after infoHours; a stood-down threat fades over three hours
    function fade(e) {
        if (e.active) return 1;
        if (e.ended) return Math.max(0, 1 - (nowSec - e.ended) / (3 * 3600));
        return Math.max(0, 1 - Math.max(0, (nowSec - e.sent) / 3600 - infoHours * 0.5) / (infoHours * 0.5));
    }
    readonly property var shown: events.filter(function (e) { return (e.level > 0 || showInfo) && e.lat !== null && e.lon !== null && fade(e) > 0; })
    readonly property bool pulseWanted: pulse && shown.some(function (e) { return e.active; })

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    function describe(e) {
        // "Tsunami threat · M7.6 Panama · 23 min"; "Tsunami evaluated, no threat · M6.6 Vanuatu · 2 h"; "Threat ended · ..."
        var what = e.ended ? "Threat ended" : e.level >= 3 ? "Tsunami " + (e.event.toLowerCase().indexOf("warning") >= 0 ? "warning" : "threat")
                 : e.level === 2 ? "Tsunami advisory" : e.level === 1 ? "Tsunami watch" : "Tsunami evaluated, no threat";
        var who = (e.mag ? "M" + e.mag.toFixed(1) + " " : "") + (e.location || "");
        return what + (who ? " · " + who : "") + " · " + Geo.spanText(Math.max(0, nowSec - e.sent) / 3600);
    }
    readonly property var labelSpecs: labelMode === 0 ? [] : shown.filter(function (e) { return labelMode === 2 || e.level > 0; }).map(function (e) {
        return { x: px(e.lon), y: py(e.lat), gap: mark * 0.7, side: "right", text: describe(e), px: labelPx, color: labelInkOf(e),
                 plate: labelPlate, bold: e.active && e.level >= 2, alpha: 0.4 + 0.6 * fade(e) };
    })

    Exec {
        id: exec
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                overlay.events = r.events || [];
                overlay.note = r.note || "";
                overlay.nowSec = Date.now() / 1000;
                console.warn("livemap tsunami:", overlay.events.length, "bulletins,", overlay.events.filter(function (e) { return e.active; }).length, "active", overlay.note);
            } catch (e) { overlay.note = "Tsunami: the helper did not answer properly"; }
        }
    }
    function ask() { exec.connectSource("python3 '" + helper + "' tsunami --stale " + staleHours + " # " + Date.now()) }
    Timer {                                       // a bulletin follows a big quake within minutes: every 5 (15 when saving)
        interval: (overlay.slow ? 15 : 5) * 60000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: overlay.ask()
    }

    // the threatened coast: between the centre's breakpoints, one path per level (a ShapePath is not an Item,
    // so a Repeater cannot make them)
    function coastPaths(level) {
        var out = [];
        if (!showCoast) return out;
        for (var i = 0; i < shown.length; i++) {
            var e = shown[i];
            if (!e.active || e.level !== level) continue;
            for (var j = 0; j < (e.segments || []).length; j++) {
                var s = e.segments[j];
                if (Math.abs(s[2] - s[4]) > 180) continue;                 // not across the date line
                out.push([Qt.point(px(s[2]), py(s[1])), Qt.point(px(s[4]), py(s[3]))]);
            }
        }
        return out;
    }
    Shape {
        anchors.fill: parent
        visible: overlay.showCoast
        preferredRendererType: Shape.CurveRenderer
        ShapePath { strokeColor: Qt.rgba(overlay.watchInk.r, overlay.watchInk.g, overlay.watchInk.b, 0.7); strokeWidth: Math.max(2, 3 * overlay.unit); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathMultiline { paths: overlay.coastPaths(1) } }
        ShapePath { strokeColor: Qt.rgba(overlay.advisoryInk.r, overlay.advisoryInk.g, overlay.advisoryInk.b, 0.7); strokeWidth: Math.max(2, 3 * overlay.unit); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathMultiline { paths: overlay.coastPaths(2) } }
        ShapePath { strokeColor: Qt.rgba(overlay.warnInk.r, overlay.warnInk.g, overlay.warnInk.b, 0.75); strokeWidth: Math.max(2, 3.5 * overlay.unit); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathMultiline { paths: overlay.coastPaths(3) } }
    }

    Repeater {
        model: overlay.shown
        Item {
            id: ev
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            readonly property color tone: overlay.inkOf(modelData)
            readonly property real k: overlay.fade(modelData)
            readonly property real r: overlay.mark * (modelData.level > 0 ? 1 : 0.7)
            Repeater {                            // three rings running out while a threat stands
                model: modelData.active && overlay.pulse && overlay.fps > 0 ? 3 : 0
                Rectangle {
                    required property int index
                    readonly property real s: Geo.pulse(overlay.clock + index * overlay.pulseMs / 3, ev.index, overlay.pulseMs, overlay.periodMs)
                    visible: s >= 0
                    anchors.centerIn: parent
                    width: ev.r * (1.5 + 5 * Math.max(0, s)); height: width; radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(ev.tone.r, ev.tone.g, ev.tone.b, (1 - Math.max(0, s)) * 0.8)
                    border.width: Math.max(1, 1.5 * overlay.unit)
                }
            }
            Rectangle {                           // the mark: a filled disc in a ring, the wave sign
                anchors.centerIn: parent
                width: ev.r * 2; height: width; radius: width / 2
                color: Qt.rgba(ev.tone.r, ev.tone.g, ev.tone.b, 0.2 * ev.k)
                border.color: Qt.rgba(ev.tone.r, ev.tone.g, ev.tone.b, 0.95 * ev.k)
                border.width: Math.max(1, (modelData.level > 0 ? 2 : 1.2) * overlay.unit)
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.4; height: width; radius: width / 2; color: Qt.rgba(ev.tone.r, ev.tone.g, ev.tone.b, 0.95 * ev.k) }
            }
            Text {                                // the wave glyph over the disc for a threat
                visible: modelData.level > 0
                anchors.centerIn: parent
                text: "≋"
                color: Qt.rgba(1, 1, 1, 0.9 * ev.k)
                font.pixelSize: Math.round(ev.r * 1.3)
                font.bold: true
            }
        }
    }
}
