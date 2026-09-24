pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Host lifetime: a queued keyring write survives unloading its plugin.
Singleton {
    id: service
    property int nextId: 0
    property var queue: []
    property var active: null
    property var memory: ({})
    property string output: ""
    signal completed(int requestId, string value, string error)

    function request(action, plugin, account, value) {
        const id = ++nextId
        const key = JSON.stringify([plugin, account])
        if (action === "get" && memory[key] !== undefined) {
            const cached = memory[key]
            Qt.callLater(function () { service.completed(id, cached, "") })
            return id
        }
        if (action !== "get") memory[key] = value || ""
        queue = queue.concat([{ id: id, action: action, plugin: plugin,
            account: account, value: value || "", key: key }])
        pump()
        return id
    }
    function pump() {
        if (active || !queue.length) return
        active = queue[0]
        queue = queue.slice(1)
        output = ""
        worker.running = true
    }
    Process {
        id: worker
        command: ["python3", Quickshell.shellPath("tools/credentials.py")]
        stdinEnabled: true
        onStarted: write(JSON.stringify(service.active) + "\n")
        stdout: StdioCollector { onStreamFinished: service.output = text }
        onExited: {
            const request = service.active
            let value = "", error = ""
            try {
                const result = JSON.parse(service.output)
                value = result.value || ""
                error = result.error || ""
            } catch (e) { error = "System keyring unavailable; credentials are session-only" }
            if (request.action === "get") {
                // A queued save already owns the session value. Its older
                // lookup must not overwrite that value when it finishes.
                if (!error && service.memory[request.key] === undefined) service.memory[request.key] = value
                if (service.memory[request.key] !== undefined) value = service.memory[request.key]
            }
            service.active = null
            service.completed(request.id, value, error)
            service.pump()
        }
    }
}
