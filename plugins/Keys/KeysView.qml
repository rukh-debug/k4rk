//  The keyboard shortcuts cheat-sheet.
//
//  Each combination paints its keys in loose capsules, which reads
//  far better than «SUPER + CONTROL + SHIFT + Right» run together,
//  and the list is grouped by the same sections you have in your
//  config.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // Without this one must click before typing: the island's root
    // keeps focus and the surface takes a moment to receive it.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        // ── header ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF030C)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: entrada
                cursorDelegate: IslandCursor {}
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                text: view.plugin.query
                onTextEdited: view.plugin.query = text

                color: Theme.ink
                font.pixelSize: 15
                font.family: Theme.uiFont
                selectByMouse: true
                selectionColor: Theme.blue
                cursorVisible: true
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: "Search shortcut, key or action…"
                    color: Theme.dim
                    font.pixelSize: 15
                }
            }

            IslandLabel {
                text: view.plugin.count + " of " + Atajos.lista.length
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── the list ───────────────────────────────────────────────
        ListView {
            //  The house scrollbar: shows only if there is more than
            //  fits.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 1
            model: view.plugin.lista
            boundsBehavior: Flickable.StopAtBounds

            delegate: Column {
                id: fila
                required property var modelData
                required property int index

                // the section title only when it changes, not on every
                // row
                readonly property bool abreSeccion: index === 0
                    || view.plugin.lista[index - 1].seccion !== modelData.seccion

                // What the shortcut does: the phrase carries «%1» where the
                // detail goes — a command, a mode, a direction.
                readonly property string haceTexto: modelData.detalle
                    ? modelData.hace.replace("%1", modelData.detalle)
                    : modelData.hace

                width: ListView.view.width
                spacing: 0

                IslandLabel {
                    visible: fila.abreSeccion
                    height: visible ? 22 : 0
                    verticalAlignment: Text.AlignBottom
                    leftPadding: 4
                    bottomPadding: 3
                    text: fila.modelData.seccion
                    color: Theme.dim
                    font.pixelSize: 9
                    font.capitalization: Font.AllUppercase
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 8
                    color: filaRaton.containsMouse ? Theme.surface : "transparent"

                    Behavior on color { ColorAnimation { duration: 110 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 10
                        spacing: 10

                        // ── the keys, one by one
                        RowLayout {
                            spacing: 3
                            // Without this it takes all the width: a
                            // layout inside another assumes it wants
                            // to grow, and the action ended up pushed
                            // to the right edge.
                            Layout.fillWidth: false
                            Layout.preferredWidth: 250
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: Atajos.teclas(fila.modelData.combo)

                                delegate: Rectangle {
                                    required property var modelData

                                    Layout.preferredWidth: capsula.implicitWidth + 12
                                    Layout.preferredHeight: 18
                                    radius: 5
                                    color: Theme.surfaceHi
                                    border.width: 1
                                    border.color: "#1affffff"

                                    IslandLabel {
                                        id: capsula
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        IslandLabel {
                            text: fila.haceTexto
                            color: Theme.ink
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: filaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }

        IslandLabel {
            Layout.fillWidth: true
            visible: view.plugin.count === 0
            text: Atajos.cargado
                ? "No shortcut matches" : "Reading the configuration…"
            color: Theme.muted
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
