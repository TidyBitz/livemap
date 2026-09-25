/*
 * Your machine's live connections, drawn as great-circle arcs from home.
 *
 * QML cannot list sockets, so a small helper does it:  livemap-helper.py net
 * runs `ss`, looks each remote address up in an offline GeoIP database and
 * prints JSON. Nothing about your connections leaves the machine.
 *
 * Arcs live in a ListModel keyed by place, so an arc that is still there on
 * the next poll is left alone (no flicker, animation keeps running), new
 * places fade in, and closed ones disappear.
 */
import QtQuick
import QtQuick.Shapes
import org.kde.plasma.plasma5support as P5Support
import "geo.js" as Geo

Item {
    id: overlay

    property var cfg: null
    property string helper: ""

    readonly property real homeLat: cfg ? parseFloat(cfg.HomeLat) : NaN
    readonly property real homeLon: cfg ? parseFloat(cfg.HomeLon) : NaN
    readonly property bool haveHome: isFinite(homeLat) && isFinite(homeLon)
                                     && Math.abs(homeLat) <= 90 && Math.abs(homeLon) <= 180
    readonly property bool labels: cfg ? cfg.NetLabels : true
    readonly property int animation: cfg ? cfg.ArcAnimation : 0          // 0 packets, 1 pulse, 2 both, 3 none
    readonly property bool packets: animation === 0 || animation === 2
    readonly property bool pulsing: animation === 1 || animation === 2
    readonly property bool labelPlate: cfg ? cfg.LabelPlate : true
    readonly property color labelColor: cfg ? cfg.NetTextColor : "#e6f7ff"
    readonly property int seconds: Math.max(3, cfg ? cfg.NetInterval : 10)
    readonly property real unit: Math.max(1, width / 1920)
    readonly property color arc: cfg ? cfg.ArcColor : "#8ce6ff"
    readonly property real widthScale: Math.max(0.2, (cfg ? cfg.ArcWidth : 100) / 100)
    readonly property bool glow: cfg ? cfg.ArcGlow : true
    readonly property real speed: Math.max(0.1, (cfg ? cfg.PacketSpeed : 100) / 100)
    readonly property int labelSize: cfg ? cfg.LabelSize : 11
    readonly property bool showProcess: cfg ? cfg.NetShowProcess : true
    readonly property int maxPlaces: cfg ? cfg.NetMaxPlaces : 40
    readonly property int linger: cfg ? cfg.NetLinger : 90                 // seconds a closed connection stays, fading
    readonly property int newWindow: (cfg ? cfg.NewWindow : 60) * 60       // how long "first time ever" is highlighted
    readonly property color closedColor: cfg ? cfg.ClosedColor : "#8b97a8"
    readonly property color newColor: cfg ? cfg.NewColor : "#ffd24a"
    readonly property bool showLatency: cfg ? cfg.ShowLatency : true
    readonly property bool flagFastRtt: cfg ? cfg.FlagFastRtt : true
    property bool proxied: false         // most round trips are answered locally: the numbers say nothing about the far end
    property string note: ""
    // animation clock (see QuakeLayer): stepped by a Timer at the chosen rate, stopped when there is nothing to animate
    property int fps: 30
    property bool slow: false            // on battery: look at the connections once a minute at most
    property real clock: 0
    Timer {
        interval: Math.round(1000 / Math.max(1, overlay.fps))
        running: overlay.fps > 0 && (overlay.packets || overlay.pulsing) && peers.count > 0
        repeat: true
        onTriggered: overlay.clock += interval
    }
    // shown by main.qml in one place that is always on screen (this item can extend past it in Crop mode)
    readonly property string hint: !haveHome ? "set your home latitude / longitude in the settings to draw network arcs" : note

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }

    // ---- data ---------------------------------------------------------------
    ListModel { id: peers }

    function sync(list) {
        var seen = {};
        for (var i = 0; i < list.length; i++) {
            var p = list[i], at = -1;
            seen[p.key] = true;
            for (var j = 0; j < peers.count; j++)
                if (peers.get(j).key === p.key) { at = j; break; }
            if (at < 0)
                peers.append({ key: p.key, lat: p.lat, lon: p.lon, n: p.n, place: p.place || "",
                               proc: p.proc || "", show: p.show !== false, side: p.side || "right",
                               rtt: p.rtt === undefined ? -1 : p.rtt, life: p.life || "live",
                               ago: p.ago || 0, fresh: p.fresh || "" });
            else {
                peers.setProperty(at, "n", p.n);
                peers.setProperty(at, "proc", p.proc || "");
                peers.setProperty(at, "show", p.show !== false);
                peers.setProperty(at, "side", p.side || "right");
                peers.setProperty(at, "rtt", p.rtt === undefined ? -1 : p.rtt);
                peers.setProperty(at, "life", p.life || "live");
                peers.setProperty(at, "ago", p.ago || 0);
                peers.setProperty(at, "fresh", p.fresh || "");
            }
        }
        proxied = flagFastRtt && Geo.mostlyProxied(list, homeLat, homeLon);
        for (var k = peers.count - 1; k >= 0; k--)
            if (!seen[peers.get(k).key]) peers.remove(k);
        peerStamp++;
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                overlay.note = "livemap-helper failed: " + String(data.stderr).trim().split("\n").pop();
                return;
            }
            try {
                var r = JSON.parse(data.stdout);
                overlay.note = r.note || "";
                overlay.sync(r.peers || []);
            } catch (e) { overlay.note = "livemap-helper: unreadable output"; }
        }
    }
    Timer {
        interval: (overlay.slow ? Math.max(60, overlay.seconds) : overlay.seconds) * 1000
        running: overlay.helper !== "" && overlay.haveHome
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + overlay.helper + "' net --max " + overlay.maxPlaces + " --home-lon " + overlay.homeLon
                                          + " --linger " + overlay.linger + " --new-window " + overlay.newWindow)
    }

    // ---- drawing ------------------------------------------------------------
    Repeater {
        model: peers
        Item {
            id: link
            required property string key
            required property real lat
            required property real lon
            required property int n
            required property string place
            required property string proc
            required property bool show
            required property int index
            required property string life                 // "live", "connecting" (no answer yet) or "closed"
            required property int ago                     // seconds since it closed
            required property string fresh                // "", "place" or "country": first time ever seen

            // closed connections change colour and fade out over the linger time instead of vanishing;
            // `ago` only changes when the helper is asked again, and each step is eased by the Behavior
            // novelty wins over "closed": a brief first-ever connection is exactly the one worth noticing (the fade still shows it closed)
            readonly property color tint: fresh !== "" ? overlay.newColor : life === "closed" ? overlay.closedColor : overlay.arc
            readonly property real strength: life === "closed" ? Math.max(0.12, 1 - ago / Math.max(1, overlay.linger))
                                           : life === "connecting" ? 0.45 : 1
            property bool born: false
            Component.onCompleted: born = true
            anchors.fill: parent
            opacity: born ? strength : 0
            Behavior on opacity { NumberAnimation { duration: 900 } }

            readonly property var segs: Geo.arc(overlay.homeLat, overlay.homeLon, lat, lon, 48)
            readonly property var flat: [].concat.apply([], segs)
            readonly property real km: Geo.distanceKm(overlay.homeLat, overlay.homeLon, lat, lon)
            readonly property real weight: Math.min(3, Math.log(1 + n) / Math.LN2) * overlay.unit * overlay.widthScale
            readonly property var paths: segs.map(function (s) {
                return s.map(function (p) { return Qt.point(overlay.px(p.lon), overlay.py(p.lat)); });
            })

            Shape {                                       // halo: steady glow, or breathing when "pulse" is chosen
                id: halo
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: (overlay.glow || overlay.pulsing) && link.life !== "closed"
                ShapePath {
                    strokeColor: Qt.rgba(link.tint.r, link.tint.g, link.tint.b, overlay.pulsing ? 0.34 : 0.14)
                    strokeWidth: (overlay.pulsing ? 6 : 4) * overlay.unit * overlay.widthScale + link.weight * 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathMultiline { paths: link.paths }
                }
                opacity: overlay.pulsing && overlay.fps > 0 && link.life === "live"
                    ? 0.625 + 0.375 * Math.sin(overlay.clock / (3000 / overlay.speed) * 2 * Math.PI + link.index * 1.7) : 1
            }
            Shape {                                       // core line
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.rgba(link.tint.r, link.tint.g, link.tint.b, 0.85)
                    strokeWidth: 0.8 * overlay.unit * overlay.widthScale + link.weight * 0.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathMultiline { paths: link.paths }
                }
            }

            Rectangle {                                   // a "packet" running home -> peer
                readonly property real t: (overlay.clock / ((1400 + link.km / 4) / overlay.speed) + link.index * 0.137) % 1
                readonly property var at: (link.flat.length
                    ? link.flat[Math.max(0, Math.min(link.flat.length - 1, Math.floor(t * link.flat.length)))]
                    : null) || ({ lat: link.lat, lon: link.lon })
                visible: overlay.packets && overlay.fps > 0 && link.life === "live" && link.flat.length > 1
                width: 4 * overlay.unit; height: width; radius: width / 2
                color: "#eafcff"
                x: overlay.px(at.lon) - width / 2
                y: overlay.py(at.lat) - height / 2
            }

            Rectangle {                                   // remote end
                x: overlay.px(link.lon) - width / 2
                y: overlay.py(link.lat) - height / 2
                width: (5 + link.weight) * overlay.unit; height: width; radius: width / 2
                color: Qt.rgba(link.tint.r, link.tint.g, link.tint.b, 0.95)
                border.color: Qt.rgba(1, 1, 1, 0.6); border.width: 1
            }
        }
    }

    // Labels are described here and drawn by main.qml's LabelPass, above every layer. Each goes on the
    // side of its dot that faces away from home (the helper decides), so its own arc never runs through it.
    function labelText(p) {
        return p.place + (showProcess && p.proc !== "" ? " \u00b7 " + p.proc : "")
            + (showLatency && !proxied && p.rtt >= 0 ? " \u00b7 " + Geo.fmtRtt(p.rtt) + " ms"
               + (flagFastRtt ? Geo.rttNote(p.rtt, Geo.distanceKm(homeLat, homeLon, p.lat, p.lon)) : "") : "")
            + (p.life === "closed" ? " \u00b7 closed" : p.life === "connecting" ? " \u00b7 no answer yet" : "")
            + (p.fresh === "country" ? " \u00b7 NEW COUNTRY" : p.fresh === "place" ? " \u00b7 new place" : "");
    }
    property var labelSpecs: []
    readonly property string labelLook: [labels, showProcess, showLatency, proxied, flagFastRtt, labelSize, labelPlate, labelColor, width, height, peerStamp].join("/")
    onLabelLookChanged: rebuildLabels()
    property int peerStamp: 0                    // bumped by sync() so the specs follow the model
    function rebuildLabels() {
        var out = [];
        if (!labels) { labelSpecs = out; return; }
        for (var i = 0; i < peers.count; i++) {
            var p = peers.get(i);
            if (!p.show) continue;
            out.push({ x: px(p.lon), y: py(p.lat), gap: 8 * unit, side: p.side === "left" ? "left" : "right", text: labelText(p),
                       px: Math.round(labelSize * unit), color: p.fresh !== "" ? newColor : labelColor, plate: labelPlate,
                       alpha: p.life === "closed" ? 0.6 : 1 });
        }
        if (proxied && showLatency && haveHome && (cfg ? cfg.ShowProxyNote : false))
            out.push({ x: px(homeLon), y: py(homeLat), gap: 9 * unit, side: "below", text: "answered locally (VPN or proxy): latency hidden",
                       px: Math.round(labelSize * unit), color: labelColor, plate: labelPlate, alpha: 0.7 });
        labelSpecs = out;
    }

    Rectangle {                                           // home
        visible: overlay.haveHome
        x: overlay.px(overlay.homeLon) - width / 2
        y: overlay.py(overlay.homeLat) - height / 2
        width: 9 * overlay.unit; height: width; radius: width / 2
        color: "transparent"
        border.color: "#ffffff"; border.width: 1.5 * overlay.unit
    }
}
