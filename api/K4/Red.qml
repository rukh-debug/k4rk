pragma Singleton

//  Wi-Fi and Bluetooth: report the machine's connections.
//
//  Read-only: plugins cannot connect to networks or pair devices, even with
//  permission. This restriction is deliberate: mistakes can disconnect the
//  machine or pair it with someone else's device, and plugin convenience
//  does not justify that tradeoff. When needed, `k4 wifi` and `k4 bluetooth`
//  open the shell's panels so the user can decide.

import QtQuick

QtObject {
    readonly property var _w: Puente.wifi
    readonly property var _b: Puente.bluetooth

    // ── Wi‑Fi ─────────────────────────────────────────────────────
    readonly property bool wifiActiva: _w ? _w.activada : false
    readonly property string wifiNombre: _w ? _w.name : ""
    readonly property bool buscando: _w ? _w.scanning : false
    //  Visible networks, each passed through as NetworkManager supplies it.
    readonly property var redes: _w ? _w.networks : []

    // ── Bluetooth ─────────────────────────────────────────────────
    readonly property bool bluetoothActivo:
        (_b && _b.adapter) ? _b.adapter.enabled : false
    readonly property var aparatos: _b ? _b.devices : []
}
