pragma Singleton

// Native sound mixer: input/output devices, default selection and gain.
//
// Summoned via k4.sound toggle with its own Placement card. The control
// centre Sound tab stays as a second entry over the same Audio service:
// `k4 sound` opens the tab, `k4.sound toggle` opens this surface.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: self

    readonly property string name: "sound"
    readonly property string title: "Sound"
    readonly property int priority: 61
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: abierto

    readonly property bool colocable: true
    readonly property string summonCommand: "k4.sound toggle"
    readonly property bool transitorio: false

    property bool abierto: false

    // The control centre; SurfaceRegistry injects it.
    property var panel: null

    readonly property int islandWidth: 520
    readonly property int islandHeight: {
        const filas = Audio.salidas.length + Audio.entradas.length
        return Math.min(560, 150 + filas * 62)
    }

    property bool grabKeyboard: abierto
    property bool closeOnHoverExit: false
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnClickOutside: true
    property bool handlesBackgroundTap: true
    signal backgroundTapped()
    onBackgroundTapped: {}

    property int hoverExitDelay: 0
    signal hoverTimedOut()

    property bool viewLoaded: true
    property var barraApartada
    property var reservaBarra

    function toggle() {
        abierto = !abierto
        if (abierto) {
            if (panel)
                panel.close()
            Audio.mirarBases()
        }
    }

    function close() { abierto = false }

    IpcHandler {
        target: "k4.sound"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
    }

    property Component view: Component { SoundIslandView { plugin: self } }
}
