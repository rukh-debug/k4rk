//  A meter: a track and its filled portion.
//
//  This replaces repeated implementations. Volume, track progress and quota
//  usage all need the same rounded rectangle inside another rectangle, with
//  the same animation. Copies had begun choosing different heights and
//  durations. External plugins can now use the same meter without drawing
//  it manually, while the shell's own meters stop diverging.
//
//      K4.Medidor { valor: 0.4 }                        // from 0 to 1
//      K4.Medidor { valor: 72; maximo: 100              // or a percentage
//                   tono: K4.Tema.verde; minimo: 3 }
//
//  Unlike `K4.Deslizador`, this displays a value rather than editing it.
//  There is deliberately no mouse handling: use the slider for dragging,
//  or add your own MouseArea above the meter for a custom click action.

import QtQuick

Item {
    id: control

    //  The measured value, between 0 and `maximo`. Clamp it: an invalid
    //  measurement should not become an overflowing fill and a harder-to-find
    //  rendering error.
    property real valor: 0
    property real maximo: 1

    property color tono: Tema.tinta
    property color fondo: Tema.carril

    property int grosor: 4

    //  Minimum fill width when the value is positive. With the default 0,
    //  tiny values may be invisible. That suits volume, but can make a newly
    //  used quota look untouched. Set 3 to keep a thin fill visible.
    property int minimo: 0

    //  Time to reach the new value. Set 0 for immediate updates, as needed
    //  by callers driving the meter every frame.
    property int duracion: 260

    readonly property real fraccion: maximo > 0
        ? Math.max(0, Math.min(1, valor / maximo)) : 0

    implicitWidth: 120
    implicitHeight: grosor

    Rectangle {
        id: carril
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: control.grosor
        radius: height / 2
        color: control.fondo

        Behavior on height {
            enabled: control.duracion > 0
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Rectangle {
            width: control.fraccion <= 0 ? 0
                : Math.max(control.minimo, carril.width * control.fraccion)
            height: parent.height
            radius: parent.radius
            color: control.tono

            Behavior on width {
                enabled: control.duracion > 0
                NumberAnimation {
                    duration: control.duracion
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                enabled: control.duracion > 0
                ColorAnimation { duration: 200 }
            }
        }
    }
}
