pragma Singleton

//  Hyprland workspaces: which exist and which one is active.
//
//  Enough for a custom pager, an alternative pill indicator, or a plugin
//  whose behavior depends on the current workspace. Switching workspaces
//  is not exposed here: use `K4.Process` with `hyprctl`, an explicit action
//  requiring the `procesos` permission.

import QtQuick

QtObject {
    readonly property var _e: Puente.escritorios

    //  Each workspace as supplied by Hyprland: `{ id, name, … }`.
    readonly property var lista: _e ? _e.list : []
    readonly property int activo: _e ? _e.activo : 0

    //  Does fullscreen content occupy this display? Pass the monitor name,
    //  as used by `K4.Isla.rectEn()` or a `K4.Ventana`, so a plugin can move
    //  out of the way when it would obstruct the display.
    function lleno(pantalla) { return _e ? _e.lleno(pantalla) : false }
}
