import QtQuick
import QtTest
import Quickshell
import K4 as K4
import "../core"
import "../services"
import "../services/PopupPlacement.js" as Placement
import "../plugins/Settings" as SettingsUi

Item {
    id: fixture
    K4.Plugin {
        id: firstOwner
        name: "first"
        independentIsland: true
        colocable: true
        priority: 90
        closeOnClickOutside: false
        view: Component { Item {} }
        function close() { active = false }
    }
    K4.Plugin {
        id: secondOwner
        name: "second"
        colocable: true
        priority: 80
        view: Component { Item {} }
        function close() { active = false }
    }
    Component { id: popupFactory; IndependentIsland { owner: firstOwner } }
    Component {
        id: settingsPageFactory
        SettingsUi.PlacementPage {
            width: 620
            onExpansionChanged: function (cards) { expandedCards = cards }
        }
    }
    QtObject {
        id: settingsOwner
        property string paginaPedida: "placement"
        property string currentPage: ""
        property var popupExpandedCards: ({})
        property var settingsScrollPositions: ({})
        property var version: ({ commit: "test", hayNovedad: false, sucio: false, detras: 0 })
        function close() {
            currentPage = ""
            popupExpandedCards = ({})
            settingsScrollPositions = ({})
        }
    }
    Component {
        id: settingsViewFactory
        SettingsUi.AjustesView { width: 940; height: 620; plugin: settingsOwner }
    }
    QtObject {
        id: firstWindow
        property var owner: firstOwner
        property bool visible: true
        property bool hovered: false
        property string pantalla: "test"
        property var placementRequest: fixture.request("top", 0, "first")
    }
    QtObject {
        id: secondWindow
        property var owner: secondOwner
        property bool visible: true
        property bool hovered: false
        property string pantalla: "test"
        property var placementRequest: fixture.request("top", 0, "second")
    }
    PopupExclusionRegion { id: holes; screenName: "test" }

    function request(side, align, id) {
        return { id: id || "test", screen: "test", screenWidth: 1000, screenHeight: 800,
                 width: 200, height: 100, placement: { side: side, align: align } }
    }
    function corner(index) {
        return { x: index === 1 || index === 2 ? 800 : 0,
                 y: index >= 2 ? 700 : 0, width: 200, height: 100 }
    }

    TestCase {
        name: "IndependentIslands"
        when: fixture.Window.window !== null
        property int previousFailures: 0
        property string checkpoint: ""

        function initTestCase() {
            tryCompare(Settings, "cargado", true)
        }

        function init() {
            checkpoint = "setup"
            PopupLayout.windows = []
            PopupLayout.placements = ({})
            PopupLayout.previousRequests = ({})
            Island.rects = ({})
            Settings.independentIslands = ({})
            Settings.popupSizes = ({})
            firstOwner.islandWidth = 300
            firstOwner.islandHeight = 160
            firstWindow.visible = true
            firstWindow.placementRequest = fixture.request("top", 0, "first")
            secondWindow.placementRequest = fixture.request("top", 0, "second")
            firstOwner.grabKeyboard = false
            secondOwner.grabKeyboard = false
            firstOwner.viewLoaded = true
            secondOwner.viewLoaded = true
            firstOwner.closeOnClickOutside = true
            firstOwner.active = false
            secondOwner.active = false
        }

        function test_clockwiseFromEveryCorner() {
            const points = [{ side: "top", align: 0 }, { side: "top", align: 100 },
                            { side: "bottom", align: 100 }, { side: "bottom", align: 0 }]
            for (let i = 0; i < 4; ++i) {
                const chosen = Placement.choose(fixture.request(points[i].side, points[i].align),
                                                [fixture.corner(i)], 24, null)
                const expected = fixture.corner((i + 1) % 4)
                compare(chosen.x, expected.x)
                compare(chosen.y, expected.y)
            }
        }

        function test_edgePreferenceAndClockwiseFallback() {
            const sides = ["top", "right", "bottom", "left"]
            for (let i = 0; i < sides.length; ++i) {
                const request = fixture.request(sides[i], 50)
                const home = Placement.choose(request, [], 24, null)
                const moved = Placement.choose(request, [home], 24, null)
                const expected = fixture.corner((i + 1) % 4)
                compare(moved.x, expected.x)
                compare(moved.y, expected.y)
            }
        }

        function test_skipSeveralOccupiedCorners() {
            const chosen = Placement.choose(fixture.request("top", 0),
                [fixture.corner(0), fixture.corner(1), fixture.corner(2)], 24, null)
            compare(chosen.x, 0)
            compare(chosen.y, 700)
        }

        function test_leastOverlapAndStableTies() {
            const blocked = [fixture.corner(0), fixture.corner(1), fixture.corner(2), fixture.corner(3)]
            blocked[2].width = 30
            const chosen = Placement.choose(fixture.request("top", 0), blocked, 0, null)
            compare(chosen.x, 800)
            compare(chosen.y, 700)
            blocked[2].width = 200
            compare(Placement.choose(fixture.request("top", 100), blocked, 0, null).y, 0)
            compare(Placement.choose(fixture.request("top", 100), blocked, 0, null).x, 800)
        }

        function test_clearanceAndPreviousAllocation() {
            const req = fixture.request("top", 0)
            const near = [{ x: 210, y: 0, width: 100, height: 100 }]
            compare(Placement.choose(req, near, 0, null).x, 0)
            compare(Placement.choose(req, near, 24, null).x, 800)
            const previous = Placement.choose(req, near, 24, null)
            compare(Placement.choose(req, [], 24, previous), previous)
            compare(Placement.choose(req, [previous], 24, previous).x, 0)
        }

        function test_overrideDefaultsAndPersistence() {
            compare(Settings.independentIslandFor(firstOwner), true)
            compare(Settings.independentIslandFor(secondOwner), false)
            Settings.setIndependentIsland("first", false)
            Settings.setIndependentIsland("second", true)
            wait(100)
            Settings.independentIslands = ({})
            Settings.cargar()
            compare(Settings.independentIslandFor(firstOwner), false)
            compare(Settings.independentIslandFor(secondOwner), true)
            Settings.ponerPlacementMemoria("first", "", 50)
            compare(Settings.independentIslandFor(firstOwner), false)
        }

        function test_sharedAllocationAndMaskCleanup() {
            Island.rects = ({ test: { x: 0, y: 0, ancho: 220, alto: 120 } })
            PopupLayout.registerWindow(firstWindow)
            PopupLayout.registerWindow(secondWindow)
            PopupLayout.reflow()
            compare(PopupLayout.placements.first.x, 800)
            compare(PopupLayout.placements.first.y, 0)
            compare(PopupLayout.placements.second.x, 800)
            compare(PopupLayout.placements.second.y, 700)
            tryCompare(holes.regions, "length", 2)
            PopupLayout.unregisterWindow(firstWindow)
            PopupLayout.reflow()
            compare(PopupLayout.placements.first, undefined)
            compare(PopupLayout.placements.second.y, 700)
            tryCompare(holes.regions, "length", 1)
        }

        function test_monitorIsolationAndSettingsMove() {
            const other = fixture.request("top", 0, "second")
            other.screen = "other"
            secondWindow.placementRequest = other
            PopupLayout.registerWindow(firstWindow)
            PopupLayout.registerWindow(secondWindow)
            PopupLayout.reflow()
            compare(PopupLayout.placements.first.x, 0)
            compare(PopupLayout.placements.second.x, 0)
            firstWindow.placementRequest = fixture.request("bottom", 100, "first")
            PopupLayout.reflow()
            compare(PopupLayout.placements.first.x, 800)
            compare(PopupLayout.placements.first.y, 700)
        }

        function test_realWindowLifecycle() {
            firstOwner.closeOnClickOutside = false
            const window = createTemporaryObject(popupFactory, fixture, {
                pantalla: Quickshell.screens[0].name,
                preferredPlacement: { side: "top", align: 50 }
            })
            verify(window !== null)
            tryVerify(function () { return !!window.allocated && window.width > 0 })
            const loader = findChild(window.contentItem, "independentContent")
            verify(loader !== null)
            verify(loader.item !== null)
            const item = loader.item
            Settings.setPopupDimension("first", "width", 560)
            Settings.setPopupDimension("first", "height", 320)
            tryVerify(function () { return window.placementRequest.width === Math.min(560, window.width) })
            compare(window.placementRequest.height, Math.min(320, window.height))
            compare(loader.item, item)
            Settings.resetPopupSize("first")
            tryVerify(function () { return window.placementRequest.width === 300 })
            window.preferredPlacement = { side: "bottom", align: 100 }
            tryVerify(function () { return window.allocated.side === "bottom" })
            compare(loader.item, item)
            firstOwner.viewLoaded = false
            tryCompare(loader, "item", null)
            window.destroy()
            tryVerify(function () { return PopupLayout.windows.length === 0 })
            tryVerify(function () { return !PopupLayout.placements.first })
        }

        function test_realHostCoexistenceAndOverride() {
            Settings.islandSpace = "onTop"
            firstOwner.closeOnClickOutside = false
            secondOwner.closeOnClickOutside = false
            PluginManager.instancias = [firstOwner, secondOwner]
            const factory = Qt.createComponent(Qt.resolvedUrl("../shell.qml"))
            compare(factory.status, Component.Ready, factory.errorString())
            const host = createTemporaryObject(factory, fixture)
            verify(host !== null)
            secondOwner.active = true
            tryCompare(host, "activePlugin", secondOwner)
            firstOwner.active = true
            tryVerify(function () { return PopupLayout.windows.length === 1 })
            wait(150)
            compare(host.activePlugin, secondOwner)
            compare(secondOwner.active, true)
            compare(firstOwner.active, true)

            // Disabling independence moves the same request into the normal
            // replacement rule, even when another main view was already open.
            Settings.setIndependentIsland("first", false)
            tryCompare(secondOwner, "active", false)
            tryCompare(host, "activePlugin", firstOwner)
            Settings.setPopupDimension("first", "width", 500)
            Settings.setPopupDimension("first", "height", 300)
            checkpoint = "main host dimensions"
            tryVerify(function () {
                const rect = Island.rects[Island.pantallaActiva]
                return rect && rect.ancho >= 500 && rect.alto === 300
            })
            tryVerify(function () { return PopupLayout.windows.length === 0 })
            Settings.setIndependentIsland("first", true)
            tryVerify(function () { return PopupLayout.windows.length === 1 })
            verify(host.activePlugin !== firstOwner)
            firstOwner.active = false
            tryVerify(function () { return PopupLayout.windows.length === 0 })
            host.destroy()
            wait(100)
            PluginManager.instancias = []
        }

        function test_focusAndOutsideClickOwnership() {
            PopupLayout.registerWindow(firstWindow)
            PopupLayout.registerWindow(secondWindow)
            compare(PopupLayout.outsideOwner("test"), secondOwner)
            compare(PopupLayout.distantOwners("test").length, 0)
            compare(PopupLayout.distantOwners("other").length, 2)
            compare(PopupLayout.keyboardOwner, null)
            firstOwner.grabKeyboard = true
            compare(PopupLayout.keyboardOwner, firstOwner)
            secondOwner.grabKeyboard = true
            compare(PopupLayout.keyboardOwner, secondOwner)
            secondOwner.viewLoaded = false
            compare(PopupLayout.keyboardOwner, firstOwner)
            compare(PopupLayout.outsideOwner("test"), firstOwner)
        }

        function test_sizeDefaultsValidationAndMigration() {
            checkpoint = "automatic size"
            compare(Settings.popupSizeFor(firstOwner, "width"), 300)
            Settings.setPopupDimension("first", "width", 520)
            firstOwner.islandWidth = 480
            firstOwner.islandHeight = 200
            compare(Settings.popupSizeFor(firstOwner, "width"), 520)
            compare(Settings.popupSizeFor(firstOwner, "height"), 200)
            Settings.setPopupDimension("first", "width", 0)
            compare(Settings.popupSizeFor(firstOwner, "width"), 480)
            Settings.loadPopupSizes({ settingsIslandWidth: 1100, settingsIslandHeight: 700, panelWidth: 900 })
            checkpoint = "legacy migration"
            compare(Settings.settingsIslandWidth, 1100)
            compare(Settings.settingsIslandHeight, 700)
            compare(Settings.panelWidth, 900)
            Settings.loadPopupSizes({ popupSizes: {}, settingsIslandWidth: 1100 })
            checkpoint = "explicit automatic size"
            compare(Settings.settingsIslandWidth, 940)
            Settings.loadPopupSizes({ popupSizes: { first: { width: "broken", height: -1 },
                settings: { width: 2, height: 100000 }, invalid: [] } })
            checkpoint = "invalid data"
            compare(Settings.popupDimension("first", "width"), 0)
            compare(Settings.popupDimension("first", "height"), 0)
            compare(Settings.settingsIslandWidth, 720)
            compare(Settings.settingsIslandHeight, 2160)
            Settings.setPopupDimension("first", "width", 640)
            checkpoint = "persist and reload"
            wait(100)
            Settings.cargar()
            compare(Settings.popupDimension("first", "width"), 640)
        }

        function test_popupEditorDisclosureAndSizing() {
            checkpoint = "page creation"
            PluginManager.instancias = [firstOwner, secondOwner]
            PluginManager._porId = ({ first: firstOwner, second: secondOwner })
            const page = createTemporaryObject(settingsPageFactory, fixture)
            verify(page !== null)
            compare(page.expandedCount, 0)
            const card = findChild(page, "popup-card-first")
            verify(card !== null)
            verify(!card.expanded)
            const disclosure = findChild(page, "popup-disclosure-first")
            disclosure.clicked()
            checkpoint = "expand one"
            tryCompare(card, "expanded", true)
            const field = findChild(page, "popup-first-width")
            verify(field !== null)
            field.text = "640"
            field.editingFinished()
            checkpoint = "edit width: " + field.text + ", valid=" + field.acceptableInput
            compare(Settings.popupDimension("first", "width"), 640)
            compare(card.expanded, true)
            const toggle = findChild(page, "popup-separate-first")
            toggle.alternado()
            checkpoint = "toggle independently"
            compare(card.expanded, true)
            page.width = 420
            wait(50)
            checkpoint = "narrow layout"
            verify(field.width > 0)
            const point = field.mapToItem(card, 0, 0)
            verify(point.x >= 0 && point.x + field.width <= card.width)
            verify(findChild(page, "popup-position-preview-first").width > 0)
            page.expandAll(true)
            checkpoint = "expand all"
            compare(page.expandedCount, page.surfaces.length)
            page.expandAll(false)
            checkpoint = "collapse all"
            compare(page.expandedCount, 0)
            verify(findChild(page, "popup-first-width") === null)
            page.destroy()
            PluginManager.instancias = []
            PluginManager._porId = ({})
        }

        function test_settingsNavigationPreservesDisclosure() {
            checkpoint = "settings page order"
            const pages = Settings.definicion.map(function (page) { return page.grupo })
            const index = pages.indexOf("Popups & Layout")
            compare(pages[index - 1], "Control Centre")
            compare(pages[index + 1], "Display")
            verify(!Settings.definicion[0].opciones.some(function (option) {
                return option.id === "settingsIslandWidth" || option.id === "settingsIslandHeight"
            }))
            PluginManager.instancias = [firstOwner]
            PluginManager._porId = ({ first: firstOwner })
            settingsOwner.paginaPedida = "placement"
            const view = createTemporaryObject(settingsViewFactory, fixture)
            verify(view !== null)
            checkpoint = "settings disclosure"
            tryCompare(view, "selectedPage", "placement")
            findChild(view, "popup-disclosure-first").clicked()
            compare(view.popupExpandedCards.first, true)
            checkpoint = "navigate away and return"
            view.irASeccion("island")
            view.irASeccion("placement")
            tryVerify(function () {
                const card = findChild(view, "popup-card-first")
                return card && card.expanded
            })
            view.width = 720
            wait(100)
            const card = findChild(view, "popup-card-first")
            const input = findChild(card, "popup-first-width")
            const point = input.mapToItem(card, 0, 0)
            verify(point.x >= 0 && point.x + input.width <= card.width)
            view.destroy()
            wait(10)
            checkpoint = "rehost the open settings session"
            const rehosted = createTemporaryObject(settingsViewFactory, fixture)
            tryCompare(rehosted, "selectedPage", "placement")
            compare(rehosted.popupExpandedCards.first, true)
            settingsOwner.close()
            rehosted.destroy()
            wait(10)
            settingsOwner.paginaPedida = "placement"
            const reopened = createTemporaryObject(settingsViewFactory, fixture)
            checkpoint = "fresh settings session"
            compare(Object.keys(reopened.popupExpandedCards).length, 0)
            reopened.destroy()
            PluginManager.instancias = []
            PluginManager._porId = ({})
        }

        function cleanupTestCase() {
            PopupLayout.windows = []
            console.log("Popup tests: " + qtest_results.passCount + " passed, "
                        + qtest_results.failCount + " failed")
            Qt.exit(qtest_results.failCount > 0 ? 1 : 0)
        }

        function cleanup() {
            if (qtest_results.failCount > previousFailures)
                console.error("Popup test failed:", qtest_results.functionName, checkpoint)
            previousFailures = qtest_results.failCount
        }
    }
}
