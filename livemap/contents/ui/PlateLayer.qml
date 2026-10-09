/*
 * Tectonic plate boundaries - the "fault lines" of a world map - as vector lines from Peter Bird's
 * PB2002 model (GeoJSON conversion by Hugo Ahlenius / Nordpil, ODC-By). Downloaded together with the
 * border data; the helper's `plates` command hands them over as flat [lon, lat, ...] polylines, exactly
 * like BorderLayer, and they are projected and stroked here. Still geometry: it lives in the cached part
 * of the map, so it costs nothing while idle. Colour, opacity and thickness come from the Earthquakes
 * settings, where the lines explain the ring clusters.
 */
import QtQuick
import QtQuick.Shapes
import org.kde.plasma.plasma5support as P5Support

Item {
    id: overlay

    property var cfg: null
    property string helper: ""

    readonly property real unit: Math.max(1, width / 1920)
    readonly property color ink: cfg ? cfg.PlateLineColor : "#ff7a59"
    readonly property real strength: (cfg ? cfg.PlateLineOpacity : 45) / 100
    readonly property real thickness: Math.max(0.3, (cfg ? cfg.PlateLineWidth : 100) / 100 * unit)

    property var plateLines: []
    property string note: ""
    readonly property string hint: note          // shown by main.qml

    readonly property string request: helper === "" ? "" : "python3 '" + helper + "' plates"
    onRequestChanged: if (request !== "") exec.connectSource(request + " # " + Date.now())

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf(overlay.request) !== 0) return;
            try {
                var r = JSON.parse(data.stdout);
                overlay.plateLines = r.plates || [];
                overlay.note = r.note || "";
                console.warn("livemap plates:", overlay.plateLines.length, "boundary lines", overlay.note);
            } catch (e) {
                overlay.note = "Plate boundaries: the helper did not answer properly";
                console.warn("livemap plates:", e, String(data.stderr).trim().split("\n").pop());
            }
        }
    }

    // flat [lon, lat, ...] polylines -> lists of points in this item's pixels (linear on this map)
    function project(lines, w, h) {
        var out = [];
        for (var i = 0; i < lines.length; i++) {
            var flat = lines[i], pts = [];
            for (var j = 0; j + 1 < flat.length; j += 2)
                pts.push(Qt.point((flat[j] + 180) / 360 * w, (90 - flat[j + 1]) / 180 * h));
            out.push(pts);
        }
        return out;
    }
    readonly property var platePaths: project(plateLines, width, height)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, overlay.strength)
            strokeWidth: overlay.thickness
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathMultiline { paths: overlay.platePaths }
        }
    }
}
