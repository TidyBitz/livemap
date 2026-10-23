/*
 * "Status" section of the settings page. It lives in its own file, loaded through
 * a Loader, so that if anything in here fails the rest of the settings still work.
 *
 * All the checking is done by  livemap-helper.py status  (files on disk, GeoIP
 * database age, live connections, and a real request to each online feed). The
 * helper also returns what the wallpaper itself wrote to the journal, which is
 * the quickest way to see why a layer is not drawing.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

ColumnLayout {
    id: panel
    spacing: Kirigami.Units.smallSpacing

    property string quakeFeed: "4.5_day"
    property string oceanFrom: ""        // the fallback image: its dark ocean is kept when the NASA maps are downloaded
    property string homeLat: ""          // the home city, for "where you are" in the coverage section
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
    property var checks: []
    property string version: ""
    property var logLines: []
    property bool busy: false
    property string problem: ""
    readonly property string helper: String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "")

    function run(args) {
        busy = true;
        problem = "";
        // the trailing shell comment makes every command line unique, so it always runs again
        exec.connectSource("python3 '" + helper + "' " + args + " # " + Date.now());
    }
    function check() { run("status --feed " + quakeFeed) }
    // What a section's "Download" button runs for a source that is not there yet: "" when there is nothing to download.
    readonly property var fetchFor: ({
        "Seasonal maps (NASA Blue Marble)": "maps", "City lights (NASA Black Marble)": "maps",
        "Hi-res seasonal maps (NASA Blue Marble, for regions)": "fetch-maps --hires",
        "Borders (Natural Earth)": "fetch-borders", "Plate boundaries (PB2002)": "fetch-borders",
        "GeoIP database (DB-IP)": "fetch-geoip", "Oil and gas infrastructure (BSEE, OpenStreetMap)": "fetch-infrastructure"
    })
    readonly property var fetchSize: ({ "maps": "about 35 MB", "fetch-maps --hires": "about 330 MB, several minutes", "fetch-borders": "about 12 MB", "fetch-geoip": "about 20 MB", "fetch-infrastructure": "a few MB, a minute or two" })
    function fetchCommand(name) {
        var c = fetchFor[name] || "";
        if (c === "maps") c = "fetch-maps" + (oceanFrom.charAt(0) === "/" ? " --ocean-from '" + oceanFrom.replace(/'/g, "'\\''") + "'" : "");
        return c;
    }
    function fetchLabel(name) { var c = fetchFor[name] || ""; return c ? "Download (" + (fetchSize[c] || "") + ")" : ""; }
    function report() {
        var out = ["Live World Map " + version + " status, " + new Date().toString()];
        for (var i = 0; i < checks.length; i++)
            out.push("[" + checks[i].state + "] " + checks[i].name + ": " + checks[i].detail);
        return out.concat(["", "Wallpaper log:"], logLines).join("\n");
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf(" status ") < 0) { panel.check(); return; }      // an update finished: look again
            panel.busy = false;
            try {
                var r = JSON.parse(data.stdout);
                panel.checks = r.checks || [];
                panel.version = r.version || "";
                panel.logLines = r.log || [];
            } catch (e) {
                panel.problem = "The helper did not answer properly: " + String(data.stderr || data.stdout).trim().split("\n").pop();
            }
        }
    }
    Component.onCompleted: { check(); askCoverage(); }

    QQC2.Label { visible: panel.version !== ""; text: "Live World Map " + panel.version + "  \u00b7  what changed: CHANGELOG.md in the download"; opacity: 0.7 }
    Repeater {
        model: panel.checks
        RowLayout {
            id: line
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Math.round(Kirigami.Units.gridUnit * 0.3)
                implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.6); implicitHeight: implicitWidth; radius: implicitWidth / 2
                color: line.modelData.state === "ok" ? Kirigami.Theme.positiveTextColor
                     : line.modelData.state === "warn" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label { text: line.modelData.name; font.bold: true }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: line.modelData.detail
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    opacity: 0.8
                }
            }
        }
    }

    QQC2.Label {
        visible: panel.problem !== ""
        Layout.fillWidth: true
        text: panel.problem
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Kirigami.Theme.negativeTextColor
    }

    QQC2.Button {
        text: "Download NASA maps and city lights (about 35 MB, takes a minute or two)"
        icon.name: "download"; enabled: !panel.busy
        onClicked: panel.run(panel.fetchCommand("Seasonal maps (NASA Blue Marble)"))
    }
    RowLayout {
        QQC2.Button { text: "Check again"; icon.name: "view-refresh"; enabled: !panel.busy; onClicked: panel.check() }
        QQC2.Button { text: "Update GeoIP database"; icon.name: "download"; enabled: !panel.busy; onClicked: panel.run("fetch-geoip") }
        QQC2.Button { text: "Forget connection history"; icon.name: "edit-clear-history"; enabled: !panel.busy; onClicked: panel.run("forget") }
        QQC2.Button { text: "Download border data"; icon.name: "download"; enabled: !panel.busy; onClicked: panel.run("fetch-borders") }
        QQC2.Button { text: "Stitch clouds now"; icon.name: "weather-clouds"; enabled: !panel.busy; onClicked: panel.run("clouds --force") }
        QQC2.Button {
            text: "Copy report"; icon.name: "edit-copy"; enabled: panel.checks.length > 0
            onClicked: { copier.text = panel.report(); copier.selectAll(); copier.copy(); }
        }
        QQC2.BusyIndicator { running: panel.busy; visible: panel.busy; implicitHeight: Kirigami.Units.gridUnit * 1.5; implicitWidth: implicitHeight }
    }

    QQC2.Label {
        visible: panel.busy
        text: "Working... downloads can take a few minutes. The dots above turn green when it is done."
        opacity: 0.8
    }

    // ---- coverage: what covers where, and how fast ------------------------------------------------------------
    QQC2.Label { text: "Coverage: what covers where, and how fast"; font.bold: true; topPadding: Kirigami.Units.gridUnit }
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
    QQC2.Label { text: "What the wallpaper reported in the last 3 hours:"; font.bold: true; topPadding: Kirigami.Units.gridUnit }
    QQC2.Label {
        Layout.fillWidth: true
        text: panel.logLines.join("\n")
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        font.family: "monospace"
        font.pointSize: Math.max(7, Kirigami.Theme.defaultFont.pointSize - 1)
        opacity: 0.8
    }

    TextEdit { id: copier; visible: false }      // clipboard helper for "Copy report" (not named "clip": every Item has a clip property)
}
