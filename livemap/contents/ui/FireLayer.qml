/*
 * Wildfires from two sources, either or both:
 *  - GDACS fire events (the same UN/EU list the storms come from): one flame per event, coloured by GDACS's
 *    alert level (green, orange, red), labelled with place, burned area and how long it has been listed.
 *    Same life cycle as the other events: pulses while newly reported or when the level changes, ages out.
 *  - NASA FIRMS hotspots (MODIS, last 24 h, no key): satellite fire detections clustered into half-degree
 *    cells by the helper; a smaller flame in the fire colour, sized by fire radiative power, so the fires
 *    burning right now show even where GDACS has no event.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "geo.js" as Geo

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    property bool slow: false

    readonly property real unit: Math.max(1, width / 1920)
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property color ink: cfg ? cfg.FireColor : "#ff5a1f"
    readonly property bool alertColors: cfg ? cfg.FireAlertColors : true
    readonly property var alertPalette: ({ green: "#5ec46a", orange: "#ff8c00", red: "#e53935" })
    function inkOf(fr) { return alertColors && alertPalette[fr.alert] ? Qt.color(alertPalette[fr.alert]) : ink }
    readonly property int feedChoice: cfg ? cfg.FireSource : 2                // 0 GDACS events, 1 NASA hotspots, 2 both
    readonly property int hotMinCount: [3, 10, 25, 50][cfg ? cfg.HotspotMinCount : 1] || 10
    property var hotspots: []
    function hotSignificant(c) { return c.n >= 25 || c.frp >= 1000 }
    readonly property var shownHot: feedChoice === 0 ? [] : hotspots.filter(function (c) { return c.n >= hotMinCount; })
    readonly property int minLevel: cfg ? cfg.FireMinLevel : 0            // 0 all, 1 orange and red, 2 red only
    readonly property real minArea: [0, 1000, 10000, 50000][cfg ? cfg.FireMinArea : 0] || 0
    function levelOf(fr) { return fr.alert === "red" ? 2 : fr.alert === "orange" ? 1 : 0 }
    readonly property int labelMode: cfg ? cfg.FireLabels : 1             // 0 none, 1 orange and red, 2 all
    readonly property int labelPx: Math.round((cfg ? cfg.FireLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.FireLabelPlate : true
    readonly property color labelColor: cfg && !cfg.FireTextFollows ? cfg.FireTextColor : ink
    function labelInkOf(fr) { return cfg && !cfg.FireTextFollows ? labelColor : inkOf(fr) }
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: Math.round((cfg ? cfg.FireLabelSize : 10) * 1.5 * unit * markScale)
    readonly property int pulseMode: cfg ? cfg.FirePulseMode : 3
    readonly property bool pulse: pulseMode > 0
    readonly property real pulseNewHours: cfg ? cfg.PulseNewHours : 3
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    readonly property bool ageFade: cfg ? cfg.AgeFade : true
    readonly property real ageStart: cfg ? cfg.AgeFadeStart : 12
    readonly property real ageEnd: cfg ? cfg.AgeFadeEnd : 48
    readonly property color agedColor: cfg ? cfg.AgedColor : "#8b97a8"
    function agedOf(fr) { return ageFade ? Geo.ageMix(fr.gone ? fr.hours : 0, ageStart, ageEnd) : 0 }
    function significant(fr) { return fr.alert === "orange" || fr.alert === "red" }
    function pulses(fr) {
        var first = fr.first_hours === undefined || fr.first_hours === null ? -1 : fr.first_hours;
        return !!(!fr.gone && (((pulseMode & 1) && first >= 0 && first < pulseNewHours) || ((pulseMode & 2) && significant(fr))));
    }
    property var fires: []
    readonly property var shown: feedChoice === 1 ? [] : fires.filter(function (fr) { return levelOf(fr) >= minLevel && fr.area_ha >= minArea; })
        .sort(function (a, b) { return levelOf(b) - levelOf(a) || b.area_ha - a.area_ha; })
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    property real clock: 0
    Timer {
        interval: Math.round(1000 / Math.max(1, overlay.fps))
        running: overlay.fps > 0 && overlay.pulse && (overlay.shown.some(overlay.pulses) || ((overlay.pulseMode & 2) && overlay.shownHot.some(overlay.hotSignificant)))
        repeat: true
        onTriggered: overlay.clock += interval
    }

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    readonly property int units: cfg ? cfg.DistanceUnits : 0
    function areaText(ha) { return Geo.areaText(ha, units) }
    function describe(fr) {
        // "Vanuatu · 6.2k ha · 3 d" (the flame's colour is the alert level)
        var text = fr.name + " · " + areaText(fr.area_ha);
        var first = fr.first_hours === undefined || fr.first_hours === null ? -1 : fr.first_hours;
        if (first >= 0) text += " · " + Geo.spanText(first);
        return text;
    }
    function powerText(mw) { return mw >= 1000 ? (mw / 1000).toFixed(1) + " GW" : mw + " MW" }
    readonly property var labelSpecs: labelMode === 0 ? [] : shown.filter(function (fr) { return labelMode === 2 || significant(fr); }).map(function (fr) {
        return { x: px(fr.lon), y: py(fr.lat), gap: mark * 0.6, side: "right",
                 text: describe(fr), px: labelPx, color: Geo.mix(labelInkOf(fr), agedColor, agedOf(fr)), plate: labelPlate,
                 bold: significant(fr), alpha: 1 - 0.4 * agedOf(fr) };
    }).concat(shownHot.filter(function (c) { return labelMode === 2 ? c.n >= 10 : hotSignificant(c); }).map(function (c) {
        // "38 detections · 1.3 GW · 4 h": what the satellites saw in that half-degree cell
        return { x: px(c.lon), y: py(c.lat), gap: mark * 0.5, side: "right",
                 text: c.n + " detections \u00b7 " + powerText(c.frp) + " \u00b7 " + Geo.spanText(c.hours), px: labelPx,
                 color: cfg && !cfg.FireTextFollows ? labelColor : ink, plate: labelPlate, bold: hotSignificant(c), alpha: 1 };
    }))

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && !(r.fires && r.fires.length) && overlay.fires.length > 0) {
                    console.warn("livemap fires: keeping the previous data -", r.note);
                    // with the satellite hotspots also on, a GDACS hiccup is not worth a notice on the desktop
                    overlay.note = overlay.feedChoice === 0 ? r.note : "";
                    return;
                }
                overlay.fires = r.fires || [];
                overlay.note = r.note && (overlay.feedChoice === 0 || !(r.fires && r.fires.length)) ? r.note : "";
                console.warn("livemap fires:", overlay.fires.length, "current wildfire events", overlay.note);
            } catch (e) { overlay.note = "Wildfires: the helper did not answer properly"; }
        }
    }
    Timer {                                       // GDACS updates fires daily; hourly is plenty
        interval: (overlay.slow ? 180 : 60) * 60000
        running: overlay.helper !== "" && overlay.feedChoice !== 1
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' fires --keep " + overlay.ageEnd + " --stale " + overlay.staleHours + " # " + Date.now())
    }
    P5Support.DataSource {
        id: hotExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && overlay.hotspots.length > 0) { console.warn("livemap hotspots: keeping the previous data -", r.note); return; }
                overlay.hotspots = r.hotspots || [];
                if (r.note) overlay.note = r.note;
                console.warn("livemap hotspots:", overlay.hotspots.length, "cells with " + overlay.hotMinCount + "+ detections", r.note || "");
            } catch (e) { console.warn("livemap hotspots: the helper did not answer properly"); }
        }
    }
    Timer {                                       // FIRMS's 24 h file is refreshed through the day; the helper caches it for 3 h
        interval: (overlay.slow ? 360 : 180) * 60000
        running: overlay.helper !== "" && overlay.feedChoice !== 0
        repeat: true
        triggeredOnStart: true
        onTriggered: hotExec.connectSource("python3 '" + overlay.helper + "' hotspots --min-count " + overlay.hotMinCount + " # " + Date.now())
    }
    onHotMinCountChanged: if (helper !== "" && feedChoice !== 0) hotExec.connectSource("python3 '" + helper + "' hotspots --min-count " + hotMinCount + " # " + Date.now())

    Repeater {                                    // satellite hotspots: small flames, the fire colour, sized by power
        model: overlay.shownHot
        Item {
            id: hot
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            readonly property real grow: 0.45 + 0.18 * Math.log10(Math.max(1, modelData.frp) / 10)
            Rectangle {
                readonly property real s: Geo.pulse(overlay.clock, 1000 + hot.index, overlay.pulseMs, overlay.periodMs)
                visible: (overlay.pulseMode & 2) && overlay.hotSignificant(hot.modelData) && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                width: overlay.mark * (1.2 + 3 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, (1 - Math.max(0, s)) * 0.85)
                border.width: 1.5 * overlay.unit
            }
            // a plain dot for the many ordinary cells (a Rectangle is a single scene-graph node, no texture);
            // the drawn flame only where it earns its cost
            Rectangle {
                visible: !overlay.hotSignificant(hot.modelData)
                anchors.centerIn: parent
                width: overlay.mark * Math.max(0.35, hot.grow) * 0.55; height: width; radius: width / 2
                color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.85)
                border.color: Qt.rgba(1, 0.93, 0.6, 0.6); border.width: Math.max(1, 0.6 * overlay.unit)
            }
            Loader {
                active: overlay.hotSignificant(hot.modelData)
                x: -width / 2; y: -height * 0.75
                sourceComponent: FireGlyph {
                    size: overlay.mark * Math.max(0.35, hot.grow)
                    color: overlay.ink
                    alpha: 0.9
                }
            }
        }
    }

    Repeater {
        model: overlay.shown
        Item {
            id: fire
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            readonly property real aged: overlay.agedOf(modelData)
            readonly property color tone: Geo.mix(overlay.inkOf(modelData), overlay.agedColor, aged)
            // flame height: by burned area (1 000 ha small, 100 000 ha about twice that), a step up per alert level
            readonly property real grow: (0.7 + 0.25 * Math.max(0, Math.log10(Math.max(1, modelData.area_ha) / 1000))) * (1 + 0.2 * overlay.levelOf(modelData))
            Rectangle {                                   // ripple: same ring as the other layers
                readonly property real s: Geo.pulse(overlay.clock, fire.index, overlay.pulseMs, overlay.periodMs)
                visible: overlay.pulses(fire.modelData) && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                width: overlay.mark * (1.2 + 3 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(fire.tone.r, fire.tone.g, fire.tone.b, (1 - Math.max(0, s)) * 0.85)
                border.width: 1.5 * overlay.unit
            }
            FireGlyph {
                x: -width / 2; y: -height * 0.75
                size: overlay.mark * fire.grow
                color: fire.tone
                alpha: 1 - 0.4 * fire.aged
            }
        }
    }
}
