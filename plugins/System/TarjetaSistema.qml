//  The control centre's System card: the live figures the hot path
//  already computes. Instantiated by the centre while its controls
//  tab is open; the room is what the card's `alto` declared, so this
//  fills it and nothing more. It paints, it does not measure.
//
//  Which meters ride along is the user's call — the toggles live in
//  the plugin's own settings rows — and a click opens the full view.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../services"

Rectangle {
    id: tarjeta

    required property var plugin

    readonly property bool verCpu: plugin && plugin.tarjetaCpu
    readonly property bool verRam: plugin && plugin.tarjetaRam
    readonly property bool verRed: plugin && plugin.tarjetaRed

    radius: 12
    color: K4.Tema.superficie

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 7
        anchors.bottomMargin: 7
        spacing: 16

        // CPU
        ColumnLayout {
            visible: tarjeta.verCpu
            Layout.fillWidth: true
            spacing: 2

            K4.Etiqueta {
                text: "CPU"
                color: K4.Tema.apagado
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
            K4.Etiqueta {
                text: Math.round(Sistema.cpuUso) + "%"
                color: K4.Tema.tinta
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            K4.Medidor {
                valor: Sistema.cpuUso
                maximo: 100
                grosor: 3
                tono: K4.Tema.azul
                Layout.fillWidth: true
            }
        }

        // Memory
        ColumnLayout {
            visible: tarjeta.verRam
            Layout.fillWidth: true
            spacing: 2

            K4.Etiqueta {
                text: "Memory"
                color: K4.Tema.apagado
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
            K4.Etiqueta {
                text: Math.round(Sistema.ramPct) + "%"
                color: K4.Tema.tinta
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            K4.Medidor {
                valor: Sistema.ramPct
                maximo: 100
                grosor: 3
                tono: "#bf5af2"
                Layout.fillWidth: true
            }
        }

        // Network: no meter, it has no ceiling
        ColumnLayout {
            visible: tarjeta.verRed
            Layout.fillWidth: true
            spacing: 2

            K4.Etiqueta {
                text: "Network"
                color: K4.Tema.apagado
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
            K4.Etiqueta {
                text: "↓ " + Sistema.tasa(Sistema.redRx) + "  ↑ " + Sistema.tasa(Sistema.redTx)
                color: K4.Tema.tinta
                font.pixelSize: 11
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (tarjeta.plugin) tarjeta.plugin.abrir()
    }
}
