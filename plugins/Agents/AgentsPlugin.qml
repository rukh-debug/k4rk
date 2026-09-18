//  How the agent CLIs' limits are doing.
//
//  Coding subscriptions cut by windows —the five hours, the week,
//  and in Claude also a separate quota for Fable— and finding out
//  where you stand forces opening each tool and asking it. This
//  shows it at a glance.
//
//  `tools/agents.py` reads local CLI state and read-only quota APIs,
//  normalizing the results. Each card says when its data was collected:
//  an old percentage shown as current deceives more than showing nothing.
//
//  Probing only while open is on purpose: with no pill to feed,
//  nobody looks at these numbers with the island folded, and a
//  process every half minute all session does not pay for that.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "agents"
    title: "Agents"
    priority: 63
    colocable: true
    summonCommand: "k4.agents toggle"
    active: habilitado && abierto

    property bool abierto: false

    // What the reader returned: one entry per enabled usage integration.
    property var agentes: []
    property bool cargado: false
    property string usageError: ""
    property bool settingsReady: false
    property var enabledProviders: ["claude", "codex"]
    property string pinnedQuota: ""
    property bool providersPageOpen: false
    property bool controlCardOpen: false
    property bool controlPageOpen: false
    readonly property bool usageBusy: lector.running
    property int _generation: 0
    property int _requestGeneration: -1
    property bool _pendingRefresh: false
    property bool _received: false

    // ── the warning ───────────────────────────────────────────────
    //
    //  By default the pill appears only when the tightest quota crosses
    //  the warning threshold. A user can instead pin one exact provider
    //  window, keeping that percentage visible while the island is folded.
    property bool avisar: true
    property int umbral: 85

    //  The tightest limit of all, whoever's it is.
    readonly property var apurado: {
        let peor = null
        for (let i = 0; i < agentes.length; ++i) {
            const a = agentes[i]
            const ls = a.limites || []
            for (let j = 0; j < ls.length; ++j)
                if (!peor || (ls[j].pct || 0) > peor.pct)
                    peor = { pct: ls[j].pct || 0, nombre: ls[j].nombre || "",
                             agente: a.nombre || "" }
        }
        return peor
    }

    function quota(code) {
        if (!code) return null
        const separator = code.indexOf(":")
        if (separator < 1) return null
        const providerId = code.slice(0, separator)
        const limitId = code.slice(separator + 1)
        const agent = agentes.find(a => a.id === providerId)
        if (!agent) return null
        const limit = (agent.limites || []).find(l => l.id === limitId)
        if (!limit) return null
        return { pct: limit.pct || 0, nombre: limit.nombre || "",
                 agente: agent.nombre || "", provider: providerId, limit: limitId }
    }

    readonly property var quotaChoices: {
        const choices = [{ codigo: "", nombre: "Automatic warning" }]
        for (let i = 0; i < agentes.length; ++i) {
            const agent = agentes[i]
            const limits = agent.limites || []
            for (let j = 0; j < limits.length; ++j)
                choices.push({ codigo: agent.id + ":" + limits[j].id,
                               nombre: agent.nombre + " · " + limits[j].nombre })
        }
        if (pinnedQuota && !choices.some(choice => choice.codigo === pinnedQuota))
            choices.push({ codigo: pinnedQuota, nombre: "Pinned quota · waiting for data" })
        return choices
    }

    function setPinnedQuota(value) {
        const code = String(value || "")
        if (code && code.indexOf(":") < 1) return
        pinnedQuota = code
        apuntar()
    }

    readonly property var pillQuota: pinnedQuota ? quota(pinnedQuota)
        : avisar && apurado !== null && apurado.pct >= umbral ? apurado : null
    readonly property bool pillVisible: habilitado && pillQuota !== null

    // steps aside when it opens; the host injects it
    property var panel: null
    property var settings: null

    islandWidth: 560

    //  The data dictates the height: each agent is a card and each
    //  limit a row. The arithmetic is the view delegate's —10 margin,
    //  18 header, 6 gap and 24+4 per row—; if it changes there, it
    //  changes here too, because a card taller than its slot shows
    //  cut off.
    readonly property int contentHeight: {
        if (!cargado || !agentes.length)
            return 154

        let alto = 72                       // margins, header, status and gap
        for (let i = 0; i < agentes.length; i++) {
            const filas = Math.max(1, (agentes[i].limites || []).length)
            alto += 40 + 30 * filas
        }
        return alto + 8 * (agentes.length - 1)
    }
    islandHeight: Math.min(contentHeight, Math.max(220, K4.Tema.altoMaximo - 80))

    //  The whole keyboard while open, and not `tecladoOpcional`.
    //
    //  It seems excessive for a module one only looks at, and it was
    //  tried that way first. But «optional» is OnDemand, and OnDemand
    //  means the compositor gives the keyboard ONLY if you click the
    //  surface: opening it from the application center, from the
    //  launcher or by shortcut, you never click it, so the ESC the
    //  host already carries never arrived. It closed with ESC only
    //  if you had first put the mouse over it, which is the kind of
    //  fix that seems to work until you use it.
    //
    //  Having it is paid for: while open, no window receives keys.
    //  It is paid gladly because this opens, is looked at and closes
    //  —the application center does the same for the same reason—
    //  and because the key it closes with must always work, not
    //  almost always.
    grabKeyboard: abierto

    //  It does NOT close on mouse exit.
    //
    //  This opens on purpose —from the launcher or by its pill— and
    //  STAYS TO BE LOOKED AT: they are five figures to read, and to
    //  read them one moves the mouse away. With close-on-exit,
    //  moving it away closed it within a second. Worse still opened
    //  from the launcher: the pointer was inside the island —it was
    //  the launcher— and on switching plugins it ended up outside,
    //  so it closed itself without anybody having moved anything.
    //
    //  Closing stays easy and three ways: ESC (this plugin keeps the
    //  keyboard so it always works), the header cross, and opening
    //  it again.
    closeOnHoverExit: false

    handlesBackgroundTap: true
    onBackgroundTapped: {}   // swallows the click: closing is the button's business

    function toggle() {
        abierto = !abierto
        if (abierto) {
            if (panel)
                panel.close()
            refrescar()
        }
    }

    function close() {
        abierto = false
    }

    function refrescar() {
        if (!settingsReady || !habilitado || !enabledProviders.length)
            return
        if (lector.running) {
            _pendingRefresh = true
            return
        }
        _pendingRefresh = false
        _received = false
        _requestGeneration = _generation
        let command = ["python3", K4.Paths.guion("agents.py"), "--providers", enabledProviders.join(",")]
        if (!enVivo) command.push("--offline")
        lector.command = command
        lector.running = true
    }

    function providerEnabled(id) {
        return enabledProviders.indexOf(id) >= 0
    }

    function setProviderEnabled(id, enabled) {
        if (!settingsReady || !catalogProviders.some(p => p.adapter === id && id.length > 0))
            return
        let next = enabledProviders.filter(p => p !== id)
        if (enabled) next.push(id)
        enabledProviders = next
        if (!enabled && pinnedQuota.indexOf(id + ":") === 0)
            pinnedQuota = ""
        apuntar()
    }

    function invalidateUsage(clear) {
        if (!settingsReady) return
        ++_generation
        agentes = clear ? [] : agentes.filter(a => providerEnabled(a.id))
        usageError = ""
        cargado = !enabledProviders.length || agentes.length > 0
        _pendingRefresh = habilitado && enabledProviders.length > 0
        if (lector.running) lector.parar(15)
        else if (_pendingRefresh) refrescar()
    }

    onEnabledProvidersChanged: invalidateUsage(false)
    onEnVivoChanged: {
        invalidateUsage(true)
        if (!enVivo && catalogReader.running) catalogReader.parar(15)
    }
    onHabilitadoChanged: {
        if (!habilitado) abierto = false
        invalidateUsage(true)
    }

    function manageProviders() {
        if (settings) {
            close()
            if (panel) panel.close()
            settings.abrirPagina("providers")
        }
    }

    function providerStatus(id) {
        if (!id) return "Usage tracking not supported yet"
        if (!providerEnabled(id)) return "Not checked · disabled"
        const result = agentes.find(a => a.id === id)
        if (!result) return usageError || (usageBusy ? "Checking usage…" : "Waiting for usage data")
        if (result.razon) return result.razon
        if (result.status && result.status !== "ok") return "Usage unavailable"
        return result.fuente === "cache" ? "Available · cached CLI data" : "Usage available"
    }

    //  Ask the server about YOUR usage, with the token Claude Code
    //  already has on disk. It is a read of your own account and
    //  spends no quota. It can be turned off, and then the tool's
    //  disk cache is read — correct but hours behind.
    property bool enVivo: true

    K4.Process {
        id: lector

        onSalida: function (texto) {
            if (self._requestGeneration !== self._generation || !self.habilitado) return
            self._received = true
            try {
                const datos = JSON.parse(texto)
                if (!Array.isArray(datos.agentes)) throw new Error("Invalid usage response")
                self.agentes = datos.agentes.filter(a => self.providerEnabled(a.id))
                self.usageError = ""
            } catch (e) {
                self.usageError = "Could not read usage data. Try refreshing."
            }
            self.cargado = true
        }

        onTerminado: function (code) {
            if (!self._received && self._requestGeneration === self._generation) {
                self.usageError = "Usage check failed. Try refreshing."
                self.cargado = true
            }
            if (self._pendingRefresh) Qt.callLater(self.refrescar)
        }
    }

    //  While in view it is looked at again now and then: if you
    //  are working with the agent in another window, the percentage
    //  moves on its own.
    Timer {
        interval: 20000
        repeat: true
        running: self.habilitado && self.settingsReady && self.enabledProviders.length > 0
                 && (self.abierto || self.providersPageOpen
                     || self.controlCardOpen || self.controlPageOpen)
        onTriggered: self.refrescar()
    }

    //  And in the background, only when there is a warning or pinned quota
    //  and only every five minutes. It is the only reason to read
    //  with the island folded. Whoever wants neither pays not one process.
    Timer {
        interval: 300000
        repeat: true
        running: self.habilitado && self.settingsReady && self.enabledProviders.length > 0
                 && (self.avisar || !!self.pinnedQuota)
                 && !self.abierto && !self.providersPageOpen
                 && !self.controlCardOpen && !self.controlPageOpen
        triggeredOnStart: true
        onTriggered: self.refrescar()
    }

    // ── the pill ──────────────────────────────────────────────────

    //  Whether it is up is tracked instead of calling `quitar` every
    //  round: the service rebuilds the whole list on every call, and
    //  removing what was no longer there redrew everybody's pill
    //  every five minutes for nothing.
    property bool _avisoPuesto: false

    function pintarAviso() {
        if (!pillVisible) {
            if (_avisoPuesto) {
                K4.Pildora.quitar("agents.limit")
                _avisoPuesto = false
            }
            return
        }
        //  Re-register only if something changed: `pillQuota` re-hooks
        //  every round —the object is new though the number is not—
        //  and reordering the whole pill every twenty seconds is
        //  noise nobody asked for.
        const pct = Math.round(pillQuota.pct)
        const color = pillQuota.pct >= 95 ? K4.Tema.rojo
            : pillQuota.pct >= umbral ? K4.Tema.amarillo : K4.Tema.verde
        if (_avisoPuesto && _avisoPct === pct && String(_avisoColor) === String(color))
            return
        K4.Pildora.registrar("agents.limit", pct + "%",
                             0xF06A9,
                             color,
                             75, true)
        _avisoPuesto = true
        _avisoPct = pct
        _avisoColor = color
    }

    property int _avisoPct: -1
    property var _avisoColor: null

    onPillVisibleChanged: pintarAviso()
    onPillQuotaChanged: pintarAviso()

    Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if (id === "agents.limit" && !self.abierto)
                self.toggle()
        }
    }

    // ── what the user decides ─────────────────────────────────────

    property var guardado: K4.Guardado {
        plugin: "agents"
        onCargado: function (d) {
            // Read the legacy state only after the current state has loaded.
            // Asynchronous competing readers used to let the old file win.
            let migrated = false
            if (!d || typeof d !== "object" || Array.isArray(d)) d = {}
            if (Object.keys(d).length === 0) {
                try {
                    legacyState.path = K4.Paths.estadoDe("agentes") + "/estado.json"
                    const old = JSON.parse(legacyState.text() || "{}")
                    if (old && typeof old === "object" && !Array.isArray(old)) {
                        d = old
                        migrated = Object.keys(old).length > 0
                    }
                } catch (e) {}
            }
            //  Keys are English now; the Spanish pair is the pre-rename
            //  file saying something — both are honored, new wins.
            if (d.warn !== undefined) self.avisar = d.warn === true
            else if (d.avisar !== undefined) self.avisar = d.avisar === true
            if (d.threshold !== undefined) self.umbral = Number(d.threshold) || 85
            else if (d.umbral !== undefined) self.umbral = Number(d.umbral) || 85
            if (d.live !== undefined) self.enVivo = d.live === true
            else if (d.enVivo !== undefined) self.enVivo = d.enVivo === true
            if (Array.isArray(d.providers))
                self.enabledProviders = d.providers.filter((p, i, all) => typeof p === "string"
                    && /^[a-z0-9][a-z0-9-]*$/.test(p) && all.indexOf(p) === i)
            if (typeof d.pinnedQuota === "string" && (!d.pinnedQuota || d.pinnedQuota.indexOf(":") > 0))
                self.pinnedQuota = d.pinnedQuota
            self.settingsReady = true
            self.cargado = !self.enabledProviders.length
            if (migrated) self.apuntar()
            if (self.abierto || self.providersPageOpen) self.refrescar()
        }
    }

    function apuntar() {
        if (settingsReady)
            guardado.guardar({ warn: avisar, threshold: umbral, live: enVivo,
                               providers: enabledProviders, pinnedQuota: pinnedQuota })
    }

    //  The one-shot move from the pre-rename home: the state lived under
    //  `agentes` and the sweeps that clean up after a dead plugin match
    //  the CATALOG id, not the one written here — a reload would orphan
    //  the pill and the launcher row. Adopted once, saved in the new
    //  home and the new keys; the old file stays as a fossil.
    property var _legacyState: K4.Fichero {
        id: legacyState
        blockLoading: true
    }

    K4.Ajustes {
        plugin: "agents"
        grupo: "Agents"
        opciones: [
            { id: "live", nombre: "Ask the server",
              desc: "Allow live usage, catalog refreshes and provider logos. Off, only local CLI usage is available",
              glifo: 0xF06F2 },
            { id: "warn", nombre: "Warn when it gets tight",
              desc: "A percentage on the pill when the tightest limit crosses the threshold",
              glifo: 0xF0026 },
            { id: "threshold", tipo: "eleccion", nombre: "Warning threshold",
              desc: "How much spent is worth hearing about",
              glifo: 0xF029A,
              alternativas: [{ codigo: "70", nombre: "70%" },
                             { codigo: "85", nombre: "85%" },
                             { codigo: "95", nombre: "95%" }] },
            { id: "pinnedQuota", tipo: "eleccion", nombre: "Quota on folded pill",
              desc: "Automatically warn with the tightest quota, or pin one provider and time window",
              glifo: 0xF06A9, alternativas: self.quotaChoices }
        ]
        valores: ({ live: self.enVivo, warn: self.avisar,
                    threshold: String(self.umbral), pinnedQuota: self.pinnedQuota })
        onCambiado: function (id, valor) {
            if (id === "live") {
                self.enVivo = valor === true
            } else if (id === "warn") {
                self.avisar = valor === true
            } else if (id === "threshold") {
                self.umbral = Number(valor) || 85
            } else if (id === "pinnedQuota") {
                self.setPinnedQuota(String(valor))
                return
            }
            self.apuntar()
        }
    }

    // Catalog requests never discover credentials and never run on the quota
    // polling timer. The page loads cached/bundled metadata, then the user
    // can refresh it or load the selected provider's logo while online.
    property var catalogProviders: []
    property var catalogInfo: ({})
    property string catalogError: ""
    property bool catalogLoaded: false
    readonly property bool catalogBusy: catalogReader.running
    property string _pendingLogo: ""

    function loadCatalog(refresh, logo) {
        if (!habilitado) return
        if (catalogReader.running) {
            if (logo) _pendingLogo = logo
            return
        }
        if (catalogLoaded && !refresh && !logo) return
        let command = ["python3", K4.Paths.guion("agents.py"), "--catalog",
                       "--snapshot", fichero("assets/models-dev-providers.json")]
        if (!enVivo) command.push("--offline")
        if (refresh) command.push("--refresh-catalog")
        if (logo) command.push("--logo", logo)
        catalogReader.command = command
        catalogReader.running = true
    }

    K4.Process {
        id: catalogReader
        onSalida: function (text) {
            try {
                const data = JSON.parse(text)
                if (!Array.isArray(data.providers)) throw new Error("Invalid catalog")
                self.catalogProviders = data.providers
                self.catalogInfo = { origin: data.origin, updated: data.updated || 0 }
                self.catalogError = data.error || ""
                self.catalogLoaded = true
            } catch (e) {
                self.catalogError = "Could not load the provider catalog"
            }
        }
        onTerminado: function (code) {
            if (code !== 0) self.catalogError = "Could not load the provider catalog"
            if (self._pendingLogo) {
                const logo = self._pendingLogo
                self._pendingLogo = ""
                Qt.callLater(function () { self.loadCatalog(false, logo) })
            }
        }
    }

    K4.Pagina {
        plugin: "agents"
        name: "providers"
        titulo: "Agent providers"
        desc: "Choose usage integrations and browse the models.dev provider catalog"
        glifo: 0xF06A9
        claves: ["agents", "providers", "models.dev", "usage", "quota", "claude", "codex", "zai", "opencode"]
        componente: Component { ProvidersPage { plugin: self } }
    }

    K4.Card {
        id: agentsCard
        plugin: "agents"
        name: "usage"
        titulo: "Agent usage"
        glifo: 0xF06A9
        desc: "Coding subscription quotas at a glance"
        alto: 58
        component: Component { AgentsCard { plugin: self; card: agentsCard } }
        detailTitle: "Agents"
        detail: Component { AgentsView { plugin: self; embedded: true } }
    }

    K4.Ipc {
        target: "k4.agents"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function refresh(): void { self.refrescar() }
    }

    //  Searching «claude» or «limits» in the launcher must bring
    //  this: it is what one types when the question is «how much is
    //  left for me?».
    K4.Lanzador {
        plugin: "agents"
        onBuscando: function (texto) {
            const t = texto.toLowerCase()
            const pega = t.length >= 2
                && ["agents", "claude", "codex", "usage", "limits", "quota",
                    "spend", "ai", "zai", "zhipu", "glm", "opencode", "providers"].some(p => p.indexOf(t) === 0)
            resultados = pega
                 ? [{ id: "open", titulo: "Agents",
                      desc: "Coding subscription usage and quotas" }]
                : []
        }
        onElegido: function (id) {
            if (!self.abierto)
                self.toggle()
        }
    }

    view: Component {
        AgentsView { plugin: self }
    }

    Component.onDestruction: K4.Pildora.quitar("agents.limit")
}
