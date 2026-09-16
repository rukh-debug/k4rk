// Shared single-line editor. Callers own labels, validation and commit policy.
import QtQuick
import QtQuick.Controls as Controls

Controls.TextField {
    id: control

    implicitWidth: 210
    implicitHeight: 32
    leftPadding: 10
    rightPadding: 10
    topPadding: 6
    bottomPadding: 6
    font.family: Tema.fuente
    font.pixelSize: 12
    color: Tema.tinta
    placeholderTextColor: Tema.apagado
    selectionColor: Tema.azul
    selectedTextColor: Tema.tinta
    selectByMouse: true
    activeFocusOnTab: true
    clip: true
    opacity: enabled ? 1 : 0.5
    background: Rectangle {
        radius: 8
        color: control.activeFocus ? Tema.superficieAlta : Tema.superficie
        border.width: 1
        border.color: control.activeFocus ? Tema.azul : Tema.carril
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
