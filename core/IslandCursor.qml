//  The in-house text cursor, for host views.
//
//  Only a wrapper around K4.Estela: the single implementation lives in the
//  API because external plugins need it too. This supplies core's color and
//  the host component name.
//
//      TextInput { cursorDelegate: IslandCursor {} }

import K4 as K4

K4.Estela {
    color: Theme.ink
}
