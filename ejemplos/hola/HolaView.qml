//  La vista: solo existe mientras el plugin tiene la island.
//
//  Un plugin de fuera importa QtQuick y K4, nada más. La paleta llega por
//  K4.Tema y el texto con los defaults de la barra por K4.Etiqueta.

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
