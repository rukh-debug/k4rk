// Shared sound-device rows. Selection, mute and volume have independent targets.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../services"

ColumnLayout {
    id: devices
    readonly property int alturaNatural: Math.ceil(implicitHeight)
    spacing: 16
    Repeater {
        model: [{ title: "Output", input: false }, { title: "Input", input: true }]
        delegate: ColumnLayout {
            id: group
            required property var modelData
            readonly property var list: modelData.input ? Audio.entradas : Audio.salidas
            readonly property var current: modelData.input ? Audio.entradaActiva : Audio.salidaActiva
            Layout.fillWidth: true
            spacing: 8
            IslandLabel {
                text: group.modelData.title
                color: Theme.muted
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            IslandLabel {
                visible: group.list.length === 0
                text: "No " + (group.modelData.input ? "input" : "output") + " devices available"
                color: Theme.muted
                font.pixelSize: 11
            }
            Repeater {
                model: group.list
                delegate: K4.Baldosa {
                    id: row
                    required property var modelData
                    readonly property bool current: !!group.current && group.current.id === modelData.id
                    readonly property int volume: Audio.volumenDe(modelData)
                    readonly property bool muted: Audio.mudoDe(modelData)
                    readonly property int naturalLevel: Audio.baseDe(modelData)
                    readonly property bool amplified: naturalLevel > 0 && volume > naturalLevel
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    radius: 10
                    activa: current
                    Accessible.name: "Use " + Audio.nombreDe(modelData) + " as " + group.modelData.title.toLowerCase()
                    onPulsada: group.modelData.input
                        ? Audio.elegirEntrada(modelData) : Audio.elegirSalida(modelData)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            IconGlyph {
                                text: row.current ? Theme.ico.check : Theme.ico.speaker
                                color: row.current ? Theme.blue : Theme.muted
                                font.pixelSize: 14
                                Layout.preferredWidth: 20
                            }
                            IslandLabel {
                                Layout.fillWidth: true
                                text: Audio.nombreDe(row.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: 12
                            }
                            IslandLabel {
                                visible: row.amplified
                                text: "+" + Audio.dbSobreNatural(row.modelData).toFixed(0) + " dB"
                                color: Theme.yellow
                                font.pixelSize: 11
                            }
                            IslandLabel {
                                text: row.volume + "%"
                                color: Theme.muted
                                font.pixelSize: 11
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                            }
                            K4.Boton {
                                glifo: row.muted ? Theme.ico.volOff : Theme.ico.volMed
                                tamano: 16
                                color: row.muted ? Theme.red : Theme.muted
                                activo: !!row.modelData.audio
                                Accessible.name: (row.muted ? "Unmute " : "Mute ") + Audio.nombreDe(row.modelData)
                                onPulsado: Audio.alternarMudoDe(row.modelData)
                            }
                        }
                        K4.Deslizador {
                            id: volume
                            Layout.fillWidth: true
                            enabled: !!row.modelData.audio
                            Accessible.name: "Volume of " + Audio.nombreDe(row.modelData)
                            valor: row.volume
                            hasta: 150
                            sufijo: "%"
                            onMovido: function (value) {
                                if (row.muted) Audio.alternarMudoDe(row.modelData)
                                Audio.ponerVolumenDe(row.modelData, value)
                            }
                            Rectangle {
                                visible: row.naturalLevel > 0 && row.naturalLevel <= 150
                                x: 6 + Math.max(0, volume.width - 12) * row.naturalLevel / 150 - 1
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 10
                                radius: 1
                                color: row.amplified ? Theme.yellow : Theme.muted
                            }
                        }
                    }
                }
            }
        }
    }
}
