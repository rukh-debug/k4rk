//  HUD de volumen. Aparece solo cuando el volumen cambia por fuera (teclas de
//  multimedia, mixer…) y se va solo; por eso va por debajo del hover.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    name: "volume"
    title: "Volume"
    priority: 40
    active: habilitado && Audio.overlayOpen

    islandWidth: 240
    islandHeight: 40

    //  Never in the way of a click: this HUD shows up uninvited — media keys,
    //  a mixer — and the pointer is usually busy somewhere else when it does.
    //  See `closeOnClickOutside` in the plugin contract.
    closeOnClickOutside: false

    view: Component { VolumeView {} }
}
