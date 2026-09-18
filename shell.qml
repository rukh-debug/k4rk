//  k4 — host de la island.
//
//  Aquí no hay lógica de ningún módulo: esto monta la superficie, dibuja la
//  silueta y decide qué plugin se queda la island. Añadir un módulo es crear
//  una carpeta en plugins/ y darla de alta en plugins/catalog.json.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import K4 as K4
import "core"
import "services"
import "widgets"

Scope {
    id: root

    // ── los módulos ───────────────────────────────────────────────
    //
    //  Ya no se instancian aquí: los crea PluginManager desde el catálogo,
    //  cada uno en su try. La diferencia no es de estilo — con la
    //  instanciación estática, un plugin con un error de sintaxis dejaba
    //  «Type X unavailable» y CERO barras, y pasó esta semana. Con la carga
    //  dinámica, el roto se apunta en Ajustes y los demás arrancan.
    //
    //  Las referencias cruzadas (`panel`, `tray`…) también las
    //  reparte el gestor: cualquier plugin que declare la propiedad la
    //  recibe, venga del repo o de ~/.config/k4/plugins.

    // ── the native surfaces ─────────────────────────────────────
    //
    //  The tray is bar chrome, not a plugin: always on and owned by
    //  the host (services/TrayIsland.qml). It still quacks like a
    //  surface — name, priority, active, view, close() — so every
    //  arbitration below runs over plugins plus natives, in one list.
    //  A second native surface joins by appending here and nowhere else.
    readonly property var surfaces: PluginManager.instancias.concat([TrayIsland])

    // ── quién se queda la island ──────────────────────────────────
    // Gana el activo de mayor prioridad. El binding se recalcula solo cuando
    // cualquier plugin cambia su `active`.
    readonly property var activePlugin: {
        if (Island.debugMode.length > 0) {
            const l = root.surfaces
            for (let i = 0; i < l.length; ++i) {
                if (l[i].name === Island.debugMode)
                    return l[i]
            }
        }

        let best = null
        //  The same race, restricted to views that still HAVE their
        //  content: a closing grace (`active: open || closing`)
        //  unloads its view the moment close() starts and then holds
        //  the island as an empty shell for the length of its timer.
        //  Letting that shell keep the arbitration steals the stage
        //  back from the view that just superseded it — and close()'s
        //  own two writes (`open = false`, then `closing = true`)
        //  flicker `active` false→true, so the theft began with a
        //  one-frame flash of the winner anyway. A loaded view beats
        //  an unloading one, whatever the ladder says; when nobody
        //  is loaded the grace keeps its hold — that is its job.
        let bestCargado = null
        const lista = root.surfaces
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (!p.habilitado || !p.active)
                continue
            if (best === null || p.priority > best.priority)
                best = p
            if (p.viewLoaded && (bestCargado === null
                                 || p.priority > bestCargado.priority))
                bestCargado = p
        }
        return bestCargado !== null ? bestCargado : best
    }

    //  ── lo que se va solo se aparta ───────────────────────────────
    //
    //  Una vista transitoria —un aviso, la confirmación de un ajuste rápido—
    //  aparece sin que nadie la pida y se cierra sola a los pocos segundos. Si
    //  en esos segundos el usuario abre algo, lo que quiere es lo que ha
    //  abierto: el aviso ya ha dicho lo suyo.
    //
    //  Antes se quedaba, y no por prioridad sino por su reloj: un aviso tiene
    //  cinco segundos y no cede hasta que vencen, así que pulsar el atajo del
    //  lanzador enseñaba el aviso hasta el final y el
    //  lanzador después. Y cerrarlo no basta con que otro le gane la prioridad:
    //  su temporizador se rearma mientras el ratón esté sobre la island —que es
    //  donde está, si acabas de abrir algo— así que volvería a salir al cerrar
    //  lo de encima.
    //
    //  Aquí y no en cada plugin: `Notifs.dismissToast()` a mano en cada sitio
    //  que abre algo era lo que había, y es exactamente lo que se olvida — solo
    //  lo llamaban dos.
    function apartarTransitorios() {
        const gana = activePlugin
        if (!gana || gana.transitorio)
            return

        const lista = root.surfaces
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (p !== gana && p.transitorio && p.active
                    && typeof p.close === "function")
                p.close()
        }
    }

    //  ── one summoned view at a time, and the newest rules ────────
    //
    //  Opening a second popup used to leave the first one OPEN under
    //  the winner: hidden, but alive — and it came back the moment
    //  the winner closed, a popup nobody had asked for. Worse, with
    //  the newcomer BELOW the holder in the priority ladder the
    //  stage never changed hands at all: the keybind looked dead.
    //
    //  So the rule the user already assumes, made real by the host:
    //  the summoned view that was just asked for supersedes whoever
    //  holds the island — the previous one is CLOSED, through its
    //  own `close()` so whatever it must do on the way out (keep a
    //  terminal session, run its grace timer) still happens. The
    //  ladder keeps arbitrating the rest: hover views, transients,
    //  the pill.
    //
    //  A binding that reads every instance's `active` re-evaluates
    //  on any flip, so the diff below sees the newcomer arrive even
    //  when `activePlugin` itself does not change (the low-priority
    //  case). The array is rebuilt on every evaluation, so the
    //  changed handler fires far more often than the cast changes —
    //  the signature diff makes the noise free.
    //  The signature counts a summoned view only while its view is
    //  LOADED: a plugin without its view mounted is on its
    //  way out, not on its way in; `viewLoaded` says which is
    //  which, and every opener mounts its view before (or in the
    //  same breath as) its `active`.
    readonly property var summonedActive: {
        const salida = []
        const lista = root.surfaces
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (p.habilitado && p.active && p.viewLoaded && p.colocable
                    && !p.transitorio && p.name !== PluginManager.pillId)
                salida.push(p.name)
        }
        return salida
    }

    property string _summonedPrevios: ""

    //  Told before the loser is closed, so the stage can freeze its
    //  live view for the departure fade — after `close()` unloads
    //  it there is nothing left to fade.
    signal viewSuperseded(string viewId)

    onSummonedActiveChanged: {
        const firma = summonedActive.join(",")
        const previa = _summonedPrevios
        _summonedPrevios = firma
        if (firma === previa)
            return

        //  Who just arrived: in the new signature and not in the
        //  old one. The close targets below are the actives that
        //  were already standing — comparing against the whole new
        //  list would skip them all, and the rule would never fire.
        const nuevos = firma.length > 0 ? firma.split(",") : []
        const viejos = previa.length > 0 ? previa.split(",") : []
        const llegaron = nuevos.filter(function (n) {
            return viejos.indexOf(n) < 0
        })
        if (llegaron.length === 0)
            return          // only departures; nothing was superseded

        const lista = root.surfaces
        const victimas = []
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (!p.habilitado || !p.active || !p.viewLoaded || !p.colocable
                    || p.transitorio || p.name === PluginManager.pillId)
                continue
            if (llegaron.indexOf(p.name) >= 0)
                continue
            victimas.push(p)
        }
        if (victimas.length === 0)
            return

        //  Deferred, and for a reason: closing a victim re-dirties
        //  this very binding and QML re-evaluates it synchronously —
        //  acting inside the dispatch re-enters the evaluation
        //  («Binding loop detected») and the pass is dropped on the
        //  floor. Let the binding settle first; the stage freeze
        //  (the signal) rides in the same deferral, still ahead of
        //  its own close().
        Qt.callLater(function () {
            for (let i = 0; i < victimas.length; ++i) {
                const p = victimas[i]
                //  Re-checked at departure time: a victim may have
                //  begun leaving on its own while the deferral was
                //  queued — view gone, nothing left to supersede.
                if (!p || !p.habilitado || !p.active || !p.viewLoaded)
                    continue
                viewSuperseded(p.name)
                if (typeof p.close === "function")
                    p.close()
            }
        })
    }

    //  Lo que decide el reparto, publicado para que lo lean los plugins por
    //  K4.Isla: quién la tiene y si está desplegada.
    onActivePluginChanged: {
        apartarTransitorios()
        const anterior = Island.ocupante
        if (activePlugin && activePlugin.name !== PluginManager.pillId) {
            // Desde reposo, el origen explícito del clic; sin él, el monitor
            // con foco. Entre dos vistas abiertas se conserva la pantalla para
            // que navegar por el panel no haga saltar la island.
            if (Island.pantallaPedida.length > 0
                    || anterior.length === 0 || anterior === PluginManager.pillId)
                Island.pantallaActiva = Island.tomarPantallaPedida()
        } else {
            Island.pantallaPedida = ""
        }
        Island.ocupante = activePlugin ? activePlugin.name : ""
        //  «Abierta» es DESPLEGADA, no «hay alguien»: la píldora también
        //  ocupa la island y siempre está, así que con `activePlugin !== null`
        //  esto valía true a todas horas y no le servía a nadie. Desplegada es
        //  pedir más alto que la píldora.
        Island.abierta = activePlugin !== null
            && activePlugin.islandHeight > Theme.baseHeight
    }

    // Clic en el fondo: lo atiende el plugin activo si lo pide; si no, abre el
    // centro de control.
    function abrirPanelEn(pantalla) {
        Island.pedirPantalla(pantalla)
        Island.pantallaActiva = pantalla
        const panel = PluginManager.instancia("panel")
        if (panel)
            panel.openTab("controls")
    }

    function backgroundTap(pantalla, mostrado) {
        if (mostrado && mostrado.name !== PluginManager.pillId && mostrado.handlesBackgroundTap)
            mostrado.backgroundTapped()
        else
            abrirPanelEn(pantalla)
    }

    // Los singletons de QML son perezosos: sin tocarlos no arrancan sus
    // procesos ni registran nada (el servidor de notificaciones, por ejemplo).
    Component.onCompleted: {
        //  El puente de la API, lo PRIMERO: los ficheros del módulo K4 no
        //  pueden importar la barra por ruta relativa —cargarían una segunda
        //  copia entera de services/, ver api/K4/Puente.qml— así que el host
        //  les inyecta aquí lo que necesitan.
        K4.Puente.tema = Theme
        K4.Puente.indicadores = Indicadores
        K4.Puente.audio = Audio
        K4.Puente.medios = Media
        K4.Puente.notificaciones = Notifs
        K4.Puente.wifi = Wifi
        K4.Puente.bluetooth = Bt
        K4.Puente.escritorios = Workspaces
        K4.Puente.portapapeles = Clipboard
        K4.Puente.reloj = Clock
        K4.Puente.enganches = Enganches
        K4.Puente.isla = Island
        K4.Puente.consola = Consola
        K4.Puente.extensiones = Extensions
        K4.Puente.submaps = Submaps

        void Audio.volume
        void Wifi.name
        void Bt.adapter
        void Notifs.count
        void Media.hasPlayer
        void Clock.date
        void Workspaces.list
        void Tray.count
        void Settings.cargado
        void PluginManager.cargado
        void Clipboard.cargado
        void Ventanas.count
        void Modulos.count
        void WallpaperPalette.ready
        void Fondos.lista
    }

    // ── IPC ───────────────────────────────────────────────────────
    // Each module publishes its own target (k4.panel, k4.openwebui,
    // k4.launcher).
    // Esto es la capa de compatibilidad: mantiene el target `k4` con los
    // nombres de siempre para no romper los atajos ya configurados.
    //  Atajo del registro: el plugin vivo con ese id, o null si está
    //  deshabilitado o roto. Con `?.` detrás, llamar a uno apagado no hace
    //  nada, que es exactamente lo que debe hacer.
    function _p(id) { return PluginManager.instancia(id) }

    IpcHandler {
        target: "k4"
        function toggleLauncher(): void { _p("launcher")?.toggle() }
        function clipboard(): void { _p("clipboard")?.toggle() }
        function system(): void { _p("system")?.toggle() }
        function keys(): void { _p("keys")?.toggle() }
        function install(query: string): void { _p("packages")?.buscar(query) }
        function search(query: string): void {
            _p("launcher")?.buscar(query)
        }
        function togglePanel(): void { _p("panel")?.toggle("controls") }
        function toggleNotifications(): void { _p("panel")?.toggle("notifications") }
        function pluginEnable(id: string): void { PluginManager.habilitar(id) }
        function pluginDisable(id: string): void { PluginManager.deshabilitar(id) }
        function pluginToggle(id: string): void { PluginManager.alternar(id) }
        function pluginRetry(id: string): void { PluginManager.reintentar(id) }
        function pluginReload(id: string): void { PluginManager.recargar(id) }
        function pluginRefresh(): void { PluginManager.releerCatalogo() }
        //  Devuelve, no imprime. Lo de antes hacía `console.log`, así que el
        //  JSON acababa en el log de Quickshell y quien lo había pedido por
        //  IPC no recibía nada: se podía leer, pero solo si además ibas a
        //  buscar el log. Con tipo de retorno, `quickshell ipc call` lo
        //  escribe en tu terminal, que es lo que uno espera al preguntar.
        function pluginStatus(): string {
            return JSON.stringify(PluginManager.catalogo.map(function (m) {
                return { id: m.id, enabled: PluginManager.estaHabilitado(m.id),
                         error: PluginManager.errores[m.id] || "" }
            }))
        }

        //  Pregunta al registro qué hay más nuevo. Contesta al momento y el
        //  resultado llega después a `PluginManager.novedades`: la respuesta
        //  útil la enseña la barra, aquí solo se dispara.
        function pluginCheck(): void { PluginManager.comprobarNovedades() }
        function wifi(): void { _p("panel")?.openTab("wifi") }
        function bluetooth(): void { _p("panel")?.openTab("bluetooth") }
        function sound(): void { _p("panel")?.openTab("sound") }
        function clearNotifications(): void { Notifs.clear() }
        //  The chat's verbs kept their old names — Super+G and a
        //  year of muscle memory point here — but they land on the
        //  OpenWebUI plugin now, the way `k4.term` outlived its own
        //  rename.
        function ask(): void {
            const a = _p("openwebui")
            if (!a)
                return
            if (a.open) a.close()
            else a.openAsk(false)
        }
        function askSelection(): void { _p("openwebui")?.openAsk(true) }
        function askNow(question: string): void {
            //  A direct question from a script: fresh thread, always.
            _p("openwebui")?.preguntar(question, true)
        }
        function askFollowUp(question: string): void {
            _p("openwebui")?.preguntar(question)
        }
        function askScreen(): void { _p("openwebui")?.attachScreenshot() }
        function askRegion(): void { _p("openwebui")?.attachRegion() }
        function togglePlay(): void { Media.togglePlaying() }
        function nextTrack(): void { Media.siguiente() }
        function prevTrack(): void { Media.anterior() }
        //  The wallpaper picker is a page of Settings, and this toggles it:
        //  closed opens at it, another page on screen switches to it, and
        //  standing on it closes — the same rule the panel's tabs follow.
        //  `theme` is the verb's old name, kept for the binds and habits
        //  that still call it.
        function wallpaper(): void { _p("settings")?.toggle("wallpaper") }
        function theme(): void { _p("settings")?.toggle("wallpaper") }
        function tray(): void { TrayIsland.toggle() }
        function settings(): void { _p("settings")?.toggle() }
        //  Ajustes abierto en una página concreta, para atarlo a un atajo:
        //  `k4 settingsSection wallpaper`, `… island`, `… effects`, … El
        //  nombre de la sección o su id, como lo entienda la vista.
        function settingsSection(section: string): void {
            _p("settings")?.abrirPagina(section)
        }
        function session(): void { _p("session")?.toggle() }
        function lock(): void { Sesion.bloquear() }
        function setMode(mode: string): void { Island.debugMode = mode }
    }

    //  The tray answers here, not from a plugin: `k4.tray toggle` is the
    //  summonCommand its Placement card hands out, and the compat `k4 tray`
    //  above lands in the same place.
    IpcHandler {
        target: "k4.tray"
        function toggle(): void { TrayIsland.toggle() }
        function close(): void { TrayIsland.close() }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            //  The island's home is Overlay — above the dim behind the
            //  deployed view (a Top surface, below) so the pill and
            //  its hover views stay bright and clickable while a view
            //  is out. Layers order strictly: Overlay > Top, whatever
            //  was created first.
            //
            //  With one exception: a true-fullscreen window. Hyprland
            //  draws BOTH top and overlay above fullscreen windows, so
            //  the only seat behind one is Bottom — correct only while
            //  the fullscreen lasts. While this monitor shows one
            //  (services/Fullscreen.qml keeps the state) the pill drops
            //  below it and the fullscreened window owns the screen,
            //  pointer and all. A view on the stage lifts the island
            //  back: one summoned over the video — by keybind, since
            //  the pointer can no longer reach the pill — has to render
            //  above it or it would open invisible.
            WlrLayershell.layer: Fullscreen.covers(panelWindow.screen.name)
                && pluginVisible === idlePlugin
                ? WlrLayer.Bottom : WlrLayer.Overlay

            //  La barra vive en el borde que diga Ajustes. El resto del
            //  fichero pregunta `abajo` en vez de repetir la comparación.
            readonly property bool abajo: Settings.barPosition === "bottom"

            //  ── dónde está la island AHORA ──────────────────────────
            //
            //  The bar has its edge; every view that OPENS can have its own
            //  — the control centre from the left, Settings from the bottom
            //  — read from its placement in Ajustes. A view with no entry
            //  follows the bar: its edge, its alignment, which is what every
            //  view did before placement existed and stays the default so
            //  nothing jumps after the update.
            readonly property var lugar: {
                const p = pluginVisible
                return p && p.name !== PluginManager.pillId
                    ? Settings.placementDe(p.name)
                    : { side: Settings.barPosition === "bottom"
                              ? "bottom" : "top",
                        align: Settings.barAlignment }
            }

            //  The placement as two fractions of the free space: the edge's
            //  axis pinned to its side, the other free to carry the
            //  alignment. Top and bottom pin Y (0 and 1), left and right pin
            //  X — and a plugin's temporary dodge (Island.colocar) rides the
            //  FREE axis, whichever it happens to be now.
            readonly property real fraccionX: lugar.side === "left" ? 0
                : lugar.side === "right" ? 1
                : (Island.colocacionPedida >= 0 ? Island.colocacionPedida
                                                : lugar.align / 100)
            readonly property real fraccionY: lugar.side === "top" ? 0
                : lugar.side === "bottom" ? 1
                : (Island.colocacionPedida >= 0 ? Island.colocacionPedida
                                                : lugar.align / 100)

            // Solo la pantalla propietaria enseña la acción global. Las demás
            // siguen con su píldora, que sí pertenece a todos los monitores.
            readonly property var idlePlugin: PluginManager.instancia(PluginManager.pillId)
            readonly property bool esPantallaActiva: root.activePlugin
                && root.activePlugin.name !== PluginManager.pillId
                && panelWindow.screen.name === Island.pantallaActiva
            readonly property var pluginVisible: root.activePlugin
                && (root.activePlugin.name === PluginManager.pillId || esPantallaActiva)
                ? root.activePlugin : idlePlugin

            //  ── the stage hand-off ────────────────────────────────
            //
            //  `pluginVisible` names the winner; the two loaders
            //  below keep one view LIVE and let the previous one
            //  LEAVE — a superseded summoned view fades out over the
            //  hand-off instead of being torn down in a single
            //  frame. Only summoned-view-over-summoned-view fades:
            //  arrivals from rest, hover peeks, the pill and every
            //  close keep the cut they always had, which is the
            //  transition the island already owns.
            property var prevPluginVisible: null
            property Loader stageCurrent: null

            function isSummoned(p) {
                return !!p && p.name !== PluginManager.pillId
                        && p.colocable && !p.transitorio
            }

            //  Freeze the live item of the named view and start its
            //  fade. Called by the supersede rule while the view is
            //  still mounted — a moment later close() pulls
            //  viewLoaded out from under the loader and there is
            //  nothing left to fade.
            function retireStage(viewId) {
                const carga = stageCurrent
                if (!carga || carga.departing)
                    return
                if (!carga.stageOwner
                        || carga.stageOwner.name !== viewId)
                    return
                carga.exitW = carga.width
                carga.exitH = carga.height
                carga.departing = true
                carga.live = false
                if (carga === stageOne)
                    fadeOne.restart()
                else
                    fadeTwo.restart()
            }

            onPluginVisibleChanged: {
                const llega = pluginVisible
                const estaba = prevPluginVisible
                prevPluginVisible = llega

                const salida = stageCurrent
                const entrada = salida === stageOne ? stageTwo : stageOne

                if (salida) {
                    const fundido = isSummoned(estaba) && isSummoned(llega)
                        && salida.stageOwner === estaba
                        && salida.item !== null

                    if (fundido && !salida.departing) {
                        //  The loser's item stays for the fade; the
                        //  island is already gliding to the newcomer
                        //  around it.
                        salida.exitW = salida.width
                        salida.exitH = salida.height
                        salida.departing = true
                        salida.live = false
                        if (salida === stageOne)
                            fadeOne.restart()
                        else
                            fadeTwo.restart()
                    } else if (!fundido) {
                        //  Cut: a close, a hover peek, a move between
                        //  screens, the pill taking the stage back —
                        //  the old view goes now, fade or no fade.
                        if (salida === stageOne)
                            fadeOne.stop()
                        else
                            fadeTwo.stop()
                        salida.stageOwner = null
                        salida.departing = false
                        salida.live = false
                    }
                    //  fundido && departing: the supersede rule
                    //  already froze this view and its fade is
                    //  running — hands off.
                }

                //  The newcomer always takes the idle loader. A fade
                //  still running there is spent: stop clears it, and
                //  the view arrives as today's arrivals do — mounted
                //  at once, at full opacity, unveiled by the
                //  island's own growth.
                if (entrada === stageOne)
                    fadeOne.stop()
                else
                    fadeTwo.stop()
                entrada.stageOwner = llega
                entrada.departing = false
                entrada.live = true
                stageCurrent = entrada
            }

            //  The supersede rule speaks for the whole shell; every
            //  screen's stage listens for its own view's name.
            Connections {
                target: root
                function onViewSuperseded(viewId) {
                    panelWindow.retireStage(viewId)
                }
            }

            //  ── click outside closes, like Escape ─────────────────────
            //
            //  A deployed view — the control center, the launcher — closes
            //  with Escape; the pointer deserves the same gesture. While one
            //  is showing HERE, the input mask includes the catcher (see
            //  `mask`), so a tap outside the island lands on us and closes
            //  the view through the same `close()` door Escape uses.
            //
            //  The click is SPENT on closing — it does not reach what is
            //  underneath. That is the trade, and the right one: the user
            //  asked for the view to go away, not for the link behind it.
            //
            //  Only the screen showing the view, only views that want it
            //  (`closeOnClickOutside`) and that somebody opened — the ones
            //  nobody asked for (`transitorio`) would eat clicks meant for
            //  other things. And never while the island is stood aside:
            //  a system dialog deserves every click it gets.
            readonly property bool cerrarConClicFuera: esPantallaActiva
                && !Island.apartada
                && root.activePlugin.closeOnClickOutside
                && !root.activePlugin.transitorio
                && root.activePlugin.islandHeight > Theme.baseHeight

            //  ── la barra apartada de UNA pantalla ─────────────────────
            //
            //  `activePlugin` es uno solo y global: gana el de más prioridad y
            //  mientras esté activo NADIE más puede activarse, en ninguna
            //  pantalla. Eso vale para un módulo que se abre y se cierra, pero
            //  no para uno que se queda —una escena puede llevarse la barra al
            //  borde de abajo y ahí sigue— porque deja la island de los otros
            //  monitores muerta: ni se despliega ni responde.
            //
            //  Así que apartar la barra deja de ser cosa de ocupar la island.
            //  Un módulo declara `barraApartada` con la pantalla que se lleva y
            //  el sitio que hay que seguir guardándole, y esa pantalla se queda
            //  sin barra sin que el resto se entere. Quien no la declare da
            //  `undefined` y todo sigue como siempre.
            readonly property var apartada: {
                const lista = root.surfaces
                for (let i = 0; i < lista.length; ++i) {
                    const p = lista[i]
                    if (!p.habilitado)
                        continue
                    const a = p.barraApartada
                    if (a && a.pantalla === panelWindow.screen.name)
                        return a
                }
                return null
            }

            //  Apartada es apartada, ocupe la island quien la ocupe.
            //
            //  Antes se hacía la excepción de dejarla salir en cuanto un módulo
            //  se activaba —el lanzador, el portapapeles—, para que su atajo no
            //  pareciese roto. El precio era que la barra REAPARECÍA DE GOLPE
            //  en el sitio donde ya no estaba, sin recorrido y con el dock aún
            //  abajo: dos barras a la vez.
            //
            //  Quien aparta la barra es quien tiene que devolverla, y con su
            //  animación. El contrato de `barraApartada` es ese: si te la
            //  llevas, mira `K4.Isla.ocupadaPor` y tráela cuando alguien la
            //  pida. Un módulo que se abre mientras tanto espera lo que dure el
            //  regreso, y entonces sale con ella.
            readonly property bool sinBarra: apartada !== null

            readonly property int anchoIsla: sinBarra ? 0
                : (pluginVisible ? pluginVisible.islandWidth : 176)
            readonly property int altoIsla: sinBarra ? 0
                : (pluginVisible ? pluginVisible.islandHeight : Theme.baseHeight)

            //  ── qué hace la barra con el sitio del escritorio ─────────
            //
            //  Tres maneras, y las elige el usuario en Ajustes. «reserva» es
            //  lo de siempre: la franja plegada se le quita al escritorio y
            //  ninguna ventana se mete debajo. «encima» no le quita nada —la
            //  píldora flota sobre las ventanas— y «escondida» además la
            //  retira por el borde hasta que hay algo que enseñar.
            //
            //  Y una cuarta que no es un modo sino una REGLA, y por eso se
            //  resuelve a uno de los tres: «completa» reserva como siempre y se
            //  esconde solo mientras una ventana llena esta pantalla. Que es la
            //  queja de verdad —que la barra estorbe cuando estás usando la
            //  pantalla entera— sin perderla el resto del día.
            //
            //  Por pantalla y no global: con dos monitores, el vídeo a pantalla
            //  completa está en uno, y en el otro la barra no molesta a nadie.
            readonly property string modoSitio: Settings.islandSpace === "auto"
                ? (Workspaces.lleno(panelWindow.screen.name) ? "hidden" : "reserve")
                : Settings.islandSpace
            readonly property bool flotante: modoSitio !== "reserve"
            readonly property bool seEsconde: modoSitio === "hidden"

            //  Qué cuenta como «está pasando algo»: que la island la tenga
            //  alguien que no sea el reposo. No hay que inventarse un aviso
            //  nuevo — un módulo se activa EXACTAMENTE cuando tiene algo que
            //  enseñar.
            //
            //  Cuáles salen solos, mirado uno a uno y no de memoria: el aviso
            //  de notificación (`Notifs.toastOpen`), el volumen
            //  (`Audio.overlayOpen`), y
            //  cualquier módulo que abras con su atajo. El reproductor y el
            //  reloj NO: los dos piden `Island.hovered`, así que una canción
            //  que cambia sola no saca la barra — se ve al asomarse, como
            //  siempre.
            //
            //  Y el ratón en el borde cuenta igual: ir a buscarla es pedirla.
            //  Franjas incluidas — el toque de una franja dura lo que su flag
            //  (`zonaToque`, más abajo), y entretanto es un ratón más encima.
            readonly property bool ratonEncima: sobreIsla.hovered
                || sobreFilo.hovered || zonaToque
            readonly property bool hayQueEnsenar: ratonEncima
                || (!!pluginVisible && pluginVisible.name !== PluginManager.pillId)

            //  Vuelve al instante y se va con retraso. Al revés —irse en cuanto
            //  se cierra lo que había— la barra parpadea cada vez que cruzas el
            //  borde, y quedarse un segundo de más no le estorba a nadie.
            property bool retirada: false

            //  ── la franja que la trae de vuelta ─────────────────────
            //
            //  Escondida y retirada, el filo de la píldora es el único camino
            //  de vuelta — y solo si recuerdas en qué borde estaba. Mientras
            //  no está, las OTRAS tres franjas de la pantalla también la
            //  llaman: una tira fina a lo largo de cada borde que no es el
            //  suyo. De 1 px por defecto, que es la promesa más fina que un
            //  borde puede hacer: cada píxel por encima es un píxel de clics
            //  ajenos que la tira se queda. Y solo existe mientras la barra
            //  NO está: puesta, no cobra nada.
            //
            //  El toque se lleva un FLAG y no el hover: en cuanto la barra
            //  vuelve, las franjas salen de la máscara y su hover se queda
            //  cojo —el puntero no se ha movido, nadie garantiza que llegue
            //  un hovered nuevo—. Con el flag, la barra asoma lo que dura el
            //  toque (y su segundo de cortesía), y si el puntero la alcanza,
            //  la retiene el hover de siempre.
            property bool zonaToque: false

            function tocarZona() {
                if (!zonasVivas)
                    return
                zonaToque = true
                zonaTimer.restart()
            }

            readonly property bool zonasVivas: Settings.edgeZoneEnabled
                && seEsconde && retirada && !sinBarra && !Island.apartada

            function repensarRetirada() {
                //  Sin modo escondite no hay nada que retirar, y con la barra
                //  apartada tampoco: ahí manda quien se la llevó.
                if (!seEsconde || sinBarra) {
                    retiroTimer.stop()
                    retirada = false
                } else if (hayQueEnsenar) {
                    retiroTimer.stop()
                    retirada = false
                } else {
                    retiroTimer.restart()
                }
            }

            //  ── asomarse no es abrir, y quién cuenta el tiempo ────────
            //
            //  Rozar el filo trae la barra de vuelta y el ratón queda encima de
            //  la píldora, así que con la regla de siempre —el reloj se activa
            //  al pasar— el roce la abría del todo. Rozar un borde sin querer
            //  no es pedir nada: la píldora asoma, y para que se ABRA hay que
            //  quedarse.
            //
            //  Y quien cuenta ese medio segundo es `ratonEncima`, que incluye
            //  el filo, y NO el hover de la island. Atado solo a la island no
            //  se abría NUNCA dejando el ratón quieto: la barra vuelve y se
            //  mete bajo un puntero que no se ha movido, y sin movimiento Qt no
            //  tiene por qué entregarle un `hovered` nuevo a nadie. El filo, en
            //  cambio, ya estaba debajo del ratón antes de que la barra
            //  volviera, así que su `hovered` es de fiar.
            onRatonEncimaChanged: {
                if (!seEsconde)
                    return
                if (ratonEncima)
                    quedarseTimer.restart()
                else
                    quedarseTimer.stop()
            }

            onHayQueEnsenarChanged: repensarRetirada()
            onSeEscondeChanged: repensarRetirada()
            onSinBarraChanged: repensarRetirada()

            //  ── cambiar de dueño no es viajar ───────────────
            //
            //  Y se cuenta, que hay animaciones que no se paran solas: ver
            //  `aLaVista` en services/Island.qml.
            onRetiradaChanged: Island.publicarVista(screen.name, !retirada)

            Component.onCompleted: {
                //  The stage starts on the first loader, mounting
                //  whoever owns it today (the pill, as a rule).
                stageCurrent = stageOne
                stageOne.stageOwner = pluginVisible
                stageOne.live = true
                prevPluginVisible = pluginVisible
                repensarRetirada()
                Island.publicarVista(screen.name, !retirada)
            }

            //  Un monitor que se va deja de contar. Si no, su «sí la veo» se
            //  quedaría puesto para siempre y las animaciones seguirían
            //  corriendo por una pantalla que ya no está.
            Component.onDestruction: Island.publicarVista(screen.name, false)

            Timer {
                id: retiroTimer
                interval: 1600
                //  Se vuelve a preguntar al vencer, y no se da por hecho lo que
                //  era verdad al armarlo: entre medias ha podido volver el
                //  ratón, o una escena llevarse la barra abajo.
                onTriggered: panelWindow.retirada = panelWindow.seEsconde
                    && !panelWindow.sinBarra && !panelWindow.hayQueEnsenar
            }

            //  Cuánto dura el asomo que pide una franja: lo que tarda en
            //  llegar quien iba de verdad a por la barra, y no mucho más.
            //  Si el puntero la alcanza antes, la retiene el hover de
            //  siempre; si no, se va con la misma cortesía de siempre.
            Timer {
                id: zonaTimer
                interval: 1600
                onTriggered: panelWindow.zonaToque = false
            }

            anchors.top: !abajo
            anchors.bottom: abajo
            anchors.left: true
            anchors.right: true
            color: "transparent"
            //  No `aboveWindows` here: it WRITES the layer (true → Top)
            //  and would fight the layer binding above on this surface.
            focusable: true

            //  Exclusivo solo para lo que se escribe; el resto, bajo demanda.
            //  Poner Exclusive en todos los módulos abribles dejaba el teclado
            //  secuestrado mientras tuvieras cualquiera abierto: no se podía
            //  escribir en ninguna ventana.
            WlrLayershell.keyboardFocus: {
                //  Con un diálogo del sistema delante, el teclado es suyo.
                //
                //  Apartar la island de la vista no bastaba: seguía teniendo el
                //  foco en exclusiva, así que el selector de ficheros se veía
                //  pero no se podía ni escribir en él ni cerrarlo con Escape.
                if (Island.apartada)
                    return WlrKeyboardFocus.None
                const p = panelWindow.pluginVisible
                if (!p || p !== root.activePlugin || p.name === PluginManager.pillId)
                    return WlrKeyboardFocus.None
                if (p.grabKeyboard)
                    return WlrKeyboardFocus.Exclusive
                //  El punto medio para los juegos: exclusivo mientras el ratón
                //  esté encima —que es donde se juega— y devuelto al salir.
                //  Wayland no tiene un modo «al pasar», así que se conmuta con
                //  `Island.hovered`, que ya trae su margen de 240 ms y por eso
                //  no parpadea al rozar un borde.
                if (p.tecladoAlPasar && Island.hovered)
                    return WlrKeyboardFocus.Exclusive
                if (p.tecladoOpcional)
                    return WlrKeyboardFocus.OnDemand
                return WlrKeyboardFocus.None
            }

            //  Se reserva solo la franja plegada: las ventanas nunca se meten
            //  bajo la píldora, y todo lo que crece por encima flota.
            //
            //  Salvo que no haya píldora. Un módulo puede pedir la island de
            //  alto CERO, que es como se dice «ahora mismo aquí no hay barra»
            //  —lo usa quien se lleva la barra al borde de abajo—,
            //  y entonces seguir quitándole 34 px al escritorio sería cobrar
            //  por una franja que no se ve.
            //  Y quien lo decide es el módulo, no su altura.
            //
            //  Atado a `altoIsla > 0`, la franja se soltaba en el instante en
            //  que un módulo pedía la island a cero, y el escritorio entero
            //  pegaba un salto ANTES de que hubiera pasado nada. Quien manda la
            //  barra de viaje sabe cuándo ya no hace falta guardarle el sitio;
            //  la barra, no.
            //
            //  Se lee sin que el contrato la declare: un plugin que no la
            //  define da `undefined`, que no es `false`, así que reserva —el
            //  comportamiento de siempre para los otros veintisiete—.
            //  En PÍXELES, para que quien la mande pueda soltarla poco a poco
            //  y el escritorio acompañe en vez de pegar un salto.
            //  Y por encima de todo eso manda Ajustes: quien ha dicho que la
            //  barra no le quite sitio no lo ha dicho a medias, así que
            //  «encima» y «escondida» le ganan también a lo que pida un módulo.
            //  Incluida la franja que se guarda para el viaje al borde: si
            //  nunca se reservó nada, empezar a reservarlo justo al bajar la
            //  barra sería un salto del escritorio salido de la nada.
            exclusiveZone: panelWindow.flotante ? 0
                : (panelWindow.sinBarra
                   ? (panelWindow.apartada.reserva || 0)
                   : (panelWindow.pluginVisible
                      && typeof panelWindow.pluginVisible.reservaBarra === "number"
                      ? panelWindow.pluginVisible.reservaBarra : Theme.baseHeight))

            //  ── the surface never resizes ────────────────────────────
            //
            //  Resizing a layer surface costs a configure/ack roundtrip,
            //  and until the first frame at the new size arrives the
            //  compositor paints the OLD buffer stretched to the new size.
            //  Growing on demand made that artifact bookend every open and
            //  close: a pill-sized strip smeared down the whole screen when
            //  a deployed view turned the catcher on, a squeeze flash on
            //  the delayed shrink back. One-shot resize discipline shrank
            //  the window of pain but could not close it.
            //
            //  So the window is screen-tall for good: the island animates
            //  inside it, the retired bar slides off inside it, gestures
            //  push it around inside it, and the outside-click catcher (see
            //  `cerrarConClicFuera`) always has surface under whatever it
            //  must catch. What the surface covers only matters for input,
            //  and input is decided by the MASK below — outside the input
            //  region, clicks pass through as if the surface wasn't there.
            implicitHeight: panelWindow.screen.height
            //  Sin la island, la ventana no acepta ni un clic.
            //
            //  No basta con dejar de dibujarla: la región de entrada seguía
            //  siendo la suya, así que un selector de ficheros que le quedara
            //  debajo perdía todos los clics de esa franja sin que se viera por
            //  qué. Con la región vacía, el ratón pasa de largo.
            //  Y escondida, lo que recibe el ratón es el filo y no la island.
            //  La island NO se ha movido —lo que se desplaza es su dibujo—, así
            //  que dejarla de región de entrada sería seguir tragándose los
            //  clics de una barra que no se ve.
            //
            //  Pero el filo entra SIEMPRE que la barra se esconda, no solo
            //  mientras está fuera, y eso es lo que arregla el agujero de los
            //  360 ms del regreso: la región de una `Region { item }` sigue a
            //  la TRANSFORMADA del item, así que mientras la island vuelve su
            //  región todavía está fuera de la pantalla. En ese rato la
            //  superficie no recibía nada: el puntero se lo quedaba la ventana
            //  de debajo —salía su cursor de redimensionar, pegado al borde— y
            //  la barra que acababa de volver no se enteraba de tener el ratón
            //  encima. Con el filo dentro, el puntero no se va nunca.
            mask: Region {
                item: Island.apartada ? null : island

                //  The catcher's region: with a view open, the whole surface
                //  takes input — including the parts no island covers — so
                //  the outside tap has somewhere to land. See `cazaClics`.
                Region {
                    item: panelWindow.cerrarConClicFuera ? cazaClics : null
                    intersection: Intersection.Combine
                }

                Region {
                    item: (Island.apartada || panelWindow.sinBarra
                           || !panelWindow.seEsconde) ? null : filo
                    intersection: Intersection.Combine
                }

                //  The rim is drawn on all four borders but only answers
                //  while the bar is away, and only on the borders it does
                //  not live on: its own border's path back is the filo,
                //  which already exists. Seeing the rim and having it take
                //  input are different things, on purpose.
                Region {
                    item: (!Island.apartada
                           && (panelWindow.zonasVivas
                               && Settings.barPosition !== "bottom"))
                        ? zonaArriba : null
                    intersection: Intersection.Combine
                }

                Region {
                    item: (!Island.apartada
                           && (panelWindow.zonasVivas
                               && Settings.barPosition !== "top"))
                        ? zonaAbajo : null
                    intersection: Intersection.Combine
                }

                Region {
                    item: (!Island.apartada
                           && panelWindow.zonasVivas)
                        ? zonaIzquierda : null
                    intersection: Intersection.Combine
                }

                Region {
                    item: (!Island.apartada
                           && panelWindow.zonasVivas)
                        ? zonaDerecha : null
                    intersection: Intersection.Combine
                }
            }

            //  ── the catcher: what the outside tap falls on ─────────────
            //
            //  No visuals and no cost; it exists so that a tap outside the
            //  island, with a view open, is received instead of lost. It is
            //  declared BEFORE `filo` and the island on purpose: they stack
            //  above it, so the island keeps every click aimed at it — and a
            //  tap on its transparent wings closes, which is right: that is
            //  the shell's own empty part.
            //
            //  Not `visible: false` — hidden items get no mouse. When nothing
            //  is open, the MASK (not visibility) keeps this inert: outside
            //  the input region nothing arrives here.
            Item {
                id: cazaClics
                anchors.fill: parent

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        //  Escape's own door, not a shortcut around it:
                        //  whatever the view does on close — stay put for its
                        //  exit animation, hand the island over — keeps
                        //  working exactly the same.
                        const p = panelWindow.pluginVisible
                        if (p && typeof p.close === "function")
                            p.close()
                    }
                }
            }

            //  ── el filo: por dónde se la llama cuando no está ─────────
            //
            //  Retirada, no hay pastilla que rozar para traerla de vuelta. Esta
            //  tira invisible del borde es lo que se roza.
            //
            //  Del ANCHO DE LA PÍLDORA y no de la pantalla entera, que es la
            //  diferencia entre un escondite y una barra que estorba sin verse:
            //  una tira de punta a punta se traga los clics de todo el borde
            //  —las pestañas del navegador, la cruz de una ventana maximizada—
            //  y eso no lo ha pedido nadie.
            Item {
                id: filo
                x: island.x
                width: island.width
                height: 4
                anchors.top: panelWindow.abajo ? undefined : parent.top
                anchors.bottom: panelWindow.abajo ? parent.bottom : undefined
                //  Invisible, pero NO `visible: false`: un item oculto no
                //  recibe ratón, y recibirlo es para lo único que existe.
                opacity: 0

                //  Sigue contando con la barra ya fuera, a propósito. Al
                //  volver, la island tapa el filo sin que el ratón se haya
                //  movido —y sin movimiento nadie garantiza que le llegue un
                //  `hovered` nuevo—, así que si el filo dejase de contar en ese
                //  instante la barra se iría otra vez con el ratón encima.
                HoverHandler { id: sobreFilo }
            }

            //  ── the rim: island colour along every screen border ────
            //
            //  Not a highlight and not a thing with a colour of its own:
            //  the rim IS the island's material, drawn along all four
            //  borders of the screen, and the island attaches to it
            //  wherever it lives — same colour, flush edge, one thing. It
            //  follows the island's colour wherever the theme takes it, on
            //  purpose and without a setting: a rim that could disagree
            //  with the island would not be attached to it.
            //
            //  One frame and not four bars, because the corners matter:
            //  where one border turns into the next, the rim rounds
            //  INWARD — a radius the user sets, six by default — and four
            //  rectangles cannot draw that turn, only butt into each other.
            //  The frame is a Shape with a hole: the outer edge the screen,
            //  the inner edge the desktop, rounded.
            //
            //  The rim also carries the summons: while the bar is away, the
            //  borders it does not live on take input — that is what the
            //  four invisible strips below the Shape are for, full-length
            //  along each border and never seen. Touch one and the bar
            //  comes back for as long as the touch lasts, carried by a flag
            //  and not by the hover: in the moment the bar returns, the
            //  strips leave the input mask, and a hover whose item stopped
            //  receiving cannot be trusted to say anything. Ver `zonaToque`.
            Shape {
                id: aro
                visible: Settings.edgeZoneEnabled
                anchors.fill: parent
                antialiasing: true

                //  The hole: the desktop, inset by the rim's thickness and
                //  rounded at its corners. Clamped so no thickness can
                //  swallow the screen and no radius can out-run its rect.
                readonly property real t: Math.max(0, Math.min(
                    Settings.edgeZoneSize, width / 2, height / 2))
                readonly property real huecoW: width - 2 * t
                readonly property real huecoH: height - 2 * t
                readonly property real r: Math.max(0, Math.min(
                    Settings.rimRadius, huecoW / 2, huecoH / 2))

                ShapePath {
                    fillColor: Theme.islandBg
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill

                    startX: 0
                    startY: 0
                    PathLine { x: aro.width; y: 0 }
                    PathLine { x: aro.width; y: aro.height }
                    PathLine { x: 0; y: aro.height }
                    PathLine { x: 0; y: 0 }

                    PathLine { x: aro.t + aro.r; y: aro.t }
                    PathLine { x: aro.t + aro.huecoW - aro.r; y: aro.t }
                    PathArc { x: aro.t + aro.huecoW; y: aro.t + aro.r
                              radiusX: aro.r; radiusY: aro.r
                              direction: PathArc.Clockwise }
                    PathLine { x: aro.t + aro.huecoW; y: aro.t + aro.huecoH - aro.r }
                    PathArc { x: aro.t + aro.huecoW - aro.r; y: aro.t + aro.huecoH
                              radiusX: aro.r; radiusY: aro.r
                              direction: PathArc.Clockwise }
                    PathLine { x: aro.t + aro.r; y: aro.t + aro.huecoH }
                    PathArc { x: aro.t; y: aro.t + aro.huecoH - aro.r
                              radiusX: aro.r; radiusY: aro.r
                              direction: PathArc.Clockwise }
                    PathLine { x: aro.t; y: aro.t + aro.r }
                    PathArc { x: aro.t + aro.r; y: aro.t
                              radiusX: aro.r; radiusY: aro.r
                              direction: PathArc.Clockwise }
                }
            }

            //  The rim's invisible fingers, one per border: only while the
            //  bar is away, and only on the borders it does not live on,
            //  does the mask let them take input. Their ids feed the mask.
            //  A touch calls `tocarZona()`, which raises the
            //  `zonaToque` flag that counts as the pointer being above
            //  while the bar comes back.
            Item {
                id: zonaArriba
                width: parent.width
                height: Settings.edgeZoneSize
                anchors.top: parent.top
                opacity: 0

                HoverHandler {
                    id: tocaArriba
                    onHoveredChanged: if (hovered) panelWindow.tocarZona()
                }
            }

            Item {
                id: zonaAbajo
                width: parent.width
                height: Settings.edgeZoneSize
                anchors.bottom: parent.bottom
                opacity: 0

                HoverHandler {
                    id: tocaAbajo
                    onHoveredChanged: if (hovered) panelWindow.tocarZona()
                }
            }

            Item {
                id: zonaIzquierda
                width: Settings.edgeZoneSize
                height: parent.height
                anchors.left: parent.left
                opacity: 0

                HoverHandler {
                    id: tocaIzquierda
                    onHoveredChanged: if (hovered) panelWindow.tocarZona()
                }
            }

            Item {
                id: zonaDerecha
                width: Settings.edgeZoneSize
                height: parent.height
                anchors.right: parent.right
                opacity: 0

                HoverHandler {
                    id: tocaDerecha
                    onHoveredChanged: if (hovered) panelWindow.tocarZona()
                }
            }

            Item {
                id: island

                //  Ya no siempre al centro: la island vive en el punto del
                //  borde que digan Ajustes, o donde la coloque temporalmente
                //  un plugin (services/Island.qml).
                //
                //  Se anima la FRACCIÓN y no la x: la x es cálculo directo,
                //  así que al cambiar el ancho se recoloca en el mismo frame
                //  —como hacía el ancla al centro— y no va a remolque con su
                //  propia animación, que era lo que descentraba la island al
                //  abrir y cerrar módulos.
                //
                //  Con vistas que abren en cualquier borde hacen falta DOS
                //  fracciones, una por eje: el del borde queda clavado a su
                //  lado (0 o 1) y el libre lleva la alineación. Una vista que
                //  abre en otro borde se DESLIZA hasta él con la misma curva
                //  que siempre tuvo la alineación, ahora en los dos ejes.
                //  Y sin anclas: la y también es cálculo directo, con lo que
                //  crecer hacia fuera del borde —el de siempre hacia abajo,
                //  el nuevo hacia la derecha— sale solo de que la fracción
                //  clavada no se mueve mientras la isla engorda.
                property real fxSuave: panelWindow.fraccionX
                property real fySuave: panelWindow.fraccionY

                Behavior on fxSuave {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.42
                    }
                }

                Behavior on fySuave {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.42
                    }
                }

                //  ── crecimiento hacia UN solo lado ───────────────
                //
                //  Mientras la píldora lleva extensiones de flanco (lo que
                //  los plugins declaran por K4.Capsule), la island crece
                //  hacia el borde que toque y NO hacia los dos a la vez
                //  como de costumbre: si no, el cuerpo de la píldora se
                //  deslizaría medio ancho de extensión cada vez que una
                //  entra o sale.
                //
                //  La cuenta mantiene la PÍLDORA donde estaba —su ancho sin
                //  extensiones, alas incluidas— y lo que crece por cada
                //  lado se suma por ese lado solo. Sigue siendo cálculo
                //  directo, sin animación propia, para que el cuerpo no vaya
                //  a remolque del ancho mientras este crece con su Behavior.
                readonly property int extDerecha: pluginVisible
                    && pluginVisible.name === PluginManager.pillId
                    ? Extensions.rightWidth : 0
                readonly property int extIzquierda: pluginVisible
                    && pluginVisible.name === PluginManager.pillId
                    ? Extensions.leftWidth : 0

                //  La x que dejaría la píldora clavada, y la de verdad con
                //  tope: una extensión larga con la island muy pegada a un
                //  borde no puede salirse de la pantalla. Si el tope actúa,
                //  la píldora cede unos píxeles —solo pasa en los extremos
                //  de la alineación— y el contenido viaja con la silueta,
                //  que es lo que importa: contenido y dibujo no se separan.
                readonly property real xQuerida: (parent.width - width) * fxSuave
                    + extDerecha * fxSuave
                    - extIzquierda * (1 - fxSuave)
                x: Math.max(0, Math.min(parent.width - width, xQuerida))
                y: Math.max(0, Math.min(parent.height - height,
                    (parent.height - height) * fySuave))

                //  A vertical island — hanging from a left or right rim —
                //  carries its wings along its vertical axis: the body grows
                //  two wings TALL, and the content zone below reads them as
                //  margins, so the first and last rows get the same air the
                //  sides always had instead of riding under the end corners.
                readonly property bool vertical:
                    silueta.lado === "left" || silueta.lado === "right"

                width: Math.min(parent.width, panelWindow.anchoIsla + Theme.wing * 2)
                //  Clamped to the parent as the width is: a view taller than
                //  the screen (none today, the ceiling is Theme's 880) must
                //  not push the island past the surface it lives in.
                height: Math.min(parent.height, panelWindow.altoIsla
                    + (vertical ? Theme.wing * 2 : 0))

                // Ver services/Island.qml: apartarse mientras haya un
                // diálogo del sistema abierto.
                opacity: Island.apartada ? 0 : 1

                readonly property real bodyRadius: Math.min(32, height / 2)

                // ESC cierra el módulo que esté abierto, sea cual sea.
                //
                // Va aquí y no en cada vista por dos razones: los módulos que
                // vengan después lo heredan sin hacer nada, y las vistas que ya
                // tratan la tecla —el lanzador, el portapapeles, la clave de
                // wifi— la consumen antes de llegar hasta aquí, que es
                // justamente lo que se quiere: primero cancela lo de dentro y
                // solo después cierra el módulo.
                focus: true

                //  Y pedirlo de verdad una vez, que `focus: true` a secas no
                //  basta: hasta que ALGUIEN dentro de esta ventana toma el
                //  foco activo, no hay foco activo, y las teclas que llegan a
                //  la capa no las recibe nadie. Se veía así: el ESC no cerraba
                //  ningún módulo hasta que abrías el lanzador —que sí lo pide,
                //  para su campo de texto— y a partir de ahí funcionaba para
                //  siempre. Un atajo que empieza a ir cuando has usado otra
                //  cosa es peor que uno que no va: parece cosa tuya.
                //
                //  Va una vez al crearse —en el `Component.onCompleted` de
                //  abajo, que uno por objeto o el QML no carga— y antes de que
                //  exista ninguna vista, así que no le quita el foco a nadie:
                //  quien lo quiera lo pide después y gana.
                //
                //  Y hay que RECUPERARLO, que es la otra mitad. Cuando el que
                //  lo tenía se va sin devolverlo —un campo que se oculta al
                //  cerrar su buscador, una vista que se destruye— la ventana
                //  se queda sin foco activo y a partir de ahí el ESC no lo
                //  recibe nadie otra vez. Se vigila quién lo tiene y, cuando
                //  no lo tiene nadie, vuelve aquí. Solo cuando no hay nadie:
                //  si alguien lo pidió, es suyo.
                readonly property var focoVentana: island.Window.activeFocusItem

                onFocoVentanaChanged: if (!focoVentana) Qt.callLater(reclamarFoco)

                function reclamarFoco() {
                    if (!island.Window.activeFocusItem)
                        island.forceActiveFocus()
                }

                Keys.onPressed: function (ev) {
                    if (ev.key !== Qt.Key_Escape)
                        return
                    const p = panelWindow.pluginVisible
                    if (p && typeof p.close === "function") {
                        p.close()
                        ev.accepted = true
                    }
                }

                Behavior on width {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.42
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.32
                    }
                }

                // ── geometría publicada, para pintar fuera de la island ──
                //
                //  K4.Isla.rect: coordenadas de pantalla, solo la principal.
                //  Un plugin con K4.Ventana ancla aquí lo que asoma. La x y
                //  la y son las de verdad —la island ya no va anclada a
                //  ningún borde— así que una vista que se desliza a su borde
                //  nuevo arrastra consigo lo que le cuelgue.
                onXChanged: publicarRect()
                onYChanged: publicarRect()
                onWidthChanged: publicarRect()
                onHeightChanged: publicarRect()
                Component.onCompleted: {
                    publicarRect()
                    forceActiveFocus()      // el ESC de arriba; ver por qué
                }

                function publicarRect() {
                    Island.publicarRect(panelWindow.screen.name, {
                        x: island.x, y: island.y,
                        ancho: island.width, alto: island.height
                    }, panelWindow.modelData === Quickshell.screens[0])
                }

                // ── gestos: el plugin pide (services/Island.qml), esto anima ──
                //
                //  Un desplazamiento del contenido, nunca de la ventana: mover
                //  una layer surface reajustaría el escritorio entero.
                transform: [
                    Translate { id: gestoTr },
                    //  ── y el escondite, por el mismo camino ──────────
                    //
                    //  La que se retira se va POR EL BORDE, y también
                    //  desplazando su dibujo: encoger la superficie o soltar el
                    //  ancla movería el escritorio entero cada vez, que es
                    //  justo lo que este modo viene a no hacer.
                    Translate {
                        id: retiroTr
                        y: panelWindow.retirada
                            ? (panelWindow.abajo ? island.height + 6
                                                 : -(island.height + 6))
                            : 0

                        //  La misma curva en los dos sentidos, y no una por
                        //  sentido atada a `retirada`: la `y` se recalcula
                        //  ANTES que la duración y la curva —el binding es más
                        //  viejo, se conecta primero— así que cada tránsito
                        //  habría salido con los valores del anterior.
                        //
                        //  Y SIN rebote, que aquí el rebote de la casa está
                        //  mal. `OutBack` se pasa del destino y vuelve, y el
                        //  destino es cero: pasarse de cero es separarse del
                        //  borde. La silueta lleva esquinas invertidas para
                        //  FUNDIRSE con el canto de la pantalla, así que ese
                        //  píxel de aire al llegar no se lee como un rebote
                        //  sino como un salto y una raya. Comprobado a ojo: se
                        //  veía. Lo que se quiere es que frene, no que bote.
                        Behavior on y {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]

                readonly property bool gestoEnCurso: aniSacudida.running
                    || aniEmpujon.running || aniTiron.running

                SequentialAnimation {
                    id: aniSacudida
                    property real f: 1
                    NumberAnimation { target: gestoTr; property: "x"; to: -8 * aniSacudida.f; duration: 40 }
                    NumberAnimation { target: gestoTr; property: "x"; to: 7 * aniSacudida.f; duration: 70 }
                    NumberAnimation { target: gestoTr; property: "x"; to: -5 * aniSacudida.f; duration: 70 }
                    NumberAnimation { target: gestoTr; property: "x"; to: 3 * aniSacudida.f; duration: 60 }
                    NumberAnimation { target: gestoTr; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                }

                //  Los gestos verticales empujan hacia DENTRO de la pantalla:
                //  con la barra abajo, el empujón y el tirón van hacia arriba.
                readonly property real gestoDir: panelWindow.abajo ? -1 : 1

                SequentialAnimation {
                    id: aniEmpujon
                    property real f: 1
                    NumberAnimation { target: gestoTr; property: "y"; to: 26 * aniEmpujon.f * island.gestoDir; duration: 150; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gestoTr; property: "y"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }

                SequentialAnimation {
                    id: aniTiron
                    property real f: 1
                    NumberAnimation { target: gestoTr; property: "y"; to: 10 * aniTiron.f * island.gestoDir; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gestoTr; property: "y"; to: 2 * island.gestoDir; duration: 90 }
                    NumberAnimation { target: gestoTr; property: "y"; to: 12 * aniTiron.f * island.gestoDir; duration: 90 }
                    NumberAnimation { target: gestoTr; property: "y"; to: 0; duration: 140; easing.type: Easing.OutQuad }
                }

                Connections {
                    target: Island
                    function onGesto(nombre, fuerza) {
                        //  Corta el que hubiera: dos gestos a la vez son un
                        //  temblor sin forma.
                        aniSacudida.stop(); aniEmpujon.stop(); aniTiron.stop()
                        gestoTr.x = 0; gestoTr.y = 0
                        if (nombre === "sacudida") { aniSacudida.f = fuerza; aniSacudida.start() }
                        else if (nombre === "empujon") { aniEmpujon.f = fuerza; aniEmpujon.start() }
                        else if (nombre === "tiron") { aniTiron.f = fuerza; aniTiron.start() }
                    }
                }

                //  ── asomarse no es abrir ──────────────────────────
                //
                //  Lo que hace que pasar el ratón despliegue la island: el
                //  reloj se activa con `Island.hovered`. Se separa del gesto
                //  para poder retrasarlo, que es lo único que cambia aquí.
                function abrirPorRaton() {
                    if (!root.activePlugin || root.activePlugin.name === PluginManager.pillId)
                        Island.pedirPantalla(panelWindow.screen.name)
                    else if (root.activePlugin.name === "clock"
                             || root.activePlugin.name === "player")
                        Island.usarPantalla(panelWindow.screen.name)
                    Island.hovered = true
                }

                HoverHandler {
                    id: sobreIsla
                    onHoveredChanged: {
                        if (hovered) {
                            //  Esto va SIEMPRE al instante: no abre nada, solo
                            //  impide que se cierre lo que ya estaba. Retrasarlo
                            //  dejaría irse un aviso mientras vas hacia él.
                            hoverExitTimer.stop()
                            root.holdHoverExit()
                            Notifs.holdToast()

                            //  Escondida, el reloj de la espera no lo lleva
                            //  esto: lo lleva `ratonEncima` en panelWindow, que
                            //  cuenta también el filo. Ver por qué allí.
                            //
                            //  Salvo que ya haya algo puesto. La espera existe
                            //  para que rozar un borde VACÍO no despliegue el
                            //  reloj; si la island ya está fuera enseñando algo
                            //  —un aviso, el asomo del reproductor—, ir hacia
                            //  ella es ir a por eso, y hacerte esperar medio
                            //  segundo es perder el tiempo justo cuando lo que
                            //  quieres se está yendo. Con asomos de tres
                            //  segundos, ese medio segundo era la diferencia
                            //  entre alcanzarlo y verlo desaparecer.
                            const enReposo = !panelWindow.pluginVisible
                                || panelWindow.pluginVisible.name === PluginManager.pillId
                            if (!panelWindow.seEsconde || !enReposo)
                                island.abrirPorRaton()
                        } else {
                            hoverExitTimer.restart()
                            root.armHoverExit()
                            Notifs.resumeToast()
                        }
                    }
                }

                //  Medio segundo: más que un roce, menos que una espera.
                Timer {
                    id: quedarseTimer
                    interval: 500
                    onTriggered: island.abrirPorRaton()
                }

                // clic derecho en cualquier parte → centro de control
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.abrirPanelEn(panelWindow.screen.name)
                }

                // ── the corner the island has reached ────────────────
                //
                // A placement endpoint becomes a true two-wall shape once
                // the animated body makes contact with both walls — never
                // earlier, or the island would wear a corner while it still
                // crosses open screen. And it LATCHES on first contact: the
                // position curve is OutBack, it overshoots the wall and
                // settles back, and a shape re-judged from raw contact would
                // flicker corner → edge → corner during that bounce. The
                // latch releases when the placement stops being a corner,
                // or when a different corner is aimed at mid-flight.
                property string esquinaTocada: ""

                function esquinaDestino() {
                    const p = panelWindow.lugar
                    if (p.align > 0.5 && p.align < 99.5)
                        return ""
                    const fin = p.align >= 99.5
                    if (p.side === "top")
                        return fin ? "tr" : "tl"
                    if (p.side === "bottom")
                        return fin ? "br" : "bl"
                    if (p.side === "left")
                        return fin ? "bl" : "tl"
                    return fin ? "br" : "tr"
                }

                function reevaluarEsquina() {
                    const destino = esquinaDestino()
                    if (destino === "") {
                        esquinaTocada = ""
                        return
                    }
                    const tocaIzq = island.x <= 0.5
                    const tocaDer = island.x + island.width
                        >= island.parent.width - 0.5
                    const tocaArriba = island.y <= 0.5
                    const tocaAbajo = island.y + island.height
                        >= island.parent.height - 0.5
                    const ahora = tocaArriba && tocaIzq ? "tl"
                        : tocaArriba && tocaDer ? "tr"
                        : tocaAbajo && tocaIzq ? "bl"
                        : tocaAbajo && tocaDer ? "br" : ""
                    if (ahora.length > 0)
                        esquinaTocada = ahora
                    else if (esquinaTocada !== destino)
                        esquinaTocada = ""
                }

                Connections {
                    target: panelWindow
                    function onLugarChanged() { island.reevaluarEsquina() }
                }

                Connections {
                    target: island
                    function onXChanged() { island.reevaluarEsquina() }
                    function onYChanged() { island.reevaluarEsquina() }
                }

                // ── la silueta: cuerpo + esquinas invertidas que funden con el borde
                //  La forma vive en `core/SiluetaIsla.qml`: la dibujan la barra y
                //  la previsualización de Ajustes, y una previsualización que
                //  dibujara otra cosa no previsualizaría nada.
                SiluetaIsla {
                    id: silueta
                    anchors.fill: parent
                    ala: Theme.wing
                    cuerpoRadio: island.bodyRadius
                    relleno: Theme.islandBg
                    //  The shape turns MIDWAY, in open water. Turning at
                    //  departure dressed a top island in bottom corners
                    //  while it still stood on the top rim; turning on
                    //  landing kept the old shape a beat past arrival.
                    //  Between the two there is a stretch where the shape
                    //  cannot be wrong: the middle of the screen, where no
                    //  rim is near enough to contradict it. So the side is
                    //  where the island IS, not where it is going — the
                    //  destination only picks the FAMILY (vertical sides
                    //  judge by height, horizontal by width), and the
                    //  island's own position does the judging: it leaves
                    //  dressed as where it came from, turns as it crosses
                    //  the middle, and arrives already true. At rest the
                    //  same rule reads the rim it sits on — no latch, no
                    //  handler, a binding that re-judges every frame of
                    //  the glide.
                    lado: {
                        const destino = panelWindow.lugar.side
                        if (destino === "left" || destino === "right")
                            return island.x + island.width / 2
                                < island.parent.width / 2
                                ? "left" : "right"
                        return island.y + island.height / 2
                            < island.parent.height / 2
                            ? "top" : "bottom"
                    }
                }

                // ── the corner's second wall ────────────────────────
                //
                // A sibling of the silhouette, not a child of it: the
                // silhouette renders through an MSAA layer sized to the
                // item, and material that must reach OUTSIDE it — the wings
                // along the adjacent wall — cannot come out of that
                // texture. Here, unlayered, the same rectangles and vector
                // wings draw past the island's bounds, over the rim, and
                // the corner reads as grown out of the frame: wall band,
                // squared corner, and a long shallow tongue along the
                // neighbouring wall, one material with no seam. Only the
                // added material fades (140 ms), so the shape never snaps.
                EdgeAttachedShape {
                    anchors.fill: parent
                    attachTop: island.esquinaTocada === "tl"
                               || island.esquinaTocada === "tr"
                    attachBottom: island.esquinaTocada === "bl"
                                  || island.esquinaTocada === "br"
                    attachLeft: island.esquinaTocada === "tl"
                                || island.esquinaTocada === "bl"
                    attachRight: island.esquinaTocada === "tr"
                                 || island.esquinaTocada === "br"
                    blending: true
                    cornerRadius: island.bodyRadius
                    rimThickness: Settings.edgeZoneEnabled
                        ? Settings.edgeZoneSize : 0
                    blendReach: Theme.wing * 2
                    blendDepth: Theme.wing
                    fillColor: Theme.islandBg
                    opacity: island.esquinaTocada.length > 0 ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: 140 }
                    }
                }

                // ── zona de contenido (dentro del cuerpo, sin las alas)
                //
                //  The wings sit on the axis the island RUNS along: left and
                //  right margins for a horizontal one, and for a VERTICAL one
                //  top and bottom as well — the silhouette's wing cuts and
                //  end corners live there, and without the margin the first
                //  and last rows ride under them while the sides keep air.
                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.wing
                    anchors.rightMargin: Theme.wing
                    anchors.topMargin: island.vertical ? Theme.wing : 0
                    anchors.bottomMargin: island.vertical ? Theme.wing : 0
                    clip: true

                    // Debajo de toda vista: los botones y sliders se quedan sus
                    // clics, lo que no coja nadie cae aquí.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backgroundTap(panelWindow.screen.name,
                                                      panelWindow.pluginVisible)
                    }

                    // Se dispone al tamaño final y se destapa con el clip, así
                    // que no hay recálculo de layout durante la animación.
                    //
                    //  Sin desplazamiento propio: el ancho de esta caja ES el
                    //  de la vista que la llena —extensiones de flanco
                    //  incluidas cuando la píldora las lleva— y su centro ya
                    //  es el sitio. Correrla aquí separaba el contenido de la
                    //  silueta media extensión: los iconos del otro extremo
                    //  se iban por fuera de la cápsula.
                    Item {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: panelWindow.anchoIsla
                        height: panelWindow.altoIsla

                        //  ── the stage: one view live, one leaving ────
                        //
                        //  TWO loaders trading the stage, not one
                        //  re-keyed: a single one must destroy the
                        //  outgoing view to mount the next, and a
                        //  superseded popup deserves better — its
                        //  LIVE item stays mounted while the next
                        //  view arrives beneath it, fades out over
                        //  the hand-off, and only then is released.
                        //  The rest of the single loader's design
                        //  stays: the stage is keyed on the plugin
                        //  that owns it, never on the instance list,
                        //  so churn around it (toggles, reloads,
                        //  rescans) is nobody's business but the
                        //  owner's.
                        Loader {
                            id: stageOne

                            property var stageOwner: null
                            property bool live: false
                            property bool departing: false
                            property real exitW: 0
                            property real exitH: 0

                            //  Anchored to the top and centred, sized
                            //  by the box — the incoming view lays
                            //  out at its final size and the growing
                            //  island unveils it (see the box above).
                            //  The departing one freezes the size it
                            //  had: the box is about to snap to the
                            //  newcomer's, and re-flowing a view that
                            //  is on its way out would tear it.
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: departing ? exitW : parent.width
                            height: departing ? exitH : parent.height

                            //  The leaving view is paint, not input:
                            //  for the fade's length it sits ABOVE the
                            //  newcomer and must not eat its clicks.
                            z: live ? 0 : 1
                            enabled: live

                            active: stageOwner !== null
                                && (departing || stageOwner.viewLoaded)
                            sourceComponent: stageOwner !== null
                                && (departing || stageOwner.viewLoaded)
                                ? stageOwner.view : null
                            onStatusChanged: {
                                const p = stageOwner
                                if (!p)
                                    return
                                //  Natives have no catalog row to hang an
                                //  error on; a load failure still lands in
                                //  the bar log from the Loader itself.
                                if (p.nativo === true)
                                    return
                                if (status === Loader.Error)
                                    PluginManager.registrarError(
                                        p.name, "The view could not be loaded")
                                else if (status === Loader.Ready)
                                    PluginManager.limpiarError(p.name)
                            }

                            //  The end of the fade is the end of the
                            //  view: released, reset, the loader idle
                            //  for its next turn on stage.
                            NumberAnimation {
                                id: fadeOne
                                target: stageOne
                                property: "opacity"
                                to: 0
                                duration: 180
                                easing.type: Easing.OutCubic
                                onStopped: {
                                    stageOne.stageOwner = null
                                    stageOne.departing = false
                                    stageOne.opacity = 1
                                }
                            }
                        }

                        Loader {
                            id: stageTwo

                            property var stageOwner: null
                            property bool live: false
                            property bool departing: false
                            property real exitW: 0
                            property real exitH: 0

                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: departing ? exitW : parent.width
                            height: departing ? exitH : parent.height
                            z: live ? 0 : 1
                            enabled: live
                            active: stageOwner !== null
                                && (departing || stageOwner.viewLoaded)
                            sourceComponent: stageOwner !== null
                                && (departing || stageOwner.viewLoaded)
                                ? stageOwner.view : null
                            onStatusChanged: {
                                const p = stageOwner
                                if (!p)
                                    return
                                //  Natives have no catalog row to hang an
                                //  error on; a load failure still lands in
                                //  the bar log from the Loader itself.
                                if (p.nativo === true)
                                    return
                                if (status === Loader.Error)
                                    PluginManager.registrarError(
                                        p.name, "The view could not be loaded")
                                else if (status === Loader.Ready)
                                    PluginManager.limpiarError(p.name)
                            }

                            NumberAnimation {
                                id: fadeTwo
                                target: stageTwo
                                property: "opacity"
                                to: 0
                                duration: 180
                                easing.type: Easing.OutCubic
                                onStopped: {
                                    stageTwo.stageOwner = null
                                    stageTwo.departing = false
                                    stageTwo.opacity = 1
                                }
                            }
                        }
                    }
                }

}




        }
    }

    //  Whether a summoned view is deployed from the island right
    //  now. Pill peeks and transients do not count: they are
    //  glances, not openings.
    readonly property bool hayVistaInvocada: {
        const p = activePlugin
        return !!p && p.name !== PluginManager.pillId
               && p.colocable && !p.transitorio
    }

    // ── the dim behind the summoned view ────────────────
    //
    //  One surface, always mapped: mapping a layer surface on demand
    //  shows the compositor's configure race — a dim that seems to
    //  grow out of an edge — and dimming is the one effect that must
    //  land all at once or not at all. The surface stays up and fully
    //  transparent; the dim is an opacity flip with no animation, so
    //  there is never a frame of half-dimmed screen.
    //
    //  While a summoned view is out it quiets the rest of the screen
    //  behind it. The island lives in Overlay, above this, so the
    //  pill and its hover views stay bright and alive.
    //
    //  The surface is always click-through: the island view keeps its
    //  own catcher above, which owns the outside-click — a
    //  transparent layer that eats clicks is a desktop that stopped
    //  answering.
    PanelWindow {
        id: fondoDim

        readonly property bool oscura: root.hayVistaInvocada

        screen: {
            const nombre = Island.pantallaActiva
            const lista = Quickshell.screens
            for (let i = 0; i < lista.length; ++i)
                if (lista[i].name === nombre)
                    return lista[i]
            return lista.length > 0 ? lista[0] : null
        }

        anchors.top: true
        anchors.left: true
        anchors.right: true
        anchors.bottom: true
        color: "transparent"

        WlrLayershell.namespace: "k4-popup-dim"
        WlrLayershell.layer: WlrLayer.Top

        Item { id: agujero }          // 0×0: the nothing an empty mask is
        property Region regionNada: Region { item: agujero }

        mask: regionNada

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5)
            opacity: fondoDim.oscura ? 1 : 0
            //  The SURFACE is what must land at once — it stays
            //  mapped and only the opacity moves, so there is never
            //  a configure race (see the header). The opacity itself
            //  breathes quickly: a dim that snaps off while the view
            //  is still leaving flashes the desktop behind it, and
            //  the end of an exit deserves the same ease as its
            //  travel.
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
    }

    Timer {
        id: hoverExitTimer
        interval: 240
        onTriggered: Island.hovered = false
    }

    // ── salida del ratón ──────────────────────────────────────────
    // Los módulos que se abren con el ratón se van al sacarlo, pero cada uno
    // decide qué hacer: aquí solo se cuenta el tiempo y se avisa al activo.
    function armHoverExit() {
        const p = activePlugin
        if (!p || !p.closeOnHoverExit)
            return

        pluginHoverExitTimer.interval = p.hoverExitDelay
        pluginHoverExitTimer.restart()
    }

    function holdHoverExit() { pluginHoverExitTimer.stop() }

    Timer {
        id: pluginHoverExitTimer
        interval: 700
        onTriggered: {
            const p = root.activePlugin
            if (!p)
                return
            if (p.closeOnHoverExit)
                p.hoverTimedOut()
        }
    }

}
