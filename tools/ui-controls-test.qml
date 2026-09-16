// QML_IMPORT_PATH="$PWD/api" QT_QPA_PLATFORM=offscreen quickshell -p tools/ui-controls-test.qml
import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 480
        height: 360
        visible: true
        Loader { anchors.fill: parent; source: "tst_ui_controls.qml" }
    }
    Timer {
        running: true
        interval: 20000
        onTriggered: { console.error("UI control tests timed out"); Qt.exit(1) }
    }
}
