/*
 * Three waves, so a flood cannot be mistaken for a storm symbol, a quake ring or a flame: the layer's colour,
 * a short crest line on top of the middle wave.
 */
import QtQuick

Canvas {
    id: glyph
    property real size: 12                  // width of the mark
    property color color: "#4aa3ff"
    property real alpha: 1
    property real lineWidth: 1.5
    width: Math.ceil(size); height: Math.ceil(size * 0.8)
    antialiasing: true
    onSizeChanged: requestPaint()
    onColorChanged: requestPaint()
    onAlphaChanged: requestPaint()
    onLineWidthChanged: requestPaint()
    function wave(ctx, y, w, amp) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.bezierCurveTo(w * 0.17, y - amp, w * 0.33, y - amp, w * 0.5, y);
        ctx.bezierCurveTo(w * 0.67, y + amp, w * 0.83, y + amp, w, y);
        ctx.stroke();
    }
    onPaint: {
        var ctx = getContext("2d"), w = width, h = height;
        ctx.clearRect(0, 0, w, h);
        ctx.lineWidth = lineWidth;
        ctx.lineCap = "round";
        ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, alpha);
        var amp = h * 0.16;
        wave(ctx, h * 0.3, w, amp);
        wave(ctx, h * 0.55, w, amp);
        wave(ctx, h * 0.8, w, amp);
    }
}
