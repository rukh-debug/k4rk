//  Clipboard: the history of what was copied, with search.
//
//  It opens with the keyboard, one types to filter and Enter puts
//  something back on the clipboard. What is pinned never expires,
//  which is what turns it into a drawer of things pasted a hundred
//  times a day.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "clipboard"
    title: "Clipboard"
    // Above the launcher: if both are open, you rule with the one
    // just asked for, and this one is always asked for on
    // purpose.
    priority: 82
    colocable: true
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property bool closing: false
    property string query: ""
    property int index: 0

    islandWidth: 720
    islandHeight: 470

    readonly property var lista: Clipboard.filtrar(query)
    readonly property int count: lista.length

    view: Component {
        ClipboardView { plugin: self }
    }

    function abrir() {
        Clipboard.recargar()
        query = ""
        index = 0
        closing = false
        open = true
        if (panel)
            panel.close()
    }

    function close() {
        if (!open)
            return
        open = false
        closing = true
        cierre.restart()
    }

    function toggle() { open ? close() : abrir() }

    Timer {
        id: cierre
        interval: 260
        onTriggered: self.closing = false
    }

    // ── keyboard ──────────────────────────────────────────────────
    function mover(paso) {
        if (count === 0)
            return
        index = Math.max(0, Math.min(count - 1, index + paso))
    }

    function elegir() {
        const e = lista[index]
        if (!e)
            return
        Clipboard.copiar(e.id)
        close()
    }

    function borrarActual() {
        const e = lista[index]
        if (!e)
            return
        Clipboard.borrar(e.id)
        // whatever takes its place becomes selected
        index = Math.max(0, Math.min(index, count - 2))
    }

    function fijarActual() {
        const e = lista[index]
        if (e)
            Clipboard.fijar(e.id)
    }

    // The list rebuilds itself when a new copy comes in: if the
    // index falls outside, it is clamped instead of pointing at
    // nothing.
    onCountChanged: if (index >= count) index = Math.max(0, count - 1)

    K4.Ipc {
        target: "k4.clipboard"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
        function clear(): void { Clipboard.limpiar() }
    }
}
