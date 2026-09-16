// Loaded by ui-controls-test.qml so Quickshell's static QML modules are registered.
import QtQuick
import QtTest
import K4 as K4

Item {
    id: fixture
    width: 480
    height: 360
    property bool switchValue: false
    property int requests: 0
    property real sliderValue: 15
    property int navigations: 0

    K4.Interruptor {
        id: toggle
        x: 16; y: 16
        marcado: fixture.switchValue
        Accessible.name: "Test switch"
        onAlternado: fixture.requests++
    }
    K4.ActionButton {
        id: action
        x: 16; y: 60
        text: "Apply"
        onClicked: fixture.requests++
    }
    K4.Boton {
        id: icon
        x: 140; y: 60
        glifo: "+"
        Accessible.name: "Test action"
        onPulsado: fixture.requests++
    }
    K4.Deslizador {
        id: slider
        x: 16; y: 112
        width: 260
        etiqueta: "Test level"
        desde: 5
        hasta: 25
        paso: 2
        valor: fixture.sliderValue
        onMovido: function (value) { fixture.sliderValue = value }
    }
    K4.Rodillo {
        id: scroll
        x: 16; y: 180
        width: 280
        height: 100
        Column {
            width: parent.width
            spacing: 8
            Repeater {
                id: buttons
                model: 12
                K4.ActionButton { required property int index; text: "Target " + index }
            }
        }
    }
    K4.Baldosa {
        id: tile
        x: 310; y: 16
        width: 150; height: 90
        onPulsada: fixture.navigations++
        K4.ActionButton {
            id: nestedAction
            anchors.centerIn: parent
            text: "Toggle"
            onClicked: fixture.requests++
        }
    }

    TestCase {
        name: "SharedControls"
        when: fixture.Window.window !== null && fixture.Window.window.visible

        function initTestCase() { wait(100) }
        function cleanupTestCase() {
            console.log("UI controls: " + qtest_results.passCount + " passed, "
                + qtest_results.failCount + " failed")
            if (qtest_results.failCount > 0) Qt.exit(1)
        }

        function init() {
            toggle.enabled = true
            action.enabled = true
            icon.activo = true
            slider.enabled = true
            fixture.switchValue = false
            fixture.sliderValue = 15
            fixture.requests = 0
            fixture.navigations = 0
            scroll.contentY = 0
        }

        function test_switchRequestsOwnerUpdate() {
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
            compare(fixture.requests, 1)
            compare(toggle.marcado, false)
            fixture.switchValue = true
            compare(toggle.marcado, true)
            toggle.forceActiveFocus()
            keyClick(Qt.Key_Space)
            compare(fixture.requests, 2)
            compare(toggle.marcado, true)
        }

        function test_disabledActionsRejectInput() {
            toggle.enabled = false
            action.enabled = false
            icon.activo = false
            mouseClick(toggle, 12, 12)
            mouseClick(action, 12, 12)
            mouseClick(icon, 12, 12)
            compare(fixture.requests, 0)
            compare(toggle.activeFocusOnTab, false)
            compare(icon.enabled, false)
        }

        function test_keyboardActions() {
            action.forceActiveFocus()
            keyClick(Qt.Key_Space)
            compare(fixture.requests, 1)
            keyClick(Qt.Key_Return)
            compare(fixture.requests, 2)
            icon.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(fixture.requests, 3)
        }

        function test_nestedActionDoesNotNavigate() {
            mouseClick(nestedAction, 12, 12)
            compare(fixture.requests, 1)
            compare(fixture.navigations, 0)
            nestedAction.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(fixture.requests, 2)
            compare(fixture.navigations, 0)
            tile.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(fixture.navigations, 1)
        }

        function test_sliderKeyboardAndBounds() {
            slider.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(fixture.sliderValue, 17)
            keyClick(Qt.Key_Home)
            compare(fixture.sliderValue, 5)
            keyClick(Qt.Key_Left)
            compare(fixture.sliderValue, 5)
            keyClick(Qt.Key_End)
            compare(fixture.sliderValue, 25)
            keyClick(Qt.Key_Right)
            compare(fixture.sliderValue, 25)
        }

        function test_sliderPointerAndDisabledState() {
            fixture.sliderValue = 5
            mouseClick(slider, slider.width / 2, slider.height - 14)
            compare(fixture.sliderValue, 15)
            mousePress(slider, 6, slider.height - 14)
            compare(slider.dragging, true)
            compare(fixture.sliderValue, 5)
            mouseMove(slider, slider.width - 6, slider.height - 14)
            compare(fixture.sliderValue, 25)
            mouseRelease(slider, slider.width - 6, slider.height - 14)
            compare(slider.dragging, false)
            slider.enabled = false
            mouseClick(slider, 6, slider.height - 14)
            compare(fixture.sliderValue, 25)
        }

        function test_focusRevealsScrolledControl() {
            const target = buttons.itemAt(buttons.count - 1)
            target.forceActiveFocus(Qt.TabFocusReason)
            tryVerify(function () { return scroll.contentY > 0 })
            const point = target.mapToItem(scroll, 0, 0)
            verify(point.y >= 0)
            verify(point.y + target.height <= scroll.height)
        }
    }
}
