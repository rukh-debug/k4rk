pragma Singleton

//  System tray (StatusNotifierItem).
//
//  Instantiating this service registers k4 as a tray host: applications
//  publish nothing until it exists. Those started before the bar may not
//  retry, so a missing application needs to be restarted itself rather
//  than restarting the bar.

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: tray

    readonly property var items: SystemTray.items

    // Sort by name so applications do not move around when they register
    // again.
    readonly property var sorted: {
        const list = SystemTray.items.values.slice()
        list.sort(function (a, b) {
            return (a.title || a.id || "").localeCompare(b.title || b.id || "")
        })
        return list
    }

    readonly property int count: sorted.length

    // Items requesting attention blink in the pill.
    readonly property var attention: sorted.filter(function (i) {
        return i.status === Status.NeedsAttention
    })

    readonly property bool hasAttention: attention.length > 0

    function label(item) {
        if (!item)
            return ""
        if (item.title && item.title.length > 0)
            return item.title
        if (item.tooltipTitle && item.tooltipTitle.length > 0)
            return item.tooltipTitle
        return item.id || "Unnamed"
    }

    function detail(item) {
        if (!item)
            return ""
        // Tooltips often repeat the title instead of adding information.
        if (item.tooltipDescription && item.tooltipDescription.length > 0
            && item.tooltipDescription !== label(item))
            return item.tooltipDescription
        if (item.tooltipTitle && item.tooltipTitle.length > 0
            && item.tooltipTitle !== label(item))
            return item.tooltipTitle
        return item.id || ""
    }

    function statusText(item) {
        if (!item)
            return ""
        if (item.status === Status.NeedsAttention)
            return "Needs attention"
        if (item.status === Status.Passive)
            return "In background"
        return "Active"
    }

    // Left click. Some applications only provide a menu (onlyMenu): their
    // activation does nothing, so the caller must show the menu directly.
    function primary(item) {
        if (!item || item.onlyMenu)
            return false
        item.activate()
        return true
    }

    function secondary(item) {
        if (item)
            item.secondaryActivate()
    }
}
