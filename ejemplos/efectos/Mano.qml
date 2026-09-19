//  The hand peeking out beside the island.
//
//  Two pieces make this possible: K4.Ventana, a transparent fullscreen
//  surface above everything, and K4.Isla.rect, the island's actual geometry
//  for anchoring precisely to its edge. Together they let anything peek
//  out, fall, or move around outside the bar.

import QtQuick
import K4 as K4

K4.Ventana {
    id: ventana

    nombre: "k4-efectos-mano"

    //  Only the hand captures mouse input; the rest of the screen belongs
    //  to the desktop. Otherwise, the invisible window would swallow clicks.
    zonaActiva: mano

    required property var plugin

    Text {
        id: mano

        //  Attached to the island's right edge, slightly below the top,
        //  facing outward.
        x: K4.Isla.rect.x + K4.Isla.rect.ancho - 4
        y: K4.Isla.rect.y + 6
        text: "👋"
        font.pixelSize: 30
        rotation: -35

        //  Pops into view and keeps waving.
        scale: 0
        Component.onCompleted: aparecer.start()

        NumberAnimation {
            id: aparecer
            target: mano
            property: "scale"
            to: 1
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }

        SequentialAnimation {
            running: true
            loops: Animation.Infinite
            NumberAnimation { target: mano; property: "rotation"; to: -10; duration: 260; easing.type: Easing.InOutQuad }
            NumberAnimation { target: mano; property: "rotation"; to: -50; duration: 260; easing.type: Easing.InOutQuad }
            NumberAnimation { target: mano; property: "rotation"; to: -10; duration: 260; easing.type: Easing.InOutQuad }
            NumberAnimation { target: mano; property: "rotation"; to: -35; duration: 220; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 900 }
        }

        //  A high five hides it.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ventana.plugin.manoFuera = false
        }
    }
}
