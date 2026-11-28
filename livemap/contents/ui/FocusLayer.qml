/*
 * The event the companion widget is pointing at, marked on the map.
 *
 * The widget and the wallpaper are separate scenes with no way to talk, so they share a file: while the widget's
 * popup is open and a row is hovered, the widget writes focus.ini in the data folder (kind, lat, lon, title,
 * open, at); this layer reads it every 400 ms while the file says the popup is open, every two seconds otherwise.
 * Nothing in the event layers is touched: this is one mark drawn over everything, in the style chosen on
 * Essentials > Events widget (FocusStyle): a steady ring, the ring with a slow pulse, a breathing glow, a
 * spotlight that dims the rest of the screen, a reticle that locks on, or a radar beacon. An event
 * outside the view is pointed at from the nearest edge with its name, since a wallpaper cannot pan.
 */
import QtQuick
import QtQuick.Shapes

Item {
    id: layer
    property var cfg: null
    property real clock: 0                        // the shared pulse clock (ms); advances only while some layer pulses
    property int fps: 30
    property string dataDir: ""                   // the data folder, as a file:// URL or a path
    property real sx: 1
    property real sy: 1
    property rect screen: Qt.rect(0, 0, 0, 0)     // the screen in this item's coordinates (the map's)
    readonly property real unit: Math.max(1, Screen.width / 1920)

    // 0 ring, 1 ring and pulse, 2 glow, 3 spotlight, 4 reticle, 5 beacon
    readonly property int style: cfg && cfg.FocusStyle !== undefined ? cfg.FocusStyle : 1
    readonly property real strength: (cfg && cfg.FocusStrength !== undefined ? cfg.FocusStrength : 100) / 100
    readonly property real dim: (cfg && cfg.FocusDim !== undefined ? cfg.FocusDim : 30) / 100
    readonly property color tone: cfg && cfg.FocusColor ? cfg.FocusColor : "#ffd23f"
    readonly property bool animated: style === 1 || style === 2 || style === 5

    property var target: ({})                     // the file's content (not "focus": that is Item's own, final)
    readonly property bool open: !!target.open && (Date.now() / 1000 - (target.at || 0)) < 120
    readonly property bool showing: open && target.lat !== undefined && target.lat !== null && target.lon !== undefined && target.lon !== null
    readonly property string key: showing ? String(target.key || "") + ":" + target.lat + "," + target.lon : ""
    readonly property real px: (Number(target.lon) + 180) * sx
    readonly property real py: (90 - Number(target.lat)) * sy
    // inside the screen, or clamped to its edge with an arrow
    readonly property real margin: 22 * unit
    readonly property bool inside: showing && px >= screen.x && px <= screen.x + screen.width && py >= screen.y && py <= screen.y + screen.height
    readonly property real cx: Math.max(screen.x + margin, Math.min(screen.x + screen.width - margin, px))
    readonly property real cy: Math.max(screen.y + margin, Math.min(screen.y + screen.height - margin, py))
    readonly property real angle: Math.atan2(py - cy, px - cx)

    // Reading the file: through Qt's Settings, no process - a fresh object per read, since QSettings re-reads a
    // file whose timestamp changed when a new object opens it. The `cat` that did this before was a fork of
    // plasmashell for every change - the jitter over the Events list.
    readonly property string path: String(dataDir).replace(/^file:\/\//, "") + "/focus.ini"
    function read() {
        if (readComp.status === Component.Ready) {
            var s = readComp.createObject(layer, { location: "file://" + path });
            if (s) {
                var raw = s.hover; s.destroy();
                try { layer.target = raw ? JSON.parse(raw) : ({}); } catch (e) { layer.target = ({}); }
                return;
            }
        }
        console.warn("livemap focus: QtCore.Settings not available, the widget's hover cannot reach the map");
    }
    Component { id: readComp; FocusRead {} }
    // The file is normally read only when it changes: FocusWatch keeps a file-system watcher on the folder (no
    // process at all while nothing happens). The poll stays as the fallback - every 400 ms / 2 s without the
    // watcher, a slow safety read with it - every second while open, every 10 s otherwise (a change the watcher missed, a stale "open" to let expire).
    Loader {
        id: watcher
        source: "FocusWatch.qml"
        onLoaded: { item.folder = Qt.binding(function () { return String(layer.dataDir).replace(/^file:\/\//, "") ? "file://" + String(layer.dataDir).replace(/^file:\/\//, "") : "" }); item.changed.connect(layer.read); }
        onStatusChanged: if (status === Loader.Error) console.warn("livemap focus: Qt.labs.folderlistmodel not available, polling focus.json instead")
    }
    readonly property bool watching: watcher.status === Loader.Ready
    Timer { interval: layer.watching ? (layer.open ? 1000 : 10000) : (layer.open ? 400 : 2000); running: layer.visible; repeat: true; triggeredOnStart: true; onTriggered: layer.read() }

    // The animated styles keep their own clock: the shared one only runs while some event layer pulses, and the
    // highlight must breathe on a quiet map too. Stopped the moment nothing is shown, so an idle desktop costs nothing.
    property real t: 0
    Timer { interval: Math.round(1000 / Math.max(1, layer.fps)); running: layer.showing && layer.animated && layer.fps > 0; repeat: true; onTriggered: layer.t += interval }

    // ---- spotlight: the screen dimmed, a clear soft-edged disc around the event -------------------------------
    // The canvas is the whole screen (11 million pixels on a 5K monitor), so it exists only while the spotlight is
    // actually showing: as a permanent item it kept its full-screen buffer around and - with no target, when its
    // centre was not a number - repainted on every read of the focus file, each paint a hundred milliseconds of the
    // GUI thread and an error line in the journal.
    Loader {
        active: layer.style === 3 && layer.showing && layer.screen.width > 0 && isFinite(layer.cx) && isFinite(layer.cy)
        sourceComponent: Canvas {
            id: spot
            x: layer.screen.x; y: layer.screen.y; width: layer.screen.width; height: layer.screen.height
            renderStrategy: Canvas.Threaded          // painted off the GUI thread
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 250 } }
            readonly property real hole: 70 * layer.unit * layer.strength
            readonly property real hx: layer.cx - x
            readonly property real hy: layer.cy - y
            onHxChanged: requestPaint()
            onHyChanged: requestPaint()
            onHoleChanged: requestPaint()
            onPaint: {
                if (!isFinite(hx) || !isFinite(hy) || !(hole > 0)) return;
                var c = getContext("2d");
                c.reset();
                c.globalCompositeOperation = "source-over";
                c.fillStyle = Qt.rgba(0, 0, 0, layer.dim);
                c.fillRect(0, 0, width, height);
                c.globalCompositeOperation = "destination-out";
                var g = c.createRadialGradient(hx, hy, hole * 0.55, hx, hy, hole);
                g.addColorStop(0, "rgba(0,0,0,1)"); g.addColorStop(1, "rgba(0,0,0,0)");
                c.fillStyle = g;
                c.beginPath(); c.arc(hx, hy, hole, 0, 2 * Math.PI); c.fill();
            }
        }
    }

    Item {
        id: ring
        visible: layer.showing
        x: layer.cx; y: layer.cy
        readonly property real r: 14 * layer.unit * layer.strength
        readonly property real line: 2 * layer.unit * Math.min(1.5, Math.max(0.6, layer.strength))
        readonly property color tone: layer.tone
        // a slow breath for the pulse and the glow: two and a half seconds, easing out
        readonly property real phase: (layer.t % 2500) / 2500
        readonly property real eased: 1 - (1 - phase) * (1 - phase)

        // ---- ring (styles 0, 1, 5): a steady circle in the colour over a dark halo; the spotlight gets a thin one too
        Rectangle { visible: layer.style <= 1 || layer.style === 5 || layer.style === 3; x: -parent.r - 3; y: -parent.r - 3; width: 2 * parent.r + 6; height: width; radius: width / 2; color: "transparent"; border.color: "#aa000000"; border.width: parent.line + 2 * layer.unit; opacity: layer.style === 3 ? 0.5 : 1 }
        Rectangle { visible: layer.style <= 1 || layer.style === 5 || layer.style === 3; x: -parent.r; y: -parent.r; width: 2 * parent.r; height: width; radius: width / 2; color: "transparent"; border.color: parent.tone; border.width: parent.line; opacity: layer.style === 3 ? 0.7 : 1 }
        // ---- pulse (style 1): one ring running out of the steady one, fading
        Rectangle {
            visible: layer.style === 1
            readonly property real rr: parent.r * (1 + 1.2 * parent.eased)
            x: -rr; y: -rr; width: 2 * rr; height: width; radius: width / 2
            color: "transparent"; border.color: parent.tone; border.width: 1.5 * layer.unit
            opacity: 0.55 * (1 - parent.eased)
        }
        // ---- glow (style 2): a soft halo breathing between 40 and 75 %
        Shape {
            visible: layer.style === 2
            readonly property real g: ring.r * 3.2
            opacity: 0.4 + 0.35 * (0.5 - 0.5 * Math.cos(2 * Math.PI * ring.phase))
            ShapePath {
                strokeWidth: 0
                fillGradient: RadialGradient {
                    centerX: 0; centerY: 0; focalX: 0; focalY: 0; centerRadius: ring.r * 3.2
                    GradientStop { position: 0; color: Qt.rgba(ring.tone.r, ring.tone.g, ring.tone.b, 0.95) }
                    GradientStop { position: 0.35; color: Qt.rgba(ring.tone.r, ring.tone.g, ring.tone.b, 0.5) }
                    GradientStop { position: 1; color: Qt.rgba(ring.tone.r, ring.tone.g, ring.tone.b, 0) }
                }
                startX: -ring.r * 3.2; startY: 0
                PathArc { x: ring.r * 3.2; y: 0; radiusX: ring.r * 3.2; radiusY: ring.r * 3.2 }
                PathArc { x: -ring.r * 3.2; y: 0; radiusX: ring.r * 3.2; radiusY: ring.r * 3.2 }
            }
        }
        Rectangle { visible: layer.style === 2; anchors.centerIn: parent; width: 5 * layer.unit * layer.strength; height: width; radius: width / 2; color: parent.tone }
        // ---- reticle (style 4): four ticks slide in from three radii out and lock on
        property real lock: 1
        NumberAnimation { id: lockAnim; target: ring; property: "lock"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
        Repeater {
            model: layer.style === 4 ? 4 : 0
            Item {
                required property int index
                rotation: index * 90
                readonly property real d: ring.r * (1.1 + 2.2 * (1 - ring.lock))     // where the tick's inner end sits
                Rectangle { x: parent.d; y: -ring.line / 2 - layer.unit; width: ring.r * 0.9; height: ring.line + 2 * layer.unit; color: "#aa000000" }
                Rectangle { x: parent.d; y: -ring.line / 2; width: ring.r * 0.9; height: ring.line; color: ring.tone }
            }
        }
        Rectangle { visible: layer.style === 4; anchors.centerIn: parent; width: 3 * layer.unit; height: width; radius: width / 2; color: parent.tone; opacity: parent.lock }
        // ---- beacon (style 5): a radar sweep inside the ring - a sharp leading line with a trail fading behind it,
        // one turn every two seconds. Built from plain wedges rather than a conical gradient, which the Shape
        // renderers do not all draw the same way.
        Item {
            id: beacon
            visible: layer.style === 5
            rotation: (layer.t / 2000 * 360) % 360
            readonly property real rr: ring.r - ring.line
            Repeater {
                model: 5                            // five 14-degree wedges trailing the line, each fainter
                Shape {
                    required property int index
                    rotation: -(index + 1) * 14
                    opacity: 0.45 * (1 - index / 5)
                    ShapePath {
                        strokeWidth: 0; fillColor: ring.tone
                        startX: 0; startY: 0
                        PathLine { x: beacon.rr; y: 0 }
                        PathArc { x: beacon.rr * Math.cos(14 * Math.PI / 180); y: beacon.rr * Math.sin(14 * Math.PI / 180); radiusX: beacon.rr; radiusY: beacon.rr }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
            Rectangle { x: 0; y: -layer.unit * 0.75; width: parent.rr; height: Math.max(1, 1.5 * layer.unit); color: ring.tone }   // the leading line
            Rectangle { anchors.centerIn: parent; width: 3 * layer.unit; height: width; radius: width / 2; color: ring.tone }
        }
        // ---- outside the view: an arrow on the ring pointing the way, and the name ------------------------------
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
    onKeyChanged: if (showing && style === 4) lockAnim.restart()
}
