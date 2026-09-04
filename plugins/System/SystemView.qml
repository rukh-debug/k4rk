//  The machine's state at a glance.
//
//  On top the four that matter —CPU, RAM, GPU and network— each
//  with its last two minutes of history; below whoever is eating
//  it, with its button to cut it off.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 11
        anchors.bottomMargin: 12
        spacing: 7

        // ── header ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF035B)
                color: Theme.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "System"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Sistema.cpuHilos > 0 ? Sistema.cpuHilos + " threads" : ""
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            // disk does not change in two minutes: it deserves no
            // graph, only a figure
            IslandLabel {
                visible: Sistema.discoTotal > 0
                text: "disk " + Math.round(Sistema.discoUsado) + " / "
                    + Math.round(Sistema.discoTotal) + " GB"
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                visible: Sistema.tempNvme > 0
                text: "nvme " + Sistema.grados(Sistema.tempNvme)
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── the four measurements ──────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 2
            columnSpacing: 8
            rowSpacing: 7

            Repeater {
                model: [
                    { id: "cpu", nombre: "CPU", tono: "#0a84ff" },
                    { id: "ram", nombre: "Memory", tono: "#bf5af2" },
                    { id: "gpu", nombre: "GPU", tono: "#30d158" },
                    { id: "red", nombre: "Network", tono: "#ff9f0a" }
                ]

                delegate: Rectangle {
                    id: tarjeta
                    required property var modelData

                    readonly property bool esRed: modelData.id === "red"
                    readonly property bool esGpu: modelData.id === "gpu"

                    visible: !esGpu || Sistema.hayGpu

                    Layout.fillWidth: true
                    Layout.preferredHeight: 74
                    radius: 11
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            IslandLabel {
                                text: tarjeta.modelData.nombre
                                color: Theme.muted
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            // each one's detail: which model, which
                            // interface
                            IslandLabel {
                                text: tarjeta.esGpu ? Sistema.gpuNombre
                                    : tarjeta.esRed ? Sistema.redIface : ""
                                color: Theme.dim
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandLabel {
                                text: {
                                    if (tarjeta.modelData.id === "cpu")
                                        return Sistema.grados(Sistema.cpuTemp)
                                    if (tarjeta.esGpu)
                                        return Sistema.grados(Sistema.gpuTemp)
                                    return ""
                                }
                                color: Theme.dim
                                font.pixelSize: 10
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            IslandLabel {
                                text: {
                                    if (tarjeta.modelData.id === "cpu")
                                        return Math.round(Sistema.cpuUso) + "%"
                                    if (tarjeta.modelData.id === "ram")
                                        return Math.round(Sistema.ramPct) + "%"
                                    if (tarjeta.esGpu)
                                        return Math.round(Sistema.gpuUso) + "%"
                                    return "↓ " + Sistema.tasa(Sistema.redRx)
                                }
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }

                            IslandLabel {
                                text: {
                                    if (tarjeta.modelData.id === "ram")
                                        return Sistema.ramUsada.toFixed(1) + " / "
                                            + Sistema.ramTotal.toFixed(1) + " GB"
                                    if (tarjeta.esGpu)
                                        return Math.round(Sistema.gpuMemUsada) + " / "
                                            + Math.round(Sistema.gpuMemTotal) + " MB"
                                    if (tarjeta.esRed)
                                        return "↑ " + Sistema.tasa(Sistema.redTx)
                                    if (Sistema.swapTotal > 0 && Sistema.swapUsada > 0.05)
                                        return "swap " + Sistema.swapUsada.toFixed(1) + " GB"
                                    return ""
                                }
                                color: Theme.dim
                                font.pixelSize: 9
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 3
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Grafica {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20
                            tono: tarjeta.modelData.tono
                            // network has no cap: it scales with
                            // whatever there is
                            techo: tarjeta.esRed ? 0 : 100
                            valores: {
                                if (tarjeta.modelData.id === "cpu") return Sistema.cpuHist
                                if (tarjeta.modelData.id === "ram") return Sistema.ramHist
                                if (tarjeta.esGpu) return Sistema.gpuHist
                                return Sistema.redHist
                            }
                        }
                    }
                }
            }
        }

        // ── who eats it ────────────────────────────────────────────
        //  Margins and widths are the same as the rows': if they do
        //  not match to the pixel, a misaligned column label
        //  confuses more than not putting one.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 9
            Layout.rightMargin: 6
            Layout.topMargin: 2
            spacing: 8

            IslandLabel {
                text: "Top consumers"
                color: Theme.muted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            IslandLabel {
                text: "PID"
                color: Theme.dim
                font.pixelSize: 9
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
            }

            IslandLabel {
                text: "CPU"
                color: Theme.dim
                font.pixelSize: 9
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
            }

            IslandLabel {
                text: "Memory"
                color: Theme.dim
                font.pixelSize: 9
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
            }

            // the kill button's slot, which in the rows always
            // takes space
            Item { Layout.preferredWidth: 28 }
        }

        ListView {
            //  The house scrollbar: comes out on its own when there
            //  is more than fits.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: Sistema.procesos
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: fila
                required property var modelData

                width: ListView.view.width
                height: 26
                radius: 7
                color: filaMouse.containsMouse ? Theme.surface : "transparent"

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 6
                    spacing: 8

                    IslandLabel {
                        text: fila.modelData.nombre
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    IslandLabel {
                        text: fila.modelData.pid
                        color: Theme.dim
                        font.pixelSize: 9
                        Layout.preferredWidth: 54
                        horizontalAlignment: Text.AlignRight
                    }

                    IslandLabel {
                        text: fila.modelData.cpu.toFixed(1) + "%"
                        color: fila.modelData.cpu > 50 ? Theme.red : Theme.ink
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                    }

                    IslandLabel {
                        text: fila.modelData.ram >= 1024
                            ? (fila.modelData.ram / 1024).toFixed(1) + " GB"
                            : fila.modelData.ram + " MB"
                        color: Theme.muted
                        font.pixelSize: 10
                        Layout.preferredWidth: 58
                        horizontalAlignment: Text.AlignRight
                    }

                    MediaButton {
                        glyph: Theme.ico.close
                        glyphSize: 12
                        glyphColor: Theme.red
                        opacity: filaMouse.containsMouse ? 1 : 0
                        onActivated: Sistema.matar(fila.modelData.pid)

                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                MouseArea {
                    id: filaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    z: -1
                }
            }
        }

        IslandLabel {
            Layout.fillWidth: true
            visible: !Sistema.cargado
            text: "Measuring…"
            color: Theme.dim
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
