/*
 * Maritime security incidents reported by UKMTO (United Kingdom Maritime Trade Operations, the Royal Navy's
 * point of contact for merchant shipping in the Indian Ocean, the Red Sea, the Gulf and the Strait of Hormuz):
 * every incident of the last days as a mark at the reported position - a diamond with an anchor, coloured by
 * what happened: red for a hijack, a kidnap, or an attack UKMTO itself flags red; orange for an attack or a
 * boarding; yellow for a suspicious approach, electronic interference or an advisory. An incident of the last
 * day is full size, a newly reported attack has rings running out from it; older ones shrink and fade over the window shown.
 * Labelled "Attack · tanker · Strait of Hormuz · 3 h". Crown copyright, via the Royal Navy's API.
 */
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support
import "geo.js" as Geo

Item {
    id: overlay
    property var cfg: null
    property string helper: ""
    property bool slow: false

    readonly property real unit: Math.max(1, Screen.width / 1920)
    readonly property real staleHours: cfg ? cfg.StaleHours : 6
    readonly property int days: cfg ? cfg.MaritimeDays : 14
    readonly property real freshHours: cfg ? cfg.MaritimeFreshHours : 24
    readonly property color severeInk: cfg ? cfg.MaritimeColor : "#ff3b3b"
    readonly property color attackInk: cfg ? cfg.MaritimeAttackColor : "#ff8c00"
    readonly property color infoInk: cfg ? cfg.MaritimeInfoColor : "#ffd23f"
    function inkOf(e) { return e.level >= 3 ? severeInk : e.level === 2 ? attackInk : infoInk }
    readonly property int labelMode: cfg ? cfg.MaritimeLabels : 1               // 0 none, 1 attacks and worse, 2 all
    readonly property int labelPx: Math.round((cfg ? cfg.MaritimeLabelSize : 10) * unit)
    readonly property bool labelPlate: cfg ? cfg.MaritimeLabelPlate : true
    readonly property color labelColor: cfg && !cfg.MaritimeTextFollows ? cfg.MaritimeTextColor : attackInk
    function labelInkOf(e) { return cfg && !cfg.MaritimeTextFollows ? labelColor : inkOf(e) }
    readonly property real markScale: (cfg ? cfg.MarkerScale : 100) / 100
    readonly property real mark: Math.round((cfg ? cfg.MaritimeLabelSize : 10) * 1.3 * unit * markScale)
    readonly property bool pulse: cfg ? cfg.MaritimePulse : true
    readonly property int pulseMs: cfg ? cfg.PulseDuration : 2800
    readonly property int periodMs: (cfg ? cfg.PulsePeriod : 5) * 1000
    property var incidents: []
    property string note: ""
    readonly property string hint: note
    property int fps: 30
    property real clock: 0
    property real nowSec: Date.now() / 1000
    Timer { interval: 60000; running: overlay.incidents.length > 0; repeat: true; onTriggered: overlay.nowSec = Date.now() / 1000 }

    function hoursOf(e) { return Math.max(0, nowSec - e.when) / 3600 }
    function fresh(e) { return hoursOf(e) < freshHours }
    // what pulses: an attack or worse younger than the shared 'Newly reported' window (Ageing and pulses), the same
    // clock the other layers use - not the 24 h 'fresh' window, which is for size. UKMTO lists an attack most days,
    // and a layer that always has something pulsing keeps the pulse clock, and so the whole screen's redraws, running
    // at full rate around the clock.
    readonly property real pulseNewHours: cfg ? cfg.PulseNewHours : 3
    function pulses(e) { return e.level >= 2 && hoursOf(e) < pulseNewHours }
    // 1 while fresh, then down to 0.35 at the end of the window: the mark shrinks and fades but stays legible
    function fade(e) { return 1 - 0.65 * Geo.ageMix(hoursOf(e), freshHours, Math.max(freshHours + 1, days * 24)) }
    readonly property var shown: incidents.filter(function (e) { return e.lat !== null && e.lon !== null && hoursOf(e) <= days * 24; })
    readonly property bool pulseWanted: pulse && fps > 0 && shown.some(pulses)

    function px(lon) { return (lon + 180) / 360 * width }
    function py(lat) { return (90 - lat) / 180 * height }
    function describe(e) {
        // "Attack · tanker · Strait of Hormuz · 3 h"; "Hijack · vessel taken · Somali Basin · 2 d"
        var parts = [e.type];
        if (e.pirate_control) parts.push("vessel taken");
        else if (e.vessel_type) parts.push(e.vessel_type);
        if (e.place) parts.push(e.place);
        parts.push(Geo.spanText(hoursOf(e)));
        return parts.join(" · ");
    }
    readonly property bool clusterLabels: cfg ? cfg.MaritimeClusterLabels : true
    function describeGroup(list) {
        // "11 attacks · tanker, tug · Strait of Hormuz · 5–11 d"; mixed types say "incidents"
        var types = {}, vessels = {}, places = {}, lo = Infinity, hi = 0;
        for (var i = 0; i < list.length; i++) {
            var e = list[i];
            types[e.type] = (types[e.type] || 0) + 1;
            if (e.vessel_type) vessels[e.vessel_type] = true;
            if (e.place) places[e.place] = (places[e.place] || 0) + 1;
            lo = Math.min(lo, hoursOf(e)); hi = Math.max(hi, hoursOf(e));
        }
        var tn = Object.keys(types), what = tn.length === 1 ? (tn[0] === "Attack" ? "attacks" : tn[0] === "Advisory" ? "advisories" : tn[0].toLowerCase() + " \u00d7") : "incidents";
        var place = Object.keys(places).sort(function (a, b) { return places[b] - places[a]; })[0] || "";
        return [list.length + " " + what, Object.keys(vessels).sort().join(", "), place, Geo.spanRange(lo, hi)].filter(function (t) { return t !== ""; }).join(" \u00b7 ");
    }
    readonly property var labelSpecs: (function () {
        if (labelMode === 0) return [];
        var list = shown.filter(function (e) { return labelMode === 2 || e.level >= 2; });     // newest first from the helper
        function specOf(e, text, bold) {
            return { x: px(e.lon), y: py(e.lat), gap: mark * 0.8, side: "right", text: text, px: labelPx, color: labelInkOf(e),
                     plate: labelPlate, bold: bold, alpha: 0.4 + 0.6 * fade(e) };
        }
        var specs = list.map(function (e) { return specOf(e, describe(e), e.level >= 3 && fresh(e)); });
        if (!clusterLabels) return specs;
        // a run of incidents in one strait: three or more within a few label heights become one label with the count
        var groups = Geo.clusterGroups(specs, 3 * labelPx), out = [];
        for (var g = 0; g < groups.length; g++) {
            if (groups[g].length >= 3) {
                var members = groups[g].map(function (i) { return list[i]; }), lead = members[0];
                out.push(specOf(lead, describeGroup(members), members.some(function (e) { return e.level >= 3 && fresh(e); })));
            } else for (var i = 0; i < groups[g].length; i++) out.push(specs[groups[g][i]]);
        }
        return out;
    })()

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                var r = JSON.parse(data.stdout);
                overlay.incidents = r.incidents || [];
                overlay.note = r.note || "";
                overlay.nowSec = Date.now() / 1000;
                console.warn("livemap maritime:", overlay.incidents.length, "incidents", overlay.note);
            } catch (e) { overlay.note = "Maritime incidents: the helper did not answer properly"; }
        }
    }
    function ask() { exec.connectSource("python3 '" + helper + "' maritime --stale " + staleHours + " --days " + days + " # " + Date.now()) }
    Timer {                                       // UKMTO publishes within hours of a report: every 15 min (30 when saving)
        interval: (overlay.slow ? 30 : 15) * 60000
        running: overlay.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: overlay.ask()
    }
    onDaysChanged: if (helper !== "") ask()

    Repeater {
        model: overlay.shown
        Item {
            id: ev
            required property var modelData
            required property int index
            x: overlay.px(modelData.lon)
            y: overlay.py(modelData.lat)
            readonly property color tone: overlay.inkOf(modelData)
            readonly property real k: overlay.fade(modelData)
            readonly property bool live: overlay.fresh(modelData)
            readonly property real r: overlay.mark * (0.6 + 0.4 * k) * (modelData.level >= 2 ? 1 : 0.8)
            Repeater {                            // rings running out from a newly reported attack
                model: overlay.pulses(modelData) && overlay.pulse && overlay.fps > 0 ? 2 : 0
                Rectangle {
                    required property int index
                    readonly property real s: Geo.pulse(overlay.clock + index * overlay.pulseMs / 2, ev.index, overlay.pulseMs, overlay.periodMs)
                    visible: s >= 0
                    anchors.centerIn: parent
                    width: ev.r * (1.5 + 4 * Math.max(0, s)); height: width; radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(ev.tone.r, ev.tone.g, ev.tone.b, (1 - Math.max(0, s)) * 0.8)
                    border.width: Math.max(1, 1.5 * overlay.unit)
                }
            }
            Rectangle {                           // the mark: a diamond, filled by the level's colour, outlined dark so it reads on water
                anchors.centerIn: parent
                width: ev.r * 1.5; height: width; rotation: 45
                radius: Math.max(1, ev.r * 0.18)
                color: Qt.rgba(ev.tone.r, ev.tone.g, ev.tone.b, (ev.live ? 0.85 : 0.55) * ev.k)
                border.color: Qt.rgba(0, 0, 0, 0.7 * ev.k)
                border.width: Math.max(1, 1.2 * overlay.unit)
            }
            Text {                                // the anchor over the diamond
                anchors.centerIn: parent
                text: "⚓"
                color: Qt.rgba(0, 0, 0, 0.9 * ev.k)
                font.pixelSize: Math.round(ev.r * 1.15)
                font.bold: true
            }
        }
    }
}
