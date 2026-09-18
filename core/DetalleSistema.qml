//  The control centre's System tab, sibling of DetalleWifi,
//  DetalleBluetooth and DetalleSonido.
//
//  The body is the same piece the System island shows
//  (core/VistaSistema): arriving from the centre or from the
//  application grid makes no difference. The process list takes
//  whatever height the tab leaves it and scrolls inside it.

import QtQuick
import QtQuick.Layouts
import "../core"

Item {
    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: view.plugin.tab === "system"

    VistaSistema {
        anchors.fill: parent
    }
}
