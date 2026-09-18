pragma Singleton

// Native notification toast: transient island view plus separate band.
//
// Priority 59 sits above resting views (pill, clock, player, volume) and
// below everything summoned. When a real view already owns the island the
// notice appears as a capsule band instead of stealing the stage. History
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

    property bool enBanda: false
    property string _dueñoReal: ""

    property var _memoria: Connections {
        target: Island
        function onOcupanteChanged() {
            if (Island.ocupante !== "toast")
                self._dueñoReal = Island.ocupante
        }
    }

    property var _latch: Connections {
        target: Notifs
        function onToastOpenChanged() {
            if (Notifs.toastOpen)
                self.enBanda = self.enReposo.indexOf(self._dueñoReal) < 0
        }
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
