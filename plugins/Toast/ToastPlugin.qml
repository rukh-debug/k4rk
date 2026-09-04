//  A notification toast. It expires on its own unless the mouse sits
//  on it (the host's care), and a click on the background dismisses
//  it instead of opening the control centre.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "toast"
    title: "Notifications"

    //  59 and not 70, which is what makes the list below and the
    //  priority say the SAME. `enReposo` already declared whom the
    //  toast may relieve —pill, clock, player, volume— but the
    //  priority said something else: at 70 it also beat the control
    //  centre, sound or the dungeon if they opened AFTERWARD,
    //  because the band is only decided when the notice opens. At
    //  59 it sits just above the resting ones and below everything
    //  you open, which is what the list already said.
    priority: 59

    //  And if the island opens something for you while it is up, it
    //  goes. A notice has already said its piece by showing; staying
    //  to cover what you just opened is charging you twice for it.
    //  The notification is NOT lost: it stays in the
    //  list and in the control centre; what leaves is the
    //  toast.
    transitorio: true

    function close() { Notifs.dismissToast() }

    //  Does somebody REALLY hold the island? The resting views
    //  (pill, clock, player) do not count: the toast always relieved
    //  those and must keep doing so. To the open game or the
    //  half-done edit, no longer:
    //  there the notification comes out in a separate band and
    //  nobody loses the screen.
    readonly property var enReposo: ["", "toast", "idle", "clock", "player",
                                     "volume"]

    //  The mode is fixed WHEN EACH toast opens: so that closing the
    //  island halfway does not make the notice jump from the band to
    //  the island.
    //
    //  And it is decided by whoever held it BEFORE the toast, not
    //  by the moment's occupant: as soon as toastOpen lights up, the
    //  toast itself may have already claimed the island —signal
    //  order promises nothing— and looking at it then always said
    //  «toast, that is rest».
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

    active: habilitado && Notifs.toastOpen && !enBanda

    //  The band lives outside the island and only while needed.
    property var banda: K4.Cargador {
        active: self.habilitado && Notifs.toastOpen && self.enBanda
        BandaToast {}
    }

    islandWidth: 440

    // The toast grows a little when the application sends action
    // buttons.
    islandHeight: Notifs.buttons(Notifs.latest).length > 0 ? 112 : 96

    // Clicking the body leads to the application: its default
    // action if it
    // manda y, si no, enfocar su ventana. Antes solo descartaba el aviso.
    handlesBackgroundTap: true
    onBackgroundTapped: {
        Notifs.activate(Notifs.latest)
        Notifs.dismissToast()
    }

    view: Component { ToastView {} }
}
