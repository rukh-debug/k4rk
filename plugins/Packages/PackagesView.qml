//  The confirm page for one package: what it is, where it comes from,
//  what is already true about it — and the buttons that act, which run
//  in the island's terminal session and say how it went.
//
//  No blind installs: a row chosen in the launcher lands here first.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: vista

    required property var plugin

    readonly property var p: plugin ? plugin.paquete : null

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 18
        anchors.bottomMargin: 18
        spacing: 14

        // ── what package this is ────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            IconGlyph {
                text: String.fromCodePoint(vista.p && vista.p.installed
                                           ? 0xF05E0 : 0xF03D7)
                color: vista.p && vista.p.installed ? Theme.green : Theme.ink
                font.pixelSize: 24
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    IslandLabel {
                        text: vista.p ? vista.p.name : ""
                        textFormat: Text.PlainText
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        visible: !!vista.p
                        Layout.preferredWidth: repoTag.implicitWidth + 12
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        radius: 8
                        color: vista.p && vista.p.repo === "aur"
                            ? "#3a2a12" : Theme.surfaceHi

                        IslandLabel {
                            id: repoTag
                            anchors.centerIn: parent
                            text: vista.p ? vista.p.repo : ""
                            color: vista.p && vista.p.repo === "aur"
                                ? "#ff9f0a" : Theme.muted
                            font.pixelSize: 9
                        }
                    }
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: vista.p
                        ? (vista.p.installed ? "Installed · " : "")
                          + vista.p.version : ""
                    textFormat: Text.PlainText
                    color: vista.p && vista.p.installed
                        ? Theme.green : Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        // ── what it says about itself ───────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Theme.surface

            IslandLabel {
                anchors.fill: parent
                anchors.margins: 14
                text: vista.p ? vista.p.description : ""
                textFormat: Text.PlainText
                color: Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        // ── what can be done about it ──────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            //  Leave, touching nothing.
            Rectangle {
                Layout.preferredWidth: cerrarTxt.implicitWidth + 26
                Layout.preferredHeight: 34
                radius: 17
                color: cerrarRaton.containsMouse ? Theme.surfaceHi
                                                 : Theme.surface

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: cerrarTxt
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.muted
                    font.pixelSize: 12
                }

                MouseArea {
                    id: cerrarRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.cerrar()
                }
            }

            Item { Layout.fillWidth: true }

            //  Remove, for what is already here. Red, and apart: the
            //  destructive one never sits next to the usual door.
            Rectangle {
                visible: vista.p && vista.p.installed === true
                Layout.preferredWidth: quitarTxt.implicitWidth + 26
                Layout.preferredHeight: 34
                radius: 17
                color: quitarRaton.containsMouse ? "#3a1518" : "#2a0f12"
                border.width: 1
                border.color: Theme.red

                RowLayout {
                    id: quitarTxt
                    anchors.centerIn: parent
                    spacing: 7

                    IconGlyph {
                        text: String.fromCodePoint(0xF09E7)
                        color: Theme.red
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        text: "Remove"
                        color: Theme.red
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: quitarRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.desinstalar()
                }
            }

            //  Install, or update — same command, same door.
            Rectangle {
                Layout.preferredWidth: ponerTxt.implicitWidth + 26
                Layout.preferredHeight: 34
                radius: 17
                color: ponerRaton.containsMouse ? "#15301c" : "#1a2415"
                border.width: 1
                border.color: Theme.green

                RowLayout {
                    id: ponerTxt
                    anchors.centerIn: parent
                    spacing: 7

                    IconGlyph {
                        text: String.fromCodePoint(0xF03D4)
                        color: Theme.green
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        text: vista.p && vista.p.installed
                            ? "Update" : "Install"
                        color: Theme.green
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: ponerRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.instalar()
                }
            }
        }
    }
}
