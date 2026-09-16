pragma Singleton

// NetworkManager owns radio and connection state. Scanning follows the open list.
import QtQuick
import Quickshell
import Quickshell.Networking
import "../core"

Singleton {
    id: wifi

    // Keep the writable compatibility property synchronized in both directions.
    property bool activada: Networking.wifiEnabled
    onActivadaChanged: if (Networking.wifiEnabled !== activada)
        Networking.wifiEnabled = activada
    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            wifi.activada = Networking.wifiEnabled
            if (!wifi.activada) wifi.cancelPsk()
        }
    }

    readonly property var device: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i)
            if (devices[i].type === DeviceType.Wifi) return devices[i]
        return null
    }
    readonly property var networks: {
        if (!device) return []
        return device.networks.values.slice().sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.known !== b.known) return a.known ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
    }
    readonly property string name: {
        if (!device) return "No adapter"
        if (!activada) return "Off"
        if (operationTarget && operationTarget.stateChanging) return status(operationTarget)
        for (let i = 0; i < networks.length; ++i)
            if (networks[i].connected) return networks[i].name || "Hidden network"
        return "Not connected"
    }
    property bool scanning: false
    property var pskTarget: null
    property string pskInput: ""
    property string notice: ""
    property var operationTarget: null
    property bool connectionFailed: false

    function strengthIcon(network) {
        const strength = network ? network.signalStrength || 0 : 0
        if (strength >= 0.75) return Theme.ico.wifi4
        if (strength >= 0.5) return Theme.ico.wifi3
        if (strength >= 0.25) return Theme.ico.wifi2
        if (strength > 0) return Theme.ico.wifi1
        return Theme.ico.wifi0
    }
    function isSecure(network) {
        return !!network && network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe
    }
    function needsPsk(network) {
        return !!network && (network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae)
    }
    function status(network) {
        if (!network) return ""
        if (network.stateChanging)
            return network.connected ? "Disconnecting…" : "Connecting…"
        if (network.connected) return "Connected"
        if (connectionFailed && operationTarget === network) return "Connection failed"
        if (network.known) return "Saved"
        return isSecure(network) ? "Secured" : "Open network"
    }
    function activate(network) {
        if (!device || !activada || !network || network.stateChanging) return
        cancelPsk()
        notice = ""
        connectionFailed = false
        operationTarget = network
        if (network.connected) { network.disconnect(); return }
        if (network.known || !isSecure(network)) { network.connect(); return }
        if (!needsPsk(network)) {
            notice = "This network needs a NetworkManager profile. Configure it in your network settings, then retry here."
            connectionFailed = true
            return
        }
        pskInput = ""
        pskTarget = network
    }
    function submitPsk() {
        if (!pskTarget || pskTarget.stateChanging || pskInput.length === 0) return
        operationTarget = pskTarget
        connectionFailed = false
        notice = ""
        pskTarget.connectWithPsk(pskInput)
        pskInput = ""
    }
    function retry() {
        if (operationTarget && !operationTarget.connected) activate(operationTarget)
    }
    function cancelPsk() { pskInput = ""; pskTarget = null }

    Connections {
        target: wifi.operationTarget
        function onConnectedChanged() {
            if (wifi.operationTarget && wifi.operationTarget.connected) {
                wifi.notice = ""
                wifi.connectionFailed = false
                wifi.cancelPsk()
            }
        }
        function onConnectionFailed(reason) {
            wifi.connectionFailed = true
            const name = wifi.operationTarget ? wifi.operationTarget.name || "Hidden network" : "Network"
            const credentials = reason === ConnectionFailReason.NoSecrets
                || reason === ConnectionFailReason.WifiAuthTimeout
            wifi.notice = name + ": " + (credentials
                ? "Authentication failed. Check the password and try again."
                : reason === ConnectionFailReason.WifiNetworkLost
                ? "The network is no longer in range. Try again when it is available."
                : "Could not connect. Try again or check the network configuration.")
            if (credentials && wifi.needsPsk(wifi.operationTarget)
                    && wifi.scanning && wifi.activada)
                wifi.pskTarget = wifi.operationTarget
        }
    }
    Binding {
        target: wifi.device
        property: "scannerEnabled"
        value: wifi.scanning && wifi.activada
        when: wifi.device !== null
    }
}
