pragma Singleton

// Native control centre: toggles, media, shortcuts, notifications, wifi,
// bluetooth, sound, power/display and system tabs plus contributed plugin cards.
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

    // These native services must run even before their detail page is opened.
    Component.onCompleted: { NightLight.refresh(); PowerMode.refresh() }

    // The launcher, injected by SurfaceRegistry like PluginManager did.
    property var launcher: null

    readonly property int islandWidth: Settings.panelWidth
    readonly property int islandHeight: tab === "controls" ? alturaControles()
        : tab === "system" ? (islandWidth < 800 ? 720 : 600)
        : tab === "night-light" && Settings.nightLightMode === "solar" ? 560 : 404
    readonly property int radioCount: Number(Settings.panelTileWifi) + Number(Settings.panelTileBluetooth)
    readonly property int sliderCount: Number(Settings.panelTileSound) + Number(Settings.panelTileBrightness)
    readonly property bool stackedControls: radioCount > 0 && sliderCount > 0

    function altoDe(id) {
        if (id === "toggles")
            return (radioCount ? 96 : 0) + (sliderCount ? 120 : 0) + (stackedControls ? 12 : 0)
        if (id === "media")
            return 72
        if (id === "power-display")
            return 80
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
        return 16 + 32 + 16 * bloques + alto + 20
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
        const nativeTab = ["controls", "notifications", "wifi", "bluetooth", "sound", "system", "power-mode", "night-light"].indexOf(wanted) >= 0
        const contributed = wanted.indexOf("card:") === 0 && Enganches.cardDetail(wanted.slice(5))
        if (!nativeTab && !contributed)
            return
        if (wanted !== tab) Wifi.cancelPsk()
        tab = wanted
        open = true
        if (wanted === "notifications") {
            Notifs.dismissToast()
            Notifs.markRead()
        }
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
        if (tab === "power-mode") return "Power mode"
        if (tab === "night-light") return "Night light"
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
        target: Brightness
        property: "watching"
        value: self.open && self.tab === "controls" && Settings.panelShowToggles && Settings.panelTileBrightness
    }

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
        function powerMode(): void { self.openTab("power-mode") }
        function nightLight(): void { self.openTab("night-light") }
        function close(): void { self.close() }
    }

    property Component view: Component {
        PanelIslandView { plugin: self }
    }
}
