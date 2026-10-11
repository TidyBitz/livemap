/*
 * Ukraine's civil air-raid alerts, by oblast: the region fills in the alert colour while an alert is on (the whole
 * oblast), at a lower opacity when only part of it is (a raion, hromada or city), breathing slowly; every oblast
 * can be outlined faintly so the map says where the alerts live even when none is on. Labelled "Kharkiv · air raid
 * · 23 min". Source: alerts.in.ua with a personal token (minute by minute, alert types and partial alerts), or
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
    readonly property color ink: cfg ? cfg.AirAlertColor : "#ff3b3b"
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
    readonly property real mark: Math.round((cfg ? cfg.AirAlertLabelSize : 10) * unit)
    property var regions: []
    property string feedSource: ""
    property string note: ""
    readonly property string hint: note
    readonly property var active: regions.filter(function (r) { return r.status !== "N"; })
    property int fps: 30
    property real clock: 0
    Timer {                                       // a slow breath on the filled oblasts, four seconds a cycle
        interval: Math.round(1000 / Math.max(1, Math.min(overlay.fps, 15)))
        running: overlay.fps > 0 && overlay.pulse && overlay.active.length > 0
        repeat: true
        onTriggered: overlay.clock += interval
    }
    readonly property real breath: pulse ? 0.8 + 0.2 * Math.sin(clock / 4000 * 2 * Math.PI) : 1

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
    Timer { interval: 30000; running: overlay.active.length > 0; repeat: true; onTriggered: overlay.nowSec = Date.now() / 1000 }
    function describe(r) {
        // "Kharkiv · air raid · 23 min"; a partial alert names the places: "Kharkiv · part: Kupiansk · air raid · 12 min"
        var parts = [r.name];
        if (r.status === "P") parts.push("part" + (r.places && r.places.length ? ": " + r.places.join(", ") : ""));
        if (r.types && r.types.length) parts.push(r.types.join(", "));
        if (r.since) parts.push(Geo.spanText(Math.max(0, nowSec - r.since) / 3600));
        return parts.join(" · ");
    }
    readonly property var labelSpecs: labelMode === 0 ? [] : regions.filter(function (r) { return labelMode === 2 || r.status !== "N"; }).map(function (r) {
        return { x: px(r.lon), y: py(r.lat), gap: mark * 0.3, side: "below",
                 text: r.status === "N" ? r.name : describe(r), px: labelPx, color: r.status === "N" ? Qt.rgba(labelColor.r, labelColor.g, labelColor.b, 0.6) : labelColor,
                 plate: labelPlate && r.status !== "N", bold: r.status === "A", alpha: r.status === "N" ? 0.7 : 1 };
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
            visible: modelData.status !== "N" || overlay.outline
            readonly property real fill: modelData.status === "A" ? overlay.fillOpacity * overlay.breath : modelData.status === "P" ? overlay.partialOpacity * overlay.breath : 0
            ShapePath {
                fillColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, region.fill)
                strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, region.modelData.status !== "N" ? Math.min(1, overlay.fillOpacity * 2) : overlay.outlineOpacity)
                strokeWidth: Math.max(1, (region.modelData.status !== "N" ? 1.2 : 0.7) * overlay.unit)
                PathMultiline { paths: overlay.project(region.modelData.rings || [], overlay.width, overlay.height) }
            }
        }
    }
}
