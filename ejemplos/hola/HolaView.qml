//  The view exists only while the plugin occupies the island.
//
//  An external plugin imports only QtQuick and K4. K4.Tema supplies the
//  palette, and K4.Etiqueta supplies text with the bar's defaults.

import QtQuick
import K4 as K4

Item {
    required property var plugin

    Rectangle {
        anchors.centerIn: parent
        width: 320
        height: 64
        radius: 14
        color: K4.Tema.superficie

        Column {
            anchors.centerIn: parent
            spacing: 2

            K4.Etiqueta {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !plugin.saludar ? "Counting visits"
                    : plugin.aQuien
                      ? `Hello, ${plugin.aQuien}`
                      : "Hello from an external plugin"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            K4.Etiqueta {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `Opened ${plugin.visitas} times`
                color: K4.Tema.apagado
                font.pixelSize: 11
            }
        }
    }
}
