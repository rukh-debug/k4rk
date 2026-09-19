//  Thin wrapper around K4.Baldosa; see core/IconGlyph.qml.

import K4 as K4

K4.Baldosa {
    id: baldosa

    readonly property bool hovered: baldosa.encima
}
