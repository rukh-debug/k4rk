//  The bar's settings, as a view deployed from the island.
//
//  They used to be a card inside a window of their own (K4.Ventana,
//  namespace "k4-ajustes"): a separate surface with its own focus rules and
//  its own dismissal gesture. Now they open from the pill like the control
//  center, hold the keyboard while open, and close with Escape or a click
//  outside — the same gestures every deployed view answers to. See
//  `AjustesView.qml` for the layout.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "settings"
    title: "Settings"
    priority: 66

    //  A deployed view: it occupies the island while open.
    active: habilitado && open
    viewLoaded: open
    grabKeyboard: open

    property bool open: false

    //  Sized once: the sidebar plus one section on the right. The window it
    //  replaces was 1040x700 of card; the island trims the frame and the
    //  margins the card carried, and the search field absorbs the rest.
    //
    //  These are user settings, not constants: the Island page carries
    //  steppers for both, and the island grows and shrinks while you turn
    //  them — the same live resize the control centre does between its tabs.
    //  Clamped to the steppers' bounds so a hand-edited settings file cannot
    //  open a window bigger than the screen or thinner than the sidebar.
    islandWidth: Math.max(720, Math.min(1400,
                  Settings.settingsIslandWidth))
    islandHeight: Math.max(420, Math.min(900,
                   Settings.settingsIslandHeight))

    //  ── a page to land on ─────────────────────────────
    //
    //  `k4 settingsSection wallpaper` and friends set this; the view lands on
    //  that page when it opens — or right away, if it already is. Empty is
    //  the top, as always. The view clears it once consumed, so closing and
    //  reopening with the pill starts at the top again.
    property string paginaPedida: ""

    function abrirPagina(pagina) {
        paginaPedida = String(pagina)
        if (!open)
            toggle()
    }

    //  ── is there a newer k4? ────────────────────────────────────
    //
    //  It lives here and not in a service for a practical reason: a new
    //  singleton in services/ does not hot-load — the whole bar needs a
    //  restart — and this was written, tested and tuned with `pluginReload
    //  settings`. And a deeper one: Settings is what shows it, so let the
    //  one showing it know.
    property Version version: Version {}

    //  `abrir()` from the API lands here, so the app center and the keybind
    //  walk in without knowing there used to be a window behind it.
    function toggle() {
        if (open) {
            close()
        } else {
            open = true
            Consola.revisar()
            self.version.mirar(false)
        }
    }

    function close() { open = false }

    //  The background glance, so the news does not depend on Settings being
    //  opened. Every six hours and once at startup — with a minute of grace,
    //  because startup already has plenty to do and a network call right
    //  then only competes with what is actually visible.
    //
    //  The deadline is tied to having been LOOKED at, not to having found
    //  out. Tied to the result —«still no commit? then again in a minute»—
    //  a copy that is not a git clone never learns anything, so it kept
    //  firing an `sh` and four `git` every minute forever.
    property Timer _vistazo: Timer {
        interval: self.version.ultima > 0 ? 6 * 3600 * 1000 : 60000
        repeat: true
        running: self.habilitado
        onTriggered: self.version.mirar(true)
    }

    view: Component { AjustesView { plugin: self } }

    K4.Ipc {
        target: "k4.settings"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }

        //  Open at a page by name, for keybinds: `quickshell ipc call
        //  k4.settings abrirPagina wallpaper`. Section name or its id both
        //  work ("Wallpaper", "wallpaper", "effects"…), case-insensitive.
        function abrirPagina(pagina: string): void {
            self.abrirPagina(pagina)
        }

        function togglePlugin(id: string): void { Settings.alternar(id) }

        //  To peek at its insides without opening anything: which commit the
        //  bar is on, how far behind `origin` it is, and why it cannot tell
        //  when it cannot tell.
        function version(): string {
            return JSON.stringify({
                commit: self.version.commit,
                detras: self.version.detras,
                sucio: self.version.sucio,
                pega: self.version.pega,
                mirando: self.version.mirando
            })
        }

        //  And to launch it from outside, which is what the button does.
        function update(): void { self.version.actualizar() }
    }
}
