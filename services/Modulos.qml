pragma Singleton

//  Modules set aside to resume later.
//
//  Closing does not always mean discarding. Losing an AI conversation on
//  close forces users to keep it open, occupying the island while they do
//  something else. Register minimized modules here so the pill can show
//  them and restore them with a click.
//
//  State does NOT live here: each module keeps its own. This is only the
//  list of modules waiting to be resumed.

import QtQuick
import Quickshell

Singleton {
    id: modulos

    // [{ id, titulo, detalle, glifo }]
    property var lista: []

    readonly property int count: lista.length

    // The registered owner listens and restores itself.
    signal restaurado(string id)

    function minimizar(id, titulo, detalle, glifo) {
        const sin = lista.filter(function (m) { return m.id !== id })
        // Reassign the whole array: mutating it in place emits no change,
        // which would leave the pill unchanged.
        lista = sin.concat([{ id: id, titulo: titulo,
                              detalle: detalle || "", glifo: glifo || 0 }])
    }

    function actualizar(id, detalle) {
        lista = lista.map(function (m) {
            if (m.id !== id)
                return m
            const d = Object.assign({}, m)
            d.detalle = detalle
            return d
        })
    }

    function restaurar(id) {
        quitar(id)
        restaurado(id)
    }

    function quitar(id) {
        lista = lista.filter(function (m) { return m.id !== id })
    }
}
