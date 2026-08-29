pragma Singleton

//  Flank extensions of the pill: the capsule growing toward a screen
//  edge, carrying a plugin's name for what is going on.
//
//  This is the arbitration half of a public API. A plugin never touches
//  the pill's geometry — it declares an extension through `K4.Capsule`
//  and this service does the rest: it measures the text with the pill's
//  own font, caps the width at the plugin's maxLength AND at the room
//  left to the screen edge, and publishes what each side of the pill
//  gained in total. The idle view reserves that room, the host anchors
//  the island so the pill's body does not move, and
//  widgets/ExtensionZone.qml paints the zones.
//
//  Why a service and not the plugin's own math: the pill is ONE thing
//  and its contributors are many. Indicators already arbitrate like
//  this (K4.Pildora → Indicadores → PluginPildora) for the small chips
//  inside the pill; extensions are the same idea for the capsule's
//  flanks, where the width is not cosmetic — it moves the island.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: exts

    //  [{ id, lado, texto, glifo, color, maxLength, visible }]
    //
    //  `id` is the owning plugin's id: one extension per plugin, and a
    //  re-registration replaces. Registration order draws left to right
    //  within a side.
    property var lista: []

    //  The pill's own font, so "hug the text" hugs the text: the zone
    //  renders at 12 px Medium, and measuring at anything else elides
    //  names that fit — seen it, fixed it here.
    readonly property var metro: TextMetrics {
        font.family: Theme.uiFont
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    //  What an extension carries besides its text: the glyph, the gap
    //  between glyph and text, the row spacing that separates the zone
    //  from the pill's own content, and a little slack — hinting can
    //  render a hair wider than the advance, and a name that fits must
    //  never come out elided.
    readonly property int adornos: 14 + 6 + 8 + 4

    //  The hug, measured ONCE at registration — never inside a binding.
    //  Assigning `metro.text` while a binding evaluates is a loop: the
    //  write notifies, the advance re-reads, the binding runs again.
    //  registrar()/actualizar() are imperative calls from event handlers,
    //  so measuring there is safe; the bindings below only READ.
    function medir(texto) {
        metro.text = String(texto || "")
        return Math.ceil(metro.advanceWidth) + adornos
    }

    //  The width one extension takes: its hug, capped twice — by the
    //  plugin's maxLength and by the room to the screen edge. A pill
    //  parked at one end of the screen (barAlignment 15/85) has less
    //  room than the max on that side, and an extension running off
    //  the screen would be a lie. The ~220 accounts for half the pill
    //  body, the wings and a margin.
    function anchoDe(item) {
        const frac = item.lado === "left"
            ? Settings.barAlignment / 100
            : 1 - Settings.barAlignment / 100
        const room = Math.max(0, Math.round(Island.anchoPantalla * frac - 220))
        const max = Number(item.maxLength) > 0 ? Math.ceil(Number(item.maxLength)) : 300
        return Math.max(0, Math.min(Number(item.hug) || 0, max, room))
    }

    //  What each side gained in total. Bindings, not functions: the
    //  idle plugin reserves from these, and they must re-tell when the
    //  alignment changes or a monitor is rethought — the reads inside
    //  anchoDe() make the dependency for free.
    readonly property int leftWidth: suma("left")
    readonly property int rightWidth: suma("right")

    function suma(lado) {
        let total = 0
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].lado === lado && lista[i].visible !== false)
                total += anchoDe(lista[i])
        return total
    }

    function registrar(owner, campos) {
        if (!owner || String(owner).length === 0 || !campos)
            return
        const item = {
            id: String(owner),
            lado: campos.lado === "left" ? "left" : "right",
            texto: String(campos.texto || ""),
            glifo: Number(campos.glifo) || 0,
            color: campos.color !== undefined ? campos.color : null,
            maxLength: campos.maxLength,
            visible: campos.visible !== false,
            hug: medir(campos.texto)
        }
        lista = lista.filter(function (x) { return x.id !== item.id })
            .concat([item])
    }

    function actualizar(owner, campos) {
        lista = lista.map(function (x) {
            if (x.id !== String(owner))
                return x
            const d = Object.assign({}, x, campos)
            if (campos.texto !== undefined)
                d.hug = medir(campos.texto)
            return d
        })
    }

    function quitar(owner) {
        lista = lista.filter(function (x) { return x.id !== String(owner) })
    }
}
