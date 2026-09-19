pragma Singleton

//  Clipboard history.
//
//  Quickshell exposes `clipboardText`, but on Wayland its change signal does
//  not fire when another application copies: a probe received no initial
//  content either. The compositor only notifies the focused client, and the
//  bar never has focus here. Instead, `wl-paste --watch` observes changes,
//  with one watcher for text and another for images so both are captured.
//
//  tools/clipboard.py manages the archive: each copy has its own file,
//  with a lightweight index. This service only starts the watchers, requests
//  the list and sends commands.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: portapapeles

    readonly property string guion: Quickshell.shellPath("tools/clipboard.py")

    property var entradas: []
    readonly property int count: entradas.length
    property bool cargado: false

    signal cambio()

    // ── queries ───────────────────────────────────────────────────
    function filtrar(texto) {
        const q = (texto || "").trim().toLowerCase()
        if (q.length === 0)
            return entradas

        const salida = []
        for (let i = 0; i < entradas.length; ++i) {
            const e = entradas[i]
            if (e.resumen.toLowerCase().indexOf(q) !== -1
                || (e.etiqueta || "").indexOf(q) !== -1)
                salida.push(e)
        }
        return salida
    }

    // Use the first nonblank line: a copy starting with line breaks must
    // not appear as an empty row.
    function titulo(e) {
        if (!e)
            return ""
        if (e.tipo === "image")
            return "Image · " + tamaño(e.bytes)

        const lineas = e.resumen.split("\n")
        for (let i = 0; i < lineas.length; ++i) {
            if (lineas[i].trim().length > 0)
                return lineas[i].trim()
        }
        return e.resumen.trim()
    }

    function tamaño(n) {
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024) return Math.round(n / 1024) + " KB"
        return n + " B"
    }

    function hace(cuando) {
        const s = Math.max(0, Date.now() / 1000 - cuando)
        if (s < 60) return "now"
        const m = Math.floor(s / 60)
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60)
        if (h < 24) return h + " h"
        return Math.floor(h / 24) + " d"
    }

    // ── commands ──────────────────────────────────────────────────
    function copiar(id) { mandar(["copy", id]) }
    function borrar(id) { mandar(["delete", id]) }
    function fijar(id) { mandar(["pin", id]) }
    function limpiar() { mandar(["clear"]) }

    function mandar(args) {
        orden.command = ["python3", portapapeles.guion].concat(args)
        orden.running = true
    }

    Process {
        id: orden
        onExited: portapapeles.recargar()
    }

    // ── the list ──────────────────────────────────────────────────
    function recargar() { lector.running = true }

    Process {
        id: lector
        command: ["python3", portapapeles.guion, "list"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    portapapeles.entradas = d.entradas || []
                } catch (e) {
                    portapapeles.entradas = []
                }
                portapapeles.cargado = true
                portapapeles.cambio()
            }
        }
    }

    // ── watchers ──────────────────────────────────────────────────
    //
    //  `wl-paste --watch` runs the script with the copy on standard input
    //  whenever the clipboard changes. The script's output arrives here,
    //  indicating that something new is ready to read.
    //
    //  Two watchers are needed because the text watcher ignores images and
    //  vice versa; one alone would miss half the supported content types.

    Process {
        id: vigilaTexto
        command: ["wl-paste", "--type", "text", "--watch",
                  "python3", portapapeles.guion, "save", "text"]
        running: true

        stdout: SplitParser {
            onRead: portapapeles.recargar()
        }

        onExited: revivir.restart()
    }

    Process {
        id: vigilaImagen
        command: ["wl-paste", "--type", "image", "--watch",
                  "python3", portapapeles.guion, "save", "image"]
        running: true

        stdout: SplitParser {
            onRead: portapapeles.recargar()
        }

        onExited: revivir.restart()
    }

    // A compositor restart kills wl-paste and would silently stop history
    // collection. Retry at a relaxed interval.
    Timer {
        id: revivir
        interval: 12000
        onTriggered: {
            vigilaTexto.running = true
            vigilaImagen.running = true
        }
    }
}
