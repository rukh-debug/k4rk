import QtQuick
import QtTest
import K4 as K4
import "../plugins/Agents" as Agents

Item {
    id: fixture
    property var owner: null
    readonly property var page: pageLoader.item

    Component { id: pluginFactory; Agents.AgentsPlugin {} }
    Loader {
        id: pageLoader
        width: 620
        active: fixture.owner !== null
        sourceComponent: Component { Agents.ProvidersPage { plugin: fixture.owner } }
    }
    Loader {
        width: 560
        height: 600
        active: fixture.owner !== null
        visible: false
        sourceComponent: Component { Agents.AgentsView { plugin: fixture.owner } }
    }

    TestCase {
        name: "AgentProviders"
        when: fixture.Window.window !== null && fixture.Window.window.visible

        function initTestCase() {
            fixture.owner = pluginFactory.createObject(fixture, {
                carpeta: Qt.resolvedUrl("../plugins/Agents").toString().replace("file://", "")
            })
            verify(fixture.owner !== null)
            tryCompare(fixture.owner, "settingsReady", true)
            // Current state must beat conflicting legacy state, and the
            // saved empty selection must not launch a default-provider query.
            compare(fixture.owner.enabledProviders.length, 0)
            compare(fixture.owner.avisar, false)
            compare(fixture.owner.umbral, 95)
            compare(fixture.owner.enVivo, false)
            compare(fixture.owner.usageBusy, false)
            fixture.owner.providersPageOpen = true
            fixture.owner.loadCatalog(false, "")
            tryCompare(fixture.owner, "catalogLoaded", true)
        }

        function init() {
            page.filter = "all"
            findChild(page, "providerSearch").text = ""
            page.selected = ""
            fixture.owner.enabledProviders = []
            tryCompare(fixture.owner, "usageBusy", false)
        }

        function cleanupTestCase() {
            console.log("Agents UI: " + qtest_results.passCount + " passed, " + qtest_results.failCount + " failed")
            Qt.exit(qtest_results.failCount > 0 ? 1 : 0)
        }

        function test_fullCatalogAndUnsupportedDetails() {
            verify(page.matches.length > 100)
            verify(page.pageCount > 1)
            findChild(page, "providerSearch").text = "302AI_API_KEY"
            compare(page.matches.length, 1)
            wait(50)
            const toggle = findChild(page, "usage-302ai")
            verify(toggle !== null)
            compare(toggle.enabled, false)
            const details = findChild(page, "details-302ai")
            verify(details.enabled)
            mouseClick(details, 10, 10)
            compare(page.selected, "302ai")
            verify(findChild(page, "providerDetails") !== null)
            fixture.owner.setProviderEnabled("302ai", true)
            compare(fixture.owner.enabledProviders.length, 0)
        }

        function test_disableWhileRequestFinishes() {
            fixture.owner.setProviderEnabled("opencode-go", true)
            tryCompare(fixture.owner, "usageBusy", true)
            wait(100)
            fixture.owner.setProviderEnabled("opencode-go", false)
            compare(fixture.owner.agentes.length, 0)
            tryCompare(fixture.owner, "usageBusy", false)
            compare(fixture.owner.agentes.length, 0)
            compare(fixture.owner.aprieta, false)
        }

        function test_latestSelectionWinsAndPersists() {
            fixture.owner.setProviderEnabled("opencode-go", true)
            tryCompare(fixture.owner, "usageBusy", true)
            wait(80)
            fixture.owner.setProviderEnabled("zai-coding-plan", true)
            fixture.owner.setProviderEnabled("opencode-go", false)
            tryVerify(function () { return !fixture.owner.usageBusy && fixture.owner.agentes.length === 1 })
            compare(fixture.owner.agentes[0].id, "zai-coding-plan")
            compare(fixture.owner.agentes[0].limites[0].pct, 99)
            // A fresh instance reads the user's final selection, even with
            // a conflicting legacy file still present.
            wait(100)
            const restored = pluginFactory.createObject(fixture, { carpeta: fixture.owner.carpeta })
            tryCompare(restored, "settingsReady", true)
            compare(restored.enabledProviders.join(","), "zai-coding-plan")
            compare(restored.avisar, false)
            restored.destroy()
        }

        function test_keyboardToggleAndSharedGoIdentity() {
            findChild(page, "providerSearch").text = "opencode"
            wait(50)
            const go = findChild(page, "usage-opencode-go")
            const zen = findChild(page, "usage-opencode")
            verify(go.enabled)
            compare(zen.enabled, false)
            go.forceActiveFocus()
            keyClick(Qt.Key_Space)
            compare(fixture.owner.enabledProviders.join(","), "opencode-go")
            compare(page.selected, "")
            tryVerify(function () { return !fixture.owner.usageBusy && fixture.owner.agentes.length === 1 })
            compare(fixture.owner.agentes[0].id, "opencode-go")
        }
    }
}
