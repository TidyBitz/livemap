/*
 * Appearance shared by every label: the Matrix map style swaps the label font for a monospace one and gives
 * the halos a phosphor-green glow. A singleton, so HaloText can read it without every layer passing it on.
 */
pragma Singleton
import QtQuick

QtObject {
    property bool matrix: false
    readonly property string family: matrix ? "monospace" : ""
    readonly property color glow: "#00ff6a"
}
