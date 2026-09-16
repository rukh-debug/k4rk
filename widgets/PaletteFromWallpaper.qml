// Palette settings share the same rows, switches and wrapping choices as Settings.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../core"
import "../services"

Rectangle {
    id: palette
    readonly property bool available: WallpaperPalette.source.length > 0
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 24
    Layout.preferredHeight: implicitHeight
    radius: 10
    color: Theme.surface
    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                IslandLabel { Layout.fillWidth: true; text: "Use colors from the wallpaper"; wrapMode: Text.WordWrap }
                IslandLabel {
                    Layout.fillWidth: true
                    text: !palette.available ? "Choose a wallpaper to sample its colors."
                        : Settings.wallpaperPalette ? "The bar's palette follows your wallpaper." : "Palette sampling is off."
                    color: Theme.muted
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
            K4.Interruptor {
                marcado: Settings.wallpaperPalette
                Accessible.name: "Use colors from the wallpaper"
                onAlternado: Settings.poner("wallpaperPalette", !marcado)
            }
        }
        Row {
            visible: Settings.wallpaperPalette && palette.available
            spacing: 8
            Repeater {
                model: [WallpaperPalette.accentFrom, WallpaperPalette.accentTo, WallpaperPalette.inactive]
                delegate: Rectangle {
                    required property var modelData
                    width: 20; height: 20; radius: 10
                    color: modelData
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                }
            }
        }
        IslandLabel {
            visible: Settings.wallpaperPalette && palette.available && !WallpaperPalette.matugenOk
            Layout.fillWidth: true
            text: "Using sampled colors. Install matugen to choose a palette scheme."
            color: Theme.muted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        ColumnLayout {
            visible: Settings.wallpaperPalette && palette.available && WallpaperPalette.matugenOk
            Layout.fillWidth: true
            spacing: 8
            IslandLabel { text: "Palette scheme"; color: Theme.muted; font.pixelSize: 11 }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: WallpaperPalette.schemes
                    delegate: K4.ActionButton {
                        required property var modelData
                        text: modelData.nombre
                        selected: WallpaperPalette.activeScheme === modelData.id
                        Accessible.name: "Palette scheme: " + text
                        onClicked: WallpaperPalette.scheme = modelData.id
                    }
                }
            }
        }
    }
}
