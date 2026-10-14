/*
 * Wildfires from two sources, either or both:
 *  - GDACS fire events (the same UN/EU list the storms come from): one flame per event, coloured by GDACS's
 *    alert level (green, orange, red), labelled with place, burned area and how long it has been listed.
 *    Same life cycle as the other events: pulses while newly reported or when the level changes, ages out.
 *  - NASA FIRMS hotspots (MODIS, last 24 h, no key): satellite fire detections clustered into half-degree
 *    cells by the helper; a smaller flame in the fire colour, sized by fire radiative power, so the fires
 *    burning right now show even where GDACS has no event.
 *  - Named incidents from the agencies fighting them, with the perimeter where it is mapped: NIFC (US, every open
 *    wildfire with acres, containment, personnel), CWFIS (Canada, size and stage of control, satellite perimeter
 *    estimates) and EFFIS (Europe, Middle East, North Africa: burnt areas of the last weeks). A flame sized by area
 *    over the perimeter as a faint fill, labelled "Bouquet · 1.0k ac · 35 % contained · 600 personnel · 3 d".
 * Sources are a set (Wildfire sources in the settings); the incidents are on and the hotspots off by default.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import org.kde.plasma.plasma5support as P5Support
import "geo.js" as Geo

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    property bool slow: false

    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property color ink: cfg ? cfg.FireColor : "#ff5a1f"
    readonly property bool alertColors: cfg ? cfg.FireAlertColors : true
    readonly property var alertPalette: ({ green: "#5ec46a", orange: "#ff8c00", red: "#e53935" })
    function inkOf(fr) { return alertColors && alertPalette[fr.alert] ? Qt.color(alertPalette[fr.alert]) : ink }
    readonly property int sources: cfg ? cfg.FireSources : 29                 // bits: 1 GDACS, 2 NASA hotspots, 4 NIFC, 8 CWFIS, 16 EFFIS
    readonly property bool wantGdacs: (sources & 1) !== 0
    readonly property bool wantHot: (sources & 2) !== 0
    readonly property string incidentSources: [(sources & 4) ? "nifc" : "", (sources & 8) ? "cwfis" : "", (sources & 16) ? "effis" : ""].filter(function (x) { return x !== ""; }).join(",")
    readonly property real incidentMinHa: [0, 100, 1000, 10000][cfg ? cfg.FireIncidentMin : 1] || 0
    readonly property bool incidentActiveOnly: cfg ? cfg.FireIncidentActive : false
    readonly property int incidentMark: cfg ? cfg.FireIncidentMark : 0        // 0 flame and perimeter, 1 perimeter only (flame where none is mapped), 2 flame only
    readonly property bool showPerimeter: (cfg ? cfg.FirePerimeter : true) && incidentMark !== 2
    function flameShown(it) { return incidentMark !== 1 }                     // perimeter only: a dot where no perimeter is mapped
    function dotShown(it) { return incidentMark === 1 && !(it.area && it.area.length) }
    readonly property real perimeterOpacity: (cfg ? cfg.FirePerimeterOpacity : 25) / 100
    property var incidents: []
    // still burning: out of control or being held (Canada), under 90 % contained (US: a fire at 95 % with a skeleton crew
    // is winding down), or mapped in the last week (Europe, where there is no containment figure)
    function incidentActive(it) { return it.stage === "out of control" || it.stage === "being held" || (it.source === "nifc" && (it.contained === null || it.contained === undefined || it.contained < 90)) || (it.source === "effis" && it.days !== null && it.days < 7) }
    readonly property var shownIncidents: incidentSources === "" ? [] : incidents.filter(function (it) { return it.area_ha >= incidentMinHa && (!incidentActiveOnly || incidentActive(it)); })
        .sort(function (a, b) { return b.area_ha - a.area_ha; })
    function incidentSignificant(it) { return it.area_ha >= 1000 && incidentActive(it) }
    function describeIncident(it) {
        var parts = [it.name, areaText(it.area_ha)];
        if (it.contained !== null && it.contained !== undefined) parts.push(it.contained + " % contained");
        else if (it.stage) parts.push(it.stage);
        if (it.personnel) parts.push(it.personnel + " personnel");
        if (it.days !== null && it.days !== undefined) parts.push(it.days < 1 ? "today" : Math.round(it.days) + " d");
        return parts.join(" · ");
    }
    // Wildfire focus: 0 everything the filters allow, 1 near people (hotspots within 50 km of a city of 100 000 or on an
    // orange/red event; GDACS orange and red), 2 GDACS orange and red events only, no hotspots
    readonly property int fireFocus: cfg ? cfg.FireFocus : 1
    readonly property int hotMinCount: [3, 10, 25, 50][cfg ? cfg.HotspotMinCount : 1] || 10
    // 0 needs attention only, 1 notable and up, 2 everything: the helper rates every cell (tier 2 / 1 / 0) from
    // persistence, isolation, nearby cities and GDACS events, so a burning season does not cover the map
    readonly property int hotTier: cfg ? cfg.HotspotTier : 0
    readonly property int hotMinTier: [2, 1, 0][hotTier] === undefined ? 2 : [2, 1, 0][hotTier]
    property var hotspots: []
    function hotSignificant(c) { return c.tier === undefined ? (c.n >= 25 || c.frp >= 1000) : c.tier >= 2 }
    readonly property var shownHot: !wantHot || fireFocus === 2 ? [] : hotspots.filter(function (c) { return (c.tier === undefined ? 0 : c.tier) >= hotMinTier && (c.tier > 0 || c.n >= hotMinCount) && (fireFocus === 0 || c.people); })
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
    readonly property var shown: !wantGdacs ? [] : fires.filter(function (fr) { return levelOf(fr) >= Math.max(minLevel, fireFocus > 0 ? 1 : 0) && fr.area_ha >= minArea; })
        .sort(function (a, b) { return levelOf(b) - levelOf(a) || b.area_ha - a.area_ha; })
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    property real clock: 0
    // the pulse clock is shared: main.qml advances one clock for every layer, so all pulses move in the same frame
    readonly property bool pulseWanted: pulse && (shown.some(pulses) || ((pulseMode & 2) && (shownHot.some(hotSignificant) || shownIncidents.some(incidentSignificant))))

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
        // "29 km from Sydney · 3 d · 1.3 GW": why it matters, then what the satellites saw in that half-degree cell
        return { x: px(c.lon), y: py(c.lat), gap: mark * 0.5, side: "right",
                 text: (c.why ? c.why + " \u00b7 " : "") + powerText(c.frp) + " \u00b7 " + c.n + " det. \u00b7 " + Geo.spanText(c.hours), px: labelPx,
                 color: cfg && !cfg.FireTextFollows ? labelColor : ink, plate: labelPlate, bold: hotSignificant(c), alpha: 1 };
    })).concat(shownIncidents.filter(function (it) { return labelMode === 2 || incidentSignificant(it); }).map(function (it) {
        return { x: px(it.lon), y: py(it.lat), gap: flameShown(it) ? mark * 0.6 : mark * 0.3, side: "right", text: describeIncident(it), px: labelPx,
                 color: cfg && !cfg.FireTextFollows ? labelColor : ink, plate: labelPlate, bold: incidentSignificant(it), alpha: 1 };
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
                    overlay.note = !overlay.wantHot && overlay.incidentSources === "" ? r.note : "";
                    return;
                }
                overlay.fires = r.fires || [];
                overlay.note = r.note && ((!overlay.wantHot && overlay.incidentSources === "") || !(r.fires && r.fires.length)) ? r.note : "";
                console.warn("livemap fires:", overlay.fires.length, "current wildfire events", overlay.note);
            } catch (e) { overlay.note = "Wildfires: the helper did not answer properly"; }
        }
    }
    Timer {                                       // GDACS updates fires daily; hourly is plenty
        interval: (overlay.slow ? 180 : 60) * 60000
        running: overlay.helper !== "" && overlay.wantGdacs
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' fires --keep " + overlay.ageEnd + " --stale " + overlay.staleHours + " # " + Date.now())
    }
    P5Support.DataSource {
        id: incExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && !(r.incidents && r.incidents.length) && overlay.incidents.length > 0) { console.warn("livemap incidents: keeping the previous data -", r.note); return; }
                overlay.incidents = r.incidents || [];
                if (r.note) overlay.note = r.note;
                console.warn("livemap incidents:", overlay.incidents.length, "named fires", r.note || "");
            } catch (e) { console.warn("livemap incidents: the helper did not answer properly"); }
        }
    }
    function askIncidents() { incExec.connectSource("python3 '" + helper + "' incidents --sources " + incidentSources + " --min-ha " + incidentMinHa + " --keep " + ageEnd + " --stale " + staleHours + " # " + Date.now()) }
    Timer {                                       // the agencies update through the day; the helper caches each source for 30 minutes
        interval: (overlay.slow ? 90 : 30) * 60000
        running: overlay.helper !== "" && overlay.incidentSources !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: overlay.askIncidents()
    }
    onIncidentSourcesChanged: { if (helper !== "" && incidentSources !== "") askIncidents(); else incidents = []; }
    onIncidentMinHaChanged: if (helper !== "" && incidentSources !== "") askIncidents()
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
        running: overlay.helper !== "" && overlay.wantHot
        repeat: true
        triggeredOnStart: true
        onTriggered: hotExec.connectSource("python3 '" + overlay.helper + "' hotspots --min-tier " + overlay.hotMinTier + " --min-count " + overlay.hotMinCount + " # " + Date.now())
    }
    onHotMinCountChanged: if (helper !== "" && wantHot) hotExec.connectSource("python3 '" + helper + "' hotspots --min-tier " + hotMinTier + " --min-count " + hotMinCount + " # " + Date.now())
    onHotMinTierChanged: if (helper !== "" && wantHot) hotExec.connectSource("python3 '" + helper + "' hotspots --min-tier " + hotMinTier + " --min-count " + hotMinCount + " # " + Date.now())

    Repeater {                                    // incident perimeters, under every mark
        model: overlay.showPerimeter ? overlay.shownIncidents : []
        Shape {
            id: perim
            required property var modelData
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, overlay.perimeterOpacity)
                strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, Math.min(1, overlay.perimeterOpacity * 2.5))
                strokeWidth: Math.max(1, 0.8 * overlay.unit)
                PathMultiline { paths: overlay.project(perim.modelData.area || [], overlay.width, overlay.height) }
            }
        }
    }
    function project(rings, w, h) {
        var out = [];
        for (var i = 0; i < rings.length; i++) {
            var r = rings[i], o = [];
            for (var j = 0; j + 1 < r.length; j += 2) o.push(Qt.point((r[j] + 180) / 360 * w, (90 - r[j + 1]) / 180 * h));
            if (o.length >= 3) out.push(o);
        }
        return out;
    }
    Repeater {                                    // named incidents: a flame sized by area at the perimeter's centre
        model: overlay.shownIncidents
        Item {
            id: inc
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            readonly property real grow: 0.7 + 0.25 * Math.max(0, Math.log10(Math.max(1, modelData.area_ha) / 300))
            Rectangle {
                readonly property real s: Geo.pulse(overlay.clock, 2000 + inc.index, overlay.pulseMs, overlay.periodMs)
                visible: (overlay.pulseMode & 2) && overlay.incidentSignificant(inc.modelData) && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                width: overlay.mark * (1.2 + 3 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, (1 - Math.max(0, s)) * 0.85)
                border.width: 1.5 * overlay.unit
            }
            Rectangle {                                   // perimeter-only mode, no perimeter mapped: a dot sized by area
                visible: overlay.dotShown(inc.modelData)
                anchors.centerIn: parent
                width: overlay.mark * 0.45 * inc.grow; height: width; radius: width / 2
                color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, overlay.incidentActive(inc.modelData) ? 0.9 : 0.55)
                border.color: Qt.rgba(1, 0.93, 0.6, 0.6); border.width: Math.max(1, 0.6 * overlay.unit)
            }
            FireGlyph {
                visible: overlay.flameShown(inc.modelData)
                x: -width / 2; y: -height * 0.75
                size: overlay.mark * inc.grow
                color: overlay.ink
                alpha: overlay.incidentActive(inc.modelData) ? 1 : 0.6
            }
        }
    }
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
