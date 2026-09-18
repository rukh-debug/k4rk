pragma Singleton

// Cheap procfs sampling for visible indicators; detailed telemetry is on demand.
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "SystemMetrics.js" as Metrics

Singleton {
    id: sistema

    readonly property int historia: 45
    property var consumers: ({})
    readonly property bool rapido: Object.keys(consumers).some(k => consumers[k].active)
    readonly property bool mirando: Object.keys(consumers).some(k => consumers[k].detailed)
    readonly property bool cargado: cpuUso >= 0 && ramTotal > 0
    property real cpuUso: -1
    property real cpuTemp: 0
    property int cpuHilos: 0
    property string cpuName: "Processor"
    property real uptime: 0
    property real ramUsada: 0
    property real ramTotal: 0
    property real ramPct: -1
    property real swapUsada: 0
    property real swapTotal: 0
    property string gpuNombre: ""
    property real gpuUso: -1
    property real gpuTemp: 0
    property real gpuMemUsada: -1
    property real gpuMemTotal: 0
    property string gpuMemoryLabel: "Graphics memory"
    readonly property bool hayGpu: gpuNombre.length > 0
    property string redIface: ""
    property real redRx: -1
    property real redTx: -1
    property real discoUsado: 0
    property real discoTotal: 0
    property real discoPct: -1
    property real diskAvailable: 0
    property real diskReserved: 0
    property string diskPath: ""
    property string diskMount: ""
    property string diskFilesystem: ""
    property string diskDevice: ""
    property real tempNvme: 0
    property var procesos: []
    property bool processesReady: false
    property string processNotice: ""
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []
    property var redHist: []
    property string rutaTempCpu: ""
    property string rutaTempNvme: ""
    property Component monitorView: Component { VistaSistema {} }

    function sample(owner, active, detailed) {
        const next = Object.assign({}, consumers)
        if (!active && !detailed) delete next[owner]
        else next[owner] = { active: active || detailed, detailed: detailed }
        consumers = next
    }
    function empujar(list, value) { return list.concat([value]).slice(-historia) }
    function tasa(bytes) {
        if (bytes < 0 || !isFinite(bytes)) return "—"
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MiB/s"
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KiB/s"
        return Math.round(bytes) + " B/s"
    }
    function tasaCorta(bytes) {
        if (bytes < 0) return "—"
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + "M"
        if (bytes >= 1024) return Math.round(bytes / 1024) + "K"
        return Math.round(bytes) + "B"
    }
    function grados(value) { return value > 0 ? Math.round(value) + " °C" : "—" }
    function duration(seconds) {
        const minutes = Math.floor(seconds / 60)
        if (minutes < 60) return minutes + "m"
        const hours = Math.floor(minutes / 60)
        return hours >= 24 ? Math.floor(hours / 24) + "d " + hours % 24 + "h"
            : hours + "h " + minutes % 60 + "m"
    }
    function matar(pid, start) {
        if (terminate.running) return
        processNotice = "Ending process…"
        terminate.command = ["python3", Quickshell.shellPath("tools/sistema.py"), "--terminate", String(pid), String(start)]
        terminate.running = true
    }
    Process {
        id: terminate
        stdout: StdioCollector { onStreamFinished: sistema.processNotice = text.trim() }
    }

    property var previousCpu: null
    property var previousNet: null
    property real previousTime: 0
    property int tick: 0
    property real previousDetailTime: 0
    function reset() {
        previousCpu = null; previousNet = null; previousTime = 0
        cpuUso = -1; redRx = -1; redTx = -1; cpuTemp = 0
        cpuHist = []; ramHist = []; redHist = []
    }
    onRapidoChanged: { reset(); if (rapido) poll() }
    onMirandoChanged: {
        procesos = []; processesReady = false; processNotice = ""
        gpuUso = -1; gpuTemp = 0; gpuMemUsada = -1; gpuHist = []
        previousDetailTime = 0
        discoPct = -1
    }
    function poll() {
        clockFile.reload()
        const now = parseFloat(clockFile.text())
        if (!isFinite(now)) { reset(); return }
        const dt = now - previousTime
        if (dt > 5 || dt <= 0) reset()
        uptime = now
        statFile.reload(); memFile.reload(); routeFile.reload(); route6File.reload(); netFile.reload()
        const cpu = Metrics.cpu(statFile.text())
        cpuUso = Metrics.cpuPercent(previousCpu, cpu)
        previousCpu = cpu
        cpuHilos = cpu ? cpu.threads : 0
        const memory = Metrics.memory(memFile.text())
        if (memory) {
            ramTotal = memory.total / 1073741824
            ramUsada = memory.used / 1073741824
            ramPct = memory.used / memory.total * 100
            swapUsada = memory.swapUsed / 1073741824
            swapTotal = memory.swapTotal / 1073741824
        } else { ramTotal = 0; ramPct = -1 }
        const iface = Metrics.defaultInterface(routeFile.text(), route6File.text())
        if (iface !== redIface) redHist = []
        redIface = iface
        const counters = Metrics.network(netFile.text(), iface)
        const rates = Metrics.rates(previousNet, counters, dt)
        redRx = rates ? rates.rx : -1; redTx = rates ? rates.tx : -1
        previousNet = counters; previousTime = now
        tick += 1
        if (tick % 2 === 0) {
            cpuHist = empujar(cpuHist, cpuUso)
            ramHist = empujar(ramHist, ramPct)
            redHist = empujar(redHist, rates ? rates.rx + rates.tx : -1)
            if (rutaTempCpu) cpuTemperature.reload()
            if (rutaTempNvme && mirando) diskTemperature.reload()
        }
    }
    Timer { interval: 1000; repeat: true; running: sistema.rapido; onTriggered: sistema.poll() }
    FileView { id: clockFile; path: "/proc/uptime"; blockLoading: true }
    FileView { id: statFile; path: "/proc/stat"; blockLoading: true }
    FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true }
    FileView { id: netFile; path: "/proc/net/dev"; blockLoading: true }
    FileView { id: routeFile; path: "/proc/net/route"; blockLoading: true }
    FileView { id: route6File; path: "/proc/net/ipv6_route"; blockLoading: true }
    FileView {
        id: cpuTemperature; path: sistema.rutaTempCpu; blockLoading: true
        onLoaded: sistema.cpuTemp = parseFloat(text()) / 1000 || 0
        onLoadFailed: sistema.cpuTemp = 0
    }
    FileView {
        id: diskTemperature; path: sistema.rutaTempNvme; blockLoading: true
        onLoaded: sistema.tempNvme = parseFloat(text()) / 1000 || 0
        onLoadFailed: sistema.tempNvme = 0
    }
    function receive(line) {
        let data
        try { data = JSON.parse(line) } catch (error) { return }
        if (data.chips) {
            rutaTempCpu = data.chips.cpu || ""; rutaTempNvme = data.chips.nvme || ""
            cpuName = data.cpuName || "Processor"
            gpuNombre = data.gpu ? data.gpu.name : ""
        }
        if (data.gpuReading !== undefined) {
            if (previousDetailTime && data.sampleTime - previousDetailTime > 5) gpuHist = []
            previousDetailTime = data.sampleTime
            const gpu = data.gpuReading
            gpuUso = gpu && gpu.usage !== null ? gpu.usage : -1
            gpuTemp = gpu && gpu.temperature !== null ? gpu.temperature : 0
            gpuMemUsada = gpu && gpu.used !== null ? gpu.used / 1048576 : -1
            gpuMemTotal = gpu && gpu.total !== null ? gpu.total / 1048576 : 0
            if (gpu) { gpuNombre = gpu.name; gpuMemoryLabel = gpu.memoryLabel }
            gpuHist = empujar(gpuHist, gpuUso)
        }
        if (data.storage !== undefined) {
            const disk = data.storage
            discoPct = disk ? disk.percent : -1
            discoTotal = disk ? disk.total / 1073741824 : 0
            discoUsado = disk ? disk.used / 1073741824 : 0
            diskAvailable = disk ? disk.available / 1073741824 : 0
            diskReserved = disk ? disk.reserved / 1073741824 : 0
            diskPath = disk ? disk.path : ""
            diskMount = disk ? disk.mount : ""
            diskFilesystem = disk ? disk.filesystem : ""
            diskDevice = disk ? disk.device : ""
        }
        if (data.procesos) { procesos = data.procesos; processesReady = true }
    }
    Process {
        command: ["python3", Quickshell.shellPath("tools/sistema.py"), "--discover"]
        running: true
        stdout: SplitParser { onRead: line => sistema.receive(line) }
    }
    Process {
        running: sistema.mirando
        command: ["python3", Quickshell.shellPath("tools/sistema.py")]
        stdout: SplitParser { onRead: line => sistema.receive(line) }
        onExited: {
            sistema.gpuUso = -1
            if (sistema.mirando) {
                sistema.procesos = []; sistema.processesReady = true
                sistema.gpuTemp = 0; sistema.gpuMemUsada = -1
                sistema.processNotice = "System sampling stopped. Reopen to retry."
            }
        }
    }
}
