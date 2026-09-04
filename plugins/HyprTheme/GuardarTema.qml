//  «This is already in your config, or only in this session» — and the
//  save button.
//
//  The Hyprland theme applies at once but does not write itself:
//  until you press, it lives in the session and leaves on restart.
//  That must be said where it is touched, not on another screen, so
//  this bar accompanies every section that writes the Lua.
//
//  Wallpapers do NOT carry it: those save themselves on choosing,
//  and offering a «Save» nobody needs is showing a doubt that does
//  not exist.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

RowLayout {
    id: guardar

    property var motor: null

    readonly property bool puesto: !!guardar.motor && guardar.motor.persistido

    Layout.fillWidth: true
    Layout.preferredHeight: 24
    spacing: 10

    IconGlyph {
        text: guardar.puesto ? Theme.ico.check : Theme.ico.alert
        color: guardar.puesto ? Theme.green : Theme.muted
        font.pixelSize: 12
        renderType: Text.NativeRendering
        Layout.alignment: Qt.AlignVCenter
    }

    IslandLabel {
        text: guardar.puesto
            ? "Saved to config/k4-theme.lua · survives restarts"
            : "Applied to this session only · press Save to keep it"
        color: Theme.muted
        font.pixelSize: 10
        Layout.alignment: Qt.AlignVCenter
    }

    Item { Layout.fillWidth: true }

    Rectangle {
        visible: !!guardar.motor
        Layout.preferredWidth: etiqueta.implicitWidth + 26
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter
        radius: 12
        color: raton.containsMouse ? Theme.blue : Theme.surfaceHi

        Behavior on color { ColorAnimation { duration: 120 } }

        IslandLabel {
            id: etiqueta
            anchors.centerIn: parent
            text: "Save"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: guardar.motor.persist()
        }
    }
}
