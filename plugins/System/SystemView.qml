//  The machine's state at a glance: its own header on top, the shared
//  monitor body below (core/VistaSistema, also shown in the control
//  centre's System tab).

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 11
        anchors.bottomMargin: 12
        spacing: 7

        // ── header ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF035B)
                color: Theme.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "System"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Sistema.cpuHilos > 0 ? Sistema.cpuHilos + " threads" : ""
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            // disk does not change in two minutes: it deserves no
            // graph, only a figure
            IslandLabel {
                visible: Sistema.discoTotal > 0
                text: "disk " + Math.round(Sistema.discoUsado) + " / "
                    + Math.round(Sistema.discoTotal) + " GB"
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                visible: Sistema.tempNvme > 0
                text: "nvme " + Sistema.grados(Sistema.tempNvme)
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        VistaSistema {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
