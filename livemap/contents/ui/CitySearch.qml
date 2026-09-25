/*
 * "Home" lookup for the settings page: type a city, the helper searches Natural Earth's populated places
 * offline (no service involved), pick one and the latitude / longitude fields are filled in. Own file behind
 * a Loader, like the status panel, so the rest of the page works even if plasma5support is missing.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

RowLayout {
    id: search
    property alias query: field.text
    property var places: []
    property string note: ""
    property bool busy: false
    signal picked(real lat, real lon, string name)
    readonly property string helper: String(Qt.resolvedUrl("../helper/livemap-helper.py")).replace(/^file:\/\//, "")

    function find() {
        if (field.text.trim() === "") return;
        busy = true; note = "";
        exec.connectSource("python3 '" + helper + "' where-city '" + field.text.trim().replace(/'/g, "'\\''") + "' # " + Date.now());
    }
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            search.busy = false;
            try {
                var r = JSON.parse(data.stdout);
                search.places = r.places || [];
                search.note = r.note || (search.places.length === 0 ? "No such city in the list (7 000 places); type the coordinates instead" : "");
                if (search.places.length > 0) { results.currentIndex = 0; results.popup.open(); }
            } catch (e) { search.note = "The helper did not answer properly"; }
        }
    }
    QQC2.TextField {
        id: field
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        placeholderText: "city name"
        onAccepted: search.find()
    }
    QQC2.Button { text: "Find"; icon.name: "search"; enabled: !search.busy && field.text.trim() !== ""; onClicked: search.find() }
    QQC2.ComboBox {
        id: results
        visible: search.places.length > 0
        Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        model: search.places.map(function (p) { return p.name + (p.region !== "" ? ", " + p.region : "") + ", " + p.country; })
        onActivated: function (i) { var p = search.places[i]; if (p) search.picked(p.lat, p.lon, p.name); }
    }
    QQC2.BusyIndicator { running: search.busy; visible: search.busy; implicitHeight: Kirigami.Units.gridUnit * 1.5; implicitWidth: implicitHeight }
}
