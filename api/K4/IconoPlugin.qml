//  A plugin icon: its image when supplied, otherwise its Nerd Font glyph.
//
//  The same icon appears in three places: the Settings row, the application
//  grid and the control-centre strip. The image-or-glyph fallback was already
//  being copied between them; centralizing it keeps the next consumer from
//  forgetting one of the two branches.

import QtQuick

Item {
    id: control

    //  A file:// image URL, or "" if none is supplied.
    property string imagen: ""
    //  The code point used when no image is available.
    property int glifo: 0
    property int tamano: 20
    property color color: Tema.tinta

    implicitWidth: tamano
    implicitHeight: tamano

    Image {
        id: pintura
        anchors.fill: parent
        source: control.imagen
        visible: control.imagen.length > 0 && status === Image.Ready
        //  Request the display size rather than the file's full resolution:
        //  scaling a 512px PNG only at paint time made it look blurry.
        sourceSize.width: control.tamano * 2
        sourceSize.height: control.tamano * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    Glifo {
        anchors.centerIn: parent
        //  Also fall back when image loading fails: a generic icon is better
        //  than a gap that makes the plugin look broken.
        visible: !pintura.visible
        text: control.glifo > 0 ? String.fromCodePoint(control.glifo) : ""
        color: control.color
        font.pixelSize: control.tamano
    }
}
