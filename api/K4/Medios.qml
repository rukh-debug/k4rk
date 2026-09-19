pragma Singleton

//  Current playback, regardless of its source (MPRIS).
//
//  Reading is unrestricted: lyrics, scrobblers and now-playing indicators
//  only observe. Controls such as pausing, skipping and seeking require the
//  `medios` permission: stopping someone's music without notice is intrusive.
//
//  `posicion` updates only while someone watches it: call `seguirPosicion()`
//  when mounting the view and `dejarPosicion()` when releasing it. Otherwise
//  the timer stays stopped, saving battery for a progress bar nobody sees.

import QtQuick

QtObject {
    readonly property var _m: Puente.medios
    readonly property var _p: _m ? _m.activePlayer : null

    readonly property bool hay: _m ? _m.hasPlayer : false
    readonly property bool sonando: _m ? _m.isPlaying : false

    readonly property string titulo: _p ? (_p.trackTitle || "") : ""
    readonly property string artista: _p ? (_p.trackArtist || "") : ""
    readonly property string album: _p ? (_p.trackAlbum || "") : ""
    readonly property string aplicacion: _p ? (_p.identity || "") : ""

    //  Artwork, already resolved to a source that Image can load.
    readonly property string caratula: (_m && _p) ? (_m.coverFor(_p) || "") : ""

    readonly property real posicion: _p ? (_p.position || 0) : 0
    readonly property real duracion: _p ? (_p.length || 0) : 0
    readonly property bool hayLinea: _m ? _m.hasTimeline : false

    //  Format seconds as "3:07", using the shell's own time format.
    function comoTiempo(segundos) {
        return _m ? _m.formatTime(segundos) : "0:00"
    }

    function seguirPosicion() { if (_m) _m.watchPosition() }
    function dejarPosicion() { if (_m) _m.unwatchPosition() }

    //  ── require the `medios` permission ───────────────────────────
    function alternarPausa() { if (_m) _m.togglePlaying() }
    function siguiente() { if (_m) _m.siguiente() }
    function anterior() { if (_m) _m.anterior() }
    function buscar(fraccion) { if (_m) _m.seekTo(fraccion) }
}
