// Launched in an isolated shell root by test_agents_ui.py.
import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 720
        height: 800
        visible: true
        Loader {
            anchors.fill: parent
            source: Quickshell.env("K4_AGENTS_TEST_SUITE")
        }
    }
    Timer {
        running: true
        interval: 30000
        onTriggered: { console.error("Agents UI tests timed out"); Qt.exit(1) }
    }
}
