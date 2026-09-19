// Disclosure state belongs to the Settings session, never to a list delegate.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
    id: card
    required property var surfaceInfo
    required property bool expanded
    signal expansionRequested(bool expanded)
    readonly property var surface: SurfaceRegistry.instance(surfaceInfo.id)
    readonly property var icon: SurfaceRegistry.iconFor(surfaceInfo.id)
    readonly property bool customSize: Settings.popupDimension(surfaceInfo.id, "width") > 0
        || Settings.popupDimension(surfaceInfo.id, "height") > 0
    objectName: "popup-card-" + surfaceInfo.id
    implicitHeight: body.implicitHeight + 24
    radius: 12
    color: Theme.surface
    border.width: 1
    border.color: expanded ? Theme.track : "transparent"

    function updateDisclosure() {
        if (!details) return
        if (!expanded && details.item && details.item.containsFocus)
            disclosure.forceActiveFocus(Qt.OtherFocusReason)
        details.active = expanded && !!surface
    }
    onExpandedChanged: updateDisclosure()
    onSurfaceChanged: updateDisclosure()
    Component.onCompleted: updateDisclosure()

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            K4.ActionButton {
                id: disclosure
                objectName: "popup-disclosure-" + card.surfaceInfo.id
                Layout.fillWidth: true
                implicitHeight: 38
                Accessible.name: (card.expanded ? "Collapse " : "Expand ") + card.surfaceInfo.nombre
                Accessible.description: "Size and position settings, " + (card.expanded ? "expanded" : "collapsed")
                onClicked: card.expansionRequested(!card.expanded)
                contentItem: RowLayout {
                    spacing: 10
                    IconGlyph {
                        text: String.fromCodePoint(0xF0142)
                        font.pixelSize: 16
                        color: Theme.muted
                        rotation: card.expanded ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: 140 } }
                    }
                    IconGlyph {
                        visible: !card.icon.imagen
                        text: String.fromCodePoint(card.icon.glifo || 0xF06A5)
                        color: Theme.blue
                        font.pixelSize: 18
                    }
                    Image {
                        visible: !!card.icon.imagen
                        source: card.icon.imagen || ""
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        fillMode: Image.PreserveAspectFit
                    }
                    IslandLabel {
                        Layout.fillWidth: true
                        text: card.surfaceInfo.nombre
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
            IslandLabel { text: "Separate popup"; color: Theme.muted; font.pixelSize: 11 }
            K4.Interruptor {
                objectName: "popup-separate-" + card.surfaceInfo.id
                marcado: Settings.independentIslandFor(card.surface)
                Accessible.name: card.surfaceInfo.nombre + ": open as a separate popup"
                onAlternado: Settings.setIndependentIsland(card.surfaceInfo.id, !marcado)
            }
        }

        Loader {
            id: details
            Layout.fillWidth: true
            Layout.preferredHeight: active && item ? item.implicitHeight : 0
            visible: active
            active: false
            sourceComponent: Component {
                FocusScope {
                    readonly property bool containsFocus: activeFocus
                    implicitHeight: editor.implicitHeight
                    ColumnLayout {
                        id: editor
                        width: parent.width
                        spacing: 12

                        IslandLabel {
                            Layout.fillWidth: true
                            text: Settings.independentIslandFor(card.surface)
                                ? "Opens alongside other popups. Occupied positions fall back to a free corner."
                                : "Opens in the main island, replacing its current view."
                            color: Theme.muted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.track }
                        RowLayout {
                            Layout.fillWidth: true
                            IslandLabel { text: "Size"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                            K4.ActionButton {
                                text: "Reset size"
                                enabled: card.customSize
                                onClicked: Settings.resetPopupSize(card.surfaceInfo.id)
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: width >= 540 ? 2 : 1
                            columnSpacing: 20
                            rowSpacing: 8
                            Repeater {
                                model: ["width", "height"]
                                PopupDimensionControl {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    surface: card.surface
                                    dimension: modelData
                                }
                            }
                        }
                        IslandLabel {
                            Layout.fillWidth: true
                            text: "Auto follows the content. Custom sizes are fitted to the available screen."
                            color: Theme.muted
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.track }
                        PopupPositionEditor { Layout.fillWidth: true; surface: card.surface }
                        RowLayout {
                            visible: card.surfaceInfo.ipc.length > 0
                            Layout.fillWidth: true
                            K4.ActionButton {
                                id: copyButton
                                property bool copied: false
                                text: copied ? "Command copied" : "Copy opening command"
                                onClicked: {
                                    K4.Sistema.copiar("quickshell ipc -p \"" + K4.Paths.enRaiz("shell.qml")
                                        + "\" call " + card.surfaceInfo.ipc)
                                    copied = true
                                    copyTimer.restart()
                                }
                                Timer { id: copyTimer; interval: 3000; onTriggered: copyButton.copied = false }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
