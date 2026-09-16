// Single-glyph action. The caller supplies an Accessible.name for its action.

import QtQuick

Item {
    id: control

    property string glifo
    property int tamano: 18
    property color color: Tema.tinta
    property bool activo: true

    signal pulsado()

    implicitWidth: tamano + 16
    implicitHeight: tamano + 12
    enabled: activo
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.onPressAction: if (enabled) pulsado()
    Keys.onSpacePressed: if (enabled) pulsado()
    Keys.onReturnPressed: if (enabled) pulsado()
    Keys.onEnterPressed: if (enabled) pulsado()
    opacity: enabled ? (raton.containsMouse ? 0.8 : 1) : 0.35

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.width: control.activeFocus ? 1 : 0
        border.color: Tema.azul
    }

    Glifo {
        anchors.centerIn: parent
        text: control.glifo
        color: control.color
        font.pixelSize: control.tamano
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: control.activo
        onClicked: {
            control.forceActiveFocus(Qt.MouseFocusReason)
            control.pulsado()
        }
    }

    scale: raton.pressed ? 0.96 : 1
    Behavior on scale {
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
}
