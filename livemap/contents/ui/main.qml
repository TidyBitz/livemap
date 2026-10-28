// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 tidybitz
/*
 * Live World Map - Plasma 6 wallpaper
 *
 * One equirectangular map, many optional layers. Everything geographic is a
 * child of `map`, and on an equirectangular image lat/lon -> pixels is linear:
 *     x = (lon + 180) / 360 * map.width      y = (90 - lat) / 180 * map.height
 * so a new layer is just a QML file in this folder plus a checkbox.
 *
 * Draw order: base map -> clouds -> dimming -> night shade -> city lights -> borders -> quakes -> network.
 */
import QtQuick
import QtQuick.Window
import QtCore
import QtQuick.Effects
import org.kde.plasma.plasmoid
import "geo.js" as Geo

WallpaperItem {
    id: root

    readonly property var cfg: root.configuration
    readonly property string dataDir: cfg.DataDir !== ""
        ? "file://" + cfg.DataDir
        : String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)) + "/livemap"

    // ---- clock: everything time-dependent hangs off `now` -------------------
    property date now: new Date()
    Timer {
        interval: 120000; running: true; repeat: true
        onTriggered: { root.now = new Date(); root.tick++; if (lights.status === Image.Error) root.nightTick++; }
    }

    // ---- performance and power ------------------------------------------------
    // fps 0 means "frozen": no animation clocks run, so the desktop is not redrawn at all
    // between data updates. saving: 0 normal, 1 paused + slow polling, 2 plain map only.
    Loader {
        id: powerLoader
        active: true                                // battery, load guard and the widget's mode file all come through here
        source: "PowerWatch.qml"
        onLoaded: {
            item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            item.guardEnabled = Qt.binding(function () { return cfg.GuardEnabled });
            item.pauseAt = Qt.binding(function () { return cfg.GuardPause });
            item.plainAt = Qt.binding(function () { return cfg.GuardPlain });
            item.layers = Qt.binding(function () { return root.shownLayers });
            item.units = Qt.binding(function () { return cfg.DistanceUnits + "," + cfg.StormUnits + "," + (cfg.ZoneClock12 ? 1 : 0) + "," + (cfg.TempUnits === undefined ? 0 : cfg.TempUnits) });
            item.fireFocus = Qt.binding(function () { return cfg.FireFocus });
            item.floodLevel = Qt.binding(function () { return cfg.FloodMinLevel });
            item.nwsEach = Qt.binding(function () { return cfg.FloodNwsEach });
            item.fireSources = Qt.binding(function () { return cfg.FireSources });
            item.floodSources = Qt.binding(function () { return (cfg.FloodNws ? 1 : 0) | cfg.FloodWarnSources });
            item.quakeSources = Qt.binding(function () { return cfg.QuakeSources });
            item.home = Qt.binding(function () { return cfg.HomeLat !== "" && cfg.HomeLon !== "" ? cfg.HomeLat + "," + cfg.HomeLon : "" });
            item.homeName = Qt.binding(function () { return cfg.HomeCity || "" });
            item.passes = Qt.binding(function () { return cfg.SatPasses === undefined ? 0 : cfg.SatPasses });
            item.saving = Qt.binding(function () { return root.saving });
            item.savingWhy = Qt.binding(function () { return root.savingWhy });
        }
    }
    readonly property bool onBattery: powerLoader.item ? powerLoader.item.onBattery : false
    // the event layers switched on, for the companion widget (it can list only what the map shows)
    readonly property string shownLayers: [cfg.ShowQuakes ? "quakes" : "", cfg.ShowVolcanoes ? "volcanoes" : "", cfg.ShowStorms ? "storms" : "",
                                           cfg.ShowFires ? "fires" : "", cfg.ShowFloods ? "floods" : "", cfg.ShowTsunami ? "tsunami" : "", cfg.ShowAirAlerts ? "alerts" : "", cfg.ShowLaunches ? "launches" : "", cfg.ShowSats ? "sats" : "",
                                           cfg.ShowNetwork ? "network" : ""].filter(function (l) { return l !== ""; }).join(",")
    readonly property int guardLevel: powerLoader.item ? powerLoader.item.guardLevel : 0
    readonly property var mode: powerLoader.item ? powerLoader.item.mode : ({})
    readonly property int modeLevel: mode.plain ? 2 : mode.pause ? 1 : 0
    // "Full speed" from the widget: the battery policy and the load guard are ignored (the helper drops a
    // timed one when its time is up); the widget's own pause / plain map still count
    readonly property bool fullSpeed: !!mode.full
    // otherwise the strictest of: battery setting, load guard, the widget's request
    readonly property int saving: fullSpeed ? modeLevel : Math.max(onBattery ? cfg.OnBattery : 0, guardLevel, modeLevel)
    readonly property string savingWhy: saving === 0 ? "" : modeLevel >= saving ? "paused from the widget"
        : guardLevel >= saving ? "load guard: CPU " + (powerLoader.item.cpu < 0 ? "?" : powerLoader.item.cpu + " %") + ", GPU " + (powerLoader.item.gpu < 0 ? "?" : powerLoader.item.gpu + " %")
        : "on battery"
    function hidden(name) { return !!(mode.hide && mode.hide.indexOf(name) >= 0) }
    readonly property int fps: saving > 0 ? 0 : ([60, 30, 20, 10][cfg.AnimationFps] || 30)
    // One pulse clock for every layer. Each layer used to run its own timer at the profile's rate, unsynchronised,
    // and every tick of every timer redraws the whole screen: five layers pulsing meant five times the frames.
    property real clock: 0
    readonly property var pulseLayers: [quakeLoader, stormLoader, volcanoLoader, fireLoader, floodLoader, tsunamiLoader, alertLoader, launchLoader, netLoader]
    readonly property bool anyPulse: pulseLayers.some(function (l) { return l.item && l.item.pulseWanted; })
    Timer {
        interval: Math.round(1000 / Math.max(1, root.fps))
        running: root.fps > 0 && root.anyPulse
        repeat: true
        onTriggered: root.clock += interval
    }
    onSavingChanged: console.warn("livemap: saving level", saving, savingWhy || "(normal)")

    // Missing files are looked for again on every tick, so pressing a Download button in the
    // settings is enough - no restart. An Image only reloads when its source changes, so the
    // retries alternate between two spellings of the same path (".../x" and "..././x").
    property int tick: 0
    property int nightTick: 0
    function again(n) { return n % 2 ? "/./" : "/" }

    readonly property var sun: Geo.sun(now)
    // Night mode: 0 the night side as the sun leaves it (the terminator); 1 the whole map at night, always;
    // 2 the whole map at night during your own night - the sun more than 6 degrees under the horizon at the home
    // place (civil dusk to dawn) - and the terminator by day. The city lights follow: everywhere when it is night
    // everywhere, when they are on at all.
    readonly property int nightMode: cfg.NightMode === undefined ? 0 : cfg.NightMode
    readonly property real homeLatN: parseFloat(cfg.HomeLat); readonly property real homeLonN: parseFloat(cfg.HomeLon)
    readonly property bool homeKnown: !isNaN(homeLatN) && !isNaN(homeLonN)
    readonly property real homeSunElevation: homeKnown ? Geo.sunElevation(homeLatN, homeLonN, sun.lat, sun.lon) : 90
    readonly property bool nightEverywhere: nightMode === 1 || (nightMode === 2 && homeKnown && homeSunElevation < -6)
    readonly property var season: Geo.monthBlend(now)
    readonly property int cloudStamp: Math.floor(now.getTime() / 10800000)   // changes every 3 h

    // ---- base image selection -----------------------------------------------
    property bool seasonalOk: true       // flips to false if the monthly files are missing
    readonly property bool seasonal: cfg.Seasonal && seasonalOk
    readonly property bool wantSeasonal: cfg.Seasonal
    onWantSeasonalChanged: seasonalOk = true
    property bool lightsPng: true        // lights.png (just the lights) first, NASA's plain night.jpg as fallback
    onDataDirChanged: seasonalOk = true
    readonly property string fallbackUrl: cfg.BaseImage === "" ? ""
        : (cfg.BaseImage.charAt(0) === "/" ? "file://" + cfg.BaseImage : cfg.BaseImage)
    function monthUrl(m, n) { return dataDir + "/base" + again(n || 0) + (m < 10 ? "0" : "") + m + ".jpg" }

    // A few lines in the journal so problems can be diagnosed without guessing.
    // (console.warn, because Fedora's default Qt logging rules hide console.log.)
    Component.onCompleted: { Look.matrix = cfg.MapStyle === 5; console.warn("livemap: 0.48 loaded - settings:", JSON.stringify({
        seasonal: cfg.Seasonal, fill: cfg.FillMode, dayNight: cfg.ShowDayNight, cityLights: cfg.ShowCityLights,
        clouds: cfg.ShowClouds, borders: cfg.ShowBorders, quakes: cfg.ShowQuakes, quakeFeed: cfg.QuakeFeed, network: cfg.ShowNetwork })) }

    Rectangle { anchors.fill: parent; color: "#02040c" }

    // ---- framing ----------------------------------------------------------------
    // The frame is the part of the world that must be on screen, in degrees. Limits keep the zoom at 2x or
    // less, because the cached still layer is a texture the size of the whole map item.
    //   Stretch: the frame fills the screen exactly (shapes get taller or wider as needed, nothing is cut off)
    //   Fit:     true proportions, the whole frame visible (more map, or bars, in the spare space)
    //   Crop:    true proportions, the frame fills the screen and is trimmed where it does not fit
    //   Fill:    Fit without bars - the frame and its surroundings, zoomed in only as far as the world's edges demand
    //   Auto:    Stretch up to 12 % off true, Crop beyond that (the default: right on a wide monitor and on a laptop panel)
    // Any frame at least 10 degrees wide and 5 tall; the still layer's texture is clipped to the screen below,
    // so the zoom is no longer limited to 2x (a region such as Europe is about 8x).
    readonly property real frameN: Math.max(-85, Math.min(90, cfg.FrameNorth))
    readonly property real frameS: Math.min(frameN - 5, Math.max(-90, cfg.FrameSouth))
    readonly property real frameW: Math.max(-180, Math.min(170, cfg.FrameWest))
    readonly property real frameE: Math.max(frameW + 10, Math.min(180, cfg.FrameEast))
    readonly property bool wholeWorld: frameN === 90 && frameS === -90 && frameW === -180 && frameE === 180
    // Map style: 0 seasonal Blue Marble (the monthly maps as they are for the whole world; cut to the frame
    // otherwise), 1 today's satellite view (GIBS VIIRS), 2 Blue Marble relief and bathymetry (GIBS), 3 dark
    // cartographic (no imagery: land polygons over an ocean colour). Styles 1 and 2, and 0 with a region, use
    // imagery the helper builds for exactly this frame (frames/<key>/), fetched by FrameWatch when missing.
    // The imagery is built for what is on screen, not for the frame: in Fit mode the screen shows more than
    // the frame, in Crop mode less, and either way the picture must reach the screen's edges. The view is
    // rounded outwards to whole degrees so a pixel of resize does not ask for a new picture.
    readonly property real viewW: Math.max(-180, Math.floor(-map.x / sx - 180))
    readonly property real viewE: Math.min(180, Math.ceil((root.width - map.x) / sx - 180))
    readonly property real viewN: Math.min(90, Math.ceil(90 + map.y / sy))
    readonly property real viewS: Math.max(-90, Math.floor(90 - (root.height - map.y) / sy))
    readonly property bool viewIsWorld: viewW <= -180 && viewE >= 180 && viewN >= 90 && viewS <= -90
    readonly property int mapStyle: cfg.MapStyle
    // Seasonal style: the 5 400 px monthly map serves a wide view as it is; a narrower view is cut from it, and
    // with the hi-res set downloaded every view - the whole world too - is cut from the 21 600 px maps.
    readonly property bool hiresMaps: frameLoader.item ? frameLoader.item.hires : false
    readonly property bool wantFrame: mapStyle !== 0 || (cfg.Seasonal && (hiresMaps || (!viewIsWorld && (viewE - viewW) < 200)))
    // 3 dark cartographic (own colours), 4 Dark Matter (greys), 5 Matrix (phosphor green): all drawn by the helper as land over ocean
    readonly property bool flatStyle: mapStyle >= 3 && mapStyle <= 5
    // 6 classic: NASA's 2002 Blue Marble, one picture, shipped with the package (a hi-res copy in base/ if the user has one)
    readonly property bool classicStyle: mapStyle === 6
    readonly property string classicUrl: Qt.resolvedUrl("../images/classic.jpg")
    readonly property string plainUrl: classicStyle ? classicUrl : fallbackUrl       // the whole-world picture for the styles with one
    readonly property string frameStyle: mapStyle === 1 ? "viirs" : mapStyle === 2 ? "relief" : flatStyle ? "dark" : classicStyle ? "classic" : "seasonal"
    readonly property string landColour: mapStyle === 4 ? "#2a2a2a" : mapStyle === 5 ? "#0b2a14" : String(cfg.LandColor)
    readonly property string oceanColour: mapStyle === 4 ? "#121212" : mapStyle === 5 ? "#020804" : String(cfg.OceanColor)
    onMapStyleChanged: Look.matrix = mapStyle === 5
    // the dark style is drawn by the helper as an image too: its colours and detail are part of the request
    readonly property string frameExtra: flatStyle ? " --land '" + landColour + "' --ocean '" + oceanColour + "' --detail " + (cfg.BorderDetail === 1 ? "50m" : "110m")
                                       : mapStyle === 0 && !cfg.SeasonalHires ? " --lowres" : ""
    readonly property int frameWidthPx: Math.min(16384, Math.ceil(Math.max(1024, (viewE - viewW) * sx * Screen.devicePixelRatio) / 256) * 256)
    readonly property string frameDir: frameLoader.item && frameLoader.item.ready ? frameLoader.item.dir : ""
    Loader {
        id: frameLoader
        active: root.width > 0 && (root.wantFrame || (root.mapStyle === 0 && cfg.Seasonal))   // the seasonal style asks too, to learn of the hi-res set
        source: "FrameWatch.qml"
        onLoaded: {
            item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            item.style = Qt.binding(function () { return root.frameStyle });
            item.north = Qt.binding(function () { return root.viewN }); item.south = Qt.binding(function () { return root.viewS });
            item.west = Qt.binding(function () { return root.viewW }); item.east = Qt.binding(function () { return root.viewE });
            item.widthPx = Qt.binding(function () { return root.frameWidthPx });
            item.extra = Qt.binding(function () { return root.frameExtra });
        }
    }
    readonly property string frameNote: frameLoader.item ? frameLoader.item.note : ""
    readonly property real sxFill: root.width / (frameE - frameW)          // pixels per degree if stretched
    readonly property real syFill: root.height / (frameN - frameS)
    // Fill (mode 3): Fit, then no bars. The whole frame at true proportions; the spare screen shows more map
    // around it rather than bars, and the view zooms in only as far as it must to stay inside the world - so a
    // region fills the screen with its surroundings, and the whole world on a 16:10 screen loses the mid-Pacific
    // (on a wide screen, the poles), like a printed map.
    readonly property real sFill: Math.max(Math.min(sxFill, syFill), root.width / 360, root.height / 180)
    // Auto (mode 4, the default): Stretch while the distortion is small, Crop beyond that. The frame is stretched up to
    // 12 % taller or wider than true - a 2.8:1 view on a 2.4:1 monitor passes unnoticed - and on a screen whose shape is
    // further from the frame's (a 16:10 laptop panel) the shapes stay within those 12 % and the sides are trimmed
    // instead. One setting that looks right on every screen, so copying settings between screens is safe.
    readonly property real autoStretch: 1.12
    readonly property real autoTall: Math.max(1 / autoStretch, Math.min(autoStretch, syFill / sxFill))   // how much taller than true the shapes come out
    readonly property real sx: cfg.FillMode === 0 ? sxFill : cfg.FillMode === 1 ? Math.min(sxFill, syFill) : cfg.FillMode === 3 ? sFill
                             : cfg.FillMode === 4 ? (syFill >= sxFill ? syFill / autoTall : sxFill) : Math.max(sxFill, syFill)
    readonly property real sy: cfg.FillMode === 0 ? syFill : cfg.FillMode === 4 ? (syFill >= sxFill ? syFill : sxFill * autoTall) : sx
    // the centre of the view: the frame's, kept inside the world so the trimmed mode never shows past the edges
    readonly property real centreLon: cfg.FillMode === 3 ? Math.max(-180 + root.width / (2 * sx), Math.min(180 - root.width / (2 * sx), (frameW + frameE) / 2)) : (frameW + frameE) / 2
    readonly property real centreLat: cfg.FillMode === 3 ? Math.max(-90 + root.height / (2 * sy), Math.min(90 - root.height / (2 * sy), (frameN + frameS) / 2)) : (frameN + frameS) / 2
    readonly property string framing: frameN + "/" + frameS + "/" + frameW + "/" + frameE + "/" + cfg.FillMode + "/" + width + "x" + height
    onFramingChanged: if (width > 0) console.warn("livemap: frame", frameN + "N", frameS + "S", frameW + "W", frameE + "E",
        "- shapes drawn", Math.round(sy / sx * 100) + "% as tall as true, on", Math.round(width) + "x" + Math.round(height))

    Item {
        id: map
        // The map item always spans the whole world (360 x 180 degrees); what changes is how many pixels a
        // degree gets and where the item sits, so that the chosen frame lands on the screen. Every layer is
        // a child of this item and works in its coordinates, so they all follow without knowing about frames.
        width: 360 * root.sx
        height: 180 * root.sy
        x: root.width / 2 - (root.centreLon + 180) * root.sx
        y: root.height / 2 - (90 - root.centreLat) * root.sy

        readonly property size tex: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                            Math.ceil(height * Screen.devicePixelRatio))
        readonly property bool sized: width > 0 && height > 0

        // -- the still part of the map --------------------------------------------
        // Everything in here changes at most every two minutes, so it is rendered once into a
        // texture and reused. Without this, any animation (an earthquake ripple is enough) makes
        // Qt redraw the whole stack - two 5K images, clouds, shade, lights and ~100 000 border
        // segments - on every single frame, which is what slowed other applications down.
        // The cached texture is the size of this outer item, so it is the screen's part of the map, not the
        // whole map: a region at 8x would otherwise ask for a texture eight screens wide, beyond what a GPU
        // allows. The inner item is the whole map again, so every child still works in map coordinates.
        Item {
            id: stillView
            x: -map.x; y: -map.y; width: root.width; height: root.height
            layer.enabled: cfg.CacheStill
        Item {
            id: still
            x: -stillView.x; y: -stillView.y; width: map.width; height: map.height

            // -- base: this month, with next/previous month cross-faded on top ----
            Image {
                visible: false
                asynchronous: true
                sourceSize: Qt.size(32, 16)
                source: cfg.Seasonal && !root.seasonalOk ? root.monthUrl(root.season.a, root.tick) : ""
                onStatusChanged: if (status === Image.Ready) root.seasonalOk = true     // probe: the monthly maps have arrived
            }
            Image {
                visible: false
                asynchronous: true
                sourceSize: Qt.size(32, 16)
                source: lights.wanted && !root.lightsPng ? root.dataDir + root.again(root.tick) + "lights.png" : ""
                onStatusChanged: if (status === Image.Ready) root.lightsPng = true       // probe: lights.png has arrived
            }
            // -- the dark cartographic style: the ocean colour while its image (helper-drawn) is on its way --
            Rectangle { anchors.fill: parent; visible: root.flatStyle; color: root.oceanColour }
            // -- imagery: the whole world's monthly maps, or the frame's own files; toned by MultiEffect below --
            Item {
                id: toneView                                  // the screen's part, for the tone effect's texture
                x: -map.x; y: -map.y; width: root.width; height: root.height
                layer.enabled: cfg.MapTone > 0 && root.mapStyle !== 3
                layer.effect: MultiEffect {
                    saturation: [0, -0.55, -1, -0.75, -1][cfg.MapTone] || 0
                    colorization: [0, 0, 0, 0.55, 0.6][cfg.MapTone] || 0
                    colorizationColor: cfg.MapTone === 4 ? "#b08a5a" : "#5b8fd6"
                    brightness: cfg.MapTone === 1 ? -0.05 : 0
                }
            Item {
                id: baseGroup
                x: -toneView.x; y: -toneView.y; width: map.width; height: map.height
                // frame imagery covers the frame only; whole-world imagery the whole map
                readonly property bool framed: root.wantFrame && root.frameDir !== ""
                readonly property real fx: framed ? (root.viewW + 180) * root.sx : 0
                readonly property real fy: framed ? (90 - root.viewN) * root.sy : 0
                readonly property real fw: framed ? (root.viewE - root.viewW) * root.sx : map.width
                readonly property real fh: framed ? (root.viewN - root.viewS) * root.sy : map.height
                readonly property size ftex: Qt.size(Math.ceil(fw * Screen.devicePixelRatio), Math.ceil(fh * Screen.devicePixelRatio))
                function frameUrl(name) { return "file://" + root.frameDir + "/" + name }
                Image {                                       // the monthly map, soft, under the picture while it is on its way (and past the world's edge)
                    anchors.fill: parent
                    asynchronous: true
                    visible: root.wantFrame && !root.viewIsWorld && !root.flatStyle
                    sourceSize: Qt.size(4096, 2048)
                    source: !visible || !map.sized ? "" : root.seasonal && !root.classicStyle ? root.monthUrl(root.season.a) : root.plainUrl
                    opacity: root.mapStyle === 0 ? 1 : 0.6     // the same picture as the frame in the seasonal style: only the sharpness changes at the edge
                }
                Image {
                    id: baseA
                    x: baseGroup.fx; y: baseGroup.fy; width: baseGroup.fw; height: baseGroup.fh
                    asynchronous: true
                    sourceSize: baseGroup.ftex
                    source: !map.sized ? ""
                        : root.wantFrame ? (baseGroup.framed ? baseGroup.frameUrl(root.mapStyle === 0 ? "base" + (root.season.a < 10 ? "0" : "") + root.season.a + ".jpg" : root.flatStyle ? "base.png" : "base.jpg")
                                                             : root.flatStyle ? "" : root.seasonal && root.mapStyle === 0 ? root.monthUrl(root.season.a) : root.plainUrl)
                        : root.seasonal && !root.classicStyle ? root.monthUrl(root.season.a) : root.plainUrl
                    onStatusChanged: {
                        if (status === Image.Error && root.seasonal && !root.classicStyle && !baseGroup.framed) root.seasonalOk = false;
                        if (status === Image.Ready || status === Image.Error)
                            console.warn("livemap: base map", status === Image.Ready ? "loaded" : "FAILED", source);
                    }
                }
                Image {
                    x: baseGroup.fx; y: baseGroup.fy; width: baseGroup.fw; height: baseGroup.fh
                    asynchronous: true
                    sourceSize: baseGroup.ftex
                    source: !map.sized || !root.seasonal || !cfg.SeasonalBlend || root.mapStyle !== 0 ? ""
                        : baseGroup.framed ? baseGroup.frameUrl("base" + (root.season.b < 10 ? "0" : "") + root.season.b + ".jpg")
                        : root.wantFrame ? "" : root.monthUrl(root.season.b)
                    opacity: status === Image.Ready ? root.season.mix : 0
                }
            }
            }

            // -- the Matrix style's graticule: a faint green grid every 10 degrees, brighter every 30
            Canvas {
                anchors.fill: parent
                visible: root.mapStyle === 5
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: if (visible) requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.clearRect(0, 0, width, height);
                    for (var lon = -180; lon <= 180; lon += 10) {
                        c.fillStyle = lon % 30 === 0 ? "rgba(0,255,106,0.22)" : "rgba(0,255,106,0.10)";
                        c.fillRect(Math.round((lon + 180) / 360 * width), 0, 1, height);
                    }
                    for (var lat = -80; lat <= 80; lat += 10) {
                        c.fillStyle = lat % 30 === 0 ? "rgba(0,255,106,0.22)" : "rgba(0,255,106,0.10)";
                        c.fillRect(0, Math.round((90 - lat) / 180 * height), width, 1);
                    }
                }
            }
            // -- clouds (remote, refreshed every three hours; stitched locally from the satellites as fallback) --
            // the widget can switch the clouds off or set their opacity on top of the settings (mode.json)
            readonly property bool cloudsWanted: cfg.ShowClouds && root.mode.clouds !== false
            readonly property real cloudOpacity: (root.mode.cloud_opacity !== undefined && root.mode.cloud_opacity !== null ? root.mode.cloud_opacity : cfg.CloudOpacity) / 100
            Loader {
                id: cloudWatch
                active: still.cloudsWanted && cfg.CloudSource !== 2
                source: "CloudWatch.qml"
                onLoaded: {
                    item.mode = Qt.binding(function () { return cfg.CloudSource });
                    item.stamp = Qt.binding(function () { return root.cloudStamp });
                    item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
                }
            }
            readonly property bool cloudsLocal: cloudWatch.item ? cloudWatch.item.wantLocal && cloudWatch.item.localSource !== "" : false
            Image {
                id: cloudImage
                anchors.fill: parent
                asynchronous: true
                cache: false
                sourceSize: map.tex
                visible: still.cloudsWanted
                opacity: still.cloudOpacity
                source: !still.cloudsWanted || !map.sized ? ""
                    : still.cloudsLocal ? cloudWatch.item.localSource
                    : "https://clouds.matteason.co.uk/images/4096x2048/clouds-alpha.png?t=" + root.cloudStamp
                onStatusChanged: {
                    if (status === Image.Error && !still.cloudsLocal && cloudWatch.item) {
                        console.warn("livemap clouds: the web image could not be loaded - stitching from the satellites instead");
                        cloudWatch.item.webFailed = true;
                    }
                }
                // try the web image again at the next 3-hour stamp (a stitched image stays until it loads)
                Connections { target: root; function onCloudStampChanged() { if (cloudWatch.item && cfg.CloudSource === 0) cloudWatch.item.webFailed = false } }
            }

            // -- optional dimming of the imagery, so icons, windows and overlays stand out
            Rectangle { anchors.fill: parent; color: "black"; visible: cfg.MapDim > 0; opacity: cfg.MapDim / 100 }

            // -- night side -------------------------------------------------------
            // A small Canvas painted with ordinary rectangles and gradients, shown
            // directly and stretched over the map by a plain Scale transform. The
            // stretch is what makes it smooth (it is only a soft gradient anyway).
            Canvas {
                id: shade
                width: 360; height: 180
                // Off on purpose. With fractional display scaling (a laptop at 120 %, say) the 1-px strips no longer
                // line up with device pixels; antialiasing then blends neighbouring strips in the pixels they share,
                // which comes out lighter than either - regular vertical stripes across the night side. Without it
                // every device pixel belongs to exactly one strip. The smooth upscale hides the hard strip edges.
                antialiasing: false
                // On the flat styles the night shade would make the land two tones (lit grey, dark grey); there the
                // city lights alone say where it is night, so the shade only serves as their mask and is not shown.
                visible: cfg.ShowDayNight && !root.flatStyle
                transform: Scale { xScale: map.width / shade.width; yScale: map.height / shade.height }
                property int paints: 0
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.globalCompositeOperation = "source-over";
                    ctx.clearRect(0, 0, width, height);
                    var n = Geo.paintNight(ctx, width, height, root.sun.lat, root.sun.lon,
                                           cfg.NightDarkness / 100, "3,5,14", cfg.Twilight, 0, root.nightEverywhere);
                    if (paints++ < 3) console.warn("livemap 0.48: night shade painted (screen scale " + Screen.devicePixelRatio + ") - sun over", root.sun.lat.toFixed(1) + "," + root.sun.lon.toFixed(1),
                                 "- gradient columns:", n, "- map", Math.round(map.width) + "x" + Math.round(map.height));
                }
                onAvailableChanged: if (available) requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                readonly property string look: cfg.NightDarkness + "/" + cfg.Twilight + "/" + root.nightEverywhere
                onLookChanged: requestPaint()
                Connections { target: root; function onSunChanged() { shade.requestPaint() } }
            }
            // City lights. lights.png holds only the lights (made by the helper from NASA's night
            // picture), so they glow on top of the dimmed map and clouds and fade in through the
            // dusk band. Default renderer: a Canvas that paints the night mask and then the image
            // with "source-in" (the image survives only where the mask is) - the same Canvas
            // machinery as the shade. Optional renderer: a GPU mask, sharper and free of CPU cost.
            Image {
                id: lights
                anchors.fill: parent
                visible: false
                asynchronous: true
                // full size only for the GPU renderer; the Canvas renderer loads the file itself
                sourceSize: cfg.LightsGpu ? map.tex : Qt.size(64, 32)
                readonly property bool wanted: cfg.ShowDayNight && cfg.ShowCityLights && map.sized
                source: !wanted ? "" : root.dataDir + (root.lightsPng ? "/lights.png" : root.again(root.nightTick) + "night.jpg")
                onStatusChanged: {
                    if (status === Image.Error && root.lightsPng) { root.lightsPng = false; return; }
                    if (status === Image.Ready || (status === Image.Error && root.nightTick === 0))
                        console.warn("livemap: city lights", status === Image.Ready ? "found:" : "NOT found:", source);
                }
            }
            Canvas {
                id: glow
                antialiasing: false                  // same reason as the shade above
                readonly property bool wanted: lights.wanted && !cfg.LightsGpu && lights.status === Image.Ready && !frameLights.active
                readonly property url picture: wanted ? lights.source : ""
                width: Math.min(4096, Math.max(1024, Math.round(map.width * Screen.devicePixelRatio)))
                height: Math.round(width / 2)
                visible: wanted
                opacity: cfg.LightsBrightness / 100
                transform: Scale { xScale: map.width / glow.width; yScale: map.height / glow.height }
                property int paints: 0
                onPictureChanged: { if (wanted) loadImage(picture); requestPaint(); }
                onImageLoaded: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.globalCompositeOperation = "source-over";
                    ctx.clearRect(0, 0, width, height);
                    if (!wanted || !isImageLoaded(picture)) return;
                    Geo.paintNight(ctx, width, height, root.sun.lat, root.sun.lon, 1, "0,0,0", cfg.Twilight, 360, root.nightEverywhere);
                    ctx.globalCompositeOperation = "source-in";          // keep the picture only where the mask is
                    ctx.drawImage(picture, 0, 0, width, height);
                    ctx.globalCompositeOperation = "source-over";
                    if (paints++ < 2) console.warn("livemap: city lights painted at", width + "x" + height);
                }
                onAvailableChanged: if (available) requestPaint()
                readonly property string look: cfg.Twilight + "/" + width + "/" + root.nightEverywhere
                onLookChanged: requestPaint()
                // the lights' edge may trail the shade a little: repainting this big canvas every 10 min is plenty
                Timer { interval: 600000; running: glow.wanted; repeat: true; onTriggered: glow.requestPaint() }
            }
            ShaderEffectSource {
                id: shadeTexture
                width: shade.width; height: shade.height
                visible: false
                sourceItem: cfg.LightsGpu ? shade : null
                smooth: true
            }
            // City lights cut for the view (frames/<key>/lights.png, from NASA's 13 500 px night picture): sharp
            // in a region where the whole-world lights would be stretched. Masked by the same shade through a
            // texture of just the view's part of it; while it loads, the whole-world lights above stay.
            Image {
                id: frameLights
                x: baseGroup.fx; y: baseGroup.fy; width: baseGroup.fw; height: baseGroup.fh
                visible: false
                asynchronous: true
                sourceSize: baseGroup.ftex
                readonly property bool wanted: lights.wanted && baseGroup.framed && !root.viewIsWorld
                source: wanted ? baseGroup.frameUrl("lights.png") : ""
                readonly property bool active: wanted && status === Image.Ready
            }
            ShaderEffectSource {
                id: frameShadeTexture
                visible: false
                sourceItem: frameLights.active ? shade : null
                sourceRect: Qt.rect(root.viewW + 180, 90 - root.viewN, root.viewE - root.viewW, root.viewN - root.viewS)   // the shade is 360 x 180: degrees
                textureSize: Qt.size(1024, Math.max(1, Math.round(1024 * (root.viewN - root.viewS) / Math.max(1, root.viewE - root.viewW))))
                smooth: true
            }
            MultiEffect {
                x: baseGroup.fx; y: baseGroup.fy; width: baseGroup.fw; height: baseGroup.fh
                visible: frameLights.active
                source: frameLights
                maskEnabled: true
                maskSource: frameShadeTexture
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                opacity: cfg.LightsBrightness / 100
            }
            MultiEffect {
                anchors.fill: parent
                visible: lights.wanted && cfg.LightsGpu && lights.status === Image.Ready && !frameLights.active
                source: lights
                maskEnabled: true
                maskSource: shadeTexture
                maskThresholdMin: 0.5            // these two make the mask a smooth alpha
                maskSpreadAtMin: 1.0             // blend instead of a hard cut-out
                opacity: cfg.LightsBrightness / 100
            }

            // -- overlay layers ---------------------------------------------------
            // Each lives in its own file and is only instantiated while enabled, so a
            // disabled layer costs nothing and a broken one cannot take the map down.
            Loader {                                       // plate boundaries, under the political lines
                anchors.fill: parent
                id: plateLoader
                active: cfg.ShowPlates
                source: "PlateLayer.qml"
                onLoaded: {
                    item.cfg = root.cfg;
                    item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
                }
                onStatusChanged: if (status === Loader.Error) console.warn("livemap: plate layer failed to load")
            }
            Loader {                                       // oil and gas infrastructure, still marks
                anchors.fill: parent
                id: infraLoader
                opacity: cfg.InfraLayerOpacity / 100                // the marks and lines; labels have their own opacity
                active: cfg.ShowInfra
                source: "InfraLayer.qml"
                onLoaded: {
                    item.cfg = root.cfg;
                    item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
                    item.impacted = Qt.binding(function () { return stormLoader.item ? stormLoader.item.impacted : [] });
                }
                onStatusChanged: if (status === Loader.Error) console.warn("livemap: infrastructure layer failed to load")
            }
            Loader {
                anchors.fill: parent
                id: borderLoader
                active: cfg.ShowBorders || cfg.ShowTimeZones || cfg.ShowRivers      // one layer draws all three
                source: "BorderLayer.qml"
                onLoaded: {
                    item.cfg = root.cfg;
                    item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
                    item.viewNorth = Qt.binding(function () { return root.viewN }); item.viewSouth = Qt.binding(function () { return root.viewS });
                }
                onStatusChanged: if (status === Loader.Error) console.warn("livemap: border layer failed to load")
            }
        }
        }

        // -- the Matrix style's scanlines, over the whole screen, cheap: one small tile repeated
        Image {
            x: -map.x; y: -map.y; width: root.width; height: root.height
            visible: root.mapStyle === 5
            fillMode: Image.Tile
            source: visible ? "scanlines.png" : ""
            opacity: 0.35
            smooth: false
        }

        // -- live overlays (the only things that animate) --------------------------
        Loader {
            id: volcanoLoader
            opacity: cfg.VolcanoLayerOpacity / 100                // the marks and lines; labels have their own opacity
            anchors.fill: parent
            active: cfg.ShowVolcanoes && root.saving < 2 && !root.hidden("volcanoes")
            source: "VolcanoLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: volcano layer failed to load")
        }
        Loader {
            id: stormLoader
            opacity: cfg.StormLayerOpacity / 100                // the marks and lines; labels have their own opacity
            anchors.fill: parent
            active: cfg.ShowStorms && root.saving < 2 && !root.hidden("storms")
            source: "StormLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: storm layer failed to load")
        }
        Loader {
            id: satLoader
            opacity: cfg.SatLayerOpacity / 100                // the marks and lines; labels have their own opacity
            anchors.fill: parent
            z: 1                                    // in orbit: above every ground-level layer (labels stay on top of all)
            active: cfg.ShowSats && root.saving < 2 && !root.hidden("sats")
            source: "SatLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: satellite layer failed to load")
        }
        Loader {
            id: launchLoader
            opacity: cfg.LaunchLayerOpacity / 100                // the marks and lines; labels have their own opacity
            anchors.fill: parent
            active: cfg.ShowLaunches && root.saving < 2 && !root.hidden("launches")
            source: "LaunchLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: launch layer failed to load")
        }
        Loader {
            id: alertLoader
            opacity: cfg.AirAlertLayerOpacity / 100
            anchors.fill: parent
            active: cfg.ShowAirAlerts && root.saving < 2 && !root.hidden("alerts")
            source: "AlertLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: air alert layer failed to load")
        }
        Loader {
            id: floodLoader
            opacity: cfg.FloodLayerOpacity / 100               // the marks and areas; labels have their own opacity
            anchors.fill: parent
            active: cfg.ShowFloods && root.saving < 2 && !root.hidden("floods")
            source: "FloodLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: flood layer failed to load")
        }
        Loader {
            id: tsunamiLoader
            opacity: cfg.TsunamiLayerOpacity / 100
            anchors.fill: parent
            active: cfg.ShowTsunami && root.saving < 2 && !root.hidden("tsunami")
            source: "TsunamiLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: tsunami layer failed to load")
        }
        Loader {
            id: fireLoader
            opacity: cfg.FireLayerOpacity / 100                // the marks and lines; labels have their own opacity
            anchors.fill: parent
            active: cfg.ShowFires && root.saving < 2 && !root.hidden("fires")
            source: "FireLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: wildfire layer failed to load")
        }
        Loader {
            id: quakeLoader
            opacity: cfg.QuakeLayerOpacity / 100                // the marks and lines; labels have their own opacity
            anchors.fill: parent
            active: cfg.ShowQuakes && root.saving < 2 && !root.hidden("quakes")
            source: "QuakeLayer.qml"
            onLoaded: { item.cfg = root.cfg; item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                        item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, ""); }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: earthquake layer failed to load")
        }
        Loader {
            anchors.fill: parent
            id: netLoader
            opacity: cfg.NetLayerOpacity / 100                // the marks and lines; labels have their own opacity
            active: cfg.ShowNetwork && root.saving < 2 && !root.hidden("network")
            source: "NetLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps }); if ("clock" in item) item.clock = Qt.binding(function () { return root.clock });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error)
                console.warn("livemap: network layer failed to load (is plasma5support installed?)")
        }

        // -- the event the widget's list points at, ringed over everything (FocusLayer.qml, focus.json) ----
        Loader {
            anchors.fill: parent
            z: 3
            active: cfg.FocusFromWidget !== false
            source: "FocusLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.clock = Qt.binding(function () { return root.clock });
                item.dataDir = Qt.binding(function () { return root.dataDir });
                item.sx = Qt.binding(function () { return root.sx }); item.sy = Qt.binding(function () { return root.sy });
                item.screen = Qt.binding(function () { return Qt.rect(-map.x, -map.y, root.width, root.height) });
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: focus layer failed to load")
        }

        // -- every event label, drawn last so nothing covers it ---------------------
        LabelPass {
            anchors.fill: parent
            z: 2
            cfg: root.cfg
            netSpecs: netLoader.item ? netLoader.item.labelSpecs : []
            stormSpecs: stormLoader.item ? stormLoader.item.labelSpecs : []
            fireSpecs: fireLoader.item ? fireLoader.item.labelSpecs : []
            floodSpecs: floodLoader.item ? floodLoader.item.labelSpecs : []
            tsunamiSpecs: tsunamiLoader.item ? tsunamiLoader.item.labelSpecs : []
            alertSpecs: alertLoader.item ? alertLoader.item.labelSpecs : []
            satSpecs: satLoader.item ? satLoader.item.labelSpecs : []
            shifts: satLoader.item ? satLoader.item.labelShifts : ({})
            launchSpecs: launchLoader.item ? launchLoader.item.labelSpecs : []
            quakeSpecs: quakeLoader.item ? quakeLoader.item.labelSpecs : []
            volcanoSpecs: volcanoLoader.item ? volcanoLoader.item.labelSpecs : []
            infraSpecs: infraLoader.item ? infraLoader.item.labelSpecs : []
            view: Qt.rect(-map.x, -map.y, root.width, root.height)     // the screen, in map pixels
        }
    }

    // ---- "you ticked it, but..." ----------------------------------------------
    // One block, anchored to the screen rather than to the map (in Crop mode the map is larger
    // than the screen, so anything anchored to its edges can end up out of sight).
    Rectangle {
        id: hints
        readonly property real unit: Math.max(1, root.width / 1920)
        readonly property var lines: [
            cfg.Seasonal && !root.seasonalOk ? "Seasonal maps not downloaded (showing the fallback image)" : "",
            lights.wanted && lights.status === Image.Error ? "City lights not downloaded" : "",
            root.frameNote,
            borderLoader.item && borderLoader.item.hint !== "" ? borderLoader.item.hint : "",
            plateLoader.item && plateLoader.item.hint !== "" ? plateLoader.item.hint : "",
            infraLoader.item && infraLoader.item.hint !== "" ? infraLoader.item.hint : "",
            stormLoader.item && stormLoader.item.hint !== "" ? stormLoader.item.hint : "",
            fireLoader.item && fireLoader.item.hint !== "" ? fireLoader.item.hint : "",
            floodLoader.item && floodLoader.item.hint !== "" ? floodLoader.item.hint : "",
            tsunamiLoader.item && tsunamiLoader.item.hint !== "" ? tsunamiLoader.item.hint : "",
            alertLoader.item && alertLoader.item.hint !== "" ? alertLoader.item.hint : "",
            satLoader.item && satLoader.item.hint !== "" ? satLoader.item.hint : "",
            launchLoader.item && launchLoader.item.hint !== "" ? launchLoader.item.hint : "",
            volcanoLoader.item && volcanoLoader.item.hint !== "" ? volcanoLoader.item.hint : "",
            quakeLoader.item && quakeLoader.item.hint !== "" ? quakeLoader.item.hint : "",
            netLoader.item && netLoader.item.hint !== "" ? "Network: " + netLoader.item.hint : "",
            // what the wallpaper holds back (load guard, battery, the widget's pause) is no longer said here: the widget's
            // Map controls tab and Settings > Status > Power and load carry it (layers.json: saving, why)
            cloudWatch.item && cloudWatch.item.note !== "" ? cloudWatch.item.note : ""
        ].filter(function (t) { return t !== "" })
        readonly property int corner: cfg.HintCorner          // 0 bottom right, 1 bottom left, 2 top right, 3 top left, 4 never
        visible: lines.length > 0 && corner < 4
        x: corner === 1 || corner === 3 ? 24 * unit : root.width - width - 24 * unit
        y: corner >= 2 ? 24 * unit : root.height - height - 56 * unit
        // Small on purpose: one short line per problem, tiny type, no border. Settings > Status has the detail.
        width: note.implicitWidth + 12 * unit; height: note.implicitHeight + 6 * unit
        radius: 3 * unit
        color: Qt.rgba(0, 0.02, 0.06, 0.5)
        function short(t) { return t.length > 64 ? t.substring(0, 62) + "\u2026" : t }
        Text {
            id: note
            anchors.centerIn: parent
            width: Math.min(root.width * 0.2, implicitWidth)
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            text: hints.lines.slice(0, 3).map(hints.short).join("\n") + (hints.lines.length > 3 ? "\n+" + (hints.lines.length - 3) + " more (Settings > Status)" : "")
            color: "#ffd9a0"
            font.pixelSize: Math.round(7.5 * hints.unit)
            opacity: 0.7
        }
    }

    // ---- imagery toast: while the picture for a new base map or view is built, say so where the eyes are ----
    // (large, lower middle, with the helper's progress; a few seconds of "ready" when it lands; the small corner
    // notice above carries everything else)
    Rectangle {
        id: imageryToast
        readonly property var fw: frameLoader.item
        readonly property bool building: !!fw && fw.busy && (fw.tick - fw.startedAt) > 3000   // not for a build that is over in a moment
        readonly property bool ready: !!fw && fw.justReady && fw.readyAt - fw.startedAt > 3000
        readonly property real unit: Math.max(1, Math.min(1.45, root.width / 1920))   // grows with the screen, but not all the way (an ultrawide got a billboard)
        readonly property real elapsed: building && fw.startedAt > 0 ? (fw.tick - fw.startedAt) / 1000 : 0
        visible: opacity > 0
        opacity: (building || ready) && cfg.HintCorner < 4 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        width: Math.min(root.width * 0.3, 460 * unit); height: toastColumn.implicitHeight + 24 * unit
        x: (root.width - width) / 2; y: root.height - height - 72 * unit
        radius: 8 * unit
        color: Qt.rgba(0.05, 0.07, 0.1, 0.92)
        border.width: 1; border.color: ready ? "#27ae60" : "#3daee9"
        Column {
            id: toastColumn
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 * imageryToast.unit }
            spacing: 6 * imageryToast.unit
            Row {
                spacing: 10 * imageryToast.unit
                Item {                                                   // spinner, or a tick when ready
                    width: 18 * imageryToast.unit; height: width
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { visible: imageryToast.building; anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 3 * imageryToast.unit; border.color: "#3daee9"
                                Rectangle { width: parent.width / 2; height: parent.height / 2; color: Qt.rgba(0.05, 0.07, 0.1, 0.92) }
                                RotationAnimation on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: imageryToast.building } }
                    Text { visible: imageryToast.ready; anchors.centerIn: parent; text: "\u2713"; color: "#27ae60"; font.pixelSize: 18 * imageryToast.unit; font.bold: true }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: imageryToast.width - 60 * imageryToast.unit
                    wrapMode: Text.Wrap
                    color: "#fcfcfc"; font.pixelSize: Math.round(13 * imageryToast.unit); font.bold: true
                    text: imageryToast.ready ? "Map imagery ready" : "Building the map imagery" + (imageryToast.fw && imageryToast.fw.total > 0 ? " \u00b7 " + Math.round(100 * imageryToast.fw.done / imageryToast.fw.total) + " %" : "")
                }
            }
            Rectangle {                                                  // the progress bar
                visible: imageryToast.building
                width: parent.width; height: 6 * imageryToast.unit; radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle {
                    height: parent.height; radius: height / 2; color: "#3daee9"
                    width: imageryToast.fw && imageryToast.fw.total > 0 ? parent.width * Math.min(1, imageryToast.fw.done / imageryToast.fw.total) : parent.width * 0.15
                    Behavior on width { NumberAnimation { duration: 600 } }
                    x: imageryToast.fw && imageryToast.fw.total > 0 ? 0 : (parent.width - width) * (0.5 + 0.5 * Math.sin(imageryToast.elapsed * 1.5))
                }
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                color: "#9ea3a6"; font.pixelSize: Math.round(11 * imageryToast.unit)
                text: imageryToast.ready ? (imageryToast.fw ? imageryToast.fw.styleWords : "")
                    : (imageryToast.fw ? imageryToast.fw.styleWords : "") + (imageryToast.fw && imageryToast.fw.what ? " \u00b7 " + imageryToast.fw.what : "")
                      + (imageryToast.elapsed > 0 ? " \u00b7 " + Math.round(imageryToast.elapsed) + " s so far" : "") + (root.frameStyle === "seasonal" ? ", usually under a minute" : root.frameStyle === "viirs" ? ", usually a minute or two" : ", usually about a minute")
                      + " \u00b7 the previous picture stays until this is ready"
            }
        }
    }

    // ---- first-run hint -----------------------------------------------------
    Text {
        anchors.centerIn: parent
        visible: baseA.status !== Image.Ready && baseA.status !== Image.Loading
        color: "#9fb4d0"
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        text: "Live World Map\nPick a base image in the wallpaper settings,\nor run:  livemap-helper fetch-maps"
    }
}
