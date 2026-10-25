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
    property bool hires: false                    // the 21 600 px monthly set is there (the helper says on every answer)
    property string dir: ""
    property string note: ""
    property bool busy: false
    property real failedAt: 0
    // progress while a build runs (the helper writes it to frame-state as it goes), and a few seconds of "ready"
    property int done: 0
    property int total: 0
    property string what: ""
    property real startedAt: 0
    property real readyAt: 0
    readonly property bool justReady: !busy && readyAt > 0 && (tick - readyAt) < 6000
    property real tick: Date.now()
    Timer { interval: 2000; running: watch.busy || watch.justReady; repeat: true; triggeredOnStart: true
            onTriggered: { watch.tick = Date.now(); if (watch.busy) exec.connectSource("python3 '" + watch.helper + "' frame-state # " + Date.now()); } }

    readonly property string frameArgs: " --style " + style + " --north " + north + " --south " + south + " --west " + west + " --east " + east + " --width " + widthPx + extra
    property bool askAgain: false                 // the view moved while a build ran: look again when it ends
    // The view settles in steps at login and on a resize (the panel appears, the screen scale lands); every step
    // would be a frame of its own to build. So a change waits until the arguments have held still for a moment.
    onFrameArgsChanged: { ready = false; dir = ""; settle.restart(); }
    Timer { id: settle; interval: 2500; onTriggered: { if (watch.busy) watch.askAgain = true; else watch.ask(); } }

    function ask() {
        if (helper === "" || busy) return;
        exec.connectSource("python3 '" + helper + "' frame" + frameArgs + " # " + Date.now());
    }
    readonly property string styleWords: style === "viirs" ? "yesterday's satellite picture" : style === "relief" ? "relief and bathymetry" : style === "dark" ? "land and ocean" : style === "classic" ? "the classic Blue Marble cut to size" : "the monthly maps cut to size"
    // the settings page shows what is going on here (helper `frame-state`): building, ready, or why not
    function report(state, text) { if (helper !== "") exec.connectSource("python3 '" + helper + "' frame-state --set " + state + " --style " + style + " --note '" + String(text).replace(/'/g, "") + "' # " + Date.now()); }
    function fetch() {
        if (busy || helper === "") return;
        if (Date.now() - failedAt < 3600000) return;              // an hour between tries after a failure
        busy = true; done = 0; total = 0; what = ""; startedAt = Date.now(); readyAt = 0;
        note = "Map style: building the imagery for this frame (" + styleWords + ")…";
        report("building", styleWords);
        console.warn("livemap frame: building", frameArgs);
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
                    watch.failedAt = 0; watch.note = ""; watch.readyAt = Date.now(); watch.tick = watch.readyAt;
                    watch.report("ready", watch.styleWords);
                    watch.askAgain = false; watch.ask();
                } else if (watch.askAgain) {
                    watch.askAgain = false; watch.ask();
                } else {
                    watch.failedAt = Date.now();
                    watch.note = "Map style: could not build the imagery - " + String(data.stderr || data.stdout).trim().split("\n").pop();
                    watch.report("failed", String(data.stderr || data.stdout).trim().split("\n").pop());
                    console.warn("livemap frame:", watch.note);
                }
                return;
            }
            if (source.indexOf("' frame-state ") >= 0) {
                try { var st = JSON.parse(data.stdout); if (st.state === "building") { watch.done = st.done || 0; watch.total = st.total || 0; watch.what = st.what || ""; } } catch (e) {}
                return;
            }
            if (source.indexOf("' frame ") < 0) return;
            try {
                var r = JSON.parse(data.stdout);
                watch.hires = !!r.hires;
                if (r.skip) { watch.ready = false; return; }           // nothing to build: the monthly map serves as it is
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
    Component.onCompleted: settle.restart()
    onHelperChanged: settle.restart()
}
