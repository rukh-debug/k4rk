//  Control centre: Wi‑Fi, Bluetooth, volume, system, playback,
//  shortcuts and notifications. Six views inside the same surface.

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
    summonCommand: "k4.panel toggle"
    active: habilitado && open

    // "controls" | "notifications" | "wifi" | "bluetooth" | "sound" | "system"
    property string tab: "controls"
    property bool open: false
    property bool interactionActive: false

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
    //  the constant used to be. One table for every reader: the native
    //  blocks' heights live HERE, and the Loader in the view asks the same
    //  `altoDe` — the two hardcoded lists were the old disease (a block
    //  resized in one and not the other left the centre with a hole or a
    //  crop).
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

    // only while typing a network's password
    //  The whole keyboard while open: «optional» is OnDemand and the
    //  compositor only gives it if you CLICK the surface, so opened
    //  from the application center or by shortcut not even ESC
    //  arrived. See `tecladoOpcional` in api/K4/Plugin.qml.
    grabKeyboard: open

    handlesBackgroundTap: true
    onBackgroundTapped: toggle()

    function toggle(wanted) {
        const destination = wanted || "controls"
        if (open && destination === tab) close()
        else openTab(destination)
    }

    function openTab(wanted) {
        if (["controls", "notifications", "wifi", "bluetooth", "sound", "system"].indexOf(wanted) < 0)
            return
        if (wanted !== tab) Wifi.cancelPsk()
        tab = wanted
        open = true
        Notifs.dismissToast()
        if (wanted === "notifications") Notifs.markRead()
        //  The baselines —each device's natural level— are a
        //  process, and only needed while the list is being looked
        //  at.
        if (wanted === "sound")
            Audio.mirarBases()
    }

    function close() {
        Wifi.cancelPsk()
        interactionActive = false
        open = false
    }
    onOpenChanged: if (!open) Wifi.cancelPsk()

    // The scanner only while the matching list is being looked at.
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

    // Detail tasks and direct manipulation survive incidental pointer exits.
    closeOnHoverExit: tab === "controls" && !interactionActive
    onHoverTimedOut: {
        if (!interactionActive && (!launcher || !launcher.open)) close()
    }

    K4.Ipc {
        target: "k4.panel"
        function toggle(): void { self.toggle("controls") }
        function notifications(): void { self.toggle("notifications") }
        function wifi(): void { self.openTab("wifi") }
        function bluetooth(): void { self.openTab("bluetooth") }
        function sound(): void { self.openTab("sound") }
        function system(): void { self.openTab("system") }
        function close(): void { self.close() }
    }

    view: Component {
        PanelView { plugin: self }
    }
}
