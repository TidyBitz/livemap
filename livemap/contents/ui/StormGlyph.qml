/*
 * The tropical cyclone symbol, as on NHC charts: a core with two trailing arms. The core is open for a
 * depression or tropical storm and solid for a hurricane; a major hurricane gets heavier arms. Southern
 * hemisphere storms spin the other way, so the symbol is mirrored there.
 */
import QtQuick

Canvas {
    id: glyph
    property real r: 6                      // core radius; the whole symbol is about 4.4 r wide
    property color color: "#ffb000"
    property int level: 1                   // 0 depression, 1 tropical storm, 2 hurricane, 3 major hurricane
    property bool south: false
    width: Math.ceil(r * 5.4); height: width
    antialiasing: true
    onRChanged: requestPaint()
    onColorChanged: requestPaint()
    onLevelChanged: requestPaint()
    onSouthChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d"), c = width / 2, dir = south ? -1 : 1, r = glyph.r;
        ctx.clearRect(0, 0, width, height);
        ctx.fillStyle = color;
        var heavy = level >= 3, sweep = 2.7, n = 24;
        // two tails, half a turn apart: each leaves the core tangentially, spirals outwards and tapers
        function rc(t) { return r * (1.1 + 1.25 * t) }                                   // centre line radius
        function w(t) { return r * ((heavy ? 0.95 : 0.7) * Math.pow(1 - t, 0.8) + 0.06) } // thickness
        for (var base = 0; base < 2; base++) {
            var a0 = base * Math.PI;
            ctx.beginPath();
            for (var i = 0; i <= n; i++) {
                var t = i / n, a = a0 + dir * t * sweep, ro = rc(t) + w(t) / 2;
                var x = c + Math.cos(a) * ro, y = c + Math.sin(a) * ro;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            for (var j = n; j >= 0; j--) {
                var t2 = j / n, a2 = a0 + dir * t2 * sweep, ri = rc(t2) - w(t2) / 2;
                ctx.lineTo(c + Math.cos(a2) * ri, c + Math.sin(a2) * ri);
            }
            ctx.closePath();
            ctx.fill();
        }
        ctx.beginPath();
        ctx.arc(c, c, r * 1.05, 0, 2 * Math.PI);
        ctx.fill();
        if (level < 2) {                                                              // open centre below hurricane strength
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();
            ctx.arc(c, c, r * 0.6, 0, 2 * Math.PI);
            ctx.fill();
            ctx.globalCompositeOperation = "source-over";
        }
    }
}
