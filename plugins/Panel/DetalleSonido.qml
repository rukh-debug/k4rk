//  The control centre's Sound detail, sibling of DetalleWifi and
//  DetalleBluetooth.
//
//  The sound tile knew how to raise and lower the general volume
//  and nothing else: to choose where sound comes out or look at a
//  mic's gain one had to go to the Sound module, while what sits
//  next to it —network, Bluetooth— opens right here. The list is
//  the same piece the module shows, so arriving by one road or the
//  other makes no difference.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

IslandTile {
    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    pulsable: false
    visible: view.plugin.tab === "sound"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

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
