//  A sound: a click, a notification or a game-over cue.
//
//  Two backends are selected automatically; neither suits every format:
//
//  - **WAV → SoundEffect.** Loads the file into memory on startup and plays
//    it without loading latency. Game effects need the sound WITH the impact,
//    not a quarter of a second afterward.
//  - **Other formats → MediaPlayer.** SoundEffect only accepts uncompressed
//    WAV. An unsupported file leaves it at `status: Error` without playback.
//    Desktop sounds exposed this with their .oga files: the bell stayed
//    silent. Those now use MediaPlayer, which opens the file on playback,
//    adding a little delay but actually producing sound.
//
//  This is not intended for music or long recordings. A plugin playing
//  music is a media player; MPRIS and K4.Medios are the relevant interfaces.
//
//  Requires the `sonido` permission: producing sound on someone's desktop
//  is a side effect, and side effects must be declared.
//
//      K4.Sonido { id: campana; fuente: campana.delSistema("bell") }
//      // …
//      campana.sonar()
//
//  Note the instance call: the former `K4.Sonido.delSistema("bell")` example
//  did NOT work. `delSistema` is an instance method, not a type method.
//  Calling it on `K4.Sonido` reports "Property 'delSistema' of object Sonido
//  is not a function". Because the error occurs in a binding, loading can
//  continue with no sound. It went unnoticed until the first shell module
//  to use this component copied the example and encountered the failure.

import QtQuick
import QtMultimedia

QtObject {
    id: sonido

    //  A file: an absolute file:// URL, or a path relative to your directory
    //  resolved with Qt.resolvedUrl.
    property string fuente: ""

    //  From 0 to 1. This does not change system volume: users can lower
    //  their own volume if they want less sound.
    property real volumen: 0.5

    readonly property bool _esWav: fuente.toLowerCase().indexOf(".wav") ===
                                   fuente.length - 4 && fuente.length >= 4

    //  Ready to play: check this when playback is unexpectedly silent.
    //  The backends expose failure differently:
    //
    //  - WAV reports its status on loading, so wait for `Ready`.
    //  - Other formats only discover failures when opening the file, so
    //    inspect `error`. Deliberately do NOT wait for `LoadedMedia`: some
    //    backends defer loading until playback is requested. Waiting for
    //    loading would leave this false forever, an even less useful result.
    //
    //  Previously, any non-WAV source was considered ready merely because
    //  the property was set. Even a missing .oga file left `listo` true,
    //  hiding the failure from callers using it as a guard.
    readonly property bool listo: fuente.length > 0
        && (_esWav ? _efecto.status === SoundEffect.Ready
                   : _repro.error === MediaPlayer.NoError)

    property SoundEffect _efecto: SoundEffect {
        source: sonido._esWav ? sonido.fuente : ""
        volume: sonido.volumen
    }

    property MediaPlayer _repro: MediaPlayer {
        source: sonido._esWav ? "" : sonido.fuente
        audioOutput: AudioOutput { volume: sonido.volumen }
    }

    function sonar() {
        if (fuente.length === 0)
            return
        if (_esWav) {
            _efecto.play()
        } else {
            //  Start from the beginning: otherwise the next play resumes
            //  at the old position, leaving a half-second effect silent.
            _repro.position = 0
            _repro.play()
        }
    }

    //  The freedesktop sound theme — the standard location every distro
    //  installs to, so these need nothing shipped.
    readonly property string _dirSistema:
        "/usr/share/sounds/freedesktop/stereo/"

    //  Desktop sounds, already installed and in the same voice as the rest
    //  of the system: "bell", "message", "complete", "dialog-error"…
    function delSistema(nombre) {
        return "file://" + _dirSistema + nombre + ".oga"
    }
}
