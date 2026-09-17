//  The Hyprland submap island: whatever mode the compositor is in,
//  as a place of its own.
//
//  Hyprland submaps are one string each — the id IS the name — so the
//  name has to carry everything the bar wants to show. The standard
//  this plugin parses:
//
//      Title: (r)egion (screenshot --region) (f)ull (screenshot --full)
//
//  · text before the first ":" is the title;
//  · a paren group whose every token is a single glyph — (r), (h j k l),
//    (← → ↑ ↓) — starts an entry and lists its keys;
//  · the label follows: glued to the group it completes the key's word
//    ("(r)egion" shows "Region"), as separate words it reads as-is
//    ("(r)egion mp4" shows "Region mp4");
//  · a paren group with any longer token is the command the key runs,
//    verbatim, executed through `sh -c` when the chip is pressed;
//  · a final ", note" outside the groups is a footer hint.
//
//  A name without a colon or without a single key group is not
//  parsable, and the island shows it as plain text instead — an id
//  nobody formatted still deserves to be read.
//
//  While a submap is on, this plugin takes the island at a priority
//  over everything the user may have opened: a mode is the keyboard
//  speaking another language, and nothing on screen matters more than
//  which language. The island is a Placement citizen like any summoned
//  surface.
//
//  Pressing a chip runs the command and resets the submap, exactly
//  what the key itself does; the island then folds on the `submap`
//  event, the same way it would if the key had been pressed.

import QtQuick
import K4 as K4
import "../../core"

