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
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasma5support as P5Support

/*
 * Shape: a sidebar on the left (search, then every section as one row: its Show switch, its name, the health of
 * its sources) and one section at a time on the right. "Essentials" is the first row and holds the handful of
 * choices most people make. Plasma reads the cfg_ properties off this root item, so they all live here.
 */
RowLayout {
    id: form
    property alias formLayout: pageForm
    spacing: Kirigami.Units.largeSpacing
    Layout.fillWidth: true

    // map
    property alias cfg_BaseImage: baseImage.text
    property alias cfg_DataDir: dataDir.text
    property alias cfg_Seasonal: seasonal.checked
    property alias cfg_SeasonalBlend: seasonalBlend.checked
    property alias cfg_FillMode: fillMode.currentIndex
    property alias cfg_MapStyle: mapStyle.currentIndex
    property alias cfg_MapTone: mapTone.currentIndex
    property alias cfg_SeasonalHires: seasonalHires.checked
    property alias cfg_LandColor: landColor.color
    property alias cfg_OceanColor: oceanColor.color
    property alias cfg_FrameNorth: frameNorth.value
    property alias cfg_FrameSouth: frameSouth.value
    property alias cfg_FrameWest: frameWest.value
    property alias cfg_FrameEast: frameEast.value
    property int cfg_MapDim
    property alias cfg_HintCorner: hintCorner.currentIndex
    property alias cfg_StaleHours: staleHours.value
    // sun and sky
    property alias cfg_ShowDayNight: dayNight.checked
    property alias cfg_NightMode: nightMode.currentIndex
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
    property alias cfg_ShowStateNames: stateNames.checked
    property alias cfg_StateNameDensity: stateNameDensity.currentIndex
    property alias cfg_StateNameSize: stateNameSize.value
    property alias cfg_StateNameTextFollows: stateNameFollows.checked
    property alias cfg_StateNameTextColor: stateNameTextColor.color
    property alias cfg_StateNameLabelBold: stateNameStyle.bold
    property alias cfg_StateNameLabelCaps: stateNameStyle.caps
    property alias cfg_StateNameLabelSpacing: stateNameStyle.letterSpacing
    property alias cfg_StateNameLabelOpacity: stateNameStyle.textOpacity
    property alias cfg_StateNameLabelHalo: stateNameStyle.halo
    property alias cfg_ShowCapitals: capitals.checked
    property alias cfg_CapitalMarks: capitalMarks.currentIndex
    property alias cfg_CapitalSize: capitalSize.value
    property alias cfg_CapitalColor: capitalColor.color
    property alias cfg_CapitalLabelBold: capitalStyle.bold
    property alias cfg_CapitalLabelCaps: capitalStyle.caps
    property alias cfg_CapitalLabelSpacing: capitalStyle.letterSpacing
    property alias cfg_CapitalLabelOpacity: capitalStyle.textOpacity
    property alias cfg_CapitalLabelHalo: capitalStyle.halo
    property alias cfg_ShowStateCapitals: stateCapitals.checked
    property alias cfg_StateCapitalMarks: stateCapitalMarks.currentIndex
    property alias cfg_StateCapitalSize: stateCapitalSize.value
    property alias cfg_StateCapitalColor: stateCapitalColor.color
    property alias cfg_StateCapitalLabelBold: stateCapitalStyle.bold
    property alias cfg_StateCapitalLabelCaps: stateCapitalStyle.caps
    property alias cfg_StateCapitalLabelSpacing: stateCapitalStyle.letterSpacing
    property alias cfg_StateCapitalLabelOpacity: stateCapitalStyle.textOpacity
    property alias cfg_StateCapitalLabelHalo: stateCapitalStyle.halo
    property alias cfg_ShowCities: cities.checked
    property alias cfg_CityMinPop: cityMinPop.currentIndex
    property alias cfg_CityMarks: cityMarks.currentIndex
    property alias cfg_CitySize: citySize.value
    property alias cfg_CityColor: cityColor.color
    property alias cfg_CityPopScale: cityPopScale.checked
    property alias cfg_CityLabelBold: cityStyle.bold
    property alias cfg_CityLabelCaps: cityStyle.caps
    property alias cfg_CityLabelSpacing: cityStyle.letterSpacing
    property alias cfg_CityLabelOpacity: cityStyle.textOpacity
    property alias cfg_CityLabelHalo: cityStyle.halo
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
    property alias cfg_FloodLabelBold: floodStyle.bold
    property alias cfg_FloodLabelCaps: floodStyle.caps
    property alias cfg_FloodLabelSpacing: floodStyle.letterSpacing
    property alias cfg_FloodLabelOpacity: floodStyle.textOpacity
    property alias cfg_FloodLabelHalo: floodStyle.halo
    property alias cfg_AirAlertLabelBold: alertStyle.bold
    property alias cfg_AirAlertLabelCaps: alertStyle.caps
    property alias cfg_AirAlertLabelSpacing: alertStyle.letterSpacing
    property alias cfg_AirAlertLabelOpacity: alertStyle.textOpacity
    property alias cfg_AirAlertLabelHalo: alertStyle.halo
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
    property int cfg_ZoneWidth
    property alias cfg_ShowRivers: rivers.checked
    property alias cfg_RiverColor: riverColor.color
    property int cfg_RiverOpacity
    property int cfg_RiverWidth
    property alias cfg_RiverDetail: riverDetail.currentIndex
    property alias cfg_ShowLakes: lakes.checked
    property int cfg_LakeFill
    property alias cfg_ShowLakeNames: lakeNames.checked
    property alias cfg_LakeNameDensity: lakeNameDensity.currentIndex
    property alias cfg_ShowSeaNames: seaNames.checked
    property alias cfg_SeaNameDensity: seaNameDensity.currentIndex
    property alias cfg_WaterNameSize: waterNameSize.value
    property alias cfg_WaterNameTextFollows: waterNameFollows.checked
    property alias cfg_WaterNameTextColor: waterNameTextColor.color
    property alias cfg_WaterNameItalic: waterNameItalic.checked
    property alias cfg_WaterNameLabelBold: waterNameStyle.bold
    property alias cfg_WaterNameLabelCaps: waterNameStyle.caps
    property alias cfg_WaterNameLabelSpacing: waterNameStyle.letterSpacing
    property alias cfg_WaterNameLabelOpacity: waterNameStyle.textOpacity
    property alias cfg_WaterNameLabelHalo: waterNameStyle.halo
    property alias cfg_ZoneLabels: zoneLabels.checked
    property alias cfg_ZoneClock: zoneClock.currentIndex
    property alias cfg_ZoneTextFollows: zoneTextFollows.checked
    property alias cfg_ZoneTextColor: zoneTextColor.color
    property alias cfg_ZoneLabelPlate: zonePlate.checked
    property alias cfg_ZoneClock12: zoneClock12.checked
    property alias cfg_ZoneLabelSize: zoneLabelSize.value
    property alias cfg_ZoneLabelBold: zoneStyle.bold
    property alias cfg_ZoneLabelCaps: zoneStyle.caps
    property alias cfg_ZoneLabelSpacing: zoneStyle.letterSpacing
    property alias cfg_ZoneLabelOpacity: zoneStyle.textOpacity
    property alias cfg_ZoneLabelHalo: zoneStyle.halo
    property alias cfg_ZoneStyle: zoneLook.currentIndex
    property alias cfg_ZoneRowLat: zoneRowLat.value
    property alias cfg_ZoneTintOpacity: zoneTintOpacity.value
    property alias cfg_ZoneBandOpacity: zoneBandOpacity.value
    property alias cfg_ZoneMarkHome: zoneMarkHome.checked
    property alias cfg_ZoneBandSun: zoneBandSun.checked
    property alias cfg_ZoneBandDiff: zoneBandDiff.checked
    property alias cfg_ZoneAbbrev: zoneAbbrev.checked
    // earthquakes
    property alias cfg_ShowQuakes: quakes.checked
    property alias cfg_QuakeFeed: quakeFeed.currentIndex
    property int cfg_QuakeSources
    property alias cfg_QuakeColor: quakeColor.color
    property int cfg_QuakeSize
    property alias cfg_ShowPlates: plates.checked
    property alias cfg_PlateLineColor: plateLineColor.color
    property int cfg_PlateLineOpacity
    property int cfg_PlateLineWidth
    property alias cfg_ShowInfra: infra.checked
    property alias cfg_InfraMode: infraMode.currentIndex
    property alias cfg_InfraPlatforms: infraPlatforms.checked
    property alias cfg_InfraRefineries: infraRefineries.checked
    property alias cfg_InfraColor: infraColor.color
    property alias cfg_InfraSize: infraSize.value
    property alias cfg_InfraLabels: infraLabels.currentIndex
    property alias cfg_InfraNameThreatened: infraNameThreatened.checked
    property alias cfg_InfraLabelSize: infraLabelSize.value
    property alias cfg_InfraLabelBold: infraStyle.bold
    property alias cfg_InfraLabelCaps: infraStyle.caps
    property alias cfg_InfraLabelSpacing: infraStyle.letterSpacing
    property alias cfg_InfraLabelOpacity: infraStyle.textOpacity
    property alias cfg_InfraLabelHalo: infraStyle.halo
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
    property alias cfg_StormLabelFacilities: stormLabelFacilities.checked
    property alias cfg_StormLabelTwoLines: stormLabelTwoLines.checked
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
    property int cfg_FireSources
    property alias cfg_FireIncidentMin: fireIncidentMin.currentIndex
    property alias cfg_FireIncidentActive: fireIncidentActive.checked
    property alias cfg_FirePerimeter: firePerimeter.checked
    property alias cfg_FireIncidentMark: fireIncidentMark.currentIndex
    property alias cfg_FirePerimeterOpacity: firePerimeterOpacity.value
    property alias cfg_FireFocus: fireFocus.currentIndex
    property alias cfg_HotspotMinCount: hotspotMinCount.currentIndex
    property alias cfg_HotspotTier: hotspotTier.currentIndex
    property alias cfg_FireLabels: fireLabels.currentIndex
    property alias cfg_FireLabelSize: fireLabelSize.value
    property alias cfg_FireLabelPlate: firePlate.checked
    property alias cfg_FireTextFollows: fireFollows.checked
    property alias cfg_FireTextColor: fireTextColor.color
    property alias cfg_FirePulseMode: firePulseMode.currentIndex
    // tsunami
    property alias cfg_ShowTsunami: tsunami.checked
    property int cfg_TsunamiLayerOpacity
    property alias cfg_TsunamiShowInfo: tsunamiShowInfo.checked
    property alias cfg_TsunamiInfoHours: tsunamiInfoHours.value
    property alias cfg_TsunamiCoast: tsunamiCoast.checked
    property alias cfg_TsunamiColor: tsunamiColor.color
    property alias cfg_TsunamiAdvisoryColor: tsunamiAdvisoryColor.color
    property alias cfg_TsunamiWatchColor: tsunamiWatchColor.color
    property alias cfg_TsunamiInfoColor: tsunamiInfoColor.color
    property alias cfg_TsunamiLabels: tsunamiLabels.currentIndex
    property alias cfg_TsunamiLabelSize: tsunamiLabelSize.value
    property alias cfg_TsunamiLabelPlate: tsunamiPlate.checked
    property alias cfg_TsunamiTextFollows: tsunamiFollows.checked
    property alias cfg_TsunamiTextColor: tsunamiTextColor.color
    property alias cfg_TsunamiPulse: tsunamiPulse.checked
    property alias cfg_TsunamiLabelBold: tsunamiStyle.bold
    property alias cfg_TsunamiLabelCaps: tsunamiStyle.caps
    property alias cfg_TsunamiLabelSpacing: tsunamiStyle.letterSpacing
    property alias cfg_TsunamiLabelOpacity: tsunamiStyle.textOpacity
    property alias cfg_TsunamiLabelHalo: tsunamiStyle.halo
    // floods
    property alias cfg_ShowFloods: floods.checked
    property alias cfg_FloodColor: floodColor.color
    property alias cfg_FloodAlertColors: floodAlertColors.checked
    property alias cfg_FloodMinLevel: floodMinLevel.currentIndex
    property alias cfg_FloodArea: floodArea.checked
    property alias cfg_FloodAreaOpacity: floodAreaOpacity.value
    property alias cfg_FloodNws: floodNws.checked
    property alias cfg_FloodNwsEach: floodNwsEach.checked
    property int cfg_FloodWarnSources
    property alias cfg_FloodLabels: floodLabels.currentIndex
    property alias cfg_FloodLabelSize: floodLabelSize.value
    property alias cfg_FloodLabelPlate: floodPlate.checked
    property alias cfg_FloodTextFollows: floodFollows.checked
    property alias cfg_FloodTextColor: floodTextColor.color
    property alias cfg_FloodPulseMode: floodPulseMode.currentIndex
    // air raid alerts
    property alias cfg_ShowAirAlerts: airAlerts.checked
    property alias cfg_AirAlertColor: alertColor.color
    property alias cfg_AirAlertNewColor: alertNewColor.color
    property alias cfg_AirAlertLongColor: alertLongColor.color
    property alias cfg_AirAlertStyle: alertDrawStyle.currentIndex
    property alias cfg_AirAlertNewMinutes: alertNewMinutes.value
    property alias cfg_AirAlertClearColor: alertClearColor.color
    property alias cfg_AirAlertShowClear: alertShowClear.checked
    property alias cfg_AirAlertOpacity: alertOpacity.value
    property alias cfg_AirAlertPartialOpacity: alertPartialOpacity.value
    property alias cfg_AirAlertOutline: alertOutline.checked
    property alias cfg_AirAlertOutlineOpacity: alertOutlineOpacity.value
    property alias cfg_AirAlertToken: alertToken.text
    property alias cfg_AirAlertPulse: alertPulse.checked
    property alias cfg_AirAlertLongHours: alertLongHours.value
    property alias cfg_AirAlertLongStyle: alertLongStyle.currentIndex
    property alias cfg_AirAlertLabels: alertLabels.currentIndex
    property alias cfg_AirAlertLabelSize: alertLabelSize.value
    property alias cfg_AirAlertLabelPlate: alertPlate.checked
    property alias cfg_AirAlertTextFollows: alertFollows.checked
    property alias cfg_AirAlertTextColor: alertTextColor.color
    // space
    property alias cfg_ShowSats: sats.checked
    property alias cfg_SatIss: satIss.checked
    property alias cfg_SatHubble: satHubble.checked
    property alias cfg_SatTiangong: satTiangong.checked
    property alias cfg_SatPasses: satPasses.currentIndex
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
    property alias cfg_LaunchLabelTwoLines: launchLabelTwoLines.checked
    property int cfg_QuakeLayerOpacity
    property int cfg_InfraLayerOpacity
    property int cfg_VolcanoLayerOpacity
    property int cfg_StormLayerOpacity
    property int cfg_FireLayerOpacity
    property int cfg_FloodLayerOpacity
    property int cfg_AirAlertLayerOpacity
    property int cfg_SatLayerOpacity
    property int cfg_LaunchLayerOpacity
    property int cfg_NetLayerOpacity
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
    // The section's Show box, as a switch: the same setting in the sidebar, in the page heading and in the page.
    component TwinSwitch: QQC2.Switch {
        id: tsw
        property QtObject twin: null
        visible: twin !== null
        checked: twin ? twin.checked : false
        onToggled: if (twin) twin.checked = checked
        Connections { target: tsw.twin; function onCheckedChanged() { if (tsw.checked !== tsw.twin.checked) tsw.checked = tsw.twin.checked } }
        QQC2.ToolTip.text: "Show this layer on the map"; QQC2.ToolTip.visible: hovered
    }
    // A combo box that mirrors another one (Essentials shows a few of the pages' choices a second time).
    component MirrorCombo: QQC2.ComboBox {
        id: mc
        property QtObject twin: null
        model: twin ? twin.model : []
        currentIndex: twin ? twin.currentIndex : -1
        onActivated: function (i) { if (twin) { twin.currentIndex = i; twin.activated(i); } }
        Connections { target: mc.twin; function onCurrentIndexChanged() { if (mc.currentIndex !== mc.twin.currentIndex) mc.currentIndex = mc.twin.currentIndex } }
    }
    // The health dot: green, every source answers; orange, some do not (the layer still draws from the rest) or
    // one warns; red, none answer; grey, not checked yet.
    component HealthDot: Rectangle {
        property string worst: ""
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5); implicitHeight: implicitWidth; radius: implicitWidth / 2
        color: worst === "ok" ? Kirigami.Theme.positiveTextColor : worst === "warn" ? Kirigami.Theme.neutralTextColor
             : worst === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        QQC2.ToolTip.text: worst === "warn" ? "Some of the sources are not answering, or something is to download" : worst === "error" ? "None of the sources are working" : worst === "ok" ? "Every source working" : "Not checked yet"
        QQC2.ToolTip.visible: dotArea.containsMouse
        MouseArea { id: dotArea; anchors.fill: parent; hoverEnabled: true }
    }
    // The sections, in the order they appear in the file; the sidebar lists them by group.
    property var sections: []
    readonly property var groupOrder: ["", "Map", "Natural events", "Civil, space and network", "Shared"]
    // the sidebar's order: by group, and inside a group as listed here (sections are completed in no fixed order)
    readonly property var sideOrder: ["Essentials", "Map", "Day and night", "Clouds", "Countries", "Rivers, lakes and seas", "Time zones", "Tectonic plates",
        "Oil and gas infrastructure", "Earthquakes", "Volcanoes", "Storms", "Wildfires", "Floods", "Tsunami bulletins", "Air raid alerts (Ukraine)",
        "Satellites", "Launches", "Network activity", "Units", "Markers and labels", "Ageing and pulses", "Performance and power", "Status", "Coverage"]
    function sideRank(s) { var g = groupOrder.indexOf(s.group), i = sideOrder.indexOf(s.title); return (g < 0 ? 99 : g) * 100 + (i < 0 ? 99 : i); }
    readonly property var sideList: sections.slice().sort(function (a, b) { return form.sideRank(a) - form.sideRank(b); })
    property string page: "Essentials"
    // "Find a setting": the sidebar keeps only the sections whose title, summary or keywords contain the words
    property string filter: ""
    readonly property int matching: filter === "" ? sections.length : sections.filter(function (s) { return s.matches; }).length
    onFilterChanged: {
        if (filter === "") return;
        var cur = sections.find(function (s) { return s.title === form.page; });
        if (cur && cur.matches) return;
        var first = sideList.find(function (s) { return s.matches; });
        if (first) form.page = first.title;
    }
    // A section is one page: its heading row (the Show switch, the health of its sources, the title and one line
    // that says what it is set to) and every row below it that is `visible: secN.open`.
    component SectionHeader: RowLayout {
        id: sh
        property string title: ""
        property string group: ""
        property string summary: ""
        property string keywords: ""                 // extra words the search should find this section by
        readonly property bool matches: (function () {
            var words = form.filter.toLowerCase().split(/\s+/).filter(function (w) { return w !== ""; });
            if (words.length === 0) return true;
            var hay = (title + " " + group + " " + summary + " " + keywords + " " + sourceNames.join(" ")).toLowerCase();
            return words.every(function (w) { return hay.indexOf(w) >= 0; });
        })()
        property QtObject twin: null                 // the section's Show checkbox, when it has one
        property var sourceNames: []                 // the Source rows below: their worst state shows as the dot
        readonly property bool open: form.page === title
        visible: open
        readonly property string worst: (function () {
            var checks = statusLoader.item ? statusLoader.item.checks : [], ok = 0, bad = 0, warn = 0;
            for (var i = 0; i < sourceNames.length; i++) {
                var c = checks.find(function (x) { return x.name === sourceNames[i]; });
                if (!c) continue;
                if (c.state === "error") bad++; else if (c.state === "warn") warn++; else ok++;
            }
            if (ok + bad + warn === 0) return "";
            if (bad > 0) return ok > 0 ? "warn" : "error";
            return warn > 0 ? "warn" : "ok";
        })()
        Kirigami.FormData.isSection: true
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Component.onCompleted: form.sections = form.sections.concat([sh])
        TwinSwitch { twin: sh.twin }
        HealthDot { visible: sh.sourceNames.length > 0; worst: sh.worst }
        Kirigami.Heading { level: 2; text: sh.title }
        QQC2.Label {
            Layout.fillWidth: true
            text: sh.summary
            opacity: 0.7
            elide: Text.ElideRight
            font.pointSize: Math.max(7, Kirigami.Theme.defaultFont.pointSize - 1)
        }
    }
    // One row of the sidebar: the section's Show switch (a blank of the same width when it has none), its name
    // and the health of its sources. The row is the page's button; the switch is the layer's.
    component SideEntry: Rectangle {
        id: se
        required property var modelData
        required property int index
        readonly property bool selected: form.page === modelData.title
        readonly property bool firstOfGroup: form.sideList.findIndex(function (s) { return s.group === se.modelData.group && s.matches; }) === index
        visible: modelData.matches
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight
        color: "transparent"
        ColumnLayout {
            id: col
            anchors.left: parent.left; anchors.right: parent.right
            spacing: 0
            Kirigami.Heading {
                visible: se.firstOfGroup && se.modelData.group !== ""
                level: 5
                text: se.modelData.group
                opacity: 0.6
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.topMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.smallSpacing
                color: se.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.3) : hover.containsMouse ? Qt.alpha(Kirigami.Theme.highlightColor, 0.12) : "transparent"
                MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: form.page = se.modelData.title }
                Rectangle { visible: se.selected; width: 3; height: parent.height; radius: 1; color: Kirigami.Theme.highlightColor }
                RowLayout {
                    id: row
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Kirigami.Units.largeSpacing; anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing
                    TwinSwitch { id: sideSwitch; twin: se.modelData.twin }
                    Item { visible: se.modelData.twin === null; implicitWidth: sideSwitch.implicitWidth; implicitHeight: 1 }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: se.modelData.title
                        elide: Text.ElideRight
                        font.bold: se.selected
                        opacity: se.modelData.twin && !se.modelData.twin.checked ? 0.6 : 1
                    }
                    HealthDot { visible: se.modelData.sourceNames.length > 0; worst: se.modelData.worst }
                }
            }
        }
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
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
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
                QQC2.ToolButton {                              // and when it is fine: a quiet way to refresh the data
                    readonly property string command: statusLoader.item ? statusLoader.item.fetchCommand(modelData) : ""
                    visible: command !== "" && check && check.state === "ok"
                    enabled: statusLoader.item && !statusLoader.item.busy
                    icon.name: "view-refresh"
                    QQC2.ToolTip.text: "Download again (" + (statusLoader.item ? statusLoader.item.fetchLabel(modelData).replace("Download (", "").replace(")", "") : "") + ")"
                    QQC2.ToolTip.visible: hovered
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
        property string label: "Label style:"
        Kirigami.FormData.label: label
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
        from: 4; to: 28
        textFromValue: function (v) { return v + " px" }
        valueFromText: function (t) { return parseInt(t) || 10 }
    }


    // ---- state and helpers that the pages share (moved up from their sections so they live on the root)
    property string cfg_StyleName
    property int cfg_StyleIncludes
    property var styleList: []
    property var styleKeys: ({ base: [], look: [], layers: [], machine: [] })
    property var styleValues: ({})          // the current style as its file has it
    property string styleFileName: ""
    property string styleDir: ""
    property bool styleIsBuiltin: true
    property bool styleLoaded: false
    property string styleNote: ""
    readonly property var historyList: styleList.filter(function (s) { return s.id.indexOf("history:") === 0; })   // newest first
    readonly property bool hasOriginal: styleList.some(function (s) { return s.id === "user:original"; })
    readonly property bool styleIsSnapshot: cfg_StyleName.indexOf("history:") === 0 || cfg_StyleName === "user:original"
    readonly property var includedBuckets: [ "base", "look", "layers" ].filter(function (b, i) { return (form.cfg_StyleIncludes & (1 << i)) !== 0; })
    function bucketOf(key) {
        for (var b in styleKeys) if (styleKeys[b].indexOf(key) >= 0) return b;
        return "machine";
    }
    function normValue(v) {
        if (v === undefined || v === null) return null;
        if (typeof v === "object" || (typeof v === "string" && v.charAt(0) === "#")) return String(v).toLowerCase();
        return v;
    }
    function collectValues(buckets) {      // this page's current values for the given buckets
        var out = {};
        for (var i = 0; i < buckets.length; i++) {
            var keys = styleKeys[buckets[i]] || [];
            for (var j = 0; j < keys.length; j++) {
                var v = form["cfg_" + keys[j]];
                if (v !== undefined) out[keys[j]] = normValue(v);
            }
        }
        return out;
    }
    function styleKeysIncluded(values) {
        var keys = [];
        for (var k in values) if (includedBuckets.indexOf(bucketOf(k)) >= 0 && form["cfg_" + k] !== undefined) keys.push(k);
        return keys.sort();
    }
    // the page's values for everything the current style sets, as text: differs from the file's -> modified
    readonly property string styleSig: {
        var keys = styleKeysIncluded(styleValues), out = [];
        for (var i = 0; i < keys.length; i++) out.push(keys[i] + "=" + JSON.stringify(normValue(form["cfg_" + keys[i]])));
        return out.join("\n");
    }
    readonly property string styleFileSig: {
        var keys = styleKeysIncluded(styleValues), out = [];
        for (var i = 0; i < keys.length; i++) out.push(keys[i] + "=" + JSON.stringify(normValue(styleValues[keys[i]])));
        return out.join("\n");
    }
    readonly property bool styleModified: styleLoaded && styleSig !== styleFileSig
    function styleCmd(words) { return "python3 '" + widgetHelper + "' styles " + words + " # " + Date.now(); }
    function quoted(t) { return "'" + String(t).replace(/'/g, "'\\''") + "'"; }
    function snapshot(id, name) {           // everything a style can hold, as the page has it now
        styleExec.connectSource(styleCmd("save --id " + id + " --name " + quoted(name) + " --includes 7 --values " + Qt.btoa(JSON.stringify(collectValues(["base", "look", "layers"])))));
    }
    function styleName(id) { var s = styleList.find(function (x) { return x.id === id; }); return s ? s.name : id; }
    function applyValues(values) {          // write a style's values into the controls, only the included buckets
        var keys = styleKeysIncluded(values);
        for (var i = 0; i < keys.length; i++) form["cfg_" + keys[i]] = values[keys[i]];
    }
    function applyStyle(id) {
        if (id.indexOf("history:") !== 0) snapshot("user:previous", "Before " + styleName(id));   // dated, the last 20 kept
        styleExec.connectSource(styleCmd("read --id " + id + " --name apply"));
    }
    function loadStyle(id) { styleExec.connectSource(styleCmd("read --id " + id)); }
    function saveStyle(id, name) {
        styleExec.connectSource(styleCmd("save --id " + id + " --name " + quoted(name) + " --includes " + cfg_StyleIncludes
                                         + " --values " + Qt.btoa(JSON.stringify(collectValues(includedBuckets)))));
    }
    P5Support.DataSource {
        id: styleExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            var r;
            try { r = JSON.parse(data.stdout); } catch (e) { form.styleNote = "The helper did not answer: " + String(data.stderr).trim().split("\n").pop(); return; }
            if (r && r.error) { form.styleNote = r.error; return; }
            form.styleNote = "";
            if (source.indexOf("' styles keys") >= 0) {
                form.styleDir = r.dir || ""; delete r.dir; form.styleKeys = r;
                // the settings as they are the first time this page opens with styles: kept for good, never overwritten
                if (!form.hasOriginal) form.snapshot("user:original", "Original settings, before styles");
                return;
            }
            if (source.indexOf("' styles list") >= 0) { form.styleList = r; return; }
            if (source.indexOf("' styles read") >= 0) {
                form.styleValues = r.values; form.styleFileName = r.name; form.styleIsBuiltin = !!r.builtin;
                if (source.indexOf("--name apply") >= 0) { form.applyValues(r.values); form.cfg_StyleName = r.id; }
                form.styleLoaded = true;
                return;
            }
            // save, delete, import: refresh the list, and the current style when it is the one just written
            styleExec.connectSource(form.styleCmd("list"));
            if (r.id && source.indexOf("' styles save") >= 0 && !r.kept && r.id.indexOf("history:") !== 0 && r.id !== "user:original") { form.cfg_StyleName = r.id; form.loadStyle(r.id); }
            if (r.id && source.indexOf("' styles import") >= 0) form.applyStyle(r.id);
            if (r.deleted && r.deleted === form.cfg_StyleName) { form.cfg_StyleName = "builtin:seasonal"; form.loadStyle(form.cfg_StyleName); }
        }
    }
    Timer { interval: 900; running: true; onTriggered: { styleExec.connectSource(form.styleCmd("keys")); styleExec.connectSource(form.styleCmd("list")); form.loadStyle(form.cfg_StyleName || "builtin:seasonal"); } }

    property var widgetMode: ({})
    // the companion widget, as the helper sees it: installed, on which desktops, and how to get it
    property var widgetInfo: ({})
    property bool widgetBusy: false
    function widgetRun(words) { widgetBusy = true; widgetExec.connectSource("python3 '" + widgetHelper + "' widget " + words + " # " + Date.now()); }
    P5Support.DataSource {
        id: widgetExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => { disconnectSource(source); form.widgetBusy = false; try { form.widgetInfo = JSON.parse(data.stdout) || ({}); } catch (e) { form.widgetInfo = ({ error: "The helper did not answer: " + String(data.stderr).trim().split("\n").pop() }); } }
    }
    Timer { interval: 1500; running: true; onTriggered: form.widgetRun("") }
    // what the wallpaper is doing about its imagery (helper `frame-state`, written by the wallpaper's FrameWatch):
    // asked every few seconds while this page is open, so a change of base map or view can be watched here
    property var frameState: ({})
    P5Support.DataSource {
        id: frameStateExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => { disconnectSource(source); try { form.frameState = JSON.parse(data.stdout) || ({}); } catch (e) {} }
    }
    Timer { interval: 2500; running: true; repeat: true; triggeredOnStart: true; onTriggered: frameStateExec.connectSource("python3 '" + form.widgetHelper + "' frame-state # " + Date.now()) }
    readonly property bool frameBuilding: frameState.state === "building" && (frameState.age || 0) < 900
    readonly property bool frameJustReady: frameState.state === "ready" && (frameState.age || 0) < 12
    readonly property bool frameFailed: frameState.state === "failed" && (frameState.age || 0) < 3600
    readonly property real frameFraction: frameBuilding && frameState.total > 0 ? Math.min(1, frameState.done / frameState.total) : -1
    readonly property string frameText: frameBuilding ? "<b>Building the map imagery</b> - " + (frameState.note || "") + (frameState.what ? " \u00b7 " + frameState.what : "") + " \u00b7 " + frameState.age + " s so far, usually about a minute. The map keeps its previous picture until this is ready."
                                      : frameFailed ? "<b>The map imagery could not be built</b> - " + (frameState.note || "") + ". The map keeps its previous picture; it is tried again in an hour, or on the next change here."
                                      : frameJustReady ? "<b>Map imagery ready</b> - " + (frameState.note || "") : ""
    // a style swatch: [top, bottom, text] for each base map (0 seasonal imagery, 1 satellite, 2 relief, 3 dark
    // cartographic, 4 Dark Matter, 5 Matrix)
    function swatchColours(base) {
        return [["#2d5f8a", "#3b6b3a", "#ffffff"], ["#0a2a4a", "#15528f", "#ffffff"], ["#d9c9a3", "#7f9a62", "#2b2418"],
                ["#1b2129", "#2e3946", "#ffffff"], ["#0d0d0d", "#2b2b2b", "#ffffff"], ["#000000", "#0b3b1f", "#7dffb0"]][base] || ["#4a4f55", "#6b7178", "#ffffff"];
    }
    readonly property string widgetHelper: String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "")
    readonly property var widgetHidden: (widgetMode.hide || []).map(function (l) {
        return ({ quakes: "Earthquakes", volcanoes: "Volcanoes", storms: "Storms", fires: "Wildfires", floods: "Floods", tsunami: "Tsunami bulletins", alerts: "Air raid alerts", sats: "Satellites", launches: "Launches", network: "Network activity" })[l] || l; })
    P5Support.DataSource {
        id: modeExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => { disconnectSource(source); try { form.widgetMode = JSON.parse(data.stdout) || ({}); } catch (e) {} }
    }
    Component.onCompleted: modeExec.connectSource("python3 '" + widgetHelper + "' mode # " + Date.now())

    readonly property var profiles: [
        // fps, arcs, quakePulse, volcanoPulse, stormPulse, firePulse, hotspots, borderDetail, satTrack, guardPause, guardPlain
        { name: "High performance", fps: 0, arcs: 2, qp: 3, vp: 1, sp: 3, fp: 3, hot: 1, detail: 1, track: 2, gpause: 85, gplain: 97 },
        { name: "Balanced",         fps: 2, arcs: 0, qp: 1, vp: 1, sp: 1, fp: 1, hot: 2, detail: 0, track: 1, gpause: 70, gplain: 90 },
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

    readonly property var framePresets: [
        { name: "The whole world",                              n: 90, s: -90, w: -180, e: 180 },
        { name: "Without Antarctica (84°N to 58°S)",  n: 84, s: -58, w: -180, e: 180 },
        { name: "Where people live (72°N to 56°S)",   n: 72, s: -56, w: -180, e: 180 },
        { name: "Americas",                                     n: 75, s: -57, w: -170, e: -30 },
        { name: "North America",                                n: 72, s: 7,   w: -170, e: -50 },
        { name: "United States",                                n: 50, s: 24,  w: -126, e: -66 },
        { name: "Central America and the Caribbean",            n: 33, s: 5,   w: -120, e: -58 },
        { name: "South America",                                n: 14, s: -57, w: -85,  e: -33 },
        { name: "Europe",                                       n: 72, s: 34,  w: -25,  e: 45 },
        { name: "Europe, Middle East and Africa",               n: 72, s: -36, w: -25,  e: 65 },
        { name: "Middle East",                                  n: 43, s: 11,  w: 24,   e: 65 },
        { name: "Africa",                                       n: 38, s: -36, w: -20,  e: 55 },
        { name: "Asia",                                         n: 78, s: -12, w: 25,   e: 150 },
        { name: "South Asia",                                   n: 40, s: 4,   w: 58,   e: 100 },
        { name: "East Asia",                                    n: 55, s: 15,  w: 95,   e: 150 },
        { name: "South-east Asia and Oceania",                  n: 25, s: -48, w: 90,   e: 180 },
        { name: "Australia and New Zealand",                    n: -8, s: -50, w: 110,  e: 180 },
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

    readonly property string fitPreview: (function () {
        var W = Screen.width, H = Screen.height, n = frameNorth.value, so = frameSouth.value, w = frameWest.value, e = frameEast.value;
        if (!(W > 0 && H > 0) || e <= w || n <= so) return "";
        var sxF = W / (e - w), syF = H / (n - so), m = fillMode.currentIndex, sx, sy;
        if (m === 0) { sx = sxF; sy = syF; } else if (m === 1) { sx = sy = Math.min(sxF, syF); } else if (m === 2) { sx = sy = Math.max(sxF, syF); }
        else { sx = sy = Math.max(Math.min(sxF, syF), W / 360, H / 180); }
        var cl = (w + e) / 2, ct = (n + so) / 2;
        if (m === 3) { cl = Math.max(-180 + W / (2 * sx), Math.min(180 - W / (2 * sx), cl)); ct = Math.max(-90 + H / (2 * sy), Math.min(90 - H / (2 * sy), ct)); }
        var vw = cl - W / (2 * sx), ve = cl + W / (2 * sx), vn = ct + H / (2 * sy), vs = ct - H / (2 * sy);
        function lon(x) { return Math.round(Math.abs(x)) + (x < 0 ? "°W" : "°E"); }
        function lat(y) { return Math.round(Math.abs(y)) + (y < 0 ? "°S" : "°N"); }
        var bars = vn > 90 || vs < -90 || vw < -180 || ve > 180;
        return "This screen is " + (W / H).toFixed(2) + ":1 (" + W + " × " + H + "): it shows " + lon(Math.max(-180, vw)) + " to " + lon(Math.min(180, ve)) + ", " + lat(Math.min(90, vn)) + " to " + lat(Math.max(-90, vs))
             + (m === 0 ? ", shapes drawn " + Math.round(sy / sx * 100) + " % as tall as true" : bars ? ", with bars where the world ends" : "")
             + ". On a screen this shape every frame the full 360° wide comes out alike in Fill: the whole latitude range, the middle of the Pacific trimmed; only Crop or Stretch can honour a narrower latitude band.".replace(/\. On a screen.*$/, m === 3 && (e - w) >= 300 && W / H < 2 ? ". On a screen this shape every frame the full 360° wide comes out alike in Fill (the whole latitude range, the middle of the Pacific trimmed); only Crop or Stretch can honour a narrower latitude band." : ".");
    })()

    readonly property var zoneStyles: [
        { name: "Classic: labels inside each zone",                       placement: 0, tint: false },
        { name: "One row of labels, at a latitude",                       placement: 1, tint: false },
        { name: "D3: a band at a latitude, time large, your zone marked", placement: 2, tint: false },
        { name: "D1: tinted zones, labels inside each zone",              placement: 0, tint: true },
        { name: "D1 + D3: tinted zones with the band",                    placement: 2, tint: true } ]

    readonly property var fireSourceList: [[1, "GDACS events (world)"], [4, "US incidents (NIFC)"], [8, "Canada (CWFIS)"], [16, "Europe, Middle East, North Africa (EFFIS)"], [2, "NASA satellite hotspots (FIRMS)"]]
    readonly property string fireSourcesText: fireSourceList.filter(function (x) { return (form.cfg_FireSources & x[0]) !== 0; }).map(function (x) { return x[1].replace(/ \(.*\)/, ""); }).join(", ") || "no source"

    // ---- the sidebar
    ColumnLayout {
        id: sidebar
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        spacing: 0
        Kirigami.SearchField {
            id: finder
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            placeholderText: "Find a setting"
            onTextChanged: form.filter = text
        }
        QQC2.Label { visible: form.filter !== ""; text: form.matching === 0 ? "Nothing matches" : form.matching + " of " + form.sections.length + " pages"; opacity: 0.7; Layout.leftMargin: Kirigami.Units.largeSpacing }
        Repeater {
            model: form.sideList
            delegate: SideEntry {}
        }
    }
    Kirigami.Separator { Layout.fillHeight: true }

    // ---- the page: one section at a time. Always the two-column form; left to itself Kirigami switches to a
    // stacked layout in a narrow window, which moves every label; with the controls capped in width the page
    // simply gets narrower instead.
    // Kirigami centres a form's grid inside the form, so the form is made exactly as wide as its content (never
    // wider than the room there is): the labels then sit next to the sidebar instead of floating in the middle.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.largeSpacing
        // what the wallpaper is doing about its picture, where it cannot be missed: a banner over the page while a
        // base map or view is built (with the helper's progress), green for a moment when it lands, red if it failed
        Kirigami.InlineMessage {
            id: imageryBanner
            Layout.fillWidth: true
            Layout.maximumWidth: pageForm.width
            visible: form.frameBuilding || form.frameJustReady || form.frameFailed
            type: form.frameFailed ? Kirigami.MessageType.Error : form.frameJustReady ? Kirigami.MessageType.Positive : Kirigami.MessageType.Information
            text: form.frameText
            showCloseButton: form.frameFailed
        }
        QQC2.ProgressBar {
            Layout.fillWidth: true
            Layout.maximumWidth: pageForm.width
            visible: form.frameBuilding
            from: 0; to: 1
            indeterminate: form.frameFraction < 0
            value: Math.max(0, form.frameFraction)
        }
    Item {
        Layout.fillWidth: true
        implicitHeight: pageForm.implicitHeight
        clip: true
        Kirigami.FormLayout {
        id: pageForm
        anchors.left: parent.left
        width: Math.max(implicitWidth, Kirigami.Units.gridUnit * 44)
        wideMode: true

        // ================================================================= Essentials
        // The first page: a look (style), the profile, where you are, what part of the world is on screen, and the
        // companion widget. Everything here is a second view of a setting that also has its own page.
        SectionHeader { id: secE; title: "Essentials"; group: ""; twin: null; keywords: "simple basic start style look profile home city where you are frame region fit screen widget"; summary: "The handful of choices most people make; everything else is one click away on the left." }
        RowLayout {
            visible: secE.open
            Kirigami.FormData.label: "Data:"
            HealthDot {
                worst: {
                    var checks = statusLoader.item ? statusLoader.item.checks : [];
                    if (checks.length === 0) return "";
                    var bad = checks.filter(function (c) { return c.state === "error"; }).length, warn = checks.filter(function (c) { return c.state === "warn"; }).length;
                    return bad === checks.length ? "error" : bad + warn > 0 ? "warn" : "ok";
                }
            }
            QQC2.Label { text: sec17.summary === "Not checked yet" ? "Sources not checked yet" : sec17.summary.replace(/^0 problems, 0 notes$/, "Every source answering"); opacity: 0.8 }
            QQC2.ToolButton { text: "Status"; icon.name: "view-list-details"; onClicked: form.page = "Status" }
            QQC2.ToolButton { text: "Coverage"; icon.name: "map-globe"; onClicked: form.page = "Coverage" }
        }

        // ---- Look: the style. A style is a snapshot of some of the pages' settings, kept as JSON by the helper (`styles`):
        // the built-in ones ship with the package and carry each base map's recommended colours; the user's own live in
        // the data folder. Picking one writes its values into the controls, after "Previous" has been saved; editing
        // anything a style covers marks it modified, and Save / Save as / Reset work on that. Every setting is in one
        // bucket (base, look, layers, machine) and the Includes boxes say which buckets an apply touches and a save captures.
        Kirigami.Heading { visible: secE.open; Kirigami.FormData.isSection: true; level: 4; text: "Look"; topPadding: Kirigami.Units.largeSpacing }
        // one swatch per style: its base map's colours, the current one framed; a click applies it
        Flow {
            visible: secE.open
            Kirigami.FormData.label: "Style:"
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 34
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: form.styleList.filter(function (s) { return !s.history; })
                delegate: Rectangle {
                    id: swatch
                    required property var modelData
                    readonly property bool current: form.cfg_StyleName === modelData.id
                    readonly property var colours: form.swatchColours(modelData.base)
                    width: Kirigami.Units.gridUnit * 6; height: Kirigami.Units.gridUnit * 3.5
                    radius: Kirigami.Units.smallSpacing
                    border.width: current ? 2 : 1
                    border.color: current ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.25)
                    gradient: Gradient {
                        GradientStop { position: 0; color: swatch.colours[0] }
                        GradientStop { position: 1; color: swatch.colours[1] }
                    }
                    QQC2.Label {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Kirigami.Units.smallSpacing }
                        text: swatch.modelData.name + (swatch.modelData.builtin ? "" : " ·")
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.bold: swatch.current
                        color: swatch.colours[2]
                        style: Text.Outline; styleColor: swatch.colours[2] === "#2b2418" ? "#ffffffaa" : "#000000aa"
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: form.applyStyle(swatch.modelData.id) }
                    QQC2.ToolTip.text: swatch.modelData.name + (swatch.modelData.builtin ? " (built in)" : " (yours)"); QQC2.ToolTip.visible: hoverArea.containsMouse
                    MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
        }
        RowLayout {
            visible: secE.open
            Kirigami.FormData.label: "Saved as:"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            QQC2.ComboBox {
                id: styleCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: form.styleList.map(function (s) { return s.name + (s.builtin || s.history ? "" : "  (yours)"); })
                currentIndex: { var i = form.styleList.findIndex(function (s) { return s.id === form.cfg_StyleName; }); return i; }
                displayText: currentIndex < 0 ? (form.styleFileName || "(none)") : currentText
                onActivated: function (i) { var s = form.styleList[i]; if (s) form.applyStyle(s.id); }
            }
            QQC2.Label { visible: form.styleModified; text: "● modified"; color: Kirigami.Theme.neutralTextColor }
            QQC2.Button { text: "Save"; icon.name: "document-save"; enabled: form.styleModified && !form.styleIsBuiltin && !form.styleIsSnapshot; onClicked: form.saveStyle(form.cfg_StyleName, form.styleFileName) }
            QQC2.Button { text: "Save as…"; icon.name: "document-save-as"; enabled: form.styleLoaded; onClicked: { saveAsName.text = form.styleIsBuiltin ? "My " + form.styleFileName.toLowerCase() : form.styleIsSnapshot ? "" : form.styleFileName; saveAsDialog.open(); } }
            QQC2.Button { text: "Reset"; icon.name: "edit-undo"; enabled: form.styleModified; onClicked: form.applyStyle(form.cfg_StyleName); QQC2.ToolTip.text: "Back to " + form.styleFileName + " as saved"; QQC2.ToolTip.visible: hovered }
            QQC2.Button {
                icon.name: "application-menu"; text: "More"
                onClicked: styleMenu.open()
                QQC2.Menu {
                    id: styleMenu
                    y: parent.height
                    QQC2.MenuItem { text: form.historyList.length > 0 ? "Back to \"" + form.historyList[0].name + "\"" : "Back to before the last apply"; enabled: form.historyList.length > 0; onTriggered: form.applyStyle(form.historyList[0].id) }
                    QQC2.MenuItem { text: "Back to the original settings (before styles)"; enabled: form.hasOriginal; onTriggered: form.applyStyle("user:original") }
                    QQC2.MenuItem { text: "Export this style…"; enabled: form.styleLoaded; onTriggered: exportDialog.open() }
                    QQC2.MenuItem { text: "Import a style…"; onTriggered: importDialog.open() }
                    QQC2.MenuItem { text: "Delete " + form.styleFileName; enabled: !form.styleIsBuiltin && form.cfg_StyleName !== "user:original"; onTriggered: styleExec.connectSource(form.styleCmd("delete --id " + form.cfg_StyleName)) }
                    QQC2.MenuItem { text: "Open the styles folder"; enabled: form.styleDir !== ""; onTriggered: Qt.openUrlExternally("file://" + form.styleDir) }
                }
            }
        }
        RowLayout {
            visible: secE.open
            Kirigami.FormData.label: "A style covers:"
            QQC2.CheckBox { text: "Map base"; checked: (form.cfg_StyleIncludes & 1) !== 0; onToggled: form.cfg_StyleIncludes = checked ? (form.cfg_StyleIncludes | 1) : (form.cfg_StyleIncludes & ~1) }
            QQC2.CheckBox { text: "Colours, lines and labels"; checked: (form.cfg_StyleIncludes & 2) !== 0; onToggled: form.cfg_StyleIncludes = checked ? (form.cfg_StyleIncludes | 2) : (form.cfg_StyleIncludes & ~2) }
            QQC2.CheckBox { text: "Layers"; checked: (form.cfg_StyleIncludes & 4) !== 0; onToggled: form.cfg_StyleIncludes = checked ? (form.cfg_StyleIncludes | 4) : (form.cfg_StyleIncludes & ~4) }
        }
        Note { visible: secE.open; text: (form.styleNote !== "" ? form.styleNote + "\n" : "")
                     + "A built-in style is a base map with its recommended colours; it leaves your sizes, line widths and label styles alone. Before every apply the settings are saved as a dated snapshot (More has the way back, and \"Original\" is how they were before styles). Save as keeps your version with everything the ticked boxes cover; home place, units, frame and profile are never part of a style." }
        Kirigami.Heading { visible: secE.open; Kirigami.FormData.isSection: true; level: 4; text: "Profile"; topPadding: Kirigami.Units.largeSpacing }
        QQC2.ComboBox {
            visible: secE.open
            id: profile
            Kirigami.FormData.label: "Profile:"
            model: form.profiles.map(function (p) { return p.name })
            onActivated: function (i) { form.applyProfile(i) }
        }
        Note { visible: secE.open; text: ["Smooth: 60 updates a second, packets and glowing lines, every pulse, more hotspot cells, two orbits of satellite track. Load guard only for heavy load.",
                      "20 updates a second while something is newly reported, then still: pulses on news only (a hurricane or a red flood that pulsed for its whole life kept the screen redrawing 20 times a second for days), packets on the lines, 25+ detection hotspot cells, one orbit of track. Load guard at 70 / 90 %.",
                      "10 updates a second, steady lines, pulses only on news, 50+ detection hotspot cells, short track, standard borders. Load guard at 50 / 80 %.",
                      "Your own mix of the settings below."][profile.currentIndex] }
        Kirigami.Heading { visible: secE.open; Kirigami.FormData.isSection: true; level: 4; text: "Where you are"; topPadding: Kirigami.Units.largeSpacing }
        Loader {
            visible: secE.open
            id: citySearch
            Kirigami.FormData.label: "Home city:"
            source: "CitySearch.qml"
            onLoaded: {
                item.query = form.cfg_HomeCity;
                item.picked.connect(function (lat, lon, name) {
                    homeLat.text = String(lat); homeLon.text = String(lon); form.cfg_HomeCity = name;
                });
            }
        }
        RowLayout {
            visible: secE.open
            Kirigami.FormData.label: "Home:"
            QQC2.TextField { id: homeLat; Layout.preferredWidth: Kirigami.Units.gridUnit * 8; placeholderText: "latitude, e.g. 52.37"; validator: DoubleValidator { bottom: -90; top: 90; decimals: 4; locale: "C" } }
            QQC2.TextField { id: homeLon; Layout.preferredWidth: Kirigami.Units.gridUnit * 8; placeholderText: "longitude, e.g. 4.90"; validator: DoubleValidator { bottom: -180; top: 180; decimals: 4; locale: "C" } }
        }
        Note { visible: secE.open; text: (citySearch.status === Loader.Error ? "The city search could not be loaded; type the coordinates. " : "Searched offline in Natural Earth's list of about 7 000 towns and cities (part of the border download); pick one to fill in the coordinates, or type them. ") + "Where you are decides where the network arcs start and what Coverage says about your area; nothing about it leaves this machine." }
        Kirigami.Heading { visible: secE.open; Kirigami.FormData.isSection: true; level: 4; text: "On screen"; topPadding: Kirigami.Units.largeSpacing }
        MirrorCombo { visible: secE.open; Kirigami.FormData.label: "Show:"; twin: framePreset }
        MirrorCombo { visible: secE.open; Kirigami.FormData.label: "Fit to screen:"; twin: fillMode }
        Note { visible: secE.open && form.fitPreview !== ""; text: form.fitPreview }
        Kirigami.Heading { visible: secE.open; Kirigami.FormData.isSection: true; level: 4; text: "Events widget"; topPadding: Kirigami.Units.largeSpacing }
        // the companion widget: a card that says what it is and puts it on the desktop (helper `widget --add`, through
        // plasmashell's scripting interface), points at the Store when it is not installed, and says when it is there
        RowLayout {
            visible: secE.open
            Kirigami.FormData.label: "Events widget:"
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 34
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon { source: "view-list-details"; implicitWidth: Kirigami.Units.iconSizes.large; implicitHeight: implicitWidth; Layout.alignment: Qt.AlignTop }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "A live list of what the map is showing - newest first, the same switches as here - that sits on the desktop beside the map, opens each event's source, and fades out of the way when you are not using it."
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Button {
                        visible: form.widgetInfo.installed === true && !(form.widgetInfo.placed && form.widgetInfo.placed.length > 0)
                        enabled: !form.widgetBusy
                        text: "Add it to this desktop"; icon.name: "list-add"
                        onClicked: form.widgetRun("--add")
                    }
                    QQC2.Button {
                        visible: form.widgetInfo.installed === false
                        text: "Get it from the KDE Store"; icon.name: "get-hot-new-stuff"
                        onClicked: Qt.openUrlExternally(form.widgetInfo.store || "https://store.kde.org")
                    }
                    QQC2.Label {
                        visible: form.widgetInfo.placed && form.widgetInfo.placed.length > 0
                        text: "✓ On " + (form.widgetInfo.placed && form.widgetInfo.placed.length > 1 ? form.widgetInfo.placed.length + " desktops" : "this desktop")
                        color: Kirigami.Theme.positiveTextColor
                    }
                    QQC2.Label { visible: form.widgetInfo.installed === false; text: "Not installed (livemap.sh install puts it in with the wallpaper)"; opacity: 0.7 }
                    QQC2.BusyIndicator { visible: form.widgetBusy; running: visible; implicitHeight: Kirigami.Units.gridUnit * 1.2; implicitWidth: implicitHeight }
                }
                QQC2.Label { visible: !!form.widgetInfo.error; text: form.widgetInfo.error || ""; color: Kirigami.Theme.negativeTextColor; wrapMode: Text.Wrap; Layout.fillWidth: true }
                QQC2.Label { visible: form.widgetInfo.installed === true && form.widgetInfo.placed === null; text: "Could not ask plasmashell whether it is on a desktop; add it from the desktop's Add Widgets panel if not."; opacity: 0.7; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        RowLayout {
            visible: secE.open && (form.widgetHidden.length > 0 || !!form.widgetMode.pause || !!form.widgetMode.plain)
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 34
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            Kirigami.Icon { source: "dialog-warning"; implicitWidth: Kirigami.Units.iconSizes.smallMedium; implicitHeight: implicitWidth }
            QQC2.Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: "The companion widget is overriding the map (Map controls): " + [form.widgetHidden.length > 0 ? "hiding " + form.widgetHidden.join(", ") : "",
                       form.widgetMode.pause ? "animations paused" : "", form.widgetMode.plain ? "plain map" : ""].filter(function (t) { return t !== ""; }).join("; ")
                      + ". A layer switched on below stays off the map while the widget hides it."
            }
            QQC2.Button { text: "Clear the widget's overrides"; icon.name: "edit-clear"; onClicked: { modeExec.connectSource("python3 '" + form.widgetHelper + "' mode --clear # " + Date.now()); } }
        }
        Note { visible: secE.open; text: "A layer's switch on the left is its Show box: a layer that is off costs nothing, it is not even loaded. Each page keeps the same order: Show, Look, Labels, Behaviour." }

        // #################################################################### Map base

        // ==================================================================== Map
        SectionHeader { id: sec1; title: "Map"; group: "Map"; sourceNames: ["Seasonal maps (NASA Blue Marble)", "Hi-res seasonal maps (NASA Blue Marble, for regions)", "NASA image server"]; twin: null; summary: mapStyle.currentText.replace(/ \(.*\)/, "") + (mapTone.currentIndex > 0 && mapStyle.currentIndex < 3 ? ", " + mapTone.currentText.toLowerCase() : "") + " · " + framePreset.currentText + " · " + fillMode.currentText }
        Source { visible: sec1.open; names: ["Seasonal maps (NASA Blue Marble)", "Hi-res seasonal maps (NASA Blue Marble, for regions)", "NASA image server"] }

        QQC2.ComboBox {
            visible: sec1.open
            id: mapStyle
            Kirigami.FormData.label: "Base map:"
            model: ["Seasonal Blue Marble (NASA, monthly)", "Today's satellite view (NASA GIBS, daily)", "Blue Marble with relief and bathymetry (NASA GIBS)", "Dark cartographic (no imagery, your colours)", "Dark Matter (no imagery, greys)", "Matrix (no imagery, phosphor green)"]
        }
        Note {
            visible: sec1.open
            text: ["NASA's Blue Marble Next Generation: one cloud-free composite per month, so the snow line and the vegetation follow the seasons. Downloaded once (fetch-maps); the whole world needs nothing more.",
                   "The actual picture from the last day's orbits (Suomi NPP VIIRS corrected reflectance): clouds, snow, smoke and sea ice as they were yesterday, with the seams and night gaps a polar orbit leaves. Fetched for the frame on screen once a day (python3-pillow needed), a few MB.",
                   "NASA's Blue Marble with shaded terrain and the ocean floor, static. Fetched once for the frame on screen (python3-pillow needed).",
                   "No imagery at all: land and ocean as flat colours from the border data, so the events and labels carry the picture. The lightest on the GPU; the border download is needed.",
                   "The flat dark basemap look: land in dark grey over a near-black ocean, from the border data; the lightest on the GPU.",
                   "Black ocean, land in the darkest green, a faint graticule every 10 degrees, every label in a monospace face with a green glow, and scanlines over everything."][mapStyle.currentIndex]
        }
        RowLayout {
            visible: sec1.open && mapStyle.currentIndex === 3
            Kirigami.FormData.label: "Map colours:"
            KQuickControls.ColorButton { id: landColor; showAlphaChannel: false; dialogTitle: "Land colour" }
            QQC2.Label { text: "land" }
            KQuickControls.ColorButton { id: oceanColor; showAlphaChannel: false; dialogTitle: "Ocean colour" }
            QQC2.Label { text: "ocean" }
        }
        Note { visible: sec1.open && mapStyle.currentIndex >= 4; text: "The base sets the land and ocean only. To take the style's recommended line, name and event colours as well, pick it under Style at the top of the page; everything it sets can be changed afterwards." }
        QQC2.ComboBox {
            visible: sec1.open
            id: mapTone
            Kirigami.FormData.label: "Map tone:"
            enabled: mapStyle.currentIndex < 3
            model: ["Natural", "Muted", "Monochrome", "Blue-tinted", "Sepia"]
        }
        QQC2.CheckBox {
            visible: sec1.open && mapStyle.currentIndex === 0
            id: seasonal
            Kirigami.FormData.label: "Base map:"
            text: "Follow the seasons (NASA monthly images)"
        }
        QQC2.CheckBox { visible: sec1.open && mapStyle.currentIndex === 0; id: seasonalBlend; enabled: seasonal.checked; text: "Cross-fade between months day by day" }
        QQC2.CheckBox { visible: sec1.open && mapStyle.currentIndex === 0; id: seasonalHires; enabled: seasonal.checked; text: "Cut every view from the hi-res maps once they are downloaded (unticked: the 5 400 px maps, cut only for a region)" }
        RowLayout {
            visible: sec1.open
            Kirigami.FormData.label: seasonal.checked ? "Fallback image:" : "Image:"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            QQC2.TextField { id: baseImage; Layout.fillWidth: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 8; Layout.maximumWidth: Kirigami.Units.gridUnit * 26; placeholderText: "/path/to/equirectangular-2x1.jpg" }
            QQC2.Button { icon.name: "document-open"; onClicked: picker.open() }
        }
        // Framing: which part of the world must be on screen, and how it is fitted to the screen's shape

        QQC2.ComboBox {
            visible: sec1.open
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
            visible: sec1.open
            Kirigami.FormData.label: "North to south:"
            QQC2.SpinBox {
                id: frameNorth
                from: -80; to: 90
                textFromValue: function (v) { return form.degrees(v, "N", "S") }
                valueFromText: function (t) { return form.fromDegrees(t, "S") }
                onValueModified: framePreset.currentIndex = form.framePresetIndex()
            }
            QQC2.SpinBox {
                id: frameSouth
                from: -90; to: 80
                textFromValue: function (v) { return form.degrees(v, "N", "S") }
                valueFromText: function (t) { return form.fromDegrees(t, "S") }
                onValueModified: framePreset.currentIndex = form.framePresetIndex()
            }
        }
        RowLayout {
            visible: sec1.open
            Kirigami.FormData.label: "West to east:"
            QQC2.SpinBox {
                id: frameWest
                from: -180; to: 170; stepSize: 5
                textFromValue: function (v) { return form.degrees(v, "E", "W") }
                valueFromText: function (t) { return form.fromDegrees(t, "W") }
                onValueModified: framePreset.currentIndex = form.framePresetIndex()
            }
            QQC2.SpinBox {
                id: frameEast
                from: -170; to: 180; stepSize: 5
                textFromValue: function (v) { return form.degrees(v, "E", "W") }
                valueFromText: function (t) { return form.fromDegrees(t, "W") }
                onValueModified: framePreset.currentIndex = form.framePresetIndex()
            }
        }
        Note {
            visible: sec1.open
            text: "A region fills the screen with that part of the world, so there is room for more: smaller quakes, every state name, cities down to 100 000, every platform named. The frame must be at least 10° wide and 5° tall and cannot cross the date line yet. Imagery is built for exactly what is on screen - edge to edge, whatever the fit - cut from the monthly maps (the 5 400 px set is soft beyond about 2x: download the hi-res set on the source line above and every view, the whole world included, is cut from the 21 600 px maps instead) or fetched from NASA GIBS for the other styles, by the wallpaper itself when the view or the style changes; the 'Map style imagery' row under Status lists what has been built."
        }
        QQC2.ComboBox {
            visible: sec1.open
            id: fillMode
            Kirigami.FormData.label: "Fit to screen:"
            model: ["Stretch to fill", "Fit, true proportions", "Crop, true proportions", "Fill, true proportions, trimming the edges"]
        }
        Note {
            visible: sec1.open
            text: ["Stretch: all of the chosen area fills the screen; shapes get taller or wider as needed.",
                   "Fit: all of the chosen area at true proportions; spare space shows more map, or bars.",
                   "Crop: true proportions filling the screen, trimmed where it does not fit.",
                   "Fill: Fit without bars. All of the chosen area at true proportions, with more map around it where the screen has room instead of bars; the view zooms in only as far as it must to stay inside the world, so the whole world on a 16:10 screen loses the middle of the Pacific (on a wide screen, the poles), like a printed map."][fillMode.currentIndex]
        }
        // what this screen will actually show for the frame and mode: the same sums as main.qml, so a 16:10 laptop learns
        // here that every full-width frame comes out as the whole latitude range in Fill mode
        Note { visible: sec1.open && form.fitPreview !== ""; text: form.fitPreview }
        Amount {
            visible: sec1.open
            Kirigami.FormData.label: "Dim the imagery:"
            to: 80
            value: form.cfg_MapDim
            onValueChanged: form.cfg_MapDim = value
        }
        QQC2.ComboBox {
            visible: sec1.open
            id: hintCorner
            Kirigami.FormData.label: "Notices:"
            model: ["Bottom right corner", "Bottom left corner", "Top right corner", "Top left corner", "Never show on the desktop"]
        }
        Hours { visible: sec1.open; id: staleHours; Kirigami.FormData.label: "Complain after:"; from: 0; to: 168 }
        Note { visible: sec1.open; text: "Every feed keeps its last good data: a failed fetch is retried quietly and the map keeps drawing. A notice appears only when a source has had no successful update for this many hours (0 = at once). The Status section always shows the full detail." }
        QQC2.TextField {
            visible: sec1.open
            id: dataDir
            Kirigami.FormData.label: "Data folder:"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: "~/.local/share/livemap (default)"
        }

        // ============================================================ Day and night
        SectionHeader { id: sec2; title: "Day and night"; group: "Map"; keywords: "night mode dark terminator sun dusk city lights"; sourceNames: ["City lights (NASA Black Marble)"]; twin: dayNight; summary: (dayNight.checked ? (nightMode.currentIndex === 1 ? "Night everywhere" : nightMode.currentIndex === 2 ? "Night everywhere during your night" : "Night side") + " " + form.cfg_NightDarkness + " % dark" : "No day and night") + (cityLights.checked ? " · city lights" : "") }
        Source { visible: sec2.open; names: ["City lights (NASA Black Marble)"] }

        QQC2.CheckBox { visible: sec2.open; id: dayNight; Kirigami.FormData.label: "Sun:"; text: "Day and night" }
        QQC2.ComboBox {
            visible: sec2.open
            id: nightMode
            Kirigami.FormData.label: "Night:"
            enabled: dayNight.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            model: ["Where the sun has set (the terminator moves across the map)", "Everywhere, all the time", "Everywhere during your own night, the terminator by day"]
        }
        Note { visible: sec2.open; text: ["The night side follows the sun: a dusk band sweeps round the world once a day, and the city lights come on behind it.",
                                           "The whole map sits in night: the imagery dimmed to the darkness below everywhere, the city lights (if on) everywhere. A night map, whatever the hour.",
                                           "From civil dusk to civil dawn where you are (the home place on Essentials - the sun more than 6° under your horizon) the whole map is night, with the city lights everywhere; by day the terminator moves across the map as usual. A map that goes dark when your room does."][nightMode.currentIndex]
                                          + (nightMode.currentIndex === 2 && (homeLat.text === "" || homeLon.text === "") ? " No home place is set yet: until it is, the terminator is used." : "") }
        Amount {
            visible: sec2.open
            Kirigami.FormData.label: "Night darkness:"
            enabled: dayNight.checked
            from: 20
            value: form.cfg_NightDarkness
            onValueChanged: form.cfg_NightDarkness = value
        }
        Amount {
            visible: sec2.open
            Kirigami.FormData.label: "Dusk band:"
            enabled: dayNight.checked
            from: 2; to: 30; suffix: "° wide"
            value: form.cfg_Twilight
            onValueChanged: form.cfg_Twilight = value
        }
        QQC2.CheckBox { visible: sec2.open; id: cityLights; Kirigami.FormData.label: "City lights:"; enabled: dayNight.checked; text: "City lights on the night side" }
        Amount {
            visible: sec2.open
            Kirigami.FormData.label: "City lights brightness:"
            enabled: dayNight.checked && cityLights.checked
            from: 10
            value: form.cfg_LightsBrightness
            onValueChanged: form.cfg_LightsBrightness = value
        }
        QQC2.CheckBox { visible: sec2.open; id: lightsGpu; enabled: dayNight.checked && cityLights.checked; text: "Sharper lights through a GPU mask" }
        Note { visible: sec2.open && lightsGpu.checked; text: "Experimental: untick if the lights vanish." }

        SectionHeader { id: sec18; title: "Clouds"; group: "Map"; sourceNames: ["Cloud image (matteason.co.uk)", "Cloud stitching (NASA GIBS, EUMETView)"]; twin: clouds; summary: clouds.checked ? cloudSource.currentText + " · " + form.cfg_CloudOpacity + " %" : "Off" }
        Source { visible: sec18.open; names: ["Cloud image (matteason.co.uk)", "Cloud stitching (NASA GIBS, EUMETView)"] }
        QQC2.CheckBox { visible: sec18.open; id: clouds; Kirigami.FormData.label: "Clouds:"; text: "Live cloud cover" }
        QQC2.ComboBox {
            visible: sec18.open
            id: cloudSource
            Kirigami.FormData.label: "Cloud source:"
            enabled: clouds.checked
            model: ["Ready-made image; stitch from satellites if it fails", "Always stitch from the satellites", "Ready-made image only"]
        }
        Note { visible: sec18.open; text: "Ready-made: one 5 MB image every 3 hours from clouds.matteason.co.uk. Stitched: the helper fetches infrared images from five geostationary satellites (GOES-East, GOES-West and Himawari via NASA GIBS; Meteosat 0° and Indian Ocean via EUMETView, all public, no key), lays them side by side and turns cloud-top brightness into cloud cover - about 6 MB and a few seconds every 3 hours. A satellite that fails keeps its last picture, so an outage of one source only stales one region. With python3-pillow installed the stitched image is 2048 px wide; without it 1024 px, in pure Python." }
        Amount {
            visible: sec18.open
            Kirigami.FormData.label: "Cloud opacity:"
            enabled: clouds.checked
            from: 10
            value: form.cfg_CloudOpacity
            onValueChanged: form.cfg_CloudOpacity = value
        }

        // #################################################################### Geographic layers

        // ============================================================== Countries
        SectionHeader { id: sec3; title: "Countries"; group: "Map"; sourceNames: ["Borders (Natural Earth)"]; twin: borders; summary: (borders.checked ? "Borders " + form.cfg_BorderOpacity + " %" + (coast.checked ? ", coastlines" : "") + (stateLines.checked ? ", states" : "") : "Off") + (countryNames.checked ? " · country names " + nameSize.value + " px" : "") + (stateNames.checked ? " · state names" : "") + (capitals.checked ? " · capitals" : "") + (stateCapitals.checked ? " · state capitals" : "") + (cities.checked ? " · cities over " + cityMinPop.currentText : "") }
        Source { visible: sec3.open; names: ["Borders (Natural Earth)"] }

        QQC2.CheckBox { visible: sec3.open; id: borders; Kirigami.FormData.label: "Show:"; text: "Country borders (Natural Earth)" }
        QQC2.CheckBox { visible: sec3.open; id: coast; enabled: borders.checked; text: "Coastlines" }
        QQC2.CheckBox { visible: sec3.open; id: stateLines; enabled: borders.checked; text: "States and provinces" }
        QQC2.ComboBox {
            visible: sec3.open
            id: borderDetail
            Kirigami.FormData.label: "Detail:"
            enabled: borders.checked
            model: ["Standard (1:110 million)", "Detailed (1:50 million, for 4K)"]
        }
        KQuickControls.ColorButton { visible: sec3.open; id: borderColor; Kirigami.FormData.label: "Border line colour:"; enabled: borders.checked; showAlphaChannel: false; dialogTitle: "Border colour" }
        Amount {
            visible: sec3.open
            Kirigami.FormData.label: "Border line opacity:"
            enabled: borders.checked
            from: 5
            value: form.cfg_BorderOpacity
            onValueChanged: form.cfg_BorderOpacity = value
        }
        Amount {
            visible: sec3.open
            Kirigami.FormData.label: "Border line thickness:"
            enabled: borders.checked
            from: 30; to: 400
            value: form.cfg_BorderWidth
            onValueChanged: form.cfg_BorderWidth = value
        }
        QQC2.CheckBox { visible: sec3.open; id: countryNames; Kirigami.FormData.label: "Country names:"; enabled: borders.checked; text: "Country names" }
        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "Country name density:"
            enabled: borders.checked && countryNames.checked
            QQC2.ComboBox { id: nameDensity; model: ["Only the largest", "Most countries", "All that fit"] }
            Px { id: nameSize; from: 5; to: 40 }
        }
        Note { visible: sec3.open; text: "The largest countries are printed a quarter bigger than the size chosen." }
        LabelStyle { visible: sec3.open; id: nameStyle; label: "Country name style:"; enabled: borders.checked && countryNames.checked; plated: namePlate.checked }
        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "Country name text:"
            enabled: borders.checked && countryNames.checked
            QQC2.CheckBox { id: namePlate; text: "Plate" }
            QQC2.CheckBox { id: nameFollows; text: "Text follows the line colour" }
            KQuickControls.ColorButton { id: nameTextColor; enabled: !nameFollows.checked; showAlphaChannel: false; dialogTitle: "Country name colour" }
        }
        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "State names:"
            enabled: borders.checked
            QQC2.CheckBox { id: stateNames; text: "State and province names" }
            QQC2.ComboBox { id: stateNameDensity; enabled: stateNames.checked; model: ["Major regions", "Most", "All that fit"] }
            Px { id: stateNameSize; enabled: stateNames.checked; from: 5; to: 24 }
        }
        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "State name text:"
            enabled: borders.checked && stateNames.checked
            QQC2.CheckBox { id: stateNameFollows; text: "Text follows the country name colour" }
            KQuickControls.ColorButton { id: stateNameTextColor; enabled: !stateNameFollows.checked; showAlphaChannel: false; dialogTitle: "State name colour" }
        }
        LabelStyle { visible: sec3.open; id: stateNameStyle; label: "State name style:"; enabled: borders.checked && stateNames.checked; plated: namePlate.checked }
        Note { visible: sec3.open; text: "Natural Earth's admin-1 label points (4 600 regions), fitted around the country names; part of the border download." }

        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "Country capitals:"
            enabled: borders.checked
            QQC2.CheckBox { id: capitals; text: "Show" }
            QQC2.ComboBox { id: capitalMarks; enabled: capitals.checked; model: ["Dot and name", "Dot only", "Name only"] }
            Px { id: capitalSize; enabled: capitals.checked; from: 4; to: 24 }
            KQuickControls.ColorButton { id: capitalColor; enabled: capitals.checked; showAlphaChannel: false; dialogTitle: "Country capital colour" }
        }
        LabelStyle { visible: sec3.open; id: capitalStyle; label: "Country capital style:"; enabled: borders.checked && capitals.checked && capitalMarks.currentIndex !== 1; plated: false }
        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "State capitals:"
            enabled: borders.checked
            QQC2.CheckBox { id: stateCapitals; text: "Show" }
            QQC2.ComboBox { id: stateCapitalMarks; enabled: stateCapitals.checked; model: ["Dot and name", "Dot only", "Name only"] }
            Px { id: stateCapitalSize; enabled: stateCapitals.checked; from: 4; to: 24 }
            KQuickControls.ColorButton { id: stateCapitalColor; enabled: stateCapitals.checked; showAlphaChannel: false; dialogTitle: "State capital colour" }
        }
        LabelStyle { visible: sec3.open; id: stateCapitalStyle; label: "State capital style:"; enabled: borders.checked && stateCapitals.checked && stateCapitalMarks.currentIndex !== 1; plated: false }
        RowLayout {
            visible: sec3.open
            Kirigami.FormData.label: "Cities:"
            enabled: borders.checked
            QQC2.CheckBox { id: cities; text: "Over" }
            QQC2.ComboBox { id: cityMinPop; enabled: cities.checked; model: ["500 000", "1 million", "5 million", "10 million"] }
            QQC2.ComboBox { id: cityMarks; enabled: cities.checked; model: ["Dot and name", "Dot only", "Name only"] }
            Px { id: citySize; enabled: cities.checked; from: 4; to: 24 }
            KQuickControls.ColorButton { id: cityColor; enabled: cities.checked; showAlphaChannel: false; dialogTitle: "City colour" }
        }
        QQC2.CheckBox { visible: sec3.open; id: cityPopScale; Kirigami.FormData.label: "City dots:"; enabled: borders.checked && cities.checked && cityMarks.currentIndex !== 2; text: "Sized by population" }
        LabelStyle { visible: sec3.open; id: cityStyle; label: "City name style:"; enabled: borders.checked && cities.checked && cityMarks.currentIndex !== 1; plated: false }
        Note { visible: sec3.open; text: "A country capital is a ringed dot, a state capital a dot, a city a small dot (or one sized by population). Placed after the country names: capitals first, then cities by size, then state names, so the important ones win the space. Natural Earth populated places, part of the border download." }

        // ================================================================= Rivers
        SectionHeader { id: sec4; title: "Rivers, lakes and seas"; group: "Map"; sourceNames: ["Borders (Natural Earth)"]; twin: rivers
                        summary: (rivers.checked ? (riverDetail.currentIndex === 0 ? "The 13 great rivers, " : "All rivers, ") + form.cfg_RiverOpacity + " %, " + form.cfg_RiverWidth + " % thick" : "No rivers")
                                 + (lakes.checked ? " · lakes" : "") + (lakeNames.checked || seaNames.checked ? " · " + [lakeNames.checked ? "lake" : "", seaNames.checked ? "sea" : ""].filter(function (t) { return t !== ""; }).join(" and ") + " names " + waterNameSize.value + " px" : "") }
        Source { visible: sec4.open; names: ["Borders (Natural Earth)"] }
        QQC2.CheckBox { visible: sec4.open; id: rivers; Kirigami.FormData.label: "Rivers:"; text: "Rivers and lake centrelines (Natural Earth)" }
        QQC2.ComboBox { visible: sec4.open; id: riverDetail; Kirigami.FormData.label: "River detail:"; enabled: rivers.checked; model: ["The 13 great rivers (Amazon, Nile, Mississippi…)", "All 460 (every named river Natural Earth draws at 1:50M)"] }
        Note { visible: sec4.open; text: "Independent of the Countries detail level: the detailed borders are 100 000 segments, the detailed rivers 462 lines, so the full set costs next to nothing on any profile." }
        KQuickControls.ColorButton { visible: sec4.open; id: riverColor; Kirigami.FormData.label: "River line colour:"; enabled: rivers.checked; showAlphaChannel: false; dialogTitle: "River colour" }
        Amount {
            visible: sec4.open
            Kirigami.FormData.label: "River line opacity:"
            enabled: rivers.checked
            from: 5
            value: form.cfg_RiverOpacity
            onValueChanged: form.cfg_RiverOpacity = value
        }
        Amount {
            visible: sec4.open
            Kirigami.FormData.label: "River line thickness:"
            enabled: rivers.checked
            from: 30; to: 400
            value: form.cfg_RiverWidth
            onValueChanged: form.cfg_RiverWidth = value
        }
        Note { visible: sec4.open; text: "Drawn under the coastlines at the Countries detail level; part of the border download. With the detailed rivers over the plain Countries level, each river mouth is carried on to the coast." }
        QQC2.CheckBox { visible: sec4.open; id: lakes; Kirigami.FormData.label: "Lakes:"; text: "Lake outlines, in the river colour, at the river detail level" }
        Amount {
            visible: sec4.open
            Kirigami.FormData.label: "Lake fill:"
            enabled: lakes.checked
            from: 0; to: 100
            value: form.cfg_LakeFill
            onValueChanged: form.cfg_LakeFill = value
        }
        Note { visible: sec4.open; text: "The 24 great lakes with the 13 great rivers, 412 lakes and reservoirs with all rivers. 0 % fill is an outline only; the river line's colour, opacity and thickness are the lake's." }
        RowLayout {
            visible: sec4.open
            Kirigami.FormData.label: "Lake names:"
            QQC2.CheckBox { id: lakeNames; text: "Show" }
            QQC2.ComboBox { id: lakeNameDensity; enabled: lakeNames.checked; model: ["The great lakes", "Every named lake"] }
        }
        RowLayout {
            visible: sec4.open
            Kirigami.FormData.label: "Sea names:"
            QQC2.CheckBox { id: seaNames; text: "Show" }
            QQC2.ComboBox { id: seaNameDensity; enabled: seaNames.checked; model: ["The oceans", "Oceans and seas", "Oceans, seas, gulfs and bays", "Everything, straits and channels too"] }
        }
        RowLayout {
            visible: sec4.open
            Kirigami.FormData.label: "Water name text:"
            enabled: lakeNames.checked || seaNames.checked
            Px { id: waterNameSize; from: 5; to: 28 }
            QQC2.CheckBox { id: waterNameItalic; text: "Italic" }
            QQC2.CheckBox { id: waterNameFollows; text: "River colour" }
            KQuickControls.ColorButton { id: waterNameTextColor; enabled: !waterNameFollows.checked; showAlphaChannel: false; dialogTitle: "Water name colour" }
        }
        LabelStyle { visible: sec4.open; id: waterNameStyle; label: "Water name style:"; enabled: lakeNames.checked || seaNames.checked; plated: false }
        Note { visible: sec4.open; text: "Oceans are written at 1.5x the size, seas at 1.15x, small lakes at 0.85x; a name goes only where the water is wide enough for it, after the country names, places and state names. Italic is the map convention for water. The lake and sea files are fetched once, the first time they are asked for (part of the border download from now on)." }

        // ============================================================== Time zones
        SectionHeader { id: sec5; title: "Time zones"; group: "Map"; sourceNames: ["Borders (Natural Earth)"]; twin: timeZones; summary: timeZones.checked ? "Zone outlines " + form.cfg_ZoneOpacity + " %" + (zoneLabels.checked ? " · " + zoneClock.currentText.toLowerCase() + " " + zoneLabelSize.value + " px, " + form.zoneStyles[zoneLook.currentIndex].name.split(":")[0].toLowerCase() : "") : "Off" }
        Source { visible: sec5.open; names: ["Borders (Natural Earth)"] }
        QQC2.CheckBox { visible: sec5.open; id: timeZones; Kirigami.FormData.label: "Show:"; text: "Time zone outlines (Natural Earth)" }
        Note { visible: sec5.open; text: "The zone boundaries as drawn on the Natural Earth time zone map, with the UTC offset written in each zone that is wide enough. Part of the border download." }
        KQuickControls.ColorButton { visible: sec5.open; id: zoneColor; Kirigami.FormData.label: "Time zone line colour:"; enabled: timeZones.checked; showAlphaChannel: false; dialogTitle: "Time zone line colour" }
        Amount {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone line opacity:"
            enabled: timeZones.checked
            from: 5
            value: form.cfg_ZoneOpacity
            onValueChanged: form.cfg_ZoneOpacity = value
        }
        Amount {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone line thickness:"
            enabled: timeZones.checked
            from: 30; to: 400
            value: form.cfg_ZoneWidth
            onValueChanged: form.cfg_ZoneWidth = value
        }
        RowLayout {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone labels:"
            enabled: timeZones.checked
            QQC2.CheckBox { id: zoneLabels; text: "Labels" }
            QQC2.ComboBox { id: zoneClock; enabled: zoneLabels.checked; model: ["UTC offset", "Offset and local time", "Offset, time and date", "Local time", "Time and date"] }
            QQC2.CheckBox { id: zoneClock12; enabled: zoneLabels.checked && zoneClock.currentIndex > 0; text: "12-hour clock" }
            Px { id: zoneLabelSize; enabled: zoneLabels.checked; from: 4; to: 24 }
        }
        Note { visible: sec5.open && zoneClock.currentIndex > 0; text: "The clock is the real time of each zone's main place, summer time included, from the system's time zone database (the date goes on a second line). A zone that straddles places with different summer-time rules shows its main place's time. Updated every minute; the summer-time changes are known from the border download, so download again if a label looks an hour off." }
        RowLayout {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone label text:"
            enabled: timeZones.checked && zoneLabels.checked
            QQC2.CheckBox { id: zonePlate; text: "Plate" }
            QQC2.CheckBox { id: zoneTextFollows; text: "Text follows the line colour" }
            KQuickControls.ColorButton { id: zoneTextColor; enabled: !zoneTextFollows.checked; showAlphaChannel: false; dialogTitle: "Time zone label colour" }
        }
        LabelStyle { visible: sec5.open; id: zoneStyle; label: "Time zone label style:"; enabled: timeZones.checked && zoneLabels.checked; plated: zonePlate.checked }
        // One dropdown for the style: it sets the label placement and the tint together (ZoneStyle); the opacity
        // rows below belong to the styles that use them.
        RowLayout {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone style:"
            enabled: timeZones.checked
            QQC2.ComboBox { id: zoneLook; Layout.preferredWidth: Kirigami.Units.gridUnit * 24; model: form.zoneStyles.map(function (z) { return z.name }) }
            QQC2.SpinBox {
                id: zoneRowLat; enabled: form.zoneStyles[zoneLook.currentIndex].placement >= 1; from: -80; to: 80; stepSize: 5
                textFromValue: function (v) { return (v < 0 ? -v + "° S" : v > 0 ? v + "° N" : "0°") }
                valueFromText: function (t) { var n = parseInt(t) || 0; return /S/i.test(t) ? -Math.abs(n) : n }
                QQC2.ToolTip.text: "The latitude of the row or band"; QQC2.ToolTip.visible: hovered
            }
        }
        RowLayout {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone band:"
            enabled: timeZones.checked && zoneLabels.checked && form.zoneStyles[zoneLook.currentIndex].placement === 2
            QQC2.Label { text: "Opacity" }
            Pct { id: zoneBandOpacity; to: 100; label: "The band's dark strip; the labels keep their own opacity" }
            QQC2.CheckBox { id: zoneMarkHome; text: "Mark this computer's zone" }
        }
        RowLayout {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone band extras:"
            enabled: timeZones.checked && zoneLabels.checked && form.zoneStyles[zoneLook.currentIndex].placement === 2
            QQC2.CheckBox { id: zoneBandSun; text: "Day and night, with noon and midnight" }
            QQC2.CheckBox { id: zoneBandDiff; text: "Hours from this computer's zone" }
            QQC2.CheckBox { id: zoneAbbrev; text: "Abbreviations (CST, CET, JST\u2026)" }
        }
        Note { visible: sec5.open; text: "The band is a scale of the standard zones, every hour from UTC-12 to UTC+14 (and the half-hour zones), the way a printed time zone map is laid out; a zone on summer time right now shows its clock an hour on and says DST, or its summer abbreviation (CDT, BST, CEST) with abbreviations on. Day and night: the band is warm where the sun is up and cool where it is night at the band's latitude, graded through twilight, and two cursors mark where it is noon and midnight right now; all three slide along the band through the day. Hours from this computer's zone puts '+6 h' under each clock (and 'you' under your own). All of it is computed here; nothing on the band can go stale." }
        RowLayout {
            visible: sec5.open
            Kirigami.FormData.label: "Time zone tint:"
            enabled: timeZones.checked && form.zoneStyles[zoneLook.currentIndex].tint
            QQC2.Label { text: "Opacity" }
            Pct { id: zoneTintOpacity; to: 60; label: "How strongly the zones are coloured; 10-15 % keeps the imagery" }
        }
        Note { visible: sec5.open; text: "D1 tints each zone with a colour cycle, like a time zone map, so a zone's extent reads from the colour where the boundaries get busy; the outlines can then be faint and the labels large and translucent (raise the label size, lower its opacity). Drawn once from the time zone data (python3-pillow needed). D3 puts the clocks in a band across the map: the time large, the offset small above it, the date only where it is not this computer's date, with your own zone marked in amber." }
        Note { visible: sec5.open; text: "Inside each zone: one label per zone area, on the widest stretch of its middle, and never over a country name. In one row: every zone on one line of latitude, placed before the country names and places, which make way for it, the way printed time-zone maps do it - 55° S runs through open ocean for all 25 zones; make sure the frame (Map section) shows that latitude." }

        // #################################################################### Natural events

        // ============================================================ Earthquakes
        SectionHeader { id: sec6; title: "Earthquakes"; group: "Natural events"; sourceNames: ["Earthquake feed (USGS)", "Earthquakes, secondary (EMSC)"]; twin: quakes; summary: (quakes.checked ? quakeFeed.currentText + " · rings " + form.cfg_QuakeSize + " % · labels: " + quakeLabels.currentText.toLowerCase() + " · pulse: " + quakePulseMode.currentText.toLowerCase() : "Off") }
        Source { visible: sec6.open; names: ["Earthquake feed (USGS)", "Earthquakes, secondary (EMSC)"] }

        QQC2.CheckBox { visible: sec6.open; id: quakes; Kirigami.FormData.label: "Show:"; text: "Earthquakes (USGS)" }
        Amount {
            visible: sec6.open
            Kirigami.FormData.label: "Earthquake layer opacity:"
            enabled: quakes.checked
            from: 10; to: 100
            value: form.cfg_QuakeLayerOpacity
            onValueChanged: form.cfg_QuakeLayerOpacity = value
        }
        QQC2.ComboBox {
            visible: sec6.open
            id: quakeFeed
            Kirigami.FormData.label: "Earthquake feed:"
            enabled: quakes.checked
            model: ["Magnitude 2.5+, past day", "Magnitude 4.5+, past day", "Significant, past week"]
        }
        RowLayout {
            visible: sec6.open
            Kirigami.FormData.label: "Earthquake sources:"
            enabled: quakes.checked
            Repeater {
                model: [[1, "USGS"], [2, "EMSC (Europe-Mediterranean Seismological Centre)"]]
                QQC2.CheckBox {
                    required property var modelData
                    text: modelData[1]
                    checked: (form.cfg_QuakeSources & modelData[0]) !== 0
                    onToggled: form.cfg_QuakeSources = checked ? (form.cfg_QuakeSources | modelData[0]) : (form.cfg_QuakeSources & ~modelData[0])
                }
            }
        }
        Note { visible: sec6.open; text: "USGS lists every M4.5+ worldwide within minutes and is the authority for the US; EMSC collects the national networks' reports and lists the smaller quakes outside the US that USGS carries late or not at all (Europe, the Mediterranean, Latin America, Indonesia). The two are merged - the same quake within 120 km and 90 s is one - at the feed's magnitude floor, every 5 minutes." }
        KQuickControls.ColorButton { visible: sec6.open; id: quakeColor; Kirigami.FormData.label: "Earthquake ring colour:"; enabled: quakes.checked; showAlphaChannel: false; dialogTitle: "Earthquake ring colour" }
        Amount {
            visible: sec6.open
            Kirigami.FormData.label: "Earthquake ring size:"
            enabled: quakes.checked
            from: 10; to: 250
            value: form.cfg_QuakeSize
            onValueChanged: form.cfg_QuakeSize = value
        }
        RowLayout {
            visible: sec6.open
            Kirigami.FormData.label: "Earthquake labels:"
            enabled: quakes.checked
            QQC2.ComboBox { id: quakeLabels; model: ["None", "Magnitude", "Magnitude, place and age"] }
            QQC2.ComboBox { id: quakeLabelMin; enabled: quakeLabels.currentIndex > 0; model: ["for every quake", "from magnitude 5", "from magnitude 6"] }
            Px { id: quakeLabelSize; enabled: quakeLabels.currentIndex > 0; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec6.open
            Kirigami.FormData.label: "Earthquake label text:"
            enabled: quakes.checked && quakeLabels.currentIndex > 0
            QQC2.CheckBox { id: quakePlate; text: "Plate" }
            QQC2.CheckBox { id: quakeFollows; text: "Text follows the ring colour" }
            KQuickControls.ColorButton { id: quakeTextColor; enabled: !quakeFollows.checked; showAlphaChannel: false; dialogTitle: "Earthquake label colour" }
        }
        LabelStyle { visible: sec6.open; id: quakeStyle; label: "Earthquake label style:"; enabled: quakes.checked && quakeLabels.currentIndex > 0; plated: quakePlate.checked }
        QQC2.ComboBox {
            visible: sec6.open
            id: quakePulseMode
            Kirigami.FormData.label: "Earthquake pulse:"
            enabled: quakes.checked
            model: form.pulseChoices
        }
        RowLayout {
            visible: sec6.open
            Kirigami.FormData.label: "Earthquake significance:"
            enabled: quakes.checked && quakePulseMode.currentIndex >= 2
            QQC2.Label { text: "from magnitude" }
            QQC2.SpinBox {
                id: quakePulseMag
                from: 30; to: 90; stepSize: 1
                textFromValue: function (v) { return (v / 10).toFixed(1) }
                valueFromText: function (t) { return Math.round((parseFloat(t) || 5.5) * 10) }
            }
        }
        Note { visible: sec6.open; text: "Newly reported = it happened less than the 'Newly reported' hours ago (under Ageing and pulses). Quakes age from the moment they happened." }

        // ============================================================== Volcanoes
        SectionHeader { id: sec19; title: "Tectonic plates"; group: "Map"; sourceNames: ["Plate boundaries (PB2002)"]; twin: plates; summary: plates.checked ? "Plate boundaries, " + form.cfg_PlateLineOpacity + " %, " + form.cfg_PlateLineWidth + " % thick" : "Off" }
        Source { visible: sec19.open; names: ["Plate boundaries (PB2002)"] }
        QQC2.CheckBox { visible: sec19.open; id: plates; Kirigami.FormData.label: "Show:"; text: "Tectonic plate boundaries (PB2002)" }
        KQuickControls.ColorButton { visible: sec19.open; id: plateLineColor; Kirigami.FormData.label: "Tectonic line colour:"; enabled: plates.checked; showAlphaChannel: false; dialogTitle: "Plate boundary colour" }
        Amount {
            visible: sec19.open
            Kirigami.FormData.label: "Tectonic line opacity:"
            enabled: plates.checked
            from: 5
            value: form.cfg_PlateLineOpacity
            onValueChanged: form.cfg_PlateLineOpacity = value
        }
        Amount {
            visible: sec19.open
            Kirigami.FormData.label: "Tectonic line thickness:"
            enabled: plates.checked
            from: 30; to: 400
            value: form.cfg_PlateLineWidth
            onValueChanged: form.cfg_PlateLineWidth = value
        }
        Note { visible: sec19.open; text: "The boundaries between the tectonic plates, where most earthquakes and volcanoes sit. Still lines under the borders; they cost nothing while idle." }

        SectionHeader { id: sec20; title: "Oil and gas infrastructure"; group: "Map"; sourceNames: ["Oil and gas infrastructure (BSEE, OpenStreetMap)"]; twin: infra; summary: infra.checked ? [infraPlatforms.checked ? "offshore platforms" : "", infraRefineries.checked ? "refineries" : ""].filter(function (t) { return t !== "" }).join(" and ") + (infraMode.currentIndex === 0 ? " · only what a storm threatens" : " · always") + " · " + infraSize.value + " px · labels: " + infraLabels.currentText.toLowerCase() + (infraNameThreatened.checked ? ", threatened named" : "") : "Off" }
        Source { visible: sec20.open; names: ["Oil and gas infrastructure (BSEE, OpenStreetMap)"] }
        QQC2.CheckBox { visible: sec20.open; id: infra; Kirigami.FormData.label: "Show:"; text: "Fixed offshore platforms and refineries" }
        Amount {
            visible: sec20.open
            Kirigami.FormData.label: "Infrastructure layer opacity:"
            enabled: infra.checked
            from: 10; to: 100
            value: form.cfg_InfraLayerOpacity
            onValueChanged: form.cfg_InfraLayerOpacity = value
        }
        QQC2.ComboBox {
            visible: sec20.open
            id: infraMode
            Kirigami.FormData.label: "Infrastructure shown:"
            enabled: infra.checked
            model: ["Only what a storm threatens (in its forecast cone, or near its track)", "Everything, all the time"]
        }
        Note { visible: sec20.open; text: "A threatened platform or refinery is drawn larger with a ring; the storm's own label counts what is in its cone and what it has crossed, and the Events widget lists them under the storm. With no storm near any facility, the first choice draws nothing." }
        RowLayout {
            visible: sec20.open
            Kirigami.FormData.label: "Infrastructure kinds:"
            enabled: infra.checked
            QQC2.CheckBox { id: infraPlatforms; text: "Offshore platforms (squares)" }
            QQC2.CheckBox { id: infraRefineries; text: "Refineries (triangles)" }
        }
        RowLayout {
            visible: sec20.open
            Kirigami.FormData.label: "Infrastructure marks:"
            enabled: infra.checked
            KQuickControls.ColorButton { id: infraColor; showAlphaChannel: false; dialogTitle: "Infrastructure colour" }
            Px { id: infraSize; from: 3; to: 20 }
        }
        RowLayout {
            visible: sec20.open
            Kirigami.FormData.label: "Infrastructure labels:"
            enabled: infra.checked
            QQC2.ComboBox { id: infraLabels; model: ["None", "Refineries", "Refineries and named platforms"] }
            Px { id: infraLabelSize; enabled: infraLabels.currentIndex > 0 || infraNameThreatened.checked; from: 5; to: 20 }
        }
        QQC2.CheckBox { visible: sec20.open; id: infraNameThreatened; Kirigami.FormData.label: "Infrastructure threatened:"; enabled: infra.checked; text: "Named on the map with their storm (the widget lists them under the storm either way)" }
        LabelStyle { visible: sec20.open; id: infraStyle; label: "Infrastructure label style:"; enabled: infra.checked && (infraLabels.currentIndex > 0 || infraNameThreatened.checked); plated: false }
        Note { visible: sec20.open; text: "Fixed structures only: every platform on the US Gulf of Mexico shelf from BSEE (public domain, updated monthly) and offshore platforms elsewhere plus refineries from OpenStreetMap (ODbL, (c) OpenStreetMap contributors). Mobile drilling rigs are in no free feed. Still marks under the events; the download takes a minute or two because OpenStreetMap's Overpass service is slow." }

        SectionHeader { id: sec7; title: "Volcanoes"; group: "Natural events"; sourceNames: ["Volcanoes (Smithsonian / USGS)", "Eruption database (Smithsonian)", "Weekly report page (Smithsonian)", "Volcano alert levels (USGS)", "Volcano alert levels (GeoNet)", "Volcano alert levels (JMA)", "Ash advisories (Washington VAAC)"]; twin: volcanoes; summary: volcanoes.checked ? "Weekly report and USGS levels" + (volcanoAlertColors.checked ? ", colour by level" : "") + " · labels: " + volcanoLabels.currentText.toLowerCase() + " · pulse: " + volcanoPulseMode.currentText.toLowerCase() : "Off" }
        Source { visible: sec7.open; names: ["Volcanoes (Smithsonian / USGS)", "Eruption database (Smithsonian)", "Weekly report page (Smithsonian)", "Volcano alert levels (USGS)", "Volcano alert levels (GeoNet)", "Volcano alert levels (JMA)", "Ash advisories (Washington VAAC)"] }

        QQC2.CheckBox { visible: sec7.open; id: volcanoes; Kirigami.FormData.label: "Show:"; text: "Weekly report and USGS alert levels" }
        Amount {
            visible: sec7.open
            Kirigami.FormData.label: "Volcano layer opacity:"
            enabled: volcanoes.checked
            from: 10; to: 100
            value: form.cfg_VolcanoLayerOpacity
            onValueChanged: form.cfg_VolcanoLayerOpacity = value
        }
        Note { visible: sec7.open; text: "The Smithsonian / USGS Weekly Volcanic Activity Report comes out every Wednesday ('New' there means an eruption after at least three months of quiet). US volcanoes also carry the USGS alert level (Advisory, Watch, Warning), checked every hour, with the date the level was raised where USGS provides it." }
        KQuickControls.ColorButton { visible: sec7.open; id: volcanoColor; Kirigami.FormData.label: "Volcano colour:"; enabled: volcanoes.checked; showAlphaChannel: false; dialogTitle: "Volcano colour" }
        QQC2.CheckBox { visible: sec7.open; id: volcanoAlertColors; enabled: volcanoes.checked; text: "Colour by level (yellow, orange, red)" }
        Note { visible: sec7.open; text: "One scale for every volcano: yellow = active (in the weekly report, or USGS Advisory), orange = USGS Watch or a 'New' eruption in the report, red = USGS Warning. Untick for the single colour above." }
        RowLayout {
            visible: sec7.open
            Kirigami.FormData.label: "Volcano labels:"
            enabled: volcanoes.checked
            QQC2.ComboBox { id: volcanoLabels; model: ["None", "New eruptions only", "All"] }
            Px { id: volcanoLabelSize; from: 4; to: 24 }
        }
        QQC2.CheckBox { visible: sec7.open; id: volcanoDetail; enabled: volcanoes.checked && volcanoLabels.currentIndex > 0; text: "Add how long it has been above normal" }
        Note { visible: sec7.open; text: "Label: the name, then how long the volcano has been above normal: USGS's date for a US alert level, else the eruption start date from the Smithsonian database. Nothing when neither is known. Colour, a bolder triangle and the pulse say the rest." }
        RowLayout {
            visible: sec7.open
            Kirigami.FormData.label: "Volcano label text:"
            enabled: volcanoes.checked && volcanoLabels.currentIndex > 0
            QQC2.CheckBox { id: volcanoPlate; text: "Plate" }
            QQC2.CheckBox { id: volcanoFollows; text: "Text follows the volcano colour" }
            KQuickControls.ColorButton { id: volcanoTextColor; enabled: !volcanoFollows.checked; showAlphaChannel: false; dialogTitle: "Volcano label colour" }
        }
        LabelStyle { visible: sec7.open; id: volcanoStyle; label: "Volcano label style:"; enabled: volcanoes.checked && volcanoLabels.currentIndex > 0; plated: volcanoPlate.checked }
        QQC2.ComboBox {
            visible: sec7.open
            id: volcanoPulseMode
            Kirigami.FormData.label: "Volcano pulse:"
            enabled: volcanoes.checked
            model: form.pulseChoices
        }
        Note { visible: sec7.open; text: "Newly reported = it appeared, or its level changed, less than the 'Newly reported' hours ago: the default, so a volcano pulses when there is news and then sits steady. Significant = orange and red, if you want those to keep pulsing. A volcano ages once it drops out of the report." }

        // ================================================================= Storms
        SectionHeader { id: sec8; title: "Storms"; group: "Natural events"; sourceNames: ["Storms (GDACS)", "Storms, secondary (NHC)", "Storms, secondary (JTWC)"]; twin: storms; summary: storms.checked ? stormMarkerStyle.currentText + (stormIntensityColors.checked ? " · colour by intensity" : "") + (stormCone.checked ? " · cone" : "") + " · labels: " + stormLabels.currentText.toLowerCase() : "Off" }
        Source { visible: sec8.open; names: ["Storms (GDACS)", "Storms, secondary (NHC)", "Storms, secondary (JTWC)"] }

        QQC2.CheckBox { visible: sec8.open; id: storms; Kirigami.FormData.label: "Show:"; text: "Tropical storms with forecast track" }
        Amount {
            visible: sec8.open
            Kirigami.FormData.label: "Storm layer opacity:"
            enabled: storms.checked
            from: 10; to: 100
            value: form.cfg_StormLayerOpacity
            onValueChanged: form.cfg_StormLayerOpacity = value
        }
        Note { visible: sec8.open; text: "GDACS worldwide first (it is often slow: 20 s and a retry are allowed); when it does not answer, the US National Hurricane Center's list, forecast track and cone take over for the Atlantic and the eastern and central Pacific. A storm keeps its identity across the two." }
        RowLayout {
            visible: sec8.open
            Kirigami.FormData.label: "Storm marker:"
            enabled: storms.checked
            QQC2.ComboBox { id: stormMarkerStyle; model: ["Drawn symbol, coloured by intensity", "Icon set with category number"] }
            Px { id: stormIconSize; enabled: stormMarkerStyle.currentIndex === 1; from: 10; to: 64 }
        }
        RowLayout {
            visible: sec8.open
            Kirigami.FormData.label: "Storm icon halo:"
            enabled: storms.checked && stormMarkerStyle.currentIndex === 1
            QQC2.ComboBox { id: stormIconTheme; model: ["Dark (for satellite maps)", "Light (for pale maps)"] }
        }
        Note { visible: sec8.open; text: "Icon set: depression D, tropical storm S, hurricane 1-5, dashed P once a storm has left the feed; mirrored south of the equator, colour by category. The colour below still drives track, cone and label." }
        KQuickControls.ColorButton { visible: sec8.open; id: stormColor; Kirigami.FormData.label: "Storm colour:"; enabled: storms.checked; showAlphaChannel: false; dialogTitle: "Storm colour" }
        QQC2.CheckBox { visible: sec8.open; id: stormIntensityColors; enabled: storms.checked; text: "Colour by intensity" }
        Note { visible: sec8.open; text: "The scale used on storm-tracking sites: not tropical (disturbance, remnant low) purple, depression blue, tropical storm green, then category 1 to 5 yellow, orange, red, pink, magenta. Untick for the one colour above." }
        QQC2.CheckBox { visible: sec8.open; id: stormTrackColors; enabled: storms.checked && stormIntensityColors.checked; text: "Track and forecast in the intensity at each fix" }
        Note { visible: sec8.open; text: "Each piece of the track takes the colour of the wind the storm had reached there, so its history reads at a glance: a fix every 6 hours from NHC's best track in the Atlantic and eastern Pacific, and elsewhere the positions this wallpaper has itself seen since it first met the storm. Forecast points use the forecast wind." }
        QQC2.CheckBox { visible: sec8.open; id: stormOriginMark; enabled: storms.checked; text: "Mark where the storm was first fixed, with how long ago" }
        QQC2.CheckBox { visible: sec8.open; id: stormCone; enabled: storms.checked; text: "Forecast cone (the centre's where it publishes one; built from JTWC's mean track errors where it does not)" }
        RowLayout {
            visible: sec8.open
            Kirigami.FormData.label: "Storm labels:"
            enabled: storms.checked
            QQC2.ComboBox { id: stormLabels; model: ["None", "Name", "Name, type and wind", "Name and wind"] }
            QQC2.ComboBox { id: stormUnits; enabled: stormLabels.currentIndex >= 2; model: ["km/h", "mph", "knots"] }
            Px { id: stormLabelSize; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec8.open
            Kirigami.FormData.label: "Storm label facilities:"
            enabled: storms.checked && stormLabels.currentIndex >= 2
            QQC2.CheckBox { id: stormLabelFacilities; text: "What it threatens (\"5 refineries in the cone · crossed 3 facilities\")" }
            QQC2.CheckBox { id: stormLabelTwoLines; enabled: stormLabelFacilities.checked; text: "On a line of its own" }
        }
        Note { visible: sec8.open; text: "The icon already says the storm's class, so \"Name and wind\" leaves \"Hurricane cat 3\" out of the text. The facilities need the Oil and gas infrastructure data; the Events widget lists them under the storm whatever is chosen here." }
        RowLayout {
            visible: sec8.open
            Kirigami.FormData.label: "Storm label text:"
            enabled: storms.checked && stormLabels.currentIndex > 0
            QQC2.CheckBox { id: stormPlate; text: "Plate" }
            QQC2.CheckBox { id: stormFollows; text: "Text follows the storm colour" }
            KQuickControls.ColorButton { id: stormTextColor; enabled: !stormFollows.checked; showAlphaChannel: false; dialogTitle: "Storm label colour" }
        }
        LabelStyle { visible: sec8.open; id: stormStyle; label: "Storm label style:"; enabled: storms.checked && stormLabels.currentIndex > 0; plated: stormPlate.checked }
        QQC2.ComboBox {
            visible: sec8.open
            id: stormPulseMode
            Kirigami.FormData.label: "Storm pulse:"
            enabled: storms.checked
            model: form.pulseChoices
        }
        Note { visible: sec8.open; text: "Newly reported = GDACS started tracking it less than the 'Newly reported' hours ago; significant = hurricane strength (category 1 and up). A storm ages from its latest advisory and greys out once GDACS stops tracking it." }

        // ============================================================== Wildfires
        SectionHeader { id: sec9; title: "Wildfires"; group: "Natural events"; sourceNames: ["Wildfires (GDACS)", "US fire incidents (NIFC)", "Canadian fires (CWFIS)", "European burnt areas (EFFIS)", "Fire hotspots (NASA FIRMS)"]; twin: fires; summary: fires.checked ? form.fireSourcesText + ((form.cfg_FireSources & 2) ? " · hotspots: " + hotspotTier.currentText.toLowerCase() : "") + " · labels: " + fireLabels.currentText.toLowerCase() : "Off" }
        Source { visible: sec9.open; names: ["Wildfires (GDACS)", "US fire incidents (NIFC)", "Canadian fires (CWFIS)", "European burnt areas (EFFIS)", "Fire hotspots (NASA FIRMS)"] }

        QQC2.CheckBox { visible: sec9.open; id: fires; Kirigami.FormData.label: "Show:"; text: "Wildfires" }
        Amount {
            visible: sec9.open
            Kirigami.FormData.label: "Wildfire layer opacity:"
            enabled: fires.checked
            from: 10; to: 100
            value: form.cfg_FireLayerOpacity
            onValueChanged: form.cfg_FireLayerOpacity = value
        }
        ColumnLayout {
            visible: sec9.open
            Kirigami.FormData.label: "Wildfire sources:"
            enabled: fires.checked
            spacing: 0
            Repeater {
                model: form.fireSourceList
                QQC2.CheckBox {
                    required property var modelData
                    text: modelData[1]
                    checked: (form.cfg_FireSources & modelData[0]) !== 0
                    onToggled: form.cfg_FireSources = checked ? (form.cfg_FireSources | modelData[0]) : (form.cfg_FireSources & ~modelData[0])
                }
            }
        }
        Note { visible: sec9.open; text: "The incident sources are the fires the agencies are fighting, by name, with the size, containment or stage of control, personnel, and the perimeter where it is mapped: NIFC's interagency perimeters (every open US wildfire, no prescribed burns), CWFIS's active-fires list with its satellite perimeter estimates (Canada; a fire with no status report for two weeks is dropped, since some agencies leave summer fires 'out of control' for months), EFFIS's burnt areas of the last three weeks (Europe, the Middle East, North Africa). Looked at every 30 minutes. GDACS adds the rest of the world's rated events; the FIRMS hotspots are the raw satellite detections, off by default because a burning season covers the map with them." }
        RowLayout {
            visible: sec9.open
            Kirigami.FormData.label: "Incident filter:"
            enabled: fires.checked && (form.cfg_FireSources & 28) !== 0
            QQC2.ComboBox { id: fireIncidentMin; model: ["Any size", "100 ha (250 ac) and up", "1 000 ha and up", "10 000 ha and up"] }
            QQC2.CheckBox { id: fireIncidentActive; text: "Only fires still burning (out of control, being held, under 90 % contained, or mapped this week)" }
        }
        RowLayout {
            visible: sec9.open
            Kirigami.FormData.label: "Incident mark:"
            enabled: fires.checked && (form.cfg_FireSources & 28) !== 0
            QQC2.ComboBox { id: fireIncidentMark; model: ["Flame and perimeter", "Perimeter only (a dot where none is mapped)", "Flame only"] }
            QQC2.CheckBox { id: firePerimeter; visible: fireIncidentMark.currentIndex === 0; text: "Shade the perimeter" }
            Pct { id: firePerimeterOpacity; enabled: firePerimeter.checked || fireIncidentMark.currentIndex === 1; visible: fireIncidentMark.currentIndex !== 2; from: 5; to: 80; label: "Fill opacity" }
        }
        Note { visible: sec9.open; text: "A flame sits at the perimeter's centre and covers part of it; 'Perimeter only' leaves the shape to speak for itself, with a small dot for fires the agency has not mapped yet (most Canadian ones)." }
        QQC2.ComboBox {
            visible: sec9.open
            id: fireFocus
            Kirigami.FormData.label: "Wildfire focus:"
            enabled: fires.checked
            model: ["Everything the filters below allow", "Near people: a city of 100 000 within 50 km, or an orange / red event", "Orange and red events only (no satellite hotspots)"]
        }
        Note { visible: sec9.open; text: "Most of what the satellites see burning is the savanna, harvest and forestry fires of the season - the world looks on fire every day. 'Near people' keeps the fires that can mean evacuations: GDACS rates orange and red on the people exposed, and a hotspot cluster within 50 km of a city of 100 000 is the other case. The Events widget follows the same choice." }
        RowLayout {
            visible: sec9.open
            Kirigami.FormData.label: "GDACS fire filter:"
            enabled: fires.checked && (form.cfg_FireSources & 1) !== 0
            QQC2.ComboBox { id: fireMinLevel; model: ["All levels", "Orange and red", "Red only"] }
            QQC2.ComboBox { id: fireMinArea; model: ["Any size", "1 000 ha and up", "10 000 ha and up", "50 000 ha and up"] }
        }
        QQC2.ComboBox {
            visible: sec9.open
            id: hotspotTier
            Kirigami.FormData.label: "Hotspot filter:"
            enabled: fires.checked && (form.cfg_FireSources & 2) !== 0
            model: ["Needs attention only", "Notable and up", "Everything"]
        }
        Note { visible: sec9.open; text: "Needs attention: on a GDACS orange or red event, near a city, burning for days in isolation, very large, or a usually quiet cell flaring up. Notable: 25+ detections or 1 GW, a smaller fire near a town, on a GDACS event; drawn as dots, labelled only with 'All' labels. Regional burning seasons (a carpet of burning cells, the savanna and harvest fires) stay notable at most, so the map is not covered in them." }
        QQC2.ComboBox {
            visible: sec9.open
            id: hotspotMinCount
            Kirigami.FormData.label: "Hotspot cells:"
            enabled: fires.checked && (form.cfg_FireSources & 2) !== 0 && hotspotTier.currentIndex === 2
            model: ["3+ detections per cell", "10+ detections per cell", "25+ detections per cell", "50+ detections per cell"]
        }
        Note { visible: sec9.open; text: "GDACS rates most fires green (it scores humanitarian impact, not size), so a GDACS flame's size follows the burned area and only its colour the level. A hotspot cell that needs attention gets the flame, a label saying why, and the pulse." }
        KQuickControls.ColorButton { visible: sec9.open; id: fireColor; Kirigami.FormData.label: "Wildfire colour:"; enabled: fires.checked; showAlphaChannel: false; dialogTitle: "Wildfire colour" }
        QQC2.CheckBox { visible: sec9.open; id: fireAlertColors; enabled: fires.checked; text: "GDACS colours by alert level (green, orange, red)" }
        RowLayout {
            visible: sec9.open
            Kirigami.FormData.label: "Wildfire labels:"
            enabled: fires.checked
            QQC2.ComboBox { id: fireLabels; model: ["None", "Orange and red only", "All"] }
            Px { id: fireLabelSize; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec9.open
            Kirigami.FormData.label: "Wildfire label text:"
            enabled: fires.checked && fireLabels.currentIndex > 0
            QQC2.CheckBox { id: firePlate; text: "Plate" }
            QQC2.CheckBox { id: fireFollows; text: "Text follows the fire colour" }
            KQuickControls.ColorButton { id: fireTextColor; enabled: !fireFollows.checked; showAlphaChannel: false; dialogTitle: "Wildfire label colour" }
        }
        LabelStyle { visible: sec9.open; id: fireStyle; label: "Wildfire label style:"; enabled: fires.checked && fireLabels.currentIndex > 0; plated: firePlate.checked }
        QQC2.ComboBox {
            visible: sec9.open
            id: firePulseMode
            Kirigami.FormData.label: "Wildfire pulse:"
            enabled: fires.checked
            model: form.pulseChoices
        }
        Note { visible: sec9.open; text: "Labels: an incident reads name, size, containment or stage, personnel and age ('Bouquet · 1.0k ac · 35 % contained · 600 personnel · 3 d'); a GDACS event reads place, burned area and how long it has been listed. Newly reported = listed, or level changed, less than the 'Newly reported' hours ago; significant = a GDACS orange or red, or an incident of 1 000 ha still burning; with 'Orange and red only' those are the only incidents labelled. A fire ages out once its source drops it." }

        // ============================================================== Floods
        SectionHeader { id: sec9f; title: "Floods"; group: "Natural events"; sourceNames: ["Floods (GDACS)", "US flood alerts (NWS)", "European warnings (MeteoAlarm)", "Canadian alerts (Environment Canada)", "England flood warnings (Environment Agency)"]; twin: floods; summary: floods.checked ? floodMinLevel.currentText + (floodNws.checked ? " · US alerts" : "") + (form.cfg_FloodWarnSources ? " · " + [[2, "Europe"], [4, "Canada"], [8, "England"]].filter(function (p) { return form.cfg_FloodWarnSources & p[0]; }).map(function (p) { return p[1]; }).join(", ") : "") + (floodArea.checked ? " · affected area " + floodAreaOpacity.value + " %" : "") + " · labels: " + floodLabels.currentText.toLowerCase() : "Off" }
        Source { visible: sec9f.open; names: ["Floods (GDACS)", "US flood alerts (NWS)", "European warnings (MeteoAlarm)", "Canadian alerts (Environment Canada)", "England flood warnings (Environment Agency)"] }

        QQC2.CheckBox { visible: sec9f.open; id: floods; Kirigami.FormData.label: "Show:"; text: "Floods" }
        Amount {
            visible: sec9f.open
            Kirigami.FormData.label: "Flood layer opacity:"
            enabled: floods.checked
            from: 10; to: 100
            value: form.cfg_FloodLayerOpacity
            onValueChanged: form.cfg_FloodLayerOpacity = value
        }
        QQC2.ComboBox {
            visible: sec9f.open
            id: floodMinLevel
            Kirigami.FormData.label: "Flood filter:"
            enabled: floods.checked
            model: ["All levels (GDACS green, NWS watches and advisories too)", "Orange and red (GDACS) · warnings (NWS)", "Red only (GDACS) · flash flood warnings (NWS)"]
        }
        QQC2.CheckBox { visible: sec9f.open; id: floodNws; Kirigami.FormData.label: "US alerts:"; enabled: floods.checked; text: "National Weather Service flood alerts (api.weather.gov, every 10 minutes)" }
        RowLayout {
            visible: sec9f.open
            Kirigami.FormData.label: "Official warnings:"
            enabled: floods.checked
            Repeater {
                model: [[2, "MeteoAlarm (Europe, 38 services)"], [4, "Environment Canada"], [8, "Environment Agency (England)"]]
                QQC2.CheckBox {
                    required property var modelData
                    text: modelData[1]
                    checked: (form.cfg_FloodWarnSources & modelData[0]) !== 0
                    onToggled: form.cfg_FloodWarnSources = checked ? (form.cfg_FloodWarnSources | modelData[0]) : (form.cfg_FloodWarnSources & ~modelData[0])
                }
            }
        }
        QQC2.CheckBox { visible: sec9f.open; id: floodNwsEach; enabled: floods.checked && (floodNws.checked || form.cfg_FloodWarnSources > 0); text: "Every alert on its own (unticked: one mark per forecast office or country and alert type, e.g. 'Flood Warning · 9 counties · Greenville-Spartanburg')" }
        Note { visible: sec9f.open; text: "The NWS alerts arrive minutes after issue: flash flood warnings (red), flood warnings (orange), watches and advisories (green), with the counties covered, when the alert ends, and the warning's own polygon or its forecast zones as the area (zones are fetched once and kept). A wet week has an office issue a flood warning per river gauge, so by default an office's warnings of one type are one mark, one label and one area; 'Red only' under labels keeps the text to flash floods. US only; untick outside the US to save the request. The official warnings elsewhere join the same list: MeteoAlarm's flood, rain and coastal warnings for the 38 European services (yellow counts as the watch tier, orange and red as warnings; placed on the named regions, every 30 minutes), Environment Canada's rainfall and flood alerts with their polygons (every 15 minutes), and the Environment Agency's flood alerts and warnings for England with each flood area's outline (every 15 minutes)." }
        Note { visible: sec9f.open; text: "GDACS lists a flood per river basin or region and rates it on the people exposed: green is a basin's seasonal high water (there are always a dozen), orange and red are the ones with people evacuated, displaced or killed. Updated a few times a day; looked at hourly. The Events widget follows this filter." }
        RowLayout {
            visible: sec9f.open
            Kirigami.FormData.label: "Affected area:"
            enabled: floods.checked
            QQC2.CheckBox { id: floodArea; text: "Shade the affected area" }
            Pct { id: floodAreaOpacity; enabled: floodArea.checked; from: 5; to: 80; label: "Fill opacity" }
        }
        Note { visible: sec9f.open; text: "The area GDACS reports as affected (the flooded districts), as a faint fill in the flood's colour under the mark. Fetched with the event's figures for the orange and red floods, a few KB each; with 'All levels' for the green ones too." }
        KQuickControls.ColorButton { visible: sec9f.open; id: floodColor; Kirigami.FormData.label: "Flood colour:"; enabled: floods.checked; showAlphaChannel: false; dialogTitle: "Flood colour" }
        QQC2.CheckBox { visible: sec9f.open; id: floodAlertColors; enabled: floods.checked; text: "Orange and red floods in GDACS's alert colours (green ones keep the flood colour)" }
        RowLayout {
            visible: sec9f.open
            Kirigami.FormData.label: "Flood labels:"
            enabled: floods.checked
            QQC2.ComboBox { id: floodLabels; model: ["None", "Orange and red only", "All", "Red only (flash flood warnings)"] }
            Px { id: floodLabelSize; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec9f.open
            Kirigami.FormData.label: "Flood label text:"
            enabled: floods.checked && floodLabels.currentIndex > 0
            QQC2.CheckBox { id: floodPlate; text: "Plate" }
            QQC2.CheckBox { id: floodFollows; text: "Text follows the flood colour" }
            KQuickControls.ColorButton { id: floodTextColor; enabled: !floodFollows.checked; showAlphaChannel: false; dialogTitle: "Flood label colour" }
        }
        LabelStyle { visible: sec9f.open; id: floodStyle; label: "Flood label style:"; enabled: floods.checked && floodLabels.currentIndex > 0; plated: floodPlate.checked }
        QQC2.ComboBox {
            visible: sec9f.open
            id: floodPulseMode
            Kirigami.FormData.label: "Flood pulse:"
            enabled: floods.checked
            model: form.pulseChoices
        }
        Note { visible: sec9f.open; text: "Label: place, what happened to people (dead, evacuated, displaced - GDACS's Sendai figures, where it has them), how long the flood has run. Newly reported = listed, or level changed, less than the 'Newly reported' hours ago; significant = orange or red. A flood ages out once GDACS drops it." }

        // ================================================================= Tsunami
        SectionHeader { id: sec9t; title: "Tsunami bulletins"; group: "Natural events"; sourceNames: ["Tsunami bulletins (PTWC / NTWC)"]; twin: tsunami; summary: tsunami.checked ? (tsunamiShowInfo.checked ? "threats and evaluations" : "threats only") + (tsunamiCoast.checked ? " · threatened coast" : "") + " · labels: " + tsunamiLabels.currentText.toLowerCase() : "Off" }
        Source { visible: sec9t.open; names: ["Tsunami bulletins (PTWC / NTWC)"] }
        QQC2.CheckBox { visible: sec9t.open; id: tsunami; Kirigami.FormData.label: "Show:"; text: "Tsunami bulletins" }
        Amount {
            visible: sec9t.open
            Kirigami.FormData.label: "Tsunami layer opacity:"
            enabled: tsunami.checked
            from: 10; to: 100
            value: form.cfg_TsunamiLayerOpacity
            onValueChanged: form.cfg_TsunamiLayerOpacity = value
        }
        Note { visible: sec9t.open; text: "The Pacific Tsunami Warning Center (the Pacific, the Caribbean, and threat messages for the Indian Ocean and the rest of the world) and the National Tsunami Warning Center (US and Canadian coasts) evaluate every large undersea earthquake within minutes. Each evaluation is a ringed mark at the epicentre: blue-grey when no threat was found, yellow for a watch, orange for an advisory, red for a warning or threat message, with rings running out while the threat stands. A threat stood down by a later message fades over three hours. Looked at every 5 minutes." }
        RowLayout {
            visible: sec9t.open
            Kirigami.FormData.label: "No-threat evaluations:"
            enabled: tsunami.checked
            QQC2.CheckBox { id: tsunamiShowInfo; text: "Show, for" }
            QQC2.SpinBox { id: tsunamiInfoHours; enabled: tsunamiShowInfo.checked; from: 1; to: 48; textFromValue: function (v) { return v + " h" }; valueFromText: function (t) { return parseInt(t) || 6 } }
        }
        QQC2.CheckBox { visible: sec9t.open; id: tsunamiCoast; Kirigami.FormData.label: "Threatened coast:"; enabled: tsunami.checked; text: "Draw the coast under threat between the centre's breakpoints" }
        RowLayout {
            visible: sec9t.open
            Kirigami.FormData.label: "Tsunami colours:"
            enabled: tsunami.checked
            QQC2.Label { text: "Warning"; opacity: 0.8 }
            KQuickControls.ColorButton { id: tsunamiColor; showAlphaChannel: false; dialogTitle: "Tsunami warning / threat colour" }
            QQC2.Label { text: "Advisory"; opacity: 0.8 }
            KQuickControls.ColorButton { id: tsunamiAdvisoryColor; showAlphaChannel: false; dialogTitle: "Tsunami advisory colour" }
            QQC2.Label { text: "Watch"; opacity: 0.8 }
            KQuickControls.ColorButton { id: tsunamiWatchColor; showAlphaChannel: false; dialogTitle: "Tsunami watch colour" }
            QQC2.Label { text: "No threat"; opacity: 0.8 }
            KQuickControls.ColorButton { id: tsunamiInfoColor; showAlphaChannel: false; dialogTitle: "No-threat evaluation colour" }
        }
        RowLayout {
            visible: sec9t.open
            Kirigami.FormData.label: "Tsunami labels:"
            enabled: tsunami.checked
            QQC2.ComboBox { id: tsunamiLabels; model: ["None", "Threats only", "All"] }
            Px { id: tsunamiLabelSize; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec9t.open
            Kirigami.FormData.label: "Tsunami label text:"
            enabled: tsunami.checked && tsunamiLabels.currentIndex > 0
            QQC2.CheckBox { id: tsunamiPlate; text: "Plate" }
            QQC2.CheckBox { id: tsunamiFollows; text: "Text follows the level colour" }
            KQuickControls.ColorButton { id: tsunamiTextColor; enabled: !tsunamiFollows.checked; showAlphaChannel: false; dialogTitle: "Tsunami label colour" }
        }
        LabelStyle { visible: sec9t.open; id: tsunamiStyle; label: "Tsunami label style:"; enabled: tsunami.checked && tsunamiLabels.currentIndex > 0; plated: tsunamiPlate.checked }
        QQC2.CheckBox { visible: sec9t.open; id: tsunamiPulse; Kirigami.FormData.label: "Tsunami pulse:"; enabled: tsunami.checked; text: "Rings run out from the epicentre while a threat stands" }
        Note { visible: sec9t.open; text: "Label: the level, the earthquake (magnitude and place as the centre names it), how long ago the bulletin was issued. tsunami.gov publishes only each centre's latest message, so the helper remembers every bulletin by event for 36 hours and stands a threat down when a later message does. Public domain (US government)." }

        // #################################################################### Space
        // #################################################################### Civil alerts

        // ============================================================== Air raid alerts
        SectionHeader { id: sec9a; title: "Air raid alerts (Ukraine)"; group: "Civil, space and network"; sourceNames: ["Air raid alerts (alerts.in.ua)"]; twin: airAlerts; summary: airAlerts.checked ? (alertToken.text !== "" ? "alerts.in.ua, with token" : "public mirror, oblast level") + " · fill " + alertOpacity.value + " %" + (alertOutline.checked ? " · outlines" : "") + " · labels: " + alertLabels.currentText.toLowerCase() : "Off" }
        Source { visible: sec9a.open; names: ["Air raid alerts (alerts.in.ua)"] }

        QQC2.CheckBox { visible: sec9a.open; id: airAlerts; Kirigami.FormData.label: "Show:"; text: "Ukraine's air raid alerts, by oblast" }
        Amount {
            visible: sec9a.open
            Kirigami.FormData.label: "Alert layer opacity:"
            enabled: airAlerts.checked
            from: 10; to: 100
            value: form.cfg_AirAlertLayerOpacity
            onValueChanged: form.cfg_AirAlertLayerOpacity = value
        }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "alerts.in.ua token:"
            enabled: airAlerts.checked
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            QQC2.TextField { id: alertToken; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "optional: a personal token from alerts.in.ua/api-request" }
        }
        Note { visible: sec9a.open; text: "Without a token the layer reads a public mirror of the same data (ubilling.net.ua): which oblasts are under air raid alert, once a minute. With a personal token (free for personal use, requested at alerts.in.ua/api-request; the limit is 8-10 requests a minute and this makes one) it reads alerts.in.ua itself: the alert type too (air raid, artillery shelling, street fighting, chemical, nuclear), when it started, and alerts on part of an oblast - a raion, hromada or city - drawn at the lower opacity and labelled with the place. The mirror does not say when an alert began, so a duration is shown only for alerts this wallpaper saw begin; with a token every alert carries its start time. Not for critical use: the data can lag, as the service itself says. The oblast outlines ship with the wallpaper (Natural Earth)." }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "Drawn as:"
            enabled: airAlerts.checked
            QQC2.ComboBox { id: alertDrawStyle; Layout.preferredWidth: Kirigami.Units.gridUnit * 16; model: ["Edge lights: the oblast's border glows", "Fills: the oblast is shaded"] }
            QQC2.Button { text: "Default colours"; icon.name: "edit-undo"; onClicked: { alertColor.color = "#e03a3a"; alertNewColor.color = "#ff3b30"; alertLongColor.color = "#d68c28"; alertClearColor.color = "#8fb6d6"; } }
        }
        Note { visible: sec9a.open; text: alertDrawStyle.currentIndex === 0 ? "The border of an oblast under alert lights up and the imagery inside it - the city lights, the terrain - stays as it is, so the night map keeps its look; a new alert breathes brightest, one that has settled in holds a steady edge, part of an oblast is dashed. Weaker at world zoom, where a border is a pixel wide: the glow carries it." : "The oblast is shaded in the alert colour, at the lower opacity when only part of it is under alert. Reads at any zoom; the imagery inside is tinted." }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: alertDrawStyle.currentIndex === 0 ? "Alert edge:" : "Alert fill:"
            enabled: airAlerts.checked
            KQuickControls.ColorButton { id: alertColor; showAlphaChannel: false; dialogTitle: "Air raid alert colour" }
            Pct { id: alertOpacity; from: 10; to: 80; label: "Whole oblast under alert" }
            Pct { id: alertPartialOpacity; from: 0; to: 60; label: "Part of the oblast under alert (with a token)" }
            QQC2.CheckBox { id: alertPulse; text: "Breathe" }
        }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "New alerts:"
            enabled: airAlerts.checked
            KQuickControls.ColorButton { id: alertNewColor; showAlphaChannel: false; dialogTitle: "New alert colour" }
            QQC2.SpinBox { id: alertNewMinutes; from: 0; to: 120; stepSize: 5; textFromValue: function (v) { return v + " min" }; valueFromText: function (t) { return parseInt(t) || 0 } }
            QQC2.Label { text: "in this colour, breathing harder (0: off)"; opacity: 0.7 }
        }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "All clear:"
            enabled: airAlerts.checked
            QQC2.CheckBox { id: alertShowClear; text: "Keep an ended alert as a fading outline for 30 minutes" }
            KQuickControls.ColorButton { id: alertClearColor; enabled: alertShowClear.checked; showAlphaChannel: false; dialogTitle: "All-clear colour" }
        }
        Note { visible: sec9a.open; text: "Time-graded: an alert's first minutes in the new-alert colour, breathing hardest, then the alert colour, then (below) the long-running colour once it has run for hours; the all-clear leaves a cool outline that fades, labelled 'Kyiv · all clear · 12 min'. Only alerts this wallpaper saw begin count as new (or any alert, with a token)." }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "Long-running alerts:"
            enabled: airAlerts.checked
            QQC2.ComboBox { id: alertLongStyle; model: ["Drawn like any other", "In their own colour, without the breath", "Outline only", "Hidden until something new happens there"] }
            Hours { id: alertLongHours; from: 0; to: 168; enabled: alertLongStyle.currentIndex > 0 }
            QQC2.Label { text: "and over"; opacity: 0.7 }
            KQuickControls.ColorButton { id: alertLongColor; enabled: alertLongStyle.currentIndex === 1 || alertLongStyle.currentIndex === 2; showAlphaChannel: false; dialogTitle: "Long-running alert colour" }
        }
        Note { visible: sec9a.open; text: "An alert clears from the map the minute the all-clear is given; nothing is kept on. But the frontline oblasts (Luhansk, Donetsk, Kharkiv, Zaporizhzhia, Kherson, Crimea) have been under alert for months on end, so past this many hours an alert is drawn lighter, as an outline, or not at all - until something new happens there. The oblast-level alert itself is never re-issued while it is on: what counts as new is a raion or city inside it getting its own alert, or a type added (shelling on top of the air raid), and only alerts.in.ua reports those - with a token. Without one, the mirror sees the oblast as one unchanging alert, so a hidden frontline oblast stays hidden until it clears. 0 hours: never. An alert already on at the first look counts from that look." }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "Oblast outlines:"
            enabled: airAlerts.checked
            QQC2.CheckBox { id: alertOutline; text: "Outline every oblast, alert or not" }
            Pct { id: alertOutlineOpacity; enabled: alertOutline.checked; from: 5; to: 100; label: "Outline opacity" }
        }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "Alert labels:"
            enabled: airAlerts.checked
            QQC2.ComboBox { id: alertLabels; model: ["None", "Oblasts under alert", "Every oblast (name only when quiet)"] }
            Px { id: alertLabelSize; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec9a.open
            Kirigami.FormData.label: "Alert label text:"
            enabled: airAlerts.checked && alertLabels.currentIndex > 0
            QQC2.CheckBox { id: alertPlate; text: "Plate" }
            QQC2.CheckBox { id: alertFollows; text: "Text follows the alert colour" }
            KQuickControls.ColorButton { id: alertTextColor; enabled: !alertFollows.checked; showAlphaChannel: false; dialogTitle: "Alert label colour" }
        }
        LabelStyle { visible: sec9a.open; id: alertStyle; label: "Alert label style:"; enabled: airAlerts.checked && alertLabels.currentIndex > 0; plated: alertPlate.checked }
        Note { visible: sec9a.open; text: "Label: oblast, the alert type, how long it has been on ('Kharkiv · air raid · 23 min'); a partial alert says 'part: Kupiansk'. The Events widget lists the oblasts under alert; an alert that is not an air raid (shelling, fighting) counts as severe for the sound." }


        // ============================================================= Satellites
        SectionHeader { id: sec10; title: "Satellites"; group: "Civil, space and network"; sourceNames: ["Satellite elements (CelesTrak)"]; twin: sats; summary: sats.checked ? [satIss.checked ? "ISS" : "", satHubble.checked ? "Hubble" : "", satTiangong.checked ? "Tiangong" : ""].filter(function (t) { return t !== "" }).join(", ") + " · " + satMarkerStyle.currentText.toLowerCase() + " · track " + satTrackLength.currentText.toLowerCase() : "Off" }
        Source { visible: sec10.open; names: ["Satellite elements (CelesTrak)"] }
        QQC2.CheckBox { visible: sec10.open; id: sats; Kirigami.FormData.label: "Show:"; text: "Satellites and their ground track" }
        Amount {
            visible: sec10.open
            Kirigami.FormData.label: "Satellite layer opacity:"
            enabled: sats.checked
            from: 10; to: 100
            value: form.cfg_SatLayerOpacity
            onValueChanged: form.cfg_SatLayerOpacity = value
        }
        RowLayout {
            visible: sec10.open
            enabled: sats.checked
            QQC2.CheckBox { id: satIss; text: "ISS" }
            QQC2.CheckBox { id: satHubble; text: "Hubble" }
            QQC2.CheckBox { id: satTiangong; text: "Tiangong" }
        }
        Note { visible: sec10.open; text: "Orbital elements from CelesTrak, refreshed every six hours, propagated by the helper (Kepler + J2: within a few km of the full SGP4 model for these low orbits). The marker moves along a precomputed track once a second; the dashed line is the ground track from 15 minutes ago to 100 minutes ahead." }
        QQC2.ComboBox {
            visible: sec10.open
            id: satPasses
            Kirigami.FormData.label: "Passes over you:"
            enabled: sats.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            model: ["Not listed", "The ones you can see, in the widget", "Every pass, seen or not"]
        }
        Note { visible: sec10.open; text: "Experimental. When the ISS will cross the sky over your home place (Essentials), from the same orbital elements: rise, highest point and set with compass directions, in the widget's Satellites group an hour ahead and in the station's bubble. A pass can be seen only when your sky is dark and the station is still in sunlight - the first hours after dusk and before dawn - so the daytime passes are left out unless you ask for every pass. Cloud over your home from the live cloud image is shown beside it as a hint; it never hides a pass." + (homeLat.text === "" || homeLon.text === "" ? " No home place is set yet." : "") }
        RowLayout {
            visible: sec10.open
            Kirigami.FormData.label: "Satellite marker:"
            enabled: sats.checked
            QQC2.ComboBox { id: satMarkerStyle; model: ["Symbol in the colour below", "Picture of the spacecraft"] }
            Px { id: satPictureSize; enabled: satMarkerStyle.currentIndex === 1; from: 8; to: 96 }
        }
        Note { visible: sec10.open; text: "Pictures: the ISS, Hubble and Tiangong artwork from the images folder, sized in px on a 1920-wide screen (scaled up on bigger ones). The colour still applies to the track, the ring and the label." }
        KQuickControls.ColorButton { visible: sec10.open; id: satColor; Kirigami.FormData.label: "Satellite colour:"; enabled: sats.checked; showAlphaChannel: false; dialogTitle: "Satellite colour" }
        RowLayout {
            visible: sec10.open
            Kirigami.FormData.label: "Satellite track:"
            enabled: sats.checked
            QQC2.CheckBox { id: satTrack; text: "Ground track" }
            QQC2.ComboBox { id: satTrackLength; enabled: satTrack.checked; model: ["Next 30 minutes", "One orbit ahead", "Two orbits ahead"] }
        }
        RowLayout {
            visible: sec10.open
            Kirigami.FormData.label: "Satellite labels:"
            enabled: sats.checked
            QQC2.ComboBox { id: satLabels; model: ["None", "Name", "Name and altitude"] }
            Px { id: satLabelSize; from: 4; to: 24 }
        }
        RowLayout {
            visible: sec10.open
            Kirigami.FormData.label: "Satellite label text:"
            enabled: sats.checked && satLabels.currentIndex > 0
            QQC2.CheckBox { id: satPlate; text: "Plate" }
            QQC2.CheckBox { id: satFollows; text: "Text follows the satellite colour" }
            KQuickControls.ColorButton { id: satTextColor; enabled: !satFollows.checked; showAlphaChannel: false; dialogTitle: "Satellite label colour" }
        }
        LabelStyle { visible: sec10.open; id: satStyle; label: "Satellite label style:"; enabled: sats.checked && satLabels.currentIndex > 0; plated: satPlate.checked }

        // =============================================================== Launches
        SectionHeader { id: sec11; title: "Launches"; group: "Civil, space and network"; sourceNames: ["Launches (The Space Devs)"]; twin: launches; summary: launches.checked ? launchWindow.currentText + " · " + launchMarkerStyle.currentText.toLowerCase() + " · labels: " + launchLabels.currentText.toLowerCase() : "Off" }
        Source { visible: sec11.open; names: ["Launches (The Space Devs)"] }
        QQC2.CheckBox { visible: sec11.open; id: launches; Kirigami.FormData.label: "Show:"; text: "Upcoming rocket launches" }
        Amount {
            visible: sec11.open
            Kirigami.FormData.label: "Launch layer opacity:"
            enabled: launches.checked
            from: 10; to: 100
            value: form.cfg_LaunchLayerOpacity
            onValueChanged: form.cfg_LaunchLayerOpacity = value
        }
        QQC2.ComboBox {
            visible: sec11.open
            id: launchWindow
            Kirigami.FormData.label: "Launch window:"
            enabled: launches.checked
            model: ["24 hours", "48 hours", "72 hours", "A week"]
        }
        Note { visible: sec11.open; text: "Launch Library 2 (The Space Devs), fetched hourly: a rocket on the pad with a countdown, one per pad (the earliest). Flight paths are not published as data, so none are drawn. A launch pulses in its last hour and stays half an hour after lift-off." }
        RowLayout {
            visible: sec11.open
            Kirigami.FormData.label: "Launch marker:"
            enabled: launches.checked
            QQC2.ComboBox { id: launchMarkerStyle; model: ["Drawn rocket in the colour below", "Picture: rocket on the pad, lifting off after T-0"] }
            Px { id: launchPictureSize; enabled: launchMarkerStyle.currentIndex === 1; from: 8; to: 96 }
        }
        Note { visible: sec11.open; text: "Picture height in px on a 1920-wide screen (scaled up on bigger ones)." }
        KQuickControls.ColorButton { visible: sec11.open; id: launchColor; Kirigami.FormData.label: "Launch colour:"; enabled: launches.checked; showAlphaChannel: false; dialogTitle: "Launch marker colour" }
        RowLayout {
            visible: sec11.open
            Kirigami.FormData.label: "Launch labels:"
            enabled: launches.checked
            QQC2.ComboBox { id: launchLabels; model: ["None", "Countdown", "Rocket, mission and countdown"] }
            Px { id: launchLabelSize; from: 4; to: 24 }
        }
        QQC2.CheckBox { visible: sec11.open; id: launchLabelTwoLines; Kirigami.FormData.label: "Launch label mission:"; enabled: launches.checked && launchLabels.currentIndex === 2; text: "On a line of its own, under the rocket and countdown" }
        RowLayout {
            visible: sec11.open
            Kirigami.FormData.label: "Launch label text:"
            enabled: launches.checked && launchLabels.currentIndex > 0
            QQC2.CheckBox { id: launchPlate; text: "Plate" }
            QQC2.CheckBox { id: launchFollows; text: "Text follows the marker colour" }
            KQuickControls.ColorButton { id: launchTextColor; enabled: !launchFollows.checked; showAlphaChannel: false; dialogTitle: "Launch label colour" }
        }
        LabelStyle { visible: sec11.open; id: launchStyle; label: "Launch label style:"; enabled: launches.checked && launchLabels.currentIndex > 0; plated: launchPlate.checked }
        QQC2.CheckBox { visible: sec11.open; id: launchPulse; Kirigami.FormData.label: "Launch pulse:"; enabled: launches.checked; text: "In the last hour before lift-off" }

        // #################################################################### Network and connectivity

        // ======================================================== Network activity
        SectionHeader { id: sec12; title: "Network activity"; group: "Civil, space and network"; sourceNames: ["Connections (ss)", "GeoIP database (DB-IP)"]; twin: network; summary: network.checked ? "Arcs from " + homeLat.text + ", " + homeLon.text + " · every " + netInterval.value + " s · nothing leaves this machine" : "Off · nothing leaves this machine" }
        Source { visible: sec12.open; names: ["Connections (ss)", "GeoIP database (DB-IP)"] }

        QQC2.CheckBox { visible: sec12.open; id: network; Kirigami.FormData.label: "Show:"; text: "Arcs to the places this computer is connected to" }
        Amount {
            visible: sec12.open
            Kirigami.FormData.label: "Network layer opacity:"
            enabled: network.checked
            from: 10; to: 100
            value: form.cfg_NetLayerOpacity
            onValueChanged: form.cfg_NetLayerOpacity = value
        }
        Note { visible: sec12.open; text: "Read locally from the kernel's connection table and an offline GeoIP file; nothing about your connections leaves this machine." }
        RowLayout {
            visible: sec12.open
            Kirigami.FormData.label: "Home:"
            QQC2.Label { text: (form.cfg_HomeCity !== "" ? form.cfg_HomeCity + " · " : "") + homeLat.text + ", " + homeLon.text; opacity: 0.8 }
            QQC2.ToolButton { text: "Change on Essentials"; icon.name: "go-jump"; onClicked: form.page = "Essentials" }
        }
        Note { visible: sec12.open; text: "The arcs start from your home place, set on the Essentials page." }
        QQC2.SpinBox {
            visible: sec12.open
            id: netInterval
            Kirigami.FormData.label: "Refresh every:"
            enabled: network.checked
            from: 3; to: 300
            textFromValue: function (v) { return v + " s" }
            valueFromText: function (t) { return parseInt(t) }
        }
        QQC2.SpinBox {
            visible: sec12.open
            id: netMaxPlaces
            Kirigami.FormData.label: "At most:"
            enabled: network.checked
            from: 1; to: 200
            textFromValue: function (v) { return v + " places" }
            valueFromText: function (t) { return parseInt(t) || 1 }
        }
        KQuickControls.ColorButton { visible: sec12.open; id: arcColor; Kirigami.FormData.label: "Arc colour:"; enabled: network.checked; showAlphaChannel: false; dialogTitle: "Arc colour" }
        QQC2.CheckBox { visible: sec12.open; id: arcGlow; enabled: network.checked; text: "Soft glow around the lines" }
        Amount {
            visible: sec12.open
            Kirigami.FormData.label: "Arc thickness:"
            enabled: network.checked
            from: 30; to: 400
            value: form.cfg_ArcWidth
            onValueChanged: form.cfg_ArcWidth = value
        }
        QQC2.ComboBox {
            visible: sec12.open
            id: arcAnimation
            Kirigami.FormData.label: "Arc animation:"
            enabled: network.checked
            model: ["Packets travel along the lines", "Lines pulse with a soft glow", "Both", "None (steady lines)"]
        }
        Amount {
            visible: sec12.open
            Kirigami.FormData.label: "Arc animation speed:"
            enabled: network.checked && arcAnimation.currentIndex !== 3
            from: 20; to: 400
            value: form.cfg_PacketSpeed
            onValueChanged: form.cfg_PacketSpeed = value
        }
        QQC2.CheckBox { visible: sec12.open; id: netLabels; Kirigami.FormData.label: "Network labels:"; enabled: network.checked; text: "Name the places" }
        QQC2.CheckBox { visible: sec12.open; id: netShowProcess; enabled: network.checked && netLabels.checked; text: "Also name the program" }
        Note { visible: sec12.open && netShowProcess.checked; text: "Untick before sharing your screen." }
        QQC2.CheckBox { visible: sec12.open; id: showLatency; enabled: network.checked && netLabels.checked; text: "Also show the round-trip time (TCP only)" }
        QQC2.CheckBox { visible: sec12.open; id: flagFastRtt; enabled: network.checked && netLabels.checked && showLatency.checked; text: "Flag round trips too fast for the distance" }
        QQC2.CheckBox { visible: sec12.open; id: proxyNote; enabled: network.checked && netLabels.checked && showLatency.checked && flagFastRtt.checked; text: "Say so under the home ring when latency is hidden" }
        Note { visible: sec12.open; text: "If most round trips are too fast (VPN, proxy), latency is hidden and, with the last box ticked, a note explains why." }
        Px { visible: sec12.open; id: labelSize; Kirigami.FormData.label: "Network label size:"; enabled: network.checked && netLabels.checked; from: 7; to: 28 }
        RowLayout {
            visible: sec12.open
            Kirigami.FormData.label: "Network label text:"
            enabled: network.checked && netLabels.checked
            QQC2.CheckBox { id: netPlate; text: "Plate" }
            QQC2.Label { text: "Text colour" }
            KQuickControls.ColorButton { id: netTextColor; showAlphaChannel: false; dialogTitle: "Network label colour" }
        }
        LabelStyle { visible: sec12.open; id: netStyle; label: "Network label style:"; enabled: network.checked && netLabels.checked; plated: netPlate.checked }
        RowLayout {
            visible: sec12.open
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
            visible: sec12.open
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

        // ================================================================== Units
        SectionHeader { id: sec13; title: "Units"; group: "Shared"; twin: null; keywords: "units distance speed wind miles kilometres knots mph acres hectares"; summary: distanceUnits.currentText + " \u00b7 " + stormUnits.currentText }
        QQC2.ComboBox {
            visible: sec13.open
            id: distanceUnits
            Kirigami.FormData.label: "Distance:"
            model: ["Kilometres (areas in hectares)", "Miles (areas in acres)", "Nautical miles"]
        }
        Note { visible: sec13.open; text: "Lengths and areas everywhere: satellite altitudes, earthquake depths, burned areas, the widget's facts." }
        MirrorCombo { visible: sec13.open; Kirigami.FormData.label: "Speed:"; twin: stormUnits }
        Note { visible: sec13.open; text: "Storm winds on the map and in the widget, and the spacecraft's orbital speed. The same choice as under Storms." }

        // ============================================================ Label styling
        SectionHeader { id: sec14; title: "Markers and labels"; group: "Shared"; twin: null; summary: "Layout: " + labelLines.currentText.toLowerCase() + " · plate " + form.cfg_PlateOpacity + " % · text " + form.cfg_TextOpacity + " %" }
        Amount {
            visible: sec14.open
            Kirigami.FormData.label: "Marker size:"
            from: 40; to: 250
            value: form.cfg_MarkerScale
            onValueChanged: form.cfg_MarkerScale = value
        }
        Note { visible: sec14.open; text: "Scales every event marker at once: quake rings, volcano triangles, storm symbols, flames, spacecraft and launch pictures. Each kind also has its own size in its section." }

        Note { visible: sec14.open; text: "Event labels (network, storms, wildfires, earthquakes, volcanoes) are drawn above every layer and never over each other; a label flips sides or moves to stay on the screen. Country names are part of the map and stay underneath. Each element chooses its own plate and text colour above; the plate colour and the opacities are shared." }
        QQC2.ComboBox {
            visible: sec14.open
            id: labelLines
            Kirigami.FormData.label: "Label layout:"
            model: ["One line", "Name above the details", "Automatic: two lines where space is tight"]
        }
        Note { visible: sec14.open; text: "Two lines put the name or place on top and what happened (magnitude, category, latency, date) underneath. Automatic keeps one line where it fits and switches a label to two lines when the wide form would run off the screen or into a neighbour." }
        KQuickControls.ColorButton { visible: sec14.open; id: plateColor; Kirigami.FormData.label: "Label plate colour:"; showAlphaChannel: false; dialogTitle: "Plate colour" }
        Amount {
            visible: sec14.open
            Kirigami.FormData.label: "Label plate opacity:"
            from: 10
            value: form.cfg_PlateOpacity
            onValueChanged: form.cfg_PlateOpacity = value
        }
        Amount {
            visible: sec14.open
            Kirigami.FormData.label: "Label text opacity:"
            from: 20
            value: form.cfg_TextOpacity
            onValueChanged: form.cfg_TextOpacity = value
        }

        // ===================================================== Ageing and pulses
        SectionHeader { id: sec15; title: "Ageing and pulses"; group: "Shared"; twin: null; summary: "Newly reported " + pulseNewHours.value + " h · aged after " + ageEnd.value + " h" }

        Note { visible: sec15.open; text: "Every event has the same life: it pulses while newly reported, sits steady while it is current, then drifts towards the aged colour and is finally removed. What counts as current differs: a quake's age is its time since it happened, a storm's since its last advisory, a volcano's since it dropped out of the weekly report." }
        Hours { visible: sec15.open; id: pulseNewHours; Kirigami.FormData.label: "Newly reported:"; from: 0; to: 168 }
        Note { visible: sec15.open; text: "For this long after an event first appears it counts as newly reported (each element chooses whether newly reported, significant, both or nothing pulses)." }
        RowLayout {
            visible: sec15.open
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
        QQC2.CheckBox { visible: sec15.open; id: ageFade; Kirigami.FormData.label: "Old events:"; text: "Fade towards a colour as they age" }
        RowLayout {
            visible: sec15.open
            Kirigami.FormData.label: "Ageing:"
            enabled: ageFade.checked
            QQC2.Label { text: "Starts after" }
            Hours { id: ageStart; from: 0; to: 240 }
            QQC2.Label { text: "done at" }
            Hours { id: ageEnd; from: 1; to: 720 }
        }
        KQuickControls.ColorButton { visible: sec15.open; id: agedColor; Kirigami.FormData.label: "Aged colour:"; enabled: ageFade.checked; showAlphaChannel: false; dialogTitle: "Colour of aged events" }
        Note { visible: sec15.open; text: "Volcanoes and storms that have left their feed are removed once fully aged. Closed network connections have their own fade under This computer." }

        // ================================================== Performance and power
        SectionHeader { id: sec16; title: "Performance and power"; group: "Shared"; sourceNames: ["Power and load"]; twin: null; summary: profile.currentText + " · " + animationFps.currentText.toLowerCase() + (guardEnabled.checked ? " · load guard " + guardPause.value + " / " + guardPlain.value + " %" : " · no load guard") + " · on battery: " + onBattery.currentText.toLowerCase() }

        QQC2.ComboBox {
            visible: sec16.open
            id: animationFps
            Kirigami.FormData.label: "Animations update:"
            model: ["60 times a second (smoothest)", "30 times a second", "20 times a second", "10 times a second (lightest)"]
        }
        QQC2.CheckBox { visible: sec16.open; id: guardEnabled; Kirigami.FormData.label: "Load guard:"; text: "Step back when the computer is busy" }
        RowLayout {
            visible: sec16.open
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
            visible: sec16.open
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
        Source { visible: sec16.open; names: ["Power and load"] }
        Note { visible: sec16.open; text: "CPU busy % is read from /proc/stat; GPU busy % from the driver where it offers one (AMD: sysfs, NVIDIA: nvidia-smi). Intel exposes no busy figure without root, so its GPU clock at the top of its range stands in for 'busy'; with no GPU reading at all the CPU alone decides. The higher of the two counts. A level is entered after two busy polls (40 s) and left after three quiet ones (a minute), so a spike does not flap the map. A game or a render pins the GPU, so it is caught either way; the corner notice says when the guard is on." }
        QQC2.CheckBox { visible: sec16.open; id: cacheStill; text: "Render the still part of the map once and reuse it" }
        Note { visible: sec16.open; text: "Untick only if the map goes blank." }
        QQC2.ComboBox {
            visible: sec16.open
            id: onBattery
            Kirigami.FormData.label: "On battery:"
            model: ["Keep everything running", "Pause animations, check connections once a minute", "Plain map only"]
        }
        Note { visible: sec16.open; text: "With no animation running, the desktop is only redrawn when data changes, which costs next to nothing. Animations are what cost GPU time: packets, pulsing lines and ripples; 20 updates a second is plenty for a wallpaper. The satellite marker moves once a second regardless (a single small item). Fewer hotspot cells (Wildfires) and fewer labels also mean less work." }

        // ================================================================= Status
        SectionHeader { id: sec17; title: "Status"; group: "Shared"; keywords: "status of the data sources download maps borders geoip log report"; twin: null; summary: statusLoader.item && statusLoader.item.checks.length > 0 ? statusLoader.item.checks.filter(function (c) { return c.state === "error" }).length + " problems, " + statusLoader.item.checks.filter(function (c) { return c.state === "warn" }).length + " notes" : "Not checked yet" }

        Loader {
            visible: sec17.open
            id: statusLoader
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 44
            source: "StatusPanel.qml"
            onLoaded: {
                item.quakeFeed = Qt.binding(function () { return ["2.5_day", "4.5_day", "significant_week"][quakeFeed.currentIndex] || "4.5_day" });
                item.oceanFrom = Qt.binding(function () { return baseImage.text });
            }
        }
        QQC2.Label {
            visible: sec17.open && statusLoader.status === Loader.Error
            text: "The status panel could not be loaded. The settings above still work."
            color: Kirigami.Theme.negativeTextColor
        }

        // =============================================================== Coverage
        SectionHeader { id: sec17c; title: "Coverage"; group: "Shared"; keywords: "what covers where how fast sources regions credits licences attribution"; twin: null; summary: coverageLoader.item && coverageLoader.item.coverage ? "What covers where, and how fast · " + (coverageLoader.item.coverage.here ? "where you are: " + (coverageLoader.item.coverage.here.country || coverageLoader.item.coverage.here.region) + " · " : "") + coverageLoader.item.coverage.sources.length + " sources, " + coverageLoader.item.coverage.hazards.length + " hazards by " + coverageLoader.item.coverage.regions.length + " regions" : "What covers where, and how fast: hazards by world region, with the source and its lead time" }
        Loader {
            visible: sec17c.open
            id: coverageLoader
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 44
            source: "CoveragePanel.qml"
            onLoaded: {
                item.homeLat = Qt.binding(function () { return homeLat.text });
                item.homeLon = Qt.binding(function () { return homeLon.text });
            }
        }
        QQC2.Label {
            visible: sec17c.open && coverageLoader.status === Loader.Error
            text: "The coverage panel could not be loaded. The settings above still work."
            color: Kirigami.Theme.negativeTextColor
        }
    }
    }
    }

    QQC2.Dialog {
        id: saveAsDialog
        title: "Save the style as"
        modal: true
        anchors.centerIn: parent
        standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel
        onAccepted: if (saveAsName.text.trim() !== "") form.saveStyle("", saveAsName.text.trim())
        ColumnLayout {
            QQC2.Label { text: "A name for this style. It saves " + form.includedBuckets.map(function (b) { return ({ base: "the map base", look: "the colours, lines and labels", layers: "the layers" })[b]; }).join(", ") + " as they are now." ; wrapMode: Text.Wrap; Layout.preferredWidth: Kirigami.Units.gridUnit * 20 }
            QQC2.TextField { id: saveAsName; Layout.fillWidth: true; placeholderText: "My night map"; onAccepted: saveAsDialog.accept() }
        }
    }
    FileDialog {
        id: exportDialog
        title: "Export the style"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["Live World Map styles (*.json)"]
        onAccepted: styleExec.connectSource(form.styleCmd("export --id " + form.cfg_StyleName + " --path " + form.quoted(String(selectedFile).replace(/^file:\/\//, ""))))
    }
    FileDialog {
        id: importDialog
        title: "Import a style"
        nameFilters: ["Live World Map styles (*.json)"]
        onAccepted: styleExec.connectSource(form.styleCmd("import --path " + form.quoted(String(selectedFile).replace(/^file:\/\//, ""))))
    }
    FileDialog {
        id: picker
        title: "Choose an equirectangular (2:1) world map"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: baseImage.text = String(selectedFile).replace(/^file:\/\//, "")
    }
}
