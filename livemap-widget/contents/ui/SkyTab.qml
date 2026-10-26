/*
 * The Sky tab: the weather at the home place, sun and moon, tonight's sky - from `livemap-helper sky`, which the
 * helper builds from Open-Meteo and NOAA SWPC (each cached twenty minutes) with the sun, moon and passes computed
 * locally. Everything here is drawn as the helper sends it: the strings are already in the wallpaper's units and
 * clock, so this file only lays them out. Each day is a 24-hour strip: colour for the temperature hour by hour,
 * the night ends darkened, hatched bands where rain or snow is forecast, ticks at 6 / 12 / 18, a line for now on
 * today; hovering a strip opens a bubble with that hour's line.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: sky
    property string helperShell: ""
    property bool active: false                   // the tab is showing: fetch on first show, then every 20 min while shown
    property var doc: ({})
    property bool busy: false
    property real fetchedAt: 0
    readonly property bool ready: !!doc.days
    readonly property string problem: doc.problem || ""
    spacing: Kirigami.Units.smallSpacing

    function refresh(force) {
        if (busy) return;
        if (!force && Date.now() / 1000 - fetchedAt < 600) return;
        busy = true;
        exec.connectSource(helperShell + "sky # " + Date.now());
    }
    onActiveChanged: if (active) refresh(false)
    Timer { interval: 20 * 60 * 1000; running: sky.active; repeat: true; onTriggered: sky.refresh(true) }
    Timer { interval: 60 * 1000; running: sky.active && sky.ready; repeat: true; onTriggered: sky.tick = Date.now() }   // the now line moves, the ages age
    property real tick: Date.now()
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source);
            sky.busy = false;
            try {
                sky.doc = JSON.parse(data.stdout);
                sky.fetchedAt = Date.now() / 1000;
            } catch (e) {
                sky.doc = { problem: "The helper did not answer: " + String(data.stderr || data.stdout).trim().split("\n").pop() };
            }
        }
    }
    // how old each source's answer is: plain under an hour, amber to three hours, red beyond
    function ageColor(minutes) {
        if (minutes === null || minutes === undefined) return Kirigami.Theme.negativeTextColor;
        return minutes < 60 ? Kirigami.Theme.textColor : minutes < 180 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor;
    }
    function iconFor(name, day) {
        return name === "sun" ? (day === false ? "weather-clear-night" : "weather-clear") : name === "partly" ? (day === false ? "weather-few-clouds-night" : "weather-few-clouds")
             : name === "cloud" ? "weather-clouds" : name === "fog" ? "weather-fog" : name === "rain" ? "weather-showers" : name === "snow" ? "weather-snow"
             : name === "sleet" ? "weather-snow-rain" : name === "storm" ? "weather-storm" : "weather-clouds";
    }
    // temperature colour for a strip cell: cold blue through grey to warm gold, by the week's range
    function tempColor(t) {
        if (t === null || t === undefined) return "transparent";
        var cold = Qt.rgba(0.23, 0.44, 0.64, 1), mid = Qt.rgba(0.55, 0.58, 0.60, 1), warm = Qt.rgba(0.95, 0.79, 0.41, 1);
        return t < 0.5 ? Qt.tint(cold, Qt.rgba(mid.r, mid.g, mid.b, t * 2)) : Qt.tint(mid, Qt.rgba(warm.r, warm.g, warm.b, (t - 0.5) * 2));
    }

    // ---- placeholder states ----
    PlasmaExtras.PlaceholderMessage {
        visible: !sky.ready
        Layout.fillWidth: true; Layout.fillHeight: true
        iconName: sky.problem !== "" ? "weather-none-available" : "weather-clear"
        text: sky.problem !== "" ? (sky.problem.indexOf("No home place") === 0 ? "No home place yet" : "No forecast") : sky.busy ? "Asking for the forecast…" : "Your sky"
        explanation: sky.problem !== "" ? sky.problem : "The weather, sun and moon at your home place, and what tonight's sky holds."
        helpfulAction: Kirigami.Action {
            visible: !sky.busy
            text: sky.problem.indexOf("No home place") === 0 ? "Open the wallpaper settings" : "Try again"; icon.name: sky.problem.indexOf("No home place") === 0 ? "configure" : "view-refresh"
            onTriggered: { if (sky.problem.indexOf("No home place") === 0) exec.connectSource(sky.helperShell + "widget --configure # " + Date.now()); else sky.refresh(true); }
        }
    }

    // ---- the tab ----
    PC3.ScrollView {
        id: scroll
        visible: sky.ready
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff     // nothing here may be wider than the tab
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Kirigami.Units.smallSpacing
            readonly property var d: sky.doc
            readonly property var now: sky.doc.now || ({})
            readonly property var ages: sky.doc.ages || ({})

            // the place, the time there, and how old each source's answer is
            RowLayout {
                Layout.fillWidth: true
                PC3.Label { text: parent.parent.d.name || ""; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                PC3.Label { text: (parent.parent.now.time || "") + (parent.parent.d.timezone ? " · " + parent.parent.d.timezone.replace(/_/g, " ") : ""); opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                PC3.ToolButton { icon.name: "view-refresh"; enabled: !sky.busy; onClicked: sky.refresh(true); PC3.ToolTip.text: "Fetch again"; PC3.ToolTip.visible: hovered }
            }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: [["Forecast", "forecast"], ["Air quality", "air"], ["Kp", "kp"]]
                    PC3.Label {
                        required property var modelData
                        readonly property var a: (sky.doc.ages || ({}))[modelData[1]] || ({})
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: modelData[0] + " " + (a.age || "no data yet") + (a.error ? " · could not be fetched" : "")
                        color: sky.ageColor(a.minutes)
                        opacity: a.minutes !== null && a.minutes !== undefined && a.minutes < 60 ? 0.7 : 1
                        PC3.ToolTip.text: a.error || ""; PC3.ToolTip.visible: a.error ? hover.containsMouse : false
                        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    }
                }
            }

            // now
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                readonly property var now: parent.now
                Kirigami.Icon { source: sky.iconFor(parent.now.icon, parent.now.is_day); implicitWidth: Kirigami.Units.iconSizes.huge; implicitHeight: implicitWidth }
                ColumnLayout {
                    spacing: 0
                    PC3.Label { text: parent.parent.now.temp || ""; font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.6; font.weight: Font.Light }
                    PC3.Label { text: (parent.parent.now.words || "") + " · feels like " + (parent.parent.now.feels || "") + " · high " + (parent.parent.now.high || "") + ", low " + (parent.parent.now.low || ""); opacity: 0.8; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    spacing: 0
                    Layout.alignment: Qt.AlignRight
                    PC3.Label { horizontalAlignment: Text.AlignRight; Layout.fillWidth: true; opacity: 0.8; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: "Wind " + (parent.parent.now.wind || "") }
                    PC3.Label { horizontalAlignment: Text.AlignRight; Layout.fillWidth: true; opacity: 0.8; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: "Humidity " + (parent.parent.now.humidity || "") + " · cloud " + (parent.parent.now.cloud || "") }
                    PC3.Label { horizontalAlignment: Text.AlignRight; Layout.fillWidth: true; opacity: 0.8; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: "Pressure " + (parent.parent.now.pressure || "") + (parent.parent.now.trend ? ", " + parent.parent.now.trend : "") }
                }
            }

            // the next days: a strip each
            PC3.Label { text: "The next days"; font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.6; Layout.topMargin: Kirigami.Units.smallSpacing }
            GridLayout {
                Layout.fillWidth: true
                columns: 5
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: 2
                // the scale over the strip column
                Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 4.2; implicitHeight: 1 }
                Item { Layout.preferredWidth: Kirigami.Units.iconSizes.small; implicitHeight: 1 }
                Item {
                    id: scaleRow
                    Layout.fillWidth: true; implicitHeight: Kirigami.Units.gridUnit * 0.9
                    readonly property bool clock12: !!((sky.doc.units || [0, 0, 0, 0])[2])
                    Repeater {
                        model: [[0, "12 am", "0"], [6, "6 am", "6"], [12, "noon", "12"], [18, "6 pm", "18"], [24, "", "24"]]
                        PC3.Label {
                            required property var modelData
                            x: modelData[0] === 0 ? 0 : modelData[0] === 24 ? scaleRow.width - width : scaleRow.width * modelData[0] / 24 - width / 2
                            y: 0
                            text: scaleRow.clock12 && modelData[1] !== "" ? modelData[1] : modelData[2]
                            opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9
                        }
                    }
                }
                PC3.Label { text: "high / low"; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5 }
                PC3.Label { text: "rain"; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.6 }

            }
            // the rows (a Repeater cannot emit five grid cells per day, so the rows are a column of their own)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: sky.doc.days || []
                    delegate: RowLayout {
                        id: dayRow
                        required property var modelData
                        required property int index
                        z: stripHover.containsMouse ? 10 : 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC3.Label { text: dayRow.modelData.short; Layout.preferredWidth: Kirigami.Units.gridUnit * 4.2; elide: Text.ElideRight
                                    PC3.ToolTip.text: dayRow.modelData.name + " · " + dayRow.modelData.words; PC3.ToolTip.visible: dayHover.containsMouse
                                    MouseArea { id: dayHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton } }
                        Kirigami.Icon { source: sky.iconFor(dayRow.modelData.icon, true); implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth }
                        // the strip
                        Item {
                            id: strip
                            Layout.fillWidth: true
                            implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.8)
                            readonly property var cells: dayRow.modelData.cells || []
                            readonly property real sunrise: dayRow.modelData.sunrise_h === null || dayRow.modelData.sunrise_h === undefined ? -1 : dayRow.modelData.sunrise_h
                            readonly property real sunset: dayRow.modelData.sunset_h === null || dayRow.modelData.sunset_h === undefined ? -1 : dayRow.modelData.sunset_h
                            Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(0, 0, 0, 0.25); clip: true
                                Row {
                                    anchors.fill: parent
                                    Repeater {
                                        model: strip.cells
                                        Rectangle {
                                            required property var modelData
                                            width: strip.width / 24; height: strip.height
                                            color: sky.tempColor(modelData ? modelData.t : null)
                                            // rain or snow over this hour: hatching whose strength is the chance
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: !!modelData && modelData.p > 0.15
                                                color: modelData && modelData.snow ? Qt.rgba(0.92, 0.95, 0.98, Math.min(0.85, (modelData ? modelData.p : 0))) : Qt.rgba(0.3, 0.62, 0.9, Math.min(0.85, (modelData ? modelData.p : 0)))
                                                Canvas {
                                                    anchors.fill: parent
                                                    onPaint: { var c = getContext("2d"); c.clearRect(0, 0, width, height); c.strokeStyle = "rgba(255,255,255,0.25)"; c.lineWidth = 1;
                                                               for (var x = -height; x < width + height; x += 4) { c.beginPath(); c.moveTo(x, height); c.lineTo(x + height, 0); c.stroke(); } }
                                                }
                                            }
                                        }
                                    }
                                }
                                // night: before sunrise and after sunset
                                Rectangle { x: 0; y: 0; height: parent.height; width: strip.sunrise >= 0 ? strip.sunrise / 24 * parent.width : 0; color: Qt.rgba(0, 0, 0, 0.5) }
                                Rectangle { x: strip.sunset >= 0 ? strip.sunset / 24 * parent.width : parent.width; y: 0; height: parent.height; width: parent.width - x; color: Qt.rgba(0, 0, 0, 0.5) }
                                // the hour ticks
                                Repeater { model: [6, 12, 18]; Rectangle { required property int modelData; x: modelData / 24 * strip.width; y: 0; width: 1; height: strip.height; color: Qt.rgba(1, 1, 1, 0.3) } }
                                // now, on today
                                Rectangle {
                                    visible: dayRow.index === 0 && sky.doc.now_h !== null && sky.doc.now_h !== undefined
                                    readonly property real h: sky.doc.now_h === null || sky.doc.now_h === undefined ? 0 : sky.doc.now_h + (sky.tick / 1000 - (sky.doc.at || sky.tick / 1000)) / 3600
                                    x: Math.max(0, Math.min(strip.width - 2, h / 24 * strip.width)); y: -1; width: 2; height: strip.height + 2
                                    color: "white"
                                }
                                // the hover: which hour; the bubble is drawn in the popup itself, above the strip (below it for the
                                // first rows), so it never sits under the pointer - a tooltip window there flickered on and off
                                MouseArea {
                                    id: stripHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    readonly property int hour: Math.max(0, Math.min(23, Math.floor(mouseX / width * 24)))
                                }
                                Rectangle { visible: stripHover.containsMouse; x: stripHover.hour / 24 * strip.width; y: 0; width: strip.width / 24; height: strip.height; color: "transparent"; border.color: "white"; border.width: 1 }
                            }
                            Rectangle {
                                id: hourBubble
                                visible: stripHover.containsMouse
                                z: 20
                                readonly property var day: dayRow.modelData
                                readonly property var cell: (day.cells || [])[stripHover.hour] || null
                                readonly property string line: (day.lines || [])[stripHover.hour] || ""
                                // above the strip when the rows above give it room, else below - never over the hour scale
                                readonly property bool below: dayRow.y < height + Kirigami.Units.smallSpacing
                                readonly property real pad: Kirigami.Units.largeSpacing
                                width: Math.min(strip.width, bubbleIcon.width + Kirigami.Units.largeSpacing + Math.max(bubbleHead.implicitWidth, bubbleBody.implicitWidth) + pad * 2)
                                height: Math.max(bubbleIcon.height, bubbleHead.implicitHeight + bubbleBody.implicitHeight + 2) + pad * 2
                                x: Math.max(0, Math.min(strip.width - width, stripHover.hour / 24 * strip.width + strip.width / 48 - width / 2))
                                y: below ? strip.height + Kirigami.Units.smallSpacing : -height - Kirigami.Units.smallSpacing
                                radius: 4
                                color: Kirigami.Theme.backgroundColor
                                border.color: Kirigami.Theme.highlightColor; border.width: 1
                                Kirigami.Icon {
                                    id: bubbleIcon
                                    x: hourBubble.pad; y: hourBubble.pad
                                    width: Kirigami.Units.iconSizes.medium; height: width
                                    source: sky.iconFor(hourBubble.cell ? hourBubble.cell.icon : "cloud", hourBubble.cell ? hourBubble.cell.day : true)
                                }
                                PC3.Label { id: bubbleHead; x: bubbleIcon.x + bubbleIcon.width + Kirigami.Units.largeSpacing; y: hourBubble.pad; font.bold: true
                                            text: (hourBubble.day.name || "") + (hourBubble.line ? " \u00b7 " + hourBubble.line.split(" \u00b7 ")[0] : "") }
                                PC3.Label { id: bubbleBody; x: bubbleHead.x; y: bubbleHead.y + bubbleHead.implicitHeight + 2; font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            text: hourBubble.line ? hourBubble.line.split(" \u00b7 ").slice(1).join("\n") : "no forecast for this hour" }
                            }
                        }
                        PC3.Label { Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5; horizontalAlignment: Text.AlignRight
                                    text: dayRow.modelData.high + " / " + dayRow.modelData.low }
                        PC3.Label { Layout.preferredWidth: Kirigami.Units.gridUnit * 2.6; horizontalAlignment: Text.AlignRight; text: dayRow.modelData.chance; color: Kirigami.Theme.linkColor
                                    PC3.ToolTip.text: dayRow.modelData.rain + " expected"; PC3.ToolTip.visible: rainHover.containsMouse
                                    MouseArea { id: rainHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton } }
                    }
                }
            }
            PC3.Label { Layout.fillWidth: true; Layout.preferredWidth: scroll.availableWidth; wrapMode: Text.Wrap; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: "Each bar is the day, midnight to midnight: colour is the temperature hour by hour, the dark ends are night, blue hatching is rain (white, snow), the white line is now. Hover for the hour." }

            // sun and moon · tonight's sky
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: 1
                readonly property var sun: sky.doc.sun || ({})
                readonly property var tonight: sky.doc.tonight || ({})
                PC3.Label { text: "Sun and moon"; font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.6; Layout.topMargin: Kirigami.Units.smallSpacing }
                PC3.Label { text: "Tonight's sky"; font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.6; Layout.topMargin: Kirigami.Units.smallSpacing }
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop; Layout.fillWidth: true; spacing: 1
                    readonly property var sun: parent.sun
                    Repeater {
                        model: [["Sunrise", "sunrise"], ["Sunset", "sunset"], ["Day length", "day_length"], ["Dark for satellites", "dark"], ["Moon", "moon"], ["UV index", "uv"]]
                        RowLayout {
                            required property var modelData
                            visible: !!parent.sun[modelData[1]]
                            Layout.fillWidth: true
                            PC3.Label { text: modelData[0]; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            Item { Layout.fillWidth: true }
                            PC3.Label { text: parent.parent.sun[modelData[1]] || ""; font.pointSize: Kirigami.Theme.smallFont.pointSize; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop; Layout.fillWidth: true; spacing: 1
                    readonly property var tonight: parent.tonight
                    Repeater {
                        model: [["Cloud cover tonight", "cloud"], ["Next visible pass", "pass"], ["Aurora", "kp"], ["Air quality", "air"]]
                        RowLayout {
                            required property var modelData
                            visible: !!parent.tonight[modelData[1]]
                            Layout.fillWidth: true
                            PC3.Label { text: modelData[0]; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            Item { Layout.fillWidth: true }
                            PC3.Label { text: parent.parent.tonight[modelData[1]] || ""; font.pointSize: Kirigami.Theme.smallFont.pointSize; horizontalAlignment: Text.AlignRight; wrapMode: Text.Wrap; Layout.maximumWidth: Kirigami.Units.gridUnit * 16 }
                        }
                    }
                }
            }
            PC3.Label { Layout.fillWidth: true; Layout.preferredWidth: scroll.availableWidth; wrapMode: Text.Wrap; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; Layout.topMargin: Kirigami.Units.smallSpacing
                        text: "Open-Meteo (forecast, air quality) · NOAA SWPC (Kp) · sun, moon and passes computed here · fetched every 20 minutes" }
        }
    }

}
