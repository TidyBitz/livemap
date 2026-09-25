/*
 * Earthquakes from the USGS GeoJSON feed (no key needed).
 * This file is also the template for any "fetch JSON, draw points" overlay:
 * copy it, change the URL and the parsing, add a Loader + checkbox.
 */
import QtQuick
import "geo.js" as Geo

Item {
    id: overlay

    property var cfg: null
    readonly property var feeds: ["2.5_day", "4.5_day", "significant_week"]
    readonly property string feedUrl: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/"
        + feeds[cfg ? cfg.QuakeFeed : 1] + ".geojson"
    readonly property real unit: Math.max(1, width / 1920)     // keeps sizes sane on 4K
    readonly property color ring: cfg ? cfg.QuakeColor : "#ffa640"
    readonly property color ringLight: Qt.lighter(ring, 1.35)
    readonly property real sizeScale: (cfg ? cfg.QuakeSize : 100) / 100 * ((cfg ? cfg.MarkerScale : 100) / 100)
    // what pulses: 0 nothing, 1 newly reported (younger than pulseNewHours), 2 significant (at least pulseMag), 3 either
    readonly property int pulseMode: cfg ? cfg.QuakePulseMode : 3
    readonly property bool pulse: pulseMode > 0
    readonly property real pulseNewHours: cfg ? cfg.PulseNewHours : 3
    readonly property real pulseMag: (cfg ? cfg.QuakePulseMag : 55) / 10
    function pulses(e) { return !!(((pulseMode & 1) && e.hours < pulseNewHours) || ((pulseMode & 2) && e.mag >= pulseMag)) }
    // ageing: an event older than ageStart hours drifts towards agedColor, fully there at ageEnd hours
    readonly property bool ageFade: cfg ? cfg.AgeFade : true
    readonly property real ageStart: cfg ? cfg.AgeFadeStart : 12
    readonly property real ageEnd: cfg ? cfg.AgeFadeEnd : 48
    readonly property color agedColor: cfg ? cfg.AgedColor : "#8b97a8"
    function agedOf(e) { return ageFade ? Geo.ageMix(e.hours, ageStart, ageEnd) : 0 }
    property var quakes: []

    // labels: 0 none, 1 magnitude, 2 magnitude, place and age; only from a chosen magnitude up
    readonly property int labelMode: cfg ? cfg.QuakeLabels : 2
    readonly property real labelMin: [0, 5, 6][cfg ? cfg.QuakeLabelMin : 0] || 0
    readonly property bool labelPlate: cfg ? cfg.QuakeLabelPlate : true
    readonly property color labelColor: cfg && !cfg.QuakeTextFollows ? cfg.QuakeTextColor : ringLight
    readonly property int labelPx: Math.round((cfg ? cfg.QuakeLabelSize : 10) * unit)
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    // ring radius: M4 about 11 px, M6 about 28 px, M7 about 45 px on a 1920-wide screen (times the size setting)
    function reachOf(mag) { return Math.pow(1.6, mag) * 1.6 * unit * sizeScale }
    function labelFor(e) {
        return "M" + e.mag.toFixed(1) + (labelMode === 2 ? (e.place !== "" ? " \u00b7 " + e.place : "") + " \u00b7 " + Geo.ageText(e.hours) : "");
    }
    // two-line form: the place above, magnitude and age below (see LabelPass)
    function labelFor2(e) {
        return labelMode !== 2 ? "" : (e.place !== "" ? e.place + "\n" : "") + "M" + e.mag.toFixed(1) + " \u00b7 " + Geo.ageText(e.hours);
    }
    // What this layer wants labelled; main.qml's LabelPass draws these above everything (see Geo.placeLabels).
    // Strongest first, so when two are close the stronger one gets the space.
    readonly property var labelSpecs: labelMode === 0 ? [] : quakes.filter(function (e) { return e.mag >= labelMin; }).map(function (e) {
        return { x: (e.lon + 180) / 360 * width, y: (90 - e.lat) / 180 * height, gap: reachOf(e.mag) + 5 * unit, side: "right",
                 text: labelFor(e), text2: labelFor2(e), px: labelPx, color: Geo.mix(labelColor, agedColor, agedOf(e)), plate: labelPlate, alpha: 1 - 0.4 * agedOf(e) };
    })
    property int pulsingCount: 0
    // Animation clock. Qt's own animations run at the monitor's refresh rate and force a full redraw
    // each time; stepping a clock with a Timer lets the settings choose 10-60 updates a second, and
    // with fps 0 (on battery) or nothing to pulse, the timer stops and nothing is redrawn at all.
    property int fps: 30
    property real clock: 0
    Timer {
        interval: Math.round(1000 / Math.max(1, overlay.fps))
        running: overlay.fps > 0 && overlay.pulse && overlay.pulsingCount > 0
        repeat: true
        onTriggered: overlay.clock += interval
    }
    property int reports: 0          // only the first few refreshes are written to the journal

    function refresh() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) { console.warn("livemap quakes: request failed, HTTP status", xhr.status, overlay.feedUrl); return; }
            try {
                var f = JSON.parse(xhr.responseText).features, out = [], nowMs = Date.now();
                for (var i = 0; i < f.length; i++) {
                    var c = f[i].geometry.coordinates, p = f[i].properties;
                    out.push({ lon: c[0], lat: c[1], mag: p.mag || 0, place: Geo.quakePlace(p.place || ""),
                               hours: (nowMs - p.time) / 3600000 });
                }
                out.sort(function (a, b) { return b.mag - a.mag; });     // strongest first: they get their labels first
                overlay.quakes = out;
                overlay.pulsingCount = out.filter(overlay.pulses).length;
                if (overlay.reports++ < 3) console.warn("livemap quakes:", out.length, "events from the feed ->", rings.count, "drawn, layer is",
                             Math.round(overlay.width) + "x" + Math.round(overlay.height),
                             out.length ? "- first at " + out[0].lat.toFixed(1) + "," + out[0].lon.toFixed(1) + " M" + out[0].mag : "");
            } catch (e) { console.warn("livemap quakes:", e); }
        };
        xhr.open("GET", feedUrl);
        xhr.send();
    }

    onFeedUrlChanged: if (poll.running) refresh()
    Timer { id: poll; interval: 300000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: overlay.refresh() }

    Repeater {
        id: rings
        model: overlay.quakes
        Item {
            id: q
            required property var modelData
            required property int index
            x: (modelData.lon + 180) / 360 * overlay.width
            y: (90 - modelData.lat) / 180 * overlay.height
            // ring radius grows with magnitude; everything fades as the quake ages
            readonly property real reach: overlay.reachOf(modelData.mag)
            readonly property real aged: overlay.agedOf(modelData)
            readonly property real fresh: 1 - 0.6 * aged
            readonly property color tone: Geo.mix(overlay.ring, overlay.agedColor, aged)
            readonly property color toneLight: Geo.mix(overlay.ringLight, overlay.agedColor, aged)
            readonly property bool pulsing: overlay.pulse && overlay.pulses(modelData)

            Rectangle {                                   // static footprint
                anchors.centerIn: parent
                width: q.reach * 2; height: width; radius: width / 2
                color: Qt.rgba(q.tone.r, q.tone.g, q.tone.b, 0.10 * q.fresh)
                border.color: Qt.rgba(q.tone.r, q.tone.g, q.tone.b, 0.6 * q.fresh)
                border.width: overlay.unit
            }
            Rectangle {                                   // expanding ripple, only for fresh or big ones
                id: ripple
                // duration and repeat period come from the settings; every quake starts at a different point of the cycle
                readonly property real s: Geo.pulse(overlay.clock, q.index, overlay.pulseMs, overlay.periodMs)
                visible: q.pulsing && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                width: q.reach * 2 * (1 + 1.6 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(q.toneLight.r, q.toneLight.g, q.toneLight.b, (1 - Math.max(0, s)) * 0.8)
                border.width: 1.5 * overlay.unit
            }
            Rectangle {                                   // epicentre
                anchors.centerIn: parent
                width: 3 * overlay.unit; height: width; radius: width / 2
                color: Qt.rgba(q.toneLight.r, q.toneLight.g, q.toneLight.b, q.fresh)
            }
        }
    }
}
