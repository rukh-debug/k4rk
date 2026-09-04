//  The system tray.
//
//  The list and the host registration live in the Tray service;
//  this is the view and the selection. Each application's menu is
//  drawn inside the island with QsMenuOpener, instead of opening a
//  native popup that would stand out next to the pill.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "tray"
    title: "Tray"
    priority: 63
    colocable: true
    active: habilitado && open
    //  The whole keyboard while open: «optional» is OnDemand and the
    //  compositor only gives it if you CLICK the surface, so opened
    //  from the application centre or by shortcut not even ESC
    //  arrived. See `tecladoOpcional` in api/K4/Plugin.qml.
    grabKeyboard: open

    property bool open: false
    property var selected: null

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 640
    islandHeight: 360

    handlesBackgroundTap: true
    onBackgroundTapped: {}   // swallows the click: closing is the button's

    closeOnHoverExit: true
    hoverExitDelay: 900
    onHoverTimedOut: close()

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
            if (selected === null || Tray.sorted.indexOf(selected) === -1)
                selected = Tray.count > 0 ? Tray.sorted[0] : null
        }
    }

    function close() { open = false }

    function select(item) { selected = item }

    // If the selected application disappears (closes), do not leave
    // a dead reference hanging.
    Connections {
        target: Tray.items
        function onValuesChanged() {
            if (self.selected !== null && Tray.sorted.indexOf(self.selected) === -1)
                self.selected = Tray.count > 0 ? Tray.sorted[0] : null
        }
    }

    K4.Ipc {
        target: "k4.tray"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
    }

    view: Component {
        TrayView { plugin: self }
    }
}
