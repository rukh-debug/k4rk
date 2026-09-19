//  A Nerd Font icon, the source of most shell icons.
//
//  The text contains the glyph: `text: ""`. Look up icons by name with
//  `python3 tools/glyphs.py <word>` rather than guessing. That tool exists
//  because three code points chosen from memory turned out to be wrong.

import QtQuick

Text {
    //  A glyph is a code point, never markup. Enforce plain text anyway:
    //  accidentally passing a name instead of an icon must not introduce
    //  markup interpretation.
    textFormat: Text.PlainText
    color: Tema.tinta
    font.family: Tema.fuenteIconos
    font.pixelSize: 16
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
