// Wi-Fi and Bluetooth share identity, operation feedback and secondary actions.
import QtQuick
import QtQuick.Layouts
import K4 as K4

Rectangle {
    id: row
    property string glyph
    property string title
    property string subtitle
    property bool active: false
    property bool busy: false
    property bool secure: false
    property bool forgettable: false
    property bool failed: false
    signal activated()
    signal forgotten()

    height: 56
    radius: 10
    color: active ? Theme.surfaceHi : pointer.containsMouse ? Theme.surface : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: Theme.blue
    activeFocusOnTab: enabled && !busy
    Accessible.role: Accessible.Button
    Accessible.name: (active ? "Disconnect " : failed ? "Retry " : "Connect ") + title
    Accessible.description: subtitle
    Keys.onSpacePressed: if (!busy) activated()
    Keys.onReturnPressed: if (!busy) activated()
    Accessible.onPressAction: if (enabled && !busy) activated()

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: !row.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: { row.forceActiveFocus(Qt.MouseFocusReason); row.activated() }
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 12
        IconGlyph {
            text: row.glyph
            color: row.active ? Theme.blue : Theme.muted
            font.pixelSize: 18
            Layout.preferredWidth: 22
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            IslandLabel {
                Layout.fillWidth: true
                text: row.title
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            IslandLabel {
                Layout.fillWidth: true
                text: row.subtitle
                color: row.failed ? Theme.red : row.active ? Theme.green : Theme.muted
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        IconGlyph {
            visible: row.secure && !row.busy
            text: Theme.ico.lock
            color: Theme.muted
            font.pixelSize: 12
        }
        IslandLabel {
            visible: !row.busy
            text: row.active ? "Disconnect" : row.failed ? "Retry" : "Connect"
            color: pointer.containsMouse || row.activeFocus ? Theme.ink : Theme.muted
            font.pixelSize: 11
        }
        IconGlyph {
            visible: row.busy
            text: Theme.ico.loading
            color: Theme.muted
            font.pixelSize: 16
            RotationAnimation on rotation {
                running: row.busy && row.visible
                loops: Animation.Infinite
                from: 0; to: 360; duration: 900
            }
        }
        K4.Boton {
            visible: row.forgettable
            activo: !row.busy
            glifo: Theme.ico.linkOff
            tamano: 16
            color: Theme.muted
            Accessible.name: "Forget " + row.title
            onPulsado: row.forgotten()
        }
    }
}
