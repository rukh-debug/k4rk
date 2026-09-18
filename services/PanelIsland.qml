pragma Singleton

// Native control centre: toggles, media, shortcuts, notifications, wifi,
// bluetooth, sound and system tabs plus contributed plugin cards.
//
// Summoned via k4.panel and the compat k4 togglePanel/wifi/bluetooth/sound.
// Background and right clicks on the island open the controls tab.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: self

    readonly property string name: "panel"
    readonly property string title: "Control centre"
    readonly property int priority: 60
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: open

    readonly property bool colocable: true
    readonly property string summonCommand: "k4.panel toggle"
    readonly property bool transitorio: false

    property string tab: "controls"
    property bool open: false
    property bool interactionActive: false

    // The launcher, injected by SurfaceRegistry like PluginManager did.
    property var launcher: null

    readonly property int islandWidth: Math.max(640, Math.min(1100, Settings.panelWidth))
    readonly property int islandHeight: tab === "controls" ? alturaControles() : 404

    function altoDe(id) {
        if (id === "toggles")
            return 78
        if (id === "media")
            return 62
        if (id === "shortcuts")
            return 40
        return Enganches.altoDeCard(id)
    }

    function alturaControles() {
        let bloques = 0, alto = 0
        const ids = Settings.panelOrdenEfectivo
        for (let i = 0; i < ids.length; ++i) {
            if (!Settings.bloqueVisible(ids[i]))
                continue
            bloques += 1
            alto += altoDe(ids[i])
        }
        return 14 + 30 + 12 * bloques + alto + 20
    }

    property bool grabKeyboard: open
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnClickOutside: true
    property bool handlesBackgroundTap: true
    signal backgroundTapped()
    onBackgroundTapped: toggle()

    property bool viewLoaded: true
    property var barraApartada
    property var reservaBarra

    function toggle(wanted) {
        const destination = wanted || "controls"
        if (open && destination === tab) close()
        else openTab(destination)
    }

    function openTab(wanted) {
        const nativeTab = ["controls", "notifications", "wifi", "bluetooth", "sound", "system"].indexOf(wanted) >= 0
        const contributed = wanted.indexOf("card:") === 0 && Enganches.cardDetail(wanted.slice(5))
        if (!nativeTab && !contributed)
            return
        if (wanted !== tab) Wifi.cancelPsk()
        tab = wanted
        open = true
        Notifs.dismissToast()
        if (wanted === "notifications") Notifs.markRead()
        if (wanted === "sound")
            Audio.mirarBases()
    }

    function tabTitle() {
        if (tab.indexOf("card:") === 0)
            return Enganches.cardDetailTitle(tab.slice(5)) || "Control centre"
        if (tab === "notifications") return "Notifications"
        if (tab === "wifi") return "Wi-Fi"
        if (tab === "bluetooth") return "Bluetooth"
        if (tab === "sound") return "Sound"
        if (tab === "system") return "System"
        return "Control centre"
    }

    Connections {
        target: Enganches
        function onCardDetailRequested(id) { self.openTab("card:" + id) }
        function onCardsChanged() {
            if (self.tab.indexOf("card:") === 0 && !Enganches.cardDetail(self.tab.slice(5)))
                self.openTab("controls")
        }
    }

    function close() {
        Wifi.cancelPsk()
        interactionActive = false
        open = false
    }
    onOpenChanged: if (!open) Wifi.cancelPsk()

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

    property bool closeOnHoverExit: tab === "controls" && !interactionActive
    property int hoverExitDelay: 0
    signal hoverTimedOut()
    onHoverTimedOut: {
        if (!interactionActive && (!launcher || !launcher.open)) close()
    }

    IpcHandler {
        target: "k4.panel"
        function toggle(): void { self.toggle("controls") }
        function notifications(): void { self.toggle("notifications") }
        function wifi(): void { self.openTab("wifi") }
        function bluetooth(): void { self.openTab("bluetooth") }
        function sound(): void { self.openTab("sound") }
        function system(): void { self.openTab("system") }
        function close(): void { self.close() }
    }

    property Component view: Component {
        PanelIslandView { plugin: self }
    }
}
