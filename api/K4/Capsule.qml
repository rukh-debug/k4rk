//  A flank extension on the pill: the capsule grows toward a screen
//  edge carrying your text, and folds back when you are done.
//
//  For the thing a plugin wants to say while it is going on — a mode
//  that grabbed the keyboard, a recording in progress — where an
//  indicator chip (K4.Pildora) is too small to read at a glance. The
//  pill stays itself: its art, clock and tray do not move, and your
//  name rides on the flank.
//
//  ```qml
//  K4.Capsule {
//      plugin: "rec"
//      extension: grabando ? ({
//          lado: "right",            // "left" · "right"
//          texto: "Recording",
//          glifo: 0xF037E,           // md-record_circle_outline
//          color: K4.Tema.red,
//          maxLength: 300            // px the capsule may grow to
//      }) : null
//  }
//  ```
//
//  `extension` is a binding or it is nothing: it must produce a NEW
//  object when your state changes, since mutating the old one in place
//  tells no one. Set it to null to fold the capsule back.
//
//  The width is not yours to fight for: the bar hugs your text with
//  the pill's own font, capped by `maxLength` and by the room left to
//  the screen edge. While a deployed view owns the island — the clock
//  on hover, the control center — the extension folds with the pill
//  and comes back when the pill does.

import QtQuick

QtObject {
    id: caps

    //  Your plugin id, the same as the manifest. It names the
    //  extension — one per plugin — and cleans it up when you die.
    required property string plugin

    //  The extension to show, or null for none:
    //  { lado: "left"|"right", texto, glifo, color?, maxLength? }
    property var extension: null

    function _sync() {
        const reg = Puente.extensiones
        if (!reg)
            return
        if (extension)
            reg.registrar(plugin, extension)
        else
            reg.quitar(plugin)
    }

    onExtensionChanged: _sync()
    Component.onCompleted: _sync()

    Component.onDestruction: {
        if (Puente.extensiones)
            Puente.extensiones.quitar(plugin)
    }
}
