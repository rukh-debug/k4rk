//  Focus the text field when a module opens.
//
//  Setting `focus: true` on the field looks sufficient, but two effects
//  interfere. First, the island root also claims focus for its Escape
//  handler, which closes any module. Second, a layer surface does not receive
//  keyboard focus at creation: the compositor grants it a little later, so
//  an initial request can arrive before the surface is ready.
//
//  Retry periodically rather than asking once, until the field has active
//  focus or the attempt limit is reached. Otherwise users must click before
//  typing, defeating the purpose of a search field opened by a shortcut.
//
//      FocoInicial { id: foco; objetivo: entrada }
//      Component.onCompleted: foco.reclamar()

import QtQuick

Timer {
    id: caza

    // The field that should receive the cursor.
    required property Item objetivo

    property int intentos: 0
    readonly property int tope: 6

    interval: 140
    repeat: false

    function reclamar() {
        intentos = 0
        objetivo.forceActiveFocus()
        restart()
    }

    onTriggered: {
        // If the module closed meanwhile, there is nothing left to focus.
        if (!objetivo.visible)
            return

        objetivo.forceActiveFocus()
        if (!objetivo.activeFocus && intentos < tope) {
            intentos += 1
            restart()
        }
    }
}
