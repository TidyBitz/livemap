/*
 * One label, the same everywhere on the map: text over an optional rounded plate. With the plate off
 * the text gets a dark halo instead, so it stays readable over clouds and lines either way.
 */
import QtQuick

Item {
    id: label
    property string text: ""
    property color textColor: "white"
    property real textOpacity: 1
    property bool plate: true
    property color plateColor: "#000510"
    property real plateOpacity: 0.6
    property int px: 11
    property bool bold: false
    property real unit: 1
    property bool caps: false
    property real haloScale: 1              // country names: thicker or thinner halo
    property real letterScale: 1            // country names: letter spacing, 1 = the default

    width: words.implicitWidth
    height: words.implicitHeight

    Rectangle {
        visible: label.plate
        anchors { fill: parent; leftMargin: -4 * label.unit; rightMargin: -4 * label.unit; topMargin: -1; bottomMargin: -1 }
        radius: 3 * label.unit
        color: Qt.rgba(label.plateColor.r, label.plateColor.g, label.plateColor.b, label.plateOpacity)
    }
    HaloText {
        id: words
        text: label.text
        color: Qt.rgba(label.textColor.r, label.textColor.g, label.textColor.b, label.textOpacity)
        haloWidth: label.plate ? 0 : Math.max(1.2, 1.1 * label.unit) * label.haloScale
        haloColor: Qt.rgba(label.plateColor.r, label.plateColor.g, label.plateColor.b, 0.9 * label.textOpacity)
        font.pixelSize: label.px
        font.bold: label.bold
        font.capitalization: label.caps ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: (label.caps ? label.unit : 0) * label.letterScale
    }
}
