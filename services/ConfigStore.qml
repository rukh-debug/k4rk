pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: store
    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/k4/config.json"
    property var data: ({})
    // Kept out of data/copy/export: private owner-local state and catalog cache.
    property var localData: ({})
    property var localErrors: ({})
    property var shellDefaults: ({})
    property var localDefaults: ({})
    property bool ready: false
    property string error: ""
    property int nextId: 0
    property var requests: ({})
    property int pendingCount: 0
    signal settled()
    property bool copying: false
    property string copyError: ""
    signal copied()
    signal committed(int requestId)
    signal failed(int requestId, string message)

    function value(path, fallback) {
        function lookup(source) {
            let result = source
            for (const key of path) {
                if (result === null || typeof result !== "object" || result[key] === undefined) return undefined
                result = result[key]
            }
            return result
        }
        const shared = lookup(data), local = lookup(localData)
        if (shared === undefined) return local === undefined ? fallback : local
        if (local !== undefined && shared && local && !Array.isArray(shared)
                && typeof shared === "object" && typeof local === "object")
            return Object.assign({}, local, shared)
        return shared
    }

    function transact(operations) {
        if (!ready || !worker.running) {
            error = error || "Configuration is not ready"
            console.warn("k4: " + error)
            return -1
        }
        const id = ++nextId
        requests[id] = true
        pendingCount++
        worker.write(JSON.stringify({ id: id, operations: operations }) + "\n")
        return id
    }
    function setValue(path, value) { return transact([{ path: path, value: value }]) }
    function stateError(path) {
        for (const prefix of Object.keys(localErrors))
            if (path.join("/") === prefix || path.join("/").indexOf(prefix + "/") === 0) return localErrors[prefix]
        return ""
    }
    function remove(path) { return transact([{ path: path, delete: true }]) }
    function copyConfiguration() {
        if (ready && !error && !pendingCount && !copying) {
            copyError = ""
            copying = true
            copyProcess.running = true
        }
    }

    Process {
        id: copyProcess
        command: ["python3", Quickshell.shellPath("tools/config_store.py"), "copy"]
        onExited: function (code) {
            store.copying = false
            if (code === 0) store.copied()
            else store.copyError = "Could not copy the configuration"
        }
    }

    Process {
        id: worker
        command: ["python3", Quickshell.shellPath("tools/config_store.py"), "serve"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function (line) {
                try {
                    const reply = JSON.parse(line)
                    if (reply.outputError) {
                        console.warn("k4: " + reply.outputError)
                    } else if (reply.error) {
                        store.error = reply.error
                        console.warn("k4 configuration: " + reply.error)
                        store.failed(reply.id || -1, reply.error)
                    } else if (reply.data) {
                        store.error = ""
                        if (reply.defaults) store.shellDefaults = reply.defaults
                        if (reply.localDefaults) store.localDefaults = reply.localDefaults
                        if (reply.localErrors) store.localErrors = reply.localErrors
                        if (reply.local && JSON.stringify(store.localData) !== JSON.stringify(reply.local)) store.localData = reply.local
                        if (JSON.stringify(store.data) !== JSON.stringify(reply.data)) store.data = reply.data
                        store.ready = true
                        if (reply.id) store.committed(reply.id)
                    }
                    if (reply.id && store.requests[reply.id]) {
                        delete store.requests[reply.id]
                        store.pendingCount--
                    }
                    if (!store.pendingCount) store.settled()
                } catch (e) { store.error = "Invalid configuration service response" }
            }
        }
        onExited: {
            store.ready = false
            store.error = "Configuration service stopped; unsaved changes were not acknowledged"
            for (const id of Object.keys(store.requests)) store.failed(Number(id), store.error)
            store.requests = ({})
            store.pendingCount = 0
            restart.restart()
        }
    }
    Timer { id: restart; interval: 1000; onTriggered: worker.running = true }
}
