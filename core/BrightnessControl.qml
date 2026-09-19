import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../services"

IslandTile {
    id: card
    required property var panel
    property var controller: Brightness
    radius: 14
    pulsable: false
    implicitHeight: 120

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 10
            IslandLabel { text: "Brightness"; font.pixelSize: 13; font.weight: Font.Medium }
            ComboBox {
                id: displayPicker
                objectName: "brightness-display-picker"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 26
                model: card.controller.displays
                textRole: "name"
                currentIndex: card.controller.displays.findIndex(d => d.id === card.controller.selectedId)
                enabled: count > 1
                Accessible.name: "Display to adjust"
                onActivated: function(index) {
                    K4.Feedback.click()
                    card.controller.selectDisplay(card.controller.displays[index].id)
                }
                contentItem: IslandLabel {
                    text: displayPicker.currentText || "No display"
                    color: Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    rightPadding: displayPicker.enabled ? 20 : 0
                }
                indicator: IconGlyph {
                    visible: displayPicker.enabled
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.ico.chevronDown
                    color: Theme.muted
                    font.pixelSize: 12
                }
                background: Rectangle {
                    radius: 6
                    color: displayPicker.hovered ? Theme.surfaceHi : "transparent"
                    border.width: displayPicker.activeFocus ? 1 : 0
                    border.color: Theme.blue
                }
                popup: Popup {
                    y: displayPicker.height + 4
                    x: displayPicker.width - width
                    width: Math.max(displayPicker.width, 260)
                    padding: 4
                    implicitHeight: Math.min(contentItem.implicitHeight + 8, 240)
                    onOpened: card.panel.interactionActive = true
                    onClosed: card.panel.interactionActive = brightnessSlider.dragging
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: displayPicker.popup.visible ? displayPicker.delegateModel : null
                        currentIndex: displayPicker.highlightedIndex
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }
                    background: Rectangle {
                        color: Theme.islandBg
                        radius: 10
                        border.color: Theme.surfaceHi
                    }
                }
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: displayPicker.popup.width - 8
                    implicitHeight: 40
                    highlighted: displayPicker.highlightedIndex === index
                    Accessible.name: modelData.name
                    contentItem: IslandLabel {
                        text: modelData.name
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: parent.highlighted ? Theme.surfaceHi : "transparent"
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                IconGlyph {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(card.controller.value < 50 ? 0xF00DE : 0xF00E0)
                    color: card.controller.available ? Theme.ink : Theme.muted
                    font.pixelSize: 16
                }
            }
            K4.Deslizador {
                id: brightnessSlider
                objectName: "brightness-slider"
                Layout.fillWidth: true
                enabled: card.controller.available
                Accessible.name: "Brightness of " + (card.controller.selected ? card.controller.selected.name : "display")
                valor: card.controller.value
                desde: 1
                hasta: 100
                sufijo: "%"
                onMovido: function(value) { card.controller.setValue(value) }
                onDraggingChanged: {
                    card.controller.dragging = dragging
                    card.panel.interactionActive = dragging || displayPicker.popup.visible
                }
            }
            IslandLabel {
                objectName: "brightness-percentage"
                text: card.controller.available ? Math.round(card.controller.value) + "%" : "—"
                color: Theme.muted
                font.pixelSize: 11
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
            }
        }
        IslandLabel {
            Layout.fillWidth: true
            text: card.controller.status
            color: card.controller.error || (card.controller.selected && card.controller.selected.error)
                ? Theme.yellow : Theme.muted
            font.pixelSize: 11
            elide: Text.ElideRight
            Accessible.name: text
            ToolTip.visible: statusHover.hovered
            ToolTip.text: text
            HoverHandler { id: statusHover }
        }
    }
    Component.onDestruction: {
        controller.dragging = false
        panel.interactionActive = false
    }
}
