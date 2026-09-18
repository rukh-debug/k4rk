//  Indicators contributed by plugins through K4.Pildora.
//
//  It rides in the three pill views, treated like the tray: at rest it
//  is look-only — by the time the pointer gets close the island has
//  already switched to clock or player — and those are the ones that
//  take clicks. Without `interactive` there is no mouse, so it never
//  swallows a click the resting view could not answer.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: view
    spacing: 8

    property bool interactive: false

    Repeater {
        model: Indicadores.reparto.muestra
        delegate: Item {
            id: chip
            required property var modelData
            readonly property bool fixedSlots: Indicadores.hasSlots(modelData)
            objectName: "pill-" + modelData.id
            visible: modelData.visible !== false
            implicitWidth: Indicadores.anchoDe(modelData)
            implicitHeight: contenido.implicitHeight + 4

            Row {
                id: contenido
                anchors.centerIn: parent
                spacing: 4

                IconGlyph {
                    objectName: chip.objectName + "-icon"
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(modelData.glifo)
                    color: modelData.color || Theme.muted
                    font: Indicadores.iconFont
                    width: Indicadores.iconWidth(modelData)
                }
                //  Capped and elided at the end. The service owns the
                //  cap, not this file, because it is the same number it
                //  uses to estimate the reserved space: splitting them
                //  would reserve room for text that never paints.
                //
                //  It also decides how many indicators fit; here we only
                //  paint the ones it sends. Text stays bright white while
                //  the glyph keeps the semantic color.
                IslandLabel {
                    visible: !chip.fixedSlots
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.texto
                    color: Theme.ink
                    font: Indicadores.textFont
                    elide: Text.ElideRight
                    width: Indicadores.textWidth(text)
                }
                Row {
                    visible: chip.fixedSlots
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Indicadores.slotGap
                    Repeater {
                        model: chip.fixedSlots ? chip.modelData.slots : []
                        delegate: Row {
                            required property var modelData
                            required property int index
                            IslandLabel {
                                objectName: chip.objectName + "-prefix-" + index
                                text: modelData.prefix || ""
                                font: Indicadores.numericFont
                                width: Indicadores.prefixWidth(modelData)
                            }
                            IslandLabel {
                                objectName: chip.objectName + "-value-" + index
                                text: modelData.text
                                font: Indicadores.numericFont
                                width: Indicadores.slotWidth(modelData)
                                horizontalAlignment: modelData.prefix ? Text.AlignLeft : Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: view.interactive
                visible: view.interactive
                cursorShape: Qt.PointingHandCursor
                onClicked: Indicadores.invocado(modelData.id)
            }
        }
    }

    //  Whatever does not fit goes into a capsule.
    //
    //  It takes no clicks: it would lead nowhere concrete — there are
    //  several — and the resting pill ignores the mouse anyway. It is
    //  there so the row never lies when it runs short.
    Rectangle {
        visible: Indicadores.reparto.ocultos > 0
        Layout.preferredWidth: Indicadores.anchoResumen
        Layout.preferredHeight: 18
        Layout.alignment: Qt.AlignVCenter
        radius: height / 2
        color: Theme.surface

        IslandLabel {
            anchors.centerIn: parent
            text: "+" + Indicadores.reparto.ocultos
            color: Theme.ink
            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }
}
