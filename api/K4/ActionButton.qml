// Compact text action or controlled single-choice chip.
import QtQuick
import QtQuick.Controls as Controls

Controls.AbstractButton {
    id: control

    property bool selected: false

    implicitWidth: Math.max(32, contentItem.implicitWidth + 24)
    implicitHeight: 32
    leftPadding: 12
    rightPadding: 12
    topPadding: 6
    bottomPadding: 6
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Accessible.role: Accessible.Button
    Keys.onReturnPressed: if (enabled) clicked()
    Keys.onEnterPressed: if (enabled) clicked()
    opacity: enabled ? 1 : 0.45

    contentItem: Etiqueta {
        text: control.text
        color: control.selected ? Tema.tinta : Tema.apagado
        font.pixelSize: 12
        font.weight: control.selected ? Font.DemiBold : Font.Medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 8
        color: control.selected ? Qt.rgba(Tema.azul.r, Tema.azul.g, Tema.azul.b, 0.24)
             : control.down ? Tema.carril
             : control.hovered ? Tema.superficieAlta : Tema.superficie
        border.width: control.visualFocus || control.selected ? 1 : 0
        border.color: control.visualFocus ? Tema.azul
                    : Qt.rgba(Tema.azul.r, Tema.azul.g, Tema.azul.b, 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
