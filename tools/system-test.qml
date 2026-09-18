import QtQuick
import Quickshell

ShellRoot {
    PanelWindow {
        implicitWidth: 1200; implicitHeight: 900
        visible: true; color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        contentItem.opacity: 0
        Loader { anchors.fill: parent; source: Quickshell.env("K4_SYSTEM_TEST_SUITE") }
    }
    Timer {
        running: true; interval: 40000
        onTriggered: { console.error("System tests timed out"); Qt.exit(1) }
    }
}
