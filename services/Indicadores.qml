pragma Singleton

// Small indicators shown in the folded pill.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: indicadores

    // [{ id, texto, glifo, color, orden, visible, slots }]
    property var lista: []
    signal invocado(string id)

    //  How wide a name may grow before it is clipped.
    readonly property int topeTexto: 160

    // The renderer uses these exact fonts and measurements. Slot widths depend
    // on declared samples, never on the live value, including before views load.
    FontMetrics {
        id: numericMetrics
        font.family: Theme.uiFont
        font.pixelSize: 11
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }
    FontMetrics {
        id: iconMetrics
        font.family: Theme.iconFont
        font.pixelSize: Settings.pillIndicatorIconSize
    }
    FontMetrics {
        id: textMetrics
        font.family: Theme.uiFont
        font.pixelSize: 11
        font.weight: Font.Medium
    }
    readonly property font iconFont: iconMetrics.font
    readonly property font textFont: textMetrics.font
    readonly property font numericFont: numericMetrics.font
    readonly property int slotGap: 3
    property var _iconWidths: Object.create(null)
    property var _textWidths: Object.create(null)
    property var _numericWidths: Object.create(null)
    onIconFontChanged: _iconWidths = Object.create(null)
    onTextFontChanged: _textWidths = Object.create(null)
    onNumericFontChanged: _numericWidths = Object.create(null)

    function numericWidth(text) {
        // FontMetrics method calls alone do not track font changes in QML
        // bindings. Replacing this cache invalidates every dependent width.
        if (_numericWidths[text] === undefined)
            _numericWidths[text] = numericMetrics.advanceWidth(text)
        return _numericWidths[text]
    }

    function hasSlots(ind) {
        // Repeater exposes nested arrays as QML sequences, not JS Arrays.
        return !!ind.slots && ind.slots.length > 0
    }
    function slotWidth(slot) {
        let width = numericWidth("—")
        const samples = slot.samples || []
        for (const sample of samples) {
            // Some user-selected fonts lack tabular figures. Reserve their
            // widest digit too, rather than assuming that '0' is widest.
            for (let digit = 0; digit <= 9; ++digit)
                width = Math.max(width, numericWidth(
                    String(sample).replace(/[0-9]/g, String(digit))))
        }
        return Math.ceil(width)
    }
    function prefixWidth(slot) {
        return Math.ceil(numericWidth(String(slot.prefix || "")))
    }
    function slotsWidth(ind) {
        let width = Math.max(0, ind.slots.length - 1) * slotGap
        for (const slot of ind.slots)
            width += prefixWidth(slot) + slotWidth(slot)
        return width
    }
    function iconWidth(ind) {
        if (_iconWidths[ind.glifo] === undefined)
            _iconWidths[ind.glifo] = Math.ceil(iconMetrics.advanceWidth(String.fromCodePoint(ind.glifo)))
        return _iconWidths[ind.glifo]
    }
    function textWidth(text) {
        if (_textWidths[text] === undefined)
            _textWidths[text] = Math.min(topeTexto, Math.ceil(textMetrics.advanceWidth(text)))
        return _textWidths[text]
    }

    // Shared with the renderer, including ordinary indicators such as agents.
    // Only the glyph changes size; text keeps its own measured reservation.
    function anchoDe(ind) {
        return iconWidth(ind) + 4
            + (hasSlots(ind) ? slotsWidth(ind) : textWidth(String(ind.texto || ""))) + 6
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

    // Reserve the same measured width even before a view has been created.
    readonly property int anchoAproximado: {
        const muestra = reparto.muestra
        let ancho = 0
        for (let i = 0; i < muestra.length; ++i)
            ancho += anchoDe(muestra[i]) + (i > 0 ? 8 : 0)
        if (reparto.ocultos > 0)
            ancho += anchoResumen + (muestra.length > 0 ? 8 : 0)
        return ancho
    }

    function registrar(id, texto, glifo, color, orden, visible, slots) {
        if (!id || String(id).length === 0)
            return
        const nuevo = { id: String(id), texto: String(texto || ""),
                        glifo: Number(glifo) || 0, color: color || Theme.muted,
                        orden: Number(orden) || 0,
                        visible: visible !== false,
                        slots: Array.isArray(slots) ? slots : [] }
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
