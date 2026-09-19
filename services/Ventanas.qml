pragma Singleton

//  Open windows for the switcher.
//
//  Use Hyprland rather than the Wayland protocol: the protocol's activate()
//  requests focus but does NOT switch workspaces, so selecting a window on
//  another workspace did nothing. Hyprland also supplies each window's
//  address and workspace, which are needed to actually reach it.
//
//  The compositor lists windows in creation order, which is unhelpful for
//  Alt+Tab: users want the previous window, not the first one opened that
//  morning. Track most-recently-used order here.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: ventanas

    // Addresses in usage order, most recent first.
    property var recientes: []

    //  The PID of the currently focused window.
    //
    //  Plugins cannot query Hyprland directly; platform access belongs in
    //  a service. Consumers with items tracked by PID need to know when
    //  the user has focused their window. The terminal bell, for example,
    //  could request attention but previously could not tell it was given.
    //
    //  A string rather than an integer matches IPC values without forcing
    //  every consumer to convert them before comparison.
    property string pidActivo: ""

    readonly property var lista: {
        const abiertas = Hyprland.toplevels.values.slice()
        const salida = []

        for (let i = 0; i < recientes.length; ++i) {
            for (let j = 0; j < abiertas.length; ++j) {
                if (direccion(abiertas[j]) === recientes[i]) {
                    salida.push(abiertas[j])
                    abiertas.splice(j, 1)
                    break
                }
            }
        }
        return salida.concat(abiertas)
    }

    readonly property int count: lista.length

    //  ── which windows are visible ────────────────────────────────
    //
    //  A Hyprland client's `visible` field does NOT answer this: windows on
    //  other workspaces also report true. Compare against each monitor's
    //  shown workspace, plus its special workspace if one is expanded.
    //
    //  Desktop overlays need this distinction: targeting an off-screen
    //  window for a crop would capture empty space.
    readonly property var espaciosVistos: {
        const ids = ({})
        const monitores = Hyprland.monitors.values
        for (let i = 0; i < monitores.length; ++i) {
            const m = monitores[i]
            if (m.activeWorkspace)
                ids[m.activeWorkspace.id] = true
            const d = m.lastIpcObject
            if (d && d.specialWorkspace && d.specialWorkspace.id !== 0)
                ids[d.specialWorkspace.id] = true
        }
        return ids
    }

    function seVe(d) {
        const w = d ? d.workspace : null
        return !!(w && espaciosVistos[w.id] === true)
    }

    function refrescar() {
        if (typeof Hyprland.refreshToplevels === "function")
            Hyprland.refreshToplevels()
    }

    // ── window data ───────────────────────────────────────────────
    function datos(t) { return t && t.lastIpcObject ? t.lastIpcObject : ({}) }

    function direccion(t) {
        if (!t)
            return ""
        const d = datos(t).address
        return d ? String(d) : (t.address ? "0x" + t.address : "")
    }

    function clase(t) { return String(datos(t).class || "") }

    function tituloVentana(t) { return String(datos(t).title || "") }

    function espacio(t) {
        const w = datos(t).workspace
        return w && w.name !== undefined ? String(w.name) : ""
    }

    function icono(t) {
        const id = clase(t)
        if (id.length === 0)
            return ""

        // A class name rarely matches its icon name. Try three lookups,
        // from cheapest to most expensive.
        let r = Quickshell.iconPath(id, true)
        if (r) return r
        r = Quickshell.iconPath(id.toLowerCase(), true)
        if (r) return r

        const apps = DesktopEntries.applications.values
        const bajo = id.toLowerCase()
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const suyo = String(a.id || "").toLowerCase()
            if (suyo === bajo || suyo.indexOf(bajo) !== -1
                || String(a.name || "").toLowerCase() === bajo) {
                const p = Quickshell.iconPath(a.icon, true)
                if (p) return p
            }
        }
        return ""
    }

    // The display name, if its desktop entry provides one.
    function titulo(t) {
        const id = clase(t).toLowerCase()
        if (id.length === 0)
            return "Window"

        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            if (String(a.id || "").toLowerCase() === id)
                return a.name || clase(t)
        }
        return clase(t)
    }

    // ── focus a window ────────────────────────────────────────────
    //
    //  Use Lua syntax like the rest of the Hyprland configuration: the new
    //  parser rejects `dispatch focuswindow address:…`. `focus` with an
    //  address does switch workspaces, unlike the Wayland activate request.
    function activar(t) {
        const d = direccion(t)
        if (d.length === 0)
            return
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + d + '" })')
    }

    function cerrar(t) {
        const d = direccion(t)
        if (d.length === 0)
            return
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + d + '" })')
        refrescar()
    }

    // ── usage order ───────────────────────────────────────────────
    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            const t = Hyprland.activeToplevel

            const pid = ventanas.datos(t).pid
            ventanas.pidActivo = pid === undefined ? "" : String(pid)

            if (!t)
                return
            const d = ventanas.direccion(t)
            if (d.length === 0)
                return
            const sin = ventanas.recientes.filter(function (x) { return x !== d })
            ventanas.recientes = [d].concat(sin).slice(0, 40)
        }
    }

    Component.onCompleted: refrescar()
}
