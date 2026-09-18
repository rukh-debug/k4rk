import QtQuick
import K4 as K4

K4.Aparicion {
    id: view
    required property var plugin
    K4.Etiqueta {
        x: 20; y: 18
        text: "System"; font.pixelSize: 15; font.weight: Font.DemiBold
    }
    K4.Boton {
        anchors.right: parent.right; anchors.rightMargin: 16; y: 12
        glifo: String.fromCodePoint(0xF0156)
        Accessible.name: "Close system monitor"
        onPulsado: view.plugin.close()
    }
    Loader {
        anchors.fill: parent
        anchors.topMargin: 56; anchors.bottomMargin: 20
        anchors.leftMargin: 20; anchors.rightMargin: 20
        sourceComponent: K4.SystemMonitor.view
    }
}
