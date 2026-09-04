//  Spotlight-style launcher, with a second mode for installing
//  packages.
//
//  Two speeds in the search: pacman reads the local base (~0.3 s)
//  and comes out at once; yay queries the AUR RPC (~1.3 s) and is
//  left for when you stop typing, so the service is not
//  abused.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "launcher"
    title: "Launcher"
    priority: 80
    colocable: true
    // it keeps the island while shrinking, but with no content
    // left
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    //  Host-injected references, declared by catalog id: the panel (opened
    //  alongside this one) and the app centre (its updates view, offered
    //  here when the system has some).
    property var panel: null
    property var apps: null

    property bool open: false
    property bool closing: false
    property string query: ""
    property int index: 0
    property var matches: []

    //  The packages plugin, injected by catalog id: the updates note at
    //  the foot of the list is its to feed — the launcher only shows
    //  what it is told, and asks it nothing else.
    property var packages: null

    // On opening the launcher the user's application index is
    // refreshed. K4.Apps already watches for changes, but this step
    // covers installations that create the .desktop while k4 was
    // closed or during a scan.
    readonly property string applicationsDir: {
        const dataHome = K4.Sistema.entorno("XDG_DATA_HOME")
        const base = dataHome && dataHome.length > 0
            ? dataHome : K4.Sistema.entorno("HOME") + "/.local/share"
        return base + "/applications"
    }

    islandWidth: 720
    islandHeight: 440

    readonly property int count: matches.length
    // `conservarSeleccion` is used by the periodic refresh:
    // without it, every second the index reset to zero and the list
    // sent you back up while going down with the arrows or the
    // wheel.
    function rebuild(conservarSeleccion) {
        const q = query.trim().toLowerCase()
        const applications = K4.Apps.lista
        const found = []

        for (let i = 0; i < applications.length; ++i) {
            const app = applications[i]
            if (app.noDisplay)
                continue

            const haystack = (app.name + " " + app.genericName + " " + app.id).toLowerCase()
            if (q.length === 0 || haystack.indexOf(q) !== -1)
                found.push(app)
        }

        found.sort(function (a, b) { return a.name.localeCompare(b.name) })

        //  This panel is the SYSTEM applications' one and that is
        //  what rules: whatever plugins contribute goes behind,
        //  never in front. Whoever opens the launcher and types
        //  «fire» wants Firefox, and a contribution however
        //  well-intentioned cannot cut in front of what the
        //  person already knows. The bar's things have their own
        //  drawer (SUPER+SHIFT+Space); they show up here so they can
        //  be FOUND, not to compete.
        //  Three ways to have an icon, in this order: the one the
        //  result itself brings —`imagen` or `glifo`—, the desktop
        //  icon name if
        //  what it contributes IS an installed application, and
        //  otherwise its plugin's. Only the second used to exist, so
        //  a plugin's contribution came out with an empty slot: the
        //  row expected a desktop icon name and what a plugin has is
        //  another thing. An empty slot between rows that do have
        //  icons reads as «this is half done», which was exactly the
        //  opposite of what was going on.
        const extras = (Enganches.resultados || []).map(function (r) {
            let imagen = r.imagen || ""
            let glifo = r.glifo || 0
            if (!imagen && !glifo && !r.icono) {
                const suyo = PluginManager.iconoDe(r._plugin || "")
                imagen = suyo.imagen
                glifo = suyo.glifo
            }
            return { name: r.titulo || "", genericName: r.desc || "",
                     icon: r.icono || "", _enganche: r,
                     _imagen: imagen, _glifo: glifo,
                     _insignia: r.insignia || null }
        })
        matches = found.slice(0, 40).concat(extras)

        if (conservarSeleccion === true)
            index = Math.max(0, Math.min(index, matches.length - 1))
        else
            index = 0
    }

    //  Tell the plugins what is being typed, and repaint when they
    //  answer — which can be later, if theirs takes a while.
    onQueryChanged: Enganches.buscar(query)

    property Connections _aportes: Connections {
        target: Enganches
        function onResultadosChanged() { self.rebuild(true) }
    }

    //  Opened with somewhere to be: the host's `k4 search` lands here
    //  instead of poking open/query/rebuild from outside. One verb, one
    //  door — and the opening sequence stays where it belongs.
    function buscar(texto) {
        if (!open)
            toggle()
        query = texto
        rebuild()
    }

    function refreshApplications() {
        desktopDatabaseProcess.running = true
        rebuild()
    }

    function toggle() {
        if (open) {
            close()
            return
        }

        query = ""
        closing = false
        if (panel) panel.close()
        Notifs.dismissToast()
        open = true
        refreshApplications()
    }

    function close() {
        open = false
        closing = true
        query = ""
        closeTimer.restart()
    }

    function launchSelected() {
        if (matches.length === 0)
            return

        const entry = matches[index]

        //  One contributed by a plugin: we hand it back and it will
        //  know.
        if (entry && entry._enganche) {
            close()
            Enganches.elegir(entry._enganche)
            return
        }

        close()
        abrir(entry)
    }

    // entry.execute() is not used: that inherits the working
    //  directory of the bar, which is quickshell's config folder
    //  —hence terminals kept opening in ~/.config/quickshell/k4—.
    //  It launches with the directory the entry itself asks for,
    //  and if it asks for none, at home.
    function abrir(entry) {
        const dir = entry.workingDirectory && entry.workingDirectory.length > 0
            ? entry.workingDirectory : K4.Sistema.entorno("HOME")

        if (!entry.command || entry.command.length === 0) {
            entry.execute()
            return
        }

        K4.Sistema.lanzar(["sh", "-c",
            "cd " + JSON.stringify(dir) + " && exec \"$@\"", "sh"].concat(entry.command))
    }

    function moveSelection(delta) {
        if (count === 0)
            return

        index = Math.max(0, Math.min(count - 1, index + delta))
    }

    // A notification steps the launcher aside.
    Connections {
        target: Notifs
        function onNotified() { self.open = false }
    }

    Connections {
        target: K4.Apps
        function onListaChanged() { self.rebuild() }
    }

    Timer {
        id: closeTimer
        interval: 320
        onTriggered: self.closing = false
    }

    Timer {
        interval: 1000
        repeat: true
        running: self.open
        onTriggered: self.rebuild(true)
    }

    K4.Process {
        id: desktopDatabaseProcess
        command: ["update-desktop-database", self.applicationsDir]
        onTerminado: self.rebuild()
    }

    K4.Ipc {
        target: "k4.launcher"
        function toggle(): void { self.toggle() }
        function search(q: string): void { self.buscar(q) }
    }

    view: Component {
        LauncherView { plugin: self }
    }
}
