/*
 * Asks the helper every 20 s: battery or mains, how busy the CPU and GPU are, and what the companion
 * widget asked for (mode.json). Its own file behind a Loader, so a problem here cannot affect the map.
 *
 * Load guard: animations pause when CPU or GPU stays above `pauseAt` for two polls in a row, and the live
 * layers unload above `plainAt`; both resume only after three quiet polls (a minute), so a brief spike does
 * not flap the map. On a GPU with no reading (Intel gives only a clock estimate, others nothing) the CPU
 * alone decides - a game still shows there.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: watch
    property string helper: ""
    property bool onBattery: false
    property int cpu: -1                          // percent, -1 = no reading yet
    property int gpu: -1
    property string gpuHow: "none"
    property bool guardEnabled: true
    property int pauseAt: 70
    property int plainAt: 90
    property int guardLevel: 0                    // 0 fine, 1 pause animations, 2 plain map
    property int highRuns: 0
    property int lowRuns: 0
    property var mode: ({})                       // {pause, plain, hide: []} from the widget
    property string layers: ""                    // "quakes,storms,...": the event layers switched on, for the widget
    property string units: "0,0,0,0"              // distance, wind, clock (1 = 12-hour), temperature: the Units choices, for the widget
    property int fireFocus: 1                     // the Wildfire focus, for the widget's feed
    property int floodLevel: 1                    // the flood filter, likewise
    property bool nwsEach: false                  // every NWS alert on its own, likewise
    property int fireSources: 29                  // the wildfire sources on, likewise
    property int floodSources: 15                 // the official flood warning sources on (1 NWS, 2 MeteoAlarm, 4 ECCC, 8 EA)
    property int quakeSources: 3                  // 1 USGS, 2 EMSC
    property string home: ""                      // "lat,lon" of the home place, for the ISS passes
    property string homeName: ""                  // its name as typed on Essentials, for the Sky tab
    property int passes: 0                        // 0 off, 1 visible passes in the widget, 2 every pass
    property int saving: 0                        // what the wallpaper holds back (0 nothing, 1 animations, 2 live layers), for the widget
    property string savingWhy: ""                 // and why ("load guard: CPU 63 %, GPU ?", "on battery", "paused from the widget")
    property bool helperOk: true

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            var text = String(data.stdout).trim();
            if (text === "battery" || text === "mains") { watch.onBattery = text === "battery"; return; }   // an older helper
            try {
                var r = JSON.parse(text);
                watch.helperOk = true;
                watch.onBattery = !!r.battery;
                watch.cpu = r.cpu === null || r.cpu === undefined ? -1 : r.cpu;
                watch.gpu = r.gpu === null || r.gpu === undefined ? -1 : r.gpu;
                watch.gpuHow = r.gpu_how || "none";
                watch.mode = r.mode || ({});
                watch.judge();
            } catch (e) {
                watch.helperOk = false;             // no reading: never guess a guard level from nothing
                if (watch.guardLevel > 0) { watch.guardLevel = 0; watch.highRuns = 0; watch.lowRuns = 0; }
            }
        }
    }
    function judge() {
        if (!guardEnabled) { guardLevel = 0; highRuns = 0; lowRuns = 0; return; }
        // the Intel clock estimate is noisier than a real busy figure: it only counts when it is pinned
        var g = gpuHow === "intel-clock" ? (gpu >= 95 ? gpu : -1) : gpu;
        var load = Math.max(cpu, g);
        if (load < 0) return;                       // nothing measured yet
        var wanted = load >= plainAt ? 2 : load >= pauseAt ? 1 : 0;
        if (wanted > guardLevel) { highRuns++; lowRuns = 0; if (highRuns >= 2) { guardLevel = wanted; highRuns = 0; } }
        else if (wanted < guardLevel) { lowRuns++; highRuns = 0; if (lowRuns >= 3) { guardLevel = wanted; lowRuns = 0; } }
        else { highRuns = 0; lowRuns = 0; }
    }
    onGuardEnabledChanged: judge()
    Timer {
        interval: 20000
        running: watch.helper !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("python3 '" + watch.helper + "' power --layers '" + watch.layers + "' --units " + watch.units + " --fire-focus " + watch.fireFocus + " --flood-level " + watch.floodLevel + " --nws-each " + (watch.nwsEach ? 1 : 0) + " --fire-sources " + watch.fireSources + " --flood-sources " + watch.floodSources + " --quake-sources " + watch.quakeSources + (watch.home !== "" ? " --home '" + watch.home.replace(/[^0-9.,-]/g, "") + "' --home-name '" + watch.homeName.replace(/[^\w .,'-]/g, "").replace(/'/g, "") + "'" : "") + " --passes " + watch.passes + " --saving " + watch.saving + " --why '" + watch.savingWhy.replace(/[^\w %:?.,-]/g, "") + "' # " + Date.now())
    }
}
