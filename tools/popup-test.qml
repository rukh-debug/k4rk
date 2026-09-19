// Run under an isolated shell root; see test_popup_ui.py.
import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 800
        height: 600
        visible: false
        Loader {
            anchors.fill: parent
            source: Quickshell.env("K4_POPUP_TEST_SUITE")
        }
    }
    Timer {
        running: true
        interval: 20000
        onTriggered: { console.error("Popup tests timed out"); Qt.exit(1) }
    }
}
