import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 900
        height: 700
        visible: true
        Loader { anchors.fill: parent; source: Quickshell.env("K4_OPENWEBUI_TEST_SUITE") }
    }
    Timer {
        running: true
        interval: 30000
        onTriggered: { console.error("OpenWebUI UI tests timed out"); Qt.exit(1) }
    }
}
