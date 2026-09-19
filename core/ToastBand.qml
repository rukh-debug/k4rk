// Notifications retain their busy-only popup policy and hover lifetime, while
// sharing rendering and collision allocation with independent plugin islands.
import QtQuick
import "../services"

IndependentIsland {
    id: window
    owner: ToastIsland
    nombre: "k4-notification-popup"
    pantalla: Island.pantallaActiva || Island.pantallaConFoco()
    preferredPlacement: ({
        side: Settings.notificationPopupPosition.indexOf("bottom") === 0 ? "bottom" : "top",
        align: Settings.notificationPopupPosition.endsWith("left") ? 0 : 100
    })

    onHoveredChanged: hovered ? Notifs.holdToast() : Notifs.resumeToast()
    Component.onDestruction: {
        if (hovered)
            Notifs.resumeToast()
    }
}
