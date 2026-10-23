/*
 * Volcanoes in the current Smithsonian / USGS Weekly Volcanic Activity Report (new every Wednesday), plus
 * every US volcano the USGS holds at an elevated alert level (Advisory yellow, Watch orange, Warning red;
 * the helper reads those from the USGS HANS API, with the date the level was raised where the CAP feed has it).
 * Every volcano is a hollow triangle in its level's colour. One scale for all of them: yellow = active (listed
 * in the weekly report, or USGS Advisory), orange = USGS Watch or a "New" eruption in the report, red = USGS
 * Warning. It pulses when it first appears and when its level changes, then sits steady.
 * A ripple (the same clock-driven ring as an earthquake, in this layer's colour) means newly reported and/or
 * a "New" eruption, as chosen in the settings: across the map a ring means "look here", whatever the layer.
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

    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property color ink: cfg ? cfg.VolcanoColor : "#ffb020"
    // USGS alert colours (Advisory / Watch / Warning), used for US volcanoes when the setting says so
    readonly property bool alertColors: cfg ? cfg.VolcanoAlertColors : true
    readonly property var alertPalette: ({ green: "#2fb344", yellow: "#ffe600", orange: "#ff7a00", red: "#e60000" })
    // one level for every volcano: 1 active (yellow), 2 watch (orange), 3 warning (red)
    function levelOf(v) { return v.alert === "red" ? 3 : v.alert === "orange" || v.status === "new" ? 2 : 1 }
    function inkOf(v) { return alertColors ? Qt.color(["", alertPalette.yellow, alertPalette.orange, alertPalette.red][levelOf(v)]) : ink }
    function labelInkOf(v) { return cfg && !cfg.VolcanoTextFollows ? labelColor : inkOf(v) }
    readonly property int labelMode: cfg ? cfg.VolcanoLabels : 1        // 0 none, 1 new activity only, 2 all
    readonly property bool labelPlate: cfg ? cfg.VolcanoLabelPlate : false
    readonly property color labelColor: cfg && !cfg.VolcanoTextFollows ? cfg.VolcanoTextColor : ink
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    readonly property int labelPx: Math.round((cfg ? cfg.VolcanoLabelSize : 9) * unit)
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: Math.round((cfg ? cfg.VolcanoLabelSize : 9) * 1.3 * unit * markScale)
    // what pulses: 0 nothing, 1 newly reported (first seen here less than pulseNewHours ago), 2 significant (the report's "New"), 3 either
    readonly property int pulseMode: cfg ? cfg.VolcanoPulseMode : 3
    readonly property bool pulse: pulseMode > 0
    // significant: the report's "New" eruption, or a USGS Watch / Warning (orange / red)
    function significant(v) { return v.status === "new" || v.alert === "orange" || v.alert === "red" }
    function pulses(v) { return !!(!v.gone && (((pulseMode & 1) && v.firstHours >= 0 && v.firstHours < pulseNewHours) || ((pulseMode & 2) && significant(v)))) }
    readonly property bool detail: cfg ? cfg.VolcanoDetail : true
    property var volcanoes: []
    property int fps: 30                      // animation clock, as in the earthquake layer; 0 = frozen
    property real clock: 0
    // the pulse clock is shared: main.qml advances one clock for every layer, so all pulses move in the same frame
    readonly property bool pulseWanted: pulse && placed.some(pulses)
    readonly property real pulseNewHours: cfg ? cfg.PulseNewHours : 3
    readonly property bool ageFade: cfg ? cfg.AgeFade : true
    readonly property real ageStart: cfg ? cfg.AgeFadeStart : 12
    readonly property real ageEnd: cfg ? cfg.AgeFadeEnd : 48
    readonly property color agedColor: cfg ? cfg.AgedColor : "#8b97a8"
    function agedOf(v) { return ageFade ? Geo.ageMix(v.gone ? v.hours : 0, ageStart, ageEnd) : 0 }
    function isNew(v) { return v.status === "new" || (v.firstHours >= 0 && v.firstHours < pulseNewHours) }
    // Standard label: the name, then how long the volcano has been above normal - the USGS date where the CAP
    // feed has it, else the eruption start date from the Smithsonian database. Nothing when neither is known.
    // Colour (USGS level), a bolder triangle and the pulse say the rest.
    function elevatedOf(v) {
        if (v.alert !== "" && v.elevatedHours >= 0) return v.elevatedHours;   // USGS: when the level left green
        if (v.sinceHours >= 0) return v.sinceHours;                          // Smithsonian: eruption start date
        return -1;                                 // no real date: say nothing rather than "since this computer noticed"
    }
    function describe(v) {
        var h = elevatedOf(v);
        var ash = v.ashHours >= 0 ? " \u00b7 ash" + (v.ashTop ? " to FL" + v.ashTop : "") + " \u00b7 " + Geo.spanText(v.ashHours) : "";
        return v.name + (detail && h >= 0 ? " \u00b7 " + Geo.spanText(h) : "") + (detail ? ash : "");
    }
    property string note: ""
    readonly property string hint: note

    // new activity first, so it gets its label space first
    readonly property var placed: volcanoes.map(function (v) {
            var was = (v.changed_from || "").split("/");               // helper signature "alert/status", e.g. "yellow/continuing"
            return { name: v.name, lat: v.lat, lon: v.lon, status: v.status || (v["new"] ? "new" : "continuing"), since: v.since || "",
                     alert: v.alert || "", level: v.level || "", alertSince: v.alert_since || "",
                     elevatedHours: v.elevated_hours === undefined || v.elevated_hours === null ? -1 : v.elevated_hours,
                     sinceHours: v.since_hours === undefined || v.since_hours === null ? -1 : v.since_hours,
                     changedFrom: v.changed_from ? (was[0] !== "" ? was[0] : was[1] === "new" ? "new eruption" : was[1] || "") : "",
                     changedHours: v.changed_hours === undefined || v.changed_hours === null ? 9999 : v.changed_hours,
                     firstHours: v.first_hours === undefined || v.first_hours === null ? -1 : v.first_hours, gone: !!v.gone, hours: v.hours || 0,
                     ashHours: v.ash_hours === undefined || v.ash_hours === null ? -1 : v.ash_hours, ashTop: v.ash_top_fl || 0,
                     ashRings: v.ash_rings || [], ashForecast: v.ash_forecast || [] };
        }).map(function (v) { v.fresh = isNew(v); return v; })
        .sort(function (a, b) { return ((b.fresh ? 2 : 0) + (significant(b) ? 1 : 0)) - ((a.fresh ? 2 : 0) + (significant(a) ? 1 : 0)); })
    // What this layer wants labelled; main.qml's LabelPass draws these above everything.
    readonly property var labelSpecs: labelMode === 0 ? [] : placed.filter(function (v) { return labelMode === 2 || v.fresh || significant(v); }).map(function (v) {
        return { x: (v.lon + 180) / 360 * width, y: (90 - v.lat) / 180 * height, gap: mark * 0.7, side: "right",
                 text: describe(v), px: labelPx, color: Geo.mix(labelInkOf(v), agedColor, agedOf(v)), plate: labelPlate, bold: v.fresh || significant(v),
                 alpha: 1 - 0.4 * agedOf(v) };
    })

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && !(r.volcanoes && r.volcanoes.length) && overlay.volcanoes.length > 0) {   // nothing came: keep what we have
                    console.warn("livemap volcanoes: keeping the previous data -", r.note);
                    overlay.note = r.note;
                    return;
                }
                overlay.volcanoes = r.volcanoes || [];
                overlay.note = r.note || "";
                console.warn("livemap volcanoes:", overlay.volcanoes.length, "in this week's report", overlay.note);
            } catch (e) { overlay.note = "Volcanoes: the helper did not answer properly"; }
        }
    }
    Timer {                                       // the report is weekly, but USGS alert levels can change any hour
        interval: 3600000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' volcanoes --keep " + overlay.ageEnd + " --stale " + overlay.staleHours + " # " + Date.now())
    }

    // the ash clouds under advisory: the observed outline, and the forecast ones fainter (Washington VAAC)
    function ashPaths(forecast) {
        var out = [];
        for (var i = 0; i < placed.length; i++) {
            var rings = forecast ? placed[i].ashForecast : placed[i].ashRings;
            if (placed[i].ashHours < 0 || placed[i].ashHours > 12) continue;
            for (var j = 0; j < rings.length; j++) {
                var r = rings[j], pts = [];
                for (var k = 0; k + 1 < r.length; k += 2) pts.push(Qt.point((r[k] + 180) / 360 * width, (90 - r[k + 1]) / 180 * height));
                if (pts.length >= 3) out.push(pts);
            }
        }
        return out;
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath { strokeColor: Qt.rgba(0.75, 0.72, 0.68, 0.25); strokeWidth: Math.max(1, 0.8 * overlay.unit); fillColor: Qt.rgba(0.75, 0.72, 0.68, 0.06)
                    PathMultiline { paths: overlay.ashPaths(true) } }
        ShapePath { strokeColor: Qt.rgba(0.8, 0.76, 0.7, 0.7); strokeWidth: Math.max(1, 1.2 * overlay.unit); fillColor: Qt.rgba(0.8, 0.76, 0.7, 0.18)
                    PathMultiline { paths: overlay.ashPaths(false) } }
    }
    Repeater {
        model: overlay.placed
        Item {
            id: peak
            required property var modelData
            required property int index
            x: (modelData.lon + 180) / 360 * overlay.width
            y: (90 - modelData.lat) / 180 * overlay.height
            Rectangle {                                   // ripple for new activity: the earthquake layer's ring, this layer's colour
                readonly property real s: Geo.pulse(overlay.clock, peak.index, overlay.pulseMs, overlay.periodMs)
                visible: overlay.pulses(peak.modelData) && overlay.fps > 0 && s >= 0
                anchors.centerIn: parent
                width: overlay.mark * (1.4 + 3.2 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                readonly property color tint: overlay.inkOf(peak.modelData)
                border.color: Qt.rgba(tint.r, tint.g, tint.b, (1 - Math.max(0, s)) * 0.85)
                border.width: 1.5 * overlay.unit
            }
            HaloText {                                    // the triangle itself is a glyph: no geometry to get wrong
                x: -width / 2; y: -height * 0.62
                text: "\u25B3"                            // hollow for all: the colour carries the level, the pulse the news
                font.bold: peak.modelData.fresh || overlay.significant(peak.modelData)
                color: Geo.mix(overlay.inkOf(peak.modelData), overlay.agedColor, overlay.agedOf(peak.modelData))
                opacity: 1 - 0.4 * overlay.agedOf(peak.modelData)
                haloWidth: Math.max(1, overlay.unit)
                font.pixelSize: overlay.mark
            }
        }
    }
}
