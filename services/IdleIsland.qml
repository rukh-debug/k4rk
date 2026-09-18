pragma Singleton

// The folded pill, owned by the host instead of a plugin.
//
// It used to be plugins/Idle/. A pill that can be disabled is no pill at
// all: every other surface assumes a fallback at priority 0, and every
// monitor shows it while another screen owns the island. So the state lives
// here, always on, and shell.qml arbitrates it through SurfaceRegistry.
//
// Contract: this object quacks like a K4.Plugin surface. shell.qml reads
// name/title/priority/habilitado/active/viewLoaded/colocable/transitorio,
// islandWidth/islandHeight/view/summonCommand, the focus flags, the
// hover-exit pair, handlesBackgroundTap/backgroundTapped and close().
// `nativo` marks the object for host health reporting.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: self

    readonly property string name: "idle"
    readonly property string title: "Pill"
    readonly property int priority: 0
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: true

    property bool viewLoaded: true
    readonly property bool colocable: false
    readonly property string summonCommand: ""
    readonly property bool transitorio: false

    // How many tray icons the pill shows. Zero (the default) shows
    // everything with no "+N"; a number caps it. Kept for the view's
    // first frame; the live TrayRow default follows the same setting.
    readonly property int trayShown: Settings.pillTrayMax > 0
        ? Math.min(Tray.count, Settings.pillTrayMax) : Tray.count

    // Settings-aware first-frame estimate. Count only blocks that currently
    // render, including only the gaps between them. The view's exact natural
    // width takes over as soon as it is laid out.
    readonly property int estimado: {
        let w = 0
        let count = 0
        if (Extensions.leftWidth > 28) {
            w += Extensions.leftWidth - 8
            count++
        }
        if (Settings.pillItemEnabled("media") && Media.isPlaying) {
            w += 53
            count++
        }
        if (Settings.pillItemEnabled("clock-workspaces")) {
            w += centroAncho
            count++
        }
        if (Settings.pillItemEnabled("minimized") && Modulos.count > 0) {
            const shownMinis = Settings.pillMinimizedMax > 0
                ? Math.min(Modulos.count, Settings.pillMinimizedMax)
                : Modulos.count
            w += shownMinis * 116 + (Modulos.count > shownMinis ? 30 : 0)
            count++
        }
        if (Settings.pillItemEnabled("plugin-indicators")
                && Indicadores.anchoAproximado > 0) {
            w += Indicadores.anchoAproximado
            count++
        }
        if (Settings.pillItemEnabled("tray") && Tray.count > 0) {
            w += trayShown * 18 + (Tray.count > trayShown ? 18 : 0)
            count++
        }
        if (Extensions.rightWidth > 28) {
            w += Extensions.rightWidth - 8
            count++
        }
        return w + Math.max(0, count - 1) * 11
    }

    property int contenidoMedido: 0
    // Workspace parade room, handed out and taken back like before.
    property int centroAncho: 46

    // A pill with everything hidden is still a clickable target for
    // background taps that open the control centre.
    readonly property int islandWidth: {
        const contenido = contenidoMedido > 0 ? contenidoMedido : estimado
        return Math.max(44, contenido + 22)
    }
    readonly property int islandHeight: Theme.baseHeight

    property bool closeOnClickOutside: false
    property bool grabKeyboard: false
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 0

    property bool handlesBackgroundTap: false

    property var barraApartada
    property var reservaBarra

    property Component view: Component {
        IdleIslandView { plugin: self }
    }

    function close() {}
}
