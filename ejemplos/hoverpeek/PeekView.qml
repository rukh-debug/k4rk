//  The hover view's content: the full date and the desk you stand on.

import QtQuick
import QtQuick.Layouts
import K4 as K4

ColumnLayout {
    required property var plugin

    spacing: 4

    K4.Etiqueta {
        text: Qt.formatDateTime(K4.Reloj.ahora, "dddd, d MMMM yyyy")
        color: K4.Tema.tinta
        font.pixelSize: 13
        font.weight: Font.DemiBold
        Layout.alignment: Qt.AlignHCenter
    }

    K4.Etiqueta {
        text: "desk " + K4.Escritorios.activo
              + " of " + K4.Escritorios.lista.length
        color: K4.Tema.apagado
        font.pixelSize: 11
        Layout.alignment: Qt.AlignHCenter
    }
}
