pragma Singleton

//  Default sink volume, updated through PipeWire signals.
//
//  This used to poll `wpctl get-volume` every 350 ms: about ten thousand
//  launches per hour, indefinitely, whether volume was being used or not.
//  Quickshell talks to PipeWire directly and notifies us: external changes
//  from media keys or a mixer emit a signal, update state and raise
//  `overlayOpen` as before, without launching a process.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: audio

    //  A PipeWire node only publishes properties while someone tracks it.
    //  This tracker provides that subscription.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property var _sink: Pipewire.defaultAudioSink

    property int volume: 0
    property bool muted: false
    property bool initialized: false
    property bool overlayOpen: false

    //  Use signals rather than a direct binding to distinguish the initial
    //  value from a change and avoid opening the overlay at startup.
    property var _vigila: Connections {
        target: audio._sink ? audio._sink.audio : null
        function onVolumesChanged() { audio._sincronizar() }
        function onMutedChanged() { audio._sincronizar() }
    }

    on_SinkChanged: _sincronizar()

    function _sincronizar() {
        if (!_sink || !_sink.audio)
            return
        const nuevoVolumen = Math.round(_sink.audio.volume * 100)
        const nuevoSilencio = _sink.audio.muted
        const cambio = initialized
            && (nuevoVolumen !== volume || nuevoSilencio !== muted)

        volume = nuevoVolumen
        muted = nuevoSilencio
        initialized = true

        if (cambio)
            showOverlay()
    }

    function showOverlay() {
        overlayOpen = true
        overlayTimer.restart()
    }

    function setVolume(percent) {
        const bounded = Math.max(0, Math.min(100, Math.round(percent)))
        if (_sink && _sink.audio) {
            _sink.audio.volume = bounded / 100
            _sink.audio.muted = false
        }
        //  Local feedback keeps the slider smooth; the signal confirms it.
        volume = bounded
        muted = false
        showOverlay()
    }

    function toggleMute() {
        if (_sink && _sink.audio)
            _sink.audio.muted = !_sink.audio.muted
        showOverlay()
    }

    Timer {
        id: overlayTimer
        interval: 1600
        onTriggered: audio.overlayOpen = false
    }

    //  ── devices: what is connected and where sound goes ──────────
    //
    //  Previously this service only adjusted the master volume. Selecting
    //  audio outputs or inputs and setting their gain required pavucontrol,
    //  leaving the shell for controls the shell should provide itself.
    //
    //  All through PipeWire without launching processes: nodes arrive by
    //  signal, and changing the default is a property assignment.
    readonly property var todos: Pipewire.nodes ? Pipewire.nodes.values : []

    //  Real devices, excluding application streams — Firefox uses an output
    //  rather than being one — and internal PipeWire nodes. Dummy-Driver,
    //  Freewheel-Driver, Midi-Bridge and BLE MIDI used to appear as if they
    //  were microphones. Real devices have `device.api` pointing to ALSA or
    //  BlueZ, unlike synthetic nodes, but filtering uses the NAME rather
    //  than those properties.
    //
    //  Node properties start empty and arrive later when the tracker can
    //  publish them. Filtering by properties left the list blank when the
    //  panel opened and filled it half a second later. Names are available
    //  from the start.
    //
    //  Keep sound-card (`alsa_`) and Bluetooth devices. Exclude internal
    //  PipeWire nodes — Dummy-Driver, Freewheel-Driver, Midi-Bridge and BLE
    //  MIDI — which previously appeared in the microphone list.
    function esAparato(n) {
        if (!n || n.isStream)
            return false
        const nombre = String(n.name || "")
        if (nombre.indexOf("alsa_") === 0)
            return true
        return nombre.indexOf("bluez_") === 0 && nombre.indexOf("midi") < 0
    }

    readonly property var salidas: todos.filter(function (n) {
        return audio.esAparato(n) && n.isSink
    })

    readonly property var entradas: todos.filter(function (n) {
        return audio.esAparato(n) && !n.isSink
    })

    //  Track them all: a PipeWire node publishes neither volume nor name
    //  properties while nobody is watching it.
    property PwObjectTracker _rastro: PwObjectTracker {
        objects: audio.salidas.concat(audio.entradas)
    }

    readonly property var salidaActiva: Pipewire.defaultAudioSink
    readonly property var entradaActiva: Pipewire.defaultAudioSource

    function nombreDe(nodo) {
        if (!nodo)
            return ""
        return String(nodo.description || nodo.nickname || nodo.name || "")
    }

    function elegirSalida(nodo) {
        if (nodo)
            Pipewire.preferredDefaultAudioSink = nodo
    }

    function elegirEntrada(nodo) {
        if (nodo)
            Pipewire.preferredDefaultAudioSource = nodo
    }

    //  ONE device's volume, not the system volume. Up to 150%: above 100%
    //  is software gain, useful for a quiet microphone but liable to clip
    //  one whose level was already sufficient.
    function volumenDe(nodo) {
        return nodo && nodo.audio ? Math.round(nodo.audio.volume * 100) : 0
    }

    function ponerVolumenDe(nodo, pct) {
        if (!nodo || !nodo.audio)
            return
        nodo.audio.volume = Math.max(0, Math.min(150, Math.round(pct))) / 100
    }

    function mudoDe(nodo) {
        return !!(nodo && nodo.audio && nodo.audio.muted)
    }

    function alternarMudoDe(nodo) {
        if (nodo && nodo.audio)
            nodo.audio.muted = !nodo.audio.muted
    }

    //  ── each device's unity-gain level ────────────────────────────
    //
    //  Base volume is the device's natural level, without amplification or
    //  attenuation. A USB microphone with a 56% base adds +15 dB at 100%,
    //  clipping its input without warning. This happened in practice and
    //  is why the level is shown.
    //
    //  PipeWire does not publish it here: ask pactl once, only when the
    //  panel opens.
    property var bases: ({})

    //  Decibels ABOVE the device's natural level. This is the meaningful
    //  number: the mixer's percentage is arbitrary, and +44% conveys much
    //  less than +15 dB.
    //
    //  PulseAudio uses a cubic curve: 60·log10(v). Checked against pactl's
    //  own values — 56% gives approximately -15 dB — rather than relying
    //  on a guessed formula.
    function dbSobreNatural(nodo) {
        const base = baseDe(nodo)
        const v = volumenDe(nodo)
        if (base <= 0 || v <= 0)
            return 0
        return 60 * Math.log(v / base) / Math.LN10
    }

    function baseDe(nodo) {
        const b = bases[nombreDe(nodo)]
        return b === undefined ? 0 : b
    }

    function mirarBases() { lector.running = true }

    Process {
        id: lector
        //  Two calls, not one: `pactl list` accepts ONE type. Asking for
        //  `sources sinks` silently uses only the first, omitting half the
        //  base volumes and their markers in the list.
        command: ["sh", "-c",
            "{ pactl list sources; pactl list sinks; } | "
            + "grep -E '^[[:space:]]*(Description|Base Volume):'"]
        stdout: StdioCollector {
            onStreamFinished: {
                //  Read pairs: description followed by base volume, as
                //  pactl prints them, without parsing the entire block.
                const nuevo = ({})
                let quien = ""
                const lineas = this.text.split("\n")
                for (let i = 0; i < lineas.length; ++i) {
                    const l = lineas[i].trim()
                    if (l.indexOf("Description:") === 0) {
                        quien = l.slice(12).trim()
                    } else if (l.indexOf("Base Volume:") === 0 && quien) {
                        const m = l.match(/(\d+)%/)
                        if (m)
                            nuevo[quien] = parseInt(m[1], 10)
                        quien = ""
                    }
                }
                audio.bases = nuevo
            }
        }
    }
}
