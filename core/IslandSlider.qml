//  Thin wrapper around K4.Deslizador; see core/IconGlyph.qml. Only maps names:
//  quantization and change notification remain in the API component.

import K4 as K4

K4.Deslizador {
    id: control

    property alias label: control.etiqueta
    property alias value: control.valor
    property alias from: control.desde
    property alias to: control.hasta
    property alias step: control.paso
    property alias suffix: control.sufijo
    signal moved(real value)

    onMovido: function (v) { control.moved(v) }
}
