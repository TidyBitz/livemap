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

    // ---- the "?" beside a line, and the bubble it opens: what the scale means ----
    property string infoTopic: ""
    property var infoAnchor: null
    component InfoButton: PC3.ToolButton {
        id: ib
        property string topic: ""
        visible: true
        enabled: topic !== ""
        opacity: topic === "" ? 0 : (sky.infoTopic === topic ? 1 : 0.5)
        icon.name: "help-contextual"
        implicitWidth: Kirigami.Units.iconSizes.small + 6; implicitHeight: implicitWidth
        // the bubble opens on hover after a moment (and stays while the pointer is on the ?), or on a click to keep it
        hoverEnabled: true
        property bool pinned: false
        Timer { id: openSoon; interval: 350; onTriggered: if (ib.hovered) { sky.infoTopic = ib.topic; sky.infoAnchor = ib; } }
        onHoveredChanged: { if (hovered) openSoon.restart(); else if (!pinned && sky.infoTopic === topic) { sky.infoTopic = ""; sky.infoAnchor = null; } }
        onClicked: { if (pinned) { pinned = false; sky.infoTopic = ""; sky.infoAnchor = null; } else { pinned = true; sky.infoTopic = topic; sky.infoAnchor = ib; } }
        Connections { target: sky; function onInfoTopicChanged() { if (sky.infoTopic !== ib.topic) ib.pinned = false; } }
    }
    // each topic: a title, a line of context, and rows [range, meaning, colour] where there is a scale
    readonly property var infoText: ({
        air: { title: "Air quality index", note: sky.doc.tonight && sky.doc.tonight.air_scale === "eu"
                   ? "The European AQI (EEA): 0 to 100 and beyond, from the worst of the main pollutants over the hour. Shown with kilometres; miles switch to the US scale."
                   : "The US AQI (EPA): 0 to 500, from the worst of the main pollutants. Shown with miles; kilometres switch to the European scale.",
               rows: sky.doc.tonight && sky.doc.tonight.air_scale === "eu"
                   ? [["0 – 20", "good", "#50f0e6"], ["20 – 40", "fair", "#50ccaa"], ["40 – 60", "moderate", "#f0e641"], ["60 – 80", "poor", "#ff5050"], ["80 – 100", "very poor", "#960032"], ["over 100", "extremely poor", "#7d2181"]]
                   : [["0 – 50", "good", "#00e400"], ["51 – 100", "moderate", "#ffff00"], ["101 – 150", "unhealthy for sensitive groups", "#ff7e00"], ["151 – 200", "unhealthy", "#ff0000"], ["201 – 300", "very unhealthy", "#8f3f97"], ["301 – 500", "hazardous", "#7e0023"]] },
        kp: { title: "Kp and the aurora", note: "The planetary K index, 0 to 9, says how disturbed Earth's magnetic field is right now (NOAA, every three hours). The higher it is, the further from the poles the aurora reaches; the latitudes are rough and need a dark, clear northern (or southern) horizon.",
              rows: [["Kp 0 – 2", "quiet · aurora near the Arctic circle, about 66° and up", "#4caf50"], ["Kp 3 – 4", "unsettled · down to about 55° (Scotland, Alberta)", "#8bc34a"], ["Kp 5", "minor storm (G1) · about 50° (Seattle, Paris)", "#ffeb3b"], ["Kp 6", "moderate storm (G2) · about 45° (Oregon, Milan)", "#ff9800"], ["Kp 7 – 8", "strong to severe (G3 – G4) · about 40° (Denver, Madrid)", "#f44336"], ["Kp 9", "extreme (G5) · the deep south and beyond", "#9c27b0"]] },
        uv: { title: "UV index", note: "The World Health Organization's scale for the day's peak sunburn strength.",
              rows: [["0 – 2", "low · no protection needed", "#4caf50"], ["3 – 5", "moderate · hat and sunscreen at midday", "#ffeb3b"], ["6 – 7", "high · cover up, seek shade at midday", "#ff9800"], ["8 – 10", "very high · extra care, burns quickly", "#f44336"], ["11 +", "extreme · stay out of the sun", "#9c27b0"]] },
        dark: { title: "Dark for satellites", note: "The hours when the sun is more than 6° below the horizon (civil dusk to civil dawn): dark enough to see a sunlit satellite. A visible pass is one in these hours while the station is still in sunlight; the moon and clouds decide the rest.", rows: [] },
        pressure: { title: "Pressure and its trend", note: "Sea-level pressure now, and whether it has moved more than about a hectopascal in the last three hours. Falling usually means weather is on the way, rising that it is clearing; the rate matters more than the number.",
                    rows: [["rising", "clearing, drier, often windier", "#4caf50"], ["steady", "no change coming soon", "#9e9e9e"], ["falling", "cloud, rain or wind on the way", "#ff9800"]] },
        moon: { title: "The moon", note: "The phase and how much of the disc is lit, from a standard approximation (within half a day). A bright moon washes out faint satellites and the aurora; the dark half of the month is best for both.", rows: [] },
        cloud: { title: "Cloud cover tonight", note: "The forecast's average cloud cover through the dark hours. Under about 25 % is clear enough for satellite spotting; over 85 % there is nothing to see.", rows: [] },
        pass: { title: "Visible passes", note: "When the ISS or Tiangong crosses your sky after dusk or before dawn while still lit by the sun: where it rises, how high it gets (90° is overhead), where it sets and for how long. It looks like a bright, steady, fast star; no blinking.", rows: [] }
    })
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
                    RowLayout {
                        Layout.alignment: Qt.AlignRight; spacing: 2
                        PC3.Label { opacity: 0.8; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: "Pressure " + (parent.parent.parent.now.pressure || "") + (parent.parent.parent.now.trend ? ", " + parent.parent.parent.now.trend : "") }
                        InfoButton { topic: "pressure" }
                    }
                    RowLayout {                                    // the air is a condition of now, like the wind, not of the night sky
                        Layout.alignment: Qt.AlignRight; spacing: 2
                        visible: !!(sky.doc.tonight || ({})).air
                        PC3.Label { opacity: 0.8; font.pointSize: Kirigami.Theme.smallFont.pointSize; text: "Air " + ((sky.doc.tonight || ({})).air || "") }
                        InfoButton { topic: "air" }
                    }
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
            // the rows (a Repeater cannot emit five grid cells per day, so the rows are a column of their own), in an
            // Item so that the one hour bubble can be drawn after - and so over - every row
            Item {
                id: rowsBox
                Layout.fillWidth: true
                implicitHeight: rows.implicitHeight
                // the hover: which strip and which hour; the bubble below reads these
                property var hoverStrip: null
                property var hoverDay: null
                property int hoverHour: 0
            ColumnLayout {
                id: rows
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                spacing: 2
                Repeater {
                    model: sky.doc.days || []
                    delegate: RowLayout {
                        id: dayRow
                        required property var modelData
                        required property int index
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
                                                // the band: at least a third strong once there is any rain, so it reads against the temperature colour
                                                color: modelData && modelData.snow ? Qt.rgba(0.92, 0.95, 0.98, Math.max(0.35, Math.min(0.9, (modelData ? modelData.p : 0)))) : Qt.rgba(0.25, 0.6, 0.95, Math.max(0.35, Math.min(0.9, (modelData ? modelData.p : 0))))
                                                Canvas {
                                                    anchors.fill: parent
                                                    onPaint: { var c = getContext("2d"); c.clearRect(0, 0, width, height); c.strokeStyle = "rgba(255,255,255,0.6)"; c.lineWidth = 1.5;
                                                               for (var x = -height; x < width + height; x += 5) { c.beginPath(); c.moveTo(x, height); c.lineTo(x + height, 0); c.stroke(); } }
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
                                    x: Math.max(0, Math.min(strip.width - 3, h / 24 * strip.width)); y: -2; width: 3; height: strip.height + 4
                                    color: "white"
                                    Rectangle { anchors.fill: parent; anchors.margins: -2; color: "transparent"; border.color: Qt.rgba(0, 0, 0, 0.6); border.width: 2; z: -1 }
                                }
                                // the hover: which hour; the bubble is drawn in the popup itself, above the strip (below it for the
                                // first rows), so it never sits under the pointer - a tooltip window there flickered on and off
                                MouseArea {
                                    id: stripHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    readonly property int hour: Math.max(0, Math.min(23, Math.floor(mouseX / width * 24)))
                                    onContainsMouseChanged: { if (containsMouse) { rowsBox.hoverStrip = strip; rowsBox.hoverDay = dayRow.modelData; rowsBox.hoverHour = hour; } else if (rowsBox.hoverStrip === strip) rowsBox.hoverStrip = null; }
                                    onHourChanged: if (containsMouse) rowsBox.hoverHour = hour
                                }
                                Rectangle { visible: stripHover.containsMouse; x: stripHover.hour / 24 * strip.width; y: 0; width: strip.width / 24; height: strip.height; color: "transparent"; border.color: "white"; border.width: 1 }
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
            // the hour bubble: beside the hovered hour - to its right, or to its left near the end of the strip - so it is
            // never under the pointer; centred on the strip and kept inside the block of rows, so it never covers the
            // hour scale or the text below; drawn last, so it is over every strip; opaque, so it can be read
            Rectangle {
                id: hourBubble
                visible: rowsBox.hoverStrip !== null
                z: 100
                readonly property var day: rowsBox.hoverDay || ({})
                readonly property var cell: (day.cells || [])[rowsBox.hoverHour] || null
                readonly property string line: (day.lines || [])[rowsBox.hoverHour] || ""
                readonly property real pad: Kirigami.Units.largeSpacing
                readonly property point at: rowsBox.hoverStrip ? rowsBox.hoverStrip.mapToItem(rowsBox, 0, 0) : Qt.point(0, 0)
                readonly property real stripW: rowsBox.hoverStrip ? rowsBox.hoverStrip.width : 0
                readonly property real stripH: rowsBox.hoverStrip ? rowsBox.hoverStrip.height : 0
                readonly property real hourX: at.x + rowsBox.hoverHour / 24 * stripW
                readonly property real gap: Kirigami.Units.largeSpacing
                width: Math.min(rowsBox.width, bubbleIcon.width + Kirigami.Units.largeSpacing + Math.max(bubbleHead.implicitWidth, bubbleBody.implicitWidth) + pad * 2)
                height: Math.max(bubbleIcon.height, bubbleHead.implicitHeight + bubbleBody.implicitHeight + 2) + pad * 2
                x: hourX + stripW / 24 + gap + width <= at.x + stripW ? hourX + stripW / 24 + gap : Math.max(0, hourX - gap - width)
                y: Math.max(0, Math.min(rowsBox.height - height, at.y + (stripH - height) / 2))
                radius: 4
                Kirigami.Theme.inherit: false
                Kirigami.Theme.colorSet: Kirigami.Theme.Window
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 1)   // fully opaque, whatever the theme says
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
            PC3.Label { Layout.fillWidth: true; Layout.preferredWidth: scroll.availableWidth; wrapMode: Text.Wrap; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: "Each bar is the day, midnight to midnight: colour is the temperature hour by hour, the dark ends are night, blue hatching is rain (white, snow), the white line is now. Hover for the hour." }

            // sun and moon · tonight's sky, in an Item so the "?" bubble can be drawn over the block, beside its line
            Item {
                id: infoBox
                Layout.fillWidth: true
                implicitHeight: infoGrid.implicitHeight
            GridLayout {
                id: infoGrid
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
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
                        model: [["Sunrise", "sunrise"], ["Sunset", "sunset"], ["Day length", "day_length"], ["Dark for satellites", "dark", "dark"], ["Moon", "moon", "moon"], ["UV index", "uv", "uv"]]
                        RowLayout {
                            required property var modelData
                            visible: !!parent.sun[modelData[1]]
                            Layout.fillWidth: true
                            PC3.Label { text: modelData[0]; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            Item { Layout.fillWidth: true }
                            PC3.Label { text: parent.parent.sun[modelData[1]] || ""; font.pointSize: Kirigami.Theme.smallFont.pointSize; horizontalAlignment: Text.AlignRight }
                            InfoButton { topic: modelData[2] || "" }
                        }
                    }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop; Layout.fillWidth: true; spacing: 1
                    readonly property var tonight: parent.tonight
                    Repeater {
                        model: [["Cloud cover tonight", "cloud", "cloud"], ["Next visible pass", "pass", "pass"], ["Aurora", "kp", "kp"]]
                        RowLayout {
                            required property var modelData
                            visible: !!parent.tonight[modelData[1]]
                            Layout.fillWidth: true
                            PC3.Label { text: modelData[0]; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                            Item { Layout.fillWidth: true }
                            PC3.Label { text: parent.parent.tonight[modelData[1]] || ""; font.pointSize: Kirigami.Theme.smallFont.pointSize; horizontalAlignment: Text.AlignRight; wrapMode: Text.Wrap; Layout.maximumWidth: Kirigami.Units.gridUnit * 16 }
                            InfoButton { topic: modelData[2] || "" }
                        }
                    }
                }
            }
            // the "?" bubble: to the left of the ? that opened it (the ? is at the end of its line), vertically centred on it
            // and kept inside the tab's width; drawn in the popup, not as a tooltip window, which flickered under the pointer
            Rectangle {
                id: infoBubble
                visible: sky.infoTopic !== "" && sky.infoAnchor !== null
                z: 100
                readonly property var info: sky.infoText[sky.infoTopic] || ({ title: "", note: "", rows: [] })
                readonly property point at: sky.infoAnchor ? sky.infoAnchor.mapToItem(infoBox, 0, 0) : Qt.point(0, 0)
                readonly property real pad: Kirigami.Units.largeSpacing
                width: Math.min(infoBox.width - Kirigami.Units.gridUnit, Kirigami.Units.gridUnit * 24)
                height: infoColumn.implicitHeight + pad * 2
                x: Math.max(0, at.x - width - Kirigami.Units.smallSpacing)
                y: Math.max(-infoBox.y, at.y + (sky.infoAnchor ? sky.infoAnchor.height / 2 : 0) - height / 2)
                radius: 4
                Kirigami.Theme.inherit: false
                Kirigami.Theme.colorSet: Kirigami.Theme.Window
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 1)
                border.color: Kirigami.Theme.highlightColor; border.width: 1
                ColumnLayout {
                    id: infoColumn
                    x: infoBubble.pad; y: infoBubble.pad
                    width: infoBubble.width - infoBubble.pad * 2
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label { text: infoBubble.info.title; font.bold: true }
                    PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: infoBubble.info.note; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.85 }
                    Repeater {
                        model: infoBubble.info.rows
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle { Layout.preferredWidth: 10; Layout.preferredHeight: 10; radius: 2; color: modelData[2] }
                            PC3.Label { text: modelData[0]; font.pointSize: Kirigami.Theme.smallFont.pointSize; Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5 }
                            PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData[1]; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.85 }
                        }
                    }
                }
            }
            }
            PC3.Label { Layout.fillWidth: true; Layout.preferredWidth: scroll.availableWidth; wrapMode: Text.Wrap; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; Layout.topMargin: Kirigami.Units.smallSpacing
                        text: "Open-Meteo (forecast, air quality) · NOAA SWPC (Kp) · sun, moon and passes computed here · fetched every 20 minutes" }
        }
    }

}
