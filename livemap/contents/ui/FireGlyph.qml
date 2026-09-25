/*
 * A flame, so a wildfire cannot be mistaken for a quake ring, a storm symbol or a volcano triangle.
 * Outer flame in the layer's colour, a paler tongue inside.
 */
import QtQuick

Canvas {
    id: glyph
    property real size: 12                  // height of the flame
    property color color: "#ff5a1f"
    property real alpha: 1
    width: Math.ceil(size * 0.9); height: Math.ceil(size)
    antialiasing: true
    onSizeChanged: requestPaint()
    onColorChanged: requestPaint()
    onAlphaChanged: requestPaint()
    function flame(ctx, w, h, cx, base) {
        ctx.beginPath();
        ctx.moveTo(cx, base - h);                                      // tip
        ctx.bezierCurveTo(cx + w * 0.05, base - h * 0.55, cx + w * 0.62, base - h * 0.55, cx + w * 0.5, base - h * 0.22);
        ctx.bezierCurveTo(cx + w * 0.42, base - h * 0.05, cx + w * 0.35, base, cx, base);   // right side down to the base
        ctx.bezierCurveTo(cx - w * 0.6, base, cx - w * 0.55, base - h * 0.45, cx - w * 0.3, base - h * 0.5);
        ctx.bezierCurveTo(cx - w * 0.2, base - h * 0.35, cx - w * 0.1, base - h * 0.75, cx, base - h);          // left side back up
        ctx.closePath();
        ctx.fill();
    }
    onPaint: {
        var ctx = getContext("2d"), w = width, h = height;
        ctx.clearRect(0, 0, w, h);
        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, alpha);
        flame(ctx, w, h, w / 2, h);
        ctx.fillStyle = Qt.rgba(1, 0.93, 0.6, 0.85 * alpha);
        flame(ctx, w * 0.5, h * 0.5, w / 2, h * 0.98);
    }
}
