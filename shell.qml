//  k4 — host of the island.
//
//  No module logic lives here: this mounts the surface, draws the silhouette
//  and decides which surface keeps the island. A new plugin is a folder in
//  plugins/ registered in plugins/catalog.json; a new native feature is a
//  services/*Island.qml singleton with its view in core/, metadata in
//  features/catalog.json, and an entry in SurfaceRegistry.nativeInstances.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import K4 as K4
import "core"
import "services"
import "widgets"

Scope {
    id: root

    // Modules load individually through PluginManager, so one syntax error
    // is reported in Settings instead of preventing the entire bar from loading.
    // The registry also injects declared cross-module references into both
    // repository plugins and those in ~/.config/k4/plugins.

    // ── the native surfaces ─────────────────────────────────────
    //
    //  Bar chrome and extensions arbitrate as one ordered list. Native
    //  features (services/*Island.qml, always on) and dynamically loaded
    //  plugins meet in services/SurfaceRegistry.qml, which keeps stable
    //  host order so equal-priority ties resolve the way the catalog did.
    //  Every arbitration below reads this list and nowhere else.
    readonly property var surfaces: SurfaceRegistry.surfaces

    //  A summoned view belongs to one monitor. Once compositor focus moves
    //  to another, keeping that distant popup open is never useful: close it
    //  before the next interaction. This is fixed host behavior, not a plugin
    //  preference. The click catcher below remains as a fallback for setups
    //  where monitor focus changes only on press.
    readonly property string focusedMonitorName: {
        const monitor = Hyprland.focusedMonitor
        return monitor && monitor.name ? monitor.name : ""
    }

    onFocusedMonitorNameChanged: {
        const p = activePlugin
        if (!p || !p.colocable || p.transitorio
                || p.name === SurfaceRegistry.pillId)
            return
        if (focusedMonitorName.length === 0
                || focusedMonitorName === Island.pantallaActiva)
            return
        if (typeof p.close === "function")
            p.close()
    }

    // The highest-priority active surface wins the island. The binding
    // re-evaluates when any surface changes its active state.
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

    // A summoned view dismisses transients centrally. Priority alone is not
    // enough: a notification's hover timer could keep it alive and make it
    // reappear after the summoned view closes. Individual openers must not
    // have to remember to dismiss notifications themselves.
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
                    && !p.transitorio && p.name !== SurfaceRegistry.pillId)
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
                    || p.transitorio || p.name === SurfaceRegistry.pillId)
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

    // Publish the winning surface and expanded state through K4.Isla.
    onActivePluginChanged: {
        apartarTransitorios()
        const anterior = Island.ocupante
        if (activePlugin && activePlugin.name !== SurfaceRegistry.pillId) {
            // From rest, use the click's explicit monitor or the focused one.
            // Keep the monitor between open views so panel navigation stays put.
            if (Island.pantallaPedida.length > 0
                    || anterior.length === 0 || anterior === SurfaceRegistry.pillId)
                Island.pantallaActiva = Island.tomarPantallaPedida()
        } else {
            Island.pantallaPedida = ""
        }
        Island.ocupante = activePlugin ? activePlugin.name : ""
        // Expanded means taller than the pill, not merely occupied: the pill
        // itself always occupies the island.
        Island.abierta = activePlugin !== null
            && activePlugin.islandHeight > Theme.baseHeight
    }

    // Background taps go to the active surface if requested, otherwise the panel.
    function abrirPanelEn(pantalla) {
        Island.pedirPantalla(pantalla)
        Island.pantallaActiva = pantalla
        const panel = SurfaceRegistry.instance("panel")
        if (panel)
            panel.openTab("controls")
    }

    function backgroundTap(pantalla, mostrado) {
        if (mostrado && mostrado.name !== SurfaceRegistry.pillId && mostrado.handlesBackgroundTap)
            mostrado.backgroundTapped()
        else
            abrirPanelEn(pantalla)
    }

    // QML singletons are lazy: access them to start processes and registrations.
    Component.onCompleted: {
        // Inject the API bridge first. Relative host imports inside K4 would
        // create a second service graph; see api/K4/Puente.qml.
        K4.Puente.tema = Theme
        K4.Puente.indicadores = Indicadores
        K4.Puente.audio = Audio
        K4.Puente.feedback = UiSounds
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
        void Sesion.bloqueado
        void SurfaceRegistry.pillId
        void Settings.cargado
        void PluginManager.cargado
        void Clipboard.cargado
        void Ventanas.count
        void Modulos.count
        void WallpaperPalette.ready
        void Fondos.lista
        try { SurfaceRegistry.repartir() } catch (e) {}
    }

    // ── IPC ───────────────────────────────────────────────────────
    // Each module publishes its own target (k4.panel, k4.openwebui,
    // k4.launcher).
    // Keep the legacy k4 target so existing shortcuts continue to work.
    // Registry lookups return null for disabled or broken plugins; optional
    // chaining makes calls to those plugins harmless.
    function _p(id) { return SurfaceRegistry.instance(id) }

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
        function pluginEnable(id: string): void {
            if (SurfaceRegistry.nativeIds.indexOf(id) >= 0) {
                console.warn("k4: '" + id + "' is native and always on")
                return
            }
            PluginManager.habilitar(id)
        }
        function pluginDisable(id: string): void {
            if (SurfaceRegistry.nativeIds.indexOf(id) >= 0) {
                console.warn("k4: '" + id + "' is native and always on")
                return
            }
            PluginManager.deshabilitar(id)
        }
        function pluginToggle(id: string): void {
            if (SurfaceRegistry.nativeIds.indexOf(id) >= 0) {
                console.warn("k4: '" + id + "' is native and always on")
                return
            }
            PluginManager.alternar(id)
        }
        function pluginRetry(id: string): void { PluginManager.reintentar(id) }
        function pluginReload(id: string): void {
            if (SurfaceRegistry.nativeIds.indexOf(id) >= 0) {
                console.warn("k4: '" + id + "' is native; restart the bar to reload it")
                return
            }
            PluginManager.recargar(id)
        }
        function pluginRefresh(): void { PluginManager.releerCatalogo() }
        // Return JSON to the IPC caller rather than printing it into the shell log.
        function pluginStatus(): string {
            return JSON.stringify(PluginManager.catalogo.map(function (m) {
                return { id: m.id, enabled: PluginManager.estaHabilitado(m.id),
                         error: PluginManager.errores[m.id] || "" }
            }))
        }
        function hostStatus(): string { return SurfaceRegistry.hostStatus() }

        // Start an asynchronous update check; Settings shows novedades when ready.
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
        // Open Settings at a section name or id, for example:
        // k4 settingsSection wallpaper, island, or effects.
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

            // Resolve the configured bar edge once for the rest of this window.
            readonly property bool abajo: Settings.barPosition === "bottom"

            //  ── the island's current position ───────────────────────
            //
            //  The bar has its edge; every view that OPENS can have its own
            //  — the control centre from the left, Settings from the bottom
            //  — read from its placement in Ajustes. A view with no entry
            //  follows the bar: its edge, its alignment, which is what every
            //  view did before placement existed and stays the default so
            //  nothing jumps after the update.
            readonly property var lugar: {
                const p = pluginVisible
                return p && p.name !== SurfaceRegistry.pillId
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

            // Only the owning monitor shows the global action; others keep the pill.
            readonly property var idlePlugin: SurfaceRegistry.instance(SurfaceRegistry.pillId)
            readonly property bool esPantallaActiva: root.activePlugin
                && root.activePlugin.name !== SurfaceRegistry.pillId
                && panelWindow.screen.name === Island.pantallaActiva
            readonly property var pluginVisible: root.activePlugin
                && (root.activePlugin.name === SurfaceRegistry.pillId || esPantallaActiva)
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
                return !!p && p.name !== SurfaceRegistry.pillId
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
            //  On the view's own screen, only views that request it
            //  (`closeOnClickOutside`) get the catcher. Views nobody asked
            //  for (`transitorio`) never eat clicks meant for other things.
            //  And never while the island is stood aside: a system dialog
            //  deserves every click it gets.
            //
            readonly property bool cerrarConClicFuera: esPantallaActiva
                && !Island.apartada
                && root.activePlugin.closeOnClickOutside
                && !root.activePlugin.transitorio
                && root.activePlugin.islandHeight > Theme.baseHeight

            // Moving the bar aside is per-monitor, independent of the global
            // active surface. A module's optional barraApartada names its
            // monitor and reserved space without disabling other monitors.
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

            // The module that moves the bar aside must animate its return when
            // K4.Isla.ocupadaPor requests it. Opening another surface must not
            // make the bar reappear abruptly or leave two bars visible.
            readonly property bool sinBarra: apartada !== null

            readonly property int anchoIsla: sinBarra ? 0
                : (pluginVisible ? pluginVisible.islandWidth : 176)
            readonly property int altoIsla: sinBarra ? 0
                : (pluginVisible ? pluginVisible.islandHeight : Theme.baseHeight)

            // Reserve keeps desktop space, onTop floats, and hidden retreats
            // past the edge. Auto resolves to reserve or hidden per monitor,
            // depending on whether that monitor has a fullscreen window.
            readonly property string modoSitio: Settings.islandSpace === "auto"
                ? (Workspaces.lleno(panelWindow.screen.name) ? "hidden" : "reserve")
                : Settings.islandSpace
            readonly property bool flotante: modoSitio !== "reserve"
            readonly property bool seEsconde: modoSitio === "hidden"

            // Any non-idle surface or pointer at an activation edge reveals
            // the bar. Edge touches hold zonaToque until their grace expires.
            readonly property bool ratonEncima: sobreIsla.hovered
                || sobreFilo.hovered || zonaToque
            readonly property bool hayQueEnsenar: ratonEncima
                || (!!pluginVisible && pluginVisible.name !== SurfaceRegistry.pillId)

            // Return immediately and retreat after a grace period to avoid flicker.
            property bool retirada: false

            // While hidden, the other three screen edges also summon the bar.
            // Remember the touch in a flag: returning removes those strips
            // from the input mask, so their hover state is no longer reliable.
            // Normal island hover takes over if the pointer reaches the bar.
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
                // Only hidden mode retreats; a displaced bar belongs to its mover.
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

            // Brushing an edge reveals the pill; dwelling opens the hover view.
            // Time the combined edge/island hover because a stationary pointer
            // may not produce a new island hover event as the bar returns.
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

            // Publish visibility so off-screen animations can stop; see
            // aLaVista in services/Island.qml.
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

            // Removed monitors must not keep animations running indefinitely.
            Component.onDestruction: Island.publicarVista(screen.name, false)

            Timer {
                id: retiroTimer
                interval: 1600
                // Recheck at expiry: the pointer or bar owner may have changed.
                onTriggered: panelWindow.retirada = panelWindow.seEsconde
                    && !panelWindow.sinBarra && !panelWindow.hayQueEnsenar
            }

            // Allow time to reach the revealed bar; normal hover then keeps it up.
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

            // Only typing-oriented views grab exclusive focus; others opt in.
            WlrLayershell.keyboardFocus: {
                // System dialogs need the keyboard as well as an unobstructed view.
                if (Island.apartada)
                    return WlrKeyboardFocus.None
                const p = panelWindow.pluginVisible
                if (!p || p !== root.activePlugin || p.name === SurfaceRegistry.pillId)
                    return WlrKeyboardFocus.None
                if (p.grabKeyboard)
                    return WlrKeyboardFocus.Exclusive
                // Games can grab only while hovered. Island.hovered includes
                // a 240 ms grace period to prevent focus flicker at the edge.
                if (p.tecladoAlPasar && Island.hovered)
                    return WlrKeyboardFocus.Exclusive
                if (p.tecladoOpcional)
                    return WlrKeyboardFocus.OnDemand
                return WlrKeyboardFocus.None
            }

            // Reserve only the folded strip; expanded content floats. A moving
            // module owns its reservation in pixels so it can release space
            // gradually, independently of the island's requested height.
            // Floating/hidden preferences override every module reservation.
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
            // An absent island must also release its input region. Hidden mode
            // always keeps the activation edge in the mask, including during
            // the return animation: Region follows the item's transform, so
            // the island itself may still be outside the screen on that frame.
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

            // A pill-width activation strip reveals the hidden bar without
            // stealing clicks along the entire screen edge.
            Item {
                id: filo
                x: island.x
                width: island.width
                height: 4
                anchors.top: panelWindow.abajo ? undefined : parent.top
                anchors.bottom: panelWindow.abajo ? parent.bottom : undefined
                // Transparent rather than hidden so it can receive pointer events.
                opacity: 0

                // Keep counting edge hover after the island covers it: a
                // stationary pointer may never send the island a new hover event.
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
            //  receiving cannot be trusted to say anything. See `zonaToque`.
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

                // Animate alignment fractions, not coordinates, so resizing
                // stays centered within the same frame. Each axis has a
                // fraction: the attached edge fixes one to 0 or 1, while the
                // other carries alignment. This also supports edge-to-edge moves.
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

                // Capsules grow on their own side while the original pill stays
                // fixed. Compute this directly so positioning never trails the
                // width animation by a separate animation frame.
                readonly property int extDerecha: pluginVisible
                    && pluginVisible.name === SurfaceRegistry.pillId
                    ? Extensions.rightWidth : 0
                readonly property int extIzquierda: pluginVisible
                    && pluginVisible.name === SurfaceRegistry.pillId
                    ? Extensions.leftWidth : 0

                // Clamp the ideal pill position to keep long extensions on
                // screen. Content and silhouette move together when clamped.
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

                // Step aside while a system dialog is open; see services/Island.qml.
                opacity: Island.apartada ? 0 : 1

                readonly property real bodyRadius: Math.min(32, height / 2)

                // Escape closes any open surface. Child views may consume it
                // first to cancel a local operation before closing the surface.
                focus: true

                // Request active focus on completion; focus:true alone does not
                // establish the window's first active focus item. Reclaim it
                // when a focused view disappears, but never steal it from a
                // live child that explicitly requested it.
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

                // Publish real screen coordinates through K4.Isla.rect on the
                // primary monitor so external windows follow the island's moves.
                onXChanged: publicarRect()
                onYChanged: publicarRect()
                onWidthChanged: publicarRect()
                onHeightChanged: publicarRect()
                Component.onCompleted: {
                    publicarRect()
                    forceActiveFocus()      // Establish the Escape fallback above.
                }

                function publicarRect() {
                    Island.publicarRect(panelWindow.screen.name, {
                        x: island.x, y: island.y,
                        ancho: island.width, alto: island.height
                    }, panelWindow.modelData === Quickshell.screens[0])
                }

                // Animate requested gestures on content, never the layer surface:
                // moving the latter would rearrange the desktop.
                transform: [
                    Translate { id: gestoTr },
                    // Hiding also translates content past the edge without
                    // resizing or unanchoring the layer surface.
                    Translate {
                        id: retiroTr
                        y: panelWindow.retirada
                            ? (panelWindow.abajo ? island.height + 6
                                                 : -(island.height + 6))
                            : 0

                        // Use the same curve both ways to avoid binding-order
                        // races. No overshoot: passing zero would detach the
                        // silhouette from the screen edge and expose a gap.
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

                // Vertical gestures point into the screen, upward for a bottom bar.
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
                        // Stop the previous gesture before starting another.
                        aniSacudida.stop(); aniEmpujon.stop(); aniTiron.stop()
                        gestoTr.x = 0; gestoTr.y = 0
                        if (nombre === "sacudida") { aniSacudida.f = fuerza; aniSacudida.start() }
                        else if (nombre === "empujon") { aniEmpujon.f = fuerza; aniEmpujon.start() }
                        else if (nombre === "tiron") { aniTiron.f = fuerza; aniTiron.start() }
                    }
                }

                // Set hover independently of motion so hidden-mode opening can
                // wait for a deliberate dwell. Clock activation reads this flag.
                function abrirPorRaton() {
                    if (!root.activePlugin || root.activePlugin.name === SurfaceRegistry.pillId)
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
                            // Hold existing views immediately so a notification
                            // cannot expire while the pointer approaches it.
                            hoverExitTimer.stop()
                            root.holdHoverExit()
                            Notifs.holdToast()

                            // Hidden idle views use panelWindow's combined edge
                            // dwell timer. An already visible transient is held
                            // immediately; delaying would waste its short lifetime.
                            const enReposo = !panelWindow.pluginVisible
                                || panelWindow.pluginVisible.name === SurfaceRegistry.pillId
                            if (!panelWindow.seEsconde || !enReposo)
                                island.abrirPorRaton()
                        } else {
                            hoverExitTimer.restart()
                            root.armHoverExit()
                            Notifs.resumeToast()
                        }
                    }
                }

                // Half a second distinguishes a deliberate dwell from a brush.
                Timer {
                    id: quedarseTimer
                    interval: 500
                    onTriggered: island.abrirPorRaton()
                }

                // Right-click anywhere opens the control centre.
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

                // The bar and Settings preview share core/SiluetaIsla.qml,
                // including the inverted corners that join the screen edge.
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

                // ── content inside the body, excluding the wings
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

                    // Under every view: controls take their clicks; unused space lands here.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backgroundTap(panelWindow.screen.name,
                                                      panelWindow.pluginVisible)
                    }

                    // Lay out at final size and reveal by clipping, avoiding
                    // relayout during animation. No independent offset: this
                    // box already includes capsules and matches the silhouette.
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
                                //  Natives report through host health; plugins
                                //  keep their catalog error row.
                                if (p.nativo === true) {
                                    if (status === Loader.Error)
                                        SurfaceRegistry.reportarErrorNativo(
                                            p.name, "The view could not be loaded")
                                    else if (status === Loader.Ready)
                                        SurfaceRegistry.reportarErrorNativo(p.name, "")
                                    return
                                }
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
                                if (p.nativo === true) {
                                    if (status === Loader.Error)
                                        SurfaceRegistry.reportarErrorNativo(
                                            p.name, "The view could not be loaded")
                                    else if (status === Loader.Ready)
                                        SurfaceRegistry.reportarErrorNativo(p.name, "")
                                    return
                                }
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

    //  ── a click on another monitor closes the summoned view ─────
    //
    //  The bar window on an idle output remains deliberately click-through
    //  outside its pill. Growing that window's dynamic input mask did not
    //  reliably update the compositor's input region, so cross-monitor taps
    //  still reached the window below and left the distant popup open.
    //
    //  Use a dedicated surface instead. It is mapped only on outputs other
    //  than the one showing a summoned view, covers that output completely,
    //  and closes through the same door as Escape. This rule is fixed host
    //  behavior: plugins cannot opt out of it.
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: crossMonitorCatcher
            required property var modelData

            readonly property var owner: root.activePlugin
            readonly property bool shouldCatch: !Island.apartada
                && owner
                && owner.name !== SurfaceRegistry.pillId
                && owner.colocable
                && !owner.transitorio
                && modelData.name !== Island.pantallaActiva

            screen: modelData
            visible: shouldCatch
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            focusable: false
            exclusiveZone: 0

            WlrLayershell.namespace: "k4-cross-monitor-dismiss"
            WlrLayershell.layer: WlrLayer.Overlay

            mask: Region { item: crossMonitorTapTarget }

            Item {
                id: crossMonitorTapTarget
                anchors.fill: parent

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: function (mouse) {
                        const p = crossMonitorCatcher.owner
                        if (p && typeof p.close === "function")
                            p.close()
                        mouse.accepted = true
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
        return !!p && p.name !== SurfaceRegistry.pillId
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

    // Time pointer departure and notify the active surface; it owns dismissal.
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
