//  Thin wrapper around K4.Interruptor; see core/IconGlyph.qml. Only maps
//  names: host views use `checked` and `toggled`.

import K4 as K4

K4.Interruptor {
    id: control

    property alias checked: control.marcado
    signal toggled()

    onAlternado: control.toggled()
}
