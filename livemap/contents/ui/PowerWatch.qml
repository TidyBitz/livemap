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
    property string units: "0,0"                  // distance, wind: the Units and Storm wind choices, for the widget
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
        onTriggered: exec.connectSource("python3 '" + watch.helper + "' power --layers '" + watch.layers + "' --units " + watch.units + " # " + Date.now())
    }
}
