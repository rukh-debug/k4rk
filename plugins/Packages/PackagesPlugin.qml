//  Package management, as its own plugin.
//
//  It used to live inside the Launcher — a second mode, its processes,
//  its row templates — which meant the Launcher knew pacman and yay
//  existed, and on a machine without them (NixOS, anything not Arch)
//  it tried anyway and warned about it in the log forever. Here it
//  probes first: no backend, no results, no updates, no noise. And the
//  Launcher stays a launcher — its results arrive through the same
//  K4.Lanzador door any plugin uses.
//
//  The flows keep their shape: search reads the local pacman base
//  (~0.3 s) and the AUR RPC through yay (~1.3 s, debounced); install
//  and remove run in the island's terminal session, because root
//  passwords, prompts and PKGBUILDs are things a real terminal is for;
//  updates are counted once for the whole bar with a ten-minute cache.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "packages"
    title: "Packages"
    priority: 76
    colocable: true

    //  A confirm page: it opens when a package row is chosen, asks what
    //  to do, and leaves.
    active: habilitado && abierto
    viewLoaded: abierto

    islandWidth: 460
    islandHeight: 250

    //  The launcher, injected by catalog id: `k4 install foo` lands
    //  there, with the results — this plugin's surface is only the
    //  confirm page.
    property var launcher: null

    property bool abierto: false
    property var paquete: null

    // ── is there a backend at all? ───────────────────────────────
    //
    //  Probed once at birth. Without pacman this plugin contributes
    //  nothing anywhere — no launcher rows, no updates badge — instead
    //  of trying and warning. yay is optional: without it there are
    //  repos but no AUR.
    property bool hayPacman: false
    property bool hayYay: false
    readonly property bool hayBackend: hayPacman

    K4.Process {
        command: ["sh", "-c",
                  "command -v pacman >/dev/null 2>&1 && echo pacman;"
                  + " command -v yay >/dev/null 2>&1 && echo yay"]
        onSalida: function (texto) {
            self.hayPacman = texto.indexOf("pacman") >= 0
            self.hayYay = texto.indexOf("yay") >= 0
            //  The first count of the day, if there is anything to count
            //  with: the badge in the launcher and the page in Apps read
            //  it, and neither should have to ask twice.
            if (self.hayBackend)
                self.refresh(false)
        }
    }

    // ── search ───────────────────────────────────────────────────
    property var repoResults: []
    property var aurResults: []
    property var installedPackages: ({})
    property bool aurSearching: false

    //  Repos first, and within each source the closest names on top.
    readonly property var packageMatches: {
        const q = packageQuery().toLowerCase()
        const scored = []
        const all = repoResults.concat(aurResults)

        for (let i = 0; i < all.length; ++i) {
            const pkg = all[i]
            const name = pkg.name.toLowerCase()
            let score = 0
            if (name === q) score = 0
            else if (name.indexOf(q) === 0) score = 1
            else if (name.indexOf(q) !== -1) score = 2
            else score = 3

            scored.push({
                repo: pkg.repo,
                name: pkg.name,
                version: pkg.version,
                description: pkg.description,
                installed: installedPackages[pkg.name] === true,
                score: score + (pkg.repo === "aur" ? 4 : 0),
                order: i
            })
        }

        scored.sort(function (a, b) {
            if (a.score !== b.score) return a.score - b.score
            return a.order - b.order
        })

        //  CachyOS serves many packages from its own repos too: keep the
        //  first, which is the one pacman would pick by priority.
        const seen = ({})
        const unique = []
        for (let j = 0; j < scored.length; ++j) {
            if (seen[scored[j].name] === true)
                continue
            seen[scored[j].name] = true
            unique.push(scored[j])
        }

        return unique.slice(0, 60)
    }

    function packageQuery() {
        //  pacman -Ss reads the pattern as a regex: strip anything that
        //  could break it or turn into an unexpected wildcard.
        return query.replace(/[^A-Za-z0-9 _.+-]/g, "").trim()
    }

    //  The text being searched, arriving from the launcher's typing.
    property string query: ""

    function parsePackages(text, onlyAur) {
        const lines = text.split("\n")
        const packages = []
        let current = null

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (line.length === 0)
                continue

            if (line.charAt(0) === " " || line.charAt(0) === "\t") {
                if (current && current.description.length === 0)
                    current.description = line.trim()
                continue
            }

            const match = line.match(/^([^\s\/]+)\/(\S+)\s+(\S+)/)
            if (!match) {
                current = null
                continue
            }

            if (onlyAur && match[1] !== "aur") {
                current = null
                continue
            }

            current = {
                repo: match[1],
                name: match[2],
                version: match[3],
                description: ""
            }
            packages.push(current)
        }

        return packages
    }

    //  A search that asked for the wheel while one was still dying:
    //  `parar()` is async, so the restart happens in `onTerminado` —
    //  a `running = true` written right after the kill is a no-op that
    //  eats the newest query.
    property bool repoSearchPendiente: false
    property bool aurSearchPendiente: false

    function runRepoSearch() {
        const q = packageQuery()
        if (q.length < 2) {
            repoResults = []
            return
        }

        repoSearchProcess.command = ["pacman", "-Ss", "--"].concat(q.split(/\s+/))
        if (repoSearchProcess.running) {
            repoSearchPendiente = true
            repoSearchProcess.parar(15)
            return
        }
        repoSearchProcess.running = true
    }

    function runAurSearch() {
        if (!hayYay) {
            aurResults = []
            aurSearching = false
            return
        }

        const q = packageQuery()
        if (q.length < 2) {
            aurResults = []
            aurSearching = false
            return
        }

        aurSearchProcess.command = ["yay", "-Ss", "--aur", "--color=never", "--"].concat(q.split(/\s+/))
        aurSearching = true
        if (aurSearchProcess.running) {
            aurSearchPendiente = true
            aurSearchProcess.parar(15)
            return
        }
        aurSearchProcess.running = true
    }

    function scheduleSearch() {
        repoSearchTimer.restart()
        aurSearchTimer.restart()
    }

    //  The launcher's typing, answered when we can: two speeds, the
    //  local base first and the AUR a beat later.
    function buscar(texto) {
        //  From the host (`k4 install foo`): land in the launcher with
        //  the text already written — the results arrive through the
        //  same door as when the user types them.
        if (launcher && String(texto || "").length > 0 && !abierto)
            launcher.buscar(texto)
        query = String(texto || "")
        if (!hayBackend)
            return
        installedListProcess.running = true
        scheduleSearch()
    }

    //  A row was chosen: the confirm page, not a blind install.
    function elegir(name) {
        for (let i = 0; i < packageMatches.length; ++i)
            if (packageMatches[i].name === name) {
                paquete = packageMatches[i]
                abierto = true
                return
            }
    }

    // ── the launcher contribution ─────────────────────────────────
    //
    //  Below the system's applications, always — that panel is theirs.
    //  The badge (`insignia`) says where a package comes from; the
    //  second line carries version, installed-ness and description,
    //  composed here so the launcher renders one shape for everyone.
    readonly property var filas: {
        const salida = []
        for (let i = 0; i < packageMatches.length; ++i) {
            const p = packageMatches[i]
            salida.push({
                id: p.name,
                titulo: p.name,
                desc: (p.installed ? "Installed · " : "")
                    + p.version + " · " + p.description,
                glifo: p.installed ? 0xF05E0 : 0xF03D7,
                insignia: { texto: p.repo, acento: p.repo === "aur" }
            })
        }
        return salida
    }

    property var enElLanzador: K4.Lanzador {
        plugin: "packages"
        resultados: hayBackend ? self.filas : []
        onBuscando: function (texto) { self.buscar(texto) }
        onElegido: function (id) { self.elegir(id) }
    }

    // ── acting on a package ───────────────────────────────────────
    //
    //  A name arrives from pacman or yay, but it is still data: quote
    //  it before it goes anywhere near a shell, so no quote or shell
    //  character can turn a package into a different command.
    function shellArgument(value) {
        return "'" + String(value || "").replace(/'/g, "'\"'\"'") + "'"
    }

    //  yay cannot run as root (makepkg refuses) and AUR asks for
    //  PKGBUILD review and questions: that is a real terminal's job.
    //  The island session is one — and if it runs short for reading a
    //  PKGBUILD, SUPER+ALT+T takes it out to a window with the
    //  installation inside, uncut.
    function instalar() {
        if (!paquete)
            return
        const name = shellArgument(paquete.name)
        const script = "yay -S --needed -- " + name
            + " && notify-send -a 'Install' " + name + " 'Installed correctly'"
            + " || { notify-send -a 'Install' -u critical " + name + " 'Installation failed';"
            + Consola.cierre + " }"

        Consola.ejecutar(script)
        cerrar()
    }

    //  pacman shows what would be retired and asks before touching
    //  anything. Works for AUR packages too: once installed, they all
    //  live in pacman's local base.
    function desinstalar() {
        if (!paquete || paquete.installed !== true)
            return
        const name = shellArgument(paquete.name)
        const script = "sudo pacman -Rns --confirm -- " + name
            + " && notify-send -a 'Remove' " + name + " 'Removed correctly'"
            + " || { notify-send -a 'Remove' -u critical " + name + " 'Removal failed';"
            + Consola.cierre + " }"

        Consola.ejecutar(script)
        cerrar()
    }

    function cerrar() {
        abierto = false
        paquete = null
    }

    //  The door the host knocks on for Escape and the click-outside.
    function close() { cerrar() }

    // ── updates, counted once for the whole bar ────────────────────
    property int pendientesRepo: -1          // -1 = not looked yet
    property int pendientesAur: -1
    property var nombresPendientes: []
    //  The detail, to be able to choose: [{nombre, de, a, aur}].
    property var detalles: []
    //  What the user has left OUT of this batch, by name. In memory on
    //  purpose: excluding is today's decision, not a policy.
    property var excluidos: ({})
    property real comprobadoEn: 0

    readonly property bool comprobando: repoUpd.running || aurUpd.running
    readonly property int pendientes:
        Math.max(0, pendientesRepo) + Math.max(0, pendientesAur)

    readonly property int marcadas: {
        let n = 0
        for (let i = 0; i < detalles.length; ++i)
            if (!excluidos[detalles[i].nombre])
                ++n
        return n
    }

    //  `checkupdates` builds a temporary base and takes a few seconds,
    //  so it is looked at when a surface that shows it opens, with a
    //  ten-minute cache — freshness has its own button.
    function refresh(forzar) {
        if (!hayBackend || comprobando)
            return
        if (!forzar && comprobadoEn > 0
                && Date.now() - comprobadoEn < 10 * 60 * 1000)
            return
        comprobadoEn = Date.now()
        pendientesRepo = -1
        pendientesAur = -1
        nombresPendientes = []
        detalles = []
        excluidos = ({})
        repoUpd.running = true
        if (hayYay)
            aurUpd.running = true
        else
            pendientesAur = 0
    }

    function alternarExcluida(nombre) {
        const e = Object.assign({}, excluidos)
        if (e[nombre])
            delete e[nombre]
        else
            e[nombre] = true
        excluidos = e
    }

    function apuntar(texto, esAur) {
        const lineas = texto.split("\n").filter(function (l) {
            return l.trim().length > 0
        })
        const nombres = nombresPendientes.slice()
        const lista = detalles.slice()
        for (let i = 0; i < lineas.length; ++i) {
            const partes = lineas[i].trim().split(/\s+/)
            nombres.push(partes[0])
            //  «name 1.2-1 -> 1.3-1», the same shape in both worlds.
            lista.push({ nombre: partes[0], de: partes[1] || "",
                         a: partes[3] || "", aur: esAur })
        }
        nombresPendientes = nombres
        detalles = lista
        if (esAur)
            pendientesAur = lineas.length
        else
            pendientesRepo = lineas.length
    }

    //  Everything at once, in a REAL terminal: the root password, the
    //  questions and the PKGBUILDs are a terminal's business, not a
    //  bar's. When it ends it notifies, and the count forgets itself so
    //  the next look counts the truth.
    //  The chosen batch: a FULL upgrade minus the excluded — in Arch
    //  the only sane way to choose; partial upgrades over an old system
    //  are the classic recipe for breaking it, and leaving a few behind
    //  with --ignore is what pacman ships with.
    function updateSelected() {
        const fuera = []
        for (let i = 0; i < detalles.length; ++i)
            if (excluidos[detalles[i].nombre])
                fuera.push(detalles[i].nombre)
        if (fuera.length === 0) {
            updateAll()
            return
        }
        const script = "yay -Syu --ignore=" + fuera.join(",")
            + " && notify-send -a 'Update' '"
            + "System up to date" + " ("
            + fuera.length + " " + "left for later" + ")'"
            + " || { notify-send -a 'Update' -u critical '"
            + "The update failed" + "';"
            + Consola.cierre + " }"
        Consola.ejecutar(script)
        comprobadoEn = 0
    }

    function updateAll() {
        const script = "yay -Syu"
            + " && notify-send -a 'Update' '"
            + "System up to date" + "'"
            + " || { notify-send -a 'Update' -u critical '"
            + "The update failed" + "';"
            + Consola.cierre + " }"
        Consola.ejecutar(script)
        comprobadoEn = 0
    }

    // ── the machinery ─────────────────────────────────────────────
    K4.Process {
        id: installedListProcess
        command: ["pacman", "-Qq"]

        onSalida: function (texto) {
            const set = ({})
            const names = texto.split("\n")
            for (let i = 0; i < names.length; ++i) {
                const name = names[i].trim()
                if (name.length > 0)
                    set[name] = true
            }
            self.installedPackages = set
        }
    }

    K4.Process {
        id: repoSearchProcess
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            self.repoResults = self.parsePackages(texto, false)
        }

        onTerminado: function (codigo) {
            if (self.repoSearchPendiente) {
                self.repoSearchPendiente = false
                repoSearchProcess.running = true
            }
        }
    }

    K4.Process {
        id: aurSearchProcess
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            self.aurResults = self.parsePackages(texto, true)
            self.aurSearching = false
        }

        onTerminado: function (codigo) {
            self.aurSearching = false
            if (self.aurSearchPendiente) {
                self.aurSearchPendiente = false
                aurSearchProcess.running = true
            }
        }
    }

    Timer {
        id: repoSearchTimer
        interval: 180
        onTriggered: self.runRepoSearch()
    }

    Timer {
        id: aurSearchTimer
        interval: 500
        onTriggered: self.runAurSearch()
    }

    //  Updates, through the wrapped process like everything else: a
    //  plugin imports QtQuick and K4, nothing more — and `salida`
    //  brings the whole text at the end, which is what the count
    //  wants.
    K4.Process {
        id: repoUpd
        command: ["checkupdates"]
        onSalida: function (texto) { self.apuntar(texto, false) }
        //  checkupdates answers 2 when nothing is pending: its way of
        //  saying «up to date», not a failure.
        onTerminado: function (codigo) {
            if (self.pendientesRepo < 0)
                self.pendientesRepo = 0
        }
    }

    K4.Process {
        id: aurUpd
        command: ["yay", "-Qua"]
        onSalida: function (texto) { self.apuntar(texto, true) }
        onTerminado: function (codigo) {
            if (self.pendientesAur < 0)
                self.pendientesAur = 0
        }
    }

    K4.Ipc {
        target: "k4.packages"
        function buscar(q: string): void { self.buscar(q) }
    }

    view: Component {
        PackagesView { plugin: self }
    }
}
