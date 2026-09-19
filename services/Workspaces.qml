pragma Singleton

// Hyprland workspaces, sorted by ID.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    readonly property var list: {
        const values = Hyprland.workspaces.values.slice()
        values.sort(function (a, b) { return a.id - b.id })
        return values
    }

    //  The desks the indicators wear: the whole roster, with the
    //  scratchpad (Hyprland's `special:` desks, negative ids) sent last
    //  and only when the Control Centre switch says so.
    readonly property var shownList: {
        const normales = []
        const especiales = []
        for (let i = 0; i < list.length; ++i) {
            const e = list[i]
            if (e.id < 0)
                especiales.push(e)
            else
                normales.push(e)
        }
        return Settings.panelShowScratchpad
            ? normales.concat(especiales) : normales
    }

    //  What a desk wears in the numbered dress: its id, or — for the
    //  scratchpad — the name Hyprland keeps after the `special:`.
    function label(e) {
        if (e.id >= 0)
            return String(e.id)
        const n = String(e.name || "")
        const corte = n.indexOf(":")
        return corte >= 0 ? n.slice(corte + 1) : n
    }

    // The focused workspace needs its own property: `list` changes for many
    // reasons, such as an opened window or a renamed workspace, but this
    // indicator should only signal workspace switches.
    readonly property int activo: {
        for (let i = 0; i < list.length; ++i)
            if (list[i].focused)
                return list[i].id
        return -1
    }

    // Pill dot width: active dot + remaining dots + gap before the clock.
    readonly property int dotsWidth: list.length === 0
        ? 0 : (list.length - 1) * 10 + 18 + 8

    //  ── is anything filling the screen? ──────────────────────────
    //
    //  Read the workspace, not individual windows: that is where Hyprland
    //  records `hasfullscreen`, answering whether the monitor's shown
    //  workspace is filled without extra work. Checking every client would
    //  require comparing geometry and defining how close to full counts.
    //
    //  This includes BOTH Hyprland fullscreen modes: true fullscreen and
    //  dispatcher maximization, because the workspace flags both.
    //
    //  Key by monitor NAME, as used throughout the bar: both PanelWindow
    //  and plugins know their screen by name.
    readonly property var llenos: {
        const d = ({})
        const monitores = Hyprland.monitors.values
        for (let i = 0; i < monitores.length; ++i) {
            const m = monitores[i]
            const e = m.activeWorkspace
            const dato = e ? e.lastIpcObject : null
            d[String(m.name)] = !!(dato && dato.hasfullscreen)
        }
        return d
    }

    function lleno(pantalla) { return llenos[String(pantalla)] === true }

    //  Explicitly refresh the data: the workspace list does NOT refresh
    //  itself when a window becomes fullscreen. Hyprland announces it over
    //  the event socket; without rereading the list, consumers might not
    //  learn about it until a window opens or closes an hour later.
    //
    //  Also handle `closewindow`: closing a fullscreen window clears the
    //  state without necessarily emitting a `fullscreen` event.
    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(evento) {
            const n = String(evento.name || "")
            if (n !== "fullscreen" && n !== "closewindow")
                return
            if (typeof Hyprland.refreshWorkspaces === "function")
                Hyprland.refreshWorkspaces()
        }
    }
}
