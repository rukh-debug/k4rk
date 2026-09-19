import QtQuick
import QtTest
import Quickshell
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
            name: "PowerDisplay"
            when: fixture.Window.window !== null && Services.Settings.cargado
            function initTestCase() {
                K4.Puente.tema = Core.Theme
                Services.PanelIsland.openTab("night-light")
            }
            function find(item, name) {
                if (item.objectName === name) return item
                for (const child of item.children) {
                    const result = find(child, name)
                    if (result) return result
                }
                return null
            }
            function test_layout_data() {
                return [
                    { tag: "compact-manual", width: 640, mode: "manual" },
                    { tag: "wide-manual", width: 1100, mode: "manual" },
                    { tag: "compact-solar", width: 640, mode: "solar" },
                    { tag: "wide-solar", width: 1100, mode: "solar" }
                ]
            }
            function test_layout(data) {
                Services.Settings.setPopupDimension("panel", "width", data.width, false)
                Services.Settings.nightLightMode = data.mode
                Services.PanelIsland.openTab("night-light")
                wait(100)
                const scroll = find(panel, "power-display-scroll")
                verify(scroll.width > 500)
                compare(scroll.contentWidth, scroll.width)
                for (const name of ["night-light-switch", "night-light-temperature", "night-light-solar"]) {
                    const control = find(panel, name)
                    verify(control !== null, name)
                    verify(control.width > 0 && control.height > 0, name + " has size")
                    const point = control.mapToItem(scroll.contentItem, 0, 0)
                    verify(point.x >= 0 && point.x + control.width <= scroll.width + 1, name + " stays inside viewport")
                }
                const city = find(panel, "night-light-city")
                compare(city.visible, data.mode === "solar")
                if (city.visible) {
                    city.forceActiveFocus()
                    wait(50)
                    const point = city.mapToItem(scroll, 0, 0)
                    verify(point.y >= 0 && point.y + city.height <= scroll.height, "Keyboard focus reveals city search")
                }
            }
            function test_card_visibility_and_editor() {
                Services.Settings.panelShowPowerDisplay = true
                const withCard = Services.PanelIsland.alturaControles()
                Services.Settings.panelShowPowerDisplay = false
                compare(withCard - Services.PanelIsland.alturaControles(), 96)
                Services.Settings.panelShowPowerDisplay = true
                const editor = createTemporaryObject(editorFactory, panel)
                verify(editor !== null)
                verify(editor.bloques.some(b => b.id === "power-display"))
                editor.alternarBloque("power-display", false)
                compare(Services.Settings.bloqueVisible("power-display"), false)
                editor.alternarBloque("power-display", true)
            }
            function test_power_profile_layout() {
                Services.Settings.setPopupDimension("panel", "width", 640, false)
                Services.PanelIsland.openTab("power-mode")
                wait(100)
                const scroll = find(panel, "power-display-scroll")
                let previousRight = 0
                for (const name of ["profile-power-saver", "profile-balanced", "profile-performance"]) {
                    const control = find(panel, name)
                    verify(control.visible && control.width > 100)
                    const point = control.mapToItem(scroll.contentItem, 0, 0)
                    verify(point.x >= previousRight && point.x + control.width <= scroll.width + 1)
                    previousRight = point.x + control.width
                }
            }
            function test_keyboard_slider() {
                Services.PanelIsland.openTab("night-light")
                wait(100) // Let the page's deferred back-button focus settle.
                const slider = find(panel, "night-light-temperature")
                Services.Settings.nightLightTemperature = 4000
                slider.forceActiveFocus()
                keyClick(Qt.Key_Right)
                compare(Services.Settings.nightLightTemperature, 4100)
                keyClick(Qt.Key_Home)
                compare(Services.Settings.nightLightTemperature, 2500)
                keyClick(Qt.Key_End)
                compare(Services.Settings.nightLightTemperature, 6500)
            }
            function test_escape_returns_to_controls() {
                Services.PanelIsland.openTab("night-light")
                find(panel, "night-light-temperature").forceActiveFocus()
                keyClick(Qt.Key_Escape)
                compare(Services.PanelIsland.tab, "controls")
                wait(100)
                const tile = find(panel, "tile-night-light")
                verify(tile !== null && tile.activeFocus, "Back restores focus to the new card")
            }
            function cleanupTestCase() {
                const failures = qtest_results.failCount
                console.log("Power/display UI: " + qtest_results.passCount + " passed, " + failures + " failed")
                Qt.callLater(function() { Qt.exit(failures ? 1 : 0) })
            }
            function cleanup() {
                if (qtest_results.failed) console.error("FAIL! " + qtest_results.functionName + " " + qtest_results.dataTag)
            }
        }
}
