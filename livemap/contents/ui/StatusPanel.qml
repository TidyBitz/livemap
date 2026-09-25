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
    Component.onCompleted: check()

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
        onClicked: panel.run("fetch-maps" + (panel.oceanFrom.charAt(0) === "/"
                             ? " --ocean-from '" + panel.oceanFrom.replace(/'/g, "'\\''") + "'" : ""))
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
    QQC2.Label { text: "What the wallpaper reported in the last 3 hours:"; font.bold: true; topPadding: Kirigami.Units.smallSpacing }
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
