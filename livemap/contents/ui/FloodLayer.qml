/*
 * Floods from GDACS (the same UN/EU list the storms and wildfires come from, eventtype FL): one event per river
 * basin or region, rated green, orange or red on the people exposed. Drawn as a wave mark coloured by the alert
 * level, the affected area as a faint fill underneath (orange and red events; the helper fetches their polygons),
 * labelled with the place, what happened to people (dead, evacuated, displaced - GDACS's Sendai figures) and
 * how long the flood has been running. Green events are a basin's seasonal high water and are off by default:
 * the layer shows orange and red only unless asked otherwise. Same life cycle as the other events: pulses while
 * newly reported or when the level changes, ages out once GDACS drops it.
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

    readonly property real unit: Math.max(1, Screen.width / 1920)
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property color ink: cfg ? cfg.FloodColor : "#4aa3ff"
    readonly property bool alertColors: cfg ? cfg.FloodAlertColors : true
    readonly property var alertPalette: ({ green: "#5ec46a", orange: "#ff8c00", red: "#e53935" })
    function inkOf(fl) { return alertColors && alertPalette[fl.alert] ? Qt.color(alertPalette[fl.alert]) : ink }
    readonly property int minLevel: cfg ? cfg.FloodMinLevel : 1            // 0 all, 1 orange and red, 2 red only
    function levelOf(fl) { return fl.alert === "red" ? 2 : fl.alert === "orange" ? 1 : 0 }
    readonly property bool showArea: cfg ? cfg.FloodArea : true
    readonly property real areaOpacity: (cfg ? cfg.FloodAreaOpacity : 25) / 100
    readonly property int labelMode: cfg ? cfg.FloodLabels : 1             // 0 none, 1 orange and red, 2 all
    readonly property int labelPx: Math.round((cfg ? cfg.FloodLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.FloodLabelPlate : true
    readonly property color labelColor: cfg && !cfg.FloodTextFollows ? cfg.FloodTextColor : ink
    function labelInkOf(fl) { return cfg && !cfg.FloodTextFollows ? labelColor : inkOf(fl) }
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: Math.round((cfg ? cfg.FloodLabelSize : 10) * 1.5 * unit * markScale)
    readonly property int pulseMode: cfg ? cfg.FloodPulseMode : 3
    readonly property bool pulse: pulseMode > 0
    readonly property real pulseNewHours: cfg ? cfg.PulseNewHours : 3
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    readonly property bool ageFade: cfg ? cfg.AgeFade : true
    readonly property real ageStart: cfg ? cfg.AgeFadeStart : 12
    readonly property real ageEnd: cfg ? cfg.AgeFadeEnd : 48
    readonly property color agedColor: cfg ? cfg.AgedColor : "#8b97a8"
    function agedOf(fl) { return ageFade ? Geo.ageMix(fl.gone ? fl.hours : 0, ageStart, ageEnd) : 0 }
    function significant(fl) { return fl.alert === "orange" || fl.alert === "red" }
    function pulses(fl) {
        var first = fl.first_hours === undefined || fl.first_hours === null ? -1 : fl.first_hours;
        return !!(!fl.gone && (((pulseMode & 1) && first >= 0 && first < pulseNewHours) || ((pulseMode & 2) && significant(fl))));
    }
    property var floods: []
    readonly property var shown: floods.filter(function (fl) { return levelOf(fl) >= minLevel; })
        .sort(function (a, b) { return levelOf(b) - levelOf(a) || (b.days || 0) - (a.days || 0); })
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    property real clock: 0
    Timer {
        interval: Math.round(1000 / Math.max(1, overlay.fps))
        running: overlay.fps > 0 && overlay.pulse && overlay.shown.some(overlay.pulses)
        repeat: true
        onTriggered: overlay.clock += interval
    }

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    function project(rings, w, h) {               // flat [lon, lat, ...] rings -> [[x, y, x, y, ...], ...]
        var out = [];
        for (var i = 0; i < rings.length; i++) {
            var r = rings[i], o = [];
            for (var j = 0; j + 1 < r.length; j += 2) o.push(Qt.point((r[j] + 180) / 360 * w, (90 - r[j + 1]) / 180 * h));
            if (o.length >= 3) out.push(o);
        }
        return out;
    }
    readonly property var words: ({ death: "dead", deaths: "dead", killed: "dead" })
    function thousands(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, "\u202f") }
    function peopleText(fl) {
        return (fl.people || []).map(function (p) { return thousands(p[1]) + " " + (words[p[0]] || p[0]); }).join(", ");
    }
    function describe(fl) {
        // "Italy · 3 dead, 1 200 evacuated · 2 d" (the mark's colour is the alert level)
        var text = fl.name, people = peopleText(fl);
        if (people !== "") text += " · " + people;
        if (fl.days !== undefined && fl.days !== null) text += " · " + (fl.days < 1 ? "today" : Math.round(fl.days) + " d");
        return text;
    }
    readonly property var labelSpecs: labelMode === 0 ? [] : shown.filter(function (fl) { return labelMode === 2 || significant(fl); }).map(function (fl) {
        return { x: px(fl.lon), y: py(fl.lat), gap: mark * 0.6, side: "right",
                 text: describe(fl), px: labelPx, color: Geo.mix(labelInkOf(fl), agedColor, agedOf(fl)), plate: labelPlate,
                 bold: significant(fl), alpha: 1 - 0.4 * agedOf(fl) };
    })

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && !(r.floods && r.floods.length) && overlay.floods.length > 0) {
                    console.warn("livemap floods: keeping the previous data -", r.note);
                    overlay.note = r.note;
                    return;
                }
                overlay.floods = r.floods || [];
                overlay.note = r.note || "";
                console.warn("livemap floods:", overlay.floods.length, "current flood events", overlay.note);
            } catch (e) { overlay.note = "Floods: the helper did not answer properly"; }
        }
    }
    function ask() { exec.connectSource("python3 '" + helper + "' floods --keep " + ageEnd + " --stale " + staleHours + (minLevel === 0 ? " --all" : "") + " # " + Date.now()) }
    Timer {                                       // GDACS updates floods a few times a day; hourly is plenty
        interval: (overlay.slow ? 180 : 60) * 60000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: overlay.ask()
    }
    onMinLevelChanged: if (helper !== "") ask()

    Repeater {                                    // the affected areas, under every mark
        model: overlay.showArea ? overlay.shown : []
        Shape {
            id: area
            required property var modelData
            required property int index
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            readonly property color tone: Geo.mix(overlay.inkOf(modelData), overlay.agedColor, overlay.agedOf(modelData))
            ShapePath {
                fillColor: Qt.rgba(area.tone.r, area.tone.g, area.tone.b, overlay.areaOpacity * (1 - 0.5 * overlay.agedOf(area.modelData)))
                strokeColor: Qt.rgba(area.tone.r, area.tone.g, area.tone.b, Math.min(1, overlay.areaOpacity * 2.5))
                strokeWidth: Math.max(1, 0.8 * overlay.unit)
                PathMultiline { paths: overlay.project(area.modelData.area || [], overlay.width, overlay.height) }
            }
        }
    }

    Repeater {
        model: overlay.shown
        Item {
            id: flood
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            readonly property real aged: overlay.agedOf(modelData)
            readonly property color tone: Geo.mix(overlay.inkOf(modelData), overlay.agedColor, aged)
            readonly property real grow: 1 + 0.2 * overlay.levelOf(modelData)
            Rectangle {                                   // ripple: same ring as the other layers
                readonly property real s: Geo.pulse(overlay.clock, flood.index, overlay.pulseMs, overlay.periodMs)
                visible: overlay.pulses(flood.modelData) && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                width: overlay.mark * (1.2 + 3 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(flood.tone.r, flood.tone.g, flood.tone.b, (1 - Math.max(0, s)) * 0.85)
                border.width: 1.5 * overlay.unit
            }
            FloodGlyph {
                x: -width / 2; y: -height / 2
                size: overlay.mark * flood.grow
                color: flood.tone
                alpha: 1 - 0.4 * flood.aged
                lineWidth: Math.max(1, 1.3 * overlay.unit)
            }
        }
    }
}
