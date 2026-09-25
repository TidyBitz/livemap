import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_QuakeFeed: quakeFeed.editText
    property alias cfg_RefreshMinutes: refresh.value
    property alias cfg_ShowQuakes: showQuakes.checked
    property alias cfg_ShowVolcanoes: showVolcanoes.checked
    property alias cfg_ShowStorms: showStorms.checked
    property alias cfg_ShowFires: showFires.checked
    property alias cfg_ShowLaunches: showLaunches.checked
    property alias cfg_ShowSats: showSats.checked
    property alias cfg_NewMinutes: newMinutes.value
    property alias cfg_LiveUrl: liveUrl.text
    property alias cfg_LiveEmbed: liveEmbed.checked
    property alias cfg_LiveExtra: liveExtra.text
    property alias cfg_LivePlayer: livePlayer.text

    QQC2.ComboBox {
        id: quakeFeed
        Kirigami.FormData.label: "Earthquake feed:"
        editable: true
        model: ["2.5_day", "4.5_day", "significant_week"]
    }
    QQC2.SpinBox {
        id: refresh
        Kirigami.FormData.label: "Refresh every:"
        from: 1; to: 60
        textFromValue: function (v) { return v + " min" }
        valueFromText: function (t) { return parseInt(t) || 5 }
    }
    QQC2.CheckBox { id: showQuakes; Kirigami.FormData.label: "Show:"; text: "Earthquakes" }
    QQC2.CheckBox { id: showVolcanoes; text: "Volcanoes" }
    QQC2.CheckBox { id: showStorms; text: "Storms" }
    QQC2.CheckBox { id: showFires; text: "Wildfires" }
    QQC2.CheckBox { id: showLaunches; text: "Launches" }
    QQC2.CheckBox { id: showSats; text: "Satellites" }
    QQC2.SpinBox {
        id: newMinutes
        Kirigami.FormData.label: "Highlight as new:"
        from: 5; to: 1440; stepSize: 5
        textFromValue: function (v) { return v + " min" }
        valueFromText: function (t) { return parseInt(t) || 60 }
    }
    QQC2.TextField { id: liveUrl; Kirigami.FormData.label: "Live stream:"; Layout.fillWidth: true; placeholderText: "YouTube URL of the stream" }
    QQC2.TextArea {
        id: liveExtra
        Kirigami.FormData.label: "More streams:"
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        placeholderText: "one per line:  Title | URL"
        wrapMode: TextEdit.NoWrap
    }
    QQC2.CheckBox { id: liveEmbed; Kirigami.FormData.label: "Live tab:"; text: "Embed the player in the widget (needs QtWebEngine; heavy)" }
    QQC2.TextField { id: livePlayer; Kirigami.FormData.label: "External player:"; Layout.fillWidth: true; placeholderText: "command; the URL is appended" }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: "The Live tab shows the stream. Embedded playback runs a browser engine inside plasmashell (a few hundred MB, GPU time while the popup is open); the external player (mpv with yt-dlp, by default) is much lighter and opens a small always-on-top window. 'Open in browser' always works."
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: "The widget reads the caches the Live World Map wallpaper keeps and runs its helper; it needs that wallpaper installed (~/.local/share/plasma/wallpapers/io.github.tidybitz.livemap.wallpaper)."
    }
}
