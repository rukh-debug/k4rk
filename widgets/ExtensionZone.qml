//  The pill's flank extensions: what plugins declared through
//  K4.Capsule, painted at the end of the capsule that grew for them.
//  The idle view places one instance at each end of its row; each
//  renders the extensions registered for its side.
//
//  The zone's width is the SERVICE's number, not the text's: the pill
//  reserved exactly that much, and the text elides inside it. The
//  measuring happened in the service, with the same font the text
//  renders at — so what was reserved and what gets painted are the
//  same pixels.
//
//  Toward the screen edge: growing right, the name sits at the right
//  end of the extension. With the hug-the-text sizing the name fills
//  the zone anyway; the alignment shows when a maxLength capped a long
//  name and there is room to spare.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: zone

    property string side: "right"

    readonly property var mias: {
        const fuera = []
        for (let i = 0; i < Extensions.lista.length; ++i)
            if (Extensions.lista[i].lado === side
                    && Extensions.lista[i].visible !== false
                    && Extensions.anchoDe(Extensions.lista[i]) > 28)
                fuera.push(Extensions.lista[i])
        return fuera
    }

    readonly property int implicito: {
        let total = 0
        for (let i = 0; i < mias.length; ++i)
            total += Extensions.anchoDe(mias[i])
        return total > 0 ? total - 8 : 0
    }

    visible: mias.length > 0
    implicitWidth: implicito
    implicitHeight: 18

    //  Pegada al borde que toca: la zona es lo último de la fila y su
    //  contenido corre hacia el borde de la pantalla, no hacia el
    //  cuerpo de la píldora.
    RowLayout {
        anchors.left: zone.side === "left" ? zone.left : undefined
        anchors.right: zone.side === "right" ? zone.right : undefined
        anchors.verticalCenter: zone.verticalCenter
        spacing: 8

        Repeater {
            model: zone.mias

            delegate: RowLayout {
                required property var modelData
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                IconGlyph {
                    text: String.fromCodePoint(modelData.glifo || 0xF030E)
                    color: modelData.color || Theme.blue
                    font.pixelSize: 11
                }

                IslandLabel {
                    text: modelData.texto
                    color: Theme.ink
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.maximumWidth: Math.max(0,
                        Extensions.anchoDe(modelData) - 28)
                }
            }
        }
    }
}
