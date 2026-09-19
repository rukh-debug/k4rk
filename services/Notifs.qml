pragma Singleton

//  The shell's notification server.
//
//  Incoming notifications emit notified() rather than changing other
//  modules' state. Features that need to yield, such as the launcher or
//  panel, subscribe to the signal.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Singleton {
    id: notifs

    signal notified()

    property var latest: null
    property int count: 0
    property bool toastOpen: false

    readonly property var tracked: server.trackedNotifications

    // Newest first for the strip shown on island hover, where the most
    // recent arrivals matter most.
    readonly property var recent: {
        const list = server.trackedNotifications.values.slice()
        list.reverse()
        return list
    }

    function clear() {
        // Copy first: dismissing mutates the list during iteration.
        const list = server.trackedNotifications.values.slice()
        for (let i = 0; i < list.length; ++i)
            list[i].dismiss()

        count = 0
        toastOpen = false
        toastTimer.stop()
    }

    function dismissToast() {
        toastTimer.stop()
        toastOpen = false
    }

    // Do not expire a toast while the pointer is over it.
    function holdToast() { toastTimer.stop() }
    function resumeToast() { if (toastOpen) toastTimer.restart() }

    function markRead() { count = 0 }

    // Notification-strip height (widgets/NotifStrip.qml). Keep the measure
    // here so features can size the island before their views exist,
    // using one shared formula.
    readonly property int stripRow: 38          // 34-pixel row + 4-pixel gap

    //  The strip's own height: its header, rows and gaps.
    //
    //  Nothing else. This used to add twenty pixels for surrounding space,
    //  but each view has its own margins and spacing: a fixed allowance was
    //  too small in one and too large in another. Notifications ended up
    //  pressed against the island's bottom edge. The embedding view now
    //  adds its own spacing, which only that view can determine.
    function stripHeight(max) {
        const n = Math.min(recent.length, max)
        // 14-pixel header + 4-pixel gap + n 34-pixel rows with 4-pixel gaps.
        return n === 0 ? 0 : 18 + n * 34 + (n - 1) * 4
    }

    // ── clicking a notification ───────────────────────────────────
    // By protocol convention, the "default" action handles a click on the
    // body; other actions are buttons.
    function defaultAction(n) {
        if (!n || !n.actions)
            return null

        for (let i = 0; i < n.actions.length; ++i) {
            if (n.actions[i].identifier === "default")
                return n.actions[i]
        }
        return null
    }

    function buttons(n) {
        if (!n || !n.actions)
            return []

        return n.actions.filter(function (a) { return a.identifier !== "default" })
    }

    // Prefer the notification's image, then the application's icon. If
    // neither exists, the caller supplies the generic bell.
    function iconFor(n) {
        if (!n)
            return ""
        if (n.image && n.image.length > 0)
            return n.image
        if (n.appIcon && n.appIcon.length > 0)
            return Quickshell.iconPath(n.appIcon, true)
        return ""
    }

    // A body click invokes the default action if present; otherwise focus
    // the application's window, as users expect.
    //
    // If neither is possible, leave the notification in place. Dismissing
    // it without taking the user anywhere would make the application seem
    // unresponsive.
    function activate(n) {
        if (!n)
            return

        const action = defaultAction(n)
        if (action) {
            action.invoke()
            // The protocol closes a notification after an action unless
            // it declares itself resident.
            if (!n.resident)
                n.dismiss()
            return
        }

        focusApp(n)
    }

    function invokeAction(n, action) {
        if (!action)
            return

        action.invoke()
        if (n && !n.resident)
            n.dismiss()
    }

    // ── focusing the application's window ─────────────────────────
    // Hyprland.toplevels is empty here, so query hyprctl and match manually:
    // exact class first, then class substring, then title.
    property var pendingMatch: []
    property string pendingPid: ""
    property var pendingNotification: null

    //  ── notification ownership ───────────────────────────────────
    //
    //  An application's appName rarely equals its window class: Zen Browser
    //  opens `zen`, while Telegram Desktop opens `org.telegram.desktop`.
    //  A handwritten mapping cannot keep up: the list is endless, varies
    //  by machine, and misses applications installed later.
    //
    //  Desktop entries already provide StartupWMClass precisely to identify
    //  an application's windows; launchers use it to avoid opening duplicates.
    //  Quickshell exposes it as startupClass. Find the entry by ID or name
    //  and ask it for the class.
    //
    //  One manual list remains, for command-line tools. An agent has neither
    //  a desktop entry nor its own window; all we know is that it runs in a
    //  terminal. These aliases therefore use the detected Consola.binario
    //  rather than a hardcoded terminal.
    readonly property string terminal: (Consola.binario || "kitty").toLowerCase()

    readonly property var aliases: ({
        // Command-line tools route to the terminal emulator hosting them.
        "claude code": terminal,
        "claude": terminal,
        "codex": terminal
    })

    //  Candidate window classes, most reliable first. Return several because
    //  some desktop entries have incorrect StartupWMClass values: Telegram
    //  declares `org.telegram.desktop.desktop`, including the file suffix,
    //  so the stripped desktop ID is the correct alternative.
    function clasesDe(n) {
        const raw = (n && n.desktopEntry && n.desktopEntry.length > 0
                     ? n.desktopEntry : (n ? n.appName : "")) || ""
        if (raw.length === 0)
            return []

        const bajo = raw.toLowerCase()

        //  Explicit aliases win because these cases cannot be inferred.
        if (aliases[bajo] !== undefined)
            return [String(aliases[bajo]).toLowerCase()]

        const salida = [bajo]
        const anotar = function (v) {
            const s = String(v || "").toLowerCase().replace(/\.desktop$/, "")
            if (s.length > 0 && salida.indexOf(s) < 0)
                salida.push(s)
        }

        const pelado = bajo.replace(/\.desktop$/, "")
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const id = String(a.id || "").toLowerCase().replace(/\.desktop$/, "")
            //  Match the ID or display name: applications choose which one
            //  to send.
            if (id !== pelado && String(a.name || "").toLowerCase() !== bajo)
                continue

            anotar(a.startupClass)
            anotar(id)
        }
        return salida
    }

    //  ── when the EXACT window is known ────────────────────────────
    //
    //  Class matching finds a window of the application, which suffices
    //  when only one is open. Two k4term windows have the same class, and
    //  Hyprland lists them in creation order, so clicking an attention
    //  notice used to select the oldest — often the wrong window.
    //
    //  k4's own notices know their owner: a specific terminal rings the bell,
    //  and its PID identifies its pill entry. Store it here so the click
    //  reaches that window. Notices without an explicit destination still
    //  fall back to class matching.
    //
    //  Include the body in the key: two waiting agents produce distinct
    //  notices, each belonging to its own window.
    property var destinos: ({})

    function _clave(app, cuerpo) {
        return String(app || "").toLowerCase() + "\n" + String(cuerpo || "")
    }

    function apuntarDestino(app, cuerpo, pid) {
        const p = String(pid || "")
        if (p.length === 0)
            return
        const d = Object.assign({}, destinos)
        d[_clave(app, cuerpo)] = p
        destinos = d
    }

    function olvidarDestino(app, cuerpo) {
        const k = _clave(app, cuerpo)
        if (destinos[k] === undefined)
            return
        const d = Object.assign({}, destinos)
        delete d[k]
        destinos = d
    }

    function destinoDe(n) {
        if (!n)
            return ""
        const p = destinos[_clave(n.appName, n.body)]
        return p === undefined ? "" : p
    }

    function focusApp(n) {
        const clases = clasesDe(n)
        if (clases.length === 0)
            return

        pendingMatch = clases
        pendingPid = destinoDe(n)
        pendingNotification = n
        clientQuery.running = true
    }

    //  Does this window own this notification? Use equality only; candidate
    //  classes already handle that well. Substring matching is reserved for
    //  matchAndFocus's final fallback, where an explicit click requests a
    //  destination and selecting the wrong window does not discard unseen
    //  notices in the background.
    function casa(clases, cls, initial) {
        for (let i = 0; i < clases.length; ++i)
            if (clases[i] === cls || clases[i] === initial)
                return true
        return false
    }

    function matchAndFocus(json) {
        const clases = pendingMatch
        const n = pendingNotification
        const pid = pendingPid
        pendingMatch = []
        pendingPid = ""
        pendingNotification = null

        if (!clases || clases.length === 0)
            return

        let list
        try {
            list = JSON.parse(json)
        } catch (e) {
            return
        }

        //  For the fallback, use the final part of a dotted ID, such as
        //  org.gnome.Nautilus -> nautilus, which may be the actual class.
        //  Exclude names of three characters or fewer: substring matching
        //  with those would match too many windows.
        const colas = []
        for (let i = 0; i < clases.length; ++i) {
            const k = clases[i]
            const cola = k.indexOf(".") !== -1 ? k.substring(k.lastIndexOf(".") + 1) : k
            if (cola.length > 3 && colas.indexOf(cola) < 0)
                colas.push(cola)
        }

        let exact = null
        let partial = null
        let porPid = null
        for (let i = 0; i < list.length; ++i) {
            const c = list[i]
            const cls = String(c.class || "").toLowerCase()
            const initial = String(c.initialClass || "").toLowerCase()
            const title = String(c.title || "").toLowerCase()
            const initialTitle = String(c.initialTitle || "").toLowerCase()

            //  A known window PID needs no guessing.
            if (pid.length > 0 && String(c.pid) === pid) {
                porPid = c
                break
            }

            if (casa(clases, cls, initial)) {
                exact = c
                break
            }
            if (partial === null)
                for (let j = 0; j < colas.length; ++j)
                    if (cls.indexOf(colas[j]) !== -1 || initial.indexOf(colas[j]) !== -1
                        || initialTitle.indexOf(colas[j]) !== -1
                        || title.indexOf(colas[j]) !== -1) {
                        partial = c
                        break
                    }
        }

        const found = porPid || exact || partial
        if (found) {
            // Use Lua syntax like the rest of the Hyprland configuration.
            // The new parser wraps arguments in hl.dispatch(...), so
            // `dispatch focuswindow address:…` fails to compile; pass a real
            // dispatcher instead. `focus` accepts direction, monitor,
            // window, urgent_or_last and last.
            Hyprland.dispatch('hl.dsp.focus({ window = "address:' + found.address + '" })')
            if (n && !n.resident)
                n.dismiss()
            return
        }

        // No matching window: launch the application if the notification
        // identifies its desktop entry. Otherwise leave the notice in place.
        if (n && launchEntry(n))
            n.dismiss()
    }

    function launchEntry(n) {
        const id = (n.desktopEntry || "").toLowerCase()
        if (id.length === 0)
            return false

        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const app = apps[i]
            const appId = String(app.id || "").toLowerCase()
            if (appId === id || appId === id + ".desktop"
                || appId.replace(/\.desktop$/, "") === id) {
                app.execute()
                return true
            }
        }
        return false
    }

    // ── dismiss automatically when visiting the application ───────
    //
    //  A notice directs the user somewhere. Once they arrive, its job is
    //  done; requiring another click to dismiss it duplicates the work.
    //  An agent's completed-turn bell used to linger, including in the
    //  clock's hover strip, until the user explicitly dismissed it.
    //
    //  Watch the newly focused window and dismiss its notices using the same
    //  class candidates as click routing, including aliases. Command-line
    //  tool notices then disappear when the user returns to their terminal.
    //
    //  Use ONLY equality through casa(), without titles or ID suffixes.
    //  A generous match is a reasonable last resort for a click because it
    //  merely selects the wrong window. Automatic dismissal has no such
    //  confirmation: a false match would discard unread notices. A browser
    //  tab titled Slack must not dismiss Slack's notifications.
    function descartarDeVentana(t) {
        const d = t && t.lastIpcObject ? t.lastIpcObject : null
        if (!d)
            return

        const cls = String(d.class || "").toLowerCase()
        const initial = String(d.initialClass || "").toLowerCase()
        if (cls.length === 0 && initial.length === 0)
            return

        // Copy first: dismissing mutates the list during iteration.
        const list = server.trackedNotifications.values.slice()
        let idas = 0
        for (let i = 0; i < list.length; ++i) {
            if (!casa(clasesDe(list[i]), cls, initial))
                continue
            if (latest === list[i])
                dismissToast()
            list[i].dismiss()
            ++idas
        }

        //  The panel counts UNREAD notices. These have been attended to;
        //  leaving the count unchanged would show a badge on an empty inbox.
        if (idas > 0)
            count = Math.max(0, count - idas)
    }

    //  Also handle features without a window to focus. The island terminal
    //  lives INSIDE the bar: opening its tab attends to the bell without
    //  changing Hyprland focus. Consumers can explicitly report that a notice
    //  has been attended to so it can be removed here.
    function descartarDeApp(app, cuerpo) {
        const quien = String(app || "").toLowerCase()
        if (quien.length === 0)
            return

        const texto = cuerpo === undefined ? null : String(cuerpo)
        const list = server.trackedNotifications.values.slice()
        let idas = 0
        for (let i = 0; i < list.length; ++i) {
            const n = list[i]
            if (String(n.appName || "").toLowerCase() !== quien)
                continue
            //  Without a body, remove every notice from this application;
            //  with one, remove only matching notices. Attending to one of
            //  two waiting agents must not clear the other's notice.
            if (texto !== null && String(n.body || "") !== texto)
                continue
            if (latest === n)
                dismissToast()
            n.dismiss()
            ++idas
        }
        if (idas > 0)
            count = Math.max(0, count - idas)
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            if (Settings.notificationsOnFocus)
                notifs.descartarDeVentana(Hyprland.activeToplevel)
        }
    }

    Process {
        //  Keep stderr, previously discarded, so failures leave their reason
        //  in the bar's log.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("notifs:", l)
            }
        }
        id: clientQuery
        command: ["hyprctl", "-j", "clients"]

        stdout: StdioCollector {
            onStreamFinished: notifs.matchAndFocus(this.text)
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true

        onNotification: function (notification) {
            notification.tracked = true
            notifs.latest = notification
            notifs.count += 1
            notifs.toastOpen = true
            toastTimer.restart()
            notifs.notified()
        }
    }

    Timer {
        id: toastTimer
        interval: 5000
        onTriggered: notifs.dismissToast()
    }
}
