pragma Singleton

//  Clipboard history.
//
//  Reading is NOT unrestricted here: the clipboard can contain passwords,
//  tokens and the last item copied from a password manager. Reading itself
//  is sensitive, so even observation requires `portapapeles` permission,
//  unlike audio or media where permissions govern changes.
//
//  The shell truncates preview text. For an entry's full content, `copiar(id)`
//  places it on the clipboard for whichever application receives the paste.

import QtQuick

QtObject {
    id: api

    readonly property var _p: Puente.portapapeles

    //  ── all of this requires the `portapapeles` permission ────────
    readonly property var entradas: _p ? _p.entradas : []
    readonly property int cuantas: _p ? _p.count : 0

    function titulo(entrada) { return _p ? _p.titulo(entrada) : "" }
    function filtrar(texto) { return _p ? _p.filtrar(texto) : [] }
    function copiar(id) { if (_p) _p.copiar(id) }

    signal cambio()

    property Connections _puente: Connections {
        target: api._p
        function onCambio() { api.cambio() }
    }
}
