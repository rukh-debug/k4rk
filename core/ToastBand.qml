// Independent notification island while a summoned view owns the main one.
// Content and actions are shared with the idle-island presentation.
import QtQuick
import K4 as K4
import "../services"

K4.Ventana {
    id: window

    nombre: "k4-notification-popup"
    pantalla: Island.pantallaActiva || Island.pantallaConFoco()
    zonaActiva: card
    reserva: -1

    readonly property var islandRect: K4.Isla.rectEn(pantalla)
    readonly property string corner: Settings.notificationPopupPosition
    readonly property int clearance: Theme.wing * 2

    // Prefer the configured corner. If the open island covers it, use the
    // nearest free corner; on a crowded screen choose the least overlap.
    readonly property point popupPosition: {
        const right = corner !== "top-left" && corner !== "bottom-left"
        const bottom = corner !== "top-left" && corner !== "top-right"
        const leftX = 0
        const topY = 0
        const rightX = Math.max(0, width - card.width)
        const bottomY = Math.max(0, height - card.height)
        const candidates = [
            Qt.point(right ? rightX : leftX, bottom ? bottomY : topY),
            Qt.point(right ? leftX : rightX, bottom ? bottomY : topY),
            Qt.point(right ? rightX : leftX, bottom ? topY : bottomY),
            Qt.point(right ? leftX : rightX, bottom ? topY : bottomY)
        ]
        let best = candidates[0]
        let least = Infinity
        const r = islandRect
        for (let i = 0; i < candidates.length; ++i) {
            const p = candidates[i]
            const overlap = Math.max(0, Math.min(p.x + card.width, r.x + r.ancho + clearance)
                                      - Math.max(p.x, r.x - clearance))
                          * Math.max(0, Math.min(p.y + card.height, r.y + r.alto + clearance)
                                      - Math.max(p.y, r.y - clearance))
            if (overlap < least) {
                least = overlap
                best = p
            }
        }
        return best
    }

    Item {
        id: card
        x: window.popupPosition.x
        y: window.popupPosition.y
        width: Math.min(ToastIsland.islandWidth, window.width)
        height: Math.min(ToastIsland.islandHeight, window.height)
        readonly property bool atBottom: y + height / 2 > window.height / 2
        readonly property bool atRight: x + width / 2 > window.width / 2
        readonly property real bodyRadius: Math.min(32, height / 2)

        // Use the same silhouette and adjoining-wall treatment as shell.qml.
        // The wings extend beyond the body, so only the content is clipped.
        SiluetaIsla {
            anchors.fill: parent
            ala: Theme.wing
            cuerpoRadio: card.bodyRadius
            relleno: Theme.islandBg
            lado: card.atBottom ? "bottom" : "top"
        }
        EdgeAttachedShape {
            anchors.fill: parent
            attachTop: !card.atBottom
            attachBottom: card.atBottom
            attachLeft: !card.atRight
            attachRight: card.atRight
            cornerRadius: card.bodyRadius
            rimThickness: Settings.edgeZoneEnabled ? Settings.edgeZoneSize : 0
            blendReach: Theme.wing * 2
            blendDepth: Theme.wing
            fillColor: Theme.islandBg
        }

        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 180 }

        HoverHandler {
            id: hover
            onHoveredChanged: hovered ? Notifs.holdToast() : Notifs.resumeToast()
        }
        Component.onDestruction: {
            if (hover.hovered)
                Notifs.resumeToast()
        }

        // Behind the content so action buttons and dismiss retain priority.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Notifs.activate(Notifs.latest)
                Notifs.dismissToast()
            }
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.wing
            anchors.rightMargin: Theme.wing
            clip: true
            ToastIslandView { anchors.fill: parent }
        }
    }
}
