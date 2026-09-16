pragma Singleton

// BlueZ discovery follows the open list. Initial pairing needs a live agent.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"

Singleton {
    id: bt
    property bool discovering: false
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: {
        if (!adapter) return []
        return adapter.devices.values.slice().sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            return a.name.localeCompare(b.name)
        })
    }
    readonly property string summary: {
        if (!adapter) return "No adapter"
        if (!adapter.enabled) return "Off"
        if (emparejando.length > 0) return "Pairing…"
        if (devices.some(function (device) { return device.state === BluetoothDeviceState.Connecting }))
            return "Connecting…"
        const connected = devices.filter(function (device) { return device.connected })
        return connected.length === 1 ? connected[0].name || connected[0].address
            : connected.length > 1 ? connected.length + " devices connected" : "Not connected"
    }

    function deviceIcon(device) {
        const icon = device && device.icon ? device.icon : ""
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) return Theme.ico.headphones
        if (icon.indexOf("phone") !== -1) return Theme.ico.cellphone
        if (icon.indexOf("mouse") !== -1) return Theme.ico.mouse
        if (icon.indexOf("keyboard") !== -1) return Theme.ico.keyboard
        if (icon.indexOf("speaker") !== -1 || icon.indexOf("audio") !== -1) return Theme.ico.speaker
        if (icon.indexOf("watch") !== -1) return Theme.ico.watch
        if (icon.indexOf("gaming") !== -1 || icon.indexOf("joystick") !== -1) return Theme.ico.gamepad
        if (icon.indexOf("computer") !== -1 || icon.indexOf("laptop") !== -1) return Theme.ico.laptop
        if (icon.indexOf("printer") !== -1) return Theme.ico.printer
        if (icon.indexOf("video") !== -1 || icon.indexOf("tv") !== -1) return Theme.ico.television
        return Theme.ico.devices
    }
    function busy(device) {
        return !!device && (device.pairing || emparejando === device.address
            || device.state === BluetoothDeviceState.Connecting
            || device.state === BluetoothDeviceState.Disconnecting)
    }
    function deviceStatus(device) {
        if (!device) return ""
        if (emparejando === device.address || device.pairing) return "Pairing…"
        if (device.state === BluetoothDeviceState.Connecting) return "Connecting…"
        if (device.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (falloEmparejar === device.address && !device.paired) return "Pairing failed"
        if (device.connected)
            return device.batteryAvailable
                ? "Connected · " + Math.round(device.battery * 100) + "%" : "Connected"
        return device.paired || device.bonded ? "Paired" : "Available"
    }
    function activate(device) {
        if (!adapter || !adapter.enabled || !device || busy(device)) return
        if (device.connected) { device.disconnect(); return }
        if (device.paired || device.bonded) {
            if (!device.trusted) device.trusted = true
            device.connect()
            return
        }
        // Trust before reconnecting so audio profiles remain authorized after pairing.
        emparejar(device)
    }

    property string emparejando: ""
    property string falloEmparejar: ""
    property string notice: ""
    property var _reciente: null

    function emparejar(device) {
        if (!device) return
        if (_agente.running) {
            notice = "Finish the current pairing before pairing another device."
            return
        }
        const mac = String(device.address || "")
        if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac)) return
        _reciente = device
        emparejando = mac
        falloEmparejar = ""
        notice = ""
        // Discovery keeps a new device in BlueZ's tree through the complete operation.
        // This agent handles simple pairing; interactive confirmation needs a system tool.
        _agente.command = ["sh", "-c",
            "{ echo 'scan on'; sleep 4;"
            + " echo 'pair " + mac + "'; sleep 9;"
            + " echo 'trust " + mac + "'; sleep 1;"
            + " echo 'connect " + mac + "'; sleep 7;"
            + " echo quit; } | bluetoothctl --agent KeyboardDisplay"]
        _agente.running = true
    }

    property Process _agente: Process {
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (code, status) {
            const device = bt._reciente
            bt.emparejando = ""
            if (!device) return
            if (device.paired || device.bonded) {
                if (!device.trusted) device.trusted = true
                bt.notice = ""
                bt._vigilancia.vueltas = 0
                bt._vigilancia.restart()
            } else {
                bt.falloEmparejar = device.address
                bt.notice = "Could not pair with " + (device.name || device.address)
                    + ". Check pairing mode and retry. If a passkey or confirmation is required, use your system Bluetooth tool."
                bt._reciente = null
            }
        }
    }
    // Only follow the device explicitly requested. Its first connection can drop
    // after bonding, so observe the complete settling interval before releasing it.
    property Timer _vigilancia: Timer {
        property int vueltas: 0
        interval: 1500
        repeat: true
        onTriggered: {
            const device = bt._reciente
            vueltas++
            if (!device || !(device.paired || device.bonded) || vueltas > 6) {
                stop()
                bt._reciente = null
                return
            }
            if (!device.connected && !bt.busy(device)) device.connect()
        }
    }
    Binding {
        target: bt.adapter
        property: "discovering"
        value: bt.discovering && !!bt.adapter && bt.adapter.enabled
        when: bt.adapter !== null
    }
}
