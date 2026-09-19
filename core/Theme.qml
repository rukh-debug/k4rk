pragma Singleton

//  Island design tokens (macOS Dynamic Island / Atoll).
//  No host dependencies: this is the base of the import graph.

import QtQuick
import Quickshell

Singleton {
    id: tema

    //  The shell's typeface. The default is its own; `Settings` owns the
    //  choice and pushes it here (`shellFont`), because this file is the
    //  base of the import graph and depends on nothing — the value comes
    //  TO it, it does not go looking. Every label that binds `uiFont`
    //  follows the push, and the whole bar re-letters itself live.
    property string chosenFont: ""
    readonly property string uiFont: chosenFont.length > 0
        ? chosenFont : "Adwaita Sans"
    //  Deliberately use the Mono variant: Nerd Font 3.5's proportional build
    //  has several glyphs wider than their boxes. The Wi-Fi icon extended
    //  2px past the circle's right edge; Mono keeps each glyph in its cell.
    readonly property string iconFont: "MesloLGS Nerd Font Mono"
    readonly property var locale: Qt.locale("es_ES")

    //  Neutral surfaces derive from these bases and the tint below. Text,
    //  muted tones and semantic colors (green, red, blue, yellow) are not
    //  tinted: text must stay readable and warning red must remain red
    //  under every theme tint.
    readonly property color _islandBgBase: "#000000"
    readonly property color _surfaceBase: "#1c1c1e"
    readonly property color _surfaceHiBase: "#2c2c2e"
    readonly property color _trackBase: "#3a3a3c"

    readonly property color islandBg: _tinta(_islandBgBase)
    readonly property color ink: "#ffffff"
    readonly property color muted: "#8e8e93"
    readonly property color dim: "#48484a"
    readonly property color surface: _tinta(_surfaceBase)
    readonly property color surfaceHi: _tinta(_surfaceHiBase)
    readonly property color track: _tinta(_trackBase)
    readonly property color green: "#30d158"
    readonly property color red: "#ff453a"
    readonly property color blue: "#0a84ff"
    // For amplified audio. The system's dark-mode yellow, in the same
    // palette as the green and red above.
    readonly property color yellow: "#ffd60a"

    // ── tint ──────────────────────────────────────────────────────
    //
    //  Plugins may temporarily tint the shell: a game can recolor the island,
    //  surfaces and tracks, and everything using the theme follows reactively.
    //  The host sets limits: clamp the strength to retain the shell's visual
    //  identity, track the tint's owner, and clear it when that owner is
    //  disabled (PluginManager calls destintar during destruction).
    property string tinteDueno: ""
    property color tinteColor: "transparent"
    property real tinteFuerza: 0

    //  Ease in and out: a gradual change of atmosphere rather than a flash.
    Behavior on tinteFuerza { NumberAnimation { duration: 420 } }
    Behavior on tinteColor { ColorAnimation { duration: 420 } }

    function _tinta(base) {
        return tinteFuerza <= 0 ? base
            : Qt.tint(base, Qt.rgba(tinteColor.r, tinteColor.g,
                                    tinteColor.b, tinteFuerza))
    }

    //  Clamp `fuerza` from 0..1 to at most 0.45; `duracionMs` 0 lasts until
    //  destintar is called. Last call wins: detailed arbitration is unnecessary
    //  for a cosmetic effect whose provider can be disabled in Settings.
    function tintar(dueno, color, fuerza, duracionMs) {
        if (!dueno)
            return
        tinteDueno = String(dueno)
        tinteColor = color
        tinteFuerza = Math.max(0, Math.min(0.45, Number(fuerza) || 0))
        if (duracionMs > 0)
            _destinte.armar(duracionMs)
        else
            _destinte.stop()
    }

    function destintar(dueno) {
        if (tinteDueno === "" || (dueno && dueno !== tinteDueno))
            return
        tinteDueno = ""
        tinteFuerza = 0
        _destinte.stop()
    }

    property var _destinte: Timer {
        onTriggered: tema.destintar(tema.tinteDueno)
        function armar(ms) { stop(); interval = ms; start() }
    }

    // Island geometry
    readonly property int wing: 16              // inverted corner radius joining the screen edge
    readonly property int baseHeight: 34        // folded height and reserved desktop strip
    //  Surface height ceiling; see PanelWindow.
    //
    //  Raised to 640 for the video editor, which was cramped at 520. Later
    //  raised to 880 when layer strips made the editor taller: two layers
    //  requested 668, clipping the footer's add and render buttons below the
    //  island edge. The symptom gave no indication that this limit caused it,
    //  making the fault difficult to locate.
    //
    //  On a 1080px screen, 880 leaves 200px free, keeping this a bar rather
    //  than a full window. At the time, the next tallest module was the game
    //  at 470px.
    readonly property int maxIslandHeight: 880

    // Nerd Font Material Design icons (supplementary plane → fromCodePoint)
    readonly property var ico: ({
        play: String.fromCodePoint(0xF040A),
        pause: String.fromCodePoint(0xF03E4),
        next: String.fromCodePoint(0xF04AD),
        prev: String.fromCodePoint(0xF04AE),
        shuffle: String.fromCodePoint(0xF049D),
        repeat: String.fromCodePoint(0xF0456),
        repeatOne: String.fromCodePoint(0xF0458),
        output: String.fromCodePoint(0xF0F5F),
        music: String.fromCodePoint(0xF0387),
        wifi: String.fromCodePoint(0xF05A9),
        wifiOff: String.fromCodePoint(0xF05AA),
        bluetooth: String.fromCodePoint(0xF00AF),
        bluetoothOff: String.fromCodePoint(0xF00B2),
        volHigh: String.fromCodePoint(0xF057E),
        volMed: String.fromCodePoint(0xF0580),
        volOff: String.fromCodePoint(0xF0581),
        bell: String.fromCodePoint(0xF009A),
        bellOutline: String.fromCodePoint(0xF009C),
        search: String.fromCodePoint(0xF0349),
        chevronUp: String.fromCodePoint(0xF0143),
        chevronDown: String.fromCodePoint(0xF0140),
        cog: String.fromCodePoint(0xF0493),
        close: String.fromCodePoint(0xF0156),
        clearAll: String.fromCodePoint(0xF039F),
        apps: String.fromCodePoint(0xF003B),
        enter: String.fromCodePoint(0xF0311),
        ask: String.fromCodePoint(0xF0674),
        shot: String.fromCodePoint(0xF0E51),
        selection: String.fromCodePoint(0xF05E7),
        copy: String.fromCodePoint(0xF018F),
        alert: String.fromCodePoint(0xF0026),
        back: String.fromCodePoint(0xF0141),
        forward: String.fromCodePoint(0xF0142),
        loading: String.fromCodePoint(0xF0772),
        install: String.fromCodePoint(0xF03D4),
        uninstall: String.fromCodePoint(0xF09E7),
        package: String.fromCodePoint(0xF03D7),
        installed: String.fromCodePoint(0xF05E0),
        lock: String.fromCodePoint(0xF033E),
        check: String.fromCodePoint(0xF012C),
        linkOff: String.fromCodePoint(0xF0338),
        devices: String.fromCodePoint(0xF0FB0),
        headphones: String.fromCodePoint(0xF02CB),
        cellphone: String.fromCodePoint(0xF011C),
        mouse: String.fromCodePoint(0xF037D),
        keyboard: String.fromCodePoint(0xF030C),
        speaker: String.fromCodePoint(0xF04C3),
        watch: String.fromCodePoint(0xF0589),
        gamepad: String.fromCodePoint(0xF0EB5),
        laptop: String.fromCodePoint(0xF0322),
        printer: String.fromCodePoint(0xF042A),
        television: String.fromCodePoint(0xF0502),
        wifi0: String.fromCodePoint(0xF092D),
        wifi1: String.fromCodePoint(0xF091F),
        wifi2: String.fromCodePoint(0xF0922),
        wifi3: String.fromCodePoint(0xF0925),
        wifi4: String.fromCodePoint(0xF0928),
        // md-palette · md-border_all · md-blur · md-wallpaper · md-animation
        place: String.fromCodePoint(0xF034E),
        palette: String.fromCodePoint(0xF03D8),
        window: String.fromCodePoint(0xF00C7),
        effects: String.fromCodePoint(0xF00B5),
        wallpaper: String.fromCodePoint(0xF0E09),
        animation: String.fromCodePoint(0xF05D8),
        image: String.fromCodePoint(0xF02E9)
    })
}
