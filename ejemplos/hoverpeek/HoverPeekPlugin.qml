//  The hover-band example: a view that takes the island's stage while
//  the mouse rests on the pill.
//
//  There is no hover API to call — the stage is taken the way every
//  view takes it: `active` plus a priority. The clock does it with
//  priority 50 bound to `K4.Isla.raton`; this one does the same with
//  priority 51, so it stands ABOVE the clock and BELOW the player
//  (55). Hover the pill with nothing playing and this shows instead
//  of the clock; start something and the player takes over — the
//  ladder, not a fight.
//
//  Leaving is the binding's job: `raton` clears a moment after the
//  mouse goes, `active` follows, and the stage returns to the pill.
//  `closeOnHoverExit` is for SUMMONED views; a hover view never needs
//  it.
//
//  Copy this folder to ~/.config/k4/plugins/hoverpeek and enable it
//  in Settings.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "hoverpeek"
    title: "Hover peek"
    priority: 51
    active: habilitado && K4.Isla.raton

    islandWidth: 300
    islandHeight: 84

    view: Component { PeekView { plugin: self } }
}
