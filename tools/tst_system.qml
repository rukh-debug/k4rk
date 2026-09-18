import QtQuick
import QtTest
import K4 as K4
import "../core" as Core
import "../services" as Services
import "../plugins/System" as System
import "../services/SystemMetrics.js" as Metrics

Item {
    id: fixture
    System.SystemPlugin { id: plugin }
    Core.PanelIslandView {
        id: panel
        plugin: Services.PanelIsland
        width: panel.plugin.islandWidth; height: panel.plugin.islandHeight
    }
    TestCase {
        name: "SystemMonitor"
        when: fixture.Window.window !== null && Services.Settings.cargado
        function initTestCase() {
            K4.Puente.tema = Core.Theme
            K4.Puente.systemMonitor = Services.Sistema
            K4.Puente.enganches = Services.Enganches
            plugin.panel = Services.PanelIsland
            Services.Settings.panelOrder = ["toggles", "system.stats", "media", "shortcuts"]
            Services.Settings.panelHiddenBlocks = []
            plugin.updateSampling()
            // Card registration normally happens after the host installs its bridge.
            for (const child of plugin.services)
                if (child.name === "stats") child._registrar()
            wait(100)
        }
        function init() {
            Core.Theme.chosenFont = ""
            plugin.tarjetaCpu = true; plugin.tarjetaRam = true; plugin.tarjetaRed = true
            Services.PanelIsland.openTab("controls")
            Services.Settings.panelWidth = 860
            wait(40)
        }
        function cleanup() {
            if (qtest_results.failed) console.error("FAILED: " + qtest_results.functionName + " " + qtest_results.dataTag)
        }
        function find(item, name) {
            if (item.objectName === name && item.visible) return item
            for (const child of item.children) {
                const match = find(child, name)
                if (match) return match
            }
            return null
        }
        function bounds(item, root) {
            if (!item.visible) return
            if (item.objectName.indexOf("system-") === 0 || item.objectName === "tile-system") {
                const position = item.mapToItem(root, 0, 0)
                if (position.x < -1 || position.x + item.width > root.width + 1)
                    console.error("Overflow: " + item.objectName + " x=" + position.x + " width=" + item.width + " root=" + root.width)
                verify(position.x >= -1 && position.x + item.width <= root.width + 1, "Horizontal overflow: " + item.objectName)
                if (position.y < -1 || position.y + item.height > root.height + 1)
                    console.error("Overflow: " + item.objectName + " y=" + position.y + " height=" + item.height + " root=" + root.height)
                verify(position.y >= -1 && position.y + item.height <= root.height + 1, "Vertical overflow: " + item.objectName)
                verify(item.height > 0 && item.width > 0)
            }
            for (const child of item.children) bounds(child, root)
        }
        function contentBounds(item, root) {
            if (!item.visible) return
            const position = item.mapToItem(root, 0, 0)
            verify(position.y >= -1 && position.y + item.height <= root.height + 1,
                "Content overflows " + root.objectName + ": " + item)
            if (item.contentHeight !== undefined && item.font !== undefined)
                verify(item.contentHeight <= item.height + 1, "Text clipped: " + item.text)
            for (const child of item.children) contentBounds(child, root)
        }
        function test_cpuAccounting() {
            const previous = Metrics.cpu("cpu  100 20 30 500 50 0 0 0 80 10\ncpu0 0\ncpu1 0")
            const current = Metrics.cpu("cpu  150 20 50 520 60 0 0 0 120 10\ncpu0 0\ncpu1 0")
            compare(previous.total, 700)
            compare(previous.threads, 2)
            compare(Metrics.cpuPercent(previous, current), 70)
            compare(Metrics.cpuPercent(null, current), -1)
            compare(Metrics.cpuPercent(current, previous), -1)
        }
        function test_memoryAccounting() {
            const memory = Metrics.memory("MemTotal: 8192 kB\nMemAvailable: 2048 kB\nSwapTotal: 4096 kB\nSwapFree: 3072 kB")
            compare(memory.used, 6144 * 1024)
            compare(memory.swapUsed, 1024 * 1024)
            compare(Metrics.memory("MemTotal: 8192 kB"), null)
        }
        function test_networkRoutesAndReset() {
            const header = "Iface Destination Gateway Flags RefCnt Use Metric Mask"
            const route = header + "\nwifi0 00000000 01020304 0003 0 0 600 00000000\neth0 00000000 01020304 0003 0 0 100 00000000"
            compare(Metrics.defaultInterface(route, ""), "eth0")
            compare(Metrics.defaultInterface(header, ""), "")
            compare(Metrics.defaultInterface(header, "00000000000000000000000000000000 00 00000000000000000000000000000000 00 fe800000000000000000000000000001 00000064 0 0 00000003 wifi0"), "wifi0")
            const before = {name: "wifi0", rx: 100, tx: 50}
            const after = {name: "wifi0", rx: 1124, tx: 306}
            compare(Metrics.rates(before, after, 2).rx, 512)
            compare(Metrics.rates(before, after, 2).tx, 128)
            compare(Metrics.rates(before, after, 0), null)
            compare(Metrics.rates(before, after, 30), null)
            compare(Metrics.rates(after, before, 2), null)
            compare(Metrics.rates(before, {name: "eth0", rx: 1124, tx: 306}, 2), null)
        }
        function test_geometry_data() {
            const rows = []
            for (const width of [640, 760, 800, 860, 1100])
                for (const mask of [0, 1, 3, 7]) rows.push({tag: width + "-" + mask, width: width, mask: mask})
            return rows
        }
        function test_geometry(data) {
            Services.Settings.panelWidth = data.width
            plugin.tarjetaCpu = !!(data.mask & 1)
            plugin.tarjetaRam = !!(data.mask & 2)
            plugin.tarjetaRed = !!(data.mask & 4)
            wait(50)
            const card = find(panel, "tile-system")
            verify(card !== null, "System card must register")
            compare(card.height, 112)
            contentBounds(card, card)
            bounds(panel, panel)
            Services.PanelIsland.openTab("system")
            wait(50)
            bounds(panel, panel)
            const cpu = find(panel, "system-cpu")
            const gpu = find(panel, "system-gpu")
            for (const id of ["cpu", "memory", "gpu", "network"]) {
                const tile = find(panel, "system-" + id)
                verify(tile.height >= 108)
                contentBounds(tile, tile)
            }
            if (data.width < 800 && gpu.y <= cpu.y)
                console.error("Grid: cpu=" + cpu.y + " gpu=" + gpu.y + " gridWidth=" + cpu.parent.width + " columns=" + cpu.parent.columns)
            if (data.width < 800) verify(gpu.y > cpu.y)
            else compare(gpu.y, cpu.y)
        }
        function test_keyboardReturnFocus() {
            const card = find(panel, "tile-system")
            verify(card !== null)
            card.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(Services.PanelIsland.tab, "system")
            wait(100)
            keyClick(Qt.Key_Escape)
            compare(Services.PanelIsland.tab, "controls")
            wait(100)
            verify(find(panel, "tile-system").activeFocus)
        }
        function test_liveTelemetry() {
            Services.PanelIsland.openTab("system")
            tryVerify(() => Services.Sistema.processesReady, 7000)
            verify(Services.Sistema.cpuUso >= 0 && Services.Sistema.cpuUso <= 100)
            verify(Services.Sistema.ramUsada <= Services.Sistema.ramTotal)
            verify(Services.Sistema.discoTotal > 0)
            verify(Services.Sistema.diskAvailable >= 0)
            verify(Services.Sistema.procesos.length > 0)
            console.log("Live telemetry: " + JSON.stringify({cpu: Services.Sistema.cpuUso,
                memoryGiB: Services.Sistema.ramUsada, totalGiB: Services.Sistema.ramTotal,
                gpu: Services.Sistema.gpuNombre, gpuPercent: Services.Sistema.gpuUso,
                interface: Services.Sistema.redIface, diskGiB: Services.Sistema.discoTotal,
                diskPercent: Services.Sistema.discoPct}))
            Services.PanelIsland.close()
            wait(200)
            verify(!Services.Sistema.mirando, "Detailed sampling must stop on close")
        }
        function test_alternateFont() {
            Core.Theme.chosenFont = "DejaVu Sans Mono"
            Services.Settings.panelWidth = 640
            Services.PanelIsland.openTab("system")
            wait(100)
            bounds(panel, panel)
        }
        function action(item, text) {
            if (item.text === text && typeof item.clicked === "function") return item
            for (const child of item.children) {
                const match = action(child, text)
                if (match) return match
            }
            return null
        }
        function test_processSortingAndFocus() {
            Services.PanelIsland.openTab("system")
            Services.Sistema.procesos = [
                {pid: 123456, start: "1", nombre: "CPU worker", cpu: 120, ram: 50},
                {pid: 123457, start: "2", nombre: "Memory worker", cpu: 0, ram: 4096}]
            wait(50)
            const list = find(panel, "system-processes")
            compare(list.model.get(0).pid, 123456)
            const end = action(list.itemAtIndex(0), "End")
            verify(end !== null)
            end.forceActiveFocus()
            Services.Sistema.procesos = [
                {pid: 123456, start: "1", nombre: "CPU worker", cpu: 100, ram: 50},
                {pid: 123457, start: "2", nombre: "Memory worker", cpu: 200, ram: 4096}]
            wait(50)
            compare(list.model.get(0).pid, 123456)
            compare(list.model.get(0).cpu, 100)
            verify(end.activeFocus, "Process updates must preserve focus on the same identity")
            const memory = action(panel, "Memory")
            mouseClick(memory)
            wait(50)
            verify(memory.selected)
            compare(list.model.get(0).pid, 123457)
        }
        function test_samplingLeases() {
            Services.PanelIsland.close()
            plugin.habilitado = false
            wait(50)
            verify(!Services.Sistema.rapido)
            K4.SystemMonitor.sample("test.one", true, false)
            K4.SystemMonitor.sample("test.two", true, false)
            K4.SystemMonitor.sample("test.one", false, false)
            verify(Services.Sistema.rapido)
            K4.SystemMonitor.sample("test.two", false, false)
            verify(!Services.Sistema.rapido)
            compare(Services.Sistema.cpuUso, -1)
            compare(Services.Sistema.cpuHist.length, 0)
            plugin.habilitado = true
        }
        function cleanupTestCase() {
            Services.PanelIsland.close()
            plugin.habilitado = false
            console.log("System UI: " + qtest_results.passCount + " passed, " + qtest_results.failCount + " failed")
            if (qtest_results.failCount) Qt.exit(1)
        }
    }
}
