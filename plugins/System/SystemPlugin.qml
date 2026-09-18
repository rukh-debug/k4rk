//  System monitor.
//
//  The sampler only runs while the view is open: a monitor probing
//  /proc and calling nvidia-smi twenty-four hours a day for nobody
//  is what earns a bar its reputation for heaviness.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "system"
    title: "System"
    priority: 62
    colocable: true
    summonCommand: "k4.system toggle"
    active: habilitado && (open || closing)
    viewLoaded: open
    //  The whole keyboard while open: «optional» is OnDemand and the
    //  compositor only gives it if you CLICK the surface, so opened
    //  from the application center or by shortcut not even ESC
    //  arrived. See `tecladoOpcional` in api/K4/Plugin.qml.
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property bool closing: false

    // ── what the user decides ──────────────────────────────
    //
    //  Three chips can ride the pill (and the hover views — all three
    //  paint the same indicator row): live CPU and memory percentages
    //  plus a compact download/upload rate. The control centre carries
    //  a card with whatever meters are on. CPU and memory default ON,
    //  network defaults OFF so the folded row stays short until asked
    //  for. The hot path they feed is a /proc read in-process: a live
    //  figure costs microseconds per second.

    property bool enPildoraCpu: true
    property bool enPildoraRam: true
    property bool enPildoraRed: false
    property bool tarjetaCpu: true
    property bool tarjetaRam: true
    property bool tarjetaRed: true

    islandWidth: 700
    islandHeight: 430

    view: Component {
        SystemView { plugin: self }
    }

    // Turns sampling on and off with whoever is looking: the island,
    // or the control centre's System tab. The tab reads through the
    // injected panel reference, so this stays the single writer of
    // both flags.
    readonly property bool tabAbierta: !!self.panel && self.panel.open
        && self.panel.tab === "system"

    Binding {
        target: Sistema
        property: "mirando"
        value: self.open || self.tabAbierta
    }

    // The hot path runs while anything wants a number: a chip, a
    // meter on the card, the view, or the centre's tab.
    Binding {
        target: Sistema
        property: "rapido"
        value: self.habilitado && (self.enPildoraCpu || self.enPildoraRam
                                   || self.enPildoraRed || self.tarjetaCpu
                                   || self.tarjetaRam || self.tarjetaRed
                                   || self.open || self.tabAbierta)
    }

    // A disabled or reloaded plugin must not leave the sampler on.
    Component.onDestruction: {
        Sistema.mirando = false
        Sistema.rapido = false
    }

    // ── the pill chips ─────────────────────────────────────
    //
    //  Each chip is independent: the user picks which of CPU, memory
    //  and network ride the pill. Refreshed only when the shown text
    //  changes — rebuilding the indicator list every second would
    //  redraw the pill for nothing. Past 90 % the CPU/memory glyph
    //  goes red: a glance only needs to say "now". Network stays
    //  orange and shows a compact "down up" pair so it fits the
    //  shared 300px row next to the Agents quota.

    property int _cpuPct: -1
    property int _ramPct: -1
    property string _redTexto: "@@none@@"

    function textoRed() {
        return "↓" + Sistema.tasaCorta(Sistema.redRx)
            + " ↑" + Sistema.tasaCorta(Sistema.redTx)
    }

    function pintarChips() {
        pintarCpu()
        pintarRam()
        pintarRed()
    }

    function pintarCpu() {
        if (!habilitado || !enPildoraCpu || !Sistema.cargado) {
            if (_cpuPct >= 0) {
                K4.Pildora.quitar("system.cpu")
                _cpuPct = -1
            }
            return
        }
        const cpu = Math.round(Sistema.cpuUso)
        if (cpu !== _cpuPct) {
            const color = cpu >= 90 ? Theme.red : Theme.blue
            if (_cpuPct < 0)
                K4.Pildora.registrar("system.cpu", cpu + "%", 0xF061A,
                                     color, 20, true)
            else
                K4.Pildora.actualizar("system.cpu", { texto: cpu + "%", color: color })
            _cpuPct = cpu
        }
    }

    function pintarRam() {
        if (!habilitado || !enPildoraRam || !Sistema.cargado) {
            if (_ramPct >= 0) {
                K4.Pildora.quitar("system.ram")
                _ramPct = -1
            }
            return
        }
        const ram = Math.round(Sistema.ramPct)
        if (ram !== _ramPct) {
            const color = ram >= 90 ? Theme.red : "#bf5af2"
            if (_ramPct < 0)
                K4.Pildora.registrar("system.ram", ram + "%", 0xF035B,
                                     color, 21, true)
            else
                K4.Pildora.actualizar("system.ram", { texto: ram + "%", color: color })
            _ramPct = ram
        }
    }

    function pintarRed() {
        if (!habilitado || !enPildoraRed || !Sistema.cargado) {
            if (_redTexto !== "@@none@@") {
                K4.Pildora.quitar("system.net")
                _redTexto = "@@none@@"
            }
            return
        }
        const texto = textoRed()
        if (texto !== _redTexto) {
            if (_redTexto === "@@none@@")
                K4.Pildora.registrar("system.net", texto, 0xF05A9,
                                     "#ff9f0a", 22, true)
            else
                K4.Pildora.actualizar("system.net", { texto: texto })
            _redTexto = texto
        }
    }

    Component.onCompleted: pintarChips()
    onHabilitadoChanged: pintarChips()
    onEnPildoraCpuChanged: pintarChips()
    onEnPildoraRamChanged: pintarChips()
    onEnPildoraRedChanged: pintarChips()

    Connections {
        target: Sistema
        function onCpuUsoChanged() { self.pintarCpu() }
        function onRamPctChanged() { self.pintarRam() }
        function onRedRxChanged() { self.pintarRed() }
        function onRedTxChanged() { self.pintarRed() }
        function onCargadoChanged() { self.pintarChips() }
    }

    Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if ((id === "system.cpu" || id === "system.ram"
                 || id === "system.net") && !self.open)
                self.toggle()
        }
    }

    // ── settings, persisted ────────────────────────────────

    property var guardado: K4.Guardado {
        plugin: "system"
        onCargado: function (d) {
            if (d.chipCpu !== undefined) self.enPildoraCpu = d.chipCpu === true
            else if (d.chip !== undefined) self.enPildoraCpu = d.chip === true
            if (d.chipRam !== undefined) self.enPildoraRam = d.chipRam === true
            else if (d.chip !== undefined) self.enPildoraRam = d.chip === true
            if (d.chipNet !== undefined) self.enPildoraRed = d.chipNet === true
            if (d.cardCpu !== undefined) self.tarjetaCpu = d.cardCpu === true
            if (d.cardRam !== undefined) self.tarjetaRam = d.cardRam === true
            if (d.cardNet !== undefined) self.tarjetaRed = d.cardNet === true
        }
    }

    function apuntar() {
        guardado.guardar({ chip: (enPildoraCpu || enPildoraRam),
                           chipCpu: enPildoraCpu, chipRam: enPildoraRam,
                           chipNet: enPildoraRed, cardCpu: tarjetaCpu,
                           cardRam: tarjetaRam, cardNet: tarjetaRed })
    }

    K4.Ajustes {
        plugin: "system"
        grupo: "System"
        glifo: 0xF061A   // chip
        desc: "Live CPU, memory and network on the pill and the control centre."

        opciones: [
            { id: "chipCpu", nombre: "CPU on the pill",
              desc: "Live processor percentage on the pill and the hover views",
              glifo: 0xF061A },
            { id: "chipRam", nombre: "Memory on the pill",
              desc: "Live memory percentage on the pill and the hover views",
              glifo: 0xF035B },
            { id: "chipNet", nombre: "Network on the pill",
              desc: "Live download and upload rates on the pill and the hover views",
              glifo: 0xF05A9 },
            { id: "cardCpu", nombre: "CPU on the card",
              desc: "The control centre shows the processor",
              glifo: 0xF061A },
            { id: "cardRam", nombre: "Memory on the card",
              desc: "The control centre shows memory in use",
              glifo: 0xF035B },
            { id: "cardNet", nombre: "Network on the card",
              desc: "Download and upload rates on the control centre",
              glifo: 0xF05A9 }
        ]
        valores: ({ chipCpu: self.enPildoraCpu, chipRam: self.enPildoraRam,
                    chipNet: self.enPildoraRed, cardCpu: self.tarjetaCpu,
                    cardRam: self.tarjetaRam, cardNet: self.tarjetaRed })
        onCambiado: function (id, valor) {
            if (id === "chipCpu")
                self.enPildoraCpu = valor === true
            else if (id === "chipRam")
                self.enPildoraRam = valor === true
            else if (id === "chipNet")
                self.enPildoraRed = valor === true
            else if (id === "cardCpu")
                self.tarjetaCpu = valor === true
            else if (id === "cardRam")
                self.tarjetaRam = valor === true
            else if (id === "cardNet")
                self.tarjetaRed = valor === true
            else
                return
            self.apuntar()
        }
    }

    // ── the control centre's card ──────────────────────────

    K4.Card {
        plugin: "system"
        name: "stats"
        titulo: "System"
        glifo: 0xF061A
        desc: "CPU, memory and network at a glance"
        alto: 48
        component: Component { TarjetaSistema { plugin: self } }
    }

    function abrir() {
        closing = false
        open = true
        if (panel)
            panel.close()
    }

    function close() {
        if (!open)
            return
        open = false
        closing = true
        cierre.restart()
    }

    function toggle() { open ? close() : abrir() }

    Timer {
        id: cierre
        interval: 260
        onTriggered: self.closing = false
    }

    K4.Ipc {
        target: "k4.system"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
    }
}
