//  Centro de control: Wi‑Fi, Bluetooth, volumen, reproducción, accesos y
//  notificaciones. Cuatro pestañas dentro de la misma vista.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "panel"
    title: "Control centre"
    priority: 60
    colocable: true
    active: habilitado && open

    // "controls" | "notifications" | "wifi" | "bluetooth" | "sound"
    property string tab: "controls"
    property bool open: false

    //  The launcher, injected by the host: the shortcuts strip opens apps
    //  through it. A reference is declared by catalog id and filled by
    //  PluginManager — see its `_repartir`.
    property var launcher: null

    islandWidth: Math.max(640, Math.min(1100, Settings.panelWidth))
    //  The controls tab is as tall as what it shows: each block brings its
    //  own height and the spacing between them, so turning a block off makes
    //  the centre shorter instead of leaving a hole behind. The other tabs
    //  are lists that fill, and keep their fixed height.
    islandHeight: tab === "controls" ? alturaControles() : 404

    //  Header 30, margins 14 + 20, 12 between every pair of neighbours, and
    //  each visible block's own height. With everything on, this is the 280
    //  the constant used to be.
    function alturaControles() {
        let bloques = 0, alto = 0
        const alguna = Settings.panelTileWifi || Settings.panelTileBluetooth
                       || Settings.panelTileSound
        if (Settings.panelShowToggles && alguna) {
            bloques += 1
            alto += 78
        }
        if (Settings.panelShowMedia) {
            bloques += 1
            alto += 62
        }
        if (Settings.panelShowShortcuts) {
            bloques += 1
            alto += 40
        }
        return 14 + 30 + 12 * bloques + alto + 20
    }

    // solo mientras se escribe la contraseña de una red
    //  El teclado entero mientras está abierto: «opcional» es OnDemand y
    //  el compositor solo lo da si PINCHAS la superficie, así que abierto
    //  desde el centro de aplicaciones o por atajo no llegaba ni el ESC.
    //  Ver `tecladoOpcional` en api/K4/Plugin.qml.
    grabKeyboard: open

    handlesBackgroundTap: true
    onBackgroundTapped: toggle()

    function toggle(wanted) {
        // pedir una pestaña que no es la que se ve cambia a ella en vez de cerrar
        const wantsTab = wanted !== undefined && wanted.length > 0
        open = !open || (wantsTab && wanted !== tab)

        if (open) {
            if (wantsTab)
                tab = wanted
            Notifs.dismissToast()
            if (tab === "notifications")
                Notifs.markRead()
        }
    }

    function openTab(wanted) {
        tab = wanted
        open = true
        //  Las bases —el nivel natural de cada aparato— son un proceso, y solo
        //  hacen falta cuando se está mirando la lista.
        if (wanted === "sound")
            Audio.mirarBases()
        Wifi.cancelPsk()
        Wifi.notice = ""
    }

    function close() { open = false }

    // El escáner solo mientras se mira la lista correspondiente.
    Binding {
        target: Wifi
        property: "scanning"
        value: self.open && self.tab === "wifi"
    }

    Binding {
        target: Bt
        property: "discovering"
        value: self.open && self.tab === "bluetooth"
    }

    // Una notificación aparta el panel.
    Connections {
        target: Notifs
        function onNotified() { self.open = false }
    }

    // Se cierra solo al salir el ratón, pero no si el lanzador está encima.
    closeOnHoverExit: true
    onHoverTimedOut: {
        if (!launcher || !launcher.open)
            open = false
    }

    K4.Ipc {
        target: "k4.panel"
        function toggle(): void { self.toggle("controls") }
        function notifications(): void { self.toggle("notifications") }
        function wifi(): void { self.openTab("wifi") }
        function bluetooth(): void { self.openTab("bluetooth") }
        function sound(): void { self.openTab("sound") }
        function close(): void { self.close() }
    }

    view: Component {
        PanelView { plugin: self }
    }
}
