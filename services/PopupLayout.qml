pragma Singleton

import QtQuick
import Quickshell
import "../core"
import "PopupPlacement.js" as Placement

// One allocation pass for all popup windows. Registration order gives existing
// windows first choice; no popup reads another popup's resulting geometry while
// deciding its own, which avoids circular bindings and corner oscillation.
Singleton {
    id: layout

    property var windows: []
    property var placements: ({})
    property var previousRequests: ({})

    function registerWindow(window) {
        if (windows.indexOf(window) < 0)
            windows = windows.concat([window])
        schedule()
    }

    function unregisterWindow(window) {
        windows = windows.filter(function (entry) { return entry !== window })
        schedule()
    }

    function schedule() { Qt.callLater(reflow) }

    function reflow() {
        const next = {}
        const requests = {}
        const occupied = {}
        const main = Island.rects
        for (const screen in main) {
            const r = main[screen]
            occupied[screen] = [{ x: r.x, y: r.y, width: r.ancho, height: r.alto }]
        }
        for (let i = 0; i < windows.length; ++i) {
            const window = windows[i]
            if (!window || !window.visible)
                continue
            const request = window.placementRequest
            if (!request.screen || request.screenWidth <= 0 || request.screenHeight <= 0)
                continue
            const signature = JSON.stringify(request)
            const previous = previousRequests[request.id] === signature
                ? placements[request.id] : null
            const obstacles = occupied[request.screen] || []
            const rect = Placement.choose(request, obstacles, Theme.wing * 2, previous)
            rect.screen = request.screen
            next[request.id] = rect
            requests[request.id] = signature
            obstacles.push(rect)
            occupied[request.screen] = obstacles
        }
        previousRequests = requests
        if (JSON.stringify(next) !== JSON.stringify(placements))
            placements = next
    }

    // Only one independent window catches outside taps on each monitor. Its
    // input mask cuts out the main island and every other independent card.
    function outsideOwner(screen) {
        for (let i = windows.length - 1; i >= 0; --i) {
            const w = windows[i]
            if (w && w.visible && w.pantalla === screen && w.owner.viewLoaded
                    && w.owner.closeOnClickOutside && !w.owner.transitorio)
                return w.owner
        }
        return null
    }

    function distantOwners(screen) {
        const owners = []
        for (let i = 0; i < windows.length; ++i) {
            const w = windows[i]
            if (w && w.visible && w.pantalla !== screen
                    && w.owner.colocable && !w.owner.transitorio)
                owners.push(w.owner)
        }
        return owners
    }

    // The newest eligible independent view gets exclusive focus. The main
    // island yields until it leaves; on-demand focus remains compositor-owned.
    readonly property var keyboardOwner: {
        for (let i = windows.length - 1; i >= 0; --i) {
            const w = windows[i]
            if (w && w.visible && w.owner.viewLoaded
                    && (w.owner.grabKeyboard || (w.owner.tecladoAlPasar && w.hovered)))
                return w.owner
        }
        return null
    }

    Connections {
        target: Island
        function onRectsChanged() { layout.schedule() }
    }
    Connections {
        target: Theme
        function onWingChanged() { layout.schedule() }
    }
}
