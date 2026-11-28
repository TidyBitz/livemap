/*
 * Keeps the fallback cloud image alive. Asks the helper (`livemap-helper clouds`) to stitch the current
 * cloud cover from the geostationary satellites (NASA GIBS: GOES-East, GOES-West, Himawari; EUMETView:
 * Meteosat 0 degrees and Indian Ocean) whenever the ready-made web image cannot be loaded, or always when
 * the setting says so. The helper caches the result for 2.5 h and keeps a source's last picture if that
 * source fails, so partial outages degrade gracefully. Own file behind a Loader: a fault here cannot touch the map.
 */
import QtQuick

Item {
    id: watch
    property string helper: ""
    property int mode: 0                          // 0 web first, stitch on failure; 1 always stitch; 2 web only
    property bool webFailed: false
    property int stamp: 0                         // the wallpaper's 3-hour cloud stamp
    readonly property bool wantLocal: mode === 1 || (mode === 0 && webFailed)
    property string file: ""
    property int fileStamp: 0
    readonly property string localSource: file !== "" ? "file://" + file + "?t=" + fileStamp : ""
    property string note: ""
    property bool busy: false

    Exec {
        id: exec
        onNewData: (source, data) => {
            disconnectSource(source);
            watch.busy = false;
            try {
                var r = JSON.parse(data.stdout);
                watch.file = r.file || "";
                watch.fileStamp = Date.now();
                watch.note = r.note || (r.file === "" ? "Clouds: no stitched image yet" : "");
                console.warn("livemap clouds:", r.file ? "stitched image " + r.age_h + " h old from " + (r.sources_ok || []).join(", ") : "no stitched image",
                             (r.sources_failed || []).length ? "- failed: " + r.sources_failed.join(", ") : "", r.note || "");
            } catch (e) {
                watch.note = "Clouds: the helper did not answer properly";
            }
        }
    }
    function update() {
        if (helper === "" || !wantLocal || busy) return;
        busy = true;
        exec.connectSource("python3 '" + helper + "' clouds # " + Date.now());
    }
    onWantLocalChanged: if (wantLocal) update(); else note = ""
    onStampChanged: update()                      // every three hours, like the web image
    onHelperChanged: update()
}
