/*
 * All event labels, drawn last so nothing can cover them: not a storm cone, not an arc, not another
 * layer's ring. Each layer only *describes* its labels (see Geo.placeLabels for the spec); this item
 * places them together, so labels from different layers no longer print over each other either, and
 * flips or nudges them to stay on the screen.
 *
 * Priority: network (yours), satellites, launches, storms, wildfires, tsunami bulletins, floods, air raid alerts, maritime incidents, earthquakes, volcanoes - the first ones get their space first.
 * Country names are not here on purpose: they are part of the map and belong underneath everything.
 */
import QtQuick
import QtQuick.Window
import "geo.js" as Geo

Item {
    id: pass
    property var cfg: null
    property var netSpecs: []
    property var stormSpecs: []
    property var fireSpecs: []
    property var floodSpecs: []
    property var tsunamiSpecs: []
    property var alertSpecs: []
    property var maritimeSpecs: []
    property var satSpecs: []
    property var shifts: ({})                            // per spec key: how far it has moved since its layout position
    function shiftX(spec) { var sh = spec.key ? shifts[spec.key] : null; return sh ? sh.dx : 0 }
    function shiftY(spec) { var sh = spec.key ? shifts[spec.key] : null; return sh ? sh.dy : 0 }
    property var launchSpecs: []
    property var quakeSpecs: []
    property var volcanoSpecs: []
    property var infraSpecs: []                           // oil and gas infrastructure, last: still names, lowest priority
    property rect view: Qt.rect(0, 0, width, height)      // the visible screen, in this item's coordinates

    readonly property real unit: Math.max(1, Screen.width / 1920)   // screen pixels: a zoomed-in frame keeps marks the same size
    readonly property color plateColor: cfg ? cfg.PlateColor : "#000510"
    readonly property real plateOpacity: (cfg ? cfg.PlateOpacity : 60) / 100
    readonly property real textOpacity: (cfg ? cfg.TextOpacity : 100) / 100
    readonly property int lines: cfg ? cfg.LabelLines : 0                 // 0 one line, 1 name above details, 2 automatic

    // Per-layer label style (Label style row of each section): bold, capitals, letter spacing, opacity, outline.
    function style(prefix) {
        return cfg ? { bold: !!cfg[prefix + "LabelBold"], caps: !!cfg[prefix + "LabelCaps"],
                       spacing: (cfg[prefix + "LabelSpacing"] === undefined ? 100 : cfg[prefix + "LabelSpacing"]) / 100,
                       alpha: (cfg[prefix + "LabelOpacity"] === undefined ? 100 : cfg[prefix + "LabelOpacity"]) / 100,
                       halo: (cfg[prefix + "LabelHalo"] === undefined ? 100 : cfg[prefix + "LabelHalo"]) / 100 }
                   : { bold: false, caps: false, spacing: 1, alpha: 1, halo: 1 };
    }
    property var styles: ({ net: style("Net"), sat: style("Sat"), launch: style("Launch"), storm: style("Storm"),
                            fire: style("Fire"), flood: style("Flood"), tsunami: style("Tsunami"), alert: style("AirAlert"), maritime: style("Maritime"), quake: style("Quake"), volcano: style("Volcano"), infra: style("Infra") })
    // Dotted reads, so QML re-evaluates this when any of the 35 settings changes; the styles are rebuilt from it.
    readonly property string styleKey: !cfg ? "" : [cfg.NetLabelBold, cfg.NetLabelCaps, cfg.NetLabelSpacing, cfg.NetLabelOpacity, cfg.NetLabelHalo, cfg.SatLabelBold, cfg.SatLabelCaps, cfg.SatLabelSpacing, cfg.SatLabelOpacity, cfg.SatLabelHalo, cfg.LaunchLabelBold, cfg.LaunchLabelCaps, cfg.LaunchLabelSpacing, cfg.LaunchLabelOpacity, cfg.LaunchLabelHalo, cfg.StormLabelBold, cfg.StormLabelCaps, cfg.StormLabelSpacing, cfg.StormLabelOpacity, cfg.StormLabelHalo, cfg.FireLabelBold, cfg.FireLabelCaps, cfg.FireLabelSpacing, cfg.FireLabelOpacity, cfg.FireLabelHalo, cfg.FloodLabelBold, cfg.FloodLabelCaps, cfg.FloodLabelSpacing, cfg.FloodLabelOpacity, cfg.FloodLabelHalo, cfg.TsunamiLabelBold, cfg.TsunamiLabelCaps, cfg.TsunamiLabelSpacing, cfg.TsunamiLabelOpacity, cfg.TsunamiLabelHalo, cfg.AirAlertLabelBold, cfg.AirAlertLabelCaps, cfg.AirAlertLabelSpacing, cfg.AirAlertLabelOpacity, cfg.AirAlertLabelHalo, cfg.MaritimeLabelBold, cfg.MaritimeLabelCaps, cfg.MaritimeLabelSpacing, cfg.MaritimeLabelOpacity, cfg.MaritimeLabelHalo, cfg.QuakeLabelBold, cfg.QuakeLabelCaps, cfg.QuakeLabelSpacing, cfg.QuakeLabelOpacity, cfg.QuakeLabelHalo, cfg.VolcanoLabelBold, cfg.VolcanoLabelCaps, cfg.VolcanoLabelSpacing, cfg.VolcanoLabelOpacity, cfg.VolcanoLabelHalo, cfg.InfraLabelBold, cfg.InfraLabelCaps, cfg.InfraLabelSpacing, cfg.InfraLabelOpacity, cfg.InfraLabelHalo].join(",")
    onStyleKeyChanged: { styles = { net: style("Net"), sat: style("Sat"), launch: style("Launch"), storm: style("Storm"),
                                    fire: style("Fire"), flood: style("Flood"), tsunami: style("Tsunami"), alert: style("AirAlert"), maritime: style("Maritime"), quake: style("Quake"), volcano: style("Volcano"), infra: style("Infra") }; relayout(); }
    function tag(list, kind) { return list.map(function (s) { var t = Object.assign({}, s); t.kind = kind; return t; }); }
    readonly property var specs: [].concat(tag(netSpecs, "net"), tag(satSpecs, "sat"), tag(launchSpecs, "launch"), tag(stormSpecs, "storm"),
                                           tag(fireSpecs, "fire"), tag(tsunamiSpecs, "tsunami"), tag(floodSpecs, "flood"), tag(alertSpecs, "alert"), tag(maritimeSpecs, "maritime"), tag(quakeSpecs, "quake"), tag(volcanoSpecs, "volcano"), tag(infraSpecs, "infra"))

    // Real text sizes, so the layout uses the width each label will actually have. Done in a handler,
    // not a binding: setting the meter's text inside a binding would re-trigger that same binding.
    TextMetrics { id: meter }
    property var places: []
    // Measuring text is the expensive part of a relayout, and most labels do not change between two
    // relayouts (a satellite moved, a quake aged), so sizes are remembered per text, size and weight.
    property var sizeCache: ({})
    property int sizeCacheCount: 0
    function measure(text, px, bold, caps, spacing) {   // TextMetrics knows one line; a two-line label is measured line by line
        var key = px + (bold ? "b" : "n") + (caps ? "C" + spacing : "") + text, hit = sizeCache[key];
        if (hit) return hit;
        meter.font.capitalization = caps ? Font.AllUppercase : Font.MixedCase;
        meter.font.letterSpacing = caps ? unit * spacing : 0;
        var parts = text.split("\n"), w = 0, h = 0;
        for (var i = 0; i < parts.length; i++) {
            meter.text = parts[i];
            w = Math.max(w, meter.width); h += meter.height;
        }
        if (sizeCacheCount > 4000) { sizeCache = {}; sizeCacheCount = 0; }
        sizeCache[key] = { w: w, h: h }; sizeCacheCount++;
        return sizeCache[key];
    }
    function relayout() {
        var sizes = [], list = [];
        for (var i = 0; i < specs.length; i++) {
            var s = specs[i];
            if (lines > 0 && !s.text2) { s = Object.assign({}, s); s.text2 = Geo.twoLine(s.text); }
            list.push(s);
            var st = styles[s.kind] || styles.quake, bold = !!s.bold || st.bold;
            meter.font.pixelSize = s.px;
            meter.font.bold = bold;
            var one = measure(s.text, s.px, bold, st.caps, st.spacing), two = s.text2 ? measure(s.text2, s.px, bold, st.caps, st.spacing) : one;
            sizes.push({ w: one.w, h: one.h, w2: two.w, h2: two.h });
        }
        places = Geo.placeLabels(list, sizes, { x: view.x, y: view.y, w: view.width, h: view.height }, unit, lines);
    }
    onSpecsChanged: relayout()
    onLinesChanged: relayout()
    onViewChanged: relayout()
    onUnitChanged: relayout()
    Component.onCompleted: relayout()

    Repeater {                                            // leader lines, under the labels
        model: pass.specs
        Rectangle {
            required property var modelData
            required property int index
            readonly property var at: pass.places[index] || ({ show: false, leader: false })
            visible: at.show && at.leader
            x: modelData.x + pass.shiftX(modelData); y: modelData.y + pass.shiftY(modelData)
            width: Math.sqrt((at.lx - modelData.x) * (at.lx - modelData.x) + (at.ly - modelData.y) * (at.ly - modelData.y))
            height: Math.max(1, 0.8 * pass.unit)
            transformOrigin: Item.TopLeft
            rotation: Math.atan2(at.ly - modelData.y, at.lx - modelData.x) * 180 / Math.PI
            color: Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.55 * pass.textOpacity)
        }
    }
    Repeater {
        model: pass.specs
        MapLabel {
            required property var modelData
            required property int index
            readonly property var at: pass.places[index] || ({ show: false, x: 0, y: 0, text: "" })
            visible: at.show
            x: at.x + pass.shiftX(modelData)
            y: at.y + pass.shiftY(modelData)
            readonly property var st: pass.styles[modelData.kind] || pass.styles.quake
            text: at.text || modelData.text
            textColor: modelData.color
            textOpacity: pass.textOpacity * st.alpha * (modelData.alpha === undefined ? 1 : modelData.alpha)
            plate: modelData.plate
            plateColor: pass.plateColor
            plateOpacity: pass.plateOpacity
            px: modelData.px
            bold: !!modelData.bold || st.bold
            caps: st.caps
            haloScale: st.halo
            letterScale: st.spacing
            unit: pass.unit
        }
    }
}
