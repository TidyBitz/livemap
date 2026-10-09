/*
 * Oil and gas infrastructure: fixed offshore platforms (BSEE for the US Gulf of Mexico, OpenStreetMap
 * elsewhere) and refineries (OpenStreetMap), as still marks in the cached part of the map - a square for
 * a platform, a triangle on a base for a refinery - with names through the label pass. Downloaded on
 * demand by the helper (`fetch-infrastructure`); this file only draws what `infrastructure` hands over.
 */
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
    readonly property color ink: cfg ? cfg.InfraColor : "#c9b3ff"
    readonly property real mark: Math.max(2, (cfg ? cfg.InfraSize : 7) * unit)
    readonly property bool showPlatforms: cfg ? cfg.InfraPlatforms : true
    readonly property bool showRefineries: cfg ? cfg.InfraRefineries : true
    readonly property int labelMode: cfg ? cfg.InfraLabels : 1
    readonly property bool nameThreatened: cfg ? cfg.InfraNameThreatened : false   // "Name · Storm" on what a storm threatens
    readonly property int labelPx: Math.round((cfg ? cfg.InfraLabelSize : 8) * unit)
    readonly property int mode: cfg ? cfg.InfraMode : 0           // 0 only what a storm threatens, 1 everything
    property var impacted: []                                     // [lon, lat, kind, name, storm, crossed] from StormLayer
    property var platforms: []
    property var refineries: []
    property string note: ""
    readonly property string hint: note !== "" ? note : ""

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }

    readonly property string request: helper === "" ? "" : "python3 '" + helper + "' infrastructure"
    onRequestChanged: if (request !== "") exec.connectSource(request + " # " + Date.now())
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.at && r.at === overlay.fileAt) return;             // the same file as last time: nothing to redraw
                overlay.fileAt = r.at || 0;
                overlay.platforms = r.platforms || []; overlay.refineries = r.refineries || []; overlay.note = r.note || "";
                console.warn("livemap infrastructure:", overlay.platforms.length, "platforms,", overlay.refineries.length, "refineries", overlay.note);
            } catch (e) { overlay.note = "Oil and gas infrastructure: the helper did not answer properly"; }
        }
    }
    property real fileAt: 0                                       // the download's own timestamp, to notice a new file
    // Re-read now and then: the settings' Download (or refresh) button runs the helper and replaces the file, and
    // the map must pick the new one up - quickly while there is nothing yet, every few minutes otherwise.
    Timer { interval: overlay.platforms.length === 0 && overlay.refineries.length === 0 ? 60000 : 300000; running: overlay.helper !== ""; repeat: true
            onTriggered: exec.connectSource(overlay.request + " # " + Date.now()) }

    readonly property var shownPlatforms: !showPlatforms ? [] : mode === 1 ? platforms : impacted.filter(function (f) { return f[2] === 0; })
    readonly property var shownRefineries: !showRefineries ? [] : mode === 1 ? refineries : impacted.filter(function (f) { return f[2] === 1; })
    readonly property var hitKeys: (function () { var o = {}; for (var i = 0; i < impacted.length; i++) o[impacted[i][0] + "," + impacted[i][1]] = impacted[i][4]; return o; })()
    readonly property var crossedKeys: (function () { var o = {}; for (var i = 0; i < impacted.length; i++) if (impacted[i][5]) o[impacted[i][0] + "," + impacted[i][1]] = true; return o; })()
    function threatenedBy(f) { return hitKeys[f[0] + "," + f[1]] || "" }
    function crossed(f) { return !!crossedKeys[f[0] + "," + f[1]] }       // already behind the storm: ringed faintly
    // what this layer wants labelled; main.qml's LabelPass places these with the other layers' labels.
    // The Infrastructure labels setting decides; "Name threatened facilities" adds "Name · Storm" on what a storm
    // threatens whatever that setting says (the widget lists them under the storm either way).
    readonly property var labelSpecs: shownRefineries.filter(function (r) { return r[2] !== "" && (labelMode >= 1 || (nameThreatened && threatenedBy(r) !== "")); }).map(function (r) {
        var st = nameThreatened ? threatenedBy(r) : "";
        return { x: px(r[0]), y: py(r[1]), gap: mark * (st ? 1.3 : 0.8), side: "right", text: st ? r[2] + " \u00b7 " + st : r[2], px: labelPx, color: ink, plate: false, alpha: 1, bold: st !== "" };
    }).concat(shownPlatforms.filter(function (p) { return p[2] !== "" && (labelMode === 2 || (nameThreatened && threatenedBy(p) !== "" && impacted.filter(function (f) { return f[2] === 0 && f[4] === threatenedBy(p); }).length <= 12)); }).map(function (p) {
        var st = nameThreatened ? threatenedBy(p) : "";             // a dozen platforms in a cone get names; the Gulf's hundreds do not
        return { x: px(p[0]), y: py(p[1]), gap: mark * (st ? 1.1 : 0.6), side: "right", text: p[2], px: labelPx, color: ink, plate: false, alpha: 0.85 };
    }))

    Repeater {                                    // platforms: a small square
        model: overlay.shownPlatforms
        Item {
            required property var modelData
            readonly property bool hit: overlay.threatenedBy(modelData) !== ""
            readonly property bool behind: hit && overlay.crossed(modelData)
            x: overlay.px(modelData[0]); y: overlay.py(modelData[1])
            Rectangle {                                       // a threatened structure: a ring around it (faint once crossed)
                visible: hit
                anchors.centerIn: parent
                width: overlay.mark * 2.6; height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, behind ? 0.35 : 0.7); border.width: Math.max(1, 1.2 * overlay.unit)
            }
            Rectangle {
                anchors.centerIn: parent
                width: overlay.mark * (hit && !behind ? 1.1 : 0.7); height: width
                color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.9)
                border.color: Qt.rgba(0, 0, 0, 0.6); border.width: Math.max(1, 0.5 * overlay.unit)
            }
        }
    }
    Repeater {                                    // refineries: a triangle on a base
        model: overlay.shownRefineries
        Canvas {
            required property var modelData
            readonly property bool hit: overlay.threatenedBy(modelData) !== ""
            readonly property bool behind: hit && overlay.crossed(modelData)
            x: overlay.px(modelData[0]) - width / 2; y: overlay.py(modelData[1]) - height * 0.7
            width: overlay.mark * (hit && !behind ? 2.0 : 1.3); height: width
            Rectangle {                                       // a threatened refinery: a ring around it (faint once crossed)
                visible: hit
                anchors.centerIn: parent
                width: overlay.mark * 3.2; height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, behind ? 0.35 : 0.7); border.width: Math.max(1, 1.2 * overlay.unit)
            }
            onPaint: {
                var c = getContext("2d"), w = width, h = height;
                c.clearRect(0, 0, w, h);
                c.fillStyle = Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.95);
                c.strokeStyle = Qt.rgba(0, 0, 0, 0.6); c.lineWidth = Math.max(1, 0.5 * overlay.unit);
                c.beginPath(); c.moveTo(w * 0.5, 0); c.lineTo(w, h * 0.7); c.lineTo(0, h * 0.7); c.closePath(); c.fill(); c.stroke();
                c.fillRect(w * 0.2, h * 0.7, w * 0.6, h * 0.3);
            }
            onWidthChanged: requestPaint()
            Connections { target: overlay; function onInkChanged() { requestPaint() } }
        }
    }
}
