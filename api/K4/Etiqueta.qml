//  Text with the shell's defaults: white, Adwaita, 12px.
//
//  The public equivalent of core/IslandLabel, implemented here rather than
//  reexported: files in this module cannot import core/ by relative path.
//  See Puente.qml for the singleton-graph issue behind that restriction.

import QtQuick

Text {
    //  Plain text is especially important here: external plugins render
    //  whatever data they receive. See core/IslandLabel.
    textFormat: Text.PlainText
    color: Tema.tinta
    font.family: Tema.fuente
    font.pixelSize: 12
}
