//  A row of buttons for each effect. The interesting part is what they
//  trigger: K4.Tema.tintar, K4.Isla.efecto, and the adjacent Mano component.

import QtQuick
import K4 as K4

Item {
    id: vista

    required property var plugin

    Column {
        anchors.centerIn: parent
        spacing: 10

        K4.Etiqueta {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The island as a stage"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        //  Tint the whole bar for a few seconds.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [
                    { texto: "Forest", color: "#2e5c3a" },
                    { texto: "Ember", color: "#5c2e2e" },
                    { texto: "Abyss", color: "#26324f" },
                    { texto: "Untint", color: "" }
                ]

                delegate: K4.Baldosa {
                    id: chipTinte
                    required property var modelData
                    width: etiquetaTinte.implicitWidth + 26
                    height: 30

                    K4.Etiqueta {
                        id: etiquetaTinte
                        anchors.centerIn: parent
                        text: chipTinte.modelData.texto
                        font.pixelSize: 11
                    }

                    onPulsada: {
                        if (chipTinte.modelData.color === "")
                            K4.Tema.destintar("efectos")
                        else
                            K4.Tema.tintar("efectos", chipTinte.modelData.color,
                                           0.35, 4000)
                    }
                }
            }
        }

        //  Gestures: the island as a physical object.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [
                    { texto: "Shake", gesto: "sacudida" },
                    { texto: "Shove", gesto: "empujon" },
                    { texto: "Tug", gesto: "tiron" }
                ]

                delegate: K4.Baldosa {
                    id: chipGesto
                    required property var modelData
                    width: etiquetaGesto.implicitWidth + 26
                    height: 30

                    K4.Etiqueta {
                        id: etiquetaGesto
                        anchors.centerIn: parent
                        text: chipGesto.modelData.texto
                        font.pixelSize: 11
                    }

                    onPulsada: K4.Isla.efecto("efectos", chipGesto.modelData.gesto)
                }
            }
        }

        //  Drawing outside and moving: the hand peeks out, and the island
        //  moves along its edge before returning on its own.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            K4.Baldosa {
                width: etiquetaMano.implicitWidth + 26
                height: 30
                activa: vista.plugin.manoFuera

                K4.Etiqueta {
                    id: etiquetaMano
                    anchors.centerIn: parent
                    text: vista.plugin.manoFuera
                        ? "Hide the hand"
                        : "Show the hand"
                    font.pixelSize: 11
                }

                onPulsada: vista.plugin.manoFuera = !vista.plugin.manoFuera
            }

            K4.Baldosa {
                width: etiquetaPaseo.implicitWidth + 26
                height: 30

                K4.Etiqueta {
                    id: etiquetaPaseo
                    anchors.centerIn: parent
                    text: "Out for a walk"
                    font.pixelSize: 11
                }

                //  Move to 15% of the edge for three seconds, then return.
                onPulsada: K4.Isla.colocar("efectos", 0.15, 3000)
            }
        }
    }
}
