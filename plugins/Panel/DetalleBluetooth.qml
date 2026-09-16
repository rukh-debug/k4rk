// Bluetooth uses the same list hierarchy and operation states as Wi-Fi.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

IslandTile {
    required property var view
    Layout.fillWidth: true
    Layout.fillHeight: true
    pulsable: false
    visible: view.plugin.tab === "bluetooth"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            IslandLabel {
                Layout.fillWidth: true
                text: !Bt.adapter ? "No Bluetooth adapter"
                    : !Bt.adapter.enabled ? "Bluetooth off" : "Available devices"
                color: Theme.muted
                font.pixelSize: 12
            }
            K4.Interruptor {
                enabled: !!Bt.adapter
                marcado: !!Bt.adapter && Bt.adapter.enabled
                Accessible.name: "Enable Bluetooth"
                onAlternado: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
            }
        }
        K4.Rodillo {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: Bt.adapter && Bt.adapter.enabled ? Bt.devices : []
                    delegate: ConnectionRow {
                        required property var modelData
                        width: parent.width
                        glyph: Bt.deviceIcon(modelData)
                        title: modelData.name || modelData.address
                        subtitle: Bt.deviceStatus(modelData)
                        active: modelData.connected
                        busy: Bt.busy(modelData)
                        failed: Bt.falloEmparejar === modelData.address && !modelData.paired
                        forgettable: modelData.paired || modelData.bonded
                        onActivated: Bt.activate(modelData)
                        onForgotten: modelData.forget()
                    }
                }
                IslandLabel {
                    width: parent.width
                    topPadding: 32
                    visible: !Bt.adapter || !Bt.adapter.enabled || Bt.devices.length === 0
                    text: !Bt.adapter ? "No Bluetooth adapter is available."
                        : !Bt.adapter.enabled ? "Turn on Bluetooth to discover nearby devices."
                        : "No devices found yet. Make sure your device is discoverable."
                    color: Theme.muted
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
        IslandLabel {
            Layout.fillWidth: true
            visible: Bt.notice.length > 0
            text: Bt.notice
            color: Theme.red
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
}
