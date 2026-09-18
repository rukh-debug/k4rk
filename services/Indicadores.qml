pragma Singleton

// Small indicators shown in the folded pill.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: indicadores

    // [{ id, texto, glifo, color, orden, visible }]
    property var lista: []
    signal invocado(string id)

    //  How wide a name may grow before it is clipped.
    readonly property int topeTexto: 160

    //  What one takes, roughly: the glyph and its gap, the text at 11 px —
    //  hence the ~7 per letter — and the 6 of padding.
    function anchoDe(ind) {
        return Math.min(topeTexto, String(ind.texto || "").length * 7) + 37
    }

    // And what the summary capsule takes, with its two digits.
    readonly property int anchoResumen: 34

    //  Which ones paint and how many stay out.
    //
    //  Decided here and not in the pill for two reasons: there are THREE pills
    //  —rest, clock and player— and all three must show the same, and whoever
    //  reserves the room is the plugin, which needs to know before any exists.
    //
    //  How many fit is a count, not a width budget: zero (the default) shows
    //  everything with no "+N"; a number caps it. The setting lives in
    //  Settings.pillIndicatorsMax so the user can set the limit.
    readonly property var reparto: {
        const vistos = []
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].visible !== false)
                vistos.push(lista[i])

        const limite = Number(Settings.pillIndicatorsMax) || 0
        if (limite > 0 && vistos.length > limite)
            return { muestra: vistos.slice(0, limite),
                     ocultos: vistos.length - limite }
        return { muestra: vistos, ocultos: 0 }
    }

    //  What they will take more or less, for whoever must reserve room BEFORE
    //  they exist. It is a floor, not a measure: the true width depends on
    //  the font and only whoever paints them knows —widgets/PluginPildora.qml—,
    //  so whoever can measure wins over this. It is here because the reserver
    //  is the clock plugin, and with the island closed there is no pill ready
    //  to ask.
    readonly property int anchoAproximado: {
        const muestra = reparto.muestra
        let ancho = 0
        for (let i = 0; i < muestra.length; ++i)
            ancho += anchoDe(muestra[i]) + (i > 0 ? 8 : 0)
        if (reparto.ocultos > 0)
            ancho += anchoResumen + (muestra.length > 0 ? 8 : 0)
        return ancho
    }

    function registrar(id, texto, glifo, color, orden, visible) {
        if (!id || String(id).length === 0)
            return
        const nuevo = { id: String(id), texto: String(texto || ""),
                        glifo: Number(glifo) || 0, color: color || Theme.muted,
                        orden: Number(orden) || 0,
                        visible: visible !== false }
        lista = lista.filter(function (x) { return x.id !== nuevo.id })
            .concat([nuevo]).sort(function (a, b) { return a.orden - b.orden })
    }

    function actualizar(id, campos) {
        lista = lista.map(function (x) {
            return x.id === id ? Object.assign({}, x, campos) : x
        })
    }

    function quitar(id) {
        lista = lista.filter(function (x) { return x.id !== id })
    }

    function quitarDe(owner) {
        const prefijo = String(owner) + "."
        lista = lista.filter(function (x) {
            return x.id.indexOf(prefijo) !== 0
        })
    }
}
