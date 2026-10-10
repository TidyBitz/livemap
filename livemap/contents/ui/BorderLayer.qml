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
import QtQuick.Window
import QtQuick.Shapes
import org.kde.plasma.plasma5support as P5Support
import "geo.js" as Geo

Item {
    id: overlay

    property var cfg: null
    property string helper: ""

    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
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
    readonly property int zoneStyle: cfg ? cfg.ZoneStyle : 0                   // 0 classic, 1 one row, 2 D3 band, 3 D1 tinted, 4 D1 + D3
    readonly property int zonePlacement: [0, 1, 2, 0, 2][zoneStyle] || 0        // 0 inside each zone, 1 one row, 2 a band
    readonly property bool rowMode: zonePlacement >= 1
    readonly property bool bandMode: zonePlacement === 2
    readonly property int zoneClock: cfg ? cfg.ZoneClock : 0                   // 0 offset, 1 offset and time, 2 offset, time and date, 3 time, 4 time and date
    readonly property bool zoneClock12: cfg ? cfg.ZoneClock12 : false
    property real clockMs: Date.now()                                          // ticks every minute while the clocks show
    Timer { interval: 60000; running: overlay.showZones && overlay.showZoneLabels && overlay.zoneClock > 0; repeat: true; triggeredOnStart: true
            onTriggered: overlay.clockMs = Date.now() }
    // The label for one zone: z = [text, lon, lat, width, offset now, next change (epoch s), offset after it].
    // The offset is the real one of the zone's main place (summer time included) while the data is fresh.
    function zoneText(z) {
        if (zoneClock === 0 || z.length < 7) return z[0];
        var off = z[5] > 0 && clockMs / 1000 >= z[5] ? z[6] : z[4];
        var d = new Date(clockMs + off * 3600000);
        var h = d.getUTCHours(), m = d.getUTCMinutes();
        var time = zoneClock12 ? ((h % 12) || 12) + ":" + (m < 10 ? "0" : "") + m + (h < 12 ? " am" : " pm") : (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        var date = days[d.getUTCDay()] + " " + d.getUTCDate() + " " + months[d.getUTCMonth()];
        var mm = /UTC([+-]?\d+)?(?::(\d+))?/.exec(z[0]), nom = mm && mm[1] ? parseInt(mm[1]) + (mm[2] ? parseInt(mm[2]) / 60 * (mm[1].charAt(0) === "-" ? -1 : 1) : 0) : 0;
        var first = zoneClock <= 2 ? z[0] + (Math.abs(off - nom) > 0.01 ? " DST" : "") + " \u00b7 " + time : time;
        return (zoneClock === 2 || zoneClock === 4) ? first + "\n" + date : first;
    }
    // The row as a band: the three facts of a zone at three sizes - the time large, the offset small above it, the
    // date only where it differs from this computer's (the one time it is news). In "inside each zone" mode
    // zoneText() still gives one string.
    function zoneParts(z) {
        var off = z.length >= 7 && z[5] > 0 && clockMs / 1000 >= z[5] ? z[6] : (z.length >= 7 ? z[4] : NaN);
        if (zoneClock === 0 || isNaN(off)) return { head: "", main: z[0], foot: "" };
        var d = new Date(clockMs + off * 3600000), here = new Date(clockMs);
        var h = d.getUTCHours(), m = d.getUTCMinutes();
        var time = zoneClock12 ? ((h % 12) || 12) + ":" + (m < 10 ? "0" : "") + m + (h < 12 ? " am" : " pm") : (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var other = d.getUTCDate() !== here.getDate() || d.getUTCMonth() !== here.getMonth();
        var withDate = zoneClock === 2 || zoneClock === 4;
        // the band is keyed by the standard offset; where the main place is on summer time its clock is an
        // hour ahead of the band's name, so say so, or two neighbours look like a duplicate
        var m = /UTC([+-]?\d+)?(?::(\d+))?/.exec(z[0]), nominal = m && m[1] ? parseInt(m[1]) + (m[2] ? parseInt(m[2]) / 60 * (m[1].charAt(0) === "-" ? -1 : 1) : 0) : 0;
        var dst = Math.abs(off - nominal) > 0.01 ? " \u00b7 DST" : "";
        return { head: zoneClock <= 2 ? z[0] + dst : "", main: time, foot: withDate && other ? days[d.getUTCDay()] + " " + d.getUTCDate() : "" };
    }
    function longestLine(t) { var parts = t.split("\n"), n = 0; for (var i = 0; i < parts.length; i++) n = Math.max(n, parts[i].length); return n; }
    function lineCount(t) { return t.split("\n").length }
    // the row's latitude; a region that does not reach it gets the row near the bottom of what is on screen
    property real viewNorth: 90
    property real viewSouth: -90
    readonly property int zoneRowLat: (function () {
        var want = cfg ? cfg.ZoneRowLat : -55;
        if (want >= viewSouth + 2 && want <= viewNorth - 2) return want;
        return Math.round(viewSouth + (viewNorth - viewSouth) * 0.12);
    })()
    property var zoneLines: []
    property var zoneLabels: []
    property string zoneTintFile: ""                                  // zones-tint.png once the helper has drawn it
    property real homeOffset: NaN                                     // this computer's UTC offset, for the band's mark
    readonly property bool wantTint: showZones && zoneStyle >= 3
    readonly property real tintStrength: (cfg ? cfg.ZoneTintOpacity : 12) / 100
    readonly property real bandStrength: (cfg ? cfg.ZoneBandOpacity : 55) / 100
    readonly property bool markHome: cfg ? cfg.ZoneMarkHome : true
    readonly property var zoneColours: ["#f67400", "#ffd23f", "#2ecc71", "#3daee9", "#9b59b6", "#da4453", "#1abc9c"]
    function zoneColour(text) {                                       // "UTC+5:30" -> the cycle colour of its hour
        var m = /UTC([+-]?\d+)?/.exec(text || ""), z = m && m[1] ? parseInt(m[1]) : 0;
        return zoneColours[((z % 7) + 7) % 7];
    }
    // the tint image is drawn by the helper on demand (once); asked for whenever the tint is wanted and missing
    P5Support.DataSource {
        id: tintExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => { disconnectSource(source); try { var r = JSON.parse(data.stdout); if (r.file) overlay.zoneTintFile = r.file; } catch (e) {} }
    }
    onWantTintChanged: if (wantTint && zoneTintFile === "" && helper !== "") tintExec.connectSource("python3 '" + helper + "' zone-tint # " + Date.now())

    property var coastLines: []
    property var borderLines: []
    property var stateLines: []
    property var countryNames: []
    // state and province names, and places (capitals, cities): both fitted around the country names
    readonly property bool showStateNames: showBorders && (cfg ? cfg.ShowStateNames : false)   // all of these are Countries' rows: its switch is theirs
    readonly property int stateRank: [4, 7, 12][cfg ? cfg.StateNameDensity : 1] || 7
    readonly property int statePx: Math.round((cfg ? cfg.StateNameSize : 8) * unit)
    readonly property bool showCapitals: cfg ? cfg.ShowCapitals : false
    readonly property bool showStateCapitals: cfg ? cfg.ShowStateCapitals : false
    readonly property bool showCities: cfg ? cfg.ShowCities : false
    readonly property int cityPop: showCities ? ([500000, 1000000, 5000000, 10000000][cfg ? cfg.CityMinPop : 1] || 1000000) : 0
    readonly property bool showPlaces: showBorders && (showCapitals || showStateCapitals || cityPop > 0)
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
          + (showZones ? " --zones" + (rowMode ? " --zone-row " + zoneRowLat : "") : "")
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
                overlay.homeOffset = r.home_offset === null || r.home_offset === undefined ? NaN : r.home_offset;
                if (r.zone_tint) overlay.zoneTintFile = r.zone_tint;
                else if (overlay.wantTint && overlay.helper !== "") tintExec.connectSource("python3 '" + overlay.helper + "' zone-tint # " + Date.now());
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
    // Inside each zone: fitted after the country names, places and state names, and only where the zone is
    // wide enough. In one row: the row was asked for, so every zone's label is placed first (only its
    // neighbours in the row can push it out) and the names make way for it instead.
    function zoneBox(z) {
        if (bandMode) {                                       // the band: the time's width, the band's height
            var bw = Math.max(z.parts.main.length * zonePx * 1.5 * 0.62, z.parts.head.length * zonePx * 0.62) + 6 * unit;
            return { x: z.x - bw / 2, y: z.y - bandHeight / 2, w: bw, h: bandHeight };
        }
        var tw = longestLine(z.text) * zonePx * 0.65, th = zonePx * 1.3 * lineCount(z.text);
        return { x: z.x - tw / 2, y: z.y - th / 2, w: tw, h: th };
    }
    // the band's height follows what the labels hold: offset line, the time at 1.5x, the date line, and padding
    readonly property real bandHeight: zonePx * (zoneClock === 0 ? 2.6
                                                 : (zoneClock <= 2 ? 1.5 : 0) + 2.2 + ((zoneClock === 2 || zoneClock === 4) ? 1.5 : 0) + 1.4)
    readonly property real bandY: (90 - zoneRowLat) / 180 * height
    readonly property var wantedZones: (function () {
        if (!showZones || !showZoneLabels) return [];
        var tick = clockMs;                                   // so the clocks re-fit every minute
        return zoneLabels.slice().sort(function (a, b) { return b[3] - a[3]; })
            .map(function (z) { return { text: zoneText(z), parts: zoneParts(z), w: z[3], x: (z[1] + 180) / 360 * width, y: (90 - z[2]) / 180 * height }; });
    })()
    readonly property var rowZones: (function () {             // one-row mode: the row first, among itself
        if (!rowMode) return [];
        var keep = Geo.declutter(wantedZones.map(zoneBox), 3 * unit);
        return wantedZones.filter(function (_z, k) { return keep[k]; });
    })()
    readonly property var rowZoneBoxes: rowZones.map(zoneBox)
    readonly property var fittedZones: (function () {
        if (rowMode) return rowZones;
        var taken = nameBoxes.concat(placeBoxes, stateBoxes);
        var wanted = wantedZones.filter(function (z) { return z.w * width / 360 > longestLine(z.text) * zonePx * 0.7; });
        var keep = Geo.declutter(taken.concat(wanted.map(zoneBox)), 3 * unit);
        return wanted.filter(function (_z, k) { return keep[taken.length + k]; });
    })()

    Image {                                                   // D1: each zone tinted, under every line
        anchors.fill: parent
        visible: overlay.wantTint && overlay.zoneTintFile !== ""
        asynchronous: true
        sourceSize: Qt.size(4096, 2048)
        source: visible ? "file://" + overlay.zoneTintFile : ""
        opacity: overlay.tintStrength
        smooth: true
    }
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
    function fitNames(list, w, h, rankLimit, px, taken) {
        var wanted = [], boxes = (taken || []).slice(), skip = boxes.length;
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
        return wanted.filter(function (_n, k) { return keep[skip + k]; });
    }
    readonly property var fittedNames: showBorders && showNames ? fitNames(countryNames, width, height, nameRank, namePx, rowZoneBoxes) : []
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
        var taken = rowZoneBoxes.concat(nameBoxes);
        var keep = Geo.declutter(taken.concat(wanted.map(function (p) { return placeBox(p); })), 2 * unit);
        return wanted.filter(function (_p, k) { return keep[taken.length + k]; });
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
        var taken = rowZoneBoxes.concat(nameBoxes, placeBoxes);
        var boxes = taken.concat(wanted.map(function (n) { return boxOf(n.x, n.y, n.name, statePx, cfg ? cfg.StateNameLabelBold : false); }));
        var keep = Geo.declutter(boxes, 2 * unit);
        return wanted.filter(function (_n, k) { return keep[taken.length + k]; });
    })()
    readonly property var stateBoxes: fittedStates.map(function (n) { return boxOf(n.x, n.y, n.name, statePx, cfg ? cfg.StateNameLabelBold : false); })

    // The band under the row: a translucent strip the width of the map with a tick at each zone edge, so the
    // labels have a baseline and sit on something instead of on the imagery.
    Rectangle {
        visible: overlay.showZones && overlay.showZoneLabels && overlay.bandMode
        x: 0; width: overlay.width
        y: overlay.bandY - overlay.bandHeight / 2; height: overlay.bandHeight
        color: Qt.rgba(0, 0.02, 0.06, overlay.bandStrength)
        border.color: Qt.rgba(overlay.zoneInk.r, overlay.zoneInk.g, overlay.zoneInk.b, 0.35 * overlay.zoneStrength * 2); border.width: Math.max(1, 0.6 * overlay.unit)
        Repeater {                                            // ticks at the zone edges on the row
            model: overlay.fittedZones
            Rectangle {
                required property var modelData
                x: modelData.x - modelData.w / 2 * overlay.width / 360 - width / 2
                y: 0; width: Math.max(1, 0.8 * overlay.unit); height: parent.height
                color: Qt.rgba(overlay.zoneInk.r, overlay.zoneInk.g, overlay.zoneInk.b, 0.4)
            }
        }
        Repeater {                                            // D3: this computer's zone marked in amber
            model: overlay.markHome && !isNaN(overlay.homeOffset) ? overlay.fittedZones.filter(function (z) { var m = /UTC([+-]?\d+(?::\d+)?)?/.exec(z.parts.head || z.text); var v = m && m[1] ? parseFloat(m[1].replace(":30", ".5").replace(":45", ".75")) : 0; return Math.abs(v - overlay.homeOffset) < 0.01; }) : []
            Rectangle {
                required property var modelData
                x: modelData.x - modelData.w / 2 * overlay.width / 360; y: 0
                width: Math.max(2, modelData.w * overlay.width / 360); height: parent.height
                color: Qt.rgba(1, 0.82, 0.25, 0.14)
                border.color: Qt.rgba(1, 0.82, 0.25, 0.9); border.width: Math.max(1, 1.2 * overlay.unit)
            }
        }
    }
    Repeater {                                                // time zones in the band: offset small, time large, date when it differs
        model: overlay.bandMode ? overlay.fittedZones : []
        Column {
            required property var modelData
            x: modelData.x - width / 2
            y: overlay.bandY - height / 2
            spacing: 0
            readonly property color ink: cfg && !cfg.ZoneTextFollows ? cfg.ZoneTextColor : overlay.zoneInk
            MapLabel { anchors.horizontalCenter: parent.horizontalCenter; visible: modelData.parts.head !== ""; text: modelData.parts.head; px: overlay.zonePx; textColor: ink; textOpacity: 0.7 * (cfg ? cfg.ZoneLabelOpacity : 100) / 100; plate: false; caps: true; letterScale: 1.2; haloScale: 0.8; unit: overlay.unit }
            MapLabel { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.parts.main; px: Math.round(overlay.zonePx * (overlay.zoneClock === 0 ? 1 : 1.5)); bold: true; textColor: ink; textOpacity: (cfg ? cfg.ZoneLabelOpacity : 100) / 100; plate: false; haloScale: 0.8; unit: overlay.unit }
            MapLabel { anchors.horizontalCenter: parent.horizontalCenter; visible: modelData.parts.foot !== ""; text: modelData.parts.foot; px: overlay.zonePx; textColor: ink; textOpacity: 0.85 * (cfg ? cfg.ZoneLabelOpacity : 100) / 100; plate: false; haloScale: 0.8; unit: overlay.unit }
        }
    }
    Repeater {                                                // time zone offsets inside each zone
        model: overlay.bandMode ? [] : overlay.fittedZones
        MapLabel {
            required property var modelData
            x: modelData.x - width / 2
            y: modelData.y - height / 2
            text: modelData.text
            textColor: cfg && !cfg.ZoneTextFollows ? cfg.ZoneTextColor : overlay.zoneInk
            textOpacity: (cfg ? cfg.ZoneLabelOpacity : 100) / 100
            plate: cfg ? cfg.ZoneLabelPlate : false
            plateColor: cfg ? cfg.PlateColor : "#000510"
            plateOpacity: (cfg ? cfg.PlateOpacity : 60) / 100
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
