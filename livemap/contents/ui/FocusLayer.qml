/*
 * The event the companion widget is pointing at, ringed on the map.
 *
 * The widget and the wallpaper are separate scenes with no way to talk, so they share a file: while the widget's
 * popup is open and a row is hovered, the widget writes focus.json in the data folder (kind, lat, lon, title,
 * open, at); this layer reads it every 400 ms while the file says the popup is open, every two seconds otherwise. Nothing in the event layers is touched: this is
 * one ring, pulsing with the shared clock, drawn over everything. An event outside the view is pointed at from
 * the nearest edge with its name, since a wallpaper cannot pan.
 */
import QtQuick
import QtQuick.Shapes
import org.kde.plasma.plasma5support as P5Support

Item {
    id: layer
    property var cfg: null
    property real clock: 0
    property string dataDir: ""                   // the data folder, as a file:// URL or a path
    property real sx: 1
    property real sy: 1
    property rect screen: Qt.rect(0, 0, 0, 0)     // the screen in this item's coordinates (the map's)
    readonly property real unit: Math.max(1, Screen.width / 1920)

    property var target: ({})                     // the file's content (not "focus": that is Item's own, final)
    readonly property bool open: !!target.open && (Date.now() / 1000 - (target.at || 0)) < 120
    readonly property bool showing: open && target.lat !== undefined && target.lat !== null && target.lon !== undefined && target.lon !== null
    readonly property real px: (Number(target.lon) + 180) * sx
    readonly property real py: (90 - Number(target.lat)) * sy
    // inside the screen, or clamped to its edge with an arrow
    readonly property real margin: 22 * unit
    readonly property bool inside: showing && px >= screen.x && px <= screen.x + screen.width && py >= screen.y && py <= screen.y + screen.height
    readonly property real cx: Math.max(screen.x + margin, Math.min(screen.x + screen.width - margin, px))
    readonly property real cy: Math.max(screen.y + margin, Math.min(screen.y + screen.height - margin, py))
    readonly property real angle: Math.atan2(py - cy, px - cx)

    // Reading the file: an XMLHttpRequest on a file:// URL is refused by Qt 6 unless plasmashell is started with
    // QML_XHR_ALLOW_FILE_READ, so the file is read by a `cat` through the executable engine - a process, but a
    // two-millisecond one, every 400 ms while the popup is open and every two seconds otherwise.
    readonly property string path: String(dataDir).replace(/^file:\/\//, "") + "/focus.json"
    function read() {
        if (reader.connectedSources.length > 0) return;              // the last one has not come back yet
        reader.connectSource("cat '" + path.replace(/'/g, "") + "' 2>/dev/null # " + Date.now());
    }
    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source);
            try { layer.target = data.stdout ? JSON.parse(data.stdout) : ({}); } catch (e) { layer.target = ({}); }
        }
    }
    Timer { interval: layer.open ? 400 : 2000; running: layer.visible; repeat: true; triggeredOnStart: true; onTriggered: layer.read() }

    // the ring: a steady circle and a pulse running out from it, in the highlight colour over a dark halo
    Item {
        id: ring
        visible: layer.showing
        x: layer.cx; y: layer.cy
        readonly property real r: 14 * layer.unit
        // the pulse: a slow breath rather than a strobe - two and a half seconds, easing out, fading from half strength
        readonly property real phase: (layer.clock % 2.5) / 2.5
        readonly property real eased: 1 - (1 - phase) * (1 - phase)
        readonly property color tone: layer.cfg && layer.cfg.FocusColor ? layer.cfg.FocusColor : "#ffd23f"
        Rectangle { x: -parent.r - 3; y: -parent.r - 3; width: 2 * parent.r + 6; height: width; radius: width / 2; color: "transparent"; border.color: "#aa000000"; border.width: 4 * layer.unit }
        Rectangle { x: -parent.r; y: -parent.r; width: 2 * parent.r; height: width; radius: width / 2; color: "transparent"; border.color: parent.tone; border.width: 2 * layer.unit }
        Rectangle {
            readonly property real rr: parent.r * (1 + 1.2 * parent.eased)
            x: -rr; y: -rr; width: 2 * rr; height: width; radius: width / 2
            color: "transparent"; border.color: parent.tone; border.width: 1.5 * layer.unit
            opacity: 0.55 * (1 - parent.eased)
        }
        // outside the view: an arrow on the ring pointing the way, and the name
        Shape {
            visible: !layer.inside
            rotation: layer.angle * 180 / Math.PI
            ShapePath {
                strokeWidth: 0; fillColor: ring.tone
                startX: ring.r + 4; startY: -6 * layer.unit
                PathLine { x: ring.r + 4 + 12 * layer.unit; y: 0 }
                PathLine { x: ring.r + 4; y: 6 * layer.unit }
                PathLine { x: ring.r + 4; y: -6 * layer.unit }
            }
        }
        Text {
            visible: !layer.inside
            text: layer.target.title || ""
            color: "white"; font.pixelSize: Math.round(8 * layer.unit); font.bold: true
            style: Text.Outline; styleColor: "#cc000000"
            // on the side of the ring away from the edge, so it stays on screen
            x: layer.cx < layer.screen.x + layer.screen.width / 2 ? ring.r + 6 : -ring.r - 6 - width
            y: -height / 2
            width: Math.min(implicitWidth, 220 * layer.unit); elide: Text.ElideRight
        }
    }
}
