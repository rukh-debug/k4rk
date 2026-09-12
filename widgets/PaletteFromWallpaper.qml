// Lets the wallpaper drive the theme accent through the supplied theme engine.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Rectangle {
    id: palette

    readonly property bool available: WallpaperPalette.source.length > 0

    Layout.fillWidth: true
    Layout.preferredHeight: 46
    implicitHeight: 46
    radius: 10
    color: Theme.islandBg

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
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
}
