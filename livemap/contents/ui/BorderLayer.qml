/*
 * Coastlines, country borders, state lines and country names as real vector
 * shapes (Natural Earth, public domain), so colour, opacity and thickness can be
 * changed live and the lines stay sharp at any resolution.
 *
 * QML cannot read local files, so the geometry comes from  livemap-helper.py
 * borders  as flat [lon, lat, lon, lat, ...] polylines; here they only get
 * projected (linear on this map) and stroked.
 *
 * Naming note: `states`, `data`, `layer`, `clip` ... are built-in Item
 * properties - none of them may be used as an id or property name in here.
 */
import QtQuick
import QtQuick.Shapes
import org.kde.plasma.plasma5support as P5Support
import "geo.js" as Geo

Item {
    id: overlay

    property var cfg: null
    property string helper: ""

    readonly property real unit: Math.max(1, width / 1920)
    readonly property color ink: cfg ? cfg.BorderColor : "#ffffff"
    readonly property real strength: (cfg ? cfg.BorderOpacity : 45) / 100
    readonly property real thickness: Math.max(0.3, (cfg ? cfg.BorderWidth : 100) / 100 * unit)
    readonly property bool showCoast: cfg ? cfg.ShowCoast : true
    readonly property bool showStates: cfg ? cfg.ShowStates : false
    readonly property bool showNames: cfg ? cfg.ShowCountryNames : false
    readonly property int nameRank: [2, 4, 10][cfg ? cfg.NameDensity : 1] || 4
    readonly property string detail: cfg && cfg.BorderDetail === 1 ? "50m" : "110m"
    // time zones: the same kind of vector outlines, in their own colour, with a UTC offset label per zone
    readonly property bool showZones: cfg ? cfg.ShowTimeZones : false
    readonly property color zoneInk: cfg ? cfg.ZoneColor : "#8fd3ff"
    readonly property real zoneStrength: (cfg ? cfg.ZoneOpacity : 35) / 100
    readonly property bool showZoneLabels: cfg ? cfg.ZoneLabels : true
    readonly property int zonePx: Math.round((cfg ? cfg.ZoneLabelSize : 9) * unit)
    readonly property int zonePlacement: cfg ? cfg.ZonePlacement : 0           // 0 inside each zone, 1 one row
    readonly property int zoneRowLat: cfg ? cfg.ZoneRowLat : -55
    property var zoneLines: []
    property var zoneLabels: []

    property var coastLines: []
    property var borderLines: []
    property var stateLines: []
    property var countryNames: []
    property string note: ""
    readonly property string hint: note          // shown by main.qml

    // ask the helper again whenever what we need changes
    readonly property string request: helper === "" ? ""
        : "python3 '" + helper + "' borders --detail " + detail + (showStates ? " --states" : "") + (showNames ? " --names" : "")
          + (showZones ? " --zones" + (zonePlacement === 1 ? " --zone-row " + zoneRowLat : "") : "")
    onRequestChanged: if (request !== "") exec.connectSource(request + " # " + Date.now())

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf(overlay.request) !== 0) return;               // an answer to an older question
            try {
                var r = JSON.parse(data.stdout);
                overlay.coastLines = r.coast; overlay.borderLines = r.borders;
                overlay.stateLines = r.states; overlay.countryNames = r.names;
                overlay.zoneLines = r.zones || []; overlay.zoneLabels = r.zone_labels || [];
                overlay.note = r.note || "";
                console.warn("livemap borders:", r.coast.length, "coast lines,", r.borders.length, "border lines,",
                             r.states.length, "state lines,", r.names.length, "names,", (r.zones || []).length, "time zone lines (" + overlay.detail + ")", overlay.note);
            } catch (e) {
                overlay.note = "Borders: the helper did not answer properly";
                console.warn("livemap borders:", e, String(data.stderr).trim().split("\n").pop());
            }
        }
    }

    // flat [lon, lat, ...] polylines -> lists of points in this item's pixels
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
    readonly property var coastPaths: showCoast ? project(coastLines, width, height) : []
    readonly property var borderPaths: project(borderLines, width, height)
    readonly property var statePaths: showStates ? project(stateLines, width, height) : []
    readonly property var zonePaths: showZones ? project(zoneLines, width, height) : []
    // one label per zone polygon, only where the polygon is wide enough for it; biggest polygons first
    // Zone labels: widest areas first, only where the area is wide enough for the text, never over a country
    // name (the fitted names go into the overlap test first, as boxes that are already taken).
    readonly property var fittedZones: (function () {
        if (!showZones || !showZoneLabels) return [];
        var taken = fittedNames.map(function (n) {
            var tw = n.name.length * (n.size * 0.7 + unit), th = n.size * 1.3;
            return { x: n.x - tw / 2, y: n.y - th / 2, w: tw, h: th };
        });
        var wanted = zoneLabels.slice().sort(function (a, b) { return b[3] - a[3]; })
            .filter(function (z) { return z[3] * width / 360 > z[0].length * zonePx * 0.7; })
            .map(function (z) { return { text: z[0], x: (z[1] + 180) / 360 * width, y: (90 - z[2]) / 180 * height }; });
        var boxes = taken.concat(wanted.map(function (z) {
            var tw = z.text.length * zonePx * 0.65, th = zonePx * 1.3;
            return { x: z.x - tw / 2, y: z.y - th / 2, w: tw, h: th };
        }));
        var keep = Geo.declutter(boxes, 3 * unit);
        return wanted.filter(function (_z, k) { return keep[taken.length + k]; });
    })()

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {                                           // time zones, underneath the political lines
            strokeColor: Qt.rgba(overlay.zoneInk.r, overlay.zoneInk.g, overlay.zoneInk.b, overlay.zoneStrength)
            strokeWidth: overlay.thickness * 0.8
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: overlay.zonePaths }
        }
        ShapePath {                                           // states and provinces: faintest
            strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, overlay.strength * 0.5)
            strokeWidth: overlay.thickness * 0.6
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: overlay.statePaths }
        }
        ShapePath {                                           // coastlines
            strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, overlay.strength * 0.75)
            strokeWidth: overlay.thickness * 0.8
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: overlay.coastPaths }
        }
        ShapePath {                                           // country borders
            strokeColor: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, overlay.strength)
            strokeWidth: overlay.thickness
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: overlay.borderPaths }
        }
    }

    // Country names: most important first, and one that would print over an earlier one is left out,
    // so "All" means "as many as fit on this screen" instead of a pile of letters over Europe.
    readonly property int namePx: Math.round((cfg ? cfg.NameSize : 10) * unit)
    readonly property real nameStrength: (cfg ? cfg.NameOpacity : 85) / 100
    function fitNames(list, w, h, rankLimit, px) {
        var wanted = [], boxes = [];
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            if (n[3] > rankLimit) continue;
            var size = n[3] <= 2 ? Math.round(px * 1.25) : px;
            var tw = n[0].length * (size * 0.7 + overlay.unit), th = size * 1.3;
            var x = (n[1] + 180) / 360 * w, y = (90 - n[2]) / 180 * h;
            wanted.push({ name: n[0], x: x, y: y, size: size });
            boxes.push({ x: x - tw / 2, y: y - th / 2, w: tw, h: th });
        }
        var keep = Geo.declutter(boxes, 2 * overlay.unit);
        return wanted.filter(function (_n, k) { return keep[k]; });
    }
    readonly property var fittedNames: showNames ? fitNames(countryNames, width, height, nameRank, namePx) : []

    Repeater {                                                // time zone offsets
        model: overlay.fittedZones
        MapLabel {
            required property var modelData
            x: modelData.x - width / 2
            y: modelData.y - height / 2
            text: modelData.text
            textColor: overlay.zoneInk
            textOpacity: Math.min(1, overlay.zoneStrength * 2) * (cfg ? cfg.ZoneLabelOpacity : 100) / 100
            plate: false
            plateColor: cfg ? cfg.PlateColor : "#000510"
            px: overlay.zonePx
            bold: cfg ? cfg.ZoneLabelBold : false
            caps: cfg ? cfg.ZoneLabelCaps : false
            haloScale: (cfg ? cfg.ZoneLabelHalo : 100) / 100
            letterScale: (cfg ? cfg.ZoneLabelSpacing : 100) / 100
            unit: overlay.unit
        }
    }

    readonly property color nameColor: cfg && !cfg.NameTextFollows ? cfg.NameTextColor : ink
    Repeater {
        model: overlay.fittedNames
        MapLabel {
            required property var modelData
            x: modelData.x - width / 2
            y: modelData.y - height / 2
            text: modelData.name
            textColor: overlay.nameColor
            textOpacity: overlay.nameStrength
            plate: cfg ? cfg.NamePlate : false
            plateColor: cfg ? cfg.PlateColor : "#000510"
            plateOpacity: (cfg ? cfg.PlateOpacity : 60) / 100
            px: modelData.size
            bold: cfg ? cfg.NameBold : true
            caps: cfg ? cfg.NameCaps : true
            haloScale: (cfg ? cfg.NameHalo : 100) / 100
            letterScale: (cfg ? cfg.NameSpacing : 100) / 100
            unit: overlay.unit
        }
    }
}
