//  The house's sound: where it comes out, where it goes in and
//  with how much gain.
//
//  The bar knew how to raise and lower the general volume and
//  nothing else. Choosing the device or looking at a mic's gain
//  forced opening pavucontrol, which is leaving home for something
//  the home has in front of it — and finding out far too late,
//  besides: a mic with runaway gain is not noticed until you listen
//  to what you recorded.
//
//  All through Pipewire, probing nothing: devices arrive by signal
//  and changing the default is assigning a property. The only
//  thing asked by process is each one's BASE volume —the gadget's
//  natural level, which Pipewire does not publish—, once on
//  opening.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "sound"
    title: "Sound"
    priority: 61
    active: habilitado && abierto
    //  A summoned view — it gets a Placement card like its peers (tray,
    //  system, keys), instead of silently following the bar.
    colocable: true

    property bool abierto: false

    //  It steps aside when it opens; the host injects it. Declaring
    //  it is what makes it arrive: without the property, the
    //  reference is not handed out and using it blows up `toggle()`
    //  mid-function —it happened, and what was left unrun was
    //  precisely the baselines read—.
    property var panel: null

    islandWidth: 520

    //  It grows with whatever is plugged in, with a cap: a laptop
    //  with a dock can have six outputs and the island must not
    //  reach the floor for it.
    islandHeight: {
        const filas = Audio.salidas.length + Audio.entradas.length
        return Math.min(560, 150 + filas * 62)
    }

    grabKeyboard: abierto
    closeOnHoverExit: false
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    function toggle() {
        abierto = !abierto
        if (abierto) {
            if (panel)
                panel.close()
            //  Baselines are asked on opening, not at bar startup:
            //  it is a process, and only needed while looking at
            //  this.
            Audio.mirarBases()
        }
    }

    function close() { abierto = false }

    K4.Ipc {
        target: "k4.sound"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
    }

    view: Component { SonidoView { plugin: self } }
}