K4Plugin {
    id: self

    name: "hyprland-submap"
    title: "Hyprland Submap"
    //  Over every summoned view (launcher 80, chat 90): a live mode
    //  outranks whatever the user had open.
    priority: 95
    colocable: true
    //  Nobody clicks away a mode they did not open — a tap outside
    //  spends itself on the desktop, not on hiding the announcement.
    closeOnClickOutside: false

    // ── what Hyprland says ────────────────────────────────────
    readonly property string mapa: K4.Submaps.current

    property bool cerrando: false

    active: habilitado && (mapa.length > 0 || cerrando)
    viewLoaded: mapa.length > 0

    //  The name the island keeps its measures from. The reset event
    //  empties `mapa` before the closing animation has finished, and a
    //  size that followed it would snap the island to the fallback
    //  width mid-fold — so while it closes, the island remembers the
    //  mode it just showed.
    property string ultimaMapa: ""
    readonly property string contenido: mapa.length > 0 ? mapa : ultimaMapa

    // ── the name, parsed ──────────────────────────────────────
    //
    //  null means "not parsable": no title, or no key group at all.
    //  Entries keep their raw pieces here; the words people read are
    //  composed once, at flush time.
    readonly property var parseo: analizar(contenido)

    function _cerrarEntrada(actual, etiqueta) {
        let e = String(etiqueta || "").trim().replace(/\s+/g, " ")
        if (actual.pegado && actual.teclas.length === 1
                && /^[a-z0-9]$/i.test(actual.teclas[0]))
            e = actual.teclas[0] + e
        if (e.length > 0)
            e = e.charAt(0).toUpperCase() + e.slice(1)
        actual.etiqueta = e
        return actual
    }

    function analizar(nombre) {
        const bruto = String(nombre || "").trim()
        if (bruto.length === 0)
            return null
        const ci = bruto.indexOf(":")
        if (ci <= 0)
            return null
        const titulo = bruto.slice(0, ci).trim()
        const cuerpo = bruto.slice(ci + 1)
        const N = cuerpo.length
        const entradas = []
        let actual = null
        let etiqueta = ""
        let i = 0
        while (i < N) {
            if (cuerpo[i] === "(") {
                //  Depth-matched: a command group may itself contain
                //  $( … ) and has to survive verbatim.
                let depth = 1
                let j = i + 1
                while (j < N && depth > 0) {
                    if (cuerpo[j] === "(")
                        depth++
                    else if (cuerpo[j] === ")")
                        depth--
                    if (depth > 0)
                        j++
                }
                if (depth !== 0)
                    return null
                const dentro = cuerpo.slice(i + 1, j).trim()
                const tokens = dentro.split(/\s+/).filter(t => t.length > 0)
                const esClaves = tokens.length > 0
                        && tokens.every(t => t.length === 1)
                if (esClaves) {
                    if (actual)
                        entradas.push(_cerrarEntrada(actual, etiqueta))
                    actual = { teclas: tokens, etiqueta: "",
                               comando: "", pegado: false }
                    //  A word glued to the group completes the key's
                    //  own word; it is consumed here, not appended.
                    const m = cuerpo.slice(j + 1).match(/^[^\s(]+/)
                    if (m && m[0].length > 0) {
                        actual.pegado = true
                        etiqueta = m[0]
                        i = j + 1 + m[0].length
                    } else {
                        etiqueta = ""
                        i = j + 1
                    }
                } else {
                    //  A command before any key group: nothing to
                    //  hang it on — plain text, then.
                    if (!actual)
                        return null
                    actual.comando = dentro
                    i = j + 1
                }
            } else {
                //  Plain words: label of the entry in progress. Text
                //  before the first group belongs to nobody and is
                //  skipped — the standard puts labels after keys.
                let j = i
                while (j < N && cuerpo[j] !== "(")
                    j++
                if (actual)
                    etiqueta += cuerpo.slice(i, j)
                i = j
            }
        }
        if (actual)
            entradas.push(_cerrarEntrada(actual, etiqueta))
        if (entradas.length === 0)
            return null

        //  The trailing ", note" — outside every group, so a comma
        //  inside a command can never be mistaken for one.
        let nota = ""
        const ultimo = entradas[entradas.length - 1]
        const k = ultimo.etiqueta.lastIndexOf(", ")
        if (k >= 0) {
            const resto = ultimo.etiqueta.slice(k + 2).trim()
            if (resto.length > 0) {
                nota = resto
                ultimo.etiqueta = ultimo.etiqueta.slice(0, k).trim()
            }
        }
        return { titulo: titulo, entradas: entradas, nota: nota }
    }

    // ── the island's size, from the parsed content ────────────
    //
    //  Estimates, not measurements: labels run ~6.2 px a character at
    //  this size and keys are fixed squares. Generous on purpose —
    //  a chip that fits its estimate never wraps by surprise, and the
    //  Flow in the view only wraps at the same greedy split these
    //  numbers compute.
    readonly property int _ladoLlave: 26

    function _anchoEntrada(e) {
        const llaves = e.teclas.length * _ladoLlave + (e.teclas.length - 1) * 3
        const texto = e.etiqueta.length > 0
                ? Math.ceil(e.etiqueta.length * 6.2) : 0
        return Math.max(llaves, texto)
    }

    //  The greedy row split both sizes share: one row while it fits
    //  under 660 px of chips, then another.
    function _filas() {
        if (!parseo)
            return 1
        let fila = 0
        let filas = 1
        const lista = parseo.entradas
        for (let n = 0; n < lista.length; ++n) {
            const w = _anchoEntrada(lista[n]) + 18
            if (fila > 0 && fila + w > 660) {
                filas++
                fila = w
            } else {
                fila += w
            }
        }
        return { filas: filas, ancho: fila }
    }

    islandWidth: {
        if (!parseo)
            return Math.max(240, Math.min(640, 70 + contenido.length * 6.5))
        return Math.max(260, Math.min(740, _filas().ancho + 40))
    }

    islandHeight: {
        if (!parseo)
            return 64
        const f = _filas().filas
        let h = 18 + 24 + 14 + f * 45 + (f - 1) * 18 + 18
        if (parseo.nota.length > 0)
            h += 21
        return h
    }

    view: Component { HyprlandSubmapView { plugin: self } }

    // ── running what the key would run ────────────────────────
    //
    //  Same shape as the config's own run-and-reset: the command is
    //  spawned, the submap is reset right after — exec spawns, it does
    //  not wait — and the `submap` event folds the island through the
    //  one path it always has.
    //
    //  The reset goes out as a Lua EXPRESSION, not the classic
    //  "dispatch submap reset" words: this Hyprland runs a Lua config,
    //  and its hyprctl bridge pastes the argument raw into
    //  `return hl.dispatch(<arg>)` — two bare words are not Lua, and
    //  the reset would die on a syntax error nobody shows you.
    property var lanzar: K4.Process {
        command: []
        onTerminado: function (codigo) {
            resetear.running = true
        }
    }

    property var resetear: K4.Process {
        command: ["hyprctl", "dispatch", "hl.dsp.submap('reset')"]
    }

    function ejecutar(comando) {
        if (!comando || comando.length === 0)
            return
        lanzar.command = ["sh", "-c", comando]
        lanzar.running = true
    }

    //  The island's own exit door: the esc chip, for a pointer that
    //  wants the same courtesy the escape key has.
    function salir() {
        resetear.running = true
    }

    onMapaChanged: {
        if (mapa.length === 0) {
            cerrando = true
            cierre.restart()
        } else {
            ultimaMapa = mapa
            cerrando = false
            cierre.stop()
        }
    }

    //  Nothing summons this surface on purpose: without a mode on it
    //  has nothing to say, and an empty island is worse than none.
    function toggle(tab) { }
    function abrir() { }

    Timer {
        id: cierre
        interval: 260
        onTriggered: self.cerrando = false
    }
}
