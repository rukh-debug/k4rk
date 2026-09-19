// Controlled switch: emits a request; the owner supplies the confirmed state.

import QtQuick

Rectangle {
    id: control

    property bool marcado: false
    signal alternado()

    Connections {
        target: control
        function onAlternado() { Feedback.click() }
    }

    implicitWidth: 40
    implicitHeight: 24
    radius: 12
    color: marcado ? Tema.verde : Tema.superficieAlta
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: enabled
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: marcado
    Accessible.onToggleAction: if (enabled) alternado()
    Keys.onSpacePressed: if (enabled) alternado()
    Keys.onReturnPressed: if (enabled) alternado()
    Keys.onEnterPressed: if (enabled) alternado()

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: 15
        color: "transparent"
        border.width: control.activeFocus ? 1 : 0
        border.color: Tema.azul
    }

    Behavior on color { ColorAnimation { duration: 180 } }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: control.marcado ? parent.width - width - 3 : 3

        Behavior on x {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            control.forceActiveFocus(Qt.MouseFocusReason)
            control.alternado()
        }
    }
}
