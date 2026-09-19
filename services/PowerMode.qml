pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import K4 as K4

Singleton {
    id: root
    property var state: ({ available: false, profiles: [], profile: "" })
    property string error: ""
    property int viewers: 0
    property bool pendingRefresh: false
    readonly property bool busy: worker.running
    readonly property string summary: state.available ? label(state.profile) : "Power modes unavailable"

    function label(profile) {
        return profile === "power-saver" ? "Power saver" : profile === "performance" ? "Performance" : "Balanced"
    }
    function refresh() {
        if (busy) { pendingRefresh = true; return }
        worker.command = ["python3", K4.Paths.guion("power_mode.py"), "inspect"]
        worker.running = true
    }
    function setProfile(profile) {
        if (busy || !state.available || state.profiles.indexOf(profile) < 0) return
        error = ""
        worker.command = ["python3", K4.Paths.guion("power_mode.py"), profile]
        worker.running = true
    }
    Component.onCompleted: refresh()
    Connections {
        target: PowerProfiles
        function onProfileChanged() { root.refresh() }
        function onHasPerformanceProfileChanged() { root.refresh() }
        function onHoldsChanged() { root.refresh() }
        function onDegradationReasonChanged() { root.refresh() }
    }
    Timer {
        interval: root.viewers > 0 ? 5000 : 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    K4.Process {
        id: worker
        onSalida: function(text) {
            try {
                const result = JSON.parse(text)
                if (result.available) {
                    if (!root.state.available) root.error = ""
                    root.state = result
                }
                else if (command[2] === "inspect") root.state = { available: false, profiles: [], profile: "" }
                if (result.error) root.error = result.error
            } catch (e) { root.error = "Could not read power-profile state" }
        }
        onTerminado: function(code) {
            if (code !== 0 && !root.error) root.error = "Could not contact the power service"
            if (root.pendingRefresh) { root.pendingRefresh = false; Qt.callLater(root.refresh) }
        }
    }
    IpcHandler {
        target: "k4.powerMode"
        function status(): string { return JSON.stringify({ state: root.state, busy: root.busy, error: root.error }) }
        function set(profile: string): void { root.setProfile(profile) }
    }
}
