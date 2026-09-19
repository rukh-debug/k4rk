pragma Singleton

//  The shell theme, published in a file for clients outside the bar.
//
//  Theme.qml is QML and cannot be read directly by other clients; k4term,
//  the shell's terminal, is written in Rust. This file bridges the two: the
//  bar writes it at startup and whenever the theme changes, and external
//  clients watch it with inotify. Neither side launches a process for this.
//
//  Colors are published ALREADY TINTED: when the dungeon tints the bar,
//  the terminal follows it. Semantic colors — green, red, blue, yellow —
//  stay untinted, as in Theme: error red must remain red under any theme.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: ambiente

    readonly property string carpeta: Quickshell.env("HOME") + "/.local/state/k4"
    readonly property string ruta: carpeta + "/tema.json"

    //  One watcher covers the whole theme: the four scaffold colors share
    //  a tint, so watching the background catches changes to all of them.
    property color fondo: Theme.islandBg
    onFondoChanged: if (listo) retardo.restart()

    property bool listo: false

    function contenido() {
        return JSON.stringify({
            fondo: String(Theme.islandBg),
            tinta: String(Theme.ink),
            apagado: String(Theme.muted),
            tenue: String(Theme.dim),
            superficie: String(Theme.surface),
            superficieAlta: String(Theme.surfaceHi),
            carril: String(Theme.track),
            verde: String(Theme.green),
            rojo: String(Theme.red),
            azul: String(Theme.blue),
            amarillo: String(Theme.yellow),
            radio: Theme.wing,
            fuente: Theme.iconFont,
            fuenteUi: Theme.uiFont,
            tinte: {
                dueno: Theme.tinteDueno,
                color: String(Theme.tinteColor),
                fuerza: Theme.tinteFuerza
            }
        }, null, 1)
    }

    function publicar() {
        if (listo)
            vista.setText(contenido())
    }

    FileView { id: vista; path: ambiente.ruta }

    //  The tint animates over 420 ms: without a delay, each transition would
    //  produce dozens of writes. Two or three are enough for the terminal
    //  to follow the change.
    Timer { id: retardo; interval: 180; onTriggered: ambiente.publicar() }

    Process {
        command: ["mkdir", "-p", ambiente.carpeta]
        running: true
        onExited: {
            ambiente.listo = true
            ambiente.publicar()
        }
    }
}
