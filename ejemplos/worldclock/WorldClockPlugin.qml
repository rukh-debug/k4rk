//  The Control Centre card example: a world-clock row.
//
//  Complete and loadable as is: copy this folder to
//  ~/.config/k4/plugins/worldclock, enable it in Settings, and open
//  the control centre — the card sits among the native blocks, and
//  Settings → Control centre reorders and hides it like any of them.
//
//  A card-only plugin has no `view` and never asks for the island's
//  stage: it exists to put one block in the centre and that is all.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "worldclock"
    title: "World clock"
    priority: 90

    //  The card: registered the moment this object exists, swept the
    //  moment the plugin dies. The centre knows it as
    //  "worldclock.clocks".
    property var tarjeta: K4.Card {
        plugin: "worldclock"
        name: "clocks"
        titulo: "World clock"
        glifo: 0xF0150        // md-clock_outline
        desc: "Local time and UTC, side by side"
        alto: 56
        component: Component { Relojes {} }
    }
}
