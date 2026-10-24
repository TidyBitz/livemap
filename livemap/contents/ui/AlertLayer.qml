/*
 * Ukraine's civil air-raid alerts, by oblast. Two ways of drawing (AirAlertStyle): edge lights - the oblast's border
 * glows in the alert colour and the imagery inside stays as it is; a new alert breathes brightest, a settled one
 * holds a steady edge, part of an oblast is dashed, a long-running one a thin ochre edge, an ended one a dotted cool
 * edge fading out - or fills, the region shaded in the alert colour (lower opacity for part of it), breathing slowly.
 * Every oblast can be outlined faintly so the map says where the alerts live even when none is on. Labelled "Kharkiv
 * · air raid · 23 min". Source: alerts.in.ua with a personal token (minute by minute, alert types and partial alerts), or
 * without one a public mirror at oblast level, air raid only. The polygons ship with the package.
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
    readonly property color ink: cfg ? cfg.AirAlertColor : "#e03a3a"
    readonly property color newInk: cfg ? cfg.AirAlertNewColor : "#ff3b30"
    readonly property color longInk: cfg ? cfg.AirAlertLongColor : "#d68c28"
    readonly property bool edges: cfg ? cfg.AirAlertStyle === 0 : true
    readonly property real newMinutes: cfg ? cfg.AirAlertNewMinutes : 15
    readonly property color clearInk: cfg ? cfg.AirAlertClearColor : "#8fb6d6"
    readonly property bool showClear: cfg ? cfg.AirAlertShowClear : true
    readonly property real clearMinutes: 30
    // 0 established .. 1 brand new: known starts only (an alert already on at the first look is never "new")
    // "fresh" counts from the alert's start, or from its last renewal (a raion or city joining, a type added - the
    // API only): that is what brings a frontline oblast back to the front when something new happens in it
    function freshSince(r) { return Math.max(r.since || 0, r.renewed || 0) || null }
    function newness(r) { var t = freshSince(r); return r.status === "C" || !t || newMinutes <= 0 ? 0 : Math.max(0, 1 - (nowSec - t) / (newMinutes * 60)) }
    function clearFade(r) { return r.status !== "C" || !r.ended ? 0 : Math.max(0, 1 - (nowSec - r.ended) / (clearMinutes * 60)) }
    function toneOf(r) { return r.status === "C" ? clearInk : longRunning(r) && longStyle > 0 && !hideLong ? longInk : Geo.mix(ink, newInk, newness(r)) }
    readonly property real fillOpacity: (cfg ? cfg.AirAlertOpacity : 35) / 100
    readonly property real partialOpacity: (cfg ? cfg.AirAlertPartialOpacity : 18) / 100
    readonly property bool outline: cfg ? cfg.AirAlertOutline : true
    readonly property real outlineOpacity: (cfg ? cfg.AirAlertOutlineOpacity : 30) / 100
    readonly property string token: cfg ? cfg.AirAlertToken : ""
    readonly property int labelMode: cfg ? cfg.AirAlertLabels : 1              // 0 none, 1 under alert, 2 every oblast
    readonly property int labelPx: Math.round((cfg ? cfg.AirAlertLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.AirAlertLabelPlate : true
    readonly property color labelColor: cfg && !cfg.AirAlertTextFollows ? cfg.AirAlertTextColor : ink
    readonly property bool pulse: cfg ? cfg.AirAlertPulse : true
    // the frontline oblasts are under alert for months on end: past this many hours an alert is long-running and
    // drawn lighter (or as an outline), so a fresh alert elsewhere stands out. An alert whose start is unknown
    // (already on at the first look, from the mirror) counts from the first look.
    readonly property real longHours: cfg ? cfg.AirAlertLongHours : 6
    readonly property int longStyle: cfg ? cfg.AirAlertLongStyle : 1
    function longRunning(r) { return longHours > 0 && (r.status !== "N") && (nowSec - (freshSince(r) || r.first_seen || nowSec)) > longHours * 3600 }
    readonly property bool hideLong: longStyle === 3                         // long-running alerts not drawn at all (outline as any quiet oblast)
    readonly property real mark: Math.round((cfg ? cfg.AirAlertLabelSize : 10) * unit)
    property var regions: []
    property string feedSource: ""
    property string note: ""
    readonly property string hint: note
    readonly property var active: regions.filter(function (r) { return r.status === "A" || r.status === "P"; })
    property int fps: 30
    property real clock: 0
    // the pulse clock is shared: main.qml advances one clock for every layer, so all pulses move in the same frame
    readonly property bool pulseWanted: pulse && active.length > 0
    // the breath changes 27 Shape fills at once: ten steps a second is smooth enough for a four-second cycle
    readonly property real breath: pulse ? 0.8 + 0.2 * Math.sin(Math.floor(clock / 100) * 100 / 4000 * 2 * Math.PI) : 1

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    function project(rings, w, h) {
        var out = [];
        for (var i = 0; i < rings.length; i++) {
            var r = rings[i], o = [];
            for (var j = 0; j + 1 < r.length; j += 2) o.push(Qt.point((r[j] + 180) / 360 * w, (90 - r[j + 1]) / 180 * h));
            if (o.length >= 3) out.push(o);
        }
        return out;
    }
    property real nowSec: Date.now() / 1000
    Timer { interval: 30000; running: overlay.regions.some(function (r) { return r.status !== "N"; }); repeat: true; onTriggered: overlay.nowSec = Date.now() / 1000 }
    function describe(r) {
        // "Kharkiv · air raid · 23 min"; a partial alert names the places: "Kharkiv · part: Kupiansk · air raid · 12 min";
        // an ended one "Kyiv · all clear · 12 min"
        if (r.status === "C") return r.name + " · all clear" + (r.ended ? " · " + Geo.spanText(Math.max(0, nowSec - r.ended) / 3600) : "");
        var parts = [r.name];
        if (r.status === "P") parts.push("part" + (r.places && r.places.length ? ": " + r.places.join(", ") : ""));
        if (r.types && r.types.length) parts.push(r.types.join(", "));
        if (r.renewed && r.since && r.renewed > r.since + 60 && nowSec - r.renewed < 6 * 3600) parts.push("renewed " + Geo.spanText(Math.max(0, nowSec - r.renewed) / 3600));
        else if (r.since) parts.push(Geo.spanText(Math.max(0, nowSec - r.since) / 3600));
        else if (r.first_seen && nowSec - r.first_seen > longHours * 3600 && longHours > 0) parts.push("over " + Geo.spanText(nowSec - r.first_seen > 0 ? (nowSec - r.first_seen) / 3600 : 0));
        return parts.join(" · ");
    }
    readonly property var labelSpecs: labelMode === 0 ? [] : regions.filter(function (r) { return labelMode === 2 ? !(hideLong && longRunning(r)) : (r.status !== "N" && (r.status !== "C" || showClear) && !(hideLong && longRunning(r))); }).map(function (r) {
        var c = r.status === "N" ? Qt.rgba(labelColor.r, labelColor.g, labelColor.b, 0.6) : r.status === "C" ? clearInk : cfg && !cfg.AirAlertTextFollows ? labelColor : toneOf(r);
        // the gap must clear the label pass's padding (2 units), or every side fails its "not over the mark" test and
        // the label vanishes - which is what happened at 6 px and below
        return { x: px(r.lon), y: py(r.lat), gap: Math.max(mark * 0.3, 2.5 * unit), side: "below",
                 text: r.status === "N" ? r.name : describe(r), px: labelPx, color: c,
                 plate: labelPlate && r.status !== "N", bold: r.status === "A" && !longRunning(r), alpha: r.status === "N" ? 0.7 : r.status === "C" ? 0.5 + 0.5 * clearFade(r) : longRunning(r) ? 0.75 : 1 };
    })

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                overlay.regions = r.regions || [];
                overlay.feedSource = r.source || "";
                overlay.note = r.note || "";
                console.warn("livemap air alerts:", overlay.active.length, "oblasts under alert", r.source || "", r.note || "");
            } catch (e) { overlay.note = "Air raid alerts: the helper did not answer properly"; }
        }
    }
    function ask() { exec.connectSource("python3 '" + helper + "' air-alerts --regions --stale " + staleHours + (token !== "" ? " --token '" + token.replace(/'/g, "") + "'" : "") + " # " + Date.now()) }
    Timer {                                       // once a minute (the API allows 8-10; the mirror caches anyway), every three when saving
        interval: (overlay.slow ? 180 : 60) * 1000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: overlay.ask()
    }
    onTokenChanged: if (helper !== "") ask()

    Repeater {
        model: overlay.regions
        Shape {
            id: region
            required property var modelData
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: (modelData.status !== "N" && (modelData.status !== "C" || overlay.showClear)) || overlay.outline
            readonly property bool long: overlay.longRunning(modelData)
            readonly property bool hiddenLong: long && overlay.hideLong
            readonly property bool cleared: modelData.status === "C"
            readonly property bool quiet: modelData.status === "N" || hiddenLong        // drawn as any oblast without an alert
            readonly property bool partial: modelData.status === "P"
            readonly property real fresh: overlay.newness(modelData)
            readonly property color tone: overlay.toneOf(modelData)
            readonly property real base: modelData.status === "A" ? overlay.fillOpacity : partial ? overlay.partialOpacity : 0
            // fills: new, a stronger breath (the breath swings twice as far); long-running, lighter or none; cleared, a faint fill that fades
            readonly property real fill: !overlay.edges ? (cleared ? overlay.fillOpacity * 0.25 * overlay.clearFade(modelData)
                                                          : long ? (overlay.longStyle >= 2 ? 0 : overlay.longStyle === 1 ? base * 0.4 : base * overlay.breath)
                                                          : base * (overlay.breath + fresh * (overlay.breath - 1)))
                                       // edges: no fill, except a hint of the long-running colour so the frontline still reads as an area
                                       : (long && !hiddenLong && overlay.longStyle === 1 ? 0.06 : 0)
            // edges: the glow is a wide, faint stroke under a crisp one; a new alert's glow breathes
            readonly property real glowAlpha: cleared ? 0.25 * overlay.clearFade(modelData)
                                            : long ? 0.12
                                            : (partial ? 0.28 : 0.4) * (overlay.breath + fresh * (overlay.breath - 1) * 1.5)
            readonly property real glowWidth: (cleared ? 4 : long ? 2.5 : partial ? 5 : 6 + 5 * fresh) * overlay.unit
            readonly property real edgeAlpha: cleared ? 0.35 + 0.55 * overlay.clearFade(modelData) : long ? 0.8 : 0.95
            readonly property real edgeWidth: (cleared ? 1.3 : long ? 1.2 : partial ? 1.8 : 2.2) * overlay.unit
            readonly property var paths: overlay.project(modelData.rings || [], overlay.width, overlay.height)
            ShapePath {                                                            // the glow (edges only, not for a quiet oblast)
                strokeColor: overlay.edges && !region.quiet ? Qt.rgba(region.tone.r, region.tone.g, region.tone.b, region.glowAlpha) : "transparent"
                strokeWidth: region.glowWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathMultiline { paths: region.paths }
            }
            ShapePath {                                                            // the fill (fills style) and the crisp edge
                fillColor: Qt.rgba(region.tone.r, region.tone.g, region.tone.b, region.fill)
                strokeColor: Qt.rgba(region.tone.r, region.tone.g, region.tone.b,
                                     region.quiet ? overlay.outlineOpacity
                                   : overlay.edges ? region.edgeAlpha
                                   : region.cleared ? 0.3 + 0.6 * overlay.clearFade(region.modelData) : Math.min(1, overlay.fillOpacity * 2))
                strokeWidth: Math.max(1, region.quiet ? 0.7 * overlay.unit : overlay.edges ? region.edgeWidth : (region.cleared ? 1.4 : 1.2) * overlay.unit)
                strokeStyle: overlay.edges && !region.quiet && (region.cleared || region.partial || region.long) ? ShapePath.DashLine : ShapePath.SolidLine
                dashPattern: region.cleared ? [1, 3] : region.long ? [4, 3] : [6, 3]
                capStyle: region.cleared ? ShapePath.RoundCap : ShapePath.FlatCap
                joinStyle: ShapePath.RoundJoin
                PathMultiline { paths: region.paths }
            }
        }
    }
}
