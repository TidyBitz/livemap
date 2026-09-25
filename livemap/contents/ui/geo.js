.pragma library
// Pure maths shared by every layer. No QML types in here, so it can be
// tested outside Plasma:  tail -n +2 geo.js > /tmp/g.js && node -e "..."

var RAD = Math.PI / 180;

// Sub-solar point {lat, lon} in degrees (NOAA low-precision series, ~0.2 deg).
function sun(date) {
    var start = Date.UTC(date.getUTCFullYear(), 0, 1);
    var doy = Math.floor((date.getTime() - start) / 86400000) + 1;
    var hours = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600;
    var g = 2 * Math.PI / 365 * (doy - 1 + (hours - 12) / 24);
    var eot = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
                        - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
    var decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g)
             - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g)
             - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
    var lon = -((hours * 60 + eot) / 4 - 180);
    lon = ((lon + 180) % 360 + 360) % 360 - 180;
    return { lat: decl / RAD, lon: lon };
}

// Set every pixel of an RGBA byte array to one colour (alpha untouched).
function tint(data, count, r, g, b) {
    for (var i = 0; i < count * 4; i += 4) { data[i] = r; data[i + 1] = g; data[i + 2] = b; }
}

// Fill the alpha channel of an RGBA byte array (w*h*4) with "night-ness":
// 0 where the sun is 3 deg up, maxAlpha where it is 12 deg below the horizon,
// smoothstepped in between.
function nightAlpha(data, w, h, sunLat, sunLon, maxAlpha) {
    var ss = Math.sin(sunLat * RAD), cs = Math.cos(sunLat * RAD);
    var hi = Math.sin(3 * RAD), lo = Math.sin(-12 * RAD), span = hi - lo;
    var cosH = new Array(w);
    for (var x = 0; x < w; x++)
        cosH[x] = Math.cos(((x + 0.5) / w * 360 - 180 - sunLon) * RAD);
    for (var y = 0; y < h; y++) {
        var lat = (90 - (y + 0.5) / h * 180) * RAD;
        var a = Math.sin(lat) * ss, b = Math.cos(lat) * cs, row = y * w * 4 + 3;
        for (x = 0; x < w; x++) {
            var k = (hi - (a + b * cosH[x])) / span;
            k = k <= 0 ? 0 : k >= 1 ? 1 : k * k * (3 - 2 * k);
            data[row + x * 4] = Math.round(k * maxAlpha);
        }
    }
}

// Paint "how dark is it here" into a Canvas 2D context using only fillRect and linear
// gradients (the most ordinary Canvas calls there are): `cols` vertical strips, each a
// gradient sampled every 3 deg of latitude. Strip edges are whole pixels, so neighbours
// never overlap or leave seams whatever the canvas width. Daylight strips are left
// untouched. Returns how many strips needed a gradient (for the diagnostics line).
function paintNight(ctx, w, h, sunLat, sunLon, maxA, rgb, twilight, cols) {
    var M = 60, ss = Math.sin(sunLat * RAD), cs = Math.cos(sunLat * RAD);
    var fade = Math.max(2, twilight || 15);        // degrees of sun elevation the dusk band spans
    var hi = Math.sin(3 * RAD), lo = Math.sin((3 - fade) * RAD), span = hi - lo;
    var sl = [], cl = [], j, gradients = 0;
    cols = Math.min(w, cols || w);
    for (j = 0; j <= M; j++) { var lat = (90 - j / M * 180) * RAD; sl.push(Math.sin(lat)); cl.push(Math.cos(lat)); }
    // Additive blending, because the strips are butted against each other. On a screen with fractional scaling a
    // strip edge falls inside a device pixel; the two neighbours each get part of that pixel, and with ordinary
    // alpha blending two partial coats come out lighter than one full coat - regular vertical stripes across the
    // night side. Added together, the parts sum to exactly one coat at any scale factor, antialiased or not.
    // (The canvas is cleared first and no pixel is covered by more than two strips, so nothing can over-add.)
    var before = ctx.globalCompositeOperation;
    ctx.globalCompositeOperation = "lighter";
    function css(k) { return "rgba(" + rgb + "," + (k * maxA).toFixed(3) + ")"; }
    for (var i = 0; i < cols; i++) {
        var x0 = Math.round(i * w / cols), x1 = Math.round((i + 1) * w / cols);
        var cH = Math.cos(((i + 0.5) / cols * 360 - 180 - sunLon) * RAD), ks = [], mn = 1, mx = 0;
        for (j = 0; j <= M; j++) {
            var k = (hi - (sl[j] * ss + cl[j] * cs * cH)) / span;
            k = k <= 0 ? 0 : k >= 1 ? 1 : k * k * (3 - 2 * k);
            ks.push(k); if (k < mn) mn = k; if (k > mx) mx = k;
        }
        if (mx < 0.002 || x1 <= x0) continue;                      // broad daylight top to bottom
        if (mx - mn < 0.004) ctx.fillStyle = css(mx);              // same darkness top to bottom
        else {
            var g = ctx.createLinearGradient(0, 0, 0, h);
            for (j = 0; j <= M; j++)                               // skip stops inside flat runs
                if (j === 0 || j === M || ks[j - 1] !== ks[j] || ks[j + 1] !== ks[j]) g.addColorStop(j / M, css(ks[j]));
            ctx.fillStyle = g; gradients++;
        }
        ctx.fillRect(x0, 0, x1 - x0, h);
    }
    ctx.globalCompositeOperation = before;
    return gradients;
}

