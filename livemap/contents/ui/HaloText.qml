/*
 * Text with a real halo: eight dark copies offset around it. Qt's own Text.Outline is a single
 * physical pixel, which disappears on a 5K screen. Used for labels that sit directly on the map.
 */
import QtQuick

Item {
    id: haloText
    property string text: ""
    property color color: "white"
    property color haloColor: Qt.rgba(0, 0.02, 0.06, 0.9)
    property real haloWidth: 1.5
    property alias font: front.font

    implicitWidth: front.implicitWidth
    implicitHeight: front.implicitHeight
    width: implicitWidth; height: implicitHeight

    Repeater {
        model: haloText.haloWidth > 0 ? 8 : 0
        Text {
            x: Math.cos(index * Math.PI / 4) * haloText.haloWidth
            y: Math.sin(index * Math.PI / 4) * haloText.haloWidth
            text: haloText.text
            textFormat: Text.PlainText
            font: front.font
            // the Matrix style: a dim green glow instead of the dark halo
            color: Look.matrix ? Qt.rgba(Look.glow.r, Look.glow.g, Look.glow.b, 0.35 * haloText.haloColor.a) : haloText.haloColor
        }
    }
    Text { id: front; text: haloText.text; textFormat: Text.PlainText; color: haloText.color
           Component.onCompleted: if (Look.family !== "") font.family = Look.family
           Connections { target: Look; function onFamilyChanged() { front.font.family = Look.family !== "" ? Look.family : Qt.application.font.family } } }
}
