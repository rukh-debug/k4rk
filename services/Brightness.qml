pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import K4 as K4

Singleton {
    id: root
    property var displays: []
    property string selectedId: ""
    property bool watching: false
    property bool dragging: false
    property bool discoveryPending: false
    property var pending: ({})
    property string error: ""
    property bool received: false
    readonly property bool busy: worker.running
    readonly property var selected: displays.find(d => d.id === selectedId) || null
    readonly property bool available: !!selected && selected.available
    readonly property real value: pending[selectedId] !== undefined ? pending[selectedId]
        : selected ? selected.value : 0
    readonly property string status: error || (selected ? selected.error
        || (selected.kind === "ddc" ? "External monitor · DDC/CI" : "Built-in screen")
        : busy ? "Detecting displays…" : "No controllable displays detected")

    function selectDisplay(id) {
        if (!displays.some(d => d.id === id)) return
        selectedId = id
        error = ""
        if (!busy) start(["read", id])
    }
    function start(args) {
        received = false
        worker.command = ["python3", K4.Paths.guion("brightness.py")].concat(args)
        worker.running = true
    }
    function refresh() {
        discoveryPending = true
        pump()
    }
    function setValue(next) {
        if (!available || !isFinite(next)) return
        const copy = Object.assign({}, pending)
        copy[selectedId] = Math.max(1, Math.min(100, Math.round(next)))
        pending = copy
        error = ""
        // A short coalescing window prevents a process for every pointer event.
        if (!writeDelay.running) writeDelay.start()
    }
    function pump() {
        if (busy) return
        const ids = Object.keys(pending)
        if (ids.length) {
            const id = ids[0]
            start(["set", id, String(pending[id])])
        } else if (!dragging && discoveryPending) {
            discoveryPending = false
            start(["discover"])
        }
    }
    function accept(result) {
        const action = worker.command[2]
        const id = worker.command[3]
        if (result.displays) {
            displays = result.displays
            if (!selected) selectedId = (displays.find(d => d.available) || displays[0] || {}).id || ""
        }
        if (result.display) displays = displays.map(d => d.id === result.display.id ? result.display : d)
        if (action === "set") {
            const copy = Object.assign({}, pending)
            if (result.error || !result.display || !result.display.available
                || copy[id] === Number(worker.command[4])) delete copy[id]
            pending = copy
        }
        if (result.error && (!id || id === selectedId)) error = result.error
        else if (!id || id === selectedId) error = ""
    }
    onWatchingChanged: if (watching) refresh()
    onDraggingChanged: if (!dragging) pump()
    Component.onCompleted: refresh()
    Timer { id: writeDelay; interval: 80; onTriggered: root.pump() }
    Timer {
        interval: 2000
        running: root.watching
        repeat: true
        onTriggered: if (!root.busy && !root.dragging && !Object.keys(root.pending).length && root.selectedId)
            root.start(["read", root.selectedId])
    }
    Timer { interval: 30000; running: root.watching; repeat: true; onTriggered: root.refresh() }
    Timer { id: hotplugDelay; interval: 700; onTriggered: root.refresh() }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved"].indexOf(event.name) >= 0)
                hotplugDelay.restart()
        }
    }
    K4.Process {
        id: worker
        onSalida: function(text) {
            root.received = true
            try { root.accept(JSON.parse(text)) }
            catch (e) { root.accept({ error: "Could not read display brightness." }) }
        }
        onTerminado: function(code) {
            if (!root.received) root.accept({ error: "Brightness helper did not respond." })
            Qt.callLater(root.pump)
        }
    }
    IpcHandler {
        target: "k4.brightness"
        function status(): string {
            return JSON.stringify({ displays: root.displays, selectedId: root.selectedId,
                value: root.value, busy: root.busy, error: root.error })
        }
        function refresh(): void { root.refresh() }
        function select(id: string): void { root.selectDisplay(id) }
        function set(value: real): void { root.setValue(value) }
    }
}
