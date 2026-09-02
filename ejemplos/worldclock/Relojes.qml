//  The card's content: instantiated by the centre while its controls
//  tab is open, in this plugin's own context. The room is what the
//  card's `alto` reserved — fill it, don't fight it.

import QtQuick
import QtQuick.Layouts
import K4 as K4

Rectangle {
    radius: 12
    color: K4.Tema.superficie

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        K4.Glifo {
            text: String.fromCharCode(0xF0150)   // md-clock_outline
            font.pixelSize: 16
            color: K4.Tema.apagado
        }

        Repeater {
            model: [
                { ciudad: "Local", hora: Qt.formatDateTime(K4.Reloj.ahora, "HH:mm") },
                { ciudad: "UTC", hora: K4.Reloj.ahora.toISOString().slice(11, 16) }
            ]

            delegate: ColumnLayout {
                required property var modelData
                spacing: 2

                K4.Etiqueta {
                    text: modelData.ciudad
                    color: K4.Tema.apagado
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                K4.Etiqueta {
                    text: modelData.hora
                    color: K4.Tema.tinta
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }
        }

        Item { Layout.fillWidth: true }

        K4.Etiqueta {
            text: "from the K4.Card example"
            color: K4.Tema.apagado
            font.pixelSize: 9
        }
    }
}
