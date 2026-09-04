//  The house terminal, seen from the bar.
//
//  k4term lives outside (Rust, libghostty + GPUI) and this is its embassy:
//  it opens windows over IPC and turns what the terminal reports into
//  notifications.
//
//  The plugin never occupies the island. It is a service piece shaped like
//  a plugin, and that is fine: it turns on and off from Settings like
//  everything else, and its IPC target unregisters itself when off.
//
//      quickshell ipc -p shell.qml call k4.term abrir
//      quickshell ipc -p shell.qml call k4.term aqui
//      quickshell ipc -p shell.qml call k4.term ejecutar "yay -Syu"

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "terminal"
    title: "Terminal"
    //  Above the player and the clock, below the launcher: if you are
    //  typing in it, no song takes it away from you.
    priority: 75
    colocable: true
    active: abierto

    //  ── the island terminal ───────────────────────────────────────
    //
    //  For the quick things: a `systemctl restart`, a `git status`, checking
    //  on something. The session lives in k4term-isla, outside the bar, so
    //  closing the view stops nothing and reopening brings you back where
    //  you were.
    property bool abierto: false

    //  The cursor trail and the font are said by the SESSION, which reads
    //  k4term's settings and watches them: the island and the window use the
    //  same by touching a single place. They are declared below, next to
    //  the list.

    grabKeyboard: abierto
    islandWidth: 900

    //  The island grows with what is inside it, which is what one expects
    //  of it: a three-line `ls` has no business opening a drawer half a
    //  monitor tall.
    //
    //  Watch the loop, which is the trap here: the island decides how many
    //  rows the PTY has, so «what is written» can never exceed what fits,
    //  and measuring content to decide size leads nowhere. What works is
    //  the other way around: it opens small, widens when it FILLS, and
    //  folds when half empty —after a `clear`, say—. With margin between
    //  the two conditions so it does not jitter.
    //
    //  The font measurement is taken HERE and the view uses it from here,
    //  even though the view is the one painting. Keeping it in both places
    //  was expensive: the island's height was computed with 18 while the
    //  view divided by the real metric, 17. Out came one row more than
    //  fit, meaning `usadas` never reached `filas_n`, meaning the grow
    //  condition NEVER held: the island stayed at its minimum size
    //  forever, and a full-screen program —claude, vim— painted squashed
    //  into seven rows with the cursor at the bottom of the box.
    //
    //  The margin and the foot take what they take; the rest is whole
    //  rows. The margin, the foot and the tab strip on top. What is left
    //  over is whole rows.
    readonly property int chrome: 62
    readonly property real altoLinea: Math.ceil(metricas.height)

    //  Cell width, in WHOLE pixels, recomputed when the font changes. The
    //  first two lines of the block are not decoration, and they were
    //  expensive: `advanceWidth` is a FUNCTION, and a QML binding only
    //  re-evaluates when a PROPERTY it read changes. Without naming the
    //  family and the size, this computed ONCE —with the font still
    //  unresolved— and kept the fallback typography's width forever: a
    //  13.8 px cell for a letter that measures 7.8. The text painted at
    //  its width and the cursor at almost double, so it drifted right the
    //  longer the line.
    //
    //  And whole because that is how it paints: with `NativeRendering`
    //  advances round to pixels, meaning nobody honors a fractional cell.
    readonly property real anchoCelda: {
        const _familia = metricas.font.family
        const _cuerpo = metricas.font.pixelSize
        return Math.max(1, Math.round(metricas.advanceWidth("M")))
    }

    property FontMetrics metricas: FontMetrics {
        font.family: self.fuente
        font.pixelSize: self.cuerpo
    }

    readonly property int filasMinimas: 6
    readonly property int filasMaximas: 26

    //  Growing and folding, at a steady pace and with ONE number.
    //
    //  This used to go in shoves: every full frame that arrived raised the
    //  target a few rows and an animation ran behind it. And it showed,
    //  because the target only moves when a frame arrives —every 30 to
    //  120 ms—: the animation caught up, stopped, and waited for the next
    //  shove. Measured over a single growth: 555, 111, 938 and 733 px/s.
    //  That is the staircase.
    //
    //  Worse was the other thing: the animated height and the PTY's rows
    //  were computed separately, so the box and the text inside did not
    //  move together —one shrank, then the other.
    //
    //  Now there is one number, `filasReales`, advancing toward `objetivo`
    //  at a fixed pace. BOTH THINGS come out of it: the island's height
    //  and the rows asked of the session. Coming from the same place they
    //  cannot fall out of step, and advancing continuously there are no
    //  stairs. Growing is one thing and folding is another. Growing
    //  accompanies something happening —the command's output arriving—
    //  and wants its own pace. When folding there is nothing left to
    //  watch: what is left over is empty space, and dragging it along at
    //  the same speed takes long.
    readonly property real filasPorSegundo: 22
    readonly property real filasPorSegundoAlRecoger: 65
    property real velocidad: filasPorSegundo

    property real objetivo: filasMinimas
    property real filasReales: objetivo
    readonly property int filasDeseadas: Math.max(filasMinimas, Math.round(filasReales))

    //  The animation engine moves it, not a Timer, and that is not a
    //  detail: a 16 ms Timer does not fire sixty times a second —measured,
    //  it came out under half the asked pace—, while this rides the
    //  screen's refresh.
    //
    //  And in a `Behavior`, not in `SmoothedAnimation on`: that second
    //  form runs ONCE and switches off when done, so changing the target
    //  afterwards did nothing. It was plain to see — the island grew
    //  halfway and planted itself there.
    Behavior on filasReales { SmoothedAnimation { velocity: self.velocidad } }

    onMarcoChanged: {
        if (!marco)
            return

        //  The first thing to arrive from the other side turns off the
        //  connection path. Rule of thumb, worth saying: what comes in the
        //  first quarter second is the echo of what was just typed; past
        //  that, any output —the far prompt or a «connection refused»—
        //  means the wait is over. And a cap, in case nothing ever
        //  arrives.
        //  And if the `ssh` has ended, leave the place: color gone and
        //  pill gone. The command's block says so —this side's shell, not
        //  the far one— and it counts the same for a clean exit as for a
        //  network cut.
        if (sesion && sesion.conectadoA && marco.ultimo
                && marco.ultimo.estado !== "corre") {
            salirDe(claveIsla(sesion.numero))
            mandar({ que: "tinte", color: "" })
            Consola.salioDe(sesion.conectadoA)
            sesion.conectadoA = ""
        }

        //  With a command still to be typed nothing switches off: the
        //  frames arriving now are the newborn session putting out its
        //  prompt, not anybody's answer. Switching off here left the path
        //  unseen forever.
        if (Consola.conectando && !pendiente) {
            const esperado = Date.now() - Consola.conectandoDesde
            if (esperado > 250)
                Consola.conectado()
        }
        //  «Full» means reaching the last row or the one before. The
        //  one-before is not a concession: a full-screen program ALWAYS
        //  fits the space it is given, so it never overflows and never
        //  asks for more — and if its last row stays blank, like
        //  claude's dialog, with the strict condition the island would
        //  never grow and the program would stay cramped forever.
        if (marco.usadas >= marco.filas_n - 1) {
            //  While it stays full, upward without stopping. The moment
            //  it stops being, it stays where it is: no target to chase
            //  in jumps, only a direction.
            recoger.stop()
            velocidad = filasPorSegundo
            objetivo = filasMaximas
        } else if (marco.usadas * 2 <= marco.filas_n && filasReales > filasMinimas) {
            //  Emptied completely —a `clear`, leaving a program— it folds
            //  NOW: there is nothing to confirm, and waiting there was
            //  what felt like an odd delay before the box reacted.
            //
            //  Half empty is another thing and that one does wait a
            //  beat: pressing Enter the screen is left for an instant
            //  with less than it had before the command's output
            //  arrives, and reacting to that gap gave a downward yank
            //  right before growing —measured: 26 px down and 73 up
            //  right after—. Waiting two frames is enough to tell them
            //  apart.
            if (marco.usadas <= 2) {
                recoger.stop()
                encoger()
            } else {
                objetivo = filasReales
                recoger.restart()
            }
        } else {
            recoger.stop()
            objetivo = filasReales
        }
    }

    function encoger() {
        velocidad = filasPorSegundoAlRecoger
        objetivo = Math.max(filasMinimas, marco.usadas + 2)
    }

    Timer {
        id: recoger
        interval: 180
        onTriggered: {
            if (!self.marco)
                return
            if (self.marco.usadas * 2 <= self.marco.filas_n
                    && self.filasReales > self.filasMinimas)
                self.encoger()
        }
    }

    //  Every new session starts folded.

    //  No animation on top: `filasReales` ALREADY moves continuously, and
    //  putting an animation behind it would only add delay between the
    //  height and the rows asked of the session, which is exactly what
    //  kept the box and the text out of step.
    islandHeight: Math.min(560, chrome + filasReales * altoLinea)
    closeOnHoverExit: false
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    view: Component { TerminalIslaView { plugin: self } }

    function mandar(orden) {
        if (sesion)
            sesion.mandar(orden)
    }

    function cerrar() { abierto = false }

    //  The door the host knocks on for Escape and the click-outside.
    //  Without it the catcher swallowed the click without closing
    //  anything: the worst of both worlds. The session does not die —
    //  closing the view is closing the view.
    function close() { cerrar() }

    //  ── the clipboard ─────────────────────────────────────────────
    //
    //  The session has none: it is not a window, it does not talk to the
    //  compositor and it cannot. The bar has it, so copy and paste go
    //  through here — and as a bonus, what is copied enters the house's
    //  copy history like any other copy.
    //
    //  For pasting the compositor is asked at the moment and not the
    //  service's cache: between what the service last saw and what is
    //  there now there may be another application's copy, and pasting
    //  the old one is among the things one does not forgive.
    function alCopiar(texto) {
        if (texto)
            K4.Sistema.copiar(texto)
    }

    function pegar(primaria) {
        pegador.primaria = primaria === true
        pegador.running = true
    }

    property K4.Process pegador: K4.Process {
        property bool primaria: false
        command: primaria ? ["wl-paste", "--primary", "--no-newline"]
                          : ["wl-paste", "--no-newline"]
        onSalida: function (texto) {
            if (texto)
                self.mandar({ que: "pegar", valor: texto })
        }
        onTerminado: running = false
    }

    //  The primary is set on releasing the selection, as in any
    //  old-school terminal: you select, you paste with the middle
    //  button.
    function copiarPrimaria(texto) {
        if (texto)
            K4.Sistema.lanzar(["wl-copy", "--primary", "--", String(texto)])
    }

    //  What the session answers when asked for a piece of history. The
    //  reason says what it came for: without it, a copy and a note would
    //  arrive identical.
    function alRecibirTexto(contenido, motivo) {
        if (motivo === "primaria") {
            copiarPrimaria(contenido)
            return
        }
        if (!contenido) {
            K4.Sistema.avisar("Terminal", "Nothing to copy", false)
            return
        }
        K4.Sistema.copiar(contenido)
    }

    //  A link written in the terminal, opened with whatever the desktop
    //  has set. Bare `www.` is an address for nobody: without a scheme,
    //  xdg-open would hand it to the browser as if it were a file.
    function abrirEnlace(url) {
        const limpio = String(url || "")
        if (!limpio)
            return
        K4.Sistema.abrir(limpio.indexOf("www.") === 0 ? "https://" + limpio : limpio)
    }

    //  ── search ────────────────────────────────────────────────────
    //
    //  Digging through history is the session's job, it is the one
    //  holding it; here only what is searched and whether the last one
    //  landed on something are kept, so the box can say so. The yellow
    //  on screen is painted by the view from what it sees, asking
    //  nothing.
    property string aguja: ""
    property bool sinRastro: false
    property int filaHallada: -1

    function buscar(hacia) {
        if (!aguja)
            return
        mandar({ que: "buscar", texto: aguja, hacia: hacia })
    }

    function hallazgo(hay, fila) {
        sinRastro = !hay
        filaHallada = hay ? fila : -1
    }

    //  To today's note: the last command with its output, or the whole
    //  session. If no Edinot is open, the session says so and it comes
    //  out here as a notification.
    function anotar(entera) { mandar({ que: "nota", entera: entera === true }) }

    //  ── quiet mode ────────────────────────────────────────────────
    //
    //  Dims what came before the last command. In a two-hour agent
    //  session, knowing where the new part starts is worth more than
    //  any color. It starts as k4term's settings say and turns on and
    //  off with the key, which is how it gets used: for a while, not
    //  forever.
    property bool tranquilo: conf.tranquilo === "si" || conf.tranquilo === "1"
    function alternarTranquilo() { tranquilo = !tranquilo }

    //  ── running a house command in here ───────────────────────────
    //
    //  Updating the system used to open a separate window. With this
    //  around, the right thing is to see it in the island: it surfaces
    //  on its own, shows it, and if you close it the command keeps
    //  running — which is exactly what a session that does not depend
    //  on the view is for.
    //
    //  It offers itself to Consola instead of Consola looking for us: a
    //  service cannot depend on a plugin existing, and this one turns
    //  off from Settings like any other. When off, the offer is
    //  withdrawn and everything opens in a window again.
    Component.onCompleted: Consola.registrarIsla(function (guion) {
        self.correrAqui(guion)
    })
    Component.onDestruction: Consola.registrarIsla(null)

    function correrAqui(guion) {
        if (!Consola.hayIsla) {
            K4.Sistema.lanzar(Consola.orden(guion))
            return
        }
        //  House commands ALWAYS go to a new terminal, not the one in
        //  front of you: if you were halfway through claude, dropping a
        //  `yay -Syu` on top would be a dirty trick.
        nueva()
        abierto = true
        mandar({ que: "pinta" })
        //  Always with a wait, because it is always a newborn session:
        //  text arriving before the shell puts out its prompt is
        //  repeated raw by the tty and the command shows twice, once
        //  loose at the top and once in its place.
        pendiente = guion
        esperarPrompt.restart()
    }

    property string pendiente: ""

    function escribirMandato(guion) {
        //  Ctrl-U in front: if you had left something half-written, the
        //  command would paste behind it and some chimera would come out.
        //
        //  And RETURN at the end, not a newline. They look the same and
        //  are not: the Enter key sends a return, and the shell's line
        //  editor expects that. With `\n` the command stays written and
        //  unexecuted — checked live, the whole line sitting there.
        //  If the connection carries a password, the terminal keeps it
        //  BEFORE the command goes out: when the far side asks for it,
        //  the terminal types it. It is neither stored nor shown here;
        //  the moment it is handed over, it is erased.
        if (Consola.claveConexion) {
            //  If the binary on the other side predates this, it swallows
            //  the order silently and the password never gets typed. It
            //  is said out loud, because waiting without knowing why is
            //  the worst that can happen here.
            if (sesion && sesion.sabeClaves) {
                mandar({ que: "clave", valor: Consola.claveConexion })
            } else {
                K4.Sistema.lanzar(["notify-send", "-a", "k4",
                                   "Update k4term",
                                   "This version of k4term-isla cannot type passwords: the connection will ask you by hand."])
            }
            Consola.claveConexion = ""
        }

        mandar({ que: "texto", valor: String.fromCharCode(0x15) + guion + "\r" })

        //  The quarter-second of grace counts from HERE, which is when
        //  the command truly leaves: the island session is brand new and
        //  waits for the shell to put out its prompt, so between
        //  pressing Enter and this almost half a second passes — and the
        //  echo arrived «late» and switched the path off before it
        //  started.
        if (Consola.conectando) {
            Consola.conectandoDesde = Date.now()

            //  The place is noted on the session —not the plugin— because
            //  there can be several, each on its own server.
            if (sesion) {
                sesion.conectadoA = Consola.conectando
                if (Consola.tinteConexion)
                    mandar({ que: "tinte", color: Consola.tinteConexion })
                entrarEn(claveIsla(sesion.numero), Consola.conectando)
            }
        }
    }

    Timer {
        id: esperarPrompt
        interval: 450
        onTriggered: {
            if (!self.pendiente)
                return
            self.escribirMandato(self.pendiente)
            self.pendiente = ""
        }
    }

    function toggle() {
        //  Without k4term-isla there is no mini-terminal —it speaks a
        //  protocol that is ours— but there is no reason to do nothing
        //  either: a window opens with whatever terminal there is.
        if (!Consola.hayIsla) {
            K4.Sistema.lanzar(Consola.abrir(""))
            return
        }
        //  The first session does not start until you ask for it:
        //  whoever does not use the island terminal does not pay a
        //  single process.
        if (vivas.length === 0)
            nueva()
        abierto = !abierto
        if (abierto)
            mandar({ que: "pinta" })
    }

    //  Taking it big: the session MOVES, it is not copied. It is asked
    //  to offer its PTY over a socket and a window opens to collect it;
    //  whatever was running inside —an agent, a `make`— carries on as
    //  if nothing, because what changes hands is the master and what
    //  ties it is the slave, which is untouched.
    //
    //  Without k4term there is nobody to hand it to: then whatever
    //  there is opens, which is what was done before this existed.
    function sacar() {
        if (!sesion || !Consola.esNuestra) {
            K4.Sistema.lanzar(Consola.abrir(""))
            return
        }
        mandar({ que: "emigrar" })
    }

    //  The session is on the socket already: the window that takes it
    //  away opens. On picking it up, the island's process turns itself
    //  off and the tab goes with it.
    function alEmigrar(socket) {
        if (!socket)
            return
        K4.Sistema.lanzar([Consola.binario, "--heredar", socket])
        abierto = false
    }

    //  ── the sessions ──────────────────────────────────────────────
    //
    //  Several, not one. Having claude in one and codex in another is
    //  exactly what a terminal that lives outside the view is for: you
    //  switch between them and both keep running.
    //
    //  The list is a ListModel and not a counter because the middle one
    //  must be closable: with a number, the Instantiator would always
    //  take away the last one.
    property ListModel listaSesiones: ListModel {}
    property var vivas: []
    property int actual: 0
    property int contador: 0

    readonly property var sesion: vivas.length > 0 && actual < vivas.length
        ? vivas[actual] : null

    readonly property var marco: sesion ? sesion.marco : null
    readonly property int estela: sesion ? sesion.estela : 8
    readonly property string fuente: sesion ? sesion.fuente : "MesloLGS Nerd Font Mono"
    readonly property bool arrancado: vivas.length > 0

    //  The font size comes from k4term's settings —the same as the
    //  window's— and on top goes this view's zoom, which belongs here
    //  and to now: enlarging to read for a while is not changing your
    //  preference. It is kept across openings because whoever enlarges
    //  it usually wants it enlarged.
    readonly property int cuerpoBase: sesion ? sesion.cuerpo : 13
    property int zoom: 0
    readonly property int cuerpo: Math.max(8, Math.min(30, cuerpoBase + zoom))

    function acercar(cuanto) { zoom = Math.max(-5, Math.min(17, zoom + cuanto)) }
    function zoomNormal() { zoom = 0 }

    property Instantiator criadero: Instantiator {
        model: self.listaSesiones
        delegate: SesionIsla {
            required property int sid
            required property string socket
            numero: sid
            //  If it comes with a socket, this session does not start a
            //  shell: it adopts the one a window has just let go.
            heredar: socket
            onDonde: function (ruta) { self.alDecirDonde(ruta) }
            onDifunta: self.alMorir(numero)
            onTrabajo: function (estado, mandato, salida, segundos) {
                self.alTrabajar(numero, estado, mandato, salida, segundos)
            }
            onCampana: function (titulo) { self.alLlamar(numero, titulo) }
            onPortapapeles: function (texto) { self.alCopiar(texto) }
            onTexto: function (contenido, motivo) { self.alRecibirTexto(contenido, motivo) }
            onBuscado: function (hay, fila) { self.hallazgo(hay, fila) }
            onEmigrando: function (socket) { self.alEmigrar(socket) }
            onAviso: function (texto) { K4.Sistema.avisar("Terminal", texto, false) }
        }
        onObjectAdded: function (indice, objeto) {
            const v = self.vivas.slice()
            v.splice(indice, 0, objeto)
            self.vivas = v
        }
        onObjectRemoved: function (indice, objeto) {
            //  Whatever that terminal had announced goes with it. Here
            //  and not in `cerrarSesion`, because this is the only place
            //  BOTH endings pass through: the one you close and the one
            //  that dies on its own.
            self.limpiarIsla(objeto.numero)
            const v = self.vivas.slice()
            v.splice(indice, 1)
            self.vivas = v
            if (self.actual >= v.length)
                self.actual = Math.max(0, v.length - 1)
            if (v.length === 0)
                self.abierto = false
        }
    }

    function nueva(socket) {
        listaSesiones.append({ sid: ++contador, socket: socket || "" })
        actual = vivas.length - 1
        //  Folded: every new terminal starts small, as on opening. ONLY
        //  the target is touched: writing to `filasReales` would break its
        //  binding to it —and with `nueva()` running the first time you
        //  open the island, the box stayed unhooked from minute one and
        //  never grew again—.
        objetivo = filasMinimas
        return vivas[actual]
    }

    function irA(n) {
        if (n >= 0 && n < vivas.length) {
            actual = n
            mandar({ que: "pinta" })
        }
    }

    function siguiente() { if (vivas.length > 1) irA((actual + 1) % vivas.length) }
    function anterior() { if (vivas.length > 1) irA((actual - 1 + vivas.length) % vivas.length) }

    //  Closing a session takes ALL of its own with it, and the
    //  connection pill is its own: the connection has gone with it. It
    //  used to be removed only at the end of the `ssh`, so closing the
    //  tab —or killing it— left the pill forever announcing a server
    //  of which nothing remains.
    function olvidarSesion(numero) {
        salirDe(claveIsla(numero))
    }

    function cerrarSesion(n) {
        if (n < 0 || n >= listaSesiones.count)
            return
        olvidarSesion(listaSesiones.get(n).sid)
        listaSesiones.remove(n)
    }

    function alMorir(numero) {
        olvidarSesion(numero)
        for (let i = 0; i < listaSesiones.count; ++i)
            if (listaSesiones.get(i).sid === numero) {
                listaSesiones.remove(i)
                return
            }
    }

    //  The session answers where it is. It is no longer used to take
    //  it out —the session now moves whole, another is not opened in
    //  its place— but it remains the way to know which directory it
    //  walks in: whoever wants to open something «right here» makes
    //  use of it.
    function alDecirDonde(ruta) {
        ultimoDirectorio = String(ruta || "")
    }

    property string ultimoDirectorio: ""

    //  Wakes the two services it needs: a QML singleton does not
    //  instantiate until someone looks at it. The environment one
    //  publishes the theme for the terminal —turning this plugin off
    //  stops publishing it, which is exactly what should happen— and
    //  the console one finds out which terminal is installed, which
    //  even the updater needs.
    readonly property string ambiente: Ambiente.ruta
    readonly property string cual: Consola.binario

    //  ── work in progress ──────────────────────────────────────────
    //
    //  What is cooking right now, by the pid of the window running it.
    //  The terminal only counts those alive for a few seconds, so an
    //  `ls`'s noise never reaches here: if something is noted down, it
    //  truly deserves a slot on the pill.
    property var trabajos: ({})

    //  The count is kept apart and not computed from the map:
    //  reassigning to a `var` property the SAME object it already had
    //  notifies nobody, and the heartbeat stayed stopped with the
    //  indicator nailed at zero. Hence also the map being copied here
    //  instead of touched inside.
    property int enCurso: 0

    //  From here upward, besides the indicator, a notification on
    //  finishing.
    readonly property int avisoSegundos: 20

    function idDe(pid) { return "terminal." + pid }

    //  A pill clock: it fits two fingers wide and does not dance past
    //  sixty, which is what matters when it sits next to the time.
    function reloj(ms) {
        const s = Math.max(0, Math.round(ms / 1000))
        if (s < 60)
            return s + " s"
        const m = Math.floor(s / 60)
        return m + ":" + String(s % 60).padStart(2, "0")
    }

    //  `llevaba` is the seconds the command had accumulated when the
    //  terminal decided to count it: the pill's clock starts there and
    //  not at zero, or it would show less time than it has truly been
    //  working.
    //  Console agents are something other than a long command: they are
    //  not «taking long», they are thinking, and one leaves them
    //  running on purpose. They get their own glyph to tell apart at a
    //  glance.
    readonly property var agentes: ["claude", "codex", "aider", "gemini", "opencode", "goose"]

    //  The bare program: no path in front and no arguments.
    //  `/usr/bin/python3 tools/goteo.py` is «python3», which is what
    //  reads at a glance in a two-finger tab.
    function programaDe(mandato) {
        const primero = String(mandato).trim().split(/\s+/)[0] || ""
        return primero.split("/").pop()
    }

    function esAgente(mandato) {
        return agentes.indexOf(programaDe(mandato)) >= 0
    }

    //  What runs is drawn with: glyph and color. Kept apart because
    //  the pill and the island's tab strip both use it, and two copies
    //  of this decision would end up saying different things about the
    //  same subject.
    //
    //  It is pure —it only looks at the command—, so a QML binding may
    //  call it without fear as long as it reads on its own the map it
    //  takes the command from: what a binding does not re-evaluate is
    //  the function, not the data.
    function insigniaDe(mandato) {
        const agente = esAgente(mandato)
        return { glifo: agente ? Theme.ico.ask.codePointAt(0) : 0xF018D,
                 color: agente ? Theme.green : Theme.blue }
    }

    function apuntar(pid, mandato, llevaba) {
        const t = Object.assign({}, trabajos)
        t[pid] = { mandato: String(mandato),
                   desde: Date.now() - (Number(llevaba) || 0) * 1000 }
        trabajos = t
        enCurso = Object.keys(t).length

        const insignia = insigniaDe(mandato)
        K4.Pildora.registrar(idDe(pid), reloj(0),
                             insignia.glifo, insignia.color, 30, true)
    }

    //  Those waiting for you go with their own id: a long command and
    //  an agent that has finished its shift are two different things
    //  and can coincide.
    function idEspera(pid) { return "terminal.espera." + pid }

    //  And who wears it. The pill registry cannot be asked, so
    //  without this list there is no way to know whom to watch: a
    //  bell can stay alone long after its command ended, and it is
    //  exactly the one most noticed if it outlives its window. Kept
    //  apart from `trabajos` because they are different things.
    property var esperas: ({})

    function esperando(pid, titulo) {
        const nombre = String(titulo || "").trim() || "Terminal"
        //  The theme's bell: it says «they are calling you» without
        //  needing to be read, and in yellow, which demands without
        //  alarming.
        K4.Pildora.registrar(idEspera(pid), nombre.slice(0, 18), Theme.ico.bell.codePointAt(0),
                             Theme.yellow, 29, true)
        //  It is kept WITH WHOM, not a `true`: on attending it, its
        //  notification must be removable, and for that one needs to
        //  know which one it was.
        const e = Object.assign({}, esperas)
        e[pid] = nombre
        esperas = e

        //  WHICH window this notice belongs to. Without this,
        //  clicking it looked for «a k4term window» and with two open
        //  it went to the older one, which is the one next door: the
        //  notice took you to the wrong terminal. The island ones have
        //  no window —their key is `isla.N`— and there is no pid to
        //  note there.
        if (String(pid).indexOf("isla.") !== 0)
            Notifs.apuntarDestino("k4term", nombre, pid)

        K4.Sistema.lanzar(["notify-send", "-a", "k4term", "-t", "8000",
                           "Waiting for you", nombre])
    }

    function dejarDeEsperar(pid) {
        K4.Pildora.quitar(idEspera(pid))
        if (esperas[pid] === undefined)
            return
        //  The pill and the notification tell the SAME thing:
        //  removing one and leaving the other leaves half the notice
        //  up, and that half is what later shows in the strip under
        //  the clock.
        Notifs.descartarDeApp("k4term", esperas[pid])
        Notifs.olvidarDestino("k4term", esperas[pid])
        const e = Object.assign({}, esperas)
        delete e[pid]
        esperas = e
    }

    //  ── going to the terminal IS attending it ─────────────────────
    //
    //  The bell asks for one concrete thing: that you come. Once you
    //  are there it has done its part, and keeping asking from the
    //  pill is noise. Until now you only went by clicking it, which is
    //  asking for the same gesture twice: going to the terminal and
    //  telling the bar you went.
    //
    //  Two paths because there are two terminals. The window one
    //  learns from the pid of whichever takes focus —the key it was
    //  noted with—; the island one, from the tab being watched, which
    //  is the same rule `alLlamar` uses to decide not to bother.
    //
    //  Work in progress is NOT touched: that indicator counts
    //  something still happening and looking at it does not end it.
    property Connections foco: Connections {
        target: Ventanas
        function onPidActivoChanged() {
            self.dejarDeEsperar(Ventanas.pidActivo)
        }
    }

    function atendidaIsla() {
        if (!abierto || actual < 0 || actual >= vivas.length || !vivas[actual])
            return
        dejarDeEsperar(claveIsla(vivas[actual].numero))
    }

    function olvidar(pid) {
        if (trabajos[pid] === undefined)
            return
        const t = Object.assign({}, trabajos)
        delete t[pid]
        trabajos = t
        enCurso = Object.keys(t).length
        K4.Pildora.quitar(idDe(pid))
    }

    function tictac() {
        const ahora = Date.now()
        for (const pid in trabajos)
            K4.Pildora.actualizar(idDe(pid), { texto: reloj(ahora - trabajos[pid].desde) })
    }

    //  It only beats while there is something to count: no jobs, no
    //  waking up.
    property Timer latido: Timer {
        interval: 1000
        repeat: true
        running: self.enCurso > 0
        onTriggered: self.tictac()
    }

    //  Clicking the indicator takes you to the working window. It is
    //  asked for first: if it no longer exists —killed without
    //  warning— the indicator heals itself, and clicking it is the
    //  only moment worth checking.
    property Connections clics: Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if (String(id).indexOf("terminal.") !== 0)
                return
            //  The open-terminals one leads to no window: it opens
            //  the island where you left it.
            if (id === self.idAbiertas) {
                self.abierto = true
                self.mandar({ que: "pinta" })
                return
            }
            //  Going to the window removes the waiting notice: you
            //  have attended it, which is what the indicator was
            //  asking.
            const espera = String(id).indexOf("terminal.espera.") === 0
            const resto = String(id).substring(espera ? "terminal.espera.".length
                                                      : "terminal.".length)
            //  Through `dejarDeEsperar` and not by removing the pill by
            //  hand: this way the click also withdraws the
            //  notification and erases the note, the same thing going
            //  to the terminal does. Removing only the pill, the
            //  notice stayed in the panel and in the clock's strip.
            if (espera)
                self.dejarDeEsperar(resto)

            //  If it is from the island, there is no window to go to:
            //  the terminal opens on that very session.
            if (resto.indexOf("isla.") === 0) {
                const donde = self.indiceDe(parseInt(resto.substring(5), 10))
                if (donde >= 0) {
                    self.actual = donde
                    self.abierto = true
                    self.mandar({ que: "pinta" })
                }
                return
            }

            buscar.pid = resto
            if (buscar.running)
                buscar.relanzar = true
            else
                buscar.running = true
        }
    }

    //  ── what cooks in the island terminals ────────────────────────
    //
    //  The same the window already did, but arriving over the
    //  session's channel instead of IPC. And with an advantage IPC
    //  never gave: we know WHICH terminal it comes from, so clicking
    //  the indicator brings you to it instead of looking for a window
    //  that does not exist.
    function claveIsla(numero) { return "isla." + numero }

    function indiceDe(numero) {
        for (let i = 0; i < vivas.length; ++i)
            if (vivas[i].numero === numero)
                return i
        return -1
    }

    //  An indicator for a terminal that is no longer there is a door
    //  to nowhere: clicking it cannot take you anywhere.
    function limpiarIsla(numero) {
        const clave = claveIsla(numero)
        olvidar(clave)
        dejarDeEsperar(clave)
    }

    function alTrabajar(numero, estado, mandato, salida, segundos) {
        const clave = claveIsla(numero)
        if (estado === "empieza") {
            apuntar(clave, mandato, segundos)
            return
        }
        olvidar(clave)
        if (segundos >= avisoSegundos)
            avisar(mandato, salida, segundos)
    }

    //  The bell only deserves a notice if you are NOT watching it.
    //  With that terminal in front of you you have already found out,
    //  and notifying you would be noise — which is exactly the rule
    //  the window applies with focus.
    function alLlamar(numero, titulo) {
        const mirando = abierto && vivas[actual] && vivas[actual].numero === numero
        if (mirando)
            return
        //  Who is calling you, not a bare «Terminal»: the point of
        //  this is knowing WHICH of your agents has finished its
        //  shift. The title the application asks for says it best; the
        //  command, if there is none.
        const donde = indiceDe(numero)
        const quien = (donde >= 0 && vivas[donde].titulo)
            || titulo || "Terminal"
        esperando(claveIsla(numero), quien)
    }

    //  ── what you are connected to ─────────────────────────────────
    //
    //  One pill per session that is inside a server. Noted with the
    //  key of whoever opens it —the window's pid or the island
    //  session— so two simultaneous connections do not step on each
    //  other.
    function idConexion(clave) { return "terminal.ssh." + clave }

    //  Where each one is connected, by its key. Needed to be able to
    //  say WHICH server was left: the window only sends its pid.
    property var dentroDe: ({})

    function entrarEn(clave, destino) {
        const nombre = String(destino || "").trim()
        if (!nombre)
            return
        const d = Object.assign({}, dentroDe)
        d[clave] = nombre
        dentroDe = d
        K4.Pildora.registrar(idConexion(clave), nombre.slice(0, 20),
                             0xF08C0, Theme.blue, 28, true)
    }

    function salirDe(clave) {
        K4.Pildora.quitar(idConexion(clave))
        const destino = dentroDe[clave]
        if (destino) {
            const d = Object.assign({}, dentroDe)
            delete d[clave]
            dentroDe = d
            Consola.salioDe(destino)
        }
    }

    //  A window can leave without saying goodbye —killed, hung, the
    //  whole session gone— and its pill would keep announcing a place
    //  of which nothing remains. Checked every few seconds, and ONLY
    //  while there is a window one: the island ones do not need it,
    //  those sessions are ours and we know when they leave.
    //
    //  And it goes over all THREE families, not just the servers': the
    //  window's goodbye (`k4.term clear`) comes from k4term when its
    //  shell dies, and closing the window does not pass there —the
    //  process is gone at once and the shell learns later, when there
    //  is nobody left to tell—. A long command or a bell then stayed
    //  on the pill forever, with the clock climbing. Here nobody is
    //  trusted to say goodbye.
    readonly property var pidsVigilados: {
        const vistos = ({})
        const anotar = function (clave) {
            //  The island ones out: their keys are `isla.N`, not
            //  pids, and of those sessions we already know when they
            //  leave.
            if (String(clave).indexOf("isla.") !== 0)
                vistos[String(clave)] = true
        }
        for (const dentro in dentroDe)
            anotar(dentro)
        for (const curro in trabajos)
            anotar(curro)
        for (const llamada in esperas)
            anotar(llamada)
        return Object.keys(vistos)
    }

    property Timer vigilante: Timer {
        interval: 5000
        repeat: true
        running: self.pidsVigilados.length > 0
        onTriggered: self.revisarVentanas()
    }

    function revisarVentanas() {
        const pids = pidsVigilados
        if (pids.length === 0)
            return
        vivos.command = ["sh", "-c",
            "for p in " + pids.join(" ") + "; do [ -d /proc/$p ] && echo $p; done"]
        vivos.running = true
    }

    //  Whoever is gone gets all three removed at once: each one knows
    //  how to ignore itself if it was not its own, and so nobody has
    //  to figure out what it died of.
    function despedir(pid) {
        salirDe(pid)
        olvidar(pid)
        dejarDeEsperar(pid)
    }

    property K4.Process vivos: K4.Process {
        onSalida: function (texto) {
            const siguen = String(texto).trim().split(/\s+/)
            const pids = self.pidsVigilados
            for (let i = 0; i < pids.length; ++i)
                if (siguen.indexOf(pids[i]) < 0)
                    self.despedir(pids[i])
        }
    }

    //  ── «you have terminals open» ─────────────────────────────────
    //
    //  With the view hidden there is NOTHING to remind you that
    //  something is still running in there, and a session that
    //  outlives its own view is exactly the one that gets forgotten.
    //  An indicator with the count says it, and clicking it brings it
    //  back.
    //
    //  Only while hidden: with it in front of you, telling you it is
    //  open is redundant.
    readonly property string idAbiertas: "terminal.abiertas"

    function refrescarAbiertas() {
        if (vivas.length === 0 || abierto) {
            K4.Pildora.quitar(idAbiertas)
            return
        }
        K4.Pildora.registrar(idAbiertas, String(vivas.length),
                             0xF018D, Theme.muted, 31, true)
    }

    onVivasChanged: refrescarAbiertas()
    onAbiertoChanged: { refrescarAbiertas(); atendidaIsla() }
    onActualChanged: atendidaIsla()

    //  Long jobs: the terminal notifies on ending and here it becomes
    //  a notification, which is the road the whole house uses for
    //  notices. The command is trimmed because a twenty-argument
    //  `find` does not fit a toast and what matters is recognizing it,
    //  not reading it whole.
    function resumir(mandato) {
        const limpio = String(mandato).trim()
        return limpio.length > 48 ? limpio.slice(0, 47) + "…" : limpio
    }

    function duracion(segundos) {
        const s = Math.round(Number(segundos) || 0)
        if (s < 60)
            return s + " s"
        const m = Math.floor(s / 60)
        return m < 60 ? m + " min " + (s % 60) + " s"
                      : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    K4.Ipc {
        target: "k4.term"

        //  Without saying where, at home. Explicit on purpose: what is
        //  inherited when launching from here is the bar's directory,
        //  which nobody cares about.
        function open(): void {
            K4.Sistema.lanzar(Consola.abrir(K4.Sistema.entorno("HOME")))
        }

        function openAt(ruta: string): void {
            K4.Sistema.lanzar(Consola.abrir(ruta))
        }

        //  Where the house runs things: the island if there is one,
        //  and if not a window. This used to always open a window,
        //  inconsistent with Update indeed showing in the island.
        function run(mandato: string): void {
            if (mandato)
                Consola.ejecutar(mandato)
        }

        //  The island one, big and in the same place.
        function popOut(): void { self.sacar() }

        //  The single gesture: move the session to the other side,
        //  whichever the other side is. If you are looking at a
        //  k4term window, it comes back to the island; if not, the
        //  island one goes to a window. Two shortcuts for the same
        //  thing made no sense, and the window one did not even arrive
        //  while the island kept the keyboard.
        function move(): void { quien.running = true }

        //  Open where you are looking: Hyprland is asked for the
        //  focused window and the process tree is walked down to the
        //  last child —the interpreter that truly holds the directory—
        //  to read its cwd. If anything fails, it falls back to just
        //  opening.
        function here(): void { donde.running = true }

        //  Something long starts: to the pill. Whoever decides what
        //  «long» is, is the terminal, the one wearing the clock.
        function start(pid: string, mandato: string, llevaba: string): void {
            self.apuntar(pid, mandato, llevaba)
        }

        //  And on ending: off the pill, and a notice if it truly took
        //  a while. The indicator appears before the notice on purpose
        //  — first learn that it works, then that it finished.
        function end(pid: string, mandato: string, salida: string,
                     segundos: string): void {
            self.olvidar(pid)
            if (Number(segundos) >= self.avisoSegundos)
                self.avisar(mandato, salida, segundos)
        }

        //  The window closes with something inside: its indicator goes
        //  with it.
        function clear(pid: string): void {
            self.olvidar(pid)
            self.dejarDeEsperar(pid)
        }

        //  The island terminal, for the quick things.
        function island(): void { self.toggle() }

        //  A window gives its session back: a tab opens to adopt it.
        //  The window closes itself as soon as it has been taken.
        function adopt(socket: string): void {
            if (!socket)
                return
            self.nueva(socket)
            self.abierto = true
        }

        //  The having-several ones: opening another, moving between
        //  them and closing the spare. The same as the keys, for
        //  whoever prefers a script.
        function newSession(): void {
            if (!Consola.hayIsla)
                return
            self.nueva()
            self.abierto = true
        }

        function next(): void { self.siguiente() }
        function prev(): void { self.anterior() }
        function goTo(n: string): void { self.irA(parseInt(n, 10) - 1) }
        function closeTerminal(): void { self.cerrarSesion(self.actual) }

        //  Type into the one in front of you, opening no new one. That
        //  is what tells this apart from `run`, which always breaks in a
        //  fresh terminal.
        function write(texto: string): void {
            //  Newlines become returns for the same reason as when
            //  pasting: that is what the Enter key sends, and with `\n`
            //  the line stays written without executing.
            if (texto)
                self.mandar({ que: "texto",
                              valor: String(texto).replace(/\r\n|\n/g, "\r") })
        }

        //  A terminal ringing the bell without focus is almost always
        //  an agent that finished its shift and waits for you. Noted
        //  on the pill —with its own glyph, not the same as a long
        //  command— and notified once.
        function bell(pid: string, titulo: string): void {
            self.esperando(pid, titulo)
        }

        //  You are inside a place. The window says it on connecting and
        //  the pill shows it: with three terminals open, knowing which
        //  machine each belongs to should not require reading the
        //  prompt.
        function connected(pid: string, destino: string): void {
            self.entrarEn(pid, destino)
        }

        function disconnected(pid: string): void {
            self.salirDe(pid)
        }

        //  A loose message from the terminal: it has nowhere to say
        //  «saved» without covering itself, and the island does.
        function notify(titulo: string, cuerpo: string): void {
            K4.Sistema.lanzar(["notify-send", "-a", "k4term", "-t", "5000",
                               titulo, cuerpo])
        }
    }

    function avisar(mandato, salida, segundos) {
        const fallo = String(salida) !== "0"
        const cuerpo = resumir(mandato) + " · " + duracion(segundos)
        K4.Sistema.lanzar(["notify-send", "-a", "k4term",
                           fallo ? "-u" : "-t", fallo ? "critical" : "6000",
                           fallo ? "Command failed" + " (" + salida + ")"
                                 : "Command finished",
                           cuerpo])
    }

    //  ── k4term's settings, in the house's Settings ────────────────
    //
    //  k4term reads them from ~/.config/k4term/k4term.conf and follows
    //  them live, so flipping a switch here shows in the open windows
    //  without reopening anything. Written LINE BY LINE and not the
    //  whole file on purpose: whoever hand-edited it has the right to
    //  keep their comments and their keys.

    readonly property string ficheroConf: K4.Sistema.entorno("HOME") + "/.config/k4term/k4term.conf"

    property var conf: ({ tamaño: "13", opacidad: "0.92", estela: "si",
                          tranquilo: "no" })

    function leerConf() {
        const texto = fConf.text() || ""
        const nuevo = Object.assign({}, conf)
        texto.split("\n").forEach(function (linea) {
            const limpia = linea.split("#")[0].trim()
            const corte = limpia.indexOf("=")
            if (corte < 0)
                return
            nuevo[limpia.slice(0, corte).trim()] = limpia.slice(corte + 1).trim()
        })
        conf = nuevo
    }

    function poner(clave, valor) {
        const nuevo = Object.assign({}, conf)
        nuevo[clave] = String(valor)
        conf = nuevo

        let texto = fConf.text() || ""
        const patron = new RegExp("^[ \\t]*" + clave + "[ \\t]*=.*$", "m")
        if (patron.test(texto))
            texto = texto.replace(patron, clave + " = " + valor)
        else
            texto = (texto.length && texto.slice(-1) !== "\n" ? texto + "\n" : texto)
                  + clave + " = " + valor + "\n"
        fConf.setText(texto)
    }

    property K4.Fichero fConf: K4.Fichero {
        path: self.ficheroConf
        onLoaded: self.leerConf()
    }

    K4.Ajustes {
        plugin: "terminal"
        grupo: "Terminal"

        //  Only if k4term is around. They are ITS settings: without
        //  it, this section offered to change the font size and glass
        //  of a terminal that is not installed, writing to a file
        //  nobody reads. With the list empty, the whole section does
        //  not show.
        //
        //  Consola's detection takes a while —a process running at
        //  startup—, so this reads «no» for the first milliseconds;
        //  what makes it appear later is K4.Ajustes registering again
        //  when `opciones` changes.
        opciones: !Consola.esNuestra ? [] : [
            { id: "tamaño", nombre: "Font size",
              desc: "Window only; the island uses its own space",
              glifo: 0xF0207, tipo: "eleccion",
              alternativas: [{ codigo: "11", nombre: "11" },
                             { codigo: "13", nombre: "13" },
                             { codigo: "15", nombre: "15" },
                             { codigo: "18", nombre: "18" }] },
            { id: "opacidad", nombre: "Glass",
              desc: "How much shows through",
              glifo: 0xF00B5, tipo: "eleccion",
              alternativas: [{ codigo: "1", nombre: "Opaque" },
                             { codigo: "0.94", nombre: "Soft" },
                             { codigo: "0.88", nombre: "Medium" },
                             { codigo: "0.8", nombre: "Strong" }] },
            { id: "estela", nombre: "Cursor trail",
              desc: "Leaves a trail when moving", glifo: 0xF05D8 },
            { id: "tranquilo", nombre: "Quiet mode",
              desc: "Dims everything before the last command",
              glifo: 0xF0335 }
        ]
        valores: ({
            "tamaño": self.conf["tamaño"] || "13",
            opacidad: self.conf.opacidad || "0.94",
            estela: self.conf.estela !== "no" && self.conf.estela !== "0",
            tranquilo: self.conf.tranquilo === "si" || self.conf.tranquilo === "1"
        })
        onCambiado: function (id, valor) {
            if (id === "estela" || id === "tranquilo")
                self.poner(id, valor ? "si" : "no")
            else
                self.poner(id, valor)
        }
    }

    K4.Process {
        id: buscar
        property string pid: ""
        //  An indicator click arriving while the previous `hyprctl
        //  clients` is still alive: assigning `pid` and `running`
        //  there is a no-op and that click was lost. The pid is noted
        //  and `onTerminado` relaunches the search with it.
        property bool relanzar: false
        command: ["hyprctl", "clients", "-j"]
        onTerminado: function (codigo) {
            if (buscar.relanzar) {
                buscar.relanzar = false
                buscar.running = true
            }
        }
        onSalida: function (texto) {
            let ventanas = []
            try {
                ventanas = JSON.parse(texto)
            } catch (e) {
                return
            }
            const viva = ventanas.some(function (v) {
                return String(v.pid) === buscar.pid
            })
            if (!viva) {
                self.olvidar(buscar.pid)
                return
            }
            enfoque.pid = buscar.pid
            enfoque.running = true
        }
    }

    //  Hyprland 0.56 no longer swallows `dispatch focuswindow pid:N`:
    //  its Lua parser chokes on the selector's colon. The living way
    //  is `eval`, the same the Hyprland theme uses in this house.
    K4.Process {
        id: enfoque
        property string pid: ""
        command: ["hyprctl", "eval",
                  "local v = hl.get_window(\"pid:" + pid + "\")"
                  + " if v then hl.dispatch(hl.dsp.focus({ window = v })) end"]
        onTerminado: running = false
    }

    //  Whoever is in front right now. With that, where the session
    //  moves is decided: the bar cannot ask a GPUI window, but it can
    //  call it — and a window's process is called with a signal.
    K4.Process {
        id: quien
        command: ["hyprctl", "activewindow", "-j"]
        onSalida: function (texto) {
            let v = null
            try {
                v = JSON.parse(texto)
            } catch (e) {
                v = null
            }
            if (v && String(v.class) === "k4term" && v.pid > 0) {
                K4.Sistema.lanzar(["kill", "-USR1", String(v.pid)])
                return
            }
            //  Moving is carrying something that exists. Without a
            //  session in the island there is nothing to take, and
            //  opening a new terminal here would be a surprise: it
            //  happened in the first test and makes no sense.
            if (self.sesion)
                self.sacar()
        }
        onTerminado: running = false
    }

    K4.Process {
        id: donde
        command: ["sh", "-c",
            "p=$(hyprctl activewindow -j | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"pid\") or 0)' 2>/dev/null);" +
            " [ \"$p\" -gt 0 ] 2>/dev/null || exit 0;" +
            " while c=$(pgrep -P \"$p\" -n 2>/dev/null); [ -n \"$c\" ]; do p=$c; done;" +
            " readlink /proc/$p/cwd 2>/dev/null"]
        onSalida: function (texto) {
            K4.Sistema.lanzar(Consola.abrir(texto.trim()))
        }
        onTerminado: running = false
    }
}
