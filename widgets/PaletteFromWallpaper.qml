// Lets the wallpaper drive the theme accent through the supplied theme engine.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Rectangle {
    id: palette

    readonly property bool available: WallpaperPalette.source.length > 0

    //  The style chips need a wallpaper to work on, sampling on, and
    //  matugen to run the schemes; without the tool the card keeps
    //  its classic single-row shape.
    readonly property bool estilos: Settings.wallpaperPalette
                                    && palette.available
                                    && WallpaperPalette.matugenOk

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    implicitHeight: columna.implicitHeight
    radius: 10
    color: Theme.islandBg

    ColumnLayout {
        id: columna
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                IslandLabel {
                    text: "Use colours from the wallpaper"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    text: Settings.wallpaperPalette && palette.available
                        ? "Choosing another thumbnail updates the bar colours"
                        : (palette.available ? "Palette sampling is turned off"
                                             : "Choose a wallpaper thumbnail to sample it")
                    color: Theme.dim
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Repeater {
                model: Settings.wallpaperPalette && palette.available
                    ? [WallpaperPalette.accentFrom, WallpaperPalette.accentTo,
                       WallpaperPalette.inactive] : []

                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    radius: 9
                    color: modelData
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }
            }

            IslandSwitch {
                checked: Settings.wallpaperPalette
                Layout.alignment: Qt.AlignVCenter
                onToggled: {
                    Settings.wallpaperPalette = !Settings.wallpaperPalette
                    Settings.guardar()
                }
            }
        }

        //  ── the style of the palette ──────────────────
        //
        //  The same chip language as the transition row in the grid:
        //  press one and the swatches above answer in place.
        ColumnLayout {
            visible: palette.estilos
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            spacing: 6

            IslandLabel {
                text: "Scheme"
                color: Theme.dim
                font.pixelSize: 10
                Layout.leftMargin: 2
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: WallpaperPalette.schemes

                    delegate: Rectangle {
                        id: chipScheme
                        required property var modelData
                        readonly property bool puesta:
                            WallpaperPalette.activeScheme === modelData.id

                        width: textoScheme.implicitWidth + 20
                        height: 22
                        radius: 11
                        color: puesta ? Theme.blue
                            : (ratonScheme.containsMouse ? Theme.surfaceHi
                                                         : Theme.track)

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: textoScheme
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: chipScheme.modelData.nombre
                            color: chipScheme.puesta ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: ratonScheme
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperPalette.scheme =
                                chipScheme.modelData.id
                        }
                    }
                }
            }
        }
    }
}
