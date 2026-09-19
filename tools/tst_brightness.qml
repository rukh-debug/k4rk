import QtQuick
import QtTest
import K4 as K4
import "../core" as Core
import "../services" as Services
import "../plugins/Settings" as SettingsUI

Item {
    id: fixture
    Core.PanelIslandView {
        id: panel
        plugin: Services.PanelIsland
        width: plugin.islandWidth
        height: plugin.islandHeight
    }
    Component { id: editorFactory; SettingsUI.PanelEditor { width: 540 } }
    TestCase {
        name: "Brightness"
        when: fixture.Window.window !== null && Services.Settings.cargado
        function initTestCase() {
            K4.Puente.tema = Core.Theme
            Services.PanelIsland.openTab("controls")
            tryCompare(Services.Brightness, "busy", false)
            tryCompare(Services.Brightness, "available", true)
            compare(Services.Brightness.selectedId, "backlight:mock")
        }
        function find(item, name) {
            if (item.objectName === name) return item
            for (const child of item.children) {
                const result = find(child, name)
                if (result) return result
            }
            return null
        }
        function init() {
            Services.Settings.panelShowToggles = true
            Services.Settings.panelTileWifi = true
            Services.Settings.panelTileBluetooth = true
            Services.Settings.panelTileSound = true
            Services.Settings.panelTileBrightness = true
            Services.PanelIsland.openTab("controls")
            wait(50)
        }
        function test_layout_data() {
            const rows = []
            for (const width of [640, 780, 1100])
                for (let mask = 0; mask < 16; ++mask)
                    rows.push({ tag: width + "-" + mask, width: width, mask: mask })
            return rows
        }
        function test_layout(data) {
            Services.Settings.panelWidth = data.width
            Services.Settings.panelTileWifi = !!(data.mask & 1)
            Services.Settings.panelTileBluetooth = !!(data.mask & 2)
            Services.Settings.panelTileSound = !!(data.mask & 4)
            Services.Settings.panelTileBrightness = !!(data.mask & 8)
            wait(60)
            compare(Services.Settings.bloqueVisible("toggles"), data.mask !== 0)
            const radios = !!(data.mask & 3), sliders = !!(data.mask & 12)
            compare(Services.PanelIsland.altoDe("toggles"), (radios ? 96 : 0) + (sliders ? 120 : 0) + (radios && sliders ? 12 : 0))
            if (data.mask & 8) {
                const card = find(panel, "brightness-card")
                const slider = find(panel, "brightness-slider")
                verify(card.visible && slider.width > 150, "Brightness has a usable track")
                const point = card.mapToItem(panel, 0, 0)
                verify(point.x >= 20 && point.x + card.width <= panel.width - 19)
                if (data.mask & 4) {
                    const sound = find(panel, "sound-card")
                    const soundSlider = find(panel, "sound-slider")
                    compare(card.height, sound.height)
                    compare(card.y, sound.y)
                    verify(Math.abs(card.width - sound.width) <= 1)
                    compare(Math.round(slider.mapToItem(panel, 0, 0).y), Math.round(soundSlider.mapToItem(panel, 0, 0).y))
                }
            }
            const editor = createTemporaryObject(editorFactory, panel)
            verify(editor !== null)
            compare(editor.visibleEl("toggles"), data.mask !== 0)
        }
        function test_keyboard_and_drag() {
            Services.Brightness.selectDisplay("backlight:mock")
            tryCompare(Services.Brightness, "busy", false)
            const slider = find(panel, "brightness-slider")
            slider.forceActiveFocus()
            const before = Services.Brightness.value
            keyClick(Qt.Key_Right)
            compare(Services.Brightness.value, before + 1)
            keyClick(Qt.Key_Home)
            compare(Services.Brightness.value, 1)
            keyClick(Qt.Key_End)
            compare(Services.Brightness.value, 100)
            mousePress(slider, slider.width * 0.4, slider.height / 2)
            verify(Services.PanelIsland.interactionActive)
            verify(Services.Brightness.dragging)
            mouseMove(slider, slider.width * 0.6, slider.height / 2)
            mouseRelease(slider, slider.width * 0.6, slider.height / 2)
            verify(!Services.Brightness.dragging)
            verify(!Services.PanelIsland.interactionActive)
            tryVerify(function() { return !Services.Brightness.busy && !Object.keys(Services.Brightness.pending).length })
        }
        function test_failed_write_and_disabled_control() {
            Services.Brightness.selectDisplay("ddc:mock")
            tryCompare(Services.Brightness, "busy", false)
            const before = Services.Brightness.value
            Services.Brightness.setValue(13)
            compare(Services.Brightness.value, 13)
            tryVerify(function() { return !Services.Brightness.busy && !Object.keys(Services.Brightness.pending).length })
            compare(Services.Brightness.value, before)
            verify(Services.Brightness.error.indexOf("Simulated") >= 0)
            Services.Brightness.setValue(55)
            tryVerify(function() { return !Services.Brightness.busy && !Object.keys(Services.Brightness.pending).length })
            compare(Services.Brightness.value, 55)
            compare(Services.Brightness.error, "")
            Services.Brightness.displays = Services.Brightness.displays.map(d =>
                d.id === "ddc:mock" ? Object.assign({}, d, { available: false, error: "No I²C access" }) : d)
            const slider = find(panel, "brightness-slider")
            verify(!slider.enabled)
            compare(find(panel, "brightness-percentage").text, "—")
            Services.Brightness.setValue(99)
            compare(Object.keys(Services.Brightness.pending).length, 0)
            Services.Brightness.refresh()
            tryCompare(Services.Brightness, "busy", false)
            verify(slider.enabled)
        }
        function test_picker_and_inflight_writes() {
            const picker = find(panel, "brightness-display-picker")
            compare(picker.count, 2)
            picker.forceActiveFocus()
            keyClick(Qt.Key_Space)
            tryCompare(picker.popup, "visible", true)
            verify(Services.PanelIsland.interactionActive)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Return)
            tryCompare(picker.popup, "visible", false)
            compare(Services.Brightness.selectedId, "ddc:mock")
            Services.Brightness.setValue(30)
            tryVerify(function() { return Services.Brightness.busy })
            Services.Brightness.setValue(42)
            Services.Brightness.selectDisplay("backlight:mock")
            Services.Brightness.setValue(63)
            tryVerify(function() { return !Services.Brightness.busy && !Object.keys(Services.Brightness.pending).length }, 5000)
            compare(Services.Brightness.displays.find(d => d.id === "ddc:mock").value, 42)
            compare(Services.Brightness.displays.find(d => d.id === "backlight:mock").value, 63)
            compare(Services.Brightness.value, 63)
        }
        function cleanup() {
            if (qtest_results.failed) console.error("FAIL! " + qtest_results.functionName + " " + qtest_results.dataTag)
        }
        function cleanupTestCase() {
            const failures = qtest_results.failCount
            console.log("Brightness UI: " + qtest_results.passCount + " passed, " + failures + " failed")
            Qt.callLater(function() { Qt.exit(failures ? 1 : 0) })
        }
    }
}
