/*
 * The event the companion widget is pointing at, ringed on the map.
 *
 * The widget and the wallpaper are separate scenes with no way to talk, so they share a file: while the widget's
 * popup is open and a row is hovered, the widget writes focus.json in the data folder (kind, lat, lon, title,
 * open, at); this layer reads it with an XMLHttpRequest - no process, a few hundred bytes - every 300 ms while
 * the file says the popup is open, every two seconds otherwise. Nothing in the event layers is touched: this is
 * one ring, pulsing with the shared clock, drawn over everything. An event outside the view is pointed at from
 * the nearest edge with its name, since a wallpaper cannot pan.
 */
import QtQuick
import QtQuick.Shapes

Item {
    id: layer
    property var cfg: null
    property real clock: 0
    property string dataDir: ""                   // the data folder, as a file:// URL or a path
    property real sx: 1
    property real sy: 1
    property rect screen: Qt.rect(0, 0, 0, 0)     // the screen in this item's coordinates (the map's)
    readonly property real unit: Math.max(1, Screen.width / 1920)

    property var focus: ({})                      // the file's content
    readonly property bool open: !!focus.open && (Date.now() / 1000 - (focus.at || 0)) < 120
    readonly property bool showing: open && focus.lat !== undefined && focus.lat !== null && focus.lon !== undefined && focus.lon !== null
    readonly property real px: (Number(focus.lon) + 180) * sx
    readonly property real py: (90 - Number(focus.lat)) * sy
    // inside the screen, or clamped to its edge with an arrow
    readonly property real margin: 22 * unit
    readonly property bool inside: showing && px >= screen.x && px <= screen.x + screen.width && py >= screen.y && py <= screen.y + screen.height
    readonly property real cx: Math.max(screen.x + margin, Math.min(screen.x + screen.width - margin, px))
    readonly property real cy: Math.max(screen.y + margin, Math.min(screen.y + screen.height - margin, py))
    readonly property real angle: Math.atan2(py - cy, px - cx)

    function read() {
        var url = dataDir + "/focus.json";
        if (url.indexOf("file://") !== 0 && url.indexOf("/") === 0) url = "file://" + url;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try { layer.focus = xhr.responseText ? JSON.parse(xhr.responseText) : ({}); } catch (e) { layer.focus = ({}); }
        };
        xhr.open("GET", url); xhr.send();
    }
    Timer { interval: layer.open ? 300 : 2000; running: layer.visible; repeat: true; triggeredOnStart: true; onTriggered: layer.read() }

    // the ring: a steady circle and a pulse running out from it, in the highlight colour over a dark halo
    Item {
        visible: layer.showing
        x: layer.cx; y: layer.cy
        readonly property real r: 14 * layer.unit
        readonly property real phase: (layer.clock % 1.6) / 1.6
        readonly property color tone: layer.cfg && layer.cfg.FocusColor ? layer.cfg.FocusColor : "#ffd23f"
        Rectangle { x: -parent.r - 3; y: -parent.r - 3; width: 2 * parent.r + 6; height: width; radius: width / 2; color: "transparent"; border.color: "#aa000000"; border.width: 4 * layer.unit }
        Rectangle { x: -parent.r; y: -parent.r; width: 2 * parent.r; height: width; radius: width / 2; color: "transparent"; border.color: parent.tone; border.width: 2 * layer.unit }
        Rectangle {
            readonly property real rr: parent.r * (1 + 1.4 * parent.phase)
            x: -rr; y: -rr; width: 2 * rr; height: width; radius: width / 2
            color: "transparent"; border.color: parent.tone; border.width: 1.5 * layer.unit
            opacity: 1 - parent.phase
        }
        // outside the view: an arrow on the ring pointing the way, and the name
        Shape {
            visible: !layer.inside
            rotation: layer.angle * 180 / Math.PI
            ShapePath {
                strokeWidth: 0; fillColor: parent.parent.tone
                startX: parent.parent.r + 4; startY: -6 * layer.unit
                PathLine { x: parent.parent.r + 4 + 12 * layer.unit; y: 0 }
                PathLine { x: parent.parent.r + 4; y: 6 * layer.unit }
                PathLine { x: parent.parent.r + 4; y: -6 * layer.unit }
            }
        }
        Text {
            visible: !layer.inside
            text: layer.focus.title || ""
            color: "white"; font.pixelSize: Math.round(8 * layer.unit); font.bold: true
            style: Text.Outline; styleColor: "#cc000000"
            // on the side of the ring away from the edge, so it stays on screen
            x: layer.cx < layer.screen.x + layer.screen.width / 2 ? parent.r + 6 : -parent.r - 6 - width
            y: -height / 2
            width: Math.min(implicitWidth, 220 * layer.unit); elide: Text.ElideRight
        }
    }
}
