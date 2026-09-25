/*
 * Embedded player for the Live tab, loaded only on demand: QtWebEngine is a whole browser engine and not
 * every system has the QML module installed, so this sits behind a Loader that falls back to the
 * "open elsewhere" buttons if the import fails.
 *
 * YouTube's player refuses to start when the embed URL is opened as a top-level page (its "error 153",
 * no HTTP Referer), so the player is placed inside a tiny page of our own with a base URL; the iframe
 * request then carries that page as referrer, which is what the player checks.
 */
import QtQuick
import QtWebEngine

WebEngineView {
    id: web
    property string videoId: ""
    settings.playbackRequiresUserGesture: false
    settings.pluginsEnabled: false
    settings.javascriptCanOpenWindows: false
    backgroundColor: "black"
    function show() {
        if (videoId === "") { loadHtml("<html><body style='background:#000'></body></html>", "https://livemap.local/"); return; }
        var src = "https://www.youtube-nocookie.com/embed/" + videoId + "?autoplay=1&mute=1&rel=0&modestbranding=1&playsinline=1";
        loadHtml("<!doctype html><html><head><meta name='referrer' content='origin'>"
                 + "<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{width:100%;height:100%;border:0}</style></head>"
                 + "<body><iframe src='" + src + "' allow='autoplay; encrypted-media; picture-in-picture' allowfullscreen referrerpolicy='origin'></iframe></body></html>",
                 "https://livemap.local/");
    }
    onVideoIdChanged: show()
    Component.onCompleted: show()
    onNewWindowRequested: function (request) {
        var u = String(request.requestedUrl)
        if (/^https?:\/\//.test(u)) Qt.openUrlExternally(u)   // pop-ups from the page go to the browser, nothing else
    }
}
