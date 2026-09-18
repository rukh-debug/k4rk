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
import K4 as K4
import "../core"
import "../services"

Item {
    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: view.plugin.tab === "sound"

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        K4.Rodillo {
            Layout.fillWidth: true
            Layout.fillHeight: true
            AparatosDeSonido { width: parent.width }
        }

        IslandLabel {
            Layout.fillWidth: true
            text: "The mark on the slider is the device's natural level: above it, sound is amplified"
            color: Theme.muted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
}
