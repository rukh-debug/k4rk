// The at-rest pill, as an editor: a sketch of the folded row on top,
// the blocks with their order and their eye below.
//
// The sketch is a drawing, not the live IdleIslandView embedded: the live
// view reads runtime data (playing media, tray apps, workspace flash) and
// a copy that lied about conditions would be worse than an honest sketch.
// It shows which blocks, in which order, and which are hidden.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: editor

    spacing: 12

    readonly property var bloques: [
        { id: "media", nombre: "Media", glifo: 0xF0387,
          desc: "Artwork and visualizer while media is playing" },
        { id: "clock-workspaces", nombre: "Clock and workspaces", glifo: 0xF0150,
          desc: "Time at rest; workspaces briefly replace it after switching" },
        { id: "minimized", nombre: "Minimized items", glifo: 0xF0047,
          desc: "Things set aside to resume later" },
        { id: "plugin-indicators", nombre: "Plugin indicators", glifo: 0xF0431,
          desc: "Plugin status chips as one lane" },
        { id: "tray", nombre: "Tray", glifo: 0xF0FB0,
          desc: "Icons from background applications" }
    ]

    function bloque(id) {
        for (let i = 0; i < editor.bloques.length; ++i)
            if (editor.bloques[i].id === id)
                return editor.bloques[i]
        return null
    }

    function visibleEl(id) {
        return Settings.pillItemEnabled(id)
    }

    function alternarBloque(id, encendido) {
        Settings.setPillItemEnabled(id, encendido)
    }

    function mover(id, salto) {
        Settings.movePillItem(id, salto)
    }

    readonly property var orden: Settings.pillEffectiveOrder

    IslandLabel {
        text: "At-rest pill"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Theme.muted
    }

    // ── the sketch ──────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.03)
        border.width: 1
        border.color: Theme.surfaceHi

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10

            Repeater {
                model: editor.orden
                delegate: Rectangle {
                    required property var modelData
                    readonly property var info: editor.bloque(modelData)
                    visible: editor.visibleEl(modelData)
                    Layout.preferredWidth: Math.max(28, etiqueta.implicitWidth + 20)
                    Layout.preferredHeight: 22
                    radius: 11
                    color: Theme.islandBg
                    border.width: 1
                    border.color: Theme.surfaceHi
                    IslandLabel {
                        id: etiqueta
                        anchors.centerIn: parent
                        text: parent.info ? parent.info.nombre : parent.modelData
                        color: Theme.muted
                        font.pixelSize: 9
                    }
                }
            }

            Item { Layout.fillWidth: true }

            IslandLabel {
                visible: editor.orden.filter(function (id) {
                    return editor.visibleEl(id)
                }).length === 0
                text: "Everything hidden — the pill keeps a minimum target"
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }

    IslandLabel {
        Layout.fillWidth: true
        text: "Plugin capsule extensions keep their own left/right flank outside this order."
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }

    // ── the blocks: order and eye ──────────────────────────
    IslandLabel {
        text: "Blocks and order"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Theme.muted
        Layout.topMargin: 8
    }

    Repeater {
        model: editor.orden

        delegate: Rectangle {
            id: fila
            required property var modelData

            readonly property var info: editor.bloque(fila.modelData)
            readonly property int posicion: editor.orden.indexOf(fila.modelData)

            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(56, blockLabels.implicitHeight + 24)
            radius: 10
            color: filaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: filaMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: function (mouse) { mouse.accepted = false }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                IconGlyph {
                    text: String.fromCodePoint(fila.info ? fila.info.glifo : 0xF0431)
                    color: Theme.ink
                    font.pixelSize: 15
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    id: blockLabels
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    IslandLabel {
                        Layout.fillWidth: true
                        text: fila.info ? fila.info.nombre : fila.modelData
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: fila.info ? fila.info.desc : ""
                        color: Theme.muted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                K4.Boton {
                    tamano: 16
                    glifo: Theme.ico.chevronUp
                    activo: fila.posicion > 0
                    Accessible.name: "Move " + (fila.info ? fila.info.nombre : fila.modelData) + " up"
                    onPulsado: editor.mover(fila.modelData, -1)
                }

                K4.Boton {
                    tamano: 16
                    glifo: Theme.ico.chevronDown
                    activo: fila.posicion < editor.orden.length - 1
                    Accessible.name: "Move " + (fila.info ? fila.info.nombre : fila.modelData) + " down"
                    onPulsado: editor.mover(fila.modelData, 1)
                }

                IslandSwitch {
                    Accessible.name: "Show " + (fila.info ? fila.info.nombre : fila.modelData)
                    checked: editor.visibleEl(fila.modelData)
                    onToggled: editor.alternarBloque(fila.modelData, !checked)
                }
            }
        }
    }
}
