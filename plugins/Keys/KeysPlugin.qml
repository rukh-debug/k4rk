//  The shortcuts cheat-sheet: what is bound to each key, without
//  opening the file.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "keys"
    title: "Shortcuts"
    priority: 65
    colocable: true
    summonCommand: "k4.keys toggle"
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property bool closing: false
    property string query: ""

    islandWidth: 760
    islandHeight: 440

    readonly property var entries: Shortcuts.filter(query)
    readonly property int count: entries.length

    view: Component {
        KeysView { plugin: self }
    }

    function abrir() {
        // re-read on opening: if you just touched the config, you
        // want to see what is there now, not what was there when
        // the bar started
        Shortcuts.reload()
        query = ""
        closing = false
        open = true
        if (panel)
            panel.close()
    }

    function close() {
        if (!open)
            return
        open = false
        closing = true
        closeDelay.restart()
    }

    function toggle() { open ? close() : abrir() }

    Timer {
        id: closeDelay
        interval: 260
        onTriggered: self.closing = false
    }

    K4.Ipc {
        target: "k4.keys"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
    }
}
