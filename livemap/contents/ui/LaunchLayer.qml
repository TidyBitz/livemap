/*
 * Upcoming rocket launches from The Space Devs' Launch Library 2: a marker on the pad with a countdown,
 * for launches inside the chosen window. No flight paths: nobody publishes those as data.
 */
import QtQuick
import QtQuick.Window
import "geo.js" as Geo

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    property bool slow: false

    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property color ink: cfg ? cfg.LaunchColor : "#ffffff"
    readonly property real windowHours: [24, 48, 72, 168][cfg ? cfg.LaunchWindow : 2] || 72
    readonly property int labelMode: cfg ? cfg.LaunchLabels : 2          // 0 none, 1 countdown, 2 rocket, mission and countdown
    readonly property int labelPx: Math.round((cfg ? cfg.LaunchLabelSize : 10) * unit)
    readonly property bool twoLines: cfg ? cfg.LaunchLabelTwoLines : true
    readonly property bool labelPlate: cfg ? cfg.LaunchLabelPlate : true
    readonly property color labelColor: cfg && !cfg.LaunchTextFollows ? cfg.LaunchTextColor : ink
    readonly property bool pulseSoon: cfg ? cfg.LaunchPulse : true
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: 6 * unit * markScale
    readonly property bool pictures: cfg ? cfg.LaunchMarkerStyle === 1 : false
    readonly property real pictureSize: (cfg ? cfg.LaunchPictureSize : 18) * unit * markScale
    property var launches: []
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    property real clock: 0
    property real now: Date.now() / 1000
    // the clock ticks every 30 s normally, every second in the last ten minutes before a lift-off
    readonly property bool finalApproach: shown.some(function (L) { return L.net - now < 600 && L.net - now > -120; })
    Timer { interval: overlay.finalApproach ? 1000 : 30000; running: overlay.shown.length > 0; repeat: true; onTriggered: overlay.now = Date.now() / 1000 }
    // the pulse clock is shared: main.qml advances one clock for every layer, so all pulses move in the same frame
    readonly property bool pulseWanted: pulseSoon && shown.some(soon)
    function soon(L) { return L.net - now < 3600 && L.net - now > -1800 }
    // one marker per pad: the earliest launch there; keep a launch for half an hour after lift-off
    // Pads are grouped by site (the Cape's and Vandenberg's several pads are a few km apart and would print over
    // each other); the earliest launch is the marker and its label says how many more are queued there.
    readonly property var shown: (function () {
        var bySite = {}, out = [];
        launches.filter(function (L) { return (L.net - now > -1800 || (L.past && L.net - now > -12 * 3600)) && L.net - now < windowHours * 3600; })
            .sort(function (a, b) { return a.net - b.net; })
            .forEach(function (L) {
                var k = (L.site || "") !== "" ? L.site : L.lat.toFixed(1) + "/" + L.lon.toFixed(1);
                if (!bySite[k]) { bySite[k] = L; L.more = 0; out.push(L); } else bySite[k].more++;
            });
        return out;
    })()
    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    function countdown(L) {
        var s = L.net - now;
        if (s < 0) return s > -120 ? "LIFT-OFF" : "lift-off " + Geo.spanText(-s / 3600) + " ago";
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = Math.floor(s % 60);
        if (s < 600) return "T−" + m + ":" + (sec < 10 ? "0" : "") + sec;                      // final approach: mm:ss
        return "T−" + (h >= 48 ? Math.round(h / 24) + " d" : h > 0 ? h + " h " + (m < 10 ? "0" : "") + m + " min" : m + " min");
    }
    function imminent(L) { return L.net - now < 600 && L.net - now > -120 }
    function describe(L) {
        // rocket and countdown on the first line; the mission (often a long payload name) on a line of its own
        var text = countdown(L) + (L.status !== "Go" && L.status !== "" ? " (" + L.status + ")" : "") + (L.more > 0 ? " · +" + L.more + " more here" : "");
        return labelMode === 2 ? L.rocket + " · " + text + (L.mission !== "" ? (twoLines ? "\n" : " · ") + L.mission : "") : text;
    }
    readonly property var labelSpecs: labelMode === 0 ? [] : shown.map(function (L) {
        return { x: px(L.lon), y: py(L.lat), gap: mark + 4 * unit, side: "right",
                 text: describe(L), px: imminent(L) ? Math.round(labelPx * 1.25) : labelPx, color: imminent(L) ? Qt.color("#ffd166") : labelColor, plate: labelPlate, bold: soon(L), alpha: 1 };
    })

    Exec {
        id: exec
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && !(r.launches && r.launches.length) && overlay.launches.length > 0) { console.warn("livemap launches: keeping the previous data -", r.note); overlay.note = r.note; return; }
                overlay.launches = r.launches || [];
                overlay.note = r.note || "";
                overlay.now = Date.now() / 1000;
                console.warn("livemap launches:", overlay.launches.length, "upcoming,", overlay.shown.length, "inside the window", overlay.note);
            } catch (e) { overlay.note = "Launches: the helper did not answer properly"; }
        }
    }
    Timer {                                       // the helper caches the list for an hour (Launch Library allows 15 requests an hour)
        interval: (overlay.slow ? 180 : 60) * 60000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' launches --stale " + overlay.staleHours + " # " + Date.now())
    }

    Repeater {
        model: overlay.shown
        Item {
            id: pad
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            Rectangle {                               // ripple in the last hour before lift-off
                readonly property real s: overlay.pulseSoon && overlay.soon(pad.modelData) && overlay.fps > 0 ? Geo.pulse(overlay.clock, 500 + pad.index, overlay.pulseMs, overlay.periodMs) : -1   // reads the clock only while pulsing: an idle ring costs nothing per tick
                visible: overlay.pulseSoon && overlay.soon(pad.modelData) && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                readonly property real boost: overlay.imminent(pad.modelData) ? 1.6 : 1
                width: overlay.mark * (2 + 4 * Math.max(0, s)) * boost; height: width; radius: width / 2
                color: "transparent"
                border.color: overlay.imminent(pad.modelData) ? Qt.rgba(1, 0.82, 0.4, (1 - Math.max(0, s)) * 0.95) : Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, (1 - Math.max(0, s)) * 0.85)
                border.width: 1.5 * overlay.unit * boost
            }
            readonly property real grow: overlay.imminent(modelData) ? 1.5 : 1   // the marker grows in the last ten minutes
            LaunchGlyph {                             // a rocket, standing on the pad
                visible: !overlay.pictures
                x: -width / 2; y: -height * 0.85
                size: overlay.mark * 2.4 * pad.grow
                color: overlay.ink
            }
            Image {                                   // or a picture: the rocket on its pad, lifting off once T-0 has passed
                visible: overlay.pictures
                source: overlay.pictures ? Qt.resolvedUrl("../images/" + (pad.modelData.net <= overlay.now ? "liftoff.png" : "pad.png")) : ""
                x: -width / 2; y: -height * 0.9
                width: overlay.pictureSize * 0.8 * pad.grow; height: overlay.pictureSize * pad.grow
                fillMode: Image.PreserveAspectFit
                sourceSize.height: 256
                smooth: true; mipmap: true
                asynchronous: true
            }
            Rectangle { anchors.centerIn: parent; width: 3 * overlay.unit; height: width; radius: width / 2; color: overlay.ink }
        }
    }
}