// NASA's monthly composites represent mid-month, so blend between neighbours:
// returns {a, b} as month numbers 1..12 and mix 0..1 (0 = all a, 1 = all b).
function monthBlend(date) {
    var m = date.getMonth(), y = date.getFullYear();
    var days = new Date(y, m + 1, 0).getDate();
    var p = m + (date.getDate() - 1) / days - 0.5;
    var a = Math.floor(p);
    return { a: ((a % 12) + 12) % 12 + 1, b: (((a + 1) % 12) + 12) % 12 + 1, mix: p - a };
}

// Great-circle path between two points as segments of {lat, lon}; the path is
// split where it crosses the antimeridian so it can be drawn on a flat map.
function arc(lat1, lon1, lat2, lon2, n) {
    var p1 = lat1 * RAD, l1 = lon1 * RAD, p2 = lat2 * RAD, l2 = lon2 * RAD;
    var sa = Math.sin((p2 - p1) / 2), sb = Math.sin((l2 - l1) / 2);
    var d = 2 * Math.asin(Math.min(1, Math.sqrt(sa * sa + Math.cos(p1) * Math.cos(p2) * sb * sb)));
    if (d < 1e-6 || Math.abs(d - Math.PI) < 1e-6)
        return [[{ lat: lat1, lon: lon1 }, { lat: lat2, lon: lon2 }]];
    var segs = [[]], prev = null, sd = Math.sin(d);
    for (var i = 0; i <= n; i++) {
        var f = i / n, A = Math.sin((1 - f) * d) / sd, B = Math.sin(f * d) / sd;
        var x = A * Math.cos(p1) * Math.cos(l1) + B * Math.cos(p2) * Math.cos(l2);
        var y = A * Math.cos(p1) * Math.sin(l1) + B * Math.cos(p2) * Math.sin(l2);
        var z = A * Math.sin(p1) + B * Math.sin(p2);
        var pt = { lat: Math.atan2(z, Math.sqrt(x * x + y * y)) / RAD, lon: Math.atan2(y, x) / RAD };
        if (prev && Math.abs(pt.lon - prev.lon) > 180) {
            var edge = prev.lon > 0 ? 180 : -180;
            var t = (edge - prev.lon) / (pt.lon + (edge > 0 ? 360 : -360) - prev.lon);
            var latc = prev.lat + t * (pt.lat - prev.lat);
            segs[segs.length - 1].push({ lat: latc, lon: edge });
            segs.push([{ lat: latc, lon: -edge }]);
        }
        segs[segs.length - 1].push(pt);
        prev = pt;
    }
    return segs.filter(function (s) { return s.length > 1; });
}

// Great-circle distance in km (used to pace the animation).
function distanceKm(lat1, lon1, lat2, lon2) {
    var sa = Math.sin((lat2 - lat1) * RAD / 2), sb = Math.sin((lon2 - lon1) * RAD / 2);
    return 12742 * Math.asin(Math.min(1, Math.sqrt(sa * sa
        + Math.cos(lat1 * RAD) * Math.cos(lat2 * RAD) * sb * sb)));
}

// ---- labels -------------------------------------------------------------------
// Which labels fit? `boxes` is in priority order, each {x, y, w, h} in pixels or null (= not wanted).
// A label is kept unless it overlaps one that was kept before it. Returns an array of booleans.
function declutter(boxes, pad) {
    var kept = [], flags = [];
    pad = pad || 0;
    for (var i = 0; i < boxes.length; i++) {
        var b = boxes[i], ok = b !== null && b !== undefined;
        for (var j = 0; ok && j < kept.length; j++) {
            var k = kept[j];
            if (b.x < k.x + k.w + pad && k.x < b.x + b.w + pad && b.y < k.y + k.h + pad && k.y < b.y + b.h + pad) ok = false;
        }
        flags.push(ok);
        if (ok) kept.push(b);
    }
    return flags;
}

