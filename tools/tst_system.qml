import QtQuick
import QtTest
import Quickshell.Io
import K4 as K4
import "../core" as Core
import "../services" as Services
import "../plugins/System" as System
import "../plugins/Settings" as SettingsUI
import "../services/SystemMetrics.js" as Metrics

Item {
    id: fixture
    System.SystemPlugin { id: plugin }
    Core.PanelIslandView {
        id: panel
        plugin: Services.PanelIsland
        width: panel.plugin.islandWidth; height: panel.plugin.islandHeight
    }
    Component {
        id: settingsPreview
        SettingsUI.PillEditor { width: 540 }
    }
    Component {
        id: savedSettings
        FileView { path: Services.Settings.ruta; blockLoading: true }
    }
    Component {
        id: widthSpy
        SignalSpy { signalName: "widthChanged" }
    }
    Component {
        id: pillViews
        Item {
            property alias idle: idle
            property alias clock: clock
            property alias player: player
            Core.IdleIslandView {
                id: idle
                plugin: Services.IdleIsland
                width: plugin.islandWidth; height: plugin.islandHeight
            }
            Core.ClockIslandView {
                id: clock
                plugin: Services.ClockIsland
                width: plugin.islandWidth; height: plugin.islandHeight
            }
            Core.PlayerIslandView {
                id: player
                plugin: Services.PlayerIsland
                width: plugin.islandWidth; height: plugin.islandHeight
            }
        }
    }
    QtObject {
        id: telemetry
        property bool cargado: true
        property real cpuUso: 0
        property real cpuTemp: -1
        property real ramPct: 0
        property real ramUsada: 0
        property real ramTotal: 8
        property real redRx: 0
        property real redTx: 0
        property string redIface: "test0"
        property Component monitorView: null
        function sample(owner, active, detailed) {}
        function tasaCorta(bytes) { return Services.Sistema.tasaCorta(bytes) }
        function tasa(bytes) { return Services.Sistema.tasa(bytes) }
        function grados(value) { return Services.Sistema.grados(value) }
    }
    TestCase {
        name: "SystemMonitor"
        when: fixture.Window.window !== null && Services.Settings.cargado
        function initTestCase() {
            K4.Puente.tema = Core.Theme
            K4.Puente.systemMonitor = Services.Sistema
            K4.Puente.enganches = Services.Enganches
            K4.Puente.indicadores = Services.Indicadores
            plugin.habilitado = false
            plugin.habilitado = true
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
            Services.Settings.setPopupDimension("panel", "width", 860, false)
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
        function test_compactRates() {
            const format = Services.Sistema.tasaCorta
            compare(format(-1), "—")
            compare(format(NaN), "—")
            compare(format(Infinity), "—")
            compare(format(0), "0B")
            compare(format(999), "999B")
            compare(format(999.5), "1K")
            compare(format(1023), "1K")
            compare(format(1023.5), "1K")
            compare(format(999 * 1024), "999K")
            compare(format(1023 * 1024), "1.0M")
            compare(format(1023.5 * 1024), "1.0M")
            compare(format(9.94 * Math.pow(1024, 2)), "9.9M")
            compare(format(9.96 * Math.pow(1024, 2)), "10M")
            compare(format(99.9 * Math.pow(1024, 2)), "100M")
            compare(format(999 * Math.pow(1024, 2)), "999M")
            compare(format(999.5 * Math.pow(1024, 2)), "1.0G")
            compare(format(1023.9 * Math.pow(1024, 2)), "1.0G")
            compare(format(1023.96 * Math.pow(1024, 2)), "1.0G")
            compare(format(Math.pow(1024, 4)), "1.0T")
            compare(format(1023 * Math.pow(1024, 4)), "1.0P")
            compare(format(Math.pow(1024, 5)), "≥1P")
            compare(format(Number.MAX_VALUE), "≥1P")
            for (let unit = 0; unit <= 5; ++unit)
                for (const value of [0, 9.94, 9.95, 9.96, 10, 99.9, 999, 999.5, 1023.9, 1024])
                    verify(format(value * Math.pow(1024, unit)).length <= 4, "Rate exceeded its compact slot")
        }
        function test_indicatorIconSetting() {
            const previousSize = Services.Settings.pillIndicatorIconSize
            try {
                const preview = createTemporaryObject(settingsPreview, fixture)
                verify(preview !== null)
                for (const entry of [{value: 0, expected: 8}, {value: 14, expected: 14}, {value: 100, expected: 20}]) {
                    Services.Settings.poner("pillIndicatorIconSize", entry.value)
                    wait(40)
                    compare(Services.Settings.pillIndicatorIconSize, entry.expected)
                    const frame = find(preview, "indicator-icon-preview")
                    verify(frame !== null)
                    for (const label of ["CPU", "Network", "RAM", "Agents"]) {
                        const icon = find(frame, "indicator-preview-" + label)
                        verify(icon !== null)
                        compare(icon.font.pixelSize, entry.expected)
                        const position = icon.mapToItem(frame, 0, 0)
                        verify(position.y >= 0 && position.y + icon.height <= frame.height,
                            "Preview clipped: " + label)
                    }
                }
                // Read the saved preference from disk independently of Settings' cache.
                const saved = createTemporaryObject(savedSettings, fixture)
                verify(saved !== null)
                compare(JSON.parse(saved.text()).pillIndicatorIconSize, 20)
                Services.Settings.pillIndicatorIconSize = 8
                Services.Settings.cargar()
                compare(Services.Settings.pillIndicatorIconSize, 20)
            } finally {
                Services.Settings.poner("pillIndicatorIconSize", previousSize)
            }
        }
        function test_stablePill_data() {
            const rows = []
            for (const font of ["", "DejaVu Sans Mono"])
                for (const iconSize of [8, 14, 20])
                    rows.push({tag: (font || "default") + "-" + iconSize, font: font, iconSize: iconSize})
            return rows
        }
        function test_stablePill(data) {
            Core.Theme.chosenFont = data.font
            const previousSource = K4.Puente.systemMonitor
            const previousOrder = Services.Settings.pillOrder
            const previousHidden = Services.Settings.pillHiddenItems
            const previousLimit = Services.Settings.pillIndicatorsMax
            const previousIconSize = Services.Settings.pillIndicatorIconSize
            try {
                // Isolate geometry from live kernel samples and unrelated pill blocks.
                K4.Puente.systemMonitor = telemetry
                Services.Settings.pillOrder = ["plugin-indicators"]
                Services.Settings.pillHiddenItems = ["media", "clock-workspaces", "minimized", "tray"]
                Services.Settings.pillIndicatorsMax = 0
                Services.Settings.pillIndicatorIconSize = data.iconSize
                // Ordinary, non-slot indicators use the same sizing as CPU/network.
                Services.Indicadores.registrar("test.agent", "75%", 0xF06A9, "#30d158", 75, true)
                plugin.enPildoraRed = true
                plugin.pintarChips()
                Services.PlayerIsland.asomando = false
                const views = createTemporaryObject(pillViews, fixture)
                verify(views !== null)
                wait(80)
                const roots = [views.idle, views.clock, views.player]
                function geometry() {
                    const result = [Services.Indicadores.anchoAproximado, Services.IdleIsland.estimado]
                    for (const root of roots) {
                        result.push(root.width)
                        for (const id of ["system.cpu", "system.ram", "system.net", "test.agent"]) {
                            const chip = find(root, "pill-" + id)
                            verify(chip !== null, "Missing " + id)
                            result.push(chip.width, chip.mapToItem(root, 0, 0).x)
                            if (id === "system.net") {
                                for (const index of [0, 1]) {
                                    const prefix = find(chip, "pill-system.net-prefix-" + index)
                                    verify(prefix !== null, "Missing network direction " + index)
                                    result.push(prefix.mapToItem(root, 0, 0).x)
                                }
                            }
                        }
                    }
                    return result
                }
                function checkText(item) {
                    if (!item.visible) return
                    if (item.objectName.indexOf("-value-") >= 0) {
                        verify(!item.truncated, "Clipped value: " + item.text)
                        verify(item.contentWidth <= item.width + 0.5, "Value overflow: " + item.text)
                    }
                    for (const child of item.children) checkText(child)
                }
                function checkIcons(size) {
                    for (const root of roots) {
                        for (const indicator of Services.Indicadores.reparto.muestra) {
                            const chip = find(root, "pill-" + indicator.id)
                            const icon = find(chip, chip.objectName + "-icon")
                            verify(icon !== null, "Missing icon: " + indicator.id)
                            compare(icon.font.pixelSize, size)
                            compare(chip.width, Services.Indicadores.anchoDe(indicator), "Stale icon reservation")
                            verify(icon.contentWidth <= icon.width + 0.5, "Clipped icon: " + indicator.id)
                            const position = icon.mapToItem(root, 0, 0)
                            verify(position.x >= 0 && position.x + icon.width <= root.width,
                                "Icon outside horizontal bounds: " + indicator.id)
                            verify(position.y >= 0 && position.y + icon.height <= root.height,
                                "Icon outside vertical bounds: " + indicator.id)
                        }
                        checkText(root)
                    }
                }
                checkIcons(data.iconSize)
                const baseline = geometry()
                const spies = roots.map(root => createTemporaryObject(widthSpy, fixture, {target: root}))
                for (const spy of spies) verify(spy.valid)
                const values = [0, 9, 10, 99, 100, -1]
                const rates = [0, 9, 999, 1023, 1023.5, 999 * 1024, 1023.5 * 1024,
                    9.9 * Math.pow(1024, 2), 9.96 * Math.pow(1024, 2), 99.9 * Math.pow(1024, 2),
                    999 * Math.pow(1024, 2), 999.5 * Math.pow(1024, 2),
                    1023.9 * Math.pow(1024, 2), Math.pow(1024, 3),
                    1023.9 * Math.pow(1024, 4), Math.pow(1024, 5), -1]
                for (let i = 0; i < rates.length; ++i) {
                    telemetry.cpuUso = values[i % values.length]
                    telemetry.ramPct = values[(i + 2) % values.length]
                    telemetry.redRx = rates[i]
                    wait(20)
                    compare(geometry(), baseline, "Download/percent update resized a view")
                    telemetry.redTx = rates[rates.length - 1 - i]
                    wait(20)
                    compare(geometry(), baseline, "Upload update resized a view")
                    for (const root of roots) checkText(root)
                }
                telemetry.cargado = false
                wait(20)
                compare(geometry(), baseline, "Unavailable telemetry changed geometry")
                for (const spy of spies)
                    compare(spy.count, 0, "A transient resize occurred between readings")
                telemetry.cargado = true
                // Font changes must refresh reservations in already-mounted views.
                Core.Theme.chosenFont = data.font ? "" : "DejaVu Sans Mono"
                wait(40)
                for (const root of roots) {
                    for (const indicator of Services.Indicadores.reparto.muestra)
                        compare(find(root, "pill-" + indicator.id).width,
                                Services.Indicadores.anchoDe(indicator), "Stale font reservation")
                    checkText(root)
                }
                Core.Theme.chosenFont = data.font
                wait(40)
                compare(geometry(), baseline)
                // Both live glyphs and first-frame estimates follow the preference.
                const numericReservation = Services.Indicadores.slotWidth(plugin.percentSlots("100%")[0])
                const widths = []
                for (const size of [8, 14, 20]) {
                    Services.Settings.pillIndicatorIconSize = size
                    wait(40)
                    checkIcons(size)
                    widths.push(Services.Indicadores.anchoAproximado)
                    compare(Services.Indicadores.slotWidth(plugin.percentSlots("100%")[0]), numericReservation)
                }
                verify(widths[0] < widths[1] && widths[1] < widths[2], "Icon size did not resize reservations")
                Services.Settings.pillIndicatorIconSize = data.iconSize
                wait(40)
                compare(geometry(), baseline)
                const fullWidth = views.idle.width
                plugin.enPildoraRed = false
                wait(40)
                verify(views.idle.width < fullWidth, "Disabling a chip should reclaim its space")
                plugin.enPildoraRed = true
                wait(40)
                compare(geometry(), baseline)
                Services.Settings.pillIndicatorsMax = 2
                wait(40)
                compare(Services.Indicadores.reparto.ocultos, 2)
                verify(find(views.idle, "pill-system.net") === null)
            } catch (error) {
                console.error("Pill geometry failure: " + error + "\n" + error.stack)
                throw error
            } finally {
                K4.Puente.systemMonitor = previousSource
                Services.Settings.pillOrder = previousOrder
                Services.Settings.pillHiddenItems = previousHidden
                Services.Settings.pillIndicatorsMax = previousLimit
                Services.Settings.pillIndicatorIconSize = previousIconSize
                Services.Indicadores.quitar("test.agent")
                plugin.enPildoraRed = false
                telemetry.cargado = true
            }
        }
        function test_geometry_data() {
            const rows = []
            for (const width of [640, 760, 800, 860, 1100])
                for (const mask of [0, 1, 3, 7]) rows.push({tag: width + "-" + mask, width: width, mask: mask})
            return rows
        }
        function test_geometry(data) {
            Services.Settings.setPopupDimension("panel", "width", data.width, false)
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
            Services.Settings.setPopupDimension("panel", "width", 640, false)
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
