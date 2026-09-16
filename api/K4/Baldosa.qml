// Pressable surface with the same pointer, keyboard and focus behavior.

import QtQuick

Rectangle {
    id: baldosa

    property bool activa: false          // Selected, independently of pressing.
    property color colorBase: Tema.superficie
    property color colorActiva: Tema.superficieAlta
    property bool pulsable: true
    property alias encima: raton.containsMouse

    signal pulsada()

    activeFocusOnTab: enabled && pulsable
    Accessible.role: pulsable ? Accessible.Button : Accessible.Grouping
    Accessible.onPressAction: if (enabled && pulsable) pulsada()
    Keys.onSpacePressed: if (enabled && pulsable) pulsada()
    Keys.onReturnPressed: if (enabled && pulsable) pulsada()
    Keys.onEnterPressed: if (enabled && pulsable) pulsada()

    radius: 16
    color: activa ? colorActiva
        : (raton.containsMouse && pulsable ? Tema.superficieAlta : colorBase)

    scale: raton.pressed && pulsable ? 0.97 : 1

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale {
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    // Quiet inner edge; keyboard focus is deliberately stronger than hover.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: baldosa.activeFocus ? Tema.azul : Qt.rgba(1, 1, 1,
            raton.containsMouse && baldosa.pulsable ? 0.09 : 0.04)
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: baldosa.pulsable
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            baldosa.forceActiveFocus(Qt.MouseFocusReason)
            baldosa.pulsada()
        }
    }
}
