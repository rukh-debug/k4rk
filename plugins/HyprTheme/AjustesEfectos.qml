//  Blur, opacity and animations, from Hyprland's settings.
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

RowLayout {
    id: raiz

    //  Whoever knows how to write this into Hyprland's config.
    property var motor: null

    //  Any hand tweak stops being «the preset as is».
    function tocado() {
        if (!raiz.motor)
            return
        raiz.motor.dirty = true
        raiz.motor.apply()
    }

    //  `anchors.fill` was from when this lived inside its own panel.
    //  Here the section's column places it, so width is asked and
    //  that is it.
    Layout.fillWidth: true
    spacing: 20

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            IslandLabel { text: "Blur"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IslandSwitch {
                checked: raiz.motor.blur
                onToggled: { raiz.motor.blur = !raiz.motor.blur; raiz.tocado() }
            }
        }

        IslandSlider {
            Layout.fillWidth: true
            enabled: raiz.motor.blur
            opacity: raiz.motor.blur ? 1 : 0.35
            label: "Radius"
            from: 1; to: 20; step: 1
            value: raiz.motor.blurSize
            onMoved: function (v) { raiz.motor.blurSize = v; raiz.tocado() }
        }

        IslandSlider {
            Layout.fillWidth: true
            enabled: raiz.motor.blur
            opacity: raiz.motor.blur ? 1 : 0.35
            label: "Passes"
            from: 1; to: 6; step: 1
            value: raiz.motor.blurPasses
            onMoved: function (v) { raiz.motor.blurPasses = v; raiz.tocado() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10

            IslandLabel { text: "Shadows"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IslandSwitch {
                checked: raiz.motor.shadow
                onToggled: { raiz.motor.shadow = !raiz.motor.shadow; raiz.tocado() }
            }
        }

        Item { Layout.fillHeight: true }
    }

    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.surfaceHi }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        IslandSlider {
            Layout.fillWidth: true
            label: "Active window opacity"
            from: 0.4; to: 1; step: 0.05
            value: raiz.motor.activeOpacity
            onMoved: function (v) { raiz.motor.activeOpacity = v; raiz.tocado() }
        }

        IslandSlider {
            Layout.fillWidth: true
            label: "Inactive windows opacity"
            from: 0.4; to: 1; step: 0.05
            value: raiz.motor.inactiveOpacity
            onMoved: function (v) { raiz.motor.inactiveOpacity = v; raiz.tocado() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10

            IslandLabel { text: "Animations"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IslandSwitch {
                checked: raiz.motor.animEnabled
                onToggled: { raiz.motor.animEnabled = !raiz.motor.animEnabled; raiz.tocado() }
            }
        }

        IslandSlider {
            Layout.fillWidth: true
            enabled: raiz.motor.animEnabled
            opacity: raiz.motor.animEnabled ? 1 : 0.35
            label: "Speed (higher = faster)"
            from: 1; to: 10; step: 1
            value: raiz.motor.animSpeed
            onMoved: function (v) { raiz.motor.animSpeed = v; raiz.tocado() }
        }

        Item { Layout.fillHeight: true }
    }
}
