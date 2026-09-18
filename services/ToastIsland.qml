pragma Singleton

// Native notification: shared content in the idle island or a separate popup.
//
// Priority 59 sits above resting views (pill, clock, player, volume) and
// below everything summoned. When a real view already owns the island the
// notice appears independently instead of stealing the stage. History
// lives in the control centre; hover strips live in clock and player.

import QtQuick
import Quickshell
import K4 as K4
import "../core"

Singleton {
    id: self

    readonly property string name: "toast"
    readonly property string title: "Notifications"
    readonly property int priority: 59
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool transitorio: true

    function close() { Notifs.dismissToast() }

    readonly property var enReposo: ["", "toast", "idle", "clock", "player",
                                     "volume"]

    // Read requests rather than the arbitration result: the notification's
    // own active state must not form a feedback loop with the winning view.
    readonly property bool enBanda: {
        const surfaces = SurfaceRegistry.surfaces
        for (let i = 0; i < surfaces.length; ++i) {
            const surface = surfaces[i]
            if (self.enReposo.indexOf(surface.name) < 0
                    && surface.habilitado && surface.active)
                return true
        }
        return false
    }

    readonly property bool active: Notifs.toastOpen && !enBanda

    property var banda: K4.Cargador {
        active: Notifs.toastOpen && self.enBanda
        ToastBand {}
    }

    readonly property int islandWidth: 440
    readonly property int islandHeight: Notifs.buttons(Notifs.latest).length > 0 ? 112 : 96

    property bool handlesBackgroundTap: true
    signal backgroundTapped()
    onBackgroundTapped: {
        Notifs.activate(Notifs.latest)
        Notifs.dismissToast()
    }

    property bool viewLoaded: true
    readonly property bool colocable: false
    readonly property string summonCommand: ""
    property bool closeOnClickOutside: true
    property bool grabKeyboard: false
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 0

    property var barraApartada
    property var reservaBarra

    property Component view: Component { ToastIslandView {} }
}
