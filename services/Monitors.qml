pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import K4 as K4
import "../core"

Singleton {
    id: root
    property int viewers: 0
    property var outputs: []
    property var draft: []
    property var transaction: ({ state: "idle" })
    property string baseline: ""
    property string observed: ""
    property string error: ""
    property bool persistent: false
    property bool dirty: false
    property bool waiting: false
    property bool identifying: false
    readonly property bool conflict: dirty && baseline !== observed
    readonly property bool busy: waiting || ["starting", "applying", "testing", "saving", "reverting"].indexOf(transaction.state) >= 0
    readonly property string script: K4.Paths.guion("monitors.py")

    function refresh() {
        if (!reader.running && !writer.running) reader.running = true
    }
    function discard() {
        if (busy) return
        draft = JSON.parse(JSON.stringify(outputs))
        baseline = observed
        dirty = false
        error = ""
    }
    function change(name, key, value) {
        if (busy) return
        const copy = JSON.parse(JSON.stringify(draft))
        const item = copy.find(o => o.name === name)
        if (!item) return
        item[key] = value
        draft = copy
        dirty = true
        error = ""
    }
    function apply() {
        if (busy || !dirty || conflict || writer.running) return
        error = ""
        waiting = true
        writer.command = ["python3", script, "begin"]
        writer.running = true
    }
    function decide(action) {
        if (writer.running || transaction.state !== "testing") return
        writer.command = ["python3", script, action, transaction.token]
        writer.running = true
    }
    function identify() {
        identifying = true
        identifyTimer.restart()
    }
    Timer { id: identifyTimer; interval: 3500; onTriggered: root.identifying = false }
    Timer {
        interval: root.busy ? 350 : 1500
        running: root.viewers > 0 || root.busy
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    K4.Process {
        id: reader
        command: ["python3", root.script, "inspect"]
        onSalida: function (text) {
            try {
                const data = JSON.parse(text)
                if (data.error) { root.error = data.error; return }
                const wasBusy = root.busy
                root.outputs = data.outputs
                root.observed = data.fingerprint
                root.persistent = data.persistent
                root.transaction = data.transaction
                if (!writer.running && root.transaction.state !== "idle") root.waiting = false
                if ((!root.dirty || wasBusy) && !root.busy) root.discard()
                if (root.transaction.error) root.error = root.transaction.error
            } catch (e) { root.error = "Could not read monitor state: " + e }
        }
    }
    K4.Process {
        id: writer
        entradaAbierta: true
        onArrancado: {
            if (command[2] === "begin") escribir(JSON.stringify({ outputs: root.draft, fingerprint: root.baseline }) + "\n")
        }
        onSalida: function (text) {
            try {
                const data = JSON.parse(text)
                if (data.error) { root.error = data.error; root.waiting = false }
            } catch (e) { root.error = "Monitor command failed: " + e; root.waiting = false }
        }
        onTerminado: function (code) {
            if (code !== 0) root.waiting = false
            root.refresh()
        }
    }

    // These surfaces outlive Settings and stay available if its output disappears.
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: root.identifying || root.transaction.state === "testing"
            anchors.top: true
            margins.top: 72
            implicitWidth: Math.min(440, modelData.width - 32)
            implicitHeight: body.implicitHeight + 32
            color: "transparent"
            exclusiveZone: -1
            WlrLayershell.namespace: "k4-monitor-confirmation"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                radius: 14
                border.color: Theme.blue
                border.width: 1
            }
            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                IslandLabel {
                    Layout.fillWidth: true
                    text: root.transaction.state === "testing" ? "Keep these monitor settings?" : overlay.modelData.name
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                IslandLabel {
                    Layout.fillWidth: true
                    text: root.transaction.state === "testing"
                        ? "Reverting automatically in " + root.transaction.remaining + " seconds."
                        : overlay.modelData.width + " × " + overlay.modelData.height + " logical pixels"
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    visible: root.transaction.state === "testing"
                    K4.ActionButton { text: "Revert"; onClicked: root.decide("revert") }
                    K4.ActionButton { text: root.persistent ? "Keep and save" : "Keep for this session"; selected: true; onClicked: root.decide("keep") }
                }
            }
        }
    }
}
