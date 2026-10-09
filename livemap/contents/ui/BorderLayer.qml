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
    // state and province names, and places (capitals, cities): both fitted around the country names
    readonly property bool showStateNames: cfg ? cfg.ShowStateNames : false
    readonly property int stateRank: [4, 7, 12][cfg ? cfg.StateNameDensity : 1] || 7
    readonly property int statePx: Math.round((cfg ? cfg.StateNameSize : 8) * unit)
    readonly property bool showCapitals: cfg ? cfg.ShowCapitals : false
    readonly property bool showStateCapitals: cfg ? cfg.ShowStateCapitals : false
    readonly property bool showCities: cfg ? cfg.ShowCities : false
    readonly property int cityPop: showCities ? ([500000, 1000000, 5000000, 10000000][cfg ? cfg.CityMinPop : 1] || 1000000) : 0
    readonly property bool showPlaces: showCapitals || showStateCapitals || cityPop > 0
    // one style per place kind (0 country capital, 1 state capital, 2 city): colour, size, marks (0 dot and
    // name, 1 dot only, 2 name only) and the label style row; cities can size their dot by population
    function kindStyle(prefix, fallbackPx) {
        return cfg ? { ink: cfg[prefix + "Color"], px: Math.round(cfg[prefix + "Size"] * unit), marks: cfg[prefix + "Marks"],
                       bold: !!cfg[prefix + "LabelBold"], caps: !!cfg[prefix + "LabelCaps"], spacing: cfg[prefix + "LabelSpacing"] / 100,
                       alpha: cfg[prefix + "LabelOpacity"] / 100, halo: cfg[prefix + "LabelHalo"] / 100 }
                   : { ink: "#ffe3a0", px: Math.round(fallbackPx * unit), marks: 0, bold: false, caps: false, spacing: 1, alpha: 1, halo: 1 };
    }
    readonly property string kindKey: !cfg ? "" : [cfg.CapitalColor, cfg.CapitalSize, cfg.CapitalMarks, cfg.CapitalLabelBold, cfg.CapitalLabelCaps, cfg.CapitalLabelSpacing, cfg.CapitalLabelOpacity, cfg.CapitalLabelHalo,
        cfg.StateCapitalColor, cfg.StateCapitalSize, cfg.StateCapitalMarks, cfg.StateCapitalLabelBold, cfg.StateCapitalLabelCaps, cfg.StateCapitalLabelSpacing, cfg.StateCapitalLabelOpacity, cfg.StateCapitalLabelHalo,
        cfg.CityColor, cfg.CitySize, cfg.CityMarks, cfg.CityLabelBold, cfg.CityLabelCaps, cfg.CityLabelSpacing, cfg.CityLabelOpacity, cfg.CityLabelHalo, cfg.CityPopScale, unit].join(",")
    property var kinds: [kindStyle("Capital", 8), kindStyle("StateCapital", 7), kindStyle("City", 7)]
    onKindKeyChanged: kinds = [kindStyle("Capital", 8), kindStyle("StateCapital", 7), kindStyle("City", 7)]
    readonly property bool cityPopScale: cfg ? cfg.CityPopScale : true
    // state names: own text colour (or the country names'), own style row
    readonly property color stateInk: cfg && !cfg.StateNameTextFollows ? cfg.StateNameTextColor : nameColor
    // rivers, under the coastlines
    readonly property bool showRivers: cfg ? cfg.ShowRivers : false
    readonly property color riverInk: cfg ? cfg.RiverColor : "#6fb7ff"
    readonly property real riverStrength: (cfg ? cfg.RiverOpacity : 50) / 100
    readonly property real riverThickness: Math.max(0.3, (cfg ? cfg.RiverWidth : 80) / 100 * unit)
    readonly property real zoneThickness: Math.max(0.3, (cfg ? cfg.ZoneWidth : 80) / 100 * unit)
    readonly property bool showBorders: cfg ? cfg.ShowBorders : true
    property var stateNames: []
    property var places: []
    property var riverLines: []
    property string note: ""
    readonly property string hint: note          // shown by main.qml

    // ask the helper again whenever what we need changes
    readonly property string request: helper === "" ? ""
        : "python3 '" + helper + "' borders --detail " + detail + (showStates ? " --states" : "") + (showNames ? " --names" : "")
          + (showZones ? " --zones" + (zonePlacement === 1 ? " --zone-row " + zoneRowLat : "") : "")
          + (showStateNames ? " --state-names" : "") + (showCapitals ? " --capitals" : "") + (showStateCapitals ? " --state-capitals" : "")
          + (cityPop > 0 ? " --city-pop " + cityPop : "") + (showRivers ? " --rivers" : "")
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
                overlay.stateNames = r.state_names || []; overlay.places = r.places || []; overlay.riverLines = r.rivers || [];
                overlay.note = r.note || "";
                console.warn("livemap borders:", r.coast.length, "coast lines,", r.borders.length, "border lines,",
                             r.states.length, "state lines,", r.names.length, "names,", (r.state_names || []).length, "state names,", (r.places || []).length, "places,", (r.zones || []).length, "time zone lines (" + overlay.detail + ")", overlay.note);
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
    readonly property var coastPaths: showBorders && showCoast ? project(coastLines, width, height) : []
    readonly property var borderPaths: showBorders ? project(borderLines, width, height) : []
    readonly property var statePaths: showBorders && showStates ? project(stateLines, width, height) : []
    readonly property var riverPaths: showRivers ? project(riverLines, width, height) : []
    readonly property var zonePaths: showZones ? project(zoneLines, width, height) : []
    // one label per zone polygon, only where the polygon is wide enough for it; biggest polygons first
    // Zone labels: widest areas first, only where the area is wide enough for the text, never over a country
    // name (the fitted names go into the overlap test first, as boxes that are already taken).
    readonly property var fittedZones: (function () {
        if (!showZones || !showZoneLabels) return [];
        var taken = nameBoxes.concat(placeBoxes, stateBoxes);
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
        ShapePath {                                           // rivers, underneath everything
            strokeColor: Qt.rgba(overlay.riverInk.r, overlay.riverInk.g, overlay.riverInk.b, overlay.riverStrength)
            strokeWidth: overlay.riverThickness
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathMultiline { paths: overlay.riverPaths }
        }
        ShapePath {                                           // time zones, underneath the political lines
            strokeColor: Qt.rgba(overlay.zoneInk.r, overlay.zoneInk.g, overlay.zoneInk.b, overlay.zoneStrength)
            strokeWidth: overlay.zoneThickness
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
    readonly property var fittedNames: showBorders && showNames ? fitNames(countryNames, width, height, nameRank, namePx) : []
    function boxOf(x, y, text, px, bold) {
        var tw = text.length * (px * (bold ? 0.72 : 0.62) + overlay.unit), th = px * 1.3;
        return { x: x - tw / 2, y: y - th / 2, w: tw, h: th };
    }
    readonly property var nameBoxes: fittedNames.map(function (n) { return boxOf(n.x, n.y, n.name, n.size, true); })
    // Places: a dot with the name to its right; country capitals first, then by population (the helper's order).
    readonly property var fittedPlaces: (function () {
        if (!showPlaces) return [];
        var wanted = places.map(function (p) {
            var st = kinds[p[4]] || kinds[2], x = (p[1] + 180) / 360 * width, y = (90 - p[2]) / 180 * height;
            var dot = st.marks === 2 ? 0 : st.px * (p[4] === 0 ? 0.55 : p[4] === 1 ? 0.42 : 0.32);
            if (p[4] === 2 && cityPopScale && dot > 0) dot *= 0.7 + 0.45 * Math.max(0, Math.log10(Math.max(1, p[3]) / 500000));   // 500k 0.7x ... 20M 1.4x
            var named = st.marks !== 1;
            return { name: p[0], x: x, y: y, kind: p[4], dot: dot, named: named, px: st.px, lx: x + dot + 3 * unit, ly: y };
        });
        var boxes = nameBoxes.concat(wanted.map(function (p) { return placeBox(p); }));
        var keep = Geo.declutter(boxes, 2 * unit);
        return wanted.filter(function (_p, k) { return keep[nameBoxes.length + k]; });
    })()
    function placeBox(p) {
        if (!p.named) return { x: p.x - p.dot, y: p.y - p.dot, w: 2 * p.dot, h: 2 * p.dot };
        var b = boxOf(0, p.ly, p.name, p.px, p.kind === 0); b.x = p.x - p.dot; b.w += p.dot + 3 * unit + p.dot; return b;
    }
    readonly property var placeBoxes: fittedPlaces.map(placeBox)
    // State and province names: after the country names and the places, by rank.
    readonly property var fittedStates: (function () {
        if (!showStateNames) return [];
        var wanted = stateNames.filter(function (n) { return n[3] <= stateRank; })
            .map(function (n) { return { name: n[0], x: (n[1] + 180) / 360 * width, y: (90 - n[2]) / 180 * height }; });
        var taken = nameBoxes.concat(placeBoxes);
        var boxes = taken.concat(wanted.map(function (n) { return boxOf(n.x, n.y, n.name, statePx, cfg ? cfg.StateNameLabelBold : false); }));
        var keep = Geo.declutter(boxes, 2 * unit);
        return wanted.filter(function (_n, k) { return keep[taken.length + k]; });
    })()
    readonly property var stateBoxes: fittedStates.map(function (n) { return boxOf(n.x, n.y, n.name, statePx, cfg ? cfg.StateNameLabelBold : false); })

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

    Repeater {                                                // state and province names: the country-name style, smaller
        model: overlay.fittedStates
        MapLabel {
            required property var modelData
            x: modelData.x - width / 2
            y: modelData.y - height / 2
            text: modelData.name
            textColor: overlay.stateInk
            textOpacity: (cfg ? cfg.StateNameLabelOpacity : 100) / 100
            plate: cfg ? cfg.NamePlate : false
            plateColor: cfg ? cfg.PlateColor : "#000510"
            plateOpacity: (cfg ? cfg.PlateOpacity : 60) / 100
            px: overlay.statePx
            bold: cfg ? cfg.StateNameLabelBold : false
            caps: cfg ? cfg.StateNameLabelCaps : false
            haloScale: (cfg ? cfg.StateNameLabelHalo : 100) / 100
            letterScale: (cfg ? cfg.StateNameLabelSpacing : 100) / 100
            unit: overlay.unit
        }
    }

    Repeater {                                                // places: a dot (ringed for a country capital) and the name
        model: overlay.fittedPlaces
        Item {
            required property var modelData
            readonly property var st: overlay.kinds[modelData.kind] || overlay.kinds[2]
            x: modelData.x; y: modelData.y
            Rectangle {
                visible: modelData.dot > 0
                anchors.centerIn: parent
                width: modelData.dot * 2; height: width; radius: width / 2
                color: modelData.kind === 0 ? "transparent" : st.ink
                border.color: st.ink; border.width: modelData.kind === 0 ? Math.max(1, 1.2 * overlay.unit) : 0
                Rectangle { visible: modelData.kind === 0; anchors.centerIn: parent; width: parent.width * 0.45; height: width; radius: width / 2; color: st.ink }
            }
            MapLabel {
                visible: modelData.named
                x: modelData.named && modelData.dot === 0 ? -width / 2 : modelData.lx - modelData.x
                y: -height / 2
                text: modelData.name
                textColor: st.ink
                textOpacity: st.alpha
                plate: false
                plateColor: cfg ? cfg.PlateColor : "#000510"
                px: st.px
                bold: st.bold || modelData.kind === 0
                caps: st.caps
                haloScale: st.halo
                letterScale: st.spacing
                unit: overlay.unit
            }
        }
    }
}
