pragma Singleton

//  Standard filesystem locations.
//
//  Plugins should request the path they need rather than construct it
//  manually or know about ~/.local/state.

import QtQuick
import Quickshell

Singleton {
    readonly property string hogar: Quickshell.env("HOME") || ""
    readonly property string config: (Quickshell.env("XDG_CONFIG_HOME") || hogar + "/.config") + "/k4/config.json"

    // Private local data, separate from shareable preferences.
    readonly property string estado: (Quickshell.env("XDG_STATE_HOME") || hogar + "/.local/state") + "/k4"

    // k4's own directory, containing its scripts and assets.
    readonly property string raiz: Quickshell.shellPath("")

    function guion(nombre) { return Quickshell.shellPath("tools/" + nombre) }

    // Owner-local data. PluginState coordinates JSON writes here; other plugin
    // assets may also use this directory. Preferences use PluginSettings.
    function estadoDe(id) { return estado + "/plugins/" + id }

    // Anything else located in k4's directory.
    function enRaiz(relativa) { return Quickshell.shellPath(relativa) }
}
