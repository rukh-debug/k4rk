pragma Singleton

//  Which monitors are showing a true-fullscreen window right now.
//
//  This exists because of a rendering order, not a preference: Hyprland
//  draws the layer-shell top AND overlay layers above fullscreen windows
//  (background → bottom → windows, the fullscreen pass included → top →
//  overlay), so a bar that floats over normal windows has no fixed layer
//  that also goes behind a fullscreen one. The only seat below a
//  fullscreen window is the bottom layer, and it is only correct while
//  the fullscreen lasts — hence a state that flips, not a setting.
//
//  "True fullscreen" is Hyprland's internal state 2 (SUPER+SHIFT+F, or
//  a client F11 — enum eFullscreenMode: 0 none, 1 maximized, 2
//  fullscreen): the window owns the whole output. State 1 — maximized,
//  SUPER+F — also fills the screen but renders like any window, under
//  the bar, which is the arrangement the island was drawn for; it is
//  deliberately not counted here.
//
//  The answer is per monitor: a fullscreen video on one output says
//  nothing about the island living on the other. And it is the workspace
//  each monitor is SHOWING that counts (its active one, plus the special
//  one if that monitor has it deployed) — exactly the set Hyprland
//  renders fullscreen; a fullscreen window parked on a hidden workspace
//  is just a window.
//
//  Fresh data does not come from the events: the `fullscreen` broadcast
//  carries one bit and no address, so it is only a poke. On the poke —
//  and on every event that can move the answer — the IPC model is
//  re-read (`refreshToplevels()` + `refreshMonitors()`) and the map
//  below recomputes from `lastIpcObject`, which is the contract
//  quickshell documents for up-to-date IPC data.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: fullscreen

    //  monitor name -> true while that monitor's shown workspace hosts a
    //  true-fullscreen window. Reactive: it re-reads whatever the last
    //  refresh brought, so a refresh alone moves the answer.
    readonly property var perMonitor: {
        const covered = {}
        const monitors = Hyprland.monitors.values
        const windows = Hyprland.toplevels.values

        for (let i = 0; i < monitors.length; ++i) {
            const m = monitors[i]

            //  The workspaces this monitor is showing.
            const ids = []
            if (m.activeWorkspace)
                ids.push(m.activeWorkspace.id)
            const data = m.lastIpcObject
            if (data && data.specialWorkspace
                    && data.specialWorkspace.id !== 0)
                ids.push(data.specialWorkspace.id)

            for (let j = 0; j < windows.length; ++j) {
                const w = windows[j].lastIpcObject
                if (!w || w.fullscreen !== 2 || !w.workspace)
                    continue
                if (ids.indexOf(w.workspace.id) !== -1) {
                    covered[m.name] = true
                    break
                }
            }
        }
        return covered
    }

    function covers(monitorName: string): bool {
        return perMonitor[String(monitorName)] === true
    }

    function refresh(): void {
        if (typeof Hyprland.refreshToplevels === "function")
            Hyprland.refreshToplevels()
        if (typeof Hyprland.refreshMonitors === "function")
            Hyprland.refreshMonitors()
    }

    //  The events that can move the answer. `fullscreen` is the obvious
    //  one; the rest move windows between monitors and workspaces, bring
    //  new ones in, or retire a monitor.
    Connections {
        target: Hyprland
        ignoreUnknownSignals: true

        function onRawEvent(event) {
            switch (String(event.name || "")) {
            case "fullscreen":
            case "workspace":
            case "focusedmon":
            case "movewindow":
            case "openwindow":
            case "closewindow":
            case "monitoradded":
            case "monitoraddedv2":
            case "monitorremoved":
                fullscreen.refresh()
            }
        }
    }

    //  A bar that starts while a fullscreen window is already up — a
    //  reload mid-video — must not wait for the next event to learn it.
    Component.onCompleted: refresh()
}
