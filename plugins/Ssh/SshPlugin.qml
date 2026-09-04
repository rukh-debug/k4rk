//  Your servers, two keystrokes away.
//
//  You type three letters and you are in. Nothing more — but with two
//  decisions behind it worth having clear:
//
//  **Hosts live in `~/.ssh/config`, not in a database of ours.**
//  That is what makes saving here serve bare `ssh`, `scp`,
//  `git`, `rsync` and anything that speaks ssh too. A vault of our own would
//  be easier to write and would leave you a prisoner of k4.
//
//  **Passwords, none.** Not in the clear, not encrypted by us: you connect
//  with keys and agent, which is how it is done. If you have no key, this
//  creates one for you and sends it to the server — ssh carries the rest,
//  that is what it is there for.
//
//  What IS ours goes in `~/.config/k4term/hosts.json`: what the ssh file
//  cannot say —favourites, when you last went in, tags— and that has no
//  business dirtying a configuration other programs read.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "ssh"
    title: "Servers"
    //  Like the clipboard: it is asked for on purpose, so it wins over
    //  whatever is already up.
    priority: 82
    colocable: true
    active: abierto || cerrando
    viewLoaded: abierto
    grabKeyboard: abierto

    islandWidth: 760
    islandHeight: 460

    property bool abierto: false
    property bool cerrando: false
    property string busqueda: ""
    property int indice: 0

    //  Two faces of the same window: the list to choose from and the form to
    //  configure. You go from one to the other without closing anything,
    //  because opening a dialogue on top of a dialogue is one of the things
    //  that make someone stop using something.
    property string modo: "lista"
    property var borrador: ({})
    property int campo: 0

    //  The fields, in the order they get filled in. The first four go to
    //  `~/.ssh/config` —ssh understands them, and scp, git and everything
    //  else takes advantage—; the last three are ours and live in
    //  `hosts.json`.
    //  The fields of the card. It is a computed list and not a constant for
    //  a reason: the password is only offered if there is a terminal of OURS
    //  —the window one or the island one—, because the automatic typing is
    //  done by the terminal watching its own PTY, and kitty or alacritty
    //  do not do that.
    //  A field that gets filled in and then does nothing is worse than not
    //  having it.
    readonly property bool puedeContrasena: Consola.esNuestra || Consola.hayIsla

    readonly property var campos: puedeContrasena ? camposTodos
        : camposTodos.filter(function (c) { return c.id !== "contrasena" })

    readonly property var camposTodos: [
        { id: "alias",      nombre: "Name",     ayuda: "what you are going to call it",          suyo: false },
        { id: "host",       nombre: "Typewriter",    ayuda: "domain or IP",                  suyo: false },
        { id: "usuario",    nombre: "User",    ayuda: "empty = yours",               suyo: false },
        //  The password goes neither into `ssh_config` nor into `hosts.json`:
        //  those two get opened and copied without thinking. It lives in
        //  `claves.json` with 600, and on the card it is shown as dots unless
        //  you ask to see it (ctrl+O).
        { id: "contrasena", nombre: "Password", ayuda: "if it logs in with a password instead of a key", suyo: false, secreto: true },
        { id: "puerto",     nombre: "Port",     ayuda: "empty = 22",                    suyo: false },
        { id: "clave",      nombre: "Key",      ayuda: "path to the private key, if not the usual one", suyo: false },
        { id: "salto",      nombre: "Jump",      ayuda: "go through another server (ProxyJump)", suyo: false },
        { id: "etiquetas",  nombre: "Tags",  ayuda: "space separated, for searching", suyo: true },
        { id: "alConectar", nombre: "On entry",  ayuda: "a command typed on connecting", suyo: true },
        { id: "tinte",      nombre: "Colour",      ayuda: "red, amber, green, blue, purple — so you know where you are", suyo: true },
        { id: "tuneles",    nombre: "Tunnels",    ayuda: "8080:localhost:80 · socks:1080 · R:9000:localhost:9000", suyo: true }
    ]

    //  Whether the password is shown or goes as dots. It switches off when
    //  the card opens and when it closes: staying on from the previous time
    //  is exactly what nobody expects.
    property bool verClave: false

    function editar(h) {
        verClave = false
        borrador = {
            original: h && !h.rapido ? h.alias : "",
            alias: h ? h.alias : "",
            host: h ? (h.host || h.alias) : "",
            usuario: h ? h.usuario : "",
            contrasena: h ? claveDe(h.alias) : "",
            puerto: h ? h.puerto : "",
            clave: h ? (h.clave || "") : "",
            salto: h ? (h.salto || "") : "",
            etiquetas: h && h.etiquetas ? h.etiquetas.join(" ") : "",
            alConectar: h && h.alConectar ? h.alConectar : "",
            tinte: h && h.tinte ? h.tinte : "",
            tuneles: h && h.tuneles ? h.tuneles : "",
            favorito: h ? h.favorito === true : false
        }
        campo = 0
        modo = "editar"
    }

    function editarActual() {
        const h = lista[indice]
        if (h)
            editar(h)
    }

    function nuevoDesdeBusqueda() {
        const d = comoDestino(busqueda)
        editar(d ? { alias: d.host, host: d.host, usuario: d.usuario,
                     puerto: d.puerto, rapido: true } : null)
    }

    function ponerCampo(id, valor) {
        const nuevo = Object.assign({}, borrador)
        nuevo[id] = String(valor)
        borrador = nuevo
    }

    function moverCampo(paso) {
        campo = Math.max(0, Math.min(campos.length - 1, campo + paso))
    }

    function cancelarEdicion() {
        modo = "lista"
        borrador = ({})
    }

    view: Component { SshView { plugin: self } }

    function open() {
        fSsh.reload()
        fExtras.reload()
        busqueda = ""
        indice = 0
        cerrando = false
        abierto = true
        claves.running = true
        //  `~/.ssh` with the permissions ssh demands. If it is created on
        //  its own by whoever writes the file, it comes out with everyone's
        //  (755) and ssh digs its heels in: to it, a directory others can
        //  look into is no place for keys. Proven — it happened to us when
        //  saving the first one.
        permisos.running = true
    }

    property K4.Process permisos: K4.Process {
        command: ["sh", "-c", "mkdir -p ~/.ssh && chmod 700 ~/.ssh"]
        onTerminado: running = false
    }

    //  And the file, yours only. It carries no secrets, but it says which
    //  machines you enter and as which user, which is nobody's business
    //  either.
    property K4.Process cerrarFichero: K4.Process {
        command: ["sh", "-c", "chmod 600 ~/.ssh/config 2>/dev/null"]
        onTerminado: running = false
    }

    function cerrar() {
        if (!abierto)
            return
        abierto = false
        cerrando = true
        salida.restart()
    }

    //  The door the host knocks on for Escape and the click-outside: by
    //  name, `close`, so the catcher can find it. `cerrar` alone was a
    //  door painted on the wall — the catcher swallowed the click and
    //  nothing closed.
    function close() { cerrar() }

    function alternar() { abierto ? cerrar() : open() }

    Timer {
        id: salida
        interval: 260
        onTriggered: self.cerrando = false
    }

    //  ── what ~/.ssh/config says ─────────────────────────────────
    //
    //  A small and deliberately tolerant parser: of the fifty options ssh
    //  admits, only the five that serve to show and connect get read. The
    //  rest is respected untouched — this file is the user's, not ours.
    readonly property string rutaSsh: K4.Sistema.entorno("HOME") + "/.ssh/config"
    readonly property string rutaExtras: K4.Sistema.entorno("HOME") + "/.config/k4term/hosts.json"

    property var guardados: []
    property var extras: ({})

    property K4.Fichero fSsh: K4.Fichero {
        path: self.rutaSsh
        onLoaded: {
            self.guardados = self.leerSsh()
            //  The script-side `connect` waits for this signal: its alias
            //  is looked up here, with the list already in memory.
            if (self._conectarTrasCargar) {
                self._conectarTrasCargar = ""
                self.buscarParaConectar(self._aliasPendiente)
            }
        }
        //  Without a file there is nothing to read, and that is the normal
        //  thing the first time.
        onLoadFailed: self.guardados = []
    }

    //  What the script-side `connect` leaves on order until the list
    //  finishes re-reading itself.
    property string _conectarTrasCargar: ""
    property string _aliasPendiente: ""

    property K4.Fichero fExtras: K4.Fichero {
        path: self.rutaExtras
        onLoaded: {
            try {
                self.extras = JSON.parse(fExtras.text() || "{}")
            } catch (e) {
                self.extras = ({})
            }
        }
        onLoadFailed: self.extras = ({})
    }

    //  ── the passwords ───────────────────────────────────────────
    //
    //  In their own file and with 600, like in the window: `claves.json`
    //  never leaves here, and neither `ssh_config` nor `hosts.json` touches
    //  it. They go in the clear, with the same treatment as a private key
    //  without a passphrase — on this machine there is no secrets service
    //  that works, and the day there is one, this is the only thing that
    //  changes.
    readonly property string rutaClaves: K4.Sistema.entorno("HOME") + "/.config/k4term/claves.json"

    property var contrasenas: ({})

    property K4.Fichero fClaves: K4.Fichero {
        path: self.rutaClaves
        onLoaded: {
            try {
                self.contrasenas = JSON.parse(fClaves.text() || "{}")
            } catch (e) {
                self.contrasenas = ({})
            }
        }
        onLoadFailed: self.contrasenas = ({})
    }

    function claveDe(alias) {
        const c = contrasenas[String(alias || "")]
        return c ? String(c) : ""
    }

    //  An empty password DELETES whatever one was there: it is the only way
    //  to remove it from the card.
    function guardarClave(alias, clave) {
        const nombre = String(alias || "")
        if (!nombre)
            return
        const nuevo = Object.assign({}, contrasenas)
        if (String(clave).length === 0)
            delete nuevo[nombre]
        else
            nuevo[nombre] = String(clave)
        contrasenas = nuevo
        fClaves.setText(JSON.stringify(contrasenas, null, 2) + "\n")
        cerrarClaves.running = true
    }

    //  The freshly written file comes out with everyone's permissions, and
    //  this is not just any file.
    property K4.Process cerrarClaves: K4.Process {
        command: ["sh", "-c",
                  "chmod 700 ~/.config/k4term 2>/dev/null; " +
                  "chmod 600 ~/.config/k4term/claves.json 2>/dev/null"]
    }

    function leerSsh() {
        const texto = fSsh.text() || ""
        const lista = []
        let actual = null

        texto.split("\n").forEach(function (linea) {
            //  Comments out, and the separator can be a space or an
            //  equals: `Port 22` and `Port=22` are the same thing to ssh.
            const limpia = linea.replace(/#.*$/, "").trim()
            if (limpia.length === 0)
                return
            const corte = limpia.search(/[\s=]/)
            if (corte < 0)
                return
            const clave = limpia.slice(0, corte).toLowerCase()
            const valor = limpia.slice(corte).replace(/^[\s=]+/, "").trim()

            if (clave === "host") {
                //  Patterns (`Host *`) are default values, not places to
                //  go: they are not shown.
                const nombres = valor.split(/\s+/)
                const primero = nombres.length > 0 ? nombres[0] : ""
                actual = null
                if (primero && primero.indexOf("*") < 0 && primero.indexOf("?") < 0) {
                    actual = { alias: primero, host: "", usuario: "", puerto: "",
                               clave: "", salto: "" }
                    lista.push(actual)
                }
                return
            }

            if (!actual)
                return
            if (clave === "hostname") actual.host = valor
            else if (clave === "user") actual.usuario = valor
            else if (clave === "port") actual.puerto = valor
            else if (clave === "identityfile") actual.clave = valor
            else if (clave === "proxyjump") actual.salto = valor
        })

        return lista
    }

    //  ── the list you see ────────────────────────────────────────
    //
    //  Favourites first, then by when you last went in —yesterday's is
    //  usually today's— and last by name. Sorting by use is what makes three
    //  letters enough for the first one to almost always be the right one.
    function conExtras(h) {
        const e = extras[h.alias] || ({})
        return { alias: h.alias, host: h.host || h.alias, usuario: h.usuario,
                 puerto: h.puerto, clave: h.clave, salto: h.salto,
                 favorito: e.favorito === true,
                 ultimo: Number(e.ultimo) || 0,
                 etiquetas: e.etiquetas || [],
                 alConectar: e.alConectar || "",
                 tinte: e.tinte || "",
                 tuneles: e.tuneles || "",
                 rapido: false }
    }

    readonly property var lista: {
        const q = busqueda.trim().toLowerCase()
        const salida = []

        for (let i = 0; i < guardados.length; ++i) {
            //  Agent aliases are not one more place to go: they are the back
            //  door of one that is already in the list. They show as a mark
            //  on its row, not as a row of their own.
            if (esAliasAgentes(guardados[i].alias))
                continue
            const h = conExtras(guardados[i])
            h.agentes = tieneAgentes(h.alias)
            const paja = (h.alias + " " + h.host + " " + h.usuario + " "
                          + h.etiquetas.join(" ")).toLowerCase()
            if (q.length === 0 || paja.indexOf(q) >= 0)
                salida.push(h)
        }

        salida.sort(function (a, b) {
            if (a.favorito !== b.favorito)
                return a.favorito ? -1 : 1
            if (a.ultimo !== b.ultimo)
                return b.ultimo - a.ultimo
            return a.alias.localeCompare(b.alias)
        })

        //  Connection on the fly: if what is typed looks like a destination
        //  and is none of the saved ones, going there directly is offered.
        //  It is what you do the first time, before having anything saved.
        const destino = self.comoDestino(busqueda)
        if (destino) {
            const yaEsta = salida.some(function (h) {
                return h.alias === destino.host || h.host === destino.host
            })
            if (!yaEsta) {
                salida.unshift({ alias: destino.host, host: destino.host,
                                 usuario: destino.usuario, puerto: destino.puerto,
                                 clave: "", salto: "", favorito: false, ultimo: 0,
                                 etiquetas: [], rapido: true })
            }
        }

        return salida
    }

    readonly property int cuantos: lista.length

    //  Does what you have typed look like a site? `usuario@maquina:puerto`,
    //  with the first two parts optional. A dot, or two and a half letters,
    //  is required — no offering «connect to p» while you type.
    function comoDestino(texto) {
        const t = String(texto).trim()
        if (t.length < 3 || /\s/.test(t))
            return null
        const m = t.match(/^(?:([\w.\-]+)@)?([\w.\-]+)(?::(\d+))?$/)
        if (!m)
            return null
        return { usuario: m[1] || "", host: m[2], puerto: m[3] || "" }
    }

    onCuantosChanged: if (indice >= cuantos) indice = Math.max(0, cuantos - 1)

    function mover(paso) {
        if (cuantos === 0)
            return
        indice = Math.max(0, Math.min(cuantos - 1, indice + paso))
    }

    //  ── connect ──────────────────────────────────────────────────
    //
    //  The command is put together the same for both places; the only thing
    //  that changes is where it comes out. On the island it goes through
    //  `K4.Terminal`, which opens a new tab —what you want, so as not to
    //  step on whatever you had half-done.
    function mandato(h) {
        if (!h)
            return ""
        const partes = ["ssh"]
        if (h.puerto)
            partes.push("-p", h.puerto)
        //  A saved host is called by its alias and that is it: ssh itself
        //  puts in the rest by reading its configuration, key and jump
        //  included. Only the on-the-fly destination gets a user in front.
        partes.push(h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias)
        return partes.join(" ")
    }

    function connect(h, enVentana) {
        let guion = mandato(h)
        if (!guion)
            return

        //  What you asked to have run on entry goes behind, on the same
        //  line: that way it goes in through the same door and nobody has to
        //  guess when the session over there has finished starting up.
        if (h.alConectar)
            guion += " -t " + JSON.stringify(String(h.alConectar))

        if (!h.rapido)
            apuntarVisita(h.alias)

        //  The tunnels, along with the connection: they come up here and
        //  they fall when the terminal reports that you left.
        abrirTuneles(h)

        if (enVentana === true) {
            //  Through `Consola` and not bare: it is the one that knows
            //  wezterm and gnome-terminal do not take `-e` like the rest,
            //  and the one that wraps with uwsm so the window does not die
            //  with the bar. It used to be written by hand and both things
            //  failed.
            //  And with the house's emergency exit behind: a window that
            //  closes itself with the «connection refused» half read is good
            //  for nothing. Only if it fails — coming out of a good session,
            //  closing is what one expects.
            K4.Sistema.lanzar(Consola.orden(guion + " || { " + Consola.cierre + " }"))
        } else {
            //  So the terminal knows that what is coming is a connection,
            //  and paints the way in the meantime.
            Consola.conectandoA(h.rapido && h.usuario
                                ? h.usuario + "@" + h.host : h.alias,
                                h.tinte || "",
                                h.rapido ? "" : claveDe(h.alias))
            K4.Terminal.ejecutar(guion)
        }

        cerrar()
    }

    function elegir(enVentana) { conectar(lista[indice], enVentana) }

    //  ── ours: favourites and visits ───────────────────────────
    function tocar(alias, cambio) {
        //  Copy, do not poke inside: reassigning to a `var` property the
        //  same object it already had tells nobody, and the list would stay
        //  the same on screen.
        const nuevo = Object.assign({}, extras)
        nuevo[alias] = Object.assign({}, nuevo[alias] || ({}), cambio)
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")
    }

    function apuntarVisita(alias) { tocar(alias, { ultimo: Date.now() }) }

    function favoritoActual() {
        const h = lista[indice]
        if (h && !h.rapido)
            tocar(h.alias, { favorito: !h.favorito })
    }

    //  ── save and delete in ~/.ssh/config ─────────────────────────
    //
    //  The block gets written and the rest of the file is left untouched:
    //  there can be years-old things in there that are not ours.
    //  Saving what the form holds. It is also EDIT: if that host was already
    //  there —or it has been renamed— its old block goes and the new one is
    //  written, so that there are no two paths to keep up.
    function guardarBorrador() {
        const b = borrador
        const alias = String(b.alias || b.host || "").trim()
        if (!alias || !String(b.host || "").trim())
            return false

        let texto = fSsh.text() || ""
        //  Out with the previous block: its own and, if it has been renamed,
        //  the one that had the new name.
        texto = sinBloque(texto, alias)
        if (b.original && b.original !== alias)
            texto = sinBloque(texto, b.original)

        if (texto.length > 0 && texto.slice(-1) !== "\n")
            texto += "\n"

        let bloque = "\nHost " + alias + "\n"
        bloque += "    HostName " + String(b.host).trim() + "\n"
        //  The fingerprint of a new machine is accepted on its own; one that
        //  CHANGES still stops the connection. Same as in the window, and
        //  for the same reason: this way the question never comes up, and
        //  nobody has to answer it in front of anyone.
        bloque += "    StrictHostKeyChecking accept-new\n"
        const deSsh = [["User", b.usuario], ["Port", b.puerto],
                       ["IdentityFile", b.clave], ["ProxyJump", b.salto]]
        for (let i = 0; i < deSsh.length; ++i) {
            const valor = String(deSsh[i][1] || "").trim()
            if (valor)
                bloque += "    " + deSsh[i][0] + " " + valor + "\n"
        }

        fSsh.setText(texto + bloque)
        cerrarFichero.running = true
        relee.restart()

        //  And ours, which ssh does not know how to save.
        const etiquetas = String(b.etiquetas || "").trim()
        tocar(alias, {
            favorito: b.favorito === true,
            etiquetas: etiquetas ? etiquetas.split(/\s+/) : [],
            alConectar: String(b.alConectar || "").trim(),
            tinte: String(b.tinte || "").trim(),
            tuneles: String(b.tuneles || "").trim()
        })
        guardarClave(alias, String(b.contrasena || ""))
        if (b.original && b.original !== alias) {
            olvidarExtra(b.original)
            guardarClave(b.original, "")
        }

        modo = "lista"
        borrador = ({})
        busqueda = ""
        indice = 0
        return true
    }

    //  The file without that host's block. «Host» and then a separator:
    //  neither `HostName` nor `HostKeyAlias` starts a block, and taking them
    //  for good leaves orphan lines in someone else's file.
    function sinBloque(texto, alias) {
        const lineas = String(texto).split("\n")
        const salida = []
        let dentro = false

        for (let i = 0; i < lineas.length; ++i) {
            const limpia = lineas[i].replace(/#.*$/, "").trim()
            if (/^host[\s=]/i.test(limpia)) {
                const nombres = limpia.slice(4).replace(/^[\s=]+/, "").split(/\s+/)
                dentro = nombres.length > 0 && nombres[0] === alias
            }
            if (!dentro)
                salida.push(lineas[i])
        }

        while (salida.length > 0 && salida[salida.length - 1].trim() === "")
            salida.pop()
        return salida.length > 0 ? salida.join("\n") + "\n" : ""
    }

    //  `text()` does not see what was just written with `setText`: it has to
    //  reload and let `onLoaded` rebuild the list. Reading it right there
    //  left the list at zero with the file already written.
    Timer {
        id: relee
        interval: 120
        onTriggered: self.fSsh.reload()
    }

    function olvidarExtra(alias) {
        const nuevo = Object.assign({}, extras)
        delete nuevo[alias]
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")
    }

    //  Saving what was typed on the fly is not write-it-and-done: the form
    //  opens with what is known and the rest gets completed. It used to be
    //  saved blind under the machine's name with no way to touch anything
    //  else, which is just what you want to do next.
    function guardarActual() {
        const h = lista[indice]
        if (h)
            editar(h)
    }

    function borrarActual() {
        const h = lista[indice]
        if (!h || h.rapido)
            return

        fSsh.setText(sinBloque(fSsh.text() || "", h.alias))
        relee.restart()

        const nuevo = Object.assign({}, extras)
        delete nuevo[h.alias]
        extras = nuevo
        fExtras.setText(JSON.stringify(extras, null, 2) + "\n")
        //  And its password: keeping the secret of a machine you no longer
        //  go to is the worst of both worlds.
        guardarClave(h.alias, "")

        indice = Math.max(0, Math.min(indice, cuantos - 2))
    }

    //  ── the key, if you have none ────────────────────────────
    //
    //  Without a key, getting in asks for a password every time. It can be
    //  saved —the field is there, and it goes to `claves.json` with 600— but
    //  a key is better: it does not travel, it does not expire, and it does
    //  not have to be typed. Creating one and sending it to the server is
    //  the step that fixes it for good, and it is done IN THE
    //  TERMINAL on purpose: `ssh-keygen` asks for the passphrase and
    //  `ssh-copy-id` for the server's password, and that you have to type
    //  yourself, not one of our dialogues.
    property int cuantasClaves: -1

    property K4.Process claves: K4.Process {
        command: ["sh", "-c", "ls -1 ~/.ssh/*.pub 2>/dev/null | wc -l"]
        onSalida: function (texto) { self.cuantasClaves = parseInt(texto.trim(), 10) || 0 }
        onTerminado: running = false
    }

    readonly property bool sinClaves: cuantasClaves === 0

    function crearClave() {
        const h = lista[indice]
        const destino = h ? (h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias) : ""
        const crear = "ssh-keygen -t ed25519 -C k4term"
        K4.Terminal.ejecutar(destino ? crear + " && ssh-copy-id " + destino : crear)
        cerrar()
    }

    //  ── the agents' door ──────────────────────────────────
    //
    //  An agent running in the terminal already has your shell, so it can
    //  launch `ssh` on its own; what it cannot do is type a password. Giving
    //  it yours would be giving it EVERYTHING, so it is given something else:
    //  a key of its own (`~/.ssh/k4-agentes`), an alias of its own
    //  (`casa-agentes`) and, on the server, whatever you choose to leave it
    //  in its `authorized_keys`. It is revoked by deleting one line there,
    //  without touching anything of yours.
    //
    //  What needs doing THERE —sending the key, or removing it— runs in the
    //  terminal, in plain sight: it asks for your password and touches its
    //  file, and those two things are not done behind anyone's back.
    readonly property string claveAgentes: K4.Sistema.entorno("HOME") + "/.ssh/k4-agentes"

    //  The key's stamp, which is what allows removing it from the server
    //  without guessing: that mark is looked for in its `authorized_keys`
    //  and the line is deleted. It HAS to come out the same here and in the
    //  window —the same file, not `$HOSTNAME`, which in the bar's session
    //  arrives empty and left two different stamps: the one put in by one
    //  side was not found by the other.
    property string nombreEquipo: "k4"

    property K4.Fichero fEquipo: K4.Fichero {
        path: "/etc/hostname"
        onLoaded: {
            const t = String(fEquipo.text() || "").trim()
            if (t.length > 0)
                self.nombreEquipo = t
        }
    }

    readonly property string marcaAgentes: "k4-agentes@" + nombreEquipo

    function aliasAgentes(alias) { return String(alias || "") + "-agentes" }

    function esAliasAgentes(alias) {
        return String(alias || "").slice(-8) === "-agentes"
    }

    function tieneAgentes(alias) {
        const buscado = aliasAgentes(alias)
        for (let i = 0; i < guardados.length; ++i)
            if (guardados[i].alias === buscado)
                return true
        return false
    }

    function alternarAgentes() {
        const h = lista[indice]
        if (!h || h.rapido)
            return

        const marca = marcaAgentes
        let texto = fSsh.text() || ""

        if (tieneAgentes(h.alias)) {
            fSsh.setText(sinBloque(texto, aliasAgentes(h.alias)))
            cerrarFichero.running = true
            relee.restart()
            //  And over there: out with the line for that key. It is looked
            //  up by its mark, which is why it carries one.
            K4.Terminal.ejecutar("ssh " + h.alias
                + " \"sed -i '/" + marca + "/d' ~/.ssh/authorized_keys\"")
            cerrar()
            return
        }

        texto = sinBloque(texto, aliasAgentes(h.alias))
        if (texto.length > 0 && texto.slice(-1) !== "\n")
            texto += "\n"

        let bloque = "\nHost " + aliasAgentes(h.alias) + "\n"
        bloque += "    HostName " + String(h.host || h.alias) + "\n"
        if (h.usuario)
            bloque += "    User " + h.usuario + "\n"
        if (h.puerto)
            bloque += "    Port " + h.puerto + "\n"
        bloque += "    IdentityFile " + claveAgentes + "\n"
        //  Without `IdentitiesOnly` ssh offers your keys too, and the agent
        //  would get in as you: just what this door is here to prevent.
        bloque += "    IdentitiesOnly yes\n"
        //  And that it asks NOTHING: this door is for what has nobody in
        //  front of it, so a key that is no good has to fail on the spot,
        //  not leave the agent waiting for a prompt it cannot see.
        bloque += "    BatchMode yes\n"
        bloque += "    StrictHostKeyChecking accept-new\n"

        fSsh.setText(texto + bloque)
        cerrarFichero.running = true
        relee.restart()

        K4.Terminal.ejecutar(
            "[ -f " + claveAgentes + " ] || ssh-keygen -t ed25519 -N '' -C '"
            + marca + "' -f " + claveAgentes
            + "; ssh-copy-id -i " + claveAgentes + ".pub " + h.alias)
        cerrar()
    }

    //  ── the tunnels ───────────────────────────────────────────
    //
    //  A tunnel is another `ssh` running on its own (`ssh -N`), so it lives
    //  outside the terminal: it takes no tab, it cannot be seen, and for
    //  that very reason it gets forgotten. The pill is the house's place for
    //  what runs behind —that is where the long commands and the agents
    //  are—, so there they go: each tunnel its own, and pressing it kills
    //  it.
    //
    //  They come up on connect and fall on exit. They could live on their
    //  own, but then you would have to remember to turn them off; tied to
    //  the session, they do what one expects without thinking about it.
    property ListModel tuneles: ListModel {}

    //  `8080:localhost:80` (local), `R:9000:localhost:9000` (remote),
    //  `socks:1080` or `D:1080` (SOCKS). Separated by spaces or commas.
    function leerTuneles(texto) {
        const salida = []
        String(texto || "").split(/[\s,]+/).forEach(function (trozo) {
            if (!trozo)
                return
            const bajo = trozo.toLowerCase()
            if (bajo.indexOf("socks:") === 0 || bajo.indexOf("d:") === 0) {
                const puerto = trozo.split(":").pop()
                if (puerto)
                    salida.push({ bandera: "-D", spec: puerto, mote: "socks " + puerto })
                return
            }
            if (bajo.indexOf("r:") === 0) {
                const spec = trozo.slice(2)
                if (spec)
                    salida.push({ bandera: "-R", spec: spec, mote: "↰ " + spec.split(":")[0] })
                return
            }
            const spec = bajo.indexOf("l:") === 0 ? trozo.slice(2) : trozo
            if (spec.indexOf(":") > 0)
                salida.push({ bandera: "-L", spec: spec, mote: "↳ " + spec.split(":")[0] })
        })
        return salida
    }

    function abrirTuneles(h) {
        if (!h || !h.tuneles)
            return
        const destino = h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias
        const lista = leerTuneles(h.tuneles)
        for (let i = 0; i < lista.length; ++i) {
            tuneles.append({ destino: destino, bandera: lista[i].bandera,
                             spec: lista[i].spec, mote: lista[i].mote })
        }
    }

    function cerrarTuneles(destino) {
        for (let i = tuneles.count - 1; i >= 0; --i)
            if (tuneles.get(i).destino === String(destino))
                tuneles.remove(i)
    }

    property Connections alSalir: Connections {
        target: Consola
        function onSalioDe(destino) { self.cerrarTuneles(destino) }
    }

    //  Each tunnel, its process and its pill. The `Instantiator` creates and
    //  destroys them with the list, which is what makes closing the
    //  connection shut them off without having to go killing anything by
    //  hand.
    property Instantiator tuneleros: Instantiator {
        model: self.tuneles

        delegate: QtObject {
            id: tunel
            required property string destino
            required property string bandera
            required property string spec
            required property string mote

            readonly property string clave: "terminal.tunel." + destino + "." + spec

            //  Reconnection: a tunnel that falls because of a network cut
            //  must come back on its own, but carefully — if the failure is
            //  on the other side (port taken, permission denied), retrying
            //  every second is a machine gun. It waits a little longer each
            //  time, up to half a minute.
            property int intentos: 0

            property var proceso: K4.Process {
                command: ["ssh", "-N", tunel.bandera, tunel.spec, tunel.destino]
                running: true
                onTerminado: {
                    running = false
                    tunel.intentos += 1
                    reintento.interval = Math.min(30000, 2000 * tunel.intentos)
                    reintento.restart()
                }
            }

            property var reintento: Timer {
                onTriggered: tunel.proceso.running = true
            }

            Component.onCompleted: K4.Pildora.registrar(
                tunel.clave, tunel.mote, 0xF0BBB, Theme.green, 27, true)
            Component.onDestruction: {
                tunel.reintento.stop()
                tunel.proceso.running = false
                K4.Pildora.quitar(tunel.clave)
            }
        }
    }

    //  ── taking our integration to the server ──────────────────
    //
    //  The blocks, the margin rule and the «it is waiting for you» notice
    //  work because the shell here emits them. Over SSH, the shell is the
    //  one from THERE: without this, entering a server switches off half the
    //  terminal.
    //
    //  It is sent through a pipe (`k4term --integracion zsh | ssh …`)
    //  instead of copying a file: that way there is no need to know where
    //  the repo lives, which in an installed bar nobody knows. And it runs
    //  IN THE TERMINAL because it may ask you for the server's password.
    function llevarIntegracion() {
        const h = lista[indice]
        if (!h || !Consola.esNuestra)
            return
        const destino = h.rapido && h.usuario ? h.usuario + "@" + h.host : h.alias

        //  The rc line carries its own mark so it can be taken out later,
        //  and it is checked before writing: installing it twice would leave
        //  the shell emitting every marker twice over.
        const guion =
            "set -e; " +
            "echo '→ copying the integration to " + destino + "'; " +
            "k4term --integracion zsh  | ssh " + destino +
                " 'mkdir -p ~/.config/k4term && cat > ~/.config/k4term/k4term.zsh'; " +
            "k4term --integracion fish | ssh " + destino +
                " 'cat > ~/.config/k4term/k4term.fish'; " +
            "ssh -t " + destino + " '" +
                "for par in \"$HOME/.zshrc:zsh\" \"$HOME/.config/fish/config.fish:fish\"; do " +
                "  rc=${par%:*}; cual=${par#*:}; " +
                "  [ -f \"$rc\" ] || continue; " +
                "  grep -q k4term/k4term.$cual \"$rc\" && { echo \"✓ $cual already had it\"; continue; }; " +
                "  printf \"\\n#  k4term: shell integration\\n\" >> \"$rc\"; " +
                "  printf \". ~/.config/k4term/k4term.%s\\n\" \"$cual\" >> \"$rc\"; " +
                "  echo \"✓ $cual integrated\"; " +
                "done'; " +
            "echo '→ done: log in again and the blocks work there too'"

        K4.Terminal.ejecutar(guion + K4.Terminal.cierre)
        cerrar()
    }

    //  Pressing a tunnel's pill closes it: it is what one expects of
    //  something that is there precisely to remind you it is still open.
    property Connections clicsPildora: Connections {
        target: K4.Pildora
        function onInvocado(id) {
            const marca = "terminal.tunel."
            if (String(id).indexOf(marca) !== 0)
                return
            for (let i = self.tuneles.count - 1; i >= 0; --i) {
                const t = self.tuneles.get(i)
                if ("terminal.tunel." + t.destino + "." + t.spec === String(id)) {
                    self.tuneles.remove(i)
                    return
                }
            }
        }
    }

    K4.Ipc {
        target: "k4.ssh"

        //  The picker, which is what this opens for.
        function open(): void { self.open() }
        function close(): void { self.close() }
        function toggle(): void { self.alternar() }

        //  And to connect by script, without opening anything: for your own
        //  keybinds or to call it from somewhere else. The list is re-read
        //  deferred —the lookup lives in onLoaded— because `reload()` is
        //  asynchronous and what is already in memory can be older than the
        //  host that was just added.
        function connect(alias: string): void {
            self._aliasPendiente = alias
            self._conectarTrasCargar = "1"
            self.fSsh.reload()
        }
    }

    //  The deferred part of the `connect` above: the list already re-read.
    function buscarParaConectar(alias) {
        const h = guardados.find(function (x) { return x.alias === alias })
        if (h)
            conectar(conExtras(h), false)
    }
}
