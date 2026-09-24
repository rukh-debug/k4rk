// A keyring entry. Secret values stay in memory, never in PluginState.
import QtQuick

QtObject {
    id: self
    required property string plugin
    property string account: ""
    property string value: ""
    property bool ready: false
    property string error: ""
    readonly property bool busy: _pending > 0
    readonly property var _host: Puente.credentials
    property int _pending: 0
    property int _generation: 0
    property var _requests: ({})
    property bool _started: false

    function send(action, secret) {
        if (!account) { ready = true; return }
        if (!_host) {
            error = "System keyring unavailable; credentials are session-only"
            ready = true
            return
        }
        const id = _host.request(action, plugin, account, secret || "")
        _requests[id] = { action: action, generation: _generation }
        _pending++
    }
    function load() { _generation++; ready = false; value = ""; send("get", "") }
    function save(secret) { _generation++; value = String(secret); ready = true; send(value ? "set" : "delete", value) }
    onAccountChanged: if (_started) load()
    on_HostChanged: if (_started) load()
    Component.onCompleted: { _started = true; load() }

    property Connections _replies: Connections {
        target: self._host
        function onCompleted(id, result, failure) {
            const request = self._requests[id]
            if (!request) return
            delete self._requests[id]
            self._pending--
            if (request.generation !== self._generation) return
            self.error = failure
            if (request.action === "get") self.value = result
            self.ready = true
        }
    }
}
