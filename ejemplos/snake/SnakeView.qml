//  The Snake board only renders; the whole game lives in the plugin.
//
//  A Repeater of cells rather than a Canvas: QML bindings easily handle
//  238 cells, and each cell derives its color from the state without
//  manual repainting or a 2D context.

import QtQuick
import K4 as K4

Item {
    id: vista

    required property var plugin

    readonly property int celda: 24
    readonly property int margen: 14

    //  Arrow keys and WASD, as expected in a game.
    Keys.onPressed: function (ev) {
        if (ev.key === Qt.Key_Left || ev.key === Qt.Key_A)
            vista.plugin.girar(-1, 0)
        else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_D)
            vista.plugin.girar(1, 0)
        else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_W)
            vista.plugin.girar(0, -1)
        else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_S)
            vista.plugin.girar(0, 1)
        else if (ev.key === Qt.Key_Space || ev.key === Qt.Key_Return)
            vista.plugin.empezar()
        else
            return
        ev.accepted = true
    }
    focus: true

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: vista.margen
        spacing: 8

        // ── the score ─────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18

            K4.Etiqueta {
                text: `Score ${vista.plugin.puntos}`
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            K4.Etiqueta {
                text: `Best ${vista.plugin.record}`
                color: K4.Tema.apagado
                font.pixelSize: 13
            }
        }

        // ── the board ─────────────────────────────────────────────
        Rectangle {
            width: vista.plugin.ancho * vista.celda + 2
            height: vista.plugin.alto * vista.celda + 2
            radius: 6
            color: K4.Tema.superficie
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.1)

            Repeater {
                model: vista.plugin.ancho * vista.plugin.alto

                delegate: Rectangle {
                    required property int index

                    readonly property int puesto:
                        vista.plugin.serpiente.indexOf(index)

                    x: 1 + (index % vista.plugin.ancho) * vista.celda
                    y: 1 + Math.floor(index / vista.plugin.ancho) * vista.celda
                    width: vista.celda - 2
                    height: vista.celda - 2
                    radius: 5

                    color: puesto === 0 ? K4.Tema.verde
                         : puesto > 0
                           //  The body fades toward the tail, making the
                           //  direction of travel clear.
                           ? Qt.darker(K4.Tema.verde,
                                       1 + puesto / vista.plugin.serpiente.length)
                         : index === vista.plugin.comida ? K4.Tema.rojo
                         : "transparent"

                    visible: color !== "transparent"
                }
            }

            //  The start and game-over screens share the same overlay.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "#cc000000"
                visible: !vista.plugin.enMarcha

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    K4.Etiqueta {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: vista.plugin.muerto
                            ? `End · ${vista.plugin.puntos} points`
                            : "Snake"
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }

                    K4.Etiqueta {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Space to play · arrows or WASD"
                        color: K4.Tema.apagado
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: vista.plugin.empezar()
                }
            }
        }
    }
}