// "57 km SSE of Hachijo-jima, Japan" -> "Hachijo-jima, Japan"; but "south of Africa" or "southeast of the
// Loyalty Islands" (USGS's names for open-ocean regions) stay as they are: that quake really is out at sea.
function quakePlace(place) {
    return place.replace(/^\s*\d+(\.\d+)?\s*km\s+[NSEW]{1,3}\s+of\s+/i, "");
}

// Distances in the chosen unit: 0 km, 1 miles, 2 nautical miles.
function distText(km, units) {
    return units === 1 ? Math.round(km * 0.621371) + " mi" : units === 2 ? Math.round(km * 0.539957) + " nmi" : Math.round(km) + " km";
}
// Areas: hectares, or acres when the distance unit is miles.
function areaText(ha, units) {
    var v = units === 1 ? ha * 2.47105 : ha, u = units === 1 ? " ac" : " ha";
    return v >= 100000 ? Math.round(v / 1000) + "k" + u : v >= 10000 ? (v / 1000).toFixed(1) + "k" + u : Math.round(v) + u;
}

// A duration without "ago": "35 min", "7 h", "26 d".
function spanText(hours) {
    if (hours < 1) return Math.max(1, Math.round(hours * 60)) + " min";
    if (hours < 48) return Math.round(hours) + " h";
    if (hours < 24 * 730) return Math.round(hours / 24) + " d";
    return (hours / (24 * 365.25)).toFixed(hours < 24 * 3652 ? 1 : 0) + " y";
}

function ageText(hours) {
    if (hours < 1) return Math.max(1, Math.round(hours * 60)) + " min ago";
    if (hours < 48) return Math.round(hours) + " h ago";
    return Math.round(hours / 24) + " d ago";
}

// A round trip cannot beat light in glass fibre: about 1 ms per 100 km of distance, there and back.
// A measurement far below that means the TCP connection does not really end where the address is
// registered: something on this machine or network answers for it (VPN, proxy, security software),
// or the address is served from a location much nearer than the GeoIP database says.
function rttNote(rtt, km) {
    if (rtt < 0 || rtt >= km / 100 * 0.8) return "";      // 20 % slack for GeoIP being a few hundred km off
    return rtt < 2 ? " (answered locally)" : " (nearer than mapped)";
}

function fmtRtt(rtt) { return rtt < 0.05 ? "<0.1" : rtt < 10 ? rtt.toFixed(1) : String(Math.round(rtt)); }

// With a local proxy or VPN in the path (Portmaster SPN, for example) connections are answered on this
// machine, and no round trip says anything about the far end any more - including the plausible-looking
// ones, which may run through the same tunnel. The evidence is unmistakable: under 2 ms to a host more
// than 300 km away. Two such live connections are enough. peers: [{lat, lon, rtt, life}]
function mostlyProxied(peers, homeLat, homeLon) {
    var local = 0;
    for (var i = 0; i < peers.length; i++) {
        var p = peers[i];
        if (p.life === "live" && p.rtt !== undefined && p.rtt >= 0 && p.rtt < 2
                && distanceKm(homeLat, homeLon, p.lat, p.lon) > 300) local++;
    }
    return local >= 2;
}

