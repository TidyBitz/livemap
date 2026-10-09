/*
 * Keeps the imagery for the frame on screen in step with the settings. main.qml says which style and
 * frame it wants and how wide; this asks the helper whether frames/<key>/ holds that (`frame`), runs
 * `fetch-frame` when it does not or when a daily picture is a day old, and hands back the folder once it
 * is ready. One fetch at a time; a failure is reported in the corner notice and tried again in an hour.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: watch
    property string helper: ""
    property string style: "seasonal"
    property real north: 90
    property real south: -90
    property real west: -180
    property real east: 180
    property int widthPx: 4096
    property string extra: ""                     // style-specific arguments (the dark style's colours)

    property bool ready: false
    property string dir: ""
    property string note: ""
    property bool busy: false
    property real failedAt: 0

    readonly property string frameArgs: " --style " + style + " --north " + north + " --south " + south + " --west " + west + " --east " + east + " --width " + widthPx + extra
    property bool askAgain: false                 // the view moved while a build ran: look again when it ends
    onFrameArgsChanged: { ready = false; dir = ""; if (busy) askAgain = true; else ask(); }

    function ask() {
        if (helper === "" || busy) return;
        exec.connectSource("python3 '" + helper + "' frame" + frameArgs + " # " + Date.now());
    }
    function fetch() {
        if (busy || helper === "") return;
        if (Date.now() - failedAt < 3600000) return;              // an hour between tries after a failure
        busy = true;
        note = "Map style: building the imagery for this frame (" + (style === "viirs" ? "yesterday's satellite picture" : style === "relief" ? "relief and bathymetry" : style === "dark" ? "land and ocean" : "the monthly maps cut to size") + ")…";
        exec.connectSource("python3 '" + helper + "' fetch-frame" + frameArgs + " # " + Date.now());
    }
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source.indexOf("' fetch-frame ") >= 0) {
                watch.busy = false;
                if (data["exit code"] === 0) {
                    watch.failedAt = 0; watch.note = "";
                    watch.askAgain = false; watch.ask();
                } else if (watch.askAgain) {
                    watch.askAgain = false; watch.ask();
                } else {
                    watch.failedAt = Date.now();
                    watch.note = "Map style: could not build the imagery - " + String(data.stderr || data.stdout).trim().split("\n").pop();
                    console.warn("livemap frame:", watch.note);
                }
                return;
            }
            if (source.indexOf("' frame ") < 0) return;
            try {
                var r = JSON.parse(data.stdout);
                if (r.ready) {
                    watch.dir = r.dir; watch.ready = true;
                    if (r.stale) watch.fetch();                   // yesterday's picture: show it, fetch today's behind it
                } else {
                    watch.fetch();
                }
            } catch (e) {
                watch.note = "Map style: the helper did not answer properly";
            }
        }
    }
    // the daily picture: look once an hour whether a new day's is due; also retries after a failure
    Timer { interval: 3600000; running: watch.helper !== ""; repeat: true; onTriggered: watch.ask() }
    Component.onCompleted: ask()
    onHelperChanged: ask()
}
