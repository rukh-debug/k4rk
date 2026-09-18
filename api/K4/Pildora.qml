pragma Singleton

// Public pill indicators, forwarded through the host bridge. Optional slots
// reserve space for changing numeric values without resizing the island.

import QtQuick

QtObject {
    id: api

    function registrar(id, texto, glifo, color, orden, visible, slots) {
        if (Puente.indicadores)
            Puente.indicadores.registrar(id, texto, glifo, color, orden, visible, slots)
    }
    function actualizar(id, campos) {
        if (Puente.indicadores)
            Puente.indicadores.actualizar(id, campos)
    }
    function quitar(id) {
        if (Puente.indicadores)
            Puente.indicadores.quitar(id)
    }
    function quitarDe(owner) {
        if (Puente.indicadores)
            Puente.indicadores.quitarDe(owner)
    }

    signal invocado(string id)

    property Connections conexion: Connections {
        target: Puente.indicadores
        function onInvocado(id) { api.invocado(id) }
    }
}
