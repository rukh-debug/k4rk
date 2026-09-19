pragma Singleton

//  Installed applications.
//
//  What the desktop knows about them: name, icon and launch command. Plugins
//  should not need to know that this comes from reading .desktop files
//  scattered across the system.

import QtQuick
import Quickshell

Singleton {
    // [{ id, name, icon, comment, execString, ... }]
    readonly property var lista: DesktopEntries.applications.values

    readonly property int count: lista.length

    // Look up an application by its identifier, the shared naming convention.
    function porId(id) {
        const bajo = String(id).toLowerCase()
        for (let i = 0; i < lista.length; ++i)
            if (String(lista[i].id || "").toLowerCase() === bajo)
                return lista[i]
        return null
    }

    // An application icon, already resolved to a path.
    function icono(nombre) {
        return nombre && nombre.length > 0
            ? (Quickshell.iconPath(nombre, true) || "") : ""
    }
}
