//  A LIVE thumbnail of an open window.
//
//  Another window's contents, rendered here and updated automatically. Use
//  it in window pickers, Alt+Tab interfaces or hover previews where a title
//  cannot distinguish the choices: three terminals may share a title while
//  showing completely different contents.
//
//      K4.Miniatura {
//          width: 160; height: 100
//          direccion: "0x5622613de2c0"      // from `hyprctl clients`
//      }
//
//  Supply the window's ADDRESS, not its object: compositor access belongs
//  in a service, not a plugin. Plugins can still obtain the address from
//  `hyprctl`, which they already use to activate windows. This component
//  resolves that address to its owner and attaches the capture source.
//
//  If the window does not exist or closes during viewing, render nothing.
//  This is deliberately silent: the caller already tracks its windows,
//  and an error for each closed thumbnail is more distracting than a gap.

import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland

ScreencopyView {
    id: self

    //  The address as supplied by Hyprland, including its `0x` prefix.
    property string direccion: ""

    //  Compare with `lastIpcObject.address`, which includes `0x`, or fall
    //  back to `address` with the prefix added. These are two forms of the
    //  same address; relying on only one caused intermittent failures.
    captureSource: {
        if (self.direccion.length === 0)
            return null
        const lista = Hyprland.toplevels.values
        for (let i = 0; i < lista.length; ++i) {
            const t = lista[i]
            const d = (t.lastIpcObject && t.lastIpcObject.address)
                ? String(t.lastIpcObject.address)
                : (t.address ? "0x" + t.address : "")
            if (d === self.direccion)
                return t.wayland || null
        }
        return null
    }

    //  Live: show the window NOW, not a snapshot from when the picker opened.
    //  A frozen thumbnail misleads rather than informs.
    live: true
}
