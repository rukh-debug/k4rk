pragma Singleton

// Native media player: hover while playing plus the track-change peek.
//
// Hover beats the clock at 55; the peek claims the island on its own for
// 3.2 seconds after a settled metadata change. The peek never asks for
// isPlaying: some players flicker through stopped on track change.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: self

    readonly property string name: "player"
    readonly property string title: "Player"
    readonly property int priority: 55
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: ((Island.hovered && Media.isPlaying) || asomando)

    property bool closeOnClickOutside: false

    property bool asomando: false

    readonly property bool asomarAlCambiar: Settings.playerPeekOnChange

    readonly property string pista:
        Media.hasPlayer && String(Media.activePlayer.trackTitle || "").length > 0
            ? String(Media.activePlayer.trackTitle) + " · "
              + String(Media.activePlayer.trackArtist || "")
            : ""

    property string pistaPrevia: ""

    onPistaChanged: posarTimer.restart()

    Timer {
        id: posarTimer
        interval: 350
        onTriggered: {
            const antes = self.pistaPrevia
            self.pistaPrevia = self.pista
            if (!self.asomarAlCambiar)
                return
            if (self.pista.length === 0 || antes.length === 0
                    || antes === self.pista)
                return
            self.asomando = true
            asomoTimer.restart()
        }
    }

    Timer {
        id: asomoTimer
        interval: 3200
        onTriggered: self.asomando = false
    }

    function close() { self.asomando = false }

    // The control centre; SurfaceRegistry injects it like PluginManager did.
    property var panel: null

    readonly property int islandWidth: {
        if (asomando)
            return 300
        const trayShown = Settings.pillTrayMax > 0
            ? Math.min(Tray.count, Settings.pillTrayMax) : Tray.count
        return 340 + (Tray.count > 0 ? trayShown * 24 + 8 : 0)
            + Indicadores.anchoAproximado
    }
    readonly property int alturaTira: Settings.notificationsOnHover
        ? Notifs.stripHeight(3) : 0
    readonly property int islandHeight: asomando ? Theme.baseHeight
        : (Media.hasTimeline ? 140 : 115)
          + (alturaTira > 0 ? alturaTira + 15 : 0)

    property bool viewLoaded: true
    readonly property bool colocable: false
    readonly property string summonCommand: ""
    readonly property bool transitorio: false
    property bool grabKeyboard: false
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 0
    property bool handlesBackgroundTap: false

    property var barraApartada
    property var reservaBarra

    property Component view: Component {
        PlayerIslandView {
            panel: self.panel
            plugin: self
        }
    }

    Connections {
        target: Island
        function onHoveredChanged() {
            if (Island.hovered && self.asomando)
                self.asomando = false
        }
    }
}
