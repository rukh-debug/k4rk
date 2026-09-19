pragma Singleton

// Plugin registry and persistent state.
//
// `active` is the host's momentary decision about who occupies the island;
// `habilitado` is the user's choice and survives restarts. Keeping them
// separate prevents closing a plugin from disabling it permanently.

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: manager

    readonly property string rutaEstado:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins.json"

    //  Two recovery mechanisms ensure that updating the bar does not lose
    //  the user's plugins.
    //
    //   · `rutaCopia` duplicates the last readable state. If plugins.json is
    //     truncated by an interrupted write or a full disk, falling back to
    //     defaults would disable user plugins, which default to OFF. The
    //     next save would then make that loss permanent.
    //
    //   · `rutaCache` stores the last valid `tools/plugins.py --list` result.
    //     A git pull can replace that script while the bar is running. One
    //     failed call, caused by a partial file or a new dependency, used to
    //     select the embedded emergency catalog containing only built-ins.
    //     User plugins then disappeared from the list and were unloaded.
    readonly property string rutaCopia:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins.json.bak"
    readonly property string rutaCache:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/catalogo.json"
    readonly property string rutaCatalogo:
        Quickshell.shellPath("plugins/catalog.json")

    property bool cargado: false
    property var habilitados: ({})
    property var errores: ({})

    // External tools read the JSON catalog. This minimal copy keeps defaults
    // available while that file is being updated or when an older installed
    // version starts.
    property var catalogo: [
        { id: "launcher", title: "Launcher", version: "1.0.0", enabled: true },
        { id: "openwebui", title: "OpenWebUI", version: "1.0.0", enabled: true },
        { id: "settings", title: "Settings", version: "1.0.0", enabled: true, configurable: false },
        { id: "clipboard", title: "Clipboard", version: "1.0.0", enabled: true },
        { id: "system", title: "System", version: "1.0.0", enabled: true },
        { id: "keys", title: "Shortcuts", version: "1.0.0", enabled: true },
        { id: "apps", title: "Applications", version: "1.0.0", enabled: true },
        { id: "terminal", title: "Terminal", version: "1.0.0", enabled: true },
        { id: "packages", title: "Packages", version: "1.0.0", enabled: true },
        { id: "ssh", title: "Servers", version: "1.0.0", enabled: true },
        { id: "agents", title: "Agents", version: "1.0.0", enabled: true },
        { id: "hyprland-submap", title: "Hyprland Submap", version: "1.0.0", enabled: true }
    ]

    signal cambiado(string id, bool habilitado)

    //  The pill's plugin id, said once. The host asks «is this the pill?» in
    //  a dozen places, and a mistyped string there fails silently — the check
    //  just stops matching — so the id lives here and nowhere else.
    readonly property string pillId: "idle"

    // ── live instances ────────────────────────────────────────────
    //
    //  Plugins are no longer instantiated statically in shell.qml. This
    //  manager creates each catalog entry separately with error handling.
    //  Static instantiation let ONE broken plugin cause "Type X unavailable"
    //  and prevent the whole bar from starting. Here its failure goes into
    //  `errores` and the remaining plugins still start.
    //
    //  Disabled means NOT INSTANTIATED: switching a plugin off destroys it,
    //  and switching it on creates it again. Previously a flag left the
    //  object alive, consuming resources and still able to fail.
    property var instancias: []
    property var _porId: ({})
    property bool listo: false

    function instancia(id) { return _porId[id] || null }

    //  The island background click opens the control centre. This helper
    //  performs the lookup rather than requiring a direct panel reference.
    function abrirPanel() {
        const p = instancia("panel")
        if (p)
            p.toggle()
    }

    //  Cross references, by catalog id and nothing else: a plugin that
    //  declares `property var <id>` — for any plugin in the catalog —
    //  receives that plugin's live instance, or null when it is off or
    //  broken, which is what keeps guarded bindings at peace. The handout
    //  is a second pass after every creation, so cycles (panel↔launcher)
    //  do not depend on the catalog's order. See `_repartir`.

    //  ── plugin requirements ──────────────────────────────────────
    //
    //  Some modules need another capability before they can work, such as
    //  a backend for an island terminal. Rather than exposing shortcuts
    //  that do nothing or settings for unavailable functionality, declare
    //  the dependency in the catalog's `require` field and check it here.
    //
    //  Check LATE deliberately: Consola discovers the installed terminal
    //  through a startup process, so the answer may be unknown during
    //  plugin creation. Create enabled plugins, then destroy those whose
    //  requirements fail when the answer arrives.
    function requisitoCumplido(m) {
        if (!m || !m.require)
            return true
        if (m.require === "k4term")
            return Consola.esNuestra
        if (m.require === "k4term-isla")
            return Consola.hayIsla
        if (String(m.require).indexOf("bin:") === 0)
            return Binarios.presente(String(m.require).substring(4))
        return true
    }

    function motivoDelRequisito(m) {
        if (!m || !m.require)
            return ""
        if (m.require === "k4term-isla")
            return "needs k4term with its island session"
        if (m.require === "k4term")
            return "needs k4term installed"
        if (String(m.require).indexOf("bin:") === 0)
            return "needs '" + String(m.require).substring(4)
                   + "' installed"
        return ""
    }

    //  Every `bin:` the catalog asks about, probed in one sweep. Called
    //  whenever the catalog lands, so a newly installed plugin's tool is
    //  asked for the moment it appears in the list.
    function _sondearRequisitos() {
        const nombres = []
        for (let i = 0; i < catalogo.length; ++i) {
            const r = String(catalogo[i].require || "")
            if (r.indexOf("bin:") === 0)
                nombres.push(r.substring(4))
        }
        if (nombres.length > 0)
            Binarios.sondear(nombres)
    }

    //  When Consola finishes discovery, recheck requirements. This works
    //  in both directions: installing k4term and reloading the bar can make
    //  its dependent module appear automatically.
    property Connections vigilaRequisitos: Connections {
        target: Consola
        function onBinarioChanged() { manager.revisarRequisitos() }
        function onHayIslaChanged() { manager.revisarRequisitos() }
    }

    //  Likewise for individual tools: probe results, such as codex becoming
    //  available or disappearing, trigger another requirement check.
    property Connections vigilaBinarios: Connections {
        target: Binarios
        function onCambiado() { manager.revisarRequisitos() }
    }

    function revisarRequisitos() {
        if (!listo)
            return
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            if (!m.require)
                continue
            const puede = requisitoCumplido(m)
            if (!puede && _porId[m.id]) {
                _destruir(m.id)
                _publicar()
            } else if (puede && !_porId[m.id] && estaHabilitado(m.id) && m.cargable !== false) {
                if (_crear(m)) {
                    _repartir()
                    _publicar()
                }
            }
        }
    }

    function arrancar() {
        //  Wait for both user state, including disabled plugins, and the
        //  combined catalog. They arrive asynchronously in either order;
        //  whichever arrives second triggers creation.
        if (listo || !cargado || !catalogoListo)
            return
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            //  Do not attempt plugins marked unloadable due to a broken
            //  manifest, incompatible version or undeclared permissions.
            //  The catalog already supplies the reason for Settings.
            if (m.cargable === false) {
                registrarError(m.id, m.motivo || "not loadable")
                continue
            }
            if (estaHabilitado(m.id))
                _crear(m)
        }
        _repartir()
        _publicar()
        listo = true

        //  Recheck after creation too: Consola often answers before any
        //  plugin exists because discovery is faster than catalog listing.
        //  Its earlier notification then had nothing to destroy. Without
        //  this pass, a plugin requiring an absent terminal would remain.
        revisarRequisitos()
    }

    //  A plugin's directory relative to the k4 root. These are the same
    //  three cases handled by _crear's URL, expressed as a filesystem path.
    //  Keep both resolvers together and update them together.
    //
    //  tools/plugins.py maintains `externos/` as a link to ~/.config/k4/plugins.
    //  Reading through it keeps a single path convention.
    function relDeCarpeta(m, ruta) {
        if (m._recarga)
            return String(ruta).replace(/\/[^/]*$/, "")
        if (ruta.indexOf("/") === 0)
            return "externos/" + m.id
        return "plugins/" + String(ruta).replace(/\/[^/]*$/, "")
    }

    function _crear(m) {
        const ruta = m.entry
        if (!ruta) {
            registrarError(m.id, "no entry in the catalog")
            return null
        }
        //  Resolve EVERYTHING relative to this file, never through file://.
        //  Quickshell serves the shell through its own URL scheme, and a
        //  singleton loaded through two URLs becomes TWO singletons. Using
        //  file:// gave each plugin a separate copy of the bar: duplicate
        //  PluginManagers, creation passes and IPC registrations, with
        //  toggles answered by stale instances.
        //
        //  User plugins enter through `externos/`, the link to
        //  ~/.config/k4/plugins maintained by tools/plugins.py, so they use
        //  the same scheme. Reloads already provide a fresh path such as
        //  `recargas/<id>-<n>/…` from plugins.py; resolve it as supplied.
        const url = m._recarga ? Qt.resolvedUrl("../" + ruta)
            : ruta.indexOf("/") === 0
            ? Qt.resolvedUrl("../externos/" + m.id + "/"
                             + ruta.split("/").pop())
            : Qt.resolvedUrl("../plugins/" + ruta)

        //  Qt.createComponent is synchronous for local files and reports
        //  failures through errorString() rather than terminating the
        //  engine. One failed plugin produces a notice, not a missing bar.
        const comp = Qt.createComponent(url)
        if (comp.status === Component.Error) {
            registrarError(m.id, comp.errorString())
            return null
        }
        let obj = null
        try {
            //  Set `habilitado: true`: only enabled plugins are created, so
            //  the old flag stays constant and bindings such as
            //  `running: habilitado && …` still work.
            //  Also supply the plugin's own directory. K4.Paths.raiz is k4's
            //  root, not the plugin's, so external plugins otherwise cannot
            //  build paths to their scripts or assets for a process.
            //  Use Quickshell.shellPath, NOT the URL above: Qt.resolvedUrl
            //  returns an internal `qs:@/qs/…` URL, unusable by Process.
            //  This previously left scripts unable to run while the plugin
            //  reported its directory as `qs:@/qs/externos/…`.
            obj = comp.createObject(null, {
                habilitado: true,
                carpeta: Quickshell.shellPath(relDeCarpeta(m, ruta))
            })
        } catch (e) {
            registrarError(m.id, String(e))
            return null
        }
        if (!obj) {
            registrarError(m.id, comp.errorString() || "createObject returned null")
            return null
        }
        const d = Object.assign({}, _porId)
        d[m.id] = obj
        _porId = d
        limpiarError(m.id)
        return obj
    }

    //  The reference handout: for every live instance, every OTHER catalog
    //  id it declares as a property receives that plugin's instance — or
    //  null when it is not loaded, which is what keeps guarded bindings at
    //  peace. The property name IS the request, so there is no map to keep
    //  in step and no translation to get wrong.
    function _repartir() {
        for (const id in _porId) {
            const obj = _porId[id]
            //  Names the handout used to translate before it went by id
            //  (theme→hyprtheme, ajustes→settings, sistema→system).
            //  Declaring one now is a typo: nothing would ever fill it, and
            //  the failure is silent. Said once, out loud.
            for (let v = 0; v < _viejos.length; ++v) {
                const nombre = _viejos[v]
                if (nombre in obj && !_avisados[nombre]) {
                    _avisados[nombre] = true
                    console.warn("k4: some plugin declares '"
                                 + nombre + "'; references go by catalog id "
                                 + "(settings, system)")
                }
            }
            for (let i = 0; i < catalogo.length; ++i) {
                const otro = catalogo[i].id
                if (otro === id || !(otro in obj))
                    continue
                const destino = _porId[otro] || null
                if (obj[otro] !== destino)
                    obj[otro] = destino
            }
            //  Native features satisfy the same property-name contract.
            //  During migration a plugin may request a native id before
            //  its catalog entry is gone; the native singleton wins.
            const nativas = ["idle", "volume", "sound", "clock", "player",
                             "toast", "panel", "session", "tray"]
            for (let n = 0; n < nativas.length; ++n) {
                const nid = nativas[n]
                if (nid === id || !(nid in obj))
                    continue
                let destinoNativo = null
                try {
                    destinoNativo = SurfaceRegistry.nativeInstance(nid)
                } catch (e) {
                    destinoNativo = null
                }
                if (destinoNativo && obj[nid] !== destinoNativo)
                    obj[nid] = destinoNativo
            }
        }
        //  The unified registry hands out the reverse direction
        //  (native requesting a plugin, or native-to-native).
        try {
            SurfaceRegistry.repartir()
        } catch (e) {
        }
    }

    readonly property var _viejos: ["theme", "ajustes", "sistema"]
    property var _avisados: ({})

    function _publicar() {
        const lista = []
        for (let i = 0; i < catalogo.length; ++i)
            if (_porId[catalogo[i].id])
                lista.push(_porId[catalogo[i].id])
        instancias = lista
    }

    function _destruir(id) {
        const obj = _porId[id]
        if (!obj)
            return
        //  Close before destroying so the plugin releases the island and
        //  its views cleanly. This used to be a Connections in shell.qml.
        if (typeof obj.close === "function") {
            try { obj.close() } catch (e) { }
        }

        //  Remove its contributions: a Settings row or launcher result must
        //  not call a destroyed plugin. K4.Ajustes unregisters on destruction,
        //  but destruction is deferred and these entries must disappear NOW.
        Enganches.quitarDe(id)

        //  Release its tint and placement: a disabled plugin can no longer
        //  restore the bar's original appearance or position.
        Theme.destintar(id)
        Island.soltar(id)

        //  Remove its indicators too. Previously this only happened on
        //  disablement, so reload left orphan indicators with frozen values
        //  and click handlers targeting destroyed objects. Put cleanup here,
        //  where all three removal paths meet: disablement, reload and
        //  disappearance from the catalog.
        Indicadores.quitarDe(id)

        //  And its flank capsule, same reasoning: the K4.Capsule
        //  unregisters itself on destruction, but that is deferred —
        //  here the pill's flank stops quoting a corpse NOW, through
        //  the one door all three deaths walk (off, reload, gone from
        //  the catalog). One capsule per plugin, so quitar(id) is the
        //  whole sweep.
        Extensions.quitar(id)

        //  DISABLE its IpcHandlers to unregister their targets.
        //
        //  Destruction did not unregister them even after three seconds in
        //  testing. The stale handler retained the target; recreation failed
        //  with "another handler is registered", and the old object answered
        //  "Function not found". Find declared children with target and
        //  enabled properties, as exposed by K4.Ipc. Handling this through
        //  Component.onDestruction inside Ipc would be cleaner, but that
        //  attached handler cannot be used on an IpcHandler.
        const hijos = obj.services || []
        for (let i = 0; i < hijos.length; ++i) {
            const h = hijos[i]
            if (h && ("target" in h) && ("enabled" in h)) {
                try { h.enabled = false } catch (e) { }
            }
        }
        const d = Object.assign({}, _porId)
        delete d[id]
        _porId = d
        //  Redistribute references so consumers receive null instead of a
        //  destroyed object that would fail on its next use.
        _repartir()
        obj.destroy()
    }

    //  Reload a LIVE plugin: destroy it and recreate it from disk. The
    //  Settings retry action for a failed, unloaded plugin uses this same
    //  path through reintentar().
    //
    //  For development, edit the plugin's QML and run `k4 pluginReload <id>`
    //  to see the change without restarting the bar. This works for both
    //  built-in and external plugins.
    //
    //  If the new version fails to compile, Settings shows its error and
    //  retry action while the bar continues, just as for a startup failure.
    //  The previous instance has already been destroyed; it is not retained
    //  as a fallback.
    function recargar(id) {
        if (!estaHabilitado(id))
            return
        const m = metadata(id)
        if (!m || m.cargable === false)
            return
        if (_porId[id])
            _destruir(id)
        _publicar()
        //  Create LATER, in a separate step, for two reasons:
        //
        //  1. destroy() is deferred until control returns to the event loop.
        //     Creating immediately left the old IPC registered, rejecting
        //     the new handler and leaving a live plugin unable to receive IPC.
        //  2. Ask plugins.py for a fresh directory. Adding ?r1 to the entry
        //     only reloads that file; sibling views resolve against the same
        //     directory and remain cached. The plugin would be recreated
        //     with its old view even after the author edited it.
        _pendienteRecarga = id
        procesoRecarga.running = true
    }

    property string _pendienteRecarga: ""

    property var procesoRecarga: Process {
        command: ["python3", Quickshell.shellPath("tools/plugins.py"),
                  "--reload", manager._pendienteRecarga]
        stdout: StdioCollector {
            onStreamFinished: {
                const id = manager._pendienteRecarga
                const ruta = text.trim()
                manager._pendienteRecarga = ""
                if (!id || !ruta)
                    return
                const m = manager.metadata(id)
                if (!m || !manager.estaHabilitado(id))
                    return
                manager.limpiarError(id)
                manager._crear(Object.assign({}, m, { entry: ruta,
                                                      _recarga: true }))
                manager._repartir()
                manager._publicar()
            }
        }
    }

    //  Retrying reloads a plugin that failed to be created. It still needs
    //  a fresh directory because the repaired file may be a view rather
    //  than the entry point.
    function reintentar(id) {
        if (_porId[id] || !estaHabilitado(id))
            return
        recargar(id)
    }

    onCambiado: function (id, valor) {
        if (!listo)
            return
        if (valor && !_porId[id]) {
            const m = metadata(id)
            if (m && _crear(m)) {
                _repartir()
                _publicar()
            }
        } else if (!valor && _porId[id]) {
            _destruir(id)
            _publicar()
        }
    }

    function indice(id) {
        for (let i = 0; i < catalogo.length; ++i)
            if (catalogo[i].id === id)
                return i
        return -1
    }

    function metadata(id) {
        const i = indice(id)
        return i >= 0 ? catalogo[i] : null
    }

    function estaHabilitado(id) {
        const m = metadata(id)
        if (!m)
            return false
        return habilitados[id] !== undefined ? !!habilitados[id] : m.enabled !== false
    }

    function puedeConfigurar(id) {
        const m = metadata(id)
        return !!(m && m.configurable !== false)
    }

    function poner(id, valor) {
        if (indice(id) < 0 || !puedeConfigurar(id))
            return
        const d = Object.assign({}, habilitados)
        d[id] = !!valor
        habilitados = d
        //  _destruir removes indicators for every destruction path, including
        //  disablement. Cleanup here used to cover only this path.
        guardar()
        cambiado(id, !!valor)
    }

    function alternar(id) { poner(id, !estaHabilitado(id)) }

    function habilitar(id) { poner(id, true) }
    function deshabilitar(id) { poner(id, false) }

    function registrarError(id, motivo) {
        const d = Object.assign({}, errores)
        d[id] = String(motivo || "load error")
        errores = d
    }

    function limpiarError(id) {
        const d = Object.assign({}, errores)
        delete d[id]
        errores = d
    }

    //  Look up a plugin icon by ID, using the two fields K4.IconoPlugin
    //  understands: an image when supplied, otherwise a glyph code point.
    //
    //  Launcher contributions used to appear without icons because rows
    //  expected desktop icon names, whereas plugins declare Nerd Font code
    //  points or their own image files. The mismatch silently left empty
    //  space among otherwise complete rows. Expose both forms explicitly.
    function iconoDe(id) {
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            if (m.id !== id)
                continue
            return { imagen: m.iconFile ? "file://" + m.iconFile : "",
                     glifo: m.icon ? parseInt(m.icon, 16)
                           : (m.externo ? 0xF0431 : 0xF06A5) }
        }
        return { imagen: "", glifo: 0xF06A5 }
    }

    //  Rows for Settings' Plugins group. External plugins show their purpose
    //  and requested permissions before the enable switch so users can make
    //  an informed choice. Failed plugins show the reason in red, with the
    //  row serving as a retry action when the error is reloadable.
    readonly property var opcionesAjustes: catalogo
        .filter(function (m) { return m.configurable !== false })
        .map(function (m) {
            const error = errores[m.id] || ""
            let desc = "Turn this plugin on or off"
            if (m.externo) {
                desc = m.description || "User plugin"
                if (m.permissions && m.permissions.length > 0)
                    desc += "  ·  needs: " + m.permissions.join(", ")
            }
            const sinRequisito = !requisitoCumplido(m)
            if (m.cargable === false)
                //  Use porque(), not the raw reason code: the script returns
                //  a machine token, while this row needs an English message.
                desc = Motivos.porque(m.motivo || "no-cargable", m.detalle)
            else if (sinRequisito)
                desc = motivoDelRequisito(m)
            else if (error.length > 0)
                desc = error
            return { id: "plugin_" + m.id,
                     pluginId: m.id,
                     nombre: (m.title || m.id)
                         + (m.externo ? "  ·  " + (m.version || "") : ""),
                     desc: desc,
                     error: (m.cargable === false || sinRequisito) ? "fijo"
                          : (error.length > 0 ? "recargable" : ""),
                      //  Use the declared icon or a generic puzzle piece for
                      //  external plugins and a plug for built-ins. Separate
                      //  image and code-point fields let the view render
                      //  either form without guessing.
                      imagen: m.iconFile ? "file://" + m.iconFile : "",
                      glifo: m.icon ? parseInt(m.icon, 16)
                           : (m.externo ? 0xF0431 : 0xF06A5) }
         })

    //  Applications shown in the application centre and shortcuts are
    //  declared by `application: true` in the catalog or manifest, not in
    //  code. They can be identified before loading, and disabled plugins
    //  remain visible in gray rather than disappearing without explanation.
    readonly property var aplicaciones: catalogo
        .filter(function (m) { return m.application === true })
        .map(function (m) {
            return { id: m.id,
                      //  Publish the catalog's plain-English title directly
                      //  for both the application centre and its shortcuts,
                      //  falling back to the ID when no title is supplied.
                     nombre: (m.title || m.id),
                     imagen: m.iconFile ? "file://" + m.iconFile : "",
                     glifo: m.icon ? parseInt(m.icon, 16) : 0xF0431,
                     externo: m.externo === true,
                     habilitado: estaHabilitado(m.id),
                     disponible: m.cargable !== false
                                 && !(errores[m.id] || "").length }
        })

    //  Open an application by ID here, where its instance is owned, rather
    //  than in the view. Return false when no live instance can be opened.
    function abrirAplicacion(id) {
        const p = _porId[id]
        if (!p)
            return false
        p.abrir()
        return true
    }

    function valorAjuste(id) {
        return estaHabilitado(String(id).replace(/^plugin_/, ""))
    }

    function alternarAjuste(id) {
        alternar(String(id).replace(/^plugin_/, ""))
    }

    //  Parse usable state into a map or return null. An empty map is valid
    //  state with no saved overrides; null means unreadable state. Confusing
    //  the two previously caused users' plugins to be disabled.
    //  Plugin ids that were renamed when the bar went English-only;
    //  old saved state is remapped on load instead of being thrown
    //  away. `ask` is the newest: the Codex assistant became the
    //  OpenWebUI chat, and whoever had it on keeps the chat on.
    readonly property var idsViejos: ({ sonido: "sound",
                                        agentes: "agents",
                                        ask: "openwebui",
                                        submap: "hyprland-submap" })

    function _leerEstado(bruto) {
        if (!bruto || bruto.length === 0)
            return null
        try {
            const d = JSON.parse(bruto)
            if (d.habilitados && typeof d.habilitados === "object") {
                const m = {}
                for (const k in d.habilitados)
                    m[idsViejos[k] !== undefined ? idsViejos[k] : k] = d.habilitados[k]
                return m
            }
        } catch (e) {
            //  Fall through; the caller reports the failure.
        }
        return null
    }

    //  Record when the backup supplied state because the primary was
    //  unreadable. Report recovery rather than hiding data loss until the
    //  backup also becomes unavailable.
    property bool estadoRepuesto: false

    function cargar() {
        const bruto = estado.text()
        let mapa = _leerEstado(bruto)

        if (mapa === null) {
            //  Check the backup before treating an unreadable primary as
            //  empty state. This distinguishes first startup from a damaged
            //  state file.
            const deCopia = _leerEstado(copiaEstado.text())
            if (deCopia !== null) {
                mapa = deCopia
                estadoRepuesto = true
                console.warn("k4: plugins.json couldn't be read; restored from "
                             + manager.rutaCopia)
            }
        }

        if (mapa !== null) {
            habilitados = mapa
            //  Create the backup on startup rather than waiting for the
            //  first setting change, so recovery is available immediately.
            //  If state came FROM the backup, repair the primary with it.
            const bueno = JSON.stringify({ habilitados: mapa }, null, 1)
            if (estadoRepuesto)
                estado.setText(bueno)
            else if (copiaEstado.text() !== bueno)
                copiaEstado.setText(bueno)
        }

        cargado = true
        //  With state loaded, start plugins if the catalog has arrived.
        //  Starting here rather than in shell.qml avoids a race: state waits
        //  for mkdir, while the catalog waits for the listing process.
        //  Creating before both arrive could load disabled plugins or omit
        //  user plugins.
        arrancar()
    }

    //  `tools/plugins.py --list` emits repository and ~/.config/k4/plugins
    //  entries with validation results. Validation belongs in ONE place,
    //  Python; this service consumes it. A broken manifest arrives with
    //  `cargable: false` and a reason rather than preventing bar startup.
    property bool catalogoListo: false

    //  The displayed catalog's source. Empty means a fresh script result;
    //  otherwise the store labels the source because the list may be stale.
    property string catalogoDe: ""

    //  Manifest vocabulary: English is what the tools emit now. Lists
    //  written before the rename — the on-disk cache above all — still
    //  speak the Spanish keys, so they are translated once, on the way in,
    //  and everything downstream reads one vocabulary.
    function _normalizarClaves(m) {
        const viejos = { requiere: "require", icono: "icon",
                         iconoFichero: "iconFile", permisos: "permissions",
                         aplicacion: "application", superficies: "surfaces" }
        const n = {}
        for (const k in m) {
            const nuevo = viejos[k]
            if (nuevo) {
                if (n[nuevo] === undefined)
                    n[nuevo] = m[k]
            } else if (n[k] === undefined) {
                n[k] = m[k]
            }
        }
        return n
    }

    function _aplicarCatalogo(bruto) {
        try {
            const d = JSON.parse(bruto)
            if (d.plugins && Array.isArray(d.plugins) && d.plugins.length > 0) {
                catalogo = d.plugins.map(function (m) {
                    return Object.assign(_normalizarClaves(m), {
                        enabled: m.enabledByDefault !== false
                    })
                })
                return true
            }
        } catch (e) {
            //  The caller handles the failure.
        }
        return false
    }

    function recibirCatalogo(bruto) {
        if (_aplicarCatalogo(bruto)) {
            catalogoDe = ""
            _intentosLista = 0
            //  Save the last valid list for when the script fails to answer;
            //  without it, startup would omit user plugins on that occasion.
            if (cacheCatalogo.text() !== bruto)
                cacheCatalogo.setText(bruto)
        } else if (catalogo.length === 0 || !catalogoListo) {
            //  An unreadable response does not mean the plugins disappeared.
            //  Try the last valid list before the emergency built-in catalog:
            //  the plugins may still exist even though listing failed.
            if (_aplicarCatalogo(cacheCatalogo.text())) {
                catalogoDe = "cache"
                console.warn("k4: couldn't list the plugins; falling back to "
                             + manager.rutaCache)
            }
        }
        catalogoListo = true
        _sondearRequisitos()
        if (listo)
            _sincronizar()
        else
            arrancar()
    }

    //  Refresh the catalog while running so terminal-based installation or
    //  removal takes effect without restarting the bar.
    function releerCatalogo() {
        //  A manual refresh resets the retry allowance; otherwise exhausting
        //  two retries would prevent later refreshes from scheduling retries.
        _intentosLista = 0
        listador.running = false
        listador.running = true
    }

    //  Watch the user plugin directory with inotify through FolderListModel,
    //  without a separate process. Adding or removing a directory refreshes
    //  the catalog automatically, so copying in a plugin appears shortly
    //  afterward without requiring `k4 pluginRefresh`.
    property var _vigiaCarpeta: FolderListModel {
        folder: "file://" + Quickshell.env("HOME") + "/.config/k4/plugins"
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        //  The first count is initial loading, not a change; startup already
        //  requests its own catalog listing.
        onCountChanged: if (manager.listo) manager._relectura.restart()
    }

    //  Debounce: git clone creates the directory BEFORE its files. Validating
    //  an incomplete clone would briefly report a false broken-plugin state.
    property var _relectura: Timer {
        interval: 1200
        onTriggered: manager.releerCatalogo()
    }

    //  Reconcile live instances with the new catalog.
    //
    //  Only act on differences: destroy plugins that disappeared and create
    //  newly available enabled plugins. Leave unchanged instances alone so
    //  a catalog refresh does not make every existing view flicker.
    //
    //  Creation checks the same requirements as continued operation. A
    //  missing `bin:` tool or terminal must not slip through on refresh;
    //  otherwise each catalog refresh would recreate what the requirement
    //  probe had just removed.
    function _sincronizar() {
        const vistos = {}
        let cambios = false
        for (let i = 0; i < catalogo.length; ++i) {
            const m = catalogo[i]
            vistos[m.id] = true
            if (m.cargable === false) {
                if (_porId[m.id]) { _destruir(m.id); cambios = true }
                registrarError(m.id, m.motivo || "not loadable")
                continue
            }
            if (estaHabilitado(m.id) && !_porId[m.id]
                    && requisitoCumplido(m)) {
                if (_crear(m))
                    cambios = true
            }
        }
        //  Remove live plugins that are no longer listed in the catalog.
        const ids = Object.keys(_porId)
        for (let j = 0; j < ids.length; ++j) {
            if (!vistos[ids[j]]) {
                _destruir(ids[j])
                limpiarError(ids[j])
                cambios = true
            }
        }
        if (cambios) {
            _repartir()
            _publicar()
        }
    }

    // Native ids are always on; legacy keys linger in old plugins.json
    // files but must never be written back out.
    readonly property var idsNativos: ["idle", "volume", "sound", "clock",
        "player", "toast", "panel", "session", "tray"]

    function guardar() {
        if (!cargado)
            return
        const limpio = {}
        for (const k in habilitados) {
            if (idsNativos.indexOf(k) < 0)
                limpio[k] = habilitados[k]
        }
        if (Object.keys(limpio).length !== Object.keys(habilitados).length)
            habilitados = limpio
        const texto = JSON.stringify({ habilitados: limpio }, null, 1)
        estado.setText(texto)
        //  Save a backup too. This small duplicate turns primary-file damage
        //  into a logged recovery rather than losing every enabled plugin.
        copiaEstado.setText(texto)
        estadoRepuesto = false
    }

    FileView {
        id: estado
        path: manager.rutaEstado
        blockLoading: true
        //  Write a temporary file and rename it. Otherwise an interrupted
        //  setText could leave truncated JSON, the unreadable state handled
        //  by the recovery path above.
        atomicWrites: true
    }

    FileView {
        id: copiaEstado
        path: manager.rutaCopia
        blockLoading: true
        atomicWrites: true
    }

    Process {
        id: listador
        command: ["python3", Quickshell.shellPath("tools/plugins.py"),
                  "--list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: manager.recibirCatalogo(String(this.text))
        }
        //  Retry Python failures. recibirCatalogo can use the last valid
        //  list when output is unreadable; after retries are exhausted,
        //  ensure that fallback also runs if no catalog was marked ready.
        //  A git pull can replace tools/plugins.py while the bar is running,
        //  so these failures are often temporary.
        onExited: function (codigo) {
            if (codigo === 0)
                return
            if (manager._intentosLista < 2) {
                manager._intentosLista += 1
                reintentoLista.interval = 3000 * manager._intentosLista
                reintentoLista.restart()
                return
            }
            if (!manager.catalogoListo)
                manager.recibirCatalogo("")
        }
    }

    property int _intentosLista: 0

    Timer {
        id: reintentoLista
        onTriggered: {
            listador.running = false
            listador.running = true
        }
    }

    FileView {
        id: cacheCatalogo
        path: manager.rutaCache
        blockLoading: true
        atomicWrites: true
    }

    //  ── plugin store ─────────────────────────────────────────────────
    //
    //  Search, examine, install, update and remove through the SAME
    //  tools/plugins.py used from the terminal. Separate bar and CLI paths
    //  would duplicate validation and leave the less-used path inconsistent.
    //
    //  One operation at a time: installation and removal write to disk,
    //  and concurrent operations on one plugin would introduce a race.

    signal registroListo(var entradas, var descartadas)
    signal examenListo(var d)
    signal obraHecha(string que, string id, bool bien, string motivo)
    signal obraFallo(string que, string motivo)

    property bool ocupado: false
    property string ocupadaEn: ""

    function buscarEnRegistro() {
        return _obrar("buscar", "", ["--search", "--json"])
    }

    //  Examine without installing. The result includes the inspected commit;
    //  pass it to instalarDesde() so installation uses exactly the revision
    //  shown in the dialog.
    function examinar(repo, carpeta, commit) {
        return _obrar("examinar", "", ["--examine", repo, "--json"]
                      .concat(carpeta ? ["--folder", carpeta] : [])
                      .concat(commit ? ["--commit", commit] : []))
    }

    function instalarDesde(repo, carpeta, commit, id) {
        return _obrar("instalar", id || "",
                      ["--install", repo, "--json", "--yes"]
                      .concat(carpeta ? ["--folder", carpeta] : [])
                      .concat(commit ? ["--commit", commit] : []))
    }

    function actualizarPlugin(id, commit) {
        return _obrar("actualizar", id,
                      ["--update", id, "--json", "--yes"]
                      .concat(commit ? ["--commit", commit] : []))
    }

    function quitarPlugin(id, conEstado) {
        return _obrar("quitar", id, ["--remove", id, "--json", "--yes"]
                      .concat(conEstado ? ["--with-state"] : []))
    }

    function comprobarNovedades() {
        return _obrar("comprobar", "", ["--check", "--json"])
    }

    property var _obra: ({ que: "", id: "", args: [] })
    property var _cola: []
    property string _queja: ""

    //  QUEUE requests instead of dropping them. Opening the store starts an
    //  update check; discarding concurrent work lost the registry search
    //  arriving half a second later. The Discover tab then stayed empty
    //  without an error or loading indicator because its request never ran.
    //
    //  Deduplicate queued operations by kind and plugin ID: pressing refresh
    //  three times needs only one equivalent queued request.
    function _obrar(que, id, args) {
        const tarea = { que: que, id: id, args: args }
        if (ocupado) {
            for (let i = 0; i < _cola.length; ++i)
                if (_cola[i].que === que && _cola[i].id === id)
                    return true
            _cola = _cola.concat([tarea])
            return true
        }
        _arrancarObra(tarea)
        return true
    }

    function _arrancarObra(tarea) {
        _queja = ""
        _obra = tarea
        ocupado = true
        ocupadaEn = tarea.id
        tienda.running = true
    }

    function _siguienteObra() {
        if (ocupado || _cola.length === 0)
            return
        const t = _cola[0]
        _cola = _cola.slice(1)
        _arrancarObra(t)
    }

    function _recibirTienda(texto) {
        //  The script writes one JSON line per event; the last is the result.
        //  Search backward because earlier lines may contain notices.
        const lineas = String(texto || "").trim().split("\n")
        for (let i = lineas.length - 1; i >= 0; --i) {
            const l = lineas[i].trim()
            if (!l.startsWith("{"))
                continue
            try {
                return JSON.parse(l)
            } catch (e) {
                //  A line starting with `{` may still be invalid JSON. Keep
                //  looking backward instead of discarding the whole result.
            }
        }
        return null
    }

    Process {
        id: tienda
        command: ["python3", Quickshell.shellPath("tools/plugins.py")]
                 .concat(manager._obra.args || [])
        stdout: StdioCollector {
            onStreamFinished: manager._salidaTienda = String(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: manager._queja = String(this.text).trim()
        }
        onExited: function (codigo) {
            const que = manager._obra.que
            const id = manager._obra.id
            const d = manager._recibirTienda(manager._salidaTienda)
            manager._salidaTienda = ""
            manager.ocupado = false
            manager.ocupadaEn = ""
            //  Start the next queued operation regardless of this result:
            //  one failure must not strand the requests behind it.
            Qt.callLater(manager._siguienteObra)

            //  A script dying silently must not leave a permanent spinner.
            //  Without a structured reason, report stderr; if that is empty
            //  too, at least report the exit code.
            const bien = codigo === 0 && d && d.ok
            const motivo = (d && d.motivo)
                ? Motivos.porque(d.motivo, d.detalle)
                : (manager._queja
                   || `The script exited with code ${codigo}`)

            if (que === "buscar") {
                if (bien)
                    manager.registroListo(d.plugins || [], d.descartadas || [])
                else
                    manager.obraFallo(que, motivo)
                return
            }
            if (que === "examinar") {
                if (bien)
                    manager.examenListo(d)
                else
                    manager.obraFallo(que, motivo)
                return
            }
            if (que === "comprobar") {
                if (bien)
                    manager.novedades = d.plugins || []
                else
                    manager.obraFallo(que, motivo)
                return
            }
            //  Installation, update and removal change disk contents, so the
            //  in-memory catalog must be refreshed after success.
            if (bien)
                manager.releerCatalogo()
            manager.obraHecha(que, id, bien, bien ? "" : motivo)
        }
    }

    property string _salidaTienda: ""

    //  The --check result: whether a newer revision is published for each ID.
    property var novedades: []

    function novedadDe(id) {
        for (let i = 0; i < novedades.length; ++i)
            if (novedades[i].id === id)
                return novedades[i]
        return null
    }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: manager.cargar()
    }
}
