pragma Singleton

// Read-only telemetry and an optional host-rendered detailed monitor.
import QtQuick

QtObject {
    readonly property var _source: Puente.systemMonitor
    readonly property bool available: _source !== null
    readonly property bool ready: _source ? _source.cargado : false
    readonly property real cpuPercent: _source ? _source.cpuUso : -1
    readonly property real cpuTemperature: _source ? _source.cpuTemp : 0
    readonly property real memoryPercent: _source ? _source.ramPct : -1
    readonly property real memoryUsed: _source ? _source.ramUsada : 0
    readonly property real memoryTotal: _source ? _source.ramTotal : 0
    readonly property real download: _source ? _source.redRx : -1
    readonly property real upload: _source ? _source.redTx : -1
    readonly property string interfaceName: _source ? _source.redIface : ""
    readonly property Component view: _source ? _source.monitorView : null

    function sample(owner, active, detailed) {
        if (_source && owner) _source.sample(String(owner), !!active, !!detailed)
    }
    function rate(bytes) { return _source ? _source.tasa(bytes) : "—" }
    function compactRate(bytes) { return _source ? _source.tasaCorta(bytes) : "—" }
    function temperature(value) { return _source ? _source.grados(value) : "—" }
}
