//  The color and the presets, from Hyprland's settings.
//
//  It lived inside `HyprThemeView`, the theme plugin's own screen. It
//  comes out here because that screen is gone: everything it
//  configured now lives in the Settings window, and having two
//  places to touch the same thing was exactly what needed fixing.
//
//  The `motor` is the one knowing how to apply it —the theme plugin,
//  which writes Hyprland's Lua—. It arrives as an object and not as
//  an import: a plugin does not depend on another, and without a
//  motor this is not shown.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: raiz

    //  Whoever knows how to write this into Hyprland's config.
    property var motor: null

    //  The engine can be off — its plugin is a switch like any other. Every
    //  read below goes through this, so a page without its engine stands
    //  still instead of throwing.
    readonly property bool vivo: !!raiz.motor

    //  Any hand tweak stops being «the preset as is».
    function tocado() {
        if (!raiz.motor)
            return
        raiz.motor.dirty = true
        raiz.motor.apply()
    }

    //  No `anchors.fill`: that was from when this lived inside its
    //  own screen. Here the section's column places it, and mixing
    //  anchors with Layout leaves the widget the wrong size.
    Layout.fillWidth: true
    spacing: 14

    //  ── the color: does the wallpaper set it, or do you? ──
    //
    //  It goes first because it is the decision ruling over
    //  everything else on this tab: with the wallpaper ruling,
    //  choosing a preset turns it off.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 46
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
                    text: "The colour comes from the wallpaper"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    text: raiz.vivo
                        ? (raiz.motor.paletaAuto
                           ? "Change the wallpaper and the bar, the borders and the terminal follow"
                           : "Turned off when you pick a preset or a colour by hand")
                        : ""
                    color: Theme.dim
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            //  What came out of the wallpaper, so it shows it is
            //  not magic: the three colors being handed out.
            Repeater {
                model: raiz.vivo && raiz.motor.paletaAuto
                    ? [raiz.motor.accentFrom, raiz.motor.accentTo,
                       raiz.motor.inactive] : []

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
                checked: raiz.vivo && raiz.motor.paletaAuto
                Layout.alignment: Qt.AlignVCenter
                onToggled: {
                    if (!raiz.motor)
                        return
                    raiz.motor.paletaAuto = !raiz.motor.paletaAuto
                    if (raiz.motor.paletaAuto)
                        raiz.motor.sacarPaleta()
                    else
                        Theme.destintar("hyprtheme")
                    raiz.motor.saveState()
                }
            }
        }
    }

    IslandLabel {
        text: "Presets"
        color: Theme.muted
        font.pixelSize: 11
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: raiz.vivo ? raiz.motor.presets : []

            delegate: Rectangle {
                id: presetCard
                required property var modelData
                readonly property bool current: raiz.vivo
                    && raiz.motor.preset === modelData.id
                    && !raiz.motor.dirty

                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 12
                color: presetMouse.containsMouse ? Theme.surfaceHi : Theme.islandBg
                border.width: presetCard.current ? 2 : 0
                border.color: Theme.blue

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    // a sample of the gradient the active border will wear
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        Layout.alignment: Qt.AlignVCenter
                        radius: 8

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: presetCard.modelData.from }
                            GradientStop { position: 1; color: presetCard.modelData.to }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        IslandLabel {
                            text: presetCard.modelData.name
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        IslandLabel {
                            text: presetCard.current ? "applied" : presetCard.modelData.from
                            color: presetCard.current ? Theme.green : Theme.dim
                            font.pixelSize: 10
                        }
                    }

                    IconGlyph {
                        visible: presetCard.current
                        text: Theme.ico.check
                        color: Theme.green
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (raiz.motor)
                        raiz.motor.applyPreset(presetCard.modelData.id)
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    IslandSlider {
        Layout.fillWidth: true
        label: "Border gradient angle"
        suffix: "°"
        from: 0
        to: 360
        step: 5
        value: raiz.vivo ? raiz.motor.angle : 0
        onMoved: function (v) {
            if (!raiz.motor)
                return
            raiz.motor.angle = v
            raiz.tocado()
        }
    }
}
