/*
 * The frame picker on the Essentials page: the world (the Classic picture from the package, equirectangular, so a
 * box on it is exactly the N/S/W/E frame) with the frame drawn on it. Drag inside the box to move it, its edges and
 * corners to resize, the wheel to zoom about the pointer, drag outside to draw a fresh box. Everything outside the
 * box dims. Dashed ghosts show what each screen actually displays once Fit to screen has had its say - the same sums
 * as main.qml - so a laptop panel's trimming is visible here instead of on the desktop. The four degree values
 * stay the truth: the picker reads them and asks to change them (changed), nothing is stored twice.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.kirigami as Kirigami

Item {
    id: picker
    property int north: 72
    property int south: -56
    property int west: -180
    property int east: 180
    property int fitMode: 4                        // 0 stretch, 1 fit, 2 crop, 3 fill, 4 auto - what the ghosts assume
    property bool lockToScreen: false              // the box keeps this screen's shape: resizing only zooms
    signal changed(int n, int s, int w, int e)

    readonly property real unit: Kirigami.Units.gridUnit
    implicitWidth: Math.round(unit * 36)
    implicitHeight: Math.round(implicitWidth / 2)
    readonly property real pxPerDeg: width / 360

    function xOf(lon) { return (lon + 180) * pxPerDeg }
    function yOf(lat) { return (90 - lat) * pxPerDeg }
    function lonAt(x) { return x / pxPerDeg - 180 }
    function latAt(y) { return 90 - y / pxPerDeg }

    // this screen's shape, for the lock and the ghost; every screen for the ghosts
    readonly property real screenAspect: Screen.width > 0 && Screen.height > 0 ? Screen.width / Screen.height : 16 / 9
    readonly property var screens: Qt.application.screens

    // the view a screen gets for a frame and a fit mode: [n, s, w, e] in degrees - the sums of main.qml
    function viewFor(W, H, n, s, w, e, mode) {
        var sxF = W / (e - w), syF = H / (n - s), sx, sy;
        if (mode === 0) { sx = sxF; sy = syF; }
        else if (mode === 1) { sx = sy = Math.min(sxF, syF); }
        else if (mode === 2) { sx = sy = Math.max(sxF, syF); }
        else if (mode === 4) { var t = Math.max(1 / 1.12, Math.min(1.12, syF / sxF)); if (syF >= sxF) { sy = syF; sx = syF / t; } else { sx = sxF; sy = sxF * t; } }
        else { sx = sy = Math.max(Math.min(sxF, syF), W / 360, H / 180); }
        var cl = (w + e) / 2, ct = (n + s) / 2;
        if (mode === 3) { cl = Math.max(-180 + W / (2 * sx), Math.min(180 - W / (2 * sx), cl)); ct = Math.max(-90 + H / (2 * sy), Math.min(90 - H / (2 * sy), ct)); }
        return [ct + H / (2 * sy), ct - H / (2 * sy), cl - W / (2 * sx), cl + W / (2 * sx)];
    }

    // the box while being dragged (null when idle): the pointer moves these, the release sends them
    property var drag: null
    readonly property int bn: drag ? drag.n : north
    readonly property int bs: drag ? drag.s : south
    readonly property int bw: drag ? drag.w : west
    readonly property int be: drag ? drag.e : east

    function clampBox(n, s, w, e) {
        n = Math.max(-80, Math.min(90, n)); s = Math.max(-90, Math.min(80, s));
        w = Math.max(-180, Math.min(170, w)); e = Math.max(-170, Math.min(180, e));
        if (n - s < 5) { if (n >= 85) s = n - 5; else n = s + 5; }
        if (e - w < 10) { if (e >= 170) w = e - 10; else e = w + 10; }
        return { n: Math.round(n), s: Math.round(s), w: Math.round(w), e: Math.round(e) };
    }
    // the box in this screen's shape, kept inside the world, around a centre
    function shaped(cx, cy, wDeg) {
        var hDeg = wDeg / screenAspect;
        if (hDeg > 180) { hDeg = 180; wDeg = hDeg * screenAspect; }
        if (wDeg > 360) { wDeg = 360; hDeg = wDeg / screenAspect; }
        cx = Math.max(-180 + wDeg / 2, Math.min(180 - wDeg / 2, cx));
        cy = Math.max(-90 + hDeg / 2, Math.min(90 - hDeg / 2, cy));
        return clampBox(cy + hDeg / 2, cy - hDeg / 2, cx - wDeg / 2, cx + wDeg / 2);
    }
    function commit(b) {
        b = clampBox(b.n, b.s, b.w, b.e);
        drag = null;
        if (b.n !== north || b.s !== south || b.w !== west || b.e !== east) changed(b.n, b.s, b.w, b.e);
    }

    Image {
        id: world
        anchors.fill: parent
        source: Qt.resolvedUrl("../images/classic.jpg")
        sourceSize: Qt.size(1440, 720)
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.9
    }
    // outside the box: dimmed
    Rectangle { x: 0; y: 0; width: parent.width; height: picker.yOf(picker.bn); color: "#99000000" }
    Rectangle { x: 0; y: picker.yOf(picker.bs); width: parent.width; height: parent.height - y; color: "#99000000" }
    Rectangle { x: 0; y: picker.yOf(picker.bn); width: picker.xOf(picker.bw); height: picker.yOf(picker.bs) - y; color: "#99000000" }
    Rectangle { x: picker.xOf(picker.be); y: picker.yOf(picker.bn); width: parent.width - x; height: picker.yOf(picker.bs) - y; color: "#99000000" }
    // what each screen shows of it: dashed, this screen in the highlight colour, the others in the neutral one
    Canvas {
        id: ghosts
        anchors.fill: parent
        readonly property string key: [picker.bn, picker.bs, picker.bw, picker.be, picker.fitMode, width, picker.screens.length].join("/")
        onKeyChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.lineWidth = 1.5;
            ctx.setLineDash([5, 4]);
            var sc = picker.screens, thisW = Screen.width, thisH = Screen.height, drawn = {};
            for (var i = 0; i < sc.length; i++) {
                var W = sc[i].width, H = sc[i].height, k = W + "x" + H;
                if (!(W > 0 && H > 0) || drawn[k]) continue;
                drawn[k] = true;
                var v = picker.viewFor(W, H, picker.bn, picker.bs, picker.bw, picker.be, picker.fitMode);
                var x0 = picker.xOf(Math.max(-180, v[2])), x1 = picker.xOf(Math.min(180, v[3]));
                var y0 = picker.yOf(Math.min(90, v[0])), y1 = picker.yOf(Math.max(-90, v[1]));
                var mine = W === thisW && H === thisH;
                ctx.strokeStyle = mine ? Kirigami.Theme.highlightColor : Kirigami.Theme.neutralTextColor;
                ctx.strokeRect(x0 + 0.5, y0 + 0.5, x1 - x0 - 1, y1 - y0 - 1);
                ctx.setLineDash([]);
                ctx.font = Math.round(picker.unit * 0.55) + "px sans-serif";
                ctx.fillStyle = ctx.strokeStyle;
                var label = (mine ? "this screen" : (sc[i].name || "another screen")) + " · " + W + "×" + H;
                ctx.fillText(label, Math.max(4, x0 + 5), mine ? Math.min(height - 4, y1 - 5) : Math.max(y0 + picker.unit * 0.7, 12));
                ctx.setLineDash([5, 4]);
            }
        }
    }
    // the box
    Rectangle {
        id: box
        x: picker.xOf(picker.bw); y: picker.yOf(picker.bn)
        width: picker.xOf(picker.be) - x; height: picker.yOf(picker.bs) - y
        color: "transparent"
        border.color: Kirigami.Theme.highlightColor; border.width: 2
    }
    Repeater {                                                   // the eight handles
        model: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]
        Rectangle {
            required property var modelData
            width: Math.round(picker.unit * 0.55); height: width; radius: 2
            x: box.x + modelData[0] * box.width - width / 2; y: box.y + modelData[1] * box.height - height / 2
            color: Kirigami.Theme.highlightColor; border.color: "white"; border.width: 1
        }
    }
    // the readout
    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: 6 }
        width: readout.implicitWidth + 12; height: readout.implicitHeight + 6; radius: 3; color: "#aa000000"
        QQC2.Label {
            id: readout
            anchors.centerIn: parent
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: "white"
            text: Math.abs(picker.bn) + "°" + (picker.bn >= 0 ? "N" : "S") + " – " + Math.abs(picker.bs) + "°" + (picker.bs >= 0 ? "N" : "S") + ", "
                + Math.abs(picker.bw) + "°" + (picker.bw >= 0 ? "E" : "W") + " – " + Math.abs(picker.be) + "°" + (picker.be >= 0 ? "E" : "W")
                + "  ·  " + (picker.be - picker.bw) + "° × " + (picker.bn - picker.bs) + "°"
        }
    }
    Rectangle {
        anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
        visible: !mouse.pressed
        width: hint.implicitWidth + 12; height: hint.implicitHeight + 6; radius: 3; color: "#aa000000"
        QQC2.Label { id: hint; anchors.centerIn: parent; font.pointSize: Kirigami.Theme.smallFont.pointSize; color: "white"; opacity: 0.85
                     text: "Drag to move · edges and corners to resize · wheel to zoom · drag outside for a new box" }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true                      // the settings page scrolls: without this the Flickable takes the drag after a few pixels and the box snaps back
        property string mode: ""                               // "move", "new", or a mix of n/s/w/e being pulled
        property real px: 0; property real py: 0               // where the press was
        property var start: null                               // the box at the press
        readonly property real grip: Math.max(8, picker.unit * 0.6)
        function modeAt(x, y) {
            var L = Math.abs(x - box.x) <= grip, R = Math.abs(x - (box.x + box.width)) <= grip;
            var T = Math.abs(y - box.y) <= grip, B = Math.abs(y - (box.y + box.height)) <= grip;
            var insideX = x >= box.x - grip && x <= box.x + box.width + grip, insideY = y >= box.y - grip && y <= box.y + box.height + grip;
            var m = "";
            if (insideX && insideY) { if (T) m += "n"; if (B) m += "s"; if (L) m += "w"; if (R) m += "e"; }
            if (m !== "") return m;
            return x > box.x && x < box.x + box.width && y > box.y && y < box.y + box.height ? "move" : "new";
        }
        cursorShape: {
            var m = pressed ? mode : modeAt(mouseX, mouseY);
            return m === "move" ? Qt.SizeAllCursor : m === "new" ? Qt.CrossCursor
                 : (m === "n" || m === "s") ? Qt.SizeVerCursor : (m === "w" || m === "e") ? Qt.SizeHorCursor
                 : (m === "nw" || m === "se") ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
        }
        onPressed: function (ev) {
            mode = modeAt(ev.x, ev.y); px = ev.x; py = ev.y;
            start = { n: picker.north, s: picker.south, w: picker.west, e: picker.east };
            picker.drag = start;
        }
        onPositionChanged: function (ev) {
            if (!pressed || !start) return;
            var dLon = (ev.x - px) / picker.pxPerDeg, dLat = -(ev.y - py) / picker.pxPerDeg;
            var b;
            if (mode === "move") {
                var wD = start.e - start.w, hD = start.n - start.s;
                var w = Math.max(-180, Math.min(180 - wD, start.w + dLon)), s = Math.max(-90, Math.min(90 - hD, start.s + dLat));
                b = { n: s + hD, s: s, w: w, e: w + wD };
            } else if (mode === "new") {
                var x0 = Math.min(px, ev.x), x1 = Math.max(px, ev.x), y0 = Math.min(py, ev.y), y1 = Math.max(py, ev.y);
                if (picker.lockToScreen) {
                    var wDeg = Math.max(10, (x1 - x0) / picker.pxPerDeg);
                    b = picker.shaped(picker.lonAt((x0 + x1) / 2), picker.latAt((y0 + y1) / 2), wDeg);
                } else b = { n: picker.latAt(y0), s: picker.latAt(y1), w: picker.lonAt(x0), e: picker.lonAt(x1) };
            } else {
                b = { n: start.n, s: start.s, w: start.w, e: start.e };
                if (mode.indexOf("n") >= 0) b.n = start.n + dLat;
                if (mode.indexOf("s") >= 0) b.s = start.s + dLat;
                if (mode.indexOf("w") >= 0) b.w = start.w + dLon;
                if (mode.indexOf("e") >= 0) b.e = start.e + dLon;
                if (picker.lockToScreen) {                                 // the pulled edge sets the zoom; the shape stays this screen's
                    var cx = (mode.indexOf("w") >= 0) ? b.e : (mode.indexOf("e") >= 0) ? b.w : (start.w + start.e) / 2;
                    var cy = (mode.indexOf("n") >= 0) ? b.s : (mode.indexOf("s") >= 0) ? b.n : (start.n + start.s) / 2;
                    var wNew = (mode.indexOf("w") >= 0 || mode.indexOf("e") >= 0) ? Math.max(10, b.e - b.w) : Math.max(5, b.n - b.s) * picker.screenAspect;
                    var hNew = wNew / picker.screenAspect;
                    // the opposite edge stays put: the box grows away from it
                    var cxc = (mode.indexOf("w") >= 0) ? b.e - wNew / 2 : (mode.indexOf("e") >= 0) ? b.w + wNew / 2 : cx;
                    var cyc = (mode.indexOf("n") >= 0) ? b.s + hNew / 2 : (mode.indexOf("s") >= 0) ? b.n - hNew / 2 : cy;
                    b = picker.shaped(cxc, cyc, wNew);
                }
            }
            picker.drag = picker.clampBox(b.n, b.s, b.w, b.e);
        }
        onReleased: { if (picker.drag) picker.commit(picker.drag); start = null; mode = ""; }
        onCanceled: { picker.drag = null; start = null; mode = ""; }
        onWheel: function (ev) {
            var f = ev.angleDelta.y > 0 ? 0.85 : 1 / 0.85;
            var lon = picker.lonAt(ev.x), lat = picker.latAt(ev.y);
            var wD = (picker.east - picker.west) * f, hD = (picker.north - picker.south) * f;
            if (wD > 360 || hD > 180) { picker.commit({ n: 90, s: -90, w: -180, e: 180 }); return; }
            var b;
            if (picker.lockToScreen) b = picker.shaped(lon - (lon - (picker.west + picker.east) / 2) * f, lat - (lat - (picker.north + picker.south) / 2) * f, wD);
            else {
                // keep the point under the pointer where it is
                var w = lon - (lon - picker.west) * f, n = lat - (lat - picker.north) * f;
                b = { n: n, s: n - hD, w: w, e: w + wD };
                if (b.w < -180) { b.e += -180 - b.w; b.w = -180; } if (b.e > 180) { b.w -= b.e - 180; b.e = 180; }
                if (b.n > 90) { b.s -= b.n - 90; b.n = 90; } if (b.s < -90) { b.n += -90 - b.s; b.s = -90; }
            }
            picker.commit(b);
            ev.accepted = true;
        }
    }
}
