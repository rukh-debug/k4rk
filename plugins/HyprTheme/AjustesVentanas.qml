//  Borders, gaps and rounding, from Hyprland's settings.
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
    spacing: 6

    IslandSlider {
        Layout.fillWidth: true
        label: "Gap between windows"
        suffix: " px"
        from: 0; to: 30; step: 1
        value: raiz.motor.gapsIn
        onMoved: function (v) { raiz.motor.gapsIn = v; raiz.tocado() }
    }

    IslandSlider {
        Layout.fillWidth: true
        label: "Gap from the screen edge"
        suffix: " px"
        from: 0; to: 60; step: 1
        value: raiz.motor.gapsOut
        onMoved: function (v) { raiz.motor.gapsOut = v; raiz.tocado() }
    }

    IslandSlider {
        Layout.fillWidth: true
        label: "Border thickness"
        suffix: " px"
        from: 0; to: 10; step: 1
        value: raiz.motor.borderSize
        onMoved: function (v) { raiz.motor.borderSize = v; raiz.tocado() }
    }

    IslandSlider {
        Layout.fillWidth: true
        label: "Corner rounding"
        suffix: " px"
        from: 0; to: 30; step: 1
        value: raiz.motor.rounding
        onMoved: function (v) { raiz.motor.rounding = v; raiz.tocado() }
    }

    Item { Layout.fillHeight: true }
}