// ---- one label pass for the whole map -------------------------------------------------
// Every layer describes the labels it wants as specs: { x, y (map pixels of the thing labelled), gap
// (how far from it), side ("right", "left" or "below" preferred), text, px (font size), ... }, in priority
// order (network first, then storms, quakes, volcanoes). `sizes` holds the measured {w, h} of each text.
// A label goes on its preferred side; if that would leave the screen or cover a label placed before it,
// the other sides are tried (right, left, below, above); at the top and bottom of the screen it is nudged
// back on; if nothing fits, or the thing it labels is off-screen, it is dropped. Returns [{show, x, y,
// leader}] aligned with specs; `leader` is true when the label ended up away from its mark and a thin
// line should join the two. `view` is the visible screen in map pixels {x, y, w, h}.
// `lines`: 0 = every label on one line, 1 = always name above details (spec.text2, "name\ndetails"),
// 2 = automatic: one line where it fits, the two-line form where the wide one would collide or leave the screen.
// sizes[i] = { w, h } of the one-line text and { w2, h2 } of the two-line text.
function placeLabels(specs, sizes, view, unit, lines) {
    var kept = [], out = [], pad = 2 * unit;
    function clash(b) {
        for (var j = 0; j < kept.length; j++) {
            var k = kept[j];
            if (b.x < k.x + k.w + pad && k.x < b.x + b.w + pad && b.y < k.y + k.h + pad && k.y < b.y + b.h + pad) return true;
        }
        return false;
    }
    for (var i = 0; i < specs.length; i++) {
        var s = specs[i], placed = null, usedText = s.text;
        var onScreen = s.x >= view.x - 4 * unit && s.x <= view.x + view.w + 4 * unit && s.y >= view.y - 4 * unit && s.y <= view.y + view.h + 4 * unit;
        var forms = [];                                     // [text, width, height] in order of preference
        if (s.text2 && lines === 1) forms.push([s.text2, sizes[i].w2, sizes[i].h2]);
        else { forms.push([s.text, sizes[i].w, sizes[i].h]); if (s.text2 && lines === 2) forms.push([s.text2, sizes[i].w2, sizes[i].h2]); }
        if (onScreen && s.text !== "") {
            var sides = s.side === "below" ? ["below", "above"] : s.side === "left" ? ["left", "right", "below", "above"] : ["right", "left", "below", "above"];
            for (var f = 0; f < forms.length && !placed; f++) {
                var tw = forms[f][1] + 8 * unit, th = forms[f][2] + 2;
                for (var c = 0; c < sides.length && !placed; c++) {
                    var b = sides[c] === "right" ? { x: s.x + s.gap, y: s.y - th / 2, w: tw, h: th }
                          : sides[c] === "left" ? { x: s.x - s.gap - tw, y: s.y - th / 2, w: tw, h: th }
                          : sides[c] === "below" ? { x: s.x - tw / 2, y: s.y + s.gap, w: tw, h: th }
                          : { x: s.x - tw / 2, y: s.y - s.gap - th, w: tw, h: th };
                    // the automatic mode only accepts the wide form where it needs no nudging: otherwise the
                    // narrow one gets its turn, and only then is a nudged position accepted
                    var nudged = b.x < view.x + pad || b.x + tw > view.x + view.w - pad || b.y < view.y + pad || b.y + th > view.y + view.h - pad;
                    if (nudged && lines === 2 && f === 0 && forms.length > 1) continue;
                    if (b.x < view.x + pad) b.x = view.x + pad;                              // nudge back onto the screen
                    if (b.x + tw > view.x + view.w - pad) b.x = view.x + view.w - pad - tw;
                    if (b.y < view.y + pad) b.y = view.y + pad;
                    if (b.y + th > view.y + view.h - pad) b.y = view.y + view.h - pad - th;
                    // a nudge must not push the label over its own mark
                    var overMark = s.x > b.x - pad && s.x < b.x + tw + pad && s.y > b.y - pad && s.y < b.y + th + pad;
                    if (!overMark && !clash(b)) { placed = b; usedText = forms[f][0]; }
                }
            }
        }
        if (placed) {
            // displaced from the natural spot beside the mark? then a leader line helps the eye
            var nearX = Math.max(placed.x, Math.min(s.x, placed.x + placed.w)), nearY = Math.max(placed.y, Math.min(s.y, placed.y + placed.h));
            var dist = Math.sqrt((nearX - s.x) * (nearX - s.x) + (nearY - s.y) * (nearY - s.y));
            out.push({ show: true, x: placed.x, y: placed.y, leader: dist > s.gap + 6 * unit, lx: nearX, ly: nearY, text: usedText });
            kept.push(placed);
        } else {
            out.push({ show: false, x: 0, y: 0, leader: false, lx: 0, ly: 0, text: s.text });
        }
    }
    return out;
}

// The two-line form of a label: the part before the first " · " above the rest. Layers may hand over
// their own text2 (earthquakes put the place first); this is the fallback.
function twoLine(text) {
    var i = text.indexOf(" \u00b7 ");
    return i < 0 ? "" : text.substring(0, i) + "\n" + text.substring(i + 3);
}

// Pulse rings: how far along (0..1) a ring is, or -1 while it rests. Every pulsing thing gets a
// different `seed`, so they do not all pulse together. Eased so the ring starts fast and fades out slow.
function pulse(clockMs, seed, durationMs, periodMs) {
    var t = (clockMs + seed * 397) % Math.max(periodMs, durationMs + 200);
    if (t >= durationMs) return -1;
    var p = t / durationMs;
    return 1 - Math.pow(1 - p, 3);
}

// ---- ageing ---------------------------------------------------------------------------
// 0 while a thing is younger than `startH` hours, 1 once it is older than `endH`, in between in between.
function ageMix(hours, startH, endH) {
    if (hours === undefined || hours === null || hours < 0) return 0;
    if (endH <= startH) return hours >= startH ? 1 : 0;
    return Math.min(1, Math.max(0, (hours - startH) / (endH - startH)));
}

// Blend two colours: k = 0 gives a, k = 1 gives b.
function mix(a, b, k) {
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
}

