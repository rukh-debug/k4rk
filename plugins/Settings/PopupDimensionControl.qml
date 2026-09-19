// One controlled dimension editor, shared by width and height on every card.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: control
    required property var surface
    required property string dimension
    readonly property string label: dimension === "width" ? "Width" : "Height"
    readonly property var limits: Settings.popupSizeLimits(surface.name, dimension)
    readonly property int customValue: Settings.popupDimension(surface.name, dimension)
    readonly property int effectiveValue: Settings.popupSizeFor(surface, dimension)
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        IslandLabel { text: control.label; font.pixelSize: 12; Layout.fillWidth: true }
        K4.ActionButton {
            text: "Auto"
            selected: control.customValue === 0
            Accessible.name: control.surface.title + ": automatic " + control.label.toLowerCase()
            onClicked: Settings.setPopupDimension(control.surface.name, control.dimension, 0)
        }
        TextField {
            id: input
            objectName: "popup-" + control.surface.name + "-" + control.dimension
            Layout.preferredWidth: 80
            implicitHeight: 32
            text: String(control.effectiveValue)
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 12
            horizontalAlignment: TextInput.AlignRight
            selectByMouse: true
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: control.limits.min; top: control.limits.max }
            Accessible.name: control.surface.title + ": " + control.label + " in pixels"
            background: Rectangle {
                radius: 8
                color: Theme.islandBg
                border.width: 1
                border.color: input.activeFocus ? Theme.blue : Theme.track
            }
            function commit() {
                if (acceptableInput && Number(text) !== control.effectiveValue)
                    Settings.setPopupDimension(control.surface.name, control.dimension, Number(text))
                text = Qt.binding(function () { return String(control.effectiveValue) })
            }
            onEditingFinished: commit()
        }
        IslandLabel { text: "px"; color: Theme.muted; font.pixelSize: 10 }
    }

    K4.Deslizador {
        Layout.fillWidth: true
        desde: control.limits.min
        // Keep dragging useful on ordinary displays; the field accepts up to
        // the full validated limit, including sizes for large monitors.
        hasta: Math.max(control.dimension === "width" ? 1600 : 1000, control.effectiveValue)
        paso: 10
        valor: control.effectiveValue
        Accessible.name: control.surface.title + ": " + control.label
        onMovido: function (value) {
            Settings.setPopupDimension(control.surface.name, control.dimension, value, !dragging)
        }
        onDraggingChanged: if (!dragging) Settings.guardar()
    }
}
