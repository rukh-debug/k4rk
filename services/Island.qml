pragma Singleton

//  The island's own state, independent of any module.
//
//  The host (shell.qml) maintains it; features read it to decide whether to
//  request the island — the clock activates on hover, for example.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: isla

    // Is the pointer over the island?
    property bool hovered: false

    //  Who currently owns the island and whether it is expanded. shell.qml
    //  sets this after comparing priorities. Plugins read it through
    //  K4.Isla to avoid animations and polling that nobody would see.
    property string ocupante: ""
    property bool abierta: false

    // The pill exists on every screen; an expanded view occupies one.
    // `pantallaPedida` preserves the action's origin until the host knows
    // which feature won. A click supplies its screen; a shortcut falls
    // back to Hyprland's focused monitor.
    property string pantallaActiva: ""
    property string pantallaPedida: ""

    function pedirPantalla(nombre) {
        if (nombre)
            pantallaPedida = String(nombre)
    }

    function pantallaConFoco() {
        const monitor = Hyprland.focusedMonitor
        if (monitor && monitor.name)
            return monitor.name
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    function pedirPantallaConFoco() { pedirPantalla(pantallaConFoco()) }

    function tomarPantallaPedida() {
        const elegida = pantallaPedida || pantallaConFoco()
        pantallaPedida = ""
        return elegida
    }

    function usarPantalla(nombre) {
        pantallaActiva = nombre || pantallaConFoco()
        pantallaPedida = ""
    }

    // Force a particular mode; used over IPC for debugging.
    property string debugMode: ""

    //  The bar's current edge: "top" or "bottom". The user chooses it in
    //  Settings; plugins drawing outside the island read it to determine
    //  which direction to extend.
    readonly property string posicion: Settings.barPosition

    //  The island's location in screen coordinates.
    //
    //  `rect` describes the primary screen, for single-monitor setups and
    //  plugins that need no further detail. `rects` maps every screen name:
    //  the island repeats across monitors, and a K4.Ventana must be able
    //  to anchor to its OWN island.
    property var rect: ({ x: 0, y: 0, ancho: 0, alto: 0 })

    //  Screen dimensions for the Settings preview to draw the island at
    //  its actual scale. Without these it would have to assume 1920×1080,
    //  giving the wrong proportions on any other screen.
    //
    //  Kept here because `tools/api.py` forbids plugins from importing
    //  Quickshell: capabilities absent from the API belong in a service.
    //  This service already imports it to resolve screens.
    readonly property real altoPantalla: {
        const p = Quickshell.screens
        return p.length > 0 && p[0].height > 0 ? p[0].height : 1080
    }

    readonly property real anchoPantalla: {
        const p = Quickshell.screens
        return p.length > 0 && p[0].width > 0 ? p[0].width : 1920
    }
    property var rects: ({})

    function publicarRect(pantalla, r, esPrincipal) {
        const d = Object.assign({}, rects)
        d[pantalla] = r
        rects = d
        if (esPrincipal)
            rect = r
    }

    // ── is it visible anywhere? ───────────────────────────────────
    //
    //  In Qt Quick, an animation does NOT stop when its item becomes
    //  invisible. It keeps running and repainting the entire scene at the
    //  monitor's refresh rate. Endless animations — audio bars, pulsing
    //  chests — must check visibility first; this is the state they read.
    //
    //  Each bar publishes its screen's visibility, as with `rects`: when
    //  the island is hidden on one monitor but shown on another, it is
    //  still visible to someone.
    property var vistas: ({})

    function publicarVista(pantalla, seVe) {
        if (vistas[pantalla] === !!seVe)
            return
        const d = Object.assign({}, vistas)
        d[pantalla] = !!seVe
        vistas = d
    }

    //  `apartada` overrides everything: while a system dialog hides the
    //  island, it is invisible regardless of each screen's publication.
    //
    //  With no publishers, default to visible. An extra animation is less
    //  disruptive than one that never starts, and this allows the island
    //  to run without shell.qml, such as in a plugin's `--test` setup.
    readonly property bool aLaVista: {
        if (apartada)
            return false
        const nombres = Object.keys(vistas)
        for (let i = 0; i < nombres.length; ++i)
            if (vistas[nombres[i]])
                return true
        return nombres.length === 0
    }

    // ── placement ────────────────────────────────────────────────
    //
    //  Position along the edge as a fraction of free width: 0 at the left,
    //  1 at the right. Settings.barAlignment supplies the base; a plugin can
    //  move it TEMPORARILY with colocar(), for dodging, acting as a paddle,
    //  or making room to show something. It returns on timeout, release,
    //  or owner disablement: PluginManager calls soltar() on destruction.
    property string colocacionDueno: ""
    property real colocacionPedida: -1      // -1 = no request; Settings wins

    readonly property real colocacion: colocacionPedida >= 0
        ? colocacionPedida : Settings.barAlignment / 100

    function colocar(dueno, fraccion, duracionMs) {
        if (!dueno)
            return
        colocacionDueno = String(dueno)
        colocacionPedida = Math.max(0, Math.min(1, Number(fraccion) || 0))
        if (duracionMs > 0)
            _suelta.armar(duracionMs)
        else
            _suelta.stop()
    }

    function soltar(dueno) {
        if (colocacionDueno === "" || (dueno && dueno !== colocacionDueno))
            return
        colocacionDueno = ""
        colocacionPedida = -1
        _suelta.stop()
    }

    property var _suelta: Timer {
        onTriggered: isla.soltar(isla.colocacionDueno)
        function armar(ms) { stop(); interval = ms; start() }
    }

    // ── gestures ──────────────────────────────────────────────────
    //
    //  The island as a physical object: a shake, push or pull. A plugin
    //  requests it and the host animates it. Arbitration is deliberately
    //  simple: at most one gesture per half-second, with bounded strength.
    //  Occasional effects stand out against a restrained bar; without
    //  these limits, one noisy plugin would disrupt the whole shell.
    signal gesto(string nombre, real fuerza)

    property real _ultimoGesto: 0

    function efecto(dueno, nombre, fuerza) {
        const ahora = Date.now()
        if (ahora - _ultimoGesto < 500)
            return
        _ultimoGesto = ahora
        const f = fuerza === undefined ? 1
            : Math.max(0.2, Math.min(1, Number(fuerza) || 0))
        gesto(String(nombre), f)
    }

    //  How many system dialogs are currently open.
    //
    //  The island's layer sits above normal windows, so a file picker it
    //  opens would appear UNDER it. While a dialog exists, the island hides
    //  and stops accepting clicks; otherwise its invisible strip would
    //  still swallow input.
    //
    //  Use a counter rather than a boolean because two file requests can
    //  overlap. Closing one must not reveal the island while the other
    //  dialog remains open.
    property int dialogos: 0

    function abrirDialogo() { dialogos += 1 }
    function cerrarDialogo() { dialogos = Math.max(0, dialogos - 1) }

    readonly property bool apartada: dialogos > 0

    //  A watchdog prevents the bar from remaining hidden indefinitely.
    //
    //  The counter increases when a process starts and decreases on exit.
    //  If its containing view is destroyed or the process dies without
    //  delivering that notification, the island could remain hidden until
    //  the bar is restarted.
    //
    //  While the counter is positive, periodically check that a zenity
    //  process is actually alive. Reset the counter when none remain.
    //  This check runs only while a dialog is open, costing nothing at rest.
    property var _sonda: Process {
        //  Keep stderr, previously discarded, so failures leave their reason
        //  in the bar's log.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("island:", l)
            }
        }
        command: ["pgrep", "-c", "-x", "zenity"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(String(this.text).trim(), 10)
                if (isFinite(n) && n <= 0)
                    isla.dialogos = 0
            }
        }
    }

    property var _vigilante: Timer {
        interval: 3000
        repeat: true
        running: isla.dialogos > 0
        onTriggered: isla._sonda.running = true
    }
}
