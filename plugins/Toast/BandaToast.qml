//  The toast in band mode: when another plugin truly holds the
//  island —the game open, the half-done edit— the notification no
//  longer steals it. It comes out as a capsule of its own glued to
//  the island's edge (below if the bar lives on top, above if it
//  lives below) and coexists with whatever is there.
//
//  Same life as the usual toast: it expires on its own, the mouse
//  on it sustains it, click goes to the application and the ✕
//  dismisses it.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4.Ventana {
    id: ventana

    nombre: "k4-toast-banda"
    zonaActiva: capsula

    readonly property bool abajo: K4.Isla.posicion === "abajo"
    readonly property var aviso: Notifs.latest

    Rectangle {
        id: capsula

        readonly property int alto: 56

        x: K4.Isla.rect.x + (K4.Isla.rect.ancho - width) / 2
        y: ventana.abajo ? K4.Isla.rect.y - alto - 8
                         : K4.Isla.rect.y + K4.Isla.rect.alto + 8
        width: Math.min(420, contenido.implicitWidth + 84)
        height: alto
        radius: 16
        color: Theme.islandBg
        border.width: 1
        border.color: Theme.surfaceHi

        //  It slides in from the island, as if peeking out of it.
        opacity: 0
        Component.onCompleted: entrada.start()

        ParallelAnimation {
            id: entrada
            NumberAnimation { target: capsula; property: "opacity"; to: 1; duration: 180 }
            NumberAnimation {
                target: capsula; property: "y"
                from: ventana.abajo ? K4.Isla.rect.y - 20
                                    : K4.Isla.rect.y + K4.Isla.rect.alto - 20
                to: ventana.abajo ? K4.Isla.rect.y - capsula.alto - 8
                                  : K4.Isla.rect.y + K4.Isla.rect.alto + 8
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }

        //  The mouse on it sustains it, as with the usual toast.
        HoverHandler {
            onHoveredChanged: hovered ? Notifs.holdToast() : Notifs.resumeToast()
        }

        Row {
            id: contenido
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: Notifs.iconFor(ventana.aviso)
                width: 26; height: 26
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 52
                sourceSize.height: 52
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                IslandLabel {
                    text: ventana.aviso ? ventana.aviso.summary
                                        : "Notification"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: Math.min(290, implicitWidth)
                }

                IslandLabel {
                    visible: text.length > 0
                    text: ventana.aviso ? ventana.aviso.body : ""
                    color: Theme.muted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    width: Math.min(290, implicitWidth)
                }
            }
        }

        //  Click on the body: to the application, like the big
        //  toast.
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: 40
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Notifs.activate(ventana.aviso)
                Notifs.dismissToast()
            }
        }

        MediaButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: Theme.ico.close
            glyphSize: 13
            glyphColor: Theme.muted
            onActivated: Notifs.dismissToast()
        }
    }
}
