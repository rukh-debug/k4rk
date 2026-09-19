pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import K4 as K4

Singleton {
    id: root
    property var state: ({ available: false })
    property int viewers: 0
    property bool queued: false
    property var cities: []
    property string searchError: ""
    readonly property bool busy: worker.running
    readonly property bool searching: searcher.running
    readonly property string summary: !state.available ? "Night light unavailable"
        : state.needsLocation && Settings.nightLightEnabled ? "Choose a city"
        : state.active ? "Night light on · " + state.temperature + " K"
        : Settings.nightLightEnabled && Settings.nightLightMode === "solar" ? "Night light scheduled" : "Night light off"

    function preferences() {
        return { enabled: Settings.nightLightEnabled, temperature: Settings.nightLightTemperature,
            mode: Settings.nightLightMode, location: Settings.nightLightLocation,
            override: Settings.nightLightOverride }
    }
    function refresh() {
        if (!Settings.cargado) return
        if (busy) { queued = true; return }
        worker.command = ["python3", K4.Paths.guion("night_light.py"), "apply", JSON.stringify(preferences())]
        worker.running = true
    }
    function update(key, value) {
        Settings.poner(key, value)
        debounce.restart()
    }
    function setEnabled(enabled) {
        Settings.poner("nightLightOverride", {})
        update("nightLightEnabled", enabled)
    }
    function setMode(mode) {
        Settings.poner("nightLightOverride", {})
        update("nightLightMode", mode)
    }
    function overrideNow() {
        if (!state.available || !state.nextBoundary || state.needsLocation) return
        update("nightLightOverride", { active: !state.active, until: state.nextBoundary })
    }
    function selectCity(city) {
        Settings.poner("nightLightOverride", {})
        update("nightLightLocation", city)
        cities = []
    }
    function search(query) {
        if (searching) return
        cities = []
        searchError = ""
        if (query.trim().length < 3) { searchError = "Enter at least three characters"; return }
        searcher.command = ["python3", K4.Paths.guion("night_light.py"), "search", query]
        searcher.running = true
    }
    Component.onCompleted: refresh()
    Connections {
        target: Settings
        function onCargadoChanged() { root.refresh() }
        function onNightLightEnabledChanged() { debounce.restart() }
        function onNightLightTemperatureChanged() { debounce.restart() }
        function onNightLightModeChanged() { debounce.restart() }
        function onNightLightLocationChanged() { debounce.restart() }
        function onNightLightOverrideChanged() { debounce.restart() }
    }
    Timer { id: debounce; interval: 250; onTriggered: root.refresh() }
    // Wall-clock evaluation also recovers from resume and backend restarts.
    Timer {
        interval: Settings.nightLightEnabled || root.viewers > 0 ? 30000 : 60000
        running: Settings.cargado
        repeat: true
        onTriggered: root.refresh()
    }
    K4.Process {
        id: worker
        onSalida: function(text) {
            try { root.state = JSON.parse(text) }
            catch (e) { root.state = { available: false, error: "Could not read night-light state" } }
        }
        onTerminado: function(code) {
            if (code !== 0 && !root.state.error) root.state = { available: false, error: "Night-light helper failed" }
            if (root.queued) { root.queued = false; Qt.callLater(root.refresh) }
        }
    }
    K4.Process {
        id: searcher
        onSalida: function(text) {
            try {
                const result = JSON.parse(text)
                root.cities = result.results || []
                root.searchError = result.error || (root.cities.length ? "" : "No cities found")
            } catch (e) { root.searchError = "Could not read city search results" }
        }
        onTerminado: function(code) {
            if (code !== 0 && !root.searchError) root.searchError = "City search failed. Try again when connected."
        }
    }
    IpcHandler {
        target: "k4.nightLight"
        function status(): string { return JSON.stringify(root.state) }
        function refresh(): void { root.refresh() }
        function enable(): void { root.setEnabled(true) }
        function disable(): void { root.setEnabled(false) }
        function toggle(): void { root.setEnabled(!Settings.nightLightEnabled) }
    }
}
