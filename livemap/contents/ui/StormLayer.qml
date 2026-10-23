/*
 * Tropical cyclones (hurricanes, typhoons, cyclones) worldwide, from GDACS - the UN/EU Global Disaster
 * Alert and Coordination System. No key. The helper fetches the list and each storm's track geometry and
 * hands over: past track, forecast track, forecast points, the forecast cone, name, type, category, wind.
 * Where NHC covers the storm, the helper adds its best track (a fix every 6 hours with wind and type) and the
 * forecast intensity per point; elsewhere it adds the breadcrumbs it collected itself, so the track can be
 * drawn in intensity colours from where the storm was first fixed.
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
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property color ink: cfg ? cfg.StormColor : "#ff66cc"
    // Intensity colours, the scale used on storm-tracking sites: not tropical (disturbance, remnant low,
    // post-tropical) purple, depression blue, tropical storm green, then cat 1-5 yellow, orange, red, pink, magenta.
    readonly property bool intensityColors: cfg ? cfg.StormIntensityColors : true
    readonly property var intensityPalette: ["#a678ff", "#5ebaff", "#3ddc84", "#ffd23f", "#ff9f1c", "#ff3b30", "#ff4fa3", "#c71fbf"]
    // 0 not tropical, 1 depression, 2 tropical storm, 3..7 category 1..5 (Saffir-Simpson, km/h)
    function levelOfWind(kmh, tropical) {
        return tropical === 0 ? 0 : kmh < 63 ? 1 : kmh < 119 ? 2 : kmh < 154 ? 3 : kmh < 178 ? 4 : kmh < 209 ? 5 : kmh < 252 ? 6 : 7;
    }
    function levelOf(st) { return st.gone ? 0 : st.cat >= 1 ? 2 + Math.min(5, st.cat) : st.wind >= 63 ? 2 : 1 }
    // Symbol level for the drawn glyph: 0 depression, 1 tropical storm, 2 hurricane, 3 major
    function glyphLevel(st) { return st.cat >= 3 ? 3 : st.cat >= 1 ? 2 : st.wind >= 63 ? 1 : 0 }
    readonly property bool trackColors: cfg ? cfg.StormTrackColors : true
    readonly property bool originMark: cfg ? cfg.StormOriginMark : true
    function trackInk(w, tropical, tone) { return trackColors && intensityColors && w !== null && w !== undefined ? Qt.color(intensityPalette[levelOfWind(w, tropical)]) : tone }
    // Icon set: the supplied hurricane icons (images/storm), category number inside, halo for a dark or
    // light map, mirrored south of the equator. "post-tropical" (dashed) once the storm has left the feed.
    readonly property bool icons: cfg ? cfg.StormMarkerStyle === 1 : true
    readonly property string iconTheme: cfg && cfg.StormIconTheme === 1 ? "light" : "dark"
    readonly property real iconSize: (cfg ? cfg.StormIconSize : 22) * unit * markScale
    function iconOf(st) {
        var name = st.gone ? "post-tropical" : st.cat >= 1 ? "cat" + Math.min(5, st.cat) : st.kind === "Tropical depression" ? "td" : "ts";
        return Qt.resolvedUrl("../images/storm/" + iconTheme + "-" + (st.lat < 0 ? "south" : "north") + "-" + name + ".svg");
    }
    function inkOf(st) { return intensityColors ? Qt.color(intensityPalette[levelOf(st)]) : ink }
    function labelInkOf(st) { return cfg && !cfg.StormTextFollows ? cfg.StormTextColor : inkOf(st) }
    readonly property int labelMode: cfg ? cfg.StormLabels : 2          // 0 none, 1 name, 2 name, type and wind, 3 name and wind
    readonly property bool labelFacilities: cfg ? cfg.StormLabelFacilities : true
    readonly property bool labelTwoLines: cfg ? cfg.StormLabelTwoLines : true
    readonly property int units: cfg ? cfg.StormUnits : 0               // 0 km/h, 1 mph, 2 knots
    readonly property bool showCone: cfg ? cfg.ShowStormCone : true
    // what pulses: 0 nothing, 1 newly tracked (first seen here less than pulseNewHours ago), 2 significant (hurricane strength, cat 1+), 3 either
    readonly property int pulseMode: cfg ? cfg.StormPulseMode : 3
    readonly property bool pulse: pulseMode > 0
    function pulses(st) {
        var first = st.first_hours === undefined || st.first_hours === null ? -1 : st.first_hours;
        return !!(!st.gone && (((pulseMode & 1) && first >= 0 && first < pulseNewHours) || ((pulseMode & 2) && st.cat >= 1)));
    }
    readonly property real pulseNewHours: cfg ? cfg.PulseNewHours : 3
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    property int fps: 30
    property real clock: 0
    // the pulse clock is shared: main.qml advances one clock for every layer, so all pulses move in the same frame
    readonly property bool pulseWanted: pulse && storms.some(pulses)
    readonly property int labelPx: Math.round((cfg ? cfg.StormLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.StormLabelPlate : true
    readonly property bool ageFade: cfg ? cfg.AgeFade : true
    readonly property real ageStart: cfg ? cfg.AgeFadeStart : 12
    readonly property real ageEnd: cfg ? cfg.AgeFadeEnd : 48
    readonly property color agedColor: cfg ? cfg.AgedColor : "#8b97a8"
    function agedOf(st) { return ageFade ? Geo.ageMix(st.hours, ageStart, ageEnd) : 0 }
    readonly property color labelColor: cfg && !cfg.StormTextFollows ? cfg.StormTextColor : ink
    // What this layer wants labelled; main.qml's LabelPass draws these above everything.
    readonly property var labelSpecs: labelMode === 0 ? [] : storms.map(function (st) {
        // the label sits just off the marker: half the icon with the icon set, the category-sized ring otherwise
        return { x: px(st.lon), y: py(st.lat), gap: icons ? iconSize * 0.5 + 3 * unit : (5 + 2.2 * st.cat) * unit * markScale + 6 * unit, side: "right",
                 text: labelFor(st), px: labelPx, color: Geo.mix(labelInkOf(st), agedColor, agedOf(st)), plate: labelPlate, bold: false, alpha: 1 - 0.4 * agedOf(st) };   // the Storm label style's Bold decides
    }).concat(originMark ? storms.filter(function (st) {
        // a small note where the storm was first fixed, when that is far enough from the storm itself
        var tr = st.track || [];
        return tr.length >= 2 && st.since_hours > 0 && Math.hypot(px(tr[0][0]) - px(st.lon), py(tr[0][1]) - py(st.lat)) > 70 * unit;
    }).map(function (st) {
        return { x: px(st.track[0][0]), y: py(st.track[0][1]), gap: 5 * unit, side: "left", text: st.name + " \u00b7 first fix " + Geo.spanText(st.since_hours) + " ago",
                 px: Math.round(labelPx * 0.85), color: Geo.mix(labelInkOf(st), agedColor, 0.5), plate: labelPlate, bold: false, alpha: 0.75 };
    }) : [])
    property var storms: []
    property string note: ""
    readonly property string hint: note

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    function project(lines, w, h) {
        var out = [];
        for (var i = 0; i < lines.length; i++) {
            var flat = lines[i], pts = [];
            for (var j = 0; j + 1 < flat.length; j += 2) pts.push(Qt.point((flat[j] + 180) / 360 * w, (90 - flat[j + 1]) / 180 * h));
            out.push(pts);
        }
        return out;
    }
    function windText(kmh) {
        return units === 1 ? Math.round(kmh * 0.621) + " mph" : units === 2 ? Math.round(kmh * 0.54) + " kt" : kmh + " km/h";
    }
    function impactText(im) {
        if (!im) return "";
        var parts = [];
        if (im.platforms) parts.push(im.platforms + (im.platforms === 1 ? " platform" : " platforms"));
        if (im.refineries) parts.push(im.refineries + (im.refineries === 1 ? " refinery" : " refineries"));
        var ahead = parts.length ? parts.join(", ") + (im.how === "cone" ? " in the cone" : " near the track") : "";
        var crossed = im.crossed_n ? "crossed " + im.crossed_n + (im.crossed_n === 1 ? " facility" : " facilities") : "";
        return ahead && crossed ? ahead + " \u00b7 " + crossed : ahead || crossed;
    }
    function labelFor(st) {
        // GDACS only knows a storm's peak wind over its episode; NHC gives the wind now (Atlantic, east Pacific)
        var text = labelMode === 1 ? st.name : st.name + (labelMode === 2 ? " \u00b7 " + st.kind + (st.cat > 0 ? " cat " + st.cat : "") : "")
                 + " \u00b7 " + (st.wind_is_peak ? "peak " : "") + windText(st.wind);
        if (st.gone) return text + " \u00b7 no longer tracked";
        if (labelMode >= 2 && labelFacilities && st.impact) return text + (labelTwoLines ? "\n" : " \u00b7 ") + impactText(st.impact);
        return text;
    }
    // platforms and refineries inside a storm's cone or near its track: [lon, lat, kind, name, storm]; InfraLayer draws them
    property var impacted: []

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && !(r.storms && r.storms.length) && overlay.storms.length > 0) {   // nothing came: keep what we have
                    console.warn("livemap storms: keeping the previous data -", r.note);
                    overlay.note = r.note;
                    return;
                }
                overlay.impacted = r.impacted || []; overlay.storms = r.storms || [];
                overlay.note = r.note || "";
                console.warn("livemap storms:", overlay.storms.length, "active -", overlay.storms.map(function (s) { return s.name }).join(", "), overlay.note);
            } catch (e) { overlay.note = "Storms: the helper did not answer properly"; }
        }
    }
    Timer {                                       // forecasts are issued every 6 hours; every 30 minutes is plenty
        interval: (overlay.slow ? 120 : 30) * 60000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' storms --keep " + overlay.ageEnd + " --stale " + overlay.staleHours + " # " + Date.now())
    }

    Repeater {
        model: overlay.storms
        Item {
            id: storm
            required property var modelData
            anchors.fill: parent
            readonly property real size: (5 + 2.2 * modelData.cat) * overlay.unit * overlay.markScale
            readonly property real aged: overlay.agedOf(modelData)
            readonly property color tone: Geo.mix(overlay.inkOf(modelData), overlay.agedColor, aged)
            opacity: 1 - 0.4 * aged
            // The track as coloured pieces: every fix of the best track (or of this wallpaper's own breadcrumbs)
            // to the next, each in the colour of the intensity it reached; then the forecast points the same way.
            readonly property var nodes: (function () {
                var st = modelData, out = [], tr = st.track || [], i, prev = null, w = overlay.width, h = overlay.height;
                function add(lon, lat, wind, trop, kind) {
                    var n = { x: overlay.px(lon), y: overlay.py(lat), c: overlay.trackInk(wind, trop, storm.tone), kind: kind, len: 0, a: 0 };
                    if (prev && Math.abs(lon - prev.lon) < 180) {                 // no piece across the date line
                        n.len = Math.hypot(n.x - prev.x, n.y - prev.y);
                        n.a = Math.atan2(n.y - prev.y, n.x - prev.x) * 180 / Math.PI;
                        n.x0 = prev.x; n.y0 = prev.y;
                    }
                    prev = { lon: lon, x: n.x, y: n.y };
                    out.push(n);
                }
                for (i = 0; i < tr.length; i++) add(tr[i][0], tr[i][1], tr[i][2], tr[i][4], i === 0 ? "origin" : "fix");
                if (tr.length) add(st.lon, st.lat, st.gone ? null : st.wind, 1, "now");
                var dots = st.dots || [], winds = dots.length > 0 && dots.every(function (d) { return d.length > 2 && d[2] !== null; });
                if (winds) {
                    if (!tr.length) add(st.lon, st.lat, st.wind, 1, "now");
                    for (i = 0; i < dots.length; i++) add(dots[i][0], dots[i][1], dots[i][2], 1, "forecast");
                }
                return out;
            })()
            readonly property bool forecastColored: nodes.some(function (n) { return n.kind === "forecast" })

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {                               // cone of uncertainty (issued by the centre, or built from JTWC's mean errors: drawn the same)
                    strokeColor: Qt.rgba(storm.tone.r, storm.tone.g, storm.tone.b, overlay.showCone ? 0.45 : 0)
                    strokeWidth: overlay.unit
                    fillColor: Qt.rgba(storm.tone.r, storm.tone.g, storm.tone.b, overlay.showCone ? 0.10 : 0)
                    PathMultiline { paths: overlay.showCone ? overlay.project(storm.modelData.cone, overlay.width, overlay.height) : [] }
                }
                ShapePath {                               // where it has been
                    strokeColor: Qt.rgba(storm.tone.r, storm.tone.g, storm.tone.b, 0.45)
                    strokeWidth: 1.2 * overlay.unit
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    PathMultiline { paths: (storm.modelData.track || []).length ? [] : overlay.project(storm.modelData.past, overlay.width, overlay.height) }
                }
                ShapePath {                               // where it is forecast to go
                    strokeColor: Qt.rgba(storm.tone.r, storm.tone.g, storm.tone.b, 0.95)
                    strokeWidth: 1.6 * overlay.unit
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    PathMultiline { paths: storm.forecastColored ? [] : overlay.project(storm.modelData.forecast, overlay.width, overlay.height) }
                }
            }
            Repeater {                                    // track pieces, coloured by intensity
                model: storm.nodes
                Rectangle {
                    required property var modelData
                    visible: modelData.len > 0
                    x: modelData.x0 || 0; y: (modelData.y0 || 0) - height / 2
                    width: modelData.len; height: (modelData.kind === "forecast" ? 1.8 : 1.5) * overlay.unit
                    transformOrigin: Item.Left
                    rotation: modelData.a
                    antialiasing: true
                    color: modelData.c
                    opacity: modelData.kind === "forecast" ? 0.95 : 0.8
                }
            }
            Repeater {                                    // the fixes themselves; a ring where the storm was first fixed
                model: storm.nodes
                Rectangle {
                    required property var modelData
                    readonly property bool origin: modelData.kind === "origin" && overlay.originMark
                    visible: modelData.kind !== "now" && modelData.kind !== "forecast"
                    width: (origin ? 7 : 3) * overlay.unit; height: width; radius: width / 2
                    x: modelData.x - width / 2; y: modelData.y - height / 2
                    color: origin ? "transparent" : modelData.c
                    border.color: modelData.c; border.width: origin ? 1.5 * overlay.unit : 0
                    antialiasing: true
                }
            }
            Repeater {                                    // forecast positions (not the ones under the symbol itself)
                model: storm.modelData.dots
                Rectangle {
                    required property var modelData
                    width: 4 * overlay.unit; height: width; radius: width / 2
                    x: overlay.px(modelData[0]) - width / 2; y: overlay.py(modelData[1]) - height / 2
                    visible: Math.abs(x - (overlay.px(storm.modelData.lon) - width / 2)) > storm.size * 1.6 || Math.abs(y - (overlay.py(storm.modelData.lat) - height / 2)) > storm.size * 1.6
                    color: modelData.length > 2 ? overlay.trackInk(modelData[2], 1, storm.tone) : storm.tone
                }
            }
            Rectangle {                                   // ripple while the storm is newly reported (same ring as quakes)
                readonly property real s: Geo.pulse(overlay.clock, storm.modelData.id || 0, overlay.pulseMs, overlay.periodMs)
                visible: overlay.pulses(storm.modelData) && overlay.fps > 0 && s >= 0
                x: overlay.px(storm.modelData.lon) - width / 2; y: overlay.py(storm.modelData.lat) - height / 2
                width: storm.size * 2 * (1 + 1.6 * Math.max(0, s)); height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(storm.tone.r, storm.tone.g, storm.tone.b, (1 - Math.max(0, s)) * 0.8)
                border.width: 1.5 * overlay.unit
            }
            Image {                                       // now, as an icon from the set
                visible: overlay.icons
                z: 2
                source: overlay.icons ? overlay.iconOf(storm.modelData) : ""
                x: overlay.px(storm.modelData.lon) - width / 2; y: overlay.py(storm.modelData.lat) - height / 2
                width: overlay.iconSize; height: overlay.iconSize
                sourceSize.width: Math.ceil(overlay.iconSize); sourceSize.height: Math.ceil(overlay.iconSize)
                smooth: true
                opacity: 1 - 0.4 * storm.aged
            }
            StormGlyph {                                  // or the drawn cyclone symbol, sized and styled by intensity
                visible: !overlay.icons
                z: 2
                x: overlay.px(storm.modelData.lon) - width / 2; y: overlay.py(storm.modelData.lat) - height / 2
                r: storm.size * (overlay.glyphLevel(storm.modelData) === 0 ? 0.4 : 0.5)
                color: storm.tone
                level: overlay.glyphLevel(storm.modelData)
                south: storm.modelData.lat < 0
            }
        }
    }
}
