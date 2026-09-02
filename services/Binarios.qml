pragma Singleton

//  Which binaries exist on this machine.
//
//  A plugin can depend on a tool the user may or may not have — codex,
//  any CLI — and until now it could only find out by trying and failing
//  in public. The catalog says it up front (`"requiere": "bin:codex"`),
//  and this service is the one honest answer to that question: one
//  batched `command -v` sweep for every name anyone asked about.
//
//  `presente(nombre)` is optimistic about the unprobed: a name nobody
//  has swept yet counts as present, so a plugin is never destroyed for
//  a question that has not been answered. The sweep lands, the map
//  speaks, and `cambiado` tells the manager to look again.
//
//  And the answer is refreshed while it is interesting: as long as some
//  asked-about name is missing, the sweep repeats — install the tool
//  and the plugin that needed it comes back on its own, no restart.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: binarios

    //  Every name anyone has asked about; `presentes` answers each.
    property var pedidos: []
    property var presentes: ({})

    signal cambiado()

    function presente(nombre) {
        return presentes[nombre] !== false
    }

    //  The sweep: one process, every name, echoing the name only when
    //  it was found.
    function sondear(nombres) {
        const limpio = pedidos.slice()
        for (let i = 0; i < nombres.length; ++i) {
            const n = String(nombres[i]).trim()
            if (n.length > 0 && limpio.indexOf(n) < 0)
                limpio.push(n)
        }
        if (limpio.length === 0)
            return
        pedidos = limpio

        const partes = []
        for (let j = 0; j < limpio.length; ++j)
            partes.push("command -v " + JSON.stringify(limpio[j])
                        + " >/dev/null 2>&1 && echo " + JSON.stringify(limpio[j]))
        sonda.command = ["sh", "-c", partes.join("; ")]
        sonda.running = true
    }

    Process {
        id: sonda
        stdout: StdioCollector {
            onStreamFinished: {
                const hallados = String(text).split("\n").map(
                    function (l) { return l.trim() })
                const nuevo = {}
                let cambio = false
                for (let i = 0; i < binarios.pedidos.length; ++i) {
                    const nombre = binarios.pedidos[i]
                    nuevo[nombre] = hallados.indexOf(nombre) >= 0
                    //  Strict inequality, so the FIRST observation —
                    //  undefined becoming an answer — counts as news.
                    if (binarios.presentes[nombre] !== nuevo[nombre])
                        cambio = true
                }
                binarios.presentes = nuevo
                if (cambio)
                    binarios.cambiado()
                //  While someone is missing, keep asking: the tool can
                //  be installed at any moment, and the plugin that needs
                //  it deserves to come back the minute it lands.
                reintento.restart()
            }
        }
    }

    //  The pace of the second look: often enough that installing a tool
    //  feels answered, rarely enough that an idle bar costs nothing.
    Timer {
        id: reintento
        interval: 30000
        onTriggered: {
            let falta = false
            for (const nombre in binarios.presentes)
                if (binarios.presentes[nombre] === false)
                    falta = true
            if (falta)
                binarios.sondear([])
        }
    }
}
