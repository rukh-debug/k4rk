//  Thin wrapper around K4.Boton; see core/IconGlyph.qml. Only maps names.

import K4 as K4

K4.Boton {
    id: control

    property alias glyph: control.glifo
    property alias glyphSize: control.tamano
    property alias glyphColor: control.color
    property alias enabledAction: control.activo
    signal activated()

    onPulsado: control.activated()
}
