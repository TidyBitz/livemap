/*
 * A small rocket, drawn rather than taken from an emoji font (which may not be installed): a pointed body,
 * two fins and a flame at the base.
 */
import QtQuick

Canvas {
    id: glyph
    property real size: 14                  // height
    property color color: "#ffffff"
    property real alpha: 1
    width: Math.ceil(size * 0.7); height: Math.ceil(size)
    antialiasing: true
    onSizeChanged: requestPaint()
    onColorChanged: requestPaint()
    onAlphaChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d"), w = width, h = height, cx = w / 2;
        ctx.clearRect(0, 0, w, h);
        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, alpha);
        ctx.beginPath();                                                  // body
        ctx.moveTo(cx, 0);
        ctx.bezierCurveTo(cx + w * 0.32, h * 0.25, cx + w * 0.3, h * 0.55, cx + w * 0.22, h * 0.78);
        ctx.lineTo(cx - w * 0.22, h * 0.78);
        ctx.bezierCurveTo(cx - w * 0.3, h * 0.55, cx - w * 0.32, h * 0.25, cx, 0);
        ctx.closePath(); ctx.fill();
        ctx.beginPath();                                                  // fins
        ctx.moveTo(cx - w * 0.22, h * 0.55); ctx.lineTo(cx - w * 0.5, h * 0.85); ctx.lineTo(cx - w * 0.2, h * 0.78); ctx.closePath(); ctx.fill();
        ctx.beginPath();
        ctx.moveTo(cx + w * 0.22, h * 0.55); ctx.lineTo(cx + w * 0.5, h * 0.85); ctx.lineTo(cx + w * 0.2, h * 0.78); ctx.closePath(); ctx.fill();
        ctx.fillStyle = Qt.rgba(1, 0.6, 0.15, alpha);                      // flame
        ctx.beginPath();
        ctx.moveTo(cx - w * 0.14, h * 0.8); ctx.lineTo(cx, h); ctx.lineTo(cx + w * 0.14, h * 0.8); ctx.closePath(); ctx.fill();
        ctx.fillStyle = Qt.rgba(0.1, 0.15, 0.25, alpha);                   // porthole
        ctx.beginPath(); ctx.arc(cx, h * 0.36, w * 0.1, 0, 2 * Math.PI); ctx.fill();
    }
}
