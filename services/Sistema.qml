pragma Singleton

//  Machine state: CPU, RAM, GPU, network, disk and who is eating it.
//
//  Two tiers, so that a live number costs what the number costs:
//
//  - Hot path (CPU, RAM, network): /proc read straight from QML — a
//    FileView per file and one Timer. No process, no JSON: it is
//    microseconds per second, so it runs whenever anything wants a
//    number (`rapido`): the pill chips, the centre's card, the view.
//    Rates need two samples — CPU usage and traffic are rhythms, not
//    values — so the first pass only arms the delta and publishes
//    nothing.
//
//  - Expensive tier (per-process walk, nvidia-smi, df): subprocesses
//    gated on `mirando` — the System view open — because nobody reads
//    a top-consumer list from a folded pill. The slim helper
//    (tools/sistema.py) does the two things QML cannot: walking
//    /proc/<pid> for the top consumers and locating the hwmon
//    temperature files (Quickshell.Io has no directory listing).
//
//  A monitor probing the system around the clock for nobody is what
//  earns a bar its reputation for heaviness — and even here, where
//  the hot path is cheap enough to always be on, it still stops the
//  moment nothing wants a number.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: sistema

    //  Samples each graph keeps. History pushes at half the hot
    //  path's cadence, so this stays the ~90 s window the System
    //  view's charts were sized for (Grafica paints 45 bars).
    readonly property int historia: 45

    //  Hot path on (chips, card or view want numbers) and full
    //  sampling on (the view is open). The System plugin owns both.
    property bool rapido: false
    property bool mirando: false
    property bool cargado: false

    // ── latest readings ───────────────────────────────────
    property real cpuUso: 0
    property real cpuTemp: 0
    property int cpuHilos: 0

    property real ramUsada: 0
    property real ramTotal: 0
    property real ramPct: 0
    property real swapUsada: 0
    property real swapTotal: 0

    property string gpuNombre: ""
    property real gpuUso: 0
    property real gpuTemp: 0
    property real gpuMemUsada: 0
    property real gpuMemTotal: 0
    readonly property bool hayGpu: gpuNombre.length > 0

    property string redIface: ""
    property real redRx: 0
    property real redTx: 0

    property real discoUsado: 0
    property real discoTotal: 0
    property real discoPct: 0
    property real tempNvme: 0

    property var procesos: []

    // ── history for the charts ─────────────────────────────
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []
    property var redHist: []            // rx+tx per second

    function empujar(lista, valor) {
        const salida = lista.slice()
        salida.push(valor)
        while (salida.length > historia)
            salida.shift()
        return salida
    }

    // ── text helpers ──────────────────────────────────────
    function tasa(bytes) {
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB/s"
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB/s"
        return Math.round(bytes) + " B/s"
    }

    function grados(t) { return t > 0 ? Math.round(t) + "°" : "—" }

    function matar(pid) {
        verdugo.command = ["kill", String(pid)]
        verdugo.running = true
    }

    Process { id: verdugo }

    // ── the hot path ──────────────────────────────────────
    //
    //  procfs reports no size and no useful mtime, so nothing is
    //  watched: one Timer calls reload() on each view and each view
    //  parses itself in onLoaded. `blockLoading` keeps the reads
    //  synchronous — these files are a few hundred bytes of kernel
    //  memory, and ordering against the tick stays deterministic.

    property int _tic: 0
    property var _statPrevio: null      // [total, idle] jiffies
    property real _statT: 0
    property var _redPrevio: ({})       // iface -> [rx, tx] bytes
    property real _redT: 0

    Timer {
        interval: 1000
        repeat: true
        running: sistema.rapido || sistema.mirando
        onTriggered: {
            sistema._tic += 1
            fStat.reload()
            fMem.reload()
            fNet.reload()
            if (sistema._tic % 2 === 0) {
                if (sistema.rutaTempCpu.length > 0)
                    fTempCpu.reload()
                if (sistema.rutaTempNvme.length > 0)
                    fTempNvme.reload()
            }
        }
    }

    FileView {
        id: fStat
        path: "/proc/stat"
        blockLoading: true
        onLoaded: {
            const lineas = text().split("\n")
            const campos = lineas[0].split(/\s+/).filter(c => c.length > 0)
            let total = 0
            let ocioso = 0
            if (campos.length > 5) {
                for (let i = 1; i < campos.length; ++i)
                    total += parseFloat(campos[i])
                ocioso = parseFloat(campos[4]) + (parseFloat(campos[5]) || 0)
            }
            let hilos = 0
            for (let i = 1; i < lineas.length; ++i) {
                if (/^cpu\d/.test(lineas[i]))
                    ++hilos
            }

            const t = Date.now()
            if (sistema._statPrevio && sistema._statT > 0) {
                const dt = (t - sistema._statT) / 1000
                const dT = total - sistema._statPrevio[0]
                const dI = ocioso - sistema._statPrevio[1]
                if (dt > 0 && dT > 0) {
                    sistema.cpuUso = Math.max(0, Math.min(100, (1 - dI / dT) * 100))
                    if (sistema._tic % 2 === 0)
                        sistema.cpuHist = sistema.empujar(sistema.cpuHist, sistema.cpuUso)
                }
            }
            sistema._statPrevio = [total, ocioso]
            sistema._statT = t
            sistema.cpuHilos = hilos
            sistema.cargado = true
        }
    }

    FileView {
        id: fMem
        path: "/proc/meminfo"
        blockLoading: true
        onLoaded: {
            const d = {}
            const lineas = text().split("\n")
            for (let i = 0; i < lineas.length; ++i) {
                const corte = lineas[i].indexOf(":")
                if (corte < 0)
                    continue
                d[lineas[i].slice(0, corte)] = parseFloat(lineas[i].slice(corte + 1))
            }
            const total = (d.MemTotal || 0) / 1048576
            const usada = Math.max(0, total - (d.MemAvailable || 0) / 1048576)
            sistema.ramTotal = total
            sistema.ramUsada = usada
            sistema.ramPct = total > 0 ? usada / total * 100 : 0
            const swapTotal = (d.SwapTotal || 0) / 1048576
            sistema.swapTotal = swapTotal
            sistema.swapUsada = Math.max(0, swapTotal - (d.SwapFree || 0) / 1048576)
            if (sistema._tic % 2 === 0)
                sistema.ramHist = sistema.empujar(sistema.ramHist, sistema.ramPct)
        }
    }

    FileView {
        id: fNet
        path: "/proc/net/dev"
        blockLoading: true
        onLoaded: {
            //  The interface that moves the most is the one being
            //  used; the rest are noise with numbers attached.
            const ahora = {}
            const lineas = text().split("\n")
            for (let i = 2; i < lineas.length; ++i) {
                const corte = lineas[i].indexOf(":")
                if (corte < 0)
                    continue
                const nombre = lineas[i].slice(0, corte).trim()
                if (!nombre || nombre === "lo")
                    continue
                const c = lineas[i].slice(corte + 1).trim().split(/\s+/)
                if (c.length >= 9)
                    ahora[nombre] = [parseFloat(c[0]), parseFloat(c[8])]
            }

            const t = Date.now()
            if (sistema._redT > 0) {
                const dt = (t - sistema._redT) / 1000
                let mejor = null
                for (const nombre in ahora) {
                    const previo = sistema._redPrevio[nombre]
                    if (!previo)
                        continue
                    const rx = Math.max(0, (ahora[nombre][0] - previo[0]) / dt)
                    const tx = Math.max(0, (ahora[nombre][1] - previo[1]) / dt)
                    if (!mejor || rx + tx > mejor[1] + mejor[2])
                        mejor = [nombre, rx, tx]
                }
                if (mejor) {
                    sistema.redIface = mejor[0]
                    sistema.redRx = mejor[1]
                    sistema.redTx = mejor[2]
                    if (sistema._tic % 2 === 0)
                        sistema.redHist = sistema.empujar(sistema.redHist, mejor[1] + mejor[2])
                }
            }
            sistema._redPrevio = ahora
            sistema._redT = t
        }
    }

    // ── temperatures ──────────────────────────────────────
    //
    //  hwmon paths arrive on the helper's first line; until then the
    //  views show "—" (grados() already handles a zero).

    property string rutaTempCpu: ""
    property string rutaTempNvme: ""

    FileView {
        id: fTempCpu
        path: sistema.rutaTempCpu
        blockLoading: true
        onLoaded: {
            const v = parseFloat(text())
            if (!isNaN(v))
                sistema.cpuTemp = v / 1000
        }
    }

    FileView {
        id: fTempNvme
        path: sistema.rutaTempNvme
        blockLoading: true
        onLoaded: {
            const v = parseFloat(text())
            if (!isNaN(v))
                sistema.tempNvme = v / 1000
        }
    }

    // ── the expensive tier, only while the view is open ────

    //  nvidia-smi takes its sweet time to start, so it is asked every
    //  other round of the old cadence (4 s). Two guards keep it quiet:
    //  the helper's first line says whether the binary exists at all
    //  (a spawn that cannot start warns every time), and the first
    //  refusal or bad exit code stops any further asking.
    property bool _proboGpu: false
    property bool _hayNvidia: true

    Process {
        id: gpu
        running: false
        command: ["nvidia-smi",
                  "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total",
                  "--format=csv,noheader,nounits"]

        stdout: StdioCollector {
            id: gpuSalida
            onStreamFinished: {
                const linea = String(gpuSalida.text).split("\n")[0].trim()
                const p = linea.split(",").map(s => s.trim())
                if (p.length >= 5 && p[0].length > 0) {
                    sistema.gpuNombre = p[0].replace("NVIDIA ", "")
                    sistema.gpuUso = parseFloat(p[1]) || 0
                    sistema.gpuTemp = parseFloat(p[2]) || 0
                    sistema.gpuMemUsada = parseFloat(p[3]) || 0
                    sistema.gpuMemTotal = parseFloat(p[4]) || 0
                    sistema.gpuHist = sistema.empujar(sistema.gpuHist, sistema.gpuUso)
                } else {
                    sistema._hayNvidia = false
                }
            }
        }

        onExited: function (codigo) {
            if (codigo !== 0)
                sistema._hayNvidia = false
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: sistema.mirando && sistema._hayNvidia && sistema._proboGpu
        triggeredOnStart: true
        onTriggered: if (!gpu.running) gpu.running = true
    }

    //  Disk: statfs is not a thing QML can call, so `df` once at
    //  open and then rarely — it does not change in half a minute.
    Process {
        id: disco
        running: false
        command: ["df", "-B1G", "--output=used,total", Quickshell.env("HOME") || "/"]

        stdout: StdioCollector {
            id: discoSalida
            onStreamFinished: {
                const lineas = String(discoSalida.text).split("\n").filter(l => l.trim().length > 0)
                if (lineas.length < 2)
                    return
                const c = lineas[lineas.length - 1].trim().split(/\s+/)
                const total = parseFloat(c[1])
                if (!isNaN(total) && total > 0) {
                    sistema.discoUsado = parseFloat(c[0]) || 0
                    sistema.discoTotal = total
                    sistema.discoPct = sistema.discoUsado / total * 100
                }
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: sistema.mirando
        triggeredOnStart: true
        onTriggered: if (!disco.running) disco.running = true
    }

    //  The slim helper: hwmon paths on its first line, then the top
    //  consumers every 2 s — per-process CPU is a rhythm, so each
    //  pass is compared against the previous sample.
    Process {
        id: procesos
        running: sistema.mirando
        command: ["python3", Quickshell.shellPath("tools/sistema.py")]

        stdout: SplitParser {
            onRead: function (linea) {
                if (String(linea).trim().length === 0)
                    return
                let d = null
                try {
                    d = JSON.parse(linea)
                } catch (e) {
                    return
                }
                if (d.chips) {
                    sistema.rutaTempCpu = d.chips.cpu || ""
                    sistema.rutaTempNvme = d.chips.nvme || ""
                    sistema._proboGpu = d.chips.gpu === true
                    if (!sistema._proboGpu)
                        sistema._hayNvidia = false
                }
                if (d.procesos)
                    sistema.procesos = d.procesos
            }
        }

        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("sistema:", l)
            }
        }
    }
}
