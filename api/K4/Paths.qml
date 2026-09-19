pragma Singleton

//  Standard filesystem locations.
//
//  Plugins should request the path they need rather than construct it
//  manually or know about ~/.local/state.

import QtQuick
import Quickshell

Singleton {
    readonly property string hogar: Quickshell.env("HOME") || ""

    // State that survives restarts: saved games, histories and settings.
    readonly property string estado: hogar + "/.local/state/k4"

    // k4's own directory, containing its scripts and assets.
    readonly property string raiz: Quickshell.shellPath("")

    function guion(nombre) { return Quickshell.shellPath("tools/" + nombre) }

    //  A plugin's OWN state: ~/.local/state/k4/plugins/<id>/.
    //
    //  Private rather than shared: two plugins using the same filename in
    //  a common directory would silently overwrite each other. K4.Guardado
    //  writes here and also creates the directory.
    function estadoDe(id) { return estado + "/plugins/" + id }

    // Anything else located in k4's directory.
    function enRaiz(relativa) { return Quickshell.shellPath(relativa) }
}
