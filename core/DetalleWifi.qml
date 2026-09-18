// Network list and an explicitly labelled credential editor inside the same surface.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../core"
import "../services"

Item {
    id: detail
    required property var view
    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: view.plugin.tab === "wifi"

    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 12
            IconGlyph {
                text: Wifi.activada ? Theme.ico.wifi : Theme.ico.wifiOff
                color: Wifi.activada ? Theme.blue : Theme.muted
                font.pixelSize: 18
            }
            IslandLabel {
                Layout.fillWidth: true
                text: !Wifi.device ? "No Wi-Fi adapter" : !Wifi.activada ? "Wi-Fi off" : "Available networks"
                color: Theme.muted
                font.pixelSize: 12
            }
            K4.Interruptor {
                enabled: !!Wifi.device
                marcado: Wifi.activada
                Accessible.name: "Enable Wi-Fi"
                onAlternado: Wifi.activada = !Wifi.activada
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface }
        K4.Rodillo {
            id: networks
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                width: parent.width
                spacing: 6
                Repeater {
                    model: Wifi.activada ? Wifi.networks : []
                    delegate: ConnectionRow {
                        required property var modelData
                        width: parent.width
                        glyph: Wifi.strengthIcon(modelData)
                        title: modelData.name || "Hidden network"
                        subtitle: Wifi.status(modelData)
                        active: modelData.connected
                        busy: modelData.stateChanging
                        failed: Wifi.connectionFailed && Wifi.operationTarget === modelData
                        secure: Wifi.isSecure(modelData) && !modelData.known
                        forgettable: modelData.known
                        onActivated: Wifi.activate(modelData)
                        onForgotten: modelData.forget()
                    }
                }
                IslandLabel {
                    width: parent.width
                    topPadding: 32
                    visible: !Wifi.activada || Wifi.networks.length === 0
                    text: !Wifi.device ? "No Wi-Fi adapter is available."
                        : !Wifi.activada ? "Turn on Wi-Fi to see nearby networks."
                        : "No networks found yet. Keep this page open to scan."
                    color: Theme.muted
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
        RowLayout {
            visible: Wifi.notice.length > 0
            Layout.fillWidth: true
            spacing: 8
            IslandLabel {
                Layout.fillWidth: true
                text: Wifi.notice
                color: Theme.red
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            K4.ActionButton {
                visible: !Wifi.pskTarget && !!Wifi.operationTarget
                text: "Retry"
                enabled: !!Wifi.device && Wifi.activada && !!Wifi.operationTarget
                    && !Wifi.operationTarget.stateChanging
                onClicked: Wifi.retry()
            }
        }
        ColumnLayout {
            visible: Wifi.pskTarget !== null
            Layout.fillWidth: true
            spacing: 8
            IslandLabel {
                Layout.fillWidth: true
                text: Wifi.pskTarget ? "Password for " + (Wifi.pskTarget.name || "hidden network") : ""
                font.pixelSize: 11
                color: Theme.muted
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                K4.TextField {
                    id: password
                    Layout.fillWidth: true
                    enabled: !!Wifi.pskTarget && !Wifi.pskTarget.stateChanging
                    Accessible.name: "Network password"
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    text: Wifi.pskInput
                    onTextEdited: Wifi.pskInput = text
                    onAccepted: Wifi.submitPsk()
                    Keys.onEscapePressed: function (event) {
                        Wifi.cancelPsk()
                        detail.view.focusBack()
                        event.accepted = true
                    }
                }
                K4.ActionButton {
                    text: Wifi.pskTarget && Wifi.pskTarget.stateChanging ? "Connecting…" : "Connect"
                    enabled: Wifi.pskInput.length > 0 && !!Wifi.pskTarget && !Wifi.pskTarget.stateChanging
                    onClicked: Wifi.submitPsk()
                }
                K4.Boton {
                    glifo: Theme.ico.close
                    tamano: 16
                    Accessible.name: "Cancel password entry"
                    onPulsado: { Wifi.cancelPsk(); detail.view.focusBack() }
                }
            }
        }
    }
    Connections {
        target: Wifi
        function onPskTargetChanged() {
            if (Wifi.pskTarget && detail.visible)
                Qt.callLater(function () { password.forceActiveFocus() })
        }
    }
}
