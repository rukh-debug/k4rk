pragma Singleton

//  The shell's palette and fonts, available to external plugins.
//
//  Reads the SAME theme object through Puente rather than keeping a copy:
//  external plugins follow host theme changes automatically. Fallbacks let
//  the API load independently in tests; with a host theme they are unused.
//
//      Rectangle { color: K4.Tema.superficie }
//      Text { color: K4.Tema.tinta; font.family: K4.Tema.fuente }

import QtQuick

QtObject {
    readonly property var _t: Puente.tema

    //  Colors, exposed under the current API names.
    readonly property color fondo: _t ? _t.islandBg : "#000000"
    readonly property color tinta: _t ? _t.ink : "#ffffff"
    readonly property color apagado: _t ? _t.muted : "#8e8e93"
    readonly property color tenue: _t ? _t.dim : "#48484a"
    readonly property color superficie: _t ? _t.surface : "#1c1c1e"
    readonly property color superficieAlta: _t ? _t.surfaceHi : "#2c2c2e"
    readonly property color carril: _t ? _t.track : "#3a3a3c"
    readonly property color verde: _t ? _t.green : "#30d158"
    readonly property color rojo: _t ? _t.red : "#ff453a"
    readonly property color azul: _t ? _t.blue : "#0a84ff"
    readonly property color amarillo: _t ? _t.yellow : "#ffd60a"

    //  Fonts.
    readonly property string fuente: _t ? _t.uiFont : "Adwaita Sans"
    readonly property string fuenteIconos: _t ? _t.iconFont
                                              : "MesloLGS Nerd Font"

    //  Geometry that plugins may need to respect.
    readonly property int altoPlegado: _t ? _t.baseHeight : 34
    readonly property int altoMaximo: _t ? _t.maxIslandHeight : 880

    // ── tint ──────────────────────────────────────────────────────
    //
    //  Temporarily tint the shell's neutral colors: the island, surfaces
    //  and tracks. Everything using the theme follows automatically. Text
    //  and semantic colors stay unchanged, the host clamps the strength,
    //  and disabling the owning plugin clears its tint.
    //
    //      K4.Tema.tintar("mi-juego", "#2e5c3a", 0.3, 4000)   // 4 s
    //      K4.Tema.tintar("mi-juego", "#5c2e2e", 0.35, 0)     // until...
    //      K4.Tema.destintar("mi-juego")                       // ...this call
    //
    //  Last call wins. `fuerza`: 0..0.45; `duracionMs`: 0 means no timeout.
    readonly property string tinteDueno: _t ? _t.tinteDueno : ""
    readonly property color tinteColor: _t ? _t.tinteColor : "transparent"

    function tintar(dueno, color, fuerza, duracionMs) {
        if (_t)
            _t.tintar(dueno, color, fuerza, duracionMs || 0)
    }

    function destintar(dueno) {
        if (_t)
            _t.destintar(dueno)
    }
}
