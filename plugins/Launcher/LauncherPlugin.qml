//  Lanzador estilo Spotlight, con un segundo modo para instalar paquetes.
//
//  Dos velocidades en la búsqueda: pacman lee la base local (~0.3 s) y sale al
//  instante; yay consulta el RPC de AUR (~1.3 s) y se deja para cuando dejas
//  de teclear, para no abusar del servicio.

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
    // sigue ocupando la island mientras se encoge, pero ya sin contenido
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

    // Al abrir el lanzador se actualiza el índice de aplicaciones del usuario.
    // K4.Apps ya vigila cambios, pero este paso cubre instalaciones que
    // crean el .desktop mientras k4 estaba cerrado o durante un escaneo.
    readonly property string applicationsDir: {
        const dataHome = K4.Sistema.entorno("XDG_DATA_HOME")
        const base = dataHome && dataHome.length > 0
            ? dataHome : K4.Sistema.entorno("HOME") + "/.local/share"
        return base + "/applications"
    }

    islandWidth: 720
    islandHeight: 440

    readonly property int count: matches.length
    // `conservarSeleccion` lo usa el refresco periódico: sin él, cada segundo
    // se reponía el índice a cero y la lista te devolvía arriba mientras
    // bajabas con las flechas o la rueda.
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

        //  Este panel es el de las aplicaciones DEL SISTEMA y manda eso: lo
        //  que aporten los plugins va detrás, nunca por delante. Quien abre el
        //  lanzador y escribe «fire» quiere Firefox, y un aporte por bien
        //  intencionado que sea no puede colarse encima de lo que la persona
        //  venía a buscar. Para las cosas de la barra está su propio cajón
        //  (SUPER+SHIFT+Space); aquí salen para que se puedan ENCONTRAR, no
        //  para competir.
        //  Tres maneras de tener icono, en este orden: el que trae el propio
        //  resultado —`imagen` o `glifo`—, el nombre de icono del escritorio
        //  si lo que aporta ES una aplicación instalada, y si no el de su
        //  plugin. Antes solo existía la segunda, así que un aporte de un
        //  plugin salía con el hueco vacío: la fila esperaba un nombre de
        //  icono del escritorio y lo que un plugin tiene es otra cosa. Un
        //  hueco entre filas que sí tienen icono se lee como «esto está a
        //  medias», que era justo lo contrario de lo que pasaba.
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

    //  Avisar a los plugins de lo que se está escribiendo, y repintar cuando
    //  contesten — que puede ser más tarde, si lo suyo cuesta.
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

        //  Uno aportado por un plugin: se lo devolvemos y él sabrá.
        if (entry && entry._enganche) {
            close()
            Enganches.elegir(entry._enganche)
            return
        }

        close()
        abrir(entry)
    }

    // No se usa entry.execute(): eso hereda el directorio de trabajo de la
    // barra, que es la carpeta de configuración de quickshell —de ahí que las
    // terminales abrieran en ~/.config/quickshell/k4—. Se lanza con el
    // directorio que pida la propia entrada y, si no pide ninguno, en casa.
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

    // Una notificación aparta el lanzador.
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
