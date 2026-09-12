//  The mode as an island: what the keys are, one chip each.
//
//  Everything shown here comes out of the parsed name — the title, the
//  keys with their labels, the trailing note — so the same view reads a
//  screenshot menu and a resize grid without knowing either. A name the
//  parser could not take is shown whole, as plain text: the island is
//  the announcement, and the announcement is the name.
//
//  A chip with a command answers the pointer: press it and it runs what
//  the key would have run, then the submap resets and the island folds.
//  One press, one action — same as the keyboard, no holding, no
//  repetition. Chips without a command are guides only: no cursor, no
//  light, they just say what the key does.

import QtQuick
import QtQuick.Layouts
import "../../core"

FadeIn {
    id: vista

    required property var plugin

    // ── a name nobody formatted ──────────────────────────────
    //
    //  Still an announcement: the glyph says "mode", the text is the
    //  raw id, elided if it has to be.
    ColumnLayout {
        visible: !vista.plugin.parseo
        anchors.centerIn: parent
        spacing: 6

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            IconGlyph {
                text: "\uF030E"
                color: Theme.blue
                font.pixelSize: 13
            }

            IslandLabel {
                Layout.maximumWidth: vista.width - 70
                text: vista.plugin.contenido
                color: Theme.muted
                elide: Text.ElideRight
            }
        }
    }

    // ── the parsed mode ──────────────────────────────────────
    ColumnLayout {
        visible: vista.plugin.parseo
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        //  The title row: what mode this is, and the way out.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: "\uF030E"
                color: Theme.blue
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                Layout.fillWidth: true
                text: vista.plugin.parseo ? vista.plugin.parseo.titulo : ""
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            //  The esc chip: the pointer's courtesy, same door the
            //  keyboard has.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 34
                implicitHeight: 20
                radius: 6
                color: ratonEsc.containsMouse ? Theme.surfaceHi : Theme.surface
                border.width: 1
                border.color: ratonEsc.containsMouse ? Theme.blue : Theme.track

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    anchors.centerIn: parent
                    text: "esc"
                    color: ratonEsc.containsMouse ? Theme.blue : Theme.muted
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: ratonEsc
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.salir()
                }
            }

            IslandLabel {
                Layout.alignment: Qt.AlignVCenter
                text: "exit"
                color: Theme.dim
                font.pixelSize: 9
            }
        }

        //  The keys. A chip is a set of key squares over one label —
        //  (h j k l) is four squares sharing "left" — and the Flow
        //  wraps at the same width the island measured for.
        Flow {
            Layout.fillWidth: true
            spacing: 18

            Repeater {
                model: vista.plugin.parseo
                        ? vista.plugin.parseo.entradas : []

                delegate: Item {
                    id: chip

                    required property var modelData
                    required property int index

                    readonly property bool accionable:
                        String(chip.modelData.comando || "").length > 0
                    readonly property bool encima:
                        chip.accionable && ratonChip.containsMouse
                    readonly property bool pulsado:
                        chip.accionable && ratonChip.pressed

                    width: cuerpo.implicitWidth
                    height: cuerpo.implicitHeight
                    opacity: 0
                    scale: chip.pulsado ? 0.94 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 110
                            easing.type: Easing.OutCubic
                        }
                    }

                    //  Arrival: each chip a beat after the last, so a
                    //  mode opens as a row of keys and not as one slab.
                    //  The pop lives on the inner column, away from the
                    //  scale the press state owns.
                    Column {
                        id: cuerpo

                        spacing: 4
                        scale: 1

                        Component.onCompleted: aparicion.start()

                        SequentialAnimation {
                            id: aparicion
                            PauseAnimation { duration: 35 * chip.index }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: chip
                                    property: "opacity"
                                    to: 1
                                    duration: 160
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: cuerpo
                                    property: "scale"
                                    from: 0.9
                                    to: 1
                                    duration: 220
                                    easing.type: Easing.OutBack
                                }
                            }
                        }

                        Row {
                            spacing: 3

                            Repeater {
                                model: chip.modelData.teclas

                                delegate: Item {
                                    id: llave

                                    required property var modelData

                                    width: 26
                                    height: 28

                                    //  The cap's side, under and behind:
                                    //  a key has depth, and two pixels
                                    //  of it say so without a shadow.
                                    Rectangle {
                                        y: 2
                                        width: parent.width
                                        height: 26
                                        radius: 7
                                        color: Theme.track
                                    }

                                    Rectangle {
                                        id: tapa

                                        width: parent.width
                                        height: 26
                                        radius: 7
                                        color: chip.pulsado ? Theme.blue
                                                : chip.encima ? Theme.surfaceHi
                                                : Theme.surface
                                        border.width: 1
                                        border.color: chip.encima || chip.pulsado
                                                ? Theme.blue : Theme.track

                                        Behavior on color {
                                            ColorAnimation { duration: 120 }
                                        }
                                        Behavior on border.color {
                                            ColorAnimation { duration: 120 }
                                        }

                                        IslandLabel {
                                            anchors.centerIn: parent
                                            text: /^[a-z0-9]$/i.test(
                                                      String(llave.modelData))
                                                  ? String(llave.modelData).toUpperCase()
                                                  : String(llave.modelData)
                                            color: chip.pulsado ? Theme.ink
                                                    : chip.encima ? Theme.blue
                                                    : chip.accionable ? Theme.ink
                                                    : Theme.muted
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }

                        IslandLabel {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: chip.modelData.etiqueta
                            color: chip.pulsado ? Theme.ink
                                    : chip.encima ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            font.weight: chip.encima
                                    ? Font.DemiBold : Font.Normal
                        }
                    }

                    MouseArea {
                        id: ratonChip
                        anchors.fill: parent
                        enabled: chip.accionable
                        hoverEnabled: true
                        cursorShape: chip.accionable
                                      ? Qt.PointingHandCursor
                                      : Qt.ArrowCursor
                        onClicked: vista.plugin.ejecutar(
                                       chip.modelData.comando)
                    }
                }
            }
        }

        //  The trailing note — "SHIFT for bigger steps" and its kind.
        IslandLabel {
            visible: vista.plugin.parseo
                     && vista.plugin.parseo.nota.length > 0
            Layout.fillWidth: true
            text: vista.plugin.parseo ? vista.plugin.parseo.nota : ""
            color: Theme.dim
            font.pixelSize: 9
            elide: Text.ElideRight
        }
    }
}
