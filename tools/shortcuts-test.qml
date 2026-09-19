// Launched with private state by test_shortcuts_ui.py.
import QtQuick
import Quickshell

ShellRoot {
    PanelWindow {
        implicitWidth: 760
        implicitHeight: 440
        visible: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        contentItem.opacity: 0
        Loader {
            anchors.fill: parent
            source: Quickshell.env("K4_SHORTCUTS_TEST_SUITE")
        }
    }
    Timer {
        running: true
        interval: 15000
        onTriggered: { console.error("Shortcuts UI tests timed out"); Qt.exit(1) }
    }
}
