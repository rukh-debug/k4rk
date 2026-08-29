import QtQuick
import K4 as K4

K4.Aparicion {
    id: vista

    required property var plugin

    K4.Rodillo {
        anchors.fill: parent
        anchors.margins: 14

        Column {
            width: parent.width
            spacing: 14

            K4.Etiqueta {
                text: "API pieces"
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            // ── Interruptor ───────────────────────────────────────
            Row {
                width: parent.width
                spacing: 10

                K4.Glifo {
                    text: "󰛨"  // md-lightbulb_on
                    color: vista.plugin.encendido ? K4.Tema.amarillo
                                                  : K4.Tema.tenue
                    anchors.verticalCenter: parent.verticalCenter
                }

                K4.Etiqueta {
                    text: "Toggle switch"
                    width: parent.width - 100
                    anchors.verticalCenter: parent.verticalCenter
                }

                K4.Interruptor {
                    marcado: vista.plugin.encendido
                    anchors.verticalCenter: parent.verticalCenter
                    //  No cambia solo: manda el plugin.
                    onAlternado: vista.plugin.encendido = !vista.plugin.encendido
                }
            }

            // ── Deslizador ────────────────────────────────────────
            K4.Deslizador {
                width: parent.width
                etiqueta: "Slider"
                valor: vista.plugin.nivel
                sufijo: "%"
                onMovido: function (v) { vista.plugin.nivel = v }
            }

            // ── Medidor ───────────────────────────────────────────
            //  El hermano quieto del deslizador: este se mira, no se toca.
            Row {
                width: parent.width
                spacing: 10

                K4.Etiqueta {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Gauge"
                    color: K4.Tema.apagado
                    font.pixelSize: 11
                }

                K4.Medidor {
                    width: parent.width - 118
                    anchors.verticalCenter: parent.verticalCenter
                    valor: vista.plugin.nivel
                    maximo: 100
                    tono: valor >= 85 ? K4.Tema.rojo
                        : valor >= 60 ? K4.Tema.amarillo : K4.Tema.verde
                    //  Con 3, un valor diminuto se sigue viendo.
                    minimo: 3
                }

                K4.Etiqueta {
                    width: 38
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(vista.plugin.nivel) + "%"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── Baldosas ──────────────────────────────────────────
            Row {
                spacing: 10

                K4.Baldosa {
                    width: 150
                    height: 66
                    activa: vista.plugin.baldosaActiva
                    onPulsada: vista.plugin.baldosaActiva = !vista.plugin.baldosaActiva

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        K4.Glifo {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰖩"  // md-wifi
                            font.pixelSize: 20
                            color: vista.plugin.baldosaActiva ? K4.Tema.azul
                                                              : K4.Tema.apagado
                        }
                        K4.Etiqueta {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: vista.plugin.baldosaActiva
                                ? "Active" : "Tile"
                            font.pixelSize: 11
                        }
                    }
                }

                K4.Baldosa {
                    width: 150
                    height: 66
                    pulsable: false

                    K4.Etiqueta {
                        anchors.centerIn: parent
                        text: "Not clickable"
                        color: K4.Tema.apagado
                        font.pixelSize: 11
                    }
                }
            }

            // ── Botones ───────────────────────────────────────────
            Row {
                spacing: 4

                K4.Boton {
                    glifo: "󰒮"  // md-skip_previous
                    activo: false                  // apagado, no escondido
                }
                K4.Boton {
                    glifo: "󰐊"  // md-play
                    tamano: 24
                    onPulsado: vista.plugin.pulsaciones += 1
                }
                K4.Boton {
                    glifo: "󰒭"  // md-skip_next
                    onPulsado: vista.plugin.pulsaciones += 1
                }

                K4.Etiqueta {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${vista.plugin.pulsaciones} clicks`
                    color: K4.Tema.apagado
                    font.pixelSize: 11
                }
            }

            // ── Estela: el cursor de la casa ──────────────────────
            //
            //  Va de `cursorDelegate` y ya: el campo lo coloca, la pieza
            //  decide cómo se pinta. Escribe aquí y mira el rastro.
            K4.Etiqueta {
                text: "Estela — type and watch the cursor"
                font.pixelSize: 11
                color: K4.Tema.apagado
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 10
                color: K4.Tema.superficie

                TextInput {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: K4.Tema.tinta
                    font.pixelSize: 13
                    selectByMouse: true
                    cursorVisible: true
                    cursorDelegate: K4.Estela {}
                    text: "type something"
                }
            }

            // ── Relleno, para que haya algo que rodar ─────────────
            Repeater {
                model: 6
                delegate: K4.Baldosa {
                    required property int index
                    width: parent.width
                    height: 44

                    K4.Etiqueta {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        text: `Row ${index + 1} · scroll the wheel`
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
