pragma Singleton

//  Island state: whether it is open, who occupies it and how much room exists.
//
//  Ownership is deliberately read-only. The host arbitrates using plugin
//  priorities so two plugins cannot fight over the display. Request it with
//  `active` on your K4.Plugin and observe the result here. Avoid work nobody
//  can see: when your plugin does not own the island, stop its animations,
//  polling and rendering.

import QtQuick

QtObject {
    readonly property var _i: Puente.isla

    readonly property bool abierta: _i ? _i.abierta : false

    //  Is the island visible RIGHT NOW?
    //
    //  This differs from `abierta`: the folded pill is visible too. False
    //  when the island is retracted in Settings' hidden mode, when a system
    //  dialog moves it aside, or when its monitor's bar is not showing.
    //
    //  Qt Quick does NOT stop an animation merely because its item becomes
    //  invisible, so indefinite animations must check this state. See
    //  docs/PLUGINS.md.
    //
    //  Without a host, such as a `--test` run, default to true: an extra
    //  animation is less disruptive than one that never starts.
    readonly property bool aLaVista: _i ? _i.aLaVista : true
    //  Pointer over the pill: the shell opens its hover view automatically.
    readonly property bool raton: _i ? _i.hovered : false
    //  The current owner's `name`, or "" when nobody owns it.
    readonly property string ocupadaPor: _i ? (_i.ocupante || "") : ""

    //  Maximum requestable height, to avoid declaring an impossible size.
    readonly property int altoMaximo: Tema.altoMaximo

    //  The bar's edge: "arriba" or "abajo", chosen by the user in Settings.
    //  Read it to orient content drawn outside the island.
    readonly property string posicion: _i ? (_i.posicion || "arriba") : "arriba"

    //  Island bounds in screen coordinates: { x, y, ancho, alto }.
    //
    //  Anchor a K4.Ventana precisely when drawing OUTSIDE the island, such as
    //  a hand reaching over its edge or something falling from the bar.
    //  `rect` describes the primary screen; `rectEn(nombre)` supplies the
    //  bounds for each monitor. K4.Ventana selects its monitor with `pantalla`.
    readonly property var rect: (_i && _i.rect) ? _i.rect
        : ({ x: 0, y: 0, ancho: 0, alto: 0 })

    //  The screen hosting the open view NOW, named as in `hyprctl monitors`.
    //  The pill exists on every screen, but an open view belongs to one.
    //
    //  Pass this to K4.Ventana's `pantalla` to attach to the correct island.
    //  Previously external views could only read the PRIMARY screen's `rect`,
    //  anchoring their content to the wrong island on multi-monitor setups.
    //  Since coordinates are local to each monitor, the result could appear
    //  elsewhere or disappear entirely rather than merely look misaligned.
    readonly property string pantalla: _i ? (_i.pantallaActiva || "") : ""

    function rectEn(pantalla) {
        const d = _i ? _i.rects : null
        return (d && d[pantalla]) ? d[pantalla] : rect
    }

    //  Position along the bar's edge, as a fraction of the free width:
    //  0 at the left, 0.5 centered, 1 at the right. Settings owns the base
    //  position; this reports the currently effective value.
    readonly property real colocacion: _i ? _i.colocacion : 0.5

    //  Animate a TEMPORARY move along the edge:
    //
    //      K4.Isla.colocar("mi-juego", 0.3, 3000)   // to 30%, for 3 seconds
    //      K4.Isla.colocar("mi-juego", 0.92, 0)     // near the corner, until...
    //      K4.Isla.soltar("mi-juego")               // ...this call
    //
    //  Returns to the user's base position on timeout, release or plugin
    //  disable. Use for a scene in which the island dodges, acts as a paddle
    //  or moves aside, not for permanent placement: that belongs to the user
    //  and is chosen in Settings.
    function colocar(dueno, fraccion, duracionMs) {
        if (_i && _i.colocar)
            _i.colocar(dueno, fraccion, duracionMs || 0)
    }

    function soltar(dueno) {
        if (_i && _i.soltar)
            _i.soltar(dueno)
    }

    //  Treat the island as a physical object: request a gesture for the host
    //  to animate.
    //
    //      K4.Isla.efecto("mi-juego", "sacudida")        // an impact
    //      K4.Isla.efecto("mi-juego", "empujon", 0.6)    // a heavy object falls
    //      K4.Isla.efecto("mi-juego", "tiron")           // a fish bites
    //
    //  Names: "sacudida", "empujon", "tiron". `fuerza` ranges from 0.2 to 1,
    //  defaulting to 1. The host limits requests to one gesture per half
    //  second. These effects stand out because the shell is otherwise quiet:
    //  request them at meaningful moments and leave time between them.
    function efecto(dueno, nombre, fuerza) {
        if (_i && _i.efecto)
            _i.efecto(dueno, nombre, fuerza)
    }
}
