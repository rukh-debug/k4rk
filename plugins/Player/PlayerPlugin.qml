//  Player: cover art, track, draggable timeline and transport. Activates on
//  hover when something is playing — beating the clock — and peeks for a few
//  seconds whenever the track changes.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "player"
    title: "Player"
    priority: 55

    //  No outside-click catcher for this one. It only ever appears by
    //  HOVER or by the track-change peek — uninvited — so an outside tap
    //  is not "close what I opened": the tap belongs to whatever it was
    //  aimed at, and the view already leaves when the pointer does.
    //  Same call as the volume HUD. See `closeOnClickOutside` in the
    //  plugin contract.
    closeOnClickOutside: false


    //  On hover — as always — and also for the duration of the peek.
    //
    //  The peek does NOT ask for `isPlaying`: on a track change some players
    //  pass through "stopped" for an instant, and with the condition shared
    //  the peek died in that flicker right as it started.
    active: habilitado
        && ((Island.hovered && Media.isPlaying) || asomando)

    //  ── peeking when the track changes ───────────────────────────
    //
    //  Before, it only came out on hover, so it was the one thing in the
    //  system with no way to claim the island on its own: with the bar
    //  hidden, nobody learned about a new song. The notification and the
    //  volume HUD already come out on their own; this was missing.
    //
    //  The track is identified by what is READ — title and artist — and not
    //  by `xesam:trackid`: some players never publish it, and browsers
    //  change it without the song changing.
    property bool asomarAlCambiar: true
    property bool asomando: false

    readonly property string pista:
        Media.hasPlayer && String(Media.activePlayer.trackTitle || "").length > 0
            ? String(Media.activePlayer.trackTitle) + " · "
              + String(Media.activePlayer.trackArtist || "")
            : ""

    property string pistaPrevia: ""

    //  And it is left to SETTLE before comparing, and this is no small
    //  detail: MPRIS metadata arrives IN PIECES. Measured with a test
    //  player: the title shows up first and the artist an instant later,
    //  so the string changes TWICE for a single track — and the second
    //  time there was already a non-empty previous one, so it looked like
    //  a track change. It peeked on the session's first song, which is
    //  exactly what the guard below exists to prevent.
    onPistaChanged: posarTimer.restart()

    Timer {
        id: posarTimer
        interval: 350
        onTriggered: {
            const antes = self.pistaPrevia
            self.pistaPrevia = self.pista
            if (!self.asomarAlCambiar || !self.habilitado)
                return
            //  BOTH are needed: that there is a new one, and that there was
            //  one before. When the bar starts with music already playing,
            //  what arrives is not a track change but the discovery that
            //  there was one, and peeking there would mean greeting every
            //  login. Same when the player closes.
            if (self.pista.length === 0 || antes.length === 0
                    || antes === self.pista)
                return
            self.asomando = true
            asomoTimer.restart()
        }
    }

    //  Just long enough to read title and artist and get back to your thing.
    Timer {
        id: asomoTimer
        interval: 3200
        onTriggered: self.asomando = false
    }

    //  And ESC takes it away, like anything else occupying the island. With
    //  the mouse on top it closes nothing — hover rules there: same behavior
    //  as always.
    function close() { self.asomando = false }

    K4.Ajustes {
        plugin: "player"
        grupo: "Player"
        opciones: [
            { id: "peekOnChange",
              nombre: "Peek when the track changes",
              desc: "A few seconds with the new track, then it leaves on its own",
              glifo: 0xF075A }   // md-music
        ]
        valores: ({ peekOnChange: self.asomarAlCambiar })
        onCambiado: function (id, valor) {
            if (id !== "peekOnChange")
                return
            self.asomarAlCambiar = valor === true
            guardado.guardar({ peekOnChange: self.asomarAlCambiar })
        }
    }

    property var guardado: K4.Guardado {
        plugin: "player"
        onCargado: function (d) {
            //  The key is English now; the Spanish one is the pre-rename
            //  file saying something — both are honored, new wins.
            if (d && d.peekOnChange !== undefined)
                self.asomarAlCambiar = d.peekOnChange === true
            else if (d && d.asomarAlCambiar !== undefined)
                self.asomarAlCambiar = d.asomarAlCambiar === true
        }
    }

    // the control center and the tray; the host injects them
    property var panel: null
    property var tray: null

    //  The plugin chips count too: without them in the sum, an agent bell
    //  pushed the right-hand group over the song title. Same problem the
    //  clock had — the long explanation lives there.
    //  Peeking: just enough for a title — pill height and a bit wider than
    //  the pill. Nothing else is painted, so asking for more would leave a
    //  gap.
    islandWidth: asomando ? 300
        : 340 + (Tray.count > 0 ? Math.min(Tray.count, 4) * 24 + 8 : 0)
        + Indicadores.anchoAproximado
    // grows to make room for the recent notifications
    //  The base already carries its 14 px margins top and bottom. The strip
    //  adds what it measures plus the 13 of the layout spacing and the 2 of
    //  its own topMargin.
    readonly property int alturaTira: Settings.notificationsOnHover
        ? Notifs.stripHeight(3) : 0
    //  Peeking, only the track row: 44 px of cover art plus its two 14 px
    //  margins. The rest — timeline, transport, notifications — is hidden by
    //  the view, so asking for more would leave a black gap.
    //
    //  This exists because the full-height peek was unbearable: a silly
    //  thirty-second video opened half the island, and again on every track
    //  change. Learning what is playing does not need the whole remote.
    islandHeight: asomando ? Theme.baseHeight
        : (Media.hasTimeline ? 140 : 115)
          + (alturaTira > 0 ? alturaTira + 15 : 0)

    view: Component {
        PlayerView {
            panel: self.panel; tray: self.tray
            //  Without this the view cannot tell it is a peek and comes out
            //  in full.
            plugin: self
        }
    }

    //  And if you come close, it stops being a peek: it deploys in full and
    //  stays while the mouse is on top — which is what passing over the pill
    //  already did. Coming close is asking for it.
    Connections {
        target: Island
        function onHoveredChanged() {
            if (Island.hovered && self.asomando)
                self.asomando = false
        }
    }
}
