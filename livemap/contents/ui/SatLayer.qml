/*
 * Satellites: the ISS, Hubble and Tiangong. The helper fetches CelesTrak's orbital elements and hands over
 * a ground track (a point every 30 s, from 15 min ago to 100 min ahead); this layer moves the marker along
 * that track with the wall clock, so nothing is computed here and the helper only runs every half hour.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import "geo.js" as Geo

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    property bool slow: false

    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
    readonly property color ink: cfg ? cfg.SatColor : "#9fe8ff"
    readonly property bool showTrack: cfg ? cfg.SatTrack : true
    readonly property int labelMode: cfg ? cfg.SatLabels : 1             // 0 none, 1 name, 2 name and altitude
    readonly property int labelPx: Math.round((cfg ? cfg.SatLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.SatLabelPlate : true
    readonly property color labelColor: cfg && !cfg.SatTextFollows ? cfg.SatTextColor : ink
    readonly property bool showIss: cfg ? cfg.SatIss : true
    readonly property bool showHubble: cfg ? cfg.SatHubble : true
    readonly property bool showTiangong: cfg ? cfg.SatTiangong : true
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: 5 * unit * markScale
    readonly property bool pictures: cfg ? cfg.SatMarkerStyle === 1 : false
    readonly property real pictureSize: (cfg ? cfg.SatPictureSize : 22) * unit * markScale
    readonly property var pictureOf: ({ ISS: "iss.png", Hubble: "hubble.png", Tiangong: "tiangong.png" })
    readonly property int units: cfg ? cfg.DistanceUnits : 0
    readonly property int trackChoice: cfg ? cfg.SatTrackLength : 1        // 0 next 30 min, 1 one orbit, 2 two orbits
    readonly property int aheadMinutes: [30, 100, 195][trackChoice] || 100
    property var sats: []
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    // the wall clock, ticked once a second (a satellite moves about 7.5 km/s: one pixel every second or two)
    property real now: Date.now() / 1000
    // the marker follows `now` every second; the track (18 shape paths) and the label (a full label relayout)
    // follow `slowNow`, which only moves every 20 s - the eye cannot tell, the GPU and the CPU can
    property real slowNow: now
    Timer {
        interval: 1000; running: overlay.fps > 0 && overlay.shown.length > 0; repeat: true
        onTriggered: { overlay.now = Date.now() / 1000; if (overlay.now - overlay.slowNow >= 20) overlay.slowNow = overlay.now; }
    }

    readonly property var shown: sats.filter(function (s) {
        return s.name === "ISS" ? showIss : s.name === "Hubble" ? showHubble : s.name === "Tiangong" ? showTiangong : true;
    })
    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    // where a satellite is right now: interpolated between the two track points around `now`
    function positionOf(s, at) {
        var t = at === undefined ? now : at, tr = s.track;
        if (!tr || tr.length < 2) return { lat: s.lat, lon: s.lon };
        var i = Math.max(0, Math.min(tr.length - 2, Math.floor((t - tr[0][0]) / 30)));
        var a = tr[i], b = tr[i + 1], k = Math.max(0, Math.min(1, (t - a[0]) / (b[0] - a[0])));
        var dlon = b[1] - a[1];
        if (dlon > 180) dlon -= 360; else if (dlon < -180) dlon += 360;   // across the date line
        var lon = a[1] + dlon * k;
        return { lat: a[2] + (b[2] - a[2]) * k, lon: lon > 180 ? lon - 360 : lon < -180 ? lon + 360 : lon };
    }
    // The ground track ahead of the satellite, as pixel polylines split where they cross the date line, in
    // `chunks` pieces so the line can fade towards its end: a ground track never closes (each orbit sits
    // 23 degrees west of the last), so a fading end says "this far ahead" instead of "broken loop".
    // Piece 0 runs from the marker's exact position to the first fixed vertex and follows `now` every
    // second (a few vertices: cheap); the other pieces follow `slowNow`, so the line never trails the marker.
    readonly property int chunks: 6
    function aheadTrack(s) { return (s.track || []).filter(function (p) { return p[0] >= slowNow - 30; }) }
    function trackChunk(s, k) {
        var out = [], pts = [], tr = aheadTrack(s);
        if (tr.length < 2) return out;
        var from = Math.floor(tr.length * k / chunks), to = Math.min(tr.length - 1, Math.ceil(tr.length * (k + 1) / chunks));
        if (k === 0) {
            // start at the marker and skip the vertices already behind it
            var p = positionOf(s), i0 = 1;
            while (i0 < to && tr[i0][0] <= now) i0++;
            pts.push(Qt.point(px(p.lon), py(p.lat)));
            for (var i = i0; i <= to; i++) {
                if (Math.abs(tr[i][1] - (i === i0 ? p.lon : tr[i - 1][1])) > 180) { if (pts.length > 1) out.push(pts); pts = []; }
                pts.push(Qt.point(px(tr[i][1]), py(tr[i][2])));
            }
            if (pts.length > 1) out.push(pts);
            return out;
        }
        for (var j = from; j <= to; j++) {
            if (j > from && Math.abs(tr[j][1] - tr[j - 1][1]) > 180) { if (pts.length > 1) out.push(pts); pts = []; }
            pts.push(Qt.point(px(tr[j][1]), py(tr[j][2])));
        }
        if (pts.length > 1) out.push(pts);
        return out;
    }
    readonly property var labelSpecs: labelMode === 0 ? [] : shown.map(function (s) {
        var p = positionOf(s, slowNow);
        return { key: "sat:" + s.name, x: px(p.lon), y: py(p.lat), gap: mark + 4 * unit, side: "right",
                 text: s.name + (labelMode === 2 ? " · " + Geo.distText(s.alt_km, units) : ""), px: labelPx, color: labelColor, plate: labelPlate, bold: true, alpha: 1 };
    })
    // The label is laid out against the 20-second position; between relayouts it slides with the marker by
    // this much (recomputed once a second, a handful of numbers), so the text never trails the picture.
    readonly property var labelShifts: (function () {
        var out = {};
        for (var i = 0; i < shown.length; i++) {
            var s = shown[i], a = positionOf(s, slowNow), b = positionOf(s, now);
            var dx = px(b.lon) - px(a.lon), dy = py(b.lat) - py(a.lat);
            if (Math.abs(dx) > width / 2) dx = 0;                     // crossed the date line: wait for the relayout
            out["sat:" + s.name] = { dx: dx, dy: dy };
        }
        return out;
    })()

    Exec {
        id: exec
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                if (r.note && overlay.sats.length > 0 && (!r.sats || r.sats.length === 0)) { console.warn("livemap sats: keeping the previous data -", r.note); return; }
                overlay.sats = r.sats || [];
                overlay.note = r.note && !(r.sats && r.sats.length) ? r.note : "";
                overlay.now = Date.now() / 1000; overlay.slowNow = overlay.now;
                console.warn("livemap sats:", overlay.sats.map(function (s) { return s.name + " " + s.lat.toFixed(1) + "," + s.lon.toFixed(1) }).join("; "), overlay.note);
            } catch (e) { overlay.note = "Satellites: the helper did not answer properly"; }
        }
    }
    Timer {                                       // the track covers 100 min ahead; refresh well inside that
        interval: (overlay.slow ? 60 : 30) * 60000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' sats --ahead " + overlay.aheadMinutes + " # " + Date.now())
    }
    onAheadMinutesChanged: if (helper !== "") exec.connectSource("python3 '" + helper + "' sats --ahead " + aheadMinutes + " # " + Date.now())

    Repeater {
        model: overlay.shown
        Item {
            id: sat
            required property var modelData
            anchors.fill: parent
            readonly property var at: overlay.positionOf(modelData)
            Repeater {                                // ground track ahead, fading towards its end
                model: overlay.showTrack ? overlay.chunks : 0
                Shape {
                    required property int index
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.6 * (1 - index / overlay.chunks) + 0.05)
                        strokeWidth: overlay.unit
                        fillColor: "transparent"
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [4, 4]
                        PathMultiline { paths: overlay.trackChunk(sat.modelData, index) }
                    }
                }
            }
            Rectangle {                               // the satellite as a symbol: a small bright square with a ring
                visible: !overlay.pictures
                x: overlay.px(sat.at.lon) - width / 2; y: overlay.py(sat.at.lat) - height / 2
                width: overlay.mark * 2.2; height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.7); border.width: overlay.unit
                Rectangle { anchors.centerIn: parent; width: overlay.mark; height: width; color: overlay.ink; rotation: 45 }
            }
            Image {                                   // or as a picture of the spacecraft (one shared texture per file)
                visible: overlay.pictures
                source: overlay.pictures ? Qt.resolvedUrl("../images/" + (overlay.pictureOf[sat.modelData.name] || "iss.png")) : ""
                x: overlay.px(sat.at.lon) - width / 2; y: overlay.py(sat.at.lat) - height / 2
                width: overlay.pictureSize; height: overlay.pictureSize * 0.65
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 384
                smooth: true; mipmap: true
                asynchronous: true
            }
        }
    }
}
