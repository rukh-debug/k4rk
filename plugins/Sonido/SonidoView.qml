//  The Sound module: the device list with its header and its foot.
//
//  The list itself is `AparatosDeSonido` from `core`, shared with
//  the control centre's detail: one arrives from the launcher the
//  same way one arrives at Wi‑Fi and Bluetooth, and wherever one
//  arrives from it is the same thing.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: vista

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── header ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF057E)   // md-volume_high
                color: Theme.ink
                font.pixelSize: 15
            }

            IslandLabel {
                text: "Sound"
                color: Theme.ink
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            IslandLabel {
                Layout.fillWidth: true
                text: "where it goes out and where it comes in"
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: vista.plugin.close()
            }
        }

        AparatosDeSonido {
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }

        IslandLabel {
            Layout.fillWidth: true
            text: "The mark on the slider is the device's natural level: above it, sound is amplified"
            color: Theme.dim
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }
    }
}
