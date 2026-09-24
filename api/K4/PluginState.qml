// Owner-local, non-secret plugin state. Use PluginSettings for shareable values.
import QtQuick

QtObject {
    id: self
    required property string plugin
    property string name: "state"
    readonly property var _store: Puente.config
    readonly property var _path: ["plugins", plugin, name]
    property var value: ({})
    property bool ready: false
    property string error: ""
    property var _baseline: ({})
    property var _desired: ({})
    property var _ownRequests: ({})
    signal loaded(var data)

    function refresh() {
        if (!_store || !_store.ready || _store.pendingCount) return
        error = _store.stateError(_path)
        if (error) { ready = false; return }
        const next = _store.value(_path, {})
        if (!ready || JSON.stringify(next) !== JSON.stringify(_baseline)) {
            _baseline = JSON.parse(JSON.stringify(next))
            _desired = JSON.parse(JSON.stringify(next))
            value = JSON.parse(JSON.stringify(next))
            ready = true
            loaded(value)
        }
    }
    function save(data) {
        if (!ready || !_store) return -1
        // Patch changed keys only: another writer may own a different field.
        const operations = []
        for (const key of Object.keys(data))
            if (JSON.stringify(data[key]) !== JSON.stringify(_desired[key]))
                operations.push({ path: _path.concat([key]), value: data[key] })
        for (const key of Object.keys(_desired))
            if (data[key] === undefined) operations.push({ path: _path.concat([key]), delete: true })
        if (!operations.length) return 0
        const id = _store.transact(operations)
        if (id > 0) {
            _ownRequests[id] = true
            _desired = JSON.parse(JSON.stringify(data))
        }
        return id
    }
    function saveSections(sections) {
        if (!ready || !_store) return -1
        const operations = []
        for (const section of Object.keys(sections)) {
            if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(section) || section === "enabled" || section === "installation")
                return -1
            operations.push({ path: ["plugins", plugin, section], value: sections[section] })
        }
        const id = _store.transact(operations)
        if (id > 0) {
            _ownRequests[id] = true
            if (sections[name] !== undefined) _desired = JSON.parse(JSON.stringify(sections[name]))
        }
        return id
    }
    on_StoreChanged: refresh()
    Component.onCompleted: refresh()
    property Connections _changes: Connections {
        target: self._store
        function onReadyChanged() { self.refresh() }
        function onDataChanged() { self.refresh() }
        function onLocalDataChanged() { self.refresh() }
        function onLocalErrorsChanged() { self.refresh() }
        function onSettled() { self.refresh() }
        function onCommitted(id) {
            if (!self._ownRequests[id]) return
            delete self._ownRequests[id]
            const next = self._store.value(self._path, {})
            self._baseline = JSON.parse(JSON.stringify(next))
            self.value = JSON.parse(JSON.stringify(next))
            // An acknowledgement must not reload a live chat/game with an
            // older snapshot of its own state. External changes still load.
        }
        function onFailed(id, message) {
            if (!self._ownRequests[id]) return
            delete self._ownRequests[id]
            self._desired = JSON.parse(JSON.stringify(self._baseline))
            self.error = message
        }
        function onErrorChanged() { self.error = self._store.error }
    }
}
