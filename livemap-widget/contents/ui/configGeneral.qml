import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page
    property alias cfg_QuakeFeed: quakeFeed.editText
    property alias cfg_FollowMap: followMap.checked
    property alias cfg_Grouped: grouped.checked
    property string cfg_Sound
    property alias cfg_SoundFile: soundFile.text
    property alias cfg_SoundSevere: soundSevere.checked
    property alias cfg_SoundLaunch: soundLaunch.checked
    property alias cfg_SoundLaunchMinutes: soundLaunchMinutes.value
    readonly property var soundIds: ["none", "pop", "chime", "zing", "custom"]
    // the same shell line the widget plays with: pw-play (PipeWire), then paplay, then aplay
    function playCommand(id, file) {
        var f = id === "custom" ? file : String(Qt.resolvedUrl("../sounds/" + id + ".wav")).replace(/^file:\/\//, "");
        if (id === "none" || f === "") return "";
        var q = "'" + f.replace(/'/g, "'\\''") + "'";
        return "f=" + q + "; pw-play \"$f\" 2>/dev/null || paplay \"$f\" 2>/dev/null || aplay -q \"$f\" 2>/dev/null";
    }
    Exec { id: player; onNewData: (source, data) => disconnectSource(source) }
    property alias cfg_RefreshMinutes: refresh.value
    property alias cfg_ShowQuakes: showQuakes.checked
    property alias cfg_ShowVolcanoes: showVolcanoes.checked
    property alias cfg_ShowStorms: showStorms.checked
    property alias cfg_ShowFires: showFires.checked
    property alias cfg_ShowFloods: showFloods.checked
    property alias cfg_ShowTsunami: showTsunami.checked
    property alias cfg_ShowAlerts: showAlerts.checked
    property alias cfg_ShowMaritime: showMaritime.checked
    property alias cfg_ShowLaunches: showLaunches.checked
    property alias cfg_ShowSats: showSats.checked
    property alias cfg_NewMinutes: newMinutes.value
    property int cfg_IdleOpacity
    property alias cfg_FadeIdle: fadeIdle.checked
    property alias cfg_IdleSeconds: idleSeconds.value
    property alias cfg_Preview: preview.currentIndex
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
    QQC2.CheckBox { id: grouped; Kirigami.FormData.label: "Events listed:"; text: "In groups by kind, each with a header that folds" }
    QQC2.CheckBox { id: followMap; text: "Only the kinds the wallpaper shows (also the On the map / Every kind choice on the Events tab)" }
    QQC2.CheckBox { id: showQuakes; Kirigami.FormData.label: "Show:"; text: "Earthquakes" }
    QQC2.CheckBox { id: showVolcanoes; text: "Volcanoes" }
    QQC2.CheckBox { id: showStorms; text: "Storms" }
    QQC2.CheckBox { id: showFires; text: "Wildfires" }
    QQC2.CheckBox { id: showFloods; text: "Floods" }
    QQC2.CheckBox { id: showTsunami; text: "Tsunami bulletins" }
    QQC2.CheckBox { id: showAlerts; text: "Air raid alerts" }
    QQC2.CheckBox { id: showMaritime; text: "Maritime incidents" }
    QQC2.CheckBox { id: showLaunches; text: "Launches" }
    QQC2.CheckBox { id: showSats; text: "Satellites" }
    QQC2.SpinBox {
        id: newMinutes
        Kirigami.FormData.label: "Highlight as new:"
        from: 5; to: 1440; stepSize: 5
        textFromValue: function (v) { return v + " min" }
        valueFromText: function (t) { return parseInt(t) || 60 }
    }
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "On the desktop" }
    RowLayout {
        Kirigami.FormData.label: "When idle:"
        QQC2.CheckBox { id: fadeIdle; text: "Fade to" }
        QQC2.Slider {
            id: idleOpacity
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            from: 5; to: 100; stepSize: 5
            value: page.cfg_IdleOpacity
            onMoved: page.cfg_IdleOpacity = Math.round(value)
        }
        QQC2.Label { text: page.cfg_IdleOpacity + " %"; Layout.minimumWidth: Kirigami.Units.gridUnit * 3 }
    }
    QQC2.SpinBox {
        id: idleSeconds
        Kirigami.FormData.label: "After:"
        enabled: fadeIdle.checked
        from: 1; to: 60
        textFromValue: function (v) { return v + " s" }
        valueFromText: function (t) { return parseInt(t) || 3 }
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40
        opacity: 0.7
        text: "As a desktop widget, the whole thing - frame included - fades to this opacity once the pointer has been away for that long, so the map shows through, and comes back as the pointer arrives. Untick Fade for a fixed opacity at the slider's value (100 % is the plain Plasma look). In a panel the popup is never faded."
    }
    QQC2.ComboBox {
        id: preview
        Kirigami.FormData.label: "Preview on hover:"
        model: ["Off", "Details", "Details and pictures"]
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40
        opacity: 0.7
        text: "Rest the pointer on an event and a bubble beside the widget says what the feed knows: for a storm its class, wind, position and what lies in its path; for a quake its depth, felt reports and intensity; for a flood the full warning and when it ends; for a launch the pad, orbit and status. Pictures are the centre's own graphic where it publishes one at a fixed address - NHC's five-day cone, JTWC's warning chart, the launch's picture - fetched when the bubble opens. Off shows the plain link tooltip instead."
    }
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Notification sound" }
    RowLayout {
        Kirigami.FormData.label: "Sound:"
        QQC2.ComboBox {
            id: sound
            model: ["Off", "Bubble pop", "Chime", "Zing", "A sound file of my own…"]
            currentIndex: Math.max(0, page.soundIds.indexOf(page.cfg_Sound))
            onActivated: page.cfg_Sound = page.soundIds[currentIndex]
        }
        QQC2.Button {
            text: "Play"
            icon.name: "media-playback-start"
            enabled: sound.currentIndex > 0 && (sound.currentIndex < 4 || soundFile.text !== "")
            onClicked: { var c = page.playCommand(page.soundIds[sound.currentIndex], soundFile.text); if (c !== "") player.connectSource(c + " # " + Date.now()); }
        }
    }
    QQC2.TextField { id: soundFile; Kirigami.FormData.label: "Sound file:"; Layout.fillWidth: true; visible: sound.currentIndex === 4; placeholderText: "/home/me/Music/alert.ogg - anything pw-play or paplay can play (wav, ogg, flac, mp3)" }
    QQC2.CheckBox { id: soundSevere; Kirigami.FormData.label: "Play for:"; enabled: sound.currentIndex > 0; text: "A severe event arriving: a magnitude 6+ quake, a category 3+ storm, a red alert" }
    RowLayout {
        enabled: sound.currentIndex > 0
        QQC2.CheckBox { id: soundLaunch; text: "A launch about to happen, within" }
        QQC2.SpinBox { id: soundLaunchMinutes; enabled: soundLaunch.checked; from: 1; to: 120; textFromValue: function (v) { return v + " min" }; valueFromText: function (t) { return parseInt(t) || 15 } }
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40
        opacity: 0.7
        text: "One sound per refresh however many events arrive at once; nothing plays for what was already on the list when the widget started. Played with pw-play, paplay or aplay, whichever is installed."
    }
    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Live" }
    QQC2.TextField { id: liveUrl; Kirigami.FormData.label: "Live stream:"; Layout.fillWidth: true; placeholderText: "YouTube URL of the stream" }
    QQC2.Label { Layout.fillWidth: true; Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40; wrapMode: Text.Wrap; opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize
                 text: "A watch?v= link, a channel's /live page (youtube.com/@sen/live: whatever that channel is broadcasting now, worked out by the helper; Map controls > Sources > Live streams shows what it found), or a link with &list= so the player moves on when a broadcaster restarts under a new id, as NASA does every few months. Below, one more stream per line, Title | URL, in the order the menu lists them." }
    QQC2.TextArea {
        id: liveExtra
        Kirigami.FormData.label: "More streams:"
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        placeholderText: "one per line:  Title | URL"
        wrapMode: TextEdit.WrapAnywhere; Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40
    }
    QQC2.CheckBox { id: liveEmbed; Kirigami.FormData.label: "Live tab:"; text: "Always play the stream inside the widget (needs QtWebEngine; unticked, the Live tab offers Play here each time)" }
    QQC2.TextField { id: livePlayer; Kirigami.FormData.label: "External player:"; Layout.fillWidth: true; placeholderText: "command; the URL is appended" }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40
        opacity: 0.7
        text: "The Live tab shows the stream. Embedded playback runs a browser engine inside plasmashell (a few hundred MB, GPU time while the popup is open); the external player (mpv with yt-dlp, by default) is much lighter and opens a small always-on-top window. 'Open in browser' always works."
    }
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30; Layout.maximumWidth: Kirigami.Units.gridUnit * 40
        opacity: 0.7
        text: "The widget reads the caches the Live World Map wallpaper keeps and runs its helper; it needs that wallpaper installed (~/.local/share/plasma/wallpapers/io.github.tidybitz.livemap.wallpaper)."
    }
}
