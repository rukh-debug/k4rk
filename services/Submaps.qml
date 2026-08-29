pragma Singleton

//  The submap Hyprland is in right now.
//
//  A submap is the keyboard speaking another language for a while —
//  the screenshot keys, window resizing, whatever the user declared.
//  Hyprland announces the change on its event socket and nowhere else,
//  and a plugin may not reach for that socket itself: platform access
//  goes through a service (that is the house rule tools/api.py keeps).
//
//  So the state lives here and the submap PLUGIN does everything else:
//  how the name is shown, which way the pill grows, how far. This file
//  is only the ear — and the one question events can't answer.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: submaps

    //  Hyprland's raw id for the active map, "" when there is none.
    //  "default" is Hyprland's own word for "no submap"; anything else
    //  means a mode is on.
    property string current: ""

    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(evento) {
            if (String(evento.name || "") !== "submap")
                return
            const d = String(evento.data || "").trim()
            submaps.current = (d.length === 0 || d === "default") ? "" : d
        }
    }

    //  The one gap events can't cover: a bar that starts while a submap
    //  is already on (a reload mid-mode) hears nothing until the NEXT
    //  submap change. One `hyprctl submap` at birth — and only if no
    //  event got here first.
    property var probe: Process {
        command: ["hyprctl", "submap"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (submaps.current.length > 0)
                    return
                const d = String(this.text).trim().split("\n")[0]
                if (d.length > 0 && d !== "default" && d !== "unknown")
                    submaps.current = d
            }
        }
    }
}
