pragma Singleton

//  The keyboard shortcuts configured in Hyprland.
//
//  The source is the configuration file, not `hyprctl binds`: with Lua
//  configuration, hyprctl reports `dispatcher: __lua` for every binding,
//  revealing the key but not its action. Its JSON output is also malformed
//  in this version. The file gives each action exactly and already groups
//  bindings through section comments.
//
//  tools/shortcuts.py reads it. This service only requests, stores and filters it.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: shortcuts

    property var entries: []
    property bool loaded: false

    function reload() { reader.running = true }

    function filter(text) {
        const q = (text || "").trim().toLowerCase()
        if (q.length === 0)
            return entries

        // Plain match on combo, phrase, detail and section.
        const results = []
        for (let i = 0; i < entries.length; ++i) {
            const a = entries[i]
            if (a.combo.toLowerCase().indexOf(q) !== -1
                || a.description.toLowerCase().indexOf(q) !== -1
                || (a.detail && a.detail.toLowerCase().indexOf(q) !== -1)
                || a.section.toLowerCase().indexOf(q) !== -1)
                results.push(a)
        }
        return results
    }

    // Split a combination into parts to render as individual keys.
    function keysForCombo(combo) {
        const parts = String(combo).split("+")
        const keys = []
        for (let i = 0; i < parts.length; ++i) {
            const t = parts[i].trim()
            if (t.length > 0)
                keys.push(t)
        }
        return keys
    }

    Process {
        //  Keep stderr, previously discarded, so failures leave their reason
        //  in the bar's log.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("shortcuts:", l)
            }
        }
        id: reader
        command: ["python3", Quickshell.shellPath("tools/shortcuts.py")]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    shortcuts.entries = d.shortcuts || []
                } catch (e) {
                    shortcuts.entries = []
                }
                shortcuts.loaded = true
            }
        }
    }
}
