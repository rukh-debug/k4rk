pragma Singleton

//  The submap Hyprland is in right now.
//
//  A submap is the keyboard speaking another language for a while —
//  the screenshot keys, window resizing, whatever the user declared.
//  Plugins can't reach for Hyprland's event socket themselves (the
//  house rule the API checker keeps), so the bar listens and the state
//  is public here: "" when there is no submap, its raw id otherwise.
//
//  For anything that should happen while a mode is on — the pill's
//  submap extension is the first customer, but a plugin could dim, warn
//  or change behavior just the same.

import QtQuick

QtObject {
    readonly property string current: Puente.submaps ? Puente.submaps.current : ""
}
