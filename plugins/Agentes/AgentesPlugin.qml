//  How the agent CLIs' limits are doing.
//
//  Claude Code and Codex cut by windows —the five hours, the week,
//  and in Claude also a separate quota for Fable— and finding out
//  where you stand forces opening each tool and asking it. This
//  shows it at a glance.
//
//  The data is asked of nobody: both programs already save to disk
//  what the server last answered them, and `tools/agentes.py` reads
//  it and leaves it in the same shape for both. The flip side is
//  that the data is from the last time the tool ran, so each card
//  says when its own is from. An old percentage shown as if current
//  deceives more than showing nothing.
//
//  Probing only while open is on purpose: with no pill to feed,
//  nobody looks at these numbers with the island folded, and a
//  process every half minute all session does not pay for that.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "agents"
    title: "Agents"
    priority: 63
    colocable: true
    active: habilitado && abierto

    property bool abierto: false

    //  What the reader returned: one entry per installed CLI.
    property var agentes: []
    property bool cargado: false

    // ── the warning ───────────────────────────────────────────────
    //
    //  The pill is not there to keep the count —for that one opens
    //  the module— but for the moment the count matters: when little
    //  is left and you can still decide what to spend it on. Hence
    //  it appears past a threshold and leaves on its own, and hence
    //  it can be turned off entirely.
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

    readonly property bool aprieta: avisar && apurado !== null
                                    && apurado.pct >= umbral

    // steps aside when it opens; the host injects it
    property var panel: null

    islandWidth: 560

    //  The data dictates the height: each agent is a card and each
    //  limit a row. The arithmetic is the view delegate's —10 margin,
    //  18 header, 6 gap and 24+4 per row—; if it changes there, it
    //  changes here too, because a card taller than its slot shows
    //  cut off.
    islandHeight: {
        if (!cargado || !agentes.length)
            return 132

        let alto = 51                       // margins, header and its gap
        for (let i = 0; i < agentes.length; i++) {
            const filas = Math.max(1, (agentes[i].limites || []).length)
            alto += 40 + 30 * filas
        }
        return alto + 8 * (agentes.length - 1)
    }

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
            Notifs.dismissToast()
            refrescar()
        }
    }

    function close() {
        abierto = false
    }

    function refrescar() {
        if (!lector.running)
            lector.running = true
    }

    //  Ask the server about YOUR usage, with the token Claude Code
    //  already has on disk. It is a read of your own account and
    //  spends no quota. It can be turned off, and then the tool's
    //  disk cache is read — correct but hours behind.
    property bool enVivo: true

    K4.Process {
        id: lector
        command: self.enVivo
            ? ["python3", K4.Paths.guion("agentes.py")]
            : ["python3", K4.Paths.guion("agentes.py"), "--sin-red"]

        onSalida: function (texto) {
            try {
                const datos = JSON.parse(texto)
                self.agentes = datos.agentes || []
            } catch (e) {
                console.warn("agentes: respuesta ilegible —", e)
                self.agentes = []
            }
            self.cargado = true
        }

        onLineaError: function (linea) { console.warn("agentes:", linea) }
    }

    //  While in view it is looked at again now and then: if you
    //  are working with the agent in another window, the percentage
    //  moves on its own.
    Timer {
        interval: 20000
        repeat: true
        running: self.abierto
        onTriggered: self.refrescar()
    }

    //  And in the background, only when there is a warning to give
    //  and only every five minutes. It is the only reason to read
    //  with the island folded, so it turns off with the warning:
    //  whoever does not want it pays not one process.
    Timer {
        interval: 300000
        repeat: true
        running: self.habilitado && self.avisar && !self.abierto
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
        if (!aprieta) {
            if (_avisoPuesto) {
                K4.Pildora.quitar("agents.limit")
                _avisoPuesto = false
            }
            return
        }
        //  Re-register only if something changed: `apurado` re-hooks
        //  every round —the object is new though the number is not—
        //  and reordering the whole pill every twenty seconds is
        //  noise nobody asked for.
        const pct = Math.round(apurado.pct)
        const color = apurado.pct >= 95 ? Theme.red : Theme.yellow
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

    onAprietaChanged: pintarAviso()
    onApuradoChanged: pintarAviso()

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
            //  Keys are English now; the Spanish pair is the pre-rename
            //  file saying something — both are honored, new wins.
            if (d.warn !== undefined) self.avisar = d.warn === true
            else if (d.avisar !== undefined) self.avisar = d.avisar === true
            if (d.threshold !== undefined) self.umbral = Number(d.threshold) || 85
            else if (d.umbral !== undefined) self.umbral = Number(d.umbral) || 85
            if (d.live !== undefined) self.enVivo = d.live === true
            else if (d.enVivo !== undefined) self.enVivo = d.enVivo === true
        }
    }

    function apuntar() {
        _ajustesTocados = true
        guardado.guardar({ warn: avisar, threshold: umbral, live: enVivo })
    }

    //  The one-shot move from the pre-rename home: the state lived under
    //  `agentes` and the sweeps that clean up after a dead plugin match
    //  the CATALOG id, not the one written here — a reload would orphan
    //  the pill and the launcher row. Adopted once, saved in the new
    //  home and the new keys; the old file stays as a fossil.
    property var _estadoViejo: K4.Fichero {
        path: K4.Paths.estadoDe("agentes") + "/estado.json"
        onLoaded: {
            if (self._ajustesTocados)
                return
            let viejo = {}
            try {
                viejo = JSON.parse(_estadoViejo.text() || "{}")
            } catch (e) {
                return
            }
            if (viejo.avisar !== undefined) self.avisar = viejo.avisar === true
            if (viejo.umbral !== undefined) self.umbral = Number(viejo.umbral) || 85
            if (viejo.enVivo !== undefined) self.enVivo = viejo.enVivo === true
            self.apuntar()
        }
    }
    property bool _ajustesTocados: false

    K4.Ajustes {
        plugin: "agents"
        grupo: "Agents"
        opciones: [
            { id: "live", nombre: "Ask the server",
              desc: "Your real usage, right now. Off, it reads the tool's cache, which lags by hours",
              glifo: 0xF06F2 },
            { id: "warn", nombre: "Warn when it gets tight",
              desc: "A percentage on the pill when the tightest limit crosses the threshold",
              glifo: 0xF0026 },
            { id: "threshold", tipo: "eleccion", nombre: "Warning threshold",
              desc: "How much spent is worth hearing about",
              glifo: 0xF029A,
              alternativas: [{ codigo: "70", nombre: "70%" },
                             { codigo: "85", nombre: "85%" },
                             { codigo: "95", nombre: "95%" }] }
        ]
        valores: ({ live: self.enVivo, warn: self.avisar,
                    threshold: String(self.umbral) })
        onCambiado: function (id, valor) {
            if (id === "live") {
                self.enVivo = valor === true
                self.refrescar()
            } else if (id === "warn") {
                self.avisar = valor === true
            } else if (id === "threshold") {
                self.umbral = Number(valor) || 85
            }
            self.apuntar()
        }
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
                    "spend", "ai", "agentes", "limites", "cupo", "gasto"].some(p => p.indexOf(t) === 0)
            resultados = pega
                ? [{ id: "abrir", titulo: "Agents",
                     desc: "Claude and Codex limits" }]
                : []
        }
        onElegido: function (id) {
            if (!self.abierto)
                self.toggle()
        }
    }

    view: Component {
        AgentesView { plugin: self }
    }
}
