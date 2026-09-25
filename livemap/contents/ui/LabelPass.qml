/*
 * All event labels, drawn last so nothing can cover them: not a storm cone, not an arc, not another
 * layer's ring. Each layer only *describes* its labels (see Geo.placeLabels for the spec); this item
 * places them together, so labels from different layers no longer print over each other either, and
 * flips or nudges them to stay on the screen.
 *
 * Priority: network (yours), satellites, launches, storms, wildfires, earthquakes, volcanoes - the first ones get their space first.
 * Country names are not here on purpose: they are part of the map and belong underneath everything.
 */
import QtQuick
import "geo.js" as Geo

Item {
    id: pass
    property var cfg: null
    property var netSpecs: []
    property var stormSpecs: []
    property var fireSpecs: []
    property var satSpecs: []
    property var shifts: ({})                            // per spec key: how far it has moved since its layout position
    function shiftX(spec) { var sh = spec.key ? shifts[spec.key] : null; return sh ? sh.dx : 0 }
    function shiftY(spec) { var sh = spec.key ? shifts[spec.key] : null; return sh ? sh.dy : 0 }
    property var launchSpecs: []
    property var quakeSpecs: []
    property var volcanoSpecs: []
    property rect view: Qt.rect(0, 0, width, height)      // the visible screen, in this item's coordinates

    readonly property real unit: Math.max(1, width / 1920)
    readonly property color plateColor: cfg ? cfg.PlateColor : "#000510"
    readonly property real plateOpacity: (cfg ? cfg.PlateOpacity : 60) / 100
    readonly property real textOpacity: (cfg ? cfg.TextOpacity : 100) / 100
    readonly property int lines: cfg ? cfg.LabelLines : 0                 // 0 one line, 1 name above details, 2 automatic

    readonly property var specs: [].concat(netSpecs, satSpecs, launchSpecs, stormSpecs, fireSpecs, quakeSpecs, volcanoSpecs)

    // Real text sizes, so the layout uses the width each label will actually have. Done in a handler,
    // not a binding: setting the meter's text inside a binding would re-trigger that same binding.
    TextMetrics { id: meter }
    property var places: []
    // Measuring text is the expensive part of a relayout, and most labels do not change between two
    // relayouts (a satellite moved, a quake aged), so sizes are remembered per text, size and weight.
    property var sizeCache: ({})
    property int sizeCacheCount: 0
    function measure(text, px, bold) {             // TextMetrics knows one line; a two-line label is measured line by line
        var key = px + (bold ? "b" : "n") + text, hit = sizeCache[key];
        if (hit) return hit;
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
            meter.font.pixelSize = s.px;
            meter.font.bold = !!s.bold;
            var one = measure(s.text, s.px, !!s.bold), two = s.text2 ? measure(s.text2, s.px, !!s.bold) : one;
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
            text: at.text || modelData.text
            textColor: modelData.color
            textOpacity: pass.textOpacity * (modelData.alpha === undefined ? 1 : modelData.alpha)
            plate: modelData.plate
            plateColor: pass.plateColor
            plateOpacity: pass.plateOpacity
            px: modelData.px
            bold: !!modelData.bold
            unit: pass.unit
        }
    }
}
