import QtQuick
import QtTest
import "../services" as Services
import "../plugins/Keys" as Keys

Item {
    id: fixture
    Keys.KeysPlugin { id: owner }
    Keys.KeysView {
        id: view
        anchors.fill: parent
        plugin: owner
    }

    TestCase {
        name: "Shortcuts"
        when: fixture.Window.window !== null && fixture.Window.window.visible

        function initTestCase() {
            tryCompare(Services.Shortcuts, "loaded", true)
            tryCompare(owner, "count", 3)
        }

        function init() {
            owner.query = ""
        }

        function cleanupTestCase() {
            console.log("Shortcuts UI: " + qtest_results.passCount + " passed, "
                + qtest_results.failCount + " failed")
            Qt.exit(qtest_results.failCount > 0 ? 1 : 0)
        }

        function test_filterEveryField() {
            for (const query of ["SUPER + Q", "close", "terminal", "media"]) {
                owner.query = query
                tryCompare(owner, "count", 1)
            }
            owner.query = "  SUPER + Q  "
            tryCompare(owner, "count", 1)
            owner.query = "unmatched"
            tryCompare(owner, "count", 0)
            owner.query = ""
            tryCompare(owner, "count", 3)
        }

        function test_keyCapsulesAndRenderedRecords() {
            compare(Services.Shortcuts.keysForCombo(" SUPER + SHIFT + Q ").join("/"),
                    "SUPER/SHIFT/Q")
            compare(Services.Shortcuts.keysForCombo(" + ").length, 0)
            const list = findChild(view, "shortcutList")
            verify(list !== null)
            tryCompare(list, "count", 3)
            list.forceLayout()
            tryVerify(function () { return list.itemAtIndex(0) !== null })
            compare(list.itemAtIndex(0).startsSection, true)
            compare(list.itemAtIndex(0).actionText, "Close the window")
            compare(list.itemAtIndex(1).startsSection, false)
            compare(list.itemAtIndex(1).actionText, "Open terminal")
            compare(list.itemAtIndex(2).startsSection, true)
        }

        function test_openReloadAndClose() {
            Services.Shortcuts.entries = []
            owner.query = "stale query"
            owner.abrir()
            compare(owner.query, "")
            compare(owner.open, true)
            tryCompare(owner, "count", 3)
            owner.close()
            compare(owner.open, false)
            compare(owner.closing, true)
            tryCompare(owner, "closing", false)
        }

        function test_searchInputUpdatesModel() {
            const search = findChild(view, "shortcutSearch")
            verify(search !== null)
            search.text = "media"
            search.textEdited()
            tryCompare(owner, "count", 1)
            compare(owner.entries[0].section, "Media")
        }
    }
}
