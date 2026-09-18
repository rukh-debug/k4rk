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
            required property var modelData
            visible: modelData.visible !== false
            implicitWidth: contenido.implicitWidth + 6
            implicitHeight: contenido.implicitHeight + 4

            RowLayout {
                id: contenido
                anchors.fill: parent
                spacing: 4

                IconGlyph {
                    text: String.fromCodePoint(modelData.glifo)
                    color: modelData.color || Theme.muted
                    font.pixelSize: 11
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
                    text: modelData.texto
                    color: Theme.ink
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.maximumWidth: Indicadores.topeTexto
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
