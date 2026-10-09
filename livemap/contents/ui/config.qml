/*
 * Settings page. Plasma fills every `cfg_<Key>` property from main.xml and
 * writes it back on Apply, so a new setting needs: one <entry> in main.xml,
 * one cfg_ property here, and a place in the wallpaper that reads cfg.<Key>.
 *
 * Layout rules, so the page survives a narrow window (Kirigami then stacks the
 * label above each row): at most three short controls per row, sliders that
 * shrink, and explanations in wrapping labels rather than in checkbox texts.
 *
 * Every element that draws something gets its own section, and inside each
 * section the order is always the same:
 *   1. Show        - the on/off switch and which data
 *   2. Look        - colour, size, shape
 *   3. Labels      - what they say, size, plate, text colour
 *   4. Behaviour   - pulsing and ageing choices for that element
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    id: form
    twinFormLayouts: parentLayout
    property alias formLayout: form
    // Always the two-column form. Left to itself Kirigami switches to a stacked layout in a narrow window,
    // which moves every label; with the controls capped in width the page simply gets narrower instead.
    wideMode: true

    // map
    property alias cfg_BaseImage: baseImage.text
    property alias cfg_DataDir: dataDir.text
    property alias cfg_Seasonal: seasonal.checked
    property alias cfg_SeasonalBlend: seasonalBlend.checked
    property alias cfg_FillMode: fillMode.currentIndex
    property alias cfg_FrameNorth: frameNorth.value
    property alias cfg_FrameSouth: frameSouth.value
    property alias cfg_FrameWest: frameWest.value
    property alias cfg_FrameEast: frameEast.value
    property int cfg_MapDim
    property alias cfg_HintCorner: hintCorner.currentIndex
    property alias cfg_StaleHours: staleHours.value
    // sun and sky
    property alias cfg_ShowDayNight: dayNight.checked
    property alias cfg_ShowCityLights: cityLights.checked
    property int cfg_NightDarkness
    property int cfg_Twilight
    property int cfg_LightsBrightness
    property alias cfg_LightsGpu: lightsGpu.checked
    property alias cfg_ShowClouds: clouds.checked
    property alias cfg_CloudSource: cloudSource.currentIndex
    property int cfg_CloudOpacity
    // countries
    property alias cfg_ShowBorders: borders.checked
    property alias cfg_ShowCoast: coast.checked
    property alias cfg_ShowStates: stateLines.checked
    property alias cfg_BorderDetail: borderDetail.currentIndex
    property alias cfg_BorderColor: borderColor.color
    property int cfg_BorderOpacity
    property int cfg_BorderWidth
    property alias cfg_ShowCountryNames: countryNames.checked
    property alias cfg_NameDensity: nameDensity.currentIndex
    property alias cfg_NameSize: nameSize.value
    property alias cfg_NameOpacity: nameStyle.textOpacity
    property alias cfg_NamePlate: namePlate.checked
    property alias cfg_NameTextFollows: nameFollows.checked
    property alias cfg_NameTextColor: nameTextColor.color
    property alias cfg_NameHalo: nameStyle.halo
    property alias cfg_NameBold: nameStyle.bold
    property alias cfg_NameCaps: nameStyle.caps
    property alias cfg_NameSpacing: nameStyle.letterSpacing
    property alias cfg_QuakeLabelBold: quakeStyle.bold
    property alias cfg_QuakeLabelCaps: quakeStyle.caps
    property alias cfg_QuakeLabelSpacing: quakeStyle.letterSpacing
    property alias cfg_QuakeLabelOpacity: quakeStyle.textOpacity
    property alias cfg_QuakeLabelHalo: quakeStyle.halo
    property alias cfg_VolcanoLabelBold: volcanoStyle.bold
    property alias cfg_VolcanoLabelCaps: volcanoStyle.caps
    property alias cfg_VolcanoLabelSpacing: volcanoStyle.letterSpacing
    property alias cfg_VolcanoLabelOpacity: volcanoStyle.textOpacity
    property alias cfg_VolcanoLabelHalo: volcanoStyle.halo
    property alias cfg_StormLabelBold: stormStyle.bold
    property alias cfg_StormLabelCaps: stormStyle.caps
    property alias cfg_StormLabelSpacing: stormStyle.letterSpacing
    property alias cfg_StormLabelOpacity: stormStyle.textOpacity
    property alias cfg_StormLabelHalo: stormStyle.halo
    property alias cfg_FireLabelBold: fireStyle.bold
    property alias cfg_FireLabelCaps: fireStyle.caps
    property alias cfg_FireLabelSpacing: fireStyle.letterSpacing
    property alias cfg_FireLabelOpacity: fireStyle.textOpacity
    property alias cfg_FireLabelHalo: fireStyle.halo
    property alias cfg_SatLabelBold: satStyle.bold
    property alias cfg_SatLabelCaps: satStyle.caps
    property alias cfg_SatLabelSpacing: satStyle.letterSpacing
    property alias cfg_SatLabelOpacity: satStyle.textOpacity
    property alias cfg_SatLabelHalo: satStyle.halo
    property alias cfg_LaunchLabelBold: launchStyle.bold
    property alias cfg_LaunchLabelCaps: launchStyle.caps
    property alias cfg_LaunchLabelSpacing: launchStyle.letterSpacing
    property alias cfg_LaunchLabelOpacity: launchStyle.textOpacity
    property alias cfg_LaunchLabelHalo: launchStyle.halo
    property alias cfg_NetLabelBold: netStyle.bold
    property alias cfg_NetLabelCaps: netStyle.caps
    property alias cfg_NetLabelSpacing: netStyle.letterSpacing
    property alias cfg_NetLabelOpacity: netStyle.textOpacity
    property alias cfg_NetLabelHalo: netStyle.halo
    // time zones
    property alias cfg_ShowTimeZones: timeZones.checked
    property alias cfg_ZoneColor: zoneColor.color
    property int cfg_ZoneOpacity
    property alias cfg_ZoneLabels: zoneLabels.checked
    property alias cfg_ZoneLabelSize: zoneLabelSize.value
    property alias cfg_ZoneLabelBold: zoneStyle.bold
    property alias cfg_ZoneLabelCaps: zoneStyle.caps
    property alias cfg_ZoneLabelSpacing: zoneStyle.letterSpacing
    property alias cfg_ZoneLabelOpacity: zoneStyle.textOpacity
    property alias cfg_ZoneLabelHalo: zoneStyle.halo
    // earthquakes
    property alias cfg_ShowQuakes: quakes.checked
    property alias cfg_QuakeFeed: quakeFeed.currentIndex
    property alias cfg_QuakeColor: quakeColor.color
    property int cfg_QuakeSize
    property alias cfg_ShowPlates: plates.checked
    property alias cfg_PlateLineColor: plateLineColor.color
    property int cfg_PlateLineOpacity
    property int cfg_PlateLineWidth
    property alias cfg_QuakeLabels: quakeLabels.currentIndex
    property alias cfg_QuakeLabelMin: quakeLabelMin.currentIndex
    property alias cfg_QuakeLabelSize: quakeLabelSize.value
    property alias cfg_QuakeLabelPlate: quakePlate.checked
    property alias cfg_QuakeTextFollows: quakeFollows.checked
    property alias cfg_QuakeTextColor: quakeTextColor.color
    property alias cfg_QuakePulseMode: quakePulseMode.currentIndex
    property alias cfg_QuakePulseMag: quakePulseMag.value
    // volcanoes
    property alias cfg_ShowVolcanoes: volcanoes.checked
    property alias cfg_VolcanoColor: volcanoColor.color
    property alias cfg_VolcanoAlertColors: volcanoAlertColors.checked
    property alias cfg_VolcanoLabels: volcanoLabels.currentIndex
    property alias cfg_VolcanoDetail: volcanoDetail.checked
    property alias cfg_VolcanoLabelSize: volcanoLabelSize.value
    property alias cfg_VolcanoLabelPlate: volcanoPlate.checked
    property alias cfg_VolcanoTextFollows: volcanoFollows.checked
    property alias cfg_VolcanoTextColor: volcanoTextColor.color
    property alias cfg_VolcanoPulseMode: volcanoPulseMode.currentIndex
    // storms
    property alias cfg_ShowStorms: storms.checked
    property alias cfg_StormColor: stormColor.color
    property alias cfg_ShowStormCone: stormCone.checked
    property alias cfg_StormLabels: stormLabels.currentIndex
    property alias cfg_StormUnits: stormUnits.currentIndex
    property alias cfg_StormLabelSize: stormLabelSize.value
    property alias cfg_StormLabelPlate: stormPlate.checked
    property alias cfg_StormTextFollows: stormFollows.checked
    property alias cfg_StormTextColor: stormTextColor.color
    property alias cfg_StormPulseMode: stormPulseMode.currentIndex
    property alias cfg_StormIntensityColors: stormIntensityColors.checked
    property alias cfg_StormTrackColors: stormTrackColors.checked
    property alias cfg_StormOriginMark: stormOriginMark.checked
    property alias cfg_StormMarkerStyle: stormMarkerStyle.currentIndex
    property alias cfg_StormIconTheme: stormIconTheme.currentIndex
    property alias cfg_StormIconSize: stormIconSize.value
    // wildfires
    property alias cfg_ShowFires: fires.checked
    property alias cfg_FireColor: fireColor.color
    property alias cfg_FireAlertColors: fireAlertColors.checked
    property alias cfg_FireMinLevel: fireMinLevel.currentIndex
    property alias cfg_FireMinArea: fireMinArea.currentIndex
    property alias cfg_FireSource: fireSource.currentIndex
    property alias cfg_HotspotMinCount: hotspotMinCount.currentIndex
    property alias cfg_FireLabels: fireLabels.currentIndex
    property alias cfg_FireLabelSize: fireLabelSize.value
    property alias cfg_FireLabelPlate: firePlate.checked
    property alias cfg_FireTextFollows: fireFollows.checked
    property alias cfg_FireTextColor: fireTextColor.color
    property alias cfg_FirePulseMode: firePulseMode.currentIndex
    // space
    property alias cfg_ShowSats: sats.checked
    property alias cfg_SatIss: satIss.checked
    property alias cfg_SatHubble: satHubble.checked
    property alias cfg_SatTiangong: satTiangong.checked
    property alias cfg_SatColor: satColor.color
    property alias cfg_SatMarkerStyle: satMarkerStyle.currentIndex
    property alias cfg_SatPictureSize: satPictureSize.value
    property alias cfg_SatTrack: satTrack.checked
    property alias cfg_SatTrackLength: satTrackLength.currentIndex
    property alias cfg_SatLabels: satLabels.currentIndex
    property alias cfg_SatLabelSize: satLabelSize.value
    property alias cfg_SatLabelPlate: satPlate.checked
    property alias cfg_SatTextFollows: satFollows.checked
    property alias cfg_SatTextColor: satTextColor.color
    property alias cfg_ShowLaunches: launches.checked
    property alias cfg_LaunchWindow: launchWindow.currentIndex
    property alias cfg_LaunchColor: launchColor.color
    property alias cfg_LaunchMarkerStyle: launchMarkerStyle.currentIndex
    property alias cfg_LaunchPictureSize: launchPictureSize.value
    property alias cfg_LaunchLabels: launchLabels.currentIndex
    property alias cfg_LaunchLabelSize: launchLabelSize.value
    property alias cfg_LaunchLabelPlate: launchPlate.checked
    property alias cfg_LaunchTextFollows: launchFollows.checked
    property alias cfg_LaunchTextColor: launchTextColor.color
    property alias cfg_LaunchPulse: launchPulse.checked
    // this computer
    property alias cfg_ShowNetwork: network.checked
    property alias cfg_HomeLat: homeLat.text
    property alias cfg_HomeLon: homeLon.text
    property string cfg_HomeCity
    property alias cfg_NetInterval: netInterval.value
    property alias cfg_NetMaxPlaces: netMaxPlaces.value
    property alias cfg_ArcColor: arcColor.color
    property alias cfg_ArcGlow: arcGlow.checked
    property int cfg_ArcWidth
    property alias cfg_ArcAnimation: arcAnimation.currentIndex
    property int cfg_PacketSpeed
    property alias cfg_NetLabels: netLabels.checked
    property alias cfg_NetShowProcess: netShowProcess.checked
    property alias cfg_ShowLatency: showLatency.checked
    property alias cfg_FlagFastRtt: flagFastRtt.checked
    property alias cfg_ShowProxyNote: proxyNote.checked
    property alias cfg_LabelSize: labelSize.value
    property alias cfg_LabelPlate: netPlate.checked
    property alias cfg_NetTextColor: netTextColor.color
    property alias cfg_NetLinger: netLinger.value
    property alias cfg_ClosedColor: closedColor.color
    property alias cfg_NewWindow: newWindow.value
    property alias cfg_NewColor: newColor.color
    // shared: labels, ageing, pulses
    property alias cfg_PlateColor: plateColor.color
    property int cfg_PlateOpacity
    property int cfg_TextOpacity
    property alias cfg_LabelLines: labelLines.currentIndex
    property alias cfg_DistanceUnits: distanceUnits.currentIndex
    property int cfg_MarkerScale
    property alias cfg_AgeFade: ageFade.checked
    property alias cfg_AgeFadeStart: ageStart.value
    property alias cfg_AgeFadeEnd: ageEnd.value
    property alias cfg_AgedColor: agedColor.color
    property alias cfg_PulseNewHours: pulseNewHours.value
    property alias cfg_PulseDuration: pulseDuration.value
    property alias cfg_PulsePeriod: pulsePeriod.value
    // performance
    property alias cfg_Profile: profile.currentIndex
    property alias cfg_GuardEnabled: guardEnabled.checked
    property int cfg_GuardPause
    property int cfg_GuardPlain
    property alias cfg_AnimationFps: animationFps.currentIndex
    property alias cfg_CacheStill: cacheStill.checked
    property alias cfg_OnBattery: onBattery.currentIndex

    readonly property var pulseChoices: ["Nothing", "Newly reported", "Significant", "Newly reported or significant"]

    // A slider with its value written next to it. `value` follows the setting until
    // the slider is moved, then the setting follows the slider. It shrinks with the window.
    component Amount: RowLayout {
        id: amount
        property int value
        property int from: 0
        property int to: 100
        property string suffix: " %"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        QQC2.Slider {
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 6
            from: amount.from; to: amount.to; stepSize: 1
            value: amount.value
            onMoved: amount.value = Math.round(value)
        }
        QQC2.Label { text: amount.value + amount.suffix; Layout.minimumWidth: Kirigami.Units.gridUnit * 3 }
    }
    // A checkbox that mirrors another one (the top-level layer list and each section's Show box are the
    // same setting in two places). No alias can point at two controls, so they are kept in step by hand.
    component Mirror: QQC2.CheckBox {
        id: mirror
        property QtObject twin: null
        checked: twin ? twin.checked : false
        onToggled: if (twin) twin.checked = checked
        Connections { target: mirror.twin; function onCheckedChanged() { if (mirror.checked !== mirror.twin.checked) mirror.checked = mirror.twin.checked } }
    }
    // A top-level group header: the sections below it belong together.
    component Group: Kirigami.Heading {
        Kirigami.FormData.isSection: true
        level: 1
        topPadding: Kirigami.Units.gridUnit
    }
    // The data sources a section depends on, with their live state from the Status panel at the bottom.
    component Source: ColumnLayout {
        id: src
        property var names: []
        Kirigami.FormData.label: "Source:"
        spacing: 0
        readonly property var checks: statusLoader.item ? statusLoader.item.checks : []
        Repeater {
            model: src.names
            RowLayout {
                required property string modelData
                readonly property var check: src.checks.find(function (c) { return c.name === modelData; }) || null
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5); implicitHeight: implicitWidth; radius: implicitWidth / 2
                    color: !check ? Kirigami.Theme.disabledTextColor : check.state === "ok" ? Kirigami.Theme.positiveTextColor
                         : check.state === "warn" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                    text: modelData + (check ? ": " + check.detail : statusLoader.item && statusLoader.item.busy ? ": checking..." : "")
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    opacity: 0.8
                    font.pointSize: Math.max(7, Kirigami.Theme.defaultFont.pointSize - 1)
                }
                // the fix next to the problem: a source that only needs downloading gets its button right here
                QQC2.Button {
                    readonly property string command: statusLoader.item ? statusLoader.item.fetchCommand(modelData) : ""
                    visible: command !== "" && check && check.state !== "ok"
                    enabled: statusLoader.item && !statusLoader.item.busy
                    text: statusLoader.item ? statusLoader.item.fetchLabel(modelData) : "Download"
                    icon.name: "download"
                    onClicked: statusLoader.item.run(command)
                }
                QQC2.BusyIndicator {
                    visible: statusLoader.item && statusLoader.item.busy && check && check.state !== "ok" && statusLoader.item.fetchCommand(modelData) !== ""
                    running: visible
                    implicitHeight: Kirigami.Units.gridUnit * 1.2; implicitWidth: implicitHeight
                }
            }
        }
    }
    // A greyed explanation that wraps instead of widening the window.
    component Note: QQC2.Label {
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        wrapMode: Text.Wrap
        opacity: 0.7
    }
    component Hours: QQC2.SpinBox {
        textFromValue: function (v) { return v + " h" }
        valueFromText: function (t) { return parseInt(t) || 0 }
    }
    // One row of label style, the same for every layer (country names have the same five under Countries):
    // bold, capitals, letter spacing (with capitals), text opacity, and the dark outline drawn when there is no plate.
    component Pct: QQC2.SpinBox {
        property string label: ""
        from: 0; to: 400; stepSize: 5
        textFromValue: function (v) { return v + " %" }
        valueFromText: function (t) { return parseInt(t) || 0 }
        QQC2.ToolTip.text: label; QQC2.ToolTip.visible: hovered
    }
    component LabelStyle: RowLayout {
        id: style
        property alias bold: boldBox.checked
        property alias caps: capsBox.checked
        property alias letterSpacing: spacingBox.value
        property alias textOpacity: opacityBox.value
        property alias halo: haloBox.value
        property bool plated: false                  // the outline only shows without a plate
        Kirigami.FormData.label: "Label style:"
        QQC2.CheckBox { id: boldBox; text: "Bold" }
        QQC2.CheckBox { id: capsBox; text: "Capitals" }
        QQC2.Label { text: "Spacing"; opacity: 0.8; enabled: capsBox.checked }
        Pct { id: spacingBox; enabled: capsBox.checked; label: "Letter spacing, with capitals (100 % = normal)" }
        QQC2.Label { text: "Opacity"; opacity: 0.8 }
        Pct { id: opacityBox; from: 20; to: 100; label: "Text opacity" }
        QQC2.Label { text: "Outline"; opacity: 0.8; enabled: !style.plated }
        Pct { id: haloBox; to: 300; enabled: !style.plated; label: "Dark outline around the text (0 % = none); not drawn with a plate" }
    }
    component Px: QQC2.SpinBox {
        from: 6; to: 28
        textFromValue: function (v) { return v + " px" }
        valueFromText: function (t) { return parseInt(t) || 10 }
    }

    // #################################################################### Profile and layers
    Group { text: "Profile and layers" }

    // The profile sets the levers that cost CPU and GPU time in one go; changing any of them by hand turns
    // the choice into "Custom". Everything it touches can still be changed below.
    readonly property var profiles: [
        // fps, arcs, quakePulse, volcanoPulse, stormPulse, firePulse, hotspots, borderDetail, satTrack, guardPause, guardPlain
        { name: "High performance", fps: 0, arcs: 2, qp: 3, vp: 1, sp: 3, fp: 3, hot: 1, detail: 1, track: 2, gpause: 85, gplain: 97 },
        { name: "Balanced",         fps: 2, arcs: 0, qp: 3, vp: 1, sp: 3, fp: 3, hot: 2, detail: 0, track: 1, gpause: 70, gplain: 90 },
        { name: "Power saving",     fps: 3, arcs: 3, qp: 1, vp: 1, sp: 1, fp: 1, hot: 3, detail: 0, track: 0, gpause: 50, gplain: 80 },
        { name: "Custom" } ]
    readonly property string leverSig: [animationFps.currentIndex, arcAnimation.currentIndex, quakePulseMode.currentIndex, volcanoPulseMode.currentIndex,
        stormPulseMode.currentIndex, firePulseMode.currentIndex, hotspotMinCount.currentIndex, borderDetail.currentIndex, satTrackLength.currentIndex,
        form.cfg_GuardPause, form.cfg_GuardPlain].join("/")
    function profileSig(p) { return [p.fps, p.arcs, p.qp, p.vp, p.sp, p.fp, p.hot, p.detail, p.track, p.gpause, p.gplain].join("/") }
    property bool applyingProfile: false
    function applyProfile(i) {
        var p = profiles[i];
        if (!p || p.fps === undefined) return;
        applyingProfile = true;
        animationFps.currentIndex = p.fps; arcAnimation.currentIndex = p.arcs;
        quakePulseMode.currentIndex = p.qp; volcanoPulseMode.currentIndex = p.vp; stormPulseMode.currentIndex = p.sp; firePulseMode.currentIndex = p.fp;
        hotspotMinCount.currentIndex = p.hot; borderDetail.currentIndex = p.detail; satTrackLength.currentIndex = p.track;
        form.cfg_GuardPause = p.gpause; form.cfg_GuardPlain = p.gplain;
        applyingProfile = false;
    }
    // Plasma fills the cfg_ values one by one while the page opens; only judge "Custom" once that has settled.
    property bool watchingLevers: false
    Timer { interval: 800; running: true; onTriggered: { form.watchingLevers = true; form.checkProfile(); } }
    function checkProfile() {
        if (watchingLevers && !applyingProfile && profile.currentIndex < 3 && leverSig !== profileSig(profiles[profile.currentIndex])) profile.currentIndex = 3;
    }
    onLeverSigChanged: checkProfile()
    QQC2.ComboBox {
        id: profile
        Kirigami.FormData.label: "Profile:"
        model: form.profiles.map(function (p) { return p.name })
        onActivated: function (i) { form.applyProfile(i) }
    }
    Note { text: ["Smooth: 60 updates a second, packets and glowing lines, every pulse, more hotspot cells, two orbits of satellite track. Load guard only for heavy load.",
                  "20 updates a second, packets on the lines, pulses on news and strong events, 25+ detection hotspot cells, one orbit of track. Load guard at 70 / 90 %.",
                  "10 updates a second, steady lines, pulses only on news, 50+ detection hotspot cells, short track, standard borders. Load guard at 50 / 80 %.",
                  "Your own mix of the settings below."][profile.currentIndex] }
    ColumnLayout {
        Kirigami.FormData.label: "Layers:"
        spacing: 0
        RowLayout { Mirror { twin: quakes; text: "Earthquakes" } Mirror { twin: volcanoes; text: "Volcanoes" } Mirror { twin: storms; text: "Storms" } }
        RowLayout { Mirror { twin: fires; text: "Wildfires" } Mirror { twin: sats; text: "Satellites" } Mirror { twin: launches; text: "Launches" } }
        RowLayout { Mirror { twin: network; text: "Network" } Mirror { twin: timeZones; text: "Time zones" } Mirror { twin: countryNames; text: "Country names" } }
    }
    Note { text: "The same switches as each section's Show box; an unticked layer's section is greyed out below. A layer that is off costs nothing: it is not even loaded." }

    // #################################################################### Map base
    Group { text: "Map base" }

    // ==================================================================== Map
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Map" }
    Source { names: ["Seasonal maps (NASA Blue Marble)", "NASA image server"] }

    QQC2.CheckBox {
        id: seasonal
        Kirigami.FormData.label: "Base map:"
        text: "Follow the seasons (NASA monthly images)"
    }
    QQC2.CheckBox { id: seasonalBlend; enabled: seasonal.checked; text: "Cross-fade between months day by day" }
    RowLayout {
        Kirigami.FormData.label: seasonal.checked ? "Fallback image:" : "Image:"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        QQC2.TextField { id: baseImage; Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 8; Layout.maximumWidth: Kirigami.Units.gridUnit * 26; placeholderText: "/path/to/equirectangular-2x1.jpg" }
        QQC2.Button { icon.name: "document-open"; onClicked: picker.open() }
    }
    // Framing: which part of the world must be on screen, and how it is fitted to the screen's shape
    readonly property var framePresets: [
        { name: "The whole world",                              n: 90, s: -90, w: -180, e: 180 },
        { name: "Without Antarctica (84°N to 58°S)",  n: 84, s: -58, w: -180, e: 180 },
        { name: "Where people live (72°N to 56°S)",   n: 72, s: -56, w: -180, e: 180 },
        { name: "Custom",                                       n: 0,  s: 0,   w: 0,    e: 0 } ]
    function framePresetIndex() {
        for (var i = 0; i < framePresets.length - 1; i++) {
            var f = framePresets[i];
            if (f.n === frameNorth.value && f.s === frameSouth.value && f.w === frameWest.value && f.e === frameEast.value) return i;
        }
        return framePresets.length - 1;
    }
    function degrees(v, plus, minus) { return Math.abs(v) + "° " + (v >= 0 ? plus : minus) }
    function fromDegrees(t, minus) { var v = parseInt(t) || 0; return t.toUpperCase().indexOf(minus) >= 0 ? -Math.abs(v) : v }

    QQC2.ComboBox {
        id: framePreset
        Kirigami.FormData.label: "Show:"
        model: form.framePresets.map(function (f) { return f.name })
        Component.onCompleted: currentIndex = form.framePresetIndex()
        onActivated: function (i) {
            var f = form.framePresets[i];
            if (f.n === 0) return;
            frameNorth.value = f.n; frameSouth.value = f.s; frameWest.value = f.w; frameEast.value = f.e;
        }
    }
    RowLayout {
        Kirigami.FormData.label: "North to south:"
        QQC2.SpinBox {
            id: frameNorth
            from: 45; to: 90
            textFromValue: function (v) { return form.degrees(v, "N", "S") }
            valueFromText: function (t) { return form.fromDegrees(t, "S") }
            onValueModified: framePreset.currentIndex = form.framePresetIndex()
        }
        QQC2.SpinBox {
            id: frameSouth
            from: -90; to: -45
            textFromValue: function (v) { return form.degrees(v, "N", "S") }
            valueFromText: function (t) { return form.fromDegrees(t, "S") }
            onValueModified: framePreset.currentIndex = form.framePresetIndex()
        }
    }
    RowLayout {
        Kirigami.FormData.label: "West to east:"
        QQC2.SpinBox {
            id: frameWest
            from: -180; to: -90; stepSize: 5
            textFromValue: function (v) { return form.degrees(v, "E", "W") }
            valueFromText: function (t) { return form.fromDegrees(t, "W") }
            onValueModified: framePreset.currentIndex = form.framePresetIndex()
        }
        QQC2.SpinBox {
            id: frameEast
            from: 90; to: 180; stepSize: 5
            textFromValue: function (v) { return form.degrees(v, "E", "W") }
            valueFromText: function (t) { return form.fromDegrees(t, "W") }
            onValueModified: framePreset.currentIndex = form.framePresetIndex()
        }
    }
    QQC2.ComboBox {
        id: fillMode
        Kirigami.FormData.label: "Fit to screen:"
        model: ["Stretch to fill", "Fit, true proportions", "Crop, true proportions"]
    }
    Note {
        text: ["Stretch: all of the chosen area fills the screen; shapes get taller or wider as needed.",
               "Fit: all of the chosen area at true proportions; spare space shows more map, or bars.",
               "Crop: true proportions filling the screen, trimmed where it does not fit."][fillMode.currentIndex]
    }
    Amount {
        Kirigami.FormData.label: "Dim the imagery:"
        to: 80
        value: form.cfg_MapDim
        onValueChanged: form.cfg_MapDim = value
    }
    QQC2.ComboBox {
        id: hintCorner
        Kirigami.FormData.label: "Notices:"
        model: ["Bottom right corner", "Bottom left corner", "Top right corner", "Top left corner", "Never show on the desktop"]
    }
    Hours { id: staleHours; Kirigami.FormData.label: "Complain after:"; from: 0; to: 168 }
    Note { text: "Every feed keeps its last good data: a failed fetch is retried quietly and the map keeps drawing. A notice appears only when a source has had no successful update for this many hours (0 = at once). The Status section always shows the full detail." }
    QQC2.TextField {
        id: dataDir
        Kirigami.FormData.label: "Data folder:"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        placeholderText: "~/.local/share/livemap (default)"
    }

    // ============================================================ Day and night
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Day and night" }
    Source { names: ["City lights (NASA Black Marble)", "Cloud image (matteason.co.uk)", "Cloud stitching (NASA GIBS, EUMETView)"] }

    QQC2.CheckBox { id: dayNight; Kirigami.FormData.label: "Sun:"; text: "Day and night" }
    Amount {
        Kirigami.FormData.label: "Night darkness:"
        enabled: dayNight.checked
        from: 20
        value: form.cfg_NightDarkness
        onValueChanged: form.cfg_NightDarkness = value
    }
    Amount {
        Kirigami.FormData.label: "Dusk band:"
        enabled: dayNight.checked
        from: 2; to: 30; suffix: "° wide"
        value: form.cfg_Twilight
        onValueChanged: form.cfg_Twilight = value
    }
    QQC2.CheckBox { id: cityLights; Kirigami.FormData.label: "Lights:"; enabled: dayNight.checked; text: "City lights on the night side" }
    Amount {
        Kirigami.FormData.label: "Lights brightness:"
        enabled: dayNight.checked && cityLights.checked
        from: 10
        value: form.cfg_LightsBrightness
        onValueChanged: form.cfg_LightsBrightness = value
    }
    QQC2.CheckBox { id: lightsGpu; enabled: dayNight.checked && cityLights.checked; text: "Sharper lights through a GPU mask" }
    Note { visible: lightsGpu.checked; text: "Experimental: untick if the lights vanish." }

    QQC2.CheckBox { id: clouds; Kirigami.FormData.label: "Sky:"; text: "Live clouds" }
    QQC2.ComboBox {
        id: cloudSource
        Kirigami.FormData.label: "Cloud source:"
        enabled: clouds.checked
        model: ["Ready-made image; stitch from satellites if it fails", "Always stitch from the satellites", "Ready-made image only"]
    }
    Note { text: "Ready-made: one 5 MB image every 3 hours from clouds.matteason.co.uk. Stitched: the helper fetches infrared images from five geostationary satellites (GOES-East, GOES-West and Himawari via NASA GIBS; Meteosat 0° and Indian Ocean via EUMETView, all public, no key), lays them side by side and turns cloud-top brightness into cloud cover - about 6 MB and a few seconds every 3 hours. A satellite that fails keeps its last picture, so an outage of one source only stales one region. With python3-pillow installed the stitched image is 2048 px wide; without it 1024 px, in pure Python." }
    Amount {
        Kirigami.FormData.label: "Cloud opacity:"
        enabled: clouds.checked
        from: 10
        value: form.cfg_CloudOpacity
        onValueChanged: form.cfg_CloudOpacity = value
    }

    // #################################################################### Geographic layers
    Group { text: "Geographic layers" }

    // ============================================================== Countries
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Countries" }
    Source { names: ["Borders (Natural Earth)"] }

    QQC2.CheckBox { id: borders; Kirigami.FormData.label: "Show:"; text: "Country borders (Natural Earth)" }
    QQC2.CheckBox { id: coast; enabled: borders.checked; text: "Coastlines" }
    QQC2.CheckBox { id: stateLines; enabled: borders.checked; text: "States and provinces" }
    QQC2.ComboBox {
        id: borderDetail
        Kirigami.FormData.label: "Detail:"
        enabled: borders.checked
        model: ["Standard (1:110 million)", "Detailed (1:50 million, for 4K)"]
    }
    KQuickControls.ColorButton { id: borderColor; Kirigami.FormData.label: "Line colour:"; enabled: borders.checked; showAlphaChannel: false; dialogTitle: "Border colour" }
    Amount {
        Kirigami.FormData.label: "Line opacity:"
        enabled: borders.checked
        from: 5
        value: form.cfg_BorderOpacity
        onValueChanged: form.cfg_BorderOpacity = value
    }
    Amount {
        Kirigami.FormData.label: "Line thickness:"
        enabled: borders.checked
        from: 30; to: 400
        value: form.cfg_BorderWidth
        onValueChanged: form.cfg_BorderWidth = value
    }
    QQC2.CheckBox { id: countryNames; Kirigami.FormData.label: "Labels:"; enabled: borders.checked; text: "Country names" }
    RowLayout {
        Kirigami.FormData.label: "Names:"
        enabled: borders.checked && countryNames.checked
        QQC2.ComboBox { id: nameDensity; model: ["Only the largest", "Most countries", "All that fit"] }
        Px { id: nameSize; from: 5; to: 40 }
    }
    Note { text: "The largest countries are printed a quarter bigger than the size chosen." }
    LabelStyle { id: nameStyle; enabled: borders.checked && countryNames.checked; plated: namePlate.checked }
    RowLayout {
        Kirigami.FormData.label: "Name text:"
        enabled: borders.checked && countryNames.checked
        QQC2.CheckBox { id: namePlate; text: "Plate" }
        QQC2.CheckBox { id: nameFollows; text: "Text follows the line colour" }
        KQuickControls.ColorButton { id: nameTextColor; enabled: !nameFollows.checked; showAlphaChannel: false; dialogTitle: "Country name colour" }
    }

    // ============================================================== Time zones
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Time zones" }
    Source { names: ["Borders (Natural Earth)"] }
    QQC2.CheckBox { id: timeZones; Kirigami.FormData.label: "Show:"; text: "Time zone outlines (Natural Earth)" }
    Note { text: "The zone boundaries as drawn on the Natural Earth time zone map, with the UTC offset written in each zone that is wide enough. Part of the border download." }
    KQuickControls.ColorButton { id: zoneColor; Kirigami.FormData.label: "Line colour:"; enabled: timeZones.checked; showAlphaChannel: false; dialogTitle: "Time zone line colour" }
    Amount {
        Kirigami.FormData.label: "Line opacity:"
        enabled: timeZones.checked
        from: 5
        value: form.cfg_ZoneOpacity
        onValueChanged: form.cfg_ZoneOpacity = value
    }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: timeZones.checked
        QQC2.CheckBox { id: zoneLabels; text: "UTC offsets" }
        Px { id: zoneLabelSize; enabled: zoneLabels.checked; from: 6; to: 24 }
    }
    LabelStyle { id: zoneStyle; enabled: timeZones.checked && zoneLabels.checked; plated: false }

    // #################################################################### Natural events
    Group { text: "Natural events" }

    // ============================================================ Earthquakes
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Earthquakes" }
    Source { names: ["Earthquake feed (USGS)", "Plate boundaries (PB2002)"] }

    QQC2.CheckBox { id: quakes; Kirigami.FormData.label: "Show:"; text: "Earthquakes (USGS)" }
    QQC2.ComboBox {
        id: quakeFeed
        Kirigami.FormData.label: "Feed:"
        enabled: quakes.checked
        model: ["Magnitude 2.5+, past day", "Magnitude 4.5+, past day", "Significant, past week"]
    }
    KQuickControls.ColorButton { id: quakeColor; Kirigami.FormData.label: "Ring colour:"; enabled: quakes.checked; showAlphaChannel: false; dialogTitle: "Earthquake ring colour" }
    Amount {
        Kirigami.FormData.label: "Ring size:"
        enabled: quakes.checked
        from: 40; to: 250
        value: form.cfg_QuakeSize
        onValueChanged: form.cfg_QuakeSize = value
    }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: quakes.checked
        QQC2.ComboBox { id: quakeLabels; model: ["None", "Magnitude", "Magnitude, place and age"] }
        QQC2.ComboBox { id: quakeLabelMin; enabled: quakeLabels.currentIndex > 0; model: ["for every quake", "from magnitude 5", "from magnitude 6"] }
        Px { id: quakeLabelSize; enabled: quakeLabels.currentIndex > 0; from: 6; to: 24 }
    }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: quakes.checked && quakeLabels.currentIndex > 0
        QQC2.CheckBox { id: quakePlate; text: "Plate" }
        QQC2.CheckBox { id: quakeFollows; text: "Text follows the ring colour" }
        KQuickControls.ColorButton { id: quakeTextColor; enabled: !quakeFollows.checked; showAlphaChannel: false; dialogTitle: "Earthquake label colour" }
    }
    LabelStyle { id: quakeStyle; enabled: quakes.checked && quakeLabels.currentIndex > 0; plated: quakePlate.checked }
    QQC2.ComboBox {
        id: quakePulseMode
        Kirigami.FormData.label: "Pulse:"
        enabled: quakes.checked
        model: form.pulseChoices
    }
    RowLayout {
        Kirigami.FormData.label: "Significant:"
        enabled: quakes.checked && quakePulseMode.currentIndex >= 2
        QQC2.Label { text: "from magnitude" }
        QQC2.SpinBox {
            id: quakePulseMag
            from: 30; to: 90; stepSize: 1
            textFromValue: function (v) { return (v / 10).toFixed(1) }
            valueFromText: function (t) { return Math.round((parseFloat(t) || 5.5) * 10) }
        }
    }
    Note { text: "Newly reported = it happened less than the 'Newly reported' hours ago (under Ageing and pulses). Quakes age from the moment they happened." }
    QQC2.CheckBox { id: plates; Kirigami.FormData.label: "Fault lines:"; text: "Tectonic plate boundaries (PB2002)" }
    KQuickControls.ColorButton { id: plateLineColor; Kirigami.FormData.label: "Line colour:"; enabled: plates.checked; showAlphaChannel: false; dialogTitle: "Plate boundary colour" }
    Amount {
        Kirigami.FormData.label: "Line opacity:"
        enabled: plates.checked
        from: 5
        value: form.cfg_PlateLineOpacity
        onValueChanged: form.cfg_PlateLineOpacity = value
    }
    Amount {
        Kirigami.FormData.label: "Line thickness:"
        enabled: plates.checked
        from: 30; to: 400
        value: form.cfg_PlateLineWidth
        onValueChanged: form.cfg_PlateLineWidth = value
    }
    Note { text: "The boundaries between the tectonic plates, where most earthquakes and volcanoes sit. Still lines under the borders; they cost nothing while idle." }

    // ============================================================== Volcanoes
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Volcanoes" }
    Source { names: ["Volcanoes (Smithsonian / USGS)", "Eruption database (Smithsonian)", "Weekly report page (Smithsonian)", "Volcano alert levels (USGS)"] }

    QQC2.CheckBox { id: volcanoes; Kirigami.FormData.label: "Show:"; text: "Weekly report and USGS alert levels" }
    Note { text: "The Smithsonian / USGS Weekly Volcanic Activity Report comes out every Wednesday ('New' there means an eruption after at least three months of quiet). US volcanoes also carry the USGS alert level (Advisory, Watch, Warning), checked every hour, with the date the level was raised where USGS provides it." }
    KQuickControls.ColorButton { id: volcanoColor; Kirigami.FormData.label: "Colour:"; enabled: volcanoes.checked; showAlphaChannel: false; dialogTitle: "Volcano colour" }
    QQC2.CheckBox { id: volcanoAlertColors; enabled: volcanoes.checked; text: "Colour by level (yellow, orange, red)" }
    Note { text: "One scale for every volcano: yellow = active (in the weekly report, or USGS Advisory), orange = USGS Watch or a 'New' eruption in the report, red = USGS Warning. Untick for the single colour above." }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: volcanoes.checked
        QQC2.ComboBox { id: volcanoLabels; model: ["None", "New eruptions only", "All"] }
        Px { id: volcanoLabelSize; from: 6; to: 24 }
    }
    QQC2.CheckBox { id: volcanoDetail; enabled: volcanoes.checked && volcanoLabels.currentIndex > 0; text: "Add how long it has been above normal" }
    Note { text: "Label: the name, then how long the volcano has been above normal: USGS's date for a US alert level, else the eruption start date from the Smithsonian database. Nothing when neither is known. Colour, a bolder triangle and the pulse say the rest." }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: volcanoes.checked && volcanoLabels.currentIndex > 0
        QQC2.CheckBox { id: volcanoPlate; text: "Plate" }
        QQC2.CheckBox { id: volcanoFollows; text: "Text follows the volcano colour" }
        KQuickControls.ColorButton { id: volcanoTextColor; enabled: !volcanoFollows.checked; showAlphaChannel: false; dialogTitle: "Volcano label colour" }
    }
    LabelStyle { id: volcanoStyle; enabled: volcanoes.checked && volcanoLabels.currentIndex > 0; plated: volcanoPlate.checked }
    QQC2.ComboBox {
        id: volcanoPulseMode
        Kirigami.FormData.label: "Pulse:"
        enabled: volcanoes.checked
        model: form.pulseChoices
    }
    Note { text: "Newly reported = it appeared, or its level changed, less than the 'Newly reported' hours ago: the default, so a volcano pulses when there is news and then sits steady. Significant = orange and red, if you want those to keep pulsing. A volcano ages once it drops out of the report." }

    // ================================================================= Storms
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Storms" }
    Source { names: ["Storms (GDACS)", "Storms, secondary (NHC)"] }

    QQC2.CheckBox { id: storms; Kirigami.FormData.label: "Show:"; text: "Tropical storms with forecast track" }
    Note { text: "GDACS worldwide first (it is often slow: 20 s and a retry are allowed); when it does not answer, the US National Hurricane Center's list, forecast track and cone take over for the Atlantic and the eastern and central Pacific. A storm keeps its identity across the two." }
    RowLayout {
        Kirigami.FormData.label: "Marker:"
        enabled: storms.checked
        QQC2.ComboBox { id: stormMarkerStyle; model: ["Drawn symbol, coloured by intensity", "Icon set with category number"] }
        Px { id: stormIconSize; enabled: stormMarkerStyle.currentIndex === 1; from: 10; to: 64 }
    }
    RowLayout {
        Kirigami.FormData.label: "Icon halo:"
        enabled: storms.checked && stormMarkerStyle.currentIndex === 1
        QQC2.ComboBox { id: stormIconTheme; model: ["Dark (for satellite maps)", "Light (for pale maps)"] }
    }
    Note { text: "Icon set: depression D, tropical storm S, hurricane 1-5, dashed P once a storm has left the feed; mirrored south of the equator, colour by category. The colour below still drives track, cone and label." }
    KQuickControls.ColorButton { id: stormColor; Kirigami.FormData.label: "Colour:"; enabled: storms.checked; showAlphaChannel: false; dialogTitle: "Storm colour" }
    QQC2.CheckBox { id: stormIntensityColors; enabled: storms.checked; text: "Colour by intensity" }
    Note { text: "The scale used on storm-tracking sites: not tropical (disturbance, remnant low) purple, depression blue, tropical storm green, then category 1 to 5 yellow, orange, red, pink, magenta. Untick for the one colour above." }
    QQC2.CheckBox { id: stormTrackColors; enabled: storms.checked && stormIntensityColors.checked; text: "Track and forecast in the intensity at each fix" }
    Note { text: "Each piece of the track takes the colour of the wind the storm had reached there, so its history reads at a glance: a fix every 6 hours from NHC's best track in the Atlantic and eastern Pacific, and elsewhere the positions this wallpaper has itself seen since it first met the storm. Forecast points use the forecast wind." }
    QQC2.CheckBox { id: stormOriginMark; enabled: storms.checked; text: "Mark where the storm was first fixed, with how long ago" }
    QQC2.CheckBox { id: stormCone; enabled: storms.checked; text: "Forecast cone" }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: storms.checked
        QQC2.ComboBox { id: stormLabels; model: ["None", "Name", "Name, type and wind"] }
        QQC2.ComboBox { id: stormUnits; enabled: stormLabels.currentIndex === 2; model: ["km/h", "mph", "knots"] }
        Px { id: stormLabelSize; from: 6; to: 24 }
    }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: storms.checked && stormLabels.currentIndex > 0
        QQC2.CheckBox { id: stormPlate; text: "Plate" }
        QQC2.CheckBox { id: stormFollows; text: "Text follows the storm colour" }
        KQuickControls.ColorButton { id: stormTextColor; enabled: !stormFollows.checked; showAlphaChannel: false; dialogTitle: "Storm label colour" }
    }
    LabelStyle { id: stormStyle; enabled: storms.checked && stormLabels.currentIndex > 0; plated: stormPlate.checked }
    QQC2.ComboBox {
        id: stormPulseMode
        Kirigami.FormData.label: "Pulse:"
        enabled: storms.checked
        model: form.pulseChoices
    }
    Note { text: "Newly reported = GDACS started tracking it less than the 'Newly reported' hours ago; significant = hurricane strength (category 1 and up). A storm ages from its latest advisory and greys out once GDACS stops tracking it." }

    // ============================================================== Wildfires
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Wildfires" }
    Source { names: ["Wildfires (GDACS)", "Fire hotspots (NASA FIRMS)"] }

    QQC2.CheckBox { id: fires; Kirigami.FormData.label: "Show:"; text: "Wildfires" }
    QQC2.ComboBox {
        id: fireSource
        Kirigami.FormData.label: "From:"
        enabled: fires.checked
        model: ["GDACS fire events", "NASA satellite hotspots (FIRMS)", "Both"]
    }
    Note { text: "GDACS: one flame per fire event it rates (green, orange, red) with the burned area; updated daily. NASA FIRMS: what the MODIS satellites detected burning in the last 24 hours, clustered by the helper into half-degree cells (about 3 MB every 3 hours, no key); a smaller flame in the fire colour, sized by fire power." }
    RowLayout {
        Kirigami.FormData.label: "GDACS only:"
        enabled: fires.checked && fireSource.currentIndex !== 1
        QQC2.ComboBox { id: fireMinLevel; model: ["All levels", "Orange and red", "Red only"] }
        QQC2.ComboBox { id: fireMinArea; model: ["Any size", "1 000 ha and up", "10 000 ha and up", "50 000 ha and up"] }
    }
    QQC2.ComboBox {
        id: hotspotMinCount
        Kirigami.FormData.label: "Hotspots:"
        enabled: fires.checked && fireSource.currentIndex !== 0
        model: ["3+ detections per cell", "10+ detections per cell", "25+ detections per cell", "50+ detections per cell"]
    }
    Note { text: "GDACS rates most fires green (it scores humanitarian impact, not size), so a GDACS flame's size follows the burned area and only its colour the level. A hotspot cell with 25+ detections or 1 GW of fire power counts as significant: it is labelled and pulses." }
    KQuickControls.ColorButton { id: fireColor; Kirigami.FormData.label: "Colour:"; enabled: fires.checked; showAlphaChannel: false; dialogTitle: "Wildfire colour" }
    QQC2.CheckBox { id: fireAlertColors; enabled: fires.checked; text: "GDACS colours by alert level (green, orange, red)" }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: fires.checked
        QQC2.ComboBox { id: fireLabels; model: ["None", "Orange and red only", "All"] }
        Px { id: fireLabelSize; from: 6; to: 24 }
    }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: fires.checked && fireLabels.currentIndex > 0
        QQC2.CheckBox { id: firePlate; text: "Plate" }
        QQC2.CheckBox { id: fireFollows; text: "Text follows the fire colour" }
        KQuickControls.ColorButton { id: fireTextColor; enabled: !fireFollows.checked; showAlphaChannel: false; dialogTitle: "Wildfire label colour" }
    }
    LabelStyle { id: fireStyle; enabled: fires.checked && fireLabels.currentIndex > 0; plated: firePlate.checked }
    QQC2.ComboBox {
        id: firePulseMode
        Kirigami.FormData.label: "Pulse:"
        enabled: fires.checked
        model: form.pulseChoices
    }
    Note { text: "Label: place, burned area, how long GDACS has listed it. Newly reported = listed, or level changed, less than the 'Newly reported' hours ago; significant = orange or red. A fire ages out once GDACS drops it." }

    // #################################################################### Space
    Group { text: "Space" }

    // ============================================================= Satellites
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Satellites" }
    Source { names: ["Satellite elements (CelesTrak)"] }
    QQC2.CheckBox { id: sats; Kirigami.FormData.label: "Show:"; text: "Satellites and their ground track" }
    RowLayout {
        enabled: sats.checked
        QQC2.CheckBox { id: satIss; text: "ISS" }
        QQC2.CheckBox { id: satHubble; text: "Hubble" }
        QQC2.CheckBox { id: satTiangong; text: "Tiangong" }
    }
    Note { text: "Orbital elements from CelesTrak, refreshed every six hours, propagated by the helper (Kepler + J2: within a few km of the full SGP4 model for these low orbits). The marker moves along a precomputed track once a second; the dashed line is the ground track from 15 minutes ago to 100 minutes ahead." }
    RowLayout {
        Kirigami.FormData.label: "Marker:"
        enabled: sats.checked
        QQC2.ComboBox { id: satMarkerStyle; model: ["Symbol in the colour below", "Picture of the spacecraft"] }
        Px { id: satPictureSize; enabled: satMarkerStyle.currentIndex === 1; from: 8; to: 96 }
    }
    Note { text: "Pictures: the ISS, Hubble and Tiangong artwork from the images folder, sized in px on a 1920-wide screen (scaled up on bigger ones). The colour still applies to the track, the ring and the label." }
    KQuickControls.ColorButton { id: satColor; Kirigami.FormData.label: "Colour:"; enabled: sats.checked; showAlphaChannel: false; dialogTitle: "Satellite colour" }
    RowLayout {
        Kirigami.FormData.label: "Track:"
        enabled: sats.checked
        QQC2.CheckBox { id: satTrack; text: "Ground track" }
        QQC2.ComboBox { id: satTrackLength; enabled: satTrack.checked; model: ["Next 30 minutes", "One orbit ahead", "Two orbits ahead"] }
    }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: sats.checked
        QQC2.ComboBox { id: satLabels; model: ["None", "Name", "Name and altitude"] }
        Px { id: satLabelSize; from: 6; to: 24 }
    }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: sats.checked && satLabels.currentIndex > 0
        QQC2.CheckBox { id: satPlate; text: "Plate" }
        QQC2.CheckBox { id: satFollows; text: "Text follows the satellite colour" }
        KQuickControls.ColorButton { id: satTextColor; enabled: !satFollows.checked; showAlphaChannel: false; dialogTitle: "Satellite label colour" }
    }
    LabelStyle { id: satStyle; enabled: sats.checked && satLabels.currentIndex > 0; plated: satPlate.checked }

    // =============================================================== Launches
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Launches" }
    Source { names: ["Launches (The Space Devs)"] }
    QQC2.CheckBox { id: launches; Kirigami.FormData.label: "Show:"; text: "Upcoming rocket launches" }
    QQC2.ComboBox {
        id: launchWindow
        Kirigami.FormData.label: "Within:"
        enabled: launches.checked
        model: ["24 hours", "48 hours", "72 hours", "A week"]
    }
    Note { text: "Launch Library 2 (The Space Devs), fetched hourly: a rocket on the pad with a countdown, one per pad (the earliest). Flight paths are not published as data, so none are drawn. A launch pulses in its last hour and stays half an hour after lift-off." }
    RowLayout {
        Kirigami.FormData.label: "Marker:"
        enabled: launches.checked
        QQC2.ComboBox { id: launchMarkerStyle; model: ["Drawn rocket in the colour below", "Picture: rocket on the pad, lifting off after T-0"] }
        Px { id: launchPictureSize; enabled: launchMarkerStyle.currentIndex === 1; from: 8; to: 96 }
    }
    Note { text: "Picture height in px on a 1920-wide screen (scaled up on bigger ones)." }
    KQuickControls.ColorButton { id: launchColor; Kirigami.FormData.label: "Colour:"; enabled: launches.checked; showAlphaChannel: false; dialogTitle: "Launch marker colour" }
    RowLayout {
        Kirigami.FormData.label: "Labels:"
        enabled: launches.checked
        QQC2.ComboBox { id: launchLabels; model: ["None", "Countdown", "Rocket, mission and countdown"] }
        Px { id: launchLabelSize; from: 6; to: 24 }
    }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: launches.checked && launchLabels.currentIndex > 0
        QQC2.CheckBox { id: launchPlate; text: "Plate" }
        QQC2.CheckBox { id: launchFollows; text: "Text follows the marker colour" }
        KQuickControls.ColorButton { id: launchTextColor; enabled: !launchFollows.checked; showAlphaChannel: false; dialogTitle: "Launch label colour" }
    }
    LabelStyle { id: launchStyle; enabled: launches.checked && launchLabels.currentIndex > 0; plated: launchPlate.checked }
    QQC2.CheckBox { id: launchPulse; Kirigami.FormData.label: "Pulse:"; enabled: launches.checked; text: "In the last hour before lift-off" }

    // #################################################################### Network and connectivity
    Group { text: "Network and connectivity" }

    // ======================================================== Network activity
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Network activity" }
    Source { names: ["Connections (ss)", "GeoIP database (DB-IP)"] }

    QQC2.CheckBox { id: network; Kirigami.FormData.label: "Show:"; text: "Arcs to the places this computer is connected to" }
    Note { text: "Read locally from the kernel's connection table and an offline GeoIP file; nothing about your connections leaves this machine." }
    Loader {
        id: citySearch
        Kirigami.FormData.label: "Home city:"
        enabled: network.checked
        source: "CitySearch.qml"
        onLoaded: {
            item.query = form.cfg_HomeCity;
            item.picked.connect(function (lat, lon, name) {
                homeLat.text = String(lat); homeLon.text = String(lon); form.cfg_HomeCity = name;
            });
        }
    }
    Note { text: statusLoader.status === Loader.Error || citySearch.status === Loader.Error ? "The city search could not be loaded; type the coordinates below." : "Searched offline in Natural Earth's list of about 7 000 towns and cities (part of the border download). Pick one to fill in the coordinates, or type them yourself." }
    RowLayout {
        Kirigami.FormData.label: "Home:"
        enabled: network.checked
        QQC2.TextField { id: homeLat; Layout.preferredWidth: Kirigami.Units.gridUnit * 8; placeholderText: "latitude, e.g. 52.37"; validator: DoubleValidator { bottom: -90; top: 90; decimals: 4; locale: "C" } }
        QQC2.TextField { id: homeLon; Layout.preferredWidth: Kirigami.Units.gridUnit * 8; placeholderText: "longitude, e.g. 4.90"; validator: DoubleValidator { bottom: -180; top: 180; decimals: 4; locale: "C" } }
    }
    QQC2.SpinBox {
        id: netInterval
        Kirigami.FormData.label: "Refresh every:"
        enabled: network.checked
        from: 3; to: 300
        textFromValue: function (v) { return v + " s" }
        valueFromText: function (t) { return parseInt(t) }
    }
    QQC2.SpinBox {
        id: netMaxPlaces
        Kirigami.FormData.label: "At most:"
        enabled: network.checked
        from: 1; to: 200
        textFromValue: function (v) { return v + " places" }
        valueFromText: function (t) { return parseInt(t) || 1 }
    }
    KQuickControls.ColorButton { id: arcColor; Kirigami.FormData.label: "Arc colour:"; enabled: network.checked; showAlphaChannel: false; dialogTitle: "Arc colour" }
    QQC2.CheckBox { id: arcGlow; enabled: network.checked; text: "Soft glow around the lines" }
    Amount {
        Kirigami.FormData.label: "Line thickness:"
        enabled: network.checked
        from: 30; to: 400
        value: form.cfg_ArcWidth
        onValueChanged: form.cfg_ArcWidth = value
    }
    QQC2.ComboBox {
        id: arcAnimation
        Kirigami.FormData.label: "Animation:"
        enabled: network.checked
        model: ["Packets travel along the lines", "Lines pulse with a soft glow", "Both", "None (steady lines)"]
    }
    Amount {
        Kirigami.FormData.label: "Animation speed:"
        enabled: network.checked && arcAnimation.currentIndex !== 3
        from: 20; to: 400
        value: form.cfg_PacketSpeed
        onValueChanged: form.cfg_PacketSpeed = value
    }
    QQC2.CheckBox { id: netLabels; Kirigami.FormData.label: "Labels:"; enabled: network.checked; text: "Name the places" }
    QQC2.CheckBox { id: netShowProcess; enabled: network.checked && netLabels.checked; text: "Also name the program" }
    Note { visible: netShowProcess.checked; text: "Untick before sharing your screen." }
    QQC2.CheckBox { id: showLatency; enabled: network.checked && netLabels.checked; text: "Also show the round-trip time (TCP only)" }
    QQC2.CheckBox { id: flagFastRtt; enabled: network.checked && netLabels.checked && showLatency.checked; text: "Flag round trips too fast for the distance" }
    QQC2.CheckBox { id: proxyNote; enabled: network.checked && netLabels.checked && showLatency.checked && flagFastRtt.checked; text: "Say so under the home ring when latency is hidden" }
    Note { text: "If most round trips are too fast (VPN, proxy), latency is hidden and, with the last box ticked, a note explains why." }
    Px { id: labelSize; Kirigami.FormData.label: "Label size:"; enabled: network.checked && netLabels.checked; from: 7; to: 28 }
    RowLayout {
        Kirigami.FormData.label: "Label text:"
        enabled: network.checked && netLabels.checked
        QQC2.CheckBox { id: netPlate; text: "Plate" }
        QQC2.Label { text: "Text colour" }
        KQuickControls.ColorButton { id: netTextColor; showAlphaChannel: false; dialogTitle: "Network label colour" }
    }
    LabelStyle { id: netStyle; enabled: network.checked && netLabels.checked; plated: netPlate.checked }
    RowLayout {
        Kirigami.FormData.label: "Closed connections:"
        enabled: network.checked
        QQC2.Label { text: "Fade over" }
        QQC2.SpinBox {
            id: netLinger
            from: 0; to: 900; stepSize: 10
            textFromValue: function (v) { return v === 0 ? "0 s (vanish)" : v + " s" }
            valueFromText: function (t) { return parseInt(t) || 0 }
        }
        KQuickControls.ColorButton { id: closedColor; showAlphaChannel: false; dialogTitle: "Colour of closed connections" }
    }
    RowLayout {
        Kirigami.FormData.label: "First-time places:"
        enabled: network.checked
        QQC2.Label { text: "Highlight for" }
        QQC2.SpinBox {
            id: newWindow
            from: 5; to: 1440; stepSize: 5
            textFromValue: function (v) { return v + " min" }
            valueFromText: function (t) { return parseInt(t) || 60 }
        }
        KQuickControls.ColorButton { id: newColor; showAlphaChannel: false; dialogTitle: "Colour of places never seen before" }
    }

    // #################################################################### Global settings
    Group { text: "Global settings" }

    // ================================================================== Units
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Units" }
    QQC2.ComboBox {
        id: distanceUnits
        Kirigami.FormData.label: "Distance:"
        model: ["Kilometres (areas in hectares)", "Miles (areas in acres)", "Nautical miles"]
    }
    Note { text: "Satellite altitudes and burned areas. Storm wind speed has its own choice under Storms." }

    // ============================================================ Label styling
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Markers and labels" }
    Amount {
        Kirigami.FormData.label: "Marker size:"
        from: 40; to: 250
        value: form.cfg_MarkerScale
        onValueChanged: form.cfg_MarkerScale = value
    }
    Note { text: "Scales every event marker at once: quake rings, volcano triangles, storm symbols, flames, spacecraft and launch pictures. Each kind also has its own size in its section." }

    Note { text: "Event labels (network, storms, wildfires, earthquakes, volcanoes) are drawn above every layer and never over each other; a label flips sides or moves to stay on the screen. Country names are part of the map and stay underneath. Each element chooses its own plate and text colour above; the plate colour and the opacities are shared." }
    QQC2.ComboBox {
        id: labelLines
        Kirigami.FormData.label: "Layout:"
        model: ["One line", "Name above the details", "Automatic: two lines where space is tight"]
    }
    Note { text: "Two lines put the name or place on top and what happened (magnitude, category, latency, date) underneath. Automatic keeps one line where it fits and switches a label to two lines when the wide form would run off the screen or into a neighbour." }
    KQuickControls.ColorButton { id: plateColor; Kirigami.FormData.label: "Plate colour:"; showAlphaChannel: false; dialogTitle: "Plate colour" }
    Amount {
        Kirigami.FormData.label: "Plate opacity:"
        from: 10
        value: form.cfg_PlateOpacity
        onValueChanged: form.cfg_PlateOpacity = value
    }
    Amount {
        Kirigami.FormData.label: "Text opacity:"
        from: 20
        value: form.cfg_TextOpacity
        onValueChanged: form.cfg_TextOpacity = value
    }

    // ===================================================== Ageing and pulses
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Ageing and pulses" }

    Note { text: "Every event has the same life: it pulses while newly reported, sits steady while it is current, then drifts towards the aged colour and is finally removed. What counts as current differs: a quake's age is its time since it happened, a storm's since its last advisory, a volcano's since it dropped out of the weekly report." }
    Hours { id: pulseNewHours; Kirigami.FormData.label: "Newly reported:"; from: 0; to: 168 }
    Note { text: "For this long after an event first appears it counts as newly reported (each element chooses whether newly reported, significant, both or nothing pulses)." }
    RowLayout {
        Kirigami.FormData.label: "Pulse rings:"
        QQC2.Label { text: "Expand over" }
        QQC2.SpinBox {
            id: pulseDuration
            from: 500; to: 8000; stepSize: 100
            textFromValue: function (v) { return (v / 1000).toFixed(1) + " s" }
            valueFromText: function (t) { return Math.round((parseFloat(t) || 2.8) * 1000) }
        }
        QQC2.Label { text: "every" }
        QQC2.SpinBox {
            id: pulsePeriod
            from: 1; to: 60
            textFromValue: function (v) { return v + " s" }
            valueFromText: function (t) { return parseInt(t) || 5 }
        }
    }
    QQC2.CheckBox { id: ageFade; Kirigami.FormData.label: "Old events:"; text: "Fade towards a colour as they age" }
    RowLayout {
        Kirigami.FormData.label: "Ageing:"
        enabled: ageFade.checked
        QQC2.Label { text: "Starts after" }
        Hours { id: ageStart; from: 0; to: 240 }
        QQC2.Label { text: "done at" }
        Hours { id: ageEnd; from: 1; to: 720 }
    }
    KQuickControls.ColorButton { id: agedColor; Kirigami.FormData.label: "Aged colour:"; enabled: ageFade.checked; showAlphaChannel: false; dialogTitle: "Colour of aged events" }
    Note { text: "Volcanoes and storms that have left their feed are removed once fully aged. Closed network connections have their own fade under This computer." }

    // ================================================== Performance and power
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Performance and power" }

    QQC2.ComboBox {
        id: animationFps
        Kirigami.FormData.label: "Animations update:"
        model: ["60 times a second (smoothest)", "30 times a second", "20 times a second", "10 times a second (lightest)"]
    }
    QQC2.CheckBox { id: guardEnabled; Kirigami.FormData.label: "Load guard:"; text: "Step back when the computer is busy" }
    RowLayout {
        Kirigami.FormData.label: "Thresholds:"
        enabled: guardEnabled.checked
        QQC2.Label { text: "pause animations above" }
        QQC2.SpinBox {
            id: guardPause
            from: 20; to: 100
            value: form.cfg_GuardPause
            onValueModified: form.cfg_GuardPause = value
            textFromValue: function (v) { return v + " %" }
            valueFromText: function (t) { return parseInt(t) || 70 }
        }
    }
    RowLayout {
        enabled: guardEnabled.checked
        QQC2.Label { text: "live layers off above" }
        QQC2.SpinBox {
            id: guardPlain
            from: 20; to: 100
            value: form.cfg_GuardPlain
            onValueModified: form.cfg_GuardPlain = value
            textFromValue: function (v) { return v + " %" }
            valueFromText: function (t) { return parseInt(t) || 90 }
        }
    }
    Source { names: ["Power and load"] }
    Note { text: "CPU busy % is read from /proc/stat; GPU busy % from the driver where it offers one (AMD: sysfs, NVIDIA: nvidia-smi). Intel exposes no busy figure without root, so its GPU clock at the top of its range stands in for 'busy'; with no GPU reading at all the CPU alone decides. The higher of the two counts. A level is entered after two busy polls (40 s) and left after three quiet ones (a minute), so a spike does not flap the map. A game or a render pins the GPU, so it is caught either way; the corner notice says when the guard is on." }
    QQC2.CheckBox { id: cacheStill; text: "Render the still part of the map once and reuse it" }
    Note { text: "Untick only if the map goes blank." }
    QQC2.ComboBox {
        id: onBattery
        Kirigami.FormData.label: "On battery:"
        model: ["Keep everything running", "Pause animations, check connections once a minute", "Plain map only"]
    }
    Note { text: "With no animation running, the desktop is only redrawn when data changes, which costs next to nothing. Animations are what cost GPU time: packets, pulsing lines and ripples; 20 updates a second is plenty for a wallpaper. The satellite marker moves once a second regardless (a single small item). Fewer hotspot cells (Wildfires) and fewer labels also mean less work." }

    // ================================================================= Status
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Status of the data sources" }

    Loader {
        id: statusLoader
        Layout.fillWidth: true
        source: "StatusPanel.qml"
        onLoaded: {
            item.quakeFeed = Qt.binding(function () { return ["2.5_day", "4.5_day", "significant_week"][quakeFeed.currentIndex] || "4.5_day" });
            item.oceanFrom = Qt.binding(function () { return baseImage.text });
        }
    }
    QQC2.Label {
        visible: statusLoader.status === Loader.Error
        text: "The status panel could not be loaded. The settings above still work."
        color: Kirigami.Theme.negativeTextColor
    }

    FileDialog {
        id: picker
        title: "Choose an equirectangular (2:1) world map"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: baseImage.text = String(selectedFile).replace(/^file:\/\//, "")
    }
}
