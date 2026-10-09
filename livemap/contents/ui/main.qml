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
        }
    }
    readonly property bool onBattery: powerLoader.item ? powerLoader.item.onBattery : false
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
    onSavingChanged: console.warn("livemap: saving level", saving, savingWhy || "(normal)")

    // Missing files are looked for again on every tick, so pressing a Download button in the
    // settings is enough - no restart. An Image only reloads when its source changes, so the
    // retries alternate between two spellings of the same path (".../x" and "..././x").
    property int tick: 0
    property int nightTick: 0
    function again(n) { return n % 2 ? "/./" : "/" }

    readonly property var sun: Geo.sun(now)
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
    Component.onCompleted: console.warn("livemap: 0.46 loaded - settings:", JSON.stringify({
        seasonal: cfg.Seasonal, fill: cfg.FillMode, dayNight: cfg.ShowDayNight, cityLights: cfg.ShowCityLights,
        clouds: cfg.ShowClouds, borders: cfg.ShowBorders, quakes: cfg.ShowQuakes, quakeFeed: cfg.QuakeFeed, network: cfg.ShowNetwork }))

    Rectangle { anchors.fill: parent; color: "#02040c" }

    // ---- framing ----------------------------------------------------------------
    // The frame is the part of the world that must be on screen, in degrees. Limits keep the zoom at 2x or
    // less, because the cached still layer is a texture the size of the whole map item.
    //   Stretch: the frame fills the screen exactly (shapes get taller or wider as needed, nothing is cut off)
    //   Fit:     true proportions, the whole frame visible (more map, or bars, in the spare space)
    //   Crop:    true proportions, the frame fills the screen and is trimmed where it does not fit
    readonly property real frameN: Math.max(45, Math.min(90, cfg.FrameNorth))
    readonly property real frameS: Math.min(-45, Math.max(-90, cfg.FrameSouth))
    readonly property real frameW: Math.min(-90, Math.max(-180, cfg.FrameWest))
    readonly property real frameE: Math.max(90, Math.min(180, cfg.FrameEast))
    readonly property real sxFill: root.width / (frameE - frameW)          // pixels per degree if stretched
    readonly property real syFill: root.height / (frameN - frameS)
    readonly property real sx: cfg.FillMode === 0 ? sxFill : cfg.FillMode === 1 ? Math.min(sxFill, syFill) : Math.max(sxFill, syFill)
    readonly property real sy: cfg.FillMode === 0 ? syFill : sx
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
        x: root.width / 2 - ((root.frameW + root.frameE) / 2 + 180) * root.sx
        y: root.height / 2 - (90 - (root.frameN + root.frameS) / 2) * root.sy

        readonly property size tex: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                            Math.ceil(height * Screen.devicePixelRatio))
        readonly property bool sized: width > 0 && height > 0

        // -- the still part of the map --------------------------------------------
        // Everything in here changes at most every two minutes, so it is rendered once into a
        // texture and reused. Without this, any animation (an earthquake ripple is enough) makes
        // Qt redraw the whole stack - two 5K images, clouds, shade, lights and ~100 000 border
        // segments - on every single frame, which is what slowed other applications down.
        Item {
            id: still
            anchors.fill: parent
            layer.enabled: cfg.CacheStill

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
            Image {
                id: baseA
                anchors.fill: parent
                asynchronous: true
                sourceSize: map.tex
                source: !map.sized ? "" : root.seasonal ? root.monthUrl(root.season.a) : root.fallbackUrl
                onStatusChanged: {
                    if (status === Image.Error && root.seasonal) root.seasonalOk = false;
                    if (status === Image.Ready || status === Image.Error)
                        console.warn("livemap: base map", status === Image.Ready ? "loaded" : "FAILED", source);
                }
            }
            Image {
                anchors.fill: parent
                asynchronous: true
                sourceSize: map.tex
                source: map.sized && root.seasonal && cfg.SeasonalBlend ? root.monthUrl(root.season.b) : ""
                opacity: status === Image.Ready ? root.season.mix : 0
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
                visible: cfg.ShowDayNight
                transform: Scale { xScale: map.width / shade.width; yScale: map.height / shade.height }
                property int paints: 0
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.globalCompositeOperation = "source-over";
                    ctx.clearRect(0, 0, width, height);
                    var n = Geo.paintNight(ctx, width, height, root.sun.lat, root.sun.lon,
                                           cfg.NightDarkness / 100, "3,5,14", cfg.Twilight);
                    if (paints++ < 3) console.warn("livemap 0.46: night shade painted (screen scale " + Screen.devicePixelRatio + ") - sun over", root.sun.lat.toFixed(1) + "," + root.sun.lon.toFixed(1),
                                 "- gradient columns:", n, "- map", Math.round(map.width) + "x" + Math.round(map.height));
                }
                onAvailableChanged: if (available) requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                readonly property string look: cfg.NightDarkness + "/" + cfg.Twilight
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
                readonly property bool wanted: lights.wanted && !cfg.LightsGpu && lights.status === Image.Ready
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
                    Geo.paintNight(ctx, width, height, root.sun.lat, root.sun.lon, 1, "0,0,0", cfg.Twilight, 360);
                    ctx.globalCompositeOperation = "source-in";          // keep the picture only where the mask is
                    ctx.drawImage(picture, 0, 0, width, height);
                    ctx.globalCompositeOperation = "source-over";
                    if (paints++ < 2) console.warn("livemap: city lights painted at", width + "x" + height);
                }
                onAvailableChanged: if (available) requestPaint()
                readonly property string look: cfg.Twilight + "/" + width
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
            MultiEffect {
                anchors.fill: parent
                visible: lights.wanted && cfg.LightsGpu && lights.status === Image.Ready
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
            Loader {
                anchors.fill: parent
                id: borderLoader
                active: cfg.ShowBorders
                source: "BorderLayer.qml"
                onLoaded: {
                    item.cfg = root.cfg;
                    item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
                }
                onStatusChanged: if (status === Loader.Error) console.warn("livemap: border layer failed to load")
            }
        }

        // -- live overlays (the only things that animate) --------------------------
        Loader {
            id: volcanoLoader
            anchors.fill: parent
            active: cfg.ShowVolcanoes && root.saving < 2 && !root.hidden("volcanoes")
            source: "VolcanoLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: volcano layer failed to load")
        }
        Loader {
            id: stormLoader
            anchors.fill: parent
            active: cfg.ShowStorms && root.saving < 2 && !root.hidden("storms")
            source: "StormLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: storm layer failed to load")
        }
        Loader {
            id: satLoader
            anchors.fill: parent
            z: 1                                    // in orbit: above every ground-level layer (labels stay on top of all)
            active: cfg.ShowSats && root.saving < 2 && !root.hidden("sats")
            source: "SatLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: satellite layer failed to load")
        }
        Loader {
            id: launchLoader
            anchors.fill: parent
            active: cfg.ShowLaunches && root.saving < 2 && !root.hidden("launches")
            source: "LaunchLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: launch layer failed to load")
        }
        Loader {
            id: fireLoader
            anchors.fill: parent
            active: cfg.ShowFires && root.saving < 2 && !root.hidden("fires")
            source: "FireLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: wildfire layer failed to load")
        }
        Loader {
            id: quakeLoader
            anchors.fill: parent
            active: cfg.ShowQuakes && root.saving < 2 && !root.hidden("quakes")
            source: "QuakeLayer.qml"
            onLoaded: { item.cfg = root.cfg; item.fps = Qt.binding(function () { return root.fps }); }
            onStatusChanged: if (status === Loader.Error) console.warn("livemap: earthquake layer failed to load")
        }
        Loader {
            anchors.fill: parent
            id: netLoader
            active: cfg.ShowNetwork && root.saving < 2 && !root.hidden("network")
            source: "NetLayer.qml"
            onLoaded: {
                item.cfg = root.cfg;
                item.fps = Qt.binding(function () { return root.fps });
                item.slow = Qt.binding(function () { return root.saving === 1 });
                item.helper = String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "");
            }
            onStatusChanged: if (status === Loader.Error)
                console.warn("livemap: network layer failed to load (is plasma5support installed?)")
        }

        // -- every event label, drawn last so nothing covers it ---------------------
        LabelPass {
            anchors.fill: parent
            z: 2
            cfg: root.cfg
            netSpecs: netLoader.item ? netLoader.item.labelSpecs : []
            stormSpecs: stormLoader.item ? stormLoader.item.labelSpecs : []
            fireSpecs: fireLoader.item ? fireLoader.item.labelSpecs : []
            satSpecs: satLoader.item ? satLoader.item.labelSpecs : []
            shifts: satLoader.item ? satLoader.item.labelShifts : ({})
            launchSpecs: launchLoader.item ? launchLoader.item.labelSpecs : []
            quakeSpecs: quakeLoader.item ? quakeLoader.item.labelSpecs : []
            volcanoSpecs: volcanoLoader.item ? volcanoLoader.item.labelSpecs : []
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
            borderLoader.item && borderLoader.item.hint !== "" ? borderLoader.item.hint : "",
            plateLoader.item && plateLoader.item.hint !== "" ? plateLoader.item.hint : "",
            stormLoader.item && stormLoader.item.hint !== "" ? stormLoader.item.hint : "",
            fireLoader.item && fireLoader.item.hint !== "" ? fireLoader.item.hint : "",
            satLoader.item && satLoader.item.hint !== "" ? satLoader.item.hint : "",
            launchLoader.item && launchLoader.item.hint !== "" ? launchLoader.item.hint : "",
            volcanoLoader.item && volcanoLoader.item.hint !== "" ? volcanoLoader.item.hint : "",
            netLoader.item && netLoader.item.hint !== "" ? "Network: " + netLoader.item.hint : "",
            root.saving > 0 && root.savingWhy !== "on battery" ? (root.saving === 2 ? "Live layers off: " : "Animations paused: ") + root.savingWhy : "",
            root.fullSpeed && root.saving === 0 && (root.guardLevel > 0 || (root.onBattery && cfg.OnBattery > 0))
                ? "Full speed from the widget" + (root.guardLevel > 0 ? " (load guard overridden)" : " (on battery)") : "",
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
