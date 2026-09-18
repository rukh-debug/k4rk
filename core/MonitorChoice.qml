import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    implicitHeight: 34
    implicitWidth: 190
    font.family: Theme.uiFont
    font.pixelSize: 12
    contentItem: IslandLabel {
        text: control.displayText
        verticalAlignment: Text.AlignVCenter
        leftPadding: 10
        rightPadding: 28
        elide: Text.ElideRight
    }
    background: Rectangle {
        color: Theme.surface
        radius: 8
        border.width: 1
        border.color: control.activeFocus ? Theme.blue : Theme.track
    }
}
