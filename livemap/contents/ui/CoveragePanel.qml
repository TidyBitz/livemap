/*
 * "Coverage" section of the settings page: what covers where, and how fast. The helper's `coverage` command
 * turns contents/data/sources.json into a matrix of hazards by world region (each cell the best source, by
 * lead time) and, with a home city set, the "where you are" lines. Loaded through a Loader like the status
 * panel, so a failure in here leaves the rest of the settings working.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

ColumnLayout {
    id: panel
    spacing: Kirigami.Units.smallSpacing
    readonly property string helper: String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "")
    property string homeLat: ""          // the home city, for "where you are"
    property string homeLon: ""
    property var coverage: null          // the helper's coverage answer: regions, hazards, matrix, here
    property var picked: null            // the matrix cell the user clicked
    readonly property var leadColor: ({ minutes: Kirigami.Theme.positiveTextColor, hours: Kirigami.Theme.neutralTextColor, days: Kirigami.Theme.disabledTextColor, "static": Kirigami.Theme.disabledTextColor })
    function askCoverage() {
        var home = parseFloat(homeLat), lon = parseFloat(homeLon);
        coverageExec.connectSource("python3 '" + helper + "' coverage" + (!isNaN(home) && !isNaN(lon) ? " --home " + home + "," + lon : "") + " # " + Date.now());
    }
    onHomeLatChanged: askCoverage()
    onHomeLonChanged: askCoverage()
    P5Support.DataSource {
        id: coverageExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => { disconnectSource(source); try { panel.coverage = JSON.parse(data.stdout); } catch (e) { panel.coverage = null; } }
    }
    Component.onCompleted: askCoverage()
    // ---- coverage: what covers where, and how fast ------------------------------------------------------------
    QQC2.Label {
        visible: panel.coverage !== null && panel.coverage.here
        Layout.fillWidth: true
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        text: panel.coverage && panel.coverage.here ? "Where you are" + (panel.coverage.here.country ? " (" + panel.coverage.here.country + ", " + panel.coverage.here.region + ")" : " (" + panel.coverage.here.region + ")") + ":" : ""
    }
    Repeater {
        model: panel.coverage && panel.coverage.here ? panel.coverage.here.lines : []
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Rectangle { implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5); implicitHeight: implicitWidth; radius: implicitWidth / 2
                        color: modelData.lead ? (panel.leadColor[modelData.lead] || Kirigami.Theme.disabledTextColor) : Kirigami.Theme.negativeTextColor }
            QQC2.Label { text: modelData.hazard; font.bold: true; Layout.preferredWidth: Kirigami.Units.gridUnit * 9 }
            QQC2.Label { Layout.fillWidth: true; text: modelData.text; textFormat: Text.PlainText; wrapMode: Text.Wrap; opacity: 0.85 }
        }
    }
    QQC2.Label { visible: panel.coverage !== null && !panel.coverage.here; text: "Set a home city under Network to see what covers your own area."; opacity: 0.7 }
    QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7
                 text: "Each cell is the best source for that hazard in that region: green reports within minutes of the event or the official warning, amber within hours (episodic or rated reporting), grey a weekly report or a one-time download. A country code means the source is national. Click a cell for the details." }
    GridLayout {
        id: grid
        visible: panel.coverage !== null
        Layout.fillWidth: true
        columns: panel.coverage ? panel.coverage.regions.length + 1 : 1
        columnSpacing: Kirigami.Units.smallSpacing; rowSpacing: 2
        QQC2.Label { text: ""; }
        Repeater {
            model: panel.coverage ? panel.coverage.regions : []
            QQC2.Label { required property var modelData; text: modelData.name; font.bold: true; font.pointSize: Math.max(7, Kirigami.Theme.defaultFont.pointSize - 1); wrapMode: Text.Wrap; Layout.preferredWidth: Kirigami.Units.gridUnit * 6; Layout.alignment: Qt.AlignBottom }
        }
        Repeater {
            model: panel.coverage ? panel.coverage.hazards.length * (panel.coverage.regions.length + 1) : 0
            Item {
                id: cell
                required property int index
                readonly property int row: Math.floor(index / (panel.coverage.regions.length + 1))
                readonly property int col: index % (panel.coverage.regions.length + 1)
                readonly property var hazard: panel.coverage.hazards[row]
                readonly property var region: col > 0 ? panel.coverage.regions[col - 1] : null
                readonly property var cells: region ? (panel.coverage.matrix[hazard.id] || {})[region.id] || [] : []
                readonly property var best: cells.length ? cells[0] : null
                Layout.preferredWidth: col === 0 ? Kirigami.Units.gridUnit * 8 : Kirigami.Units.gridUnit * 6
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                Layout.fillWidth: true
                Rectangle {
                    anchors.fill: parent
                    visible: cell.col > 0
                    radius: 3
                    color: panel.picked && cell.best && panel.picked.hazard === cell.hazard.id && panel.picked.region === cell.region.id ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25) : Qt.rgba(1, 1, 1, 0.04)
                    MouseArea { anchors.fill: parent; enabled: !!cell.best; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: panel.picked = { hazard: cell.hazard.id, region: cell.region.id, hazardName: cell.hazard.name, regionName: cell.region.name, cells: cell.cells } }
                }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4
                    spacing: 4
                    Rectangle { visible: cell.col > 0; implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.5); implicitHeight: implicitWidth; radius: implicitWidth / 2
                                color: cell.best ? (panel.leadColor[cell.best.lead] || Kirigami.Theme.disabledTextColor) : Kirigami.Theme.negativeTextColor; opacity: cell.best ? 1 : 0.5 }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: cell.col === 0 ? cell.hazard.name : cell.best ? cell.best.name.split(" (")[0].replace(/^(NOAA |USGS |NASA |The Space Devs, )/, "") + (cell.best.countries.length ? " · " + cell.best.countries.join("/") : "") : "—"
                        font.bold: cell.col === 0
                        font.pointSize: Math.max(7, Kirigami.Theme.defaultFont.pointSize - (cell.col === 0 ? 0 : 1))
                        elide: Text.ElideRight
                        opacity: cell.best || cell.col === 0 ? 1 : 0.5
                    }
                }
            }
        }
    }
    ColumnLayout {
        visible: panel.picked !== null
        Layout.fillWidth: true
        spacing: 2
        QQC2.Label { text: panel.picked ? panel.picked.hazardName + " · " + panel.picked.regionName : ""; font.bold: true }
        Repeater {
            model: panel.picked ? panel.picked.cells : []
            QQC2.Label {
                required property var modelData
                Layout.fillWidth: true
                textFormat: Text.PlainText; wrapMode: Text.Wrap; opacity: 0.85
                text: "• " + modelData.name + (modelData.countries.length ? " (" + modelData.countries.join("/") + " only)" : "") + ": " + modelData.gives + " · " + modelData.lead + ", " + modelData.cadence
                      + " · " + (modelData.official ? "official" : "community") + " · " + modelData.licence + " · " + modelData.attribution + (modelData.note ? " · " + modelData.note : "")
            }
        }
    }
    QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7; text: "The same table is docs/COVERAGE.md in the download; docs/SOURCES.md has each feed's format and handling. Edit contents/data/sources.json to change either." }
}
