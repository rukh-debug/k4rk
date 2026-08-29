//  The control centre, as an editor: a sketch of it on top, the blocks with
//  their order and their eye below, and the plain knobs (width, tiles,
//  header) as ordinary option rows that follow this view in the page.
//
//  The sketch is a drawing and not the real view embedded: the real one is a
//  plugin view that lives in the island, and a copy that lied about spacing
//  would be worse than an honest sketch. It shows what matters here — WHICH
//  blocks, in WHICH order, HOW wide — and nothing else.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: editor

    spacing: 12

    //  Every block the centre can show, with what the list rows and the
    //  sketch need to draw them. Ids are the ones `panelOrder` stores and
    //  PanelView looks up — one list, two readers, same truth.
    readonly property var bloques: [
        { id: "toggles", nombre: "Quick toggles", altura: 40,
          glifo: 0xF056E },     // md-view_dashboard
        { id: "media", nombre: "Media", altura: 32,
          glifo: 0xF0387 },     // md-music_note
        { id: "shortcuts", nombre: "Shortcuts", altura: 22,
          glifo: 0xF003B }      // md-apps
    ]

    function bloque(id) {
        for (let i = 0; i < editor.bloques.length; ++i)
            if (editor.bloques[i].id === id)
                return editor.bloques[i]
        return null
    }

    //  A block is on show when its switch says so AND it has something to
    //  show — the toggles with every tile off are a row of nothing.
    function visibleEl(id) {
        if (id === "toggles")
            return Settings.panelShowToggles
                   && (Settings.panelTileWifi || Settings.panelTileBluetooth
                       || Settings.panelTileSound)
        if (id === "media")
            return Settings.panelShowMedia
        if (id === "shortcuts")
            return Settings.panelShowShortcuts
        return false
    }

    //  panelOrder as the bar obeys it, from the service: unknown ids
    //  dropped, forgotten ids appended. The editor edits; this is what both
    //  sides read.
    readonly property var orden: Settings.panelOrdenEfectivo

    //  Swap two neighbours. The whole list is stored at once — an order is
    //  one value, not three positions that can disagree.
    function mover(id, salto) {
        const lista = editor.orden.slice()
        const de = lista.indexOf(id)
        const a = de + salto
        if (de < 0 || a < 0 || a >= lista.length)
            return
        lista.splice(de, 1)
        lista.splice(a, 0, id)
        Settings.poner("panelOrder", lista)
    }

    //  ── the sketch ──────────────────────────────────────────
    //
    //  Same proportions as the real centre, shrunk to the page: the width
    //  maps panelWidth's range onto the sketch, so turning the width
    //  stepper visibly widens it.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: cabeceraSketch.height + 16
            + (function () {
                let h = 0
                for (let i = 0; i < editor.orden.length; ++i) {
                    const b = editor.bloque(editor.orden[i])
                    if (b && editor.visibleEl(b.id))
                        h += b.altura + 8
                }
                return h
            })()
        radius: 16
        color: Qt.rgba(1, 1, 1, 0.03)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            //  The header: dots and clock only, the two things this page
            //  can remove from it. The bells and the close stay out of the
            //  argument — they are not optional.
            RowLayout {
                id: cabeceraSketch
                Layout.fillWidth: true
                spacing: 8

                IslandLabel {
                    text: "Control centre"
                    color: Theme.muted
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Row {
                    visible: Settings.panelShowWorkspaces
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 5
                            height: 5
                            radius: 3
                            color: index === 1 ? Theme.ink : Theme.surfaceHi
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                IslandLabel {
                    visible: Settings.panelShowClock
                    text: Qt.formatDateTime(Clock.date, "HH:mm")
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            //  One placeholder per block on show, in the stored order. The
            //  label is the block's name; the shape hints at the real one —
            //  three tiles, a row with a triangle, a row of squares —
            //  because a stack of identical boxes says nothing about WHICH
            //  block landed where.
            Repeater {
                model: editor.orden

                delegate: Rectangle {
                    id: hueco
                    required property var modelData

                    readonly property var bloque:
                        editor.bloque(hueco.modelData)
                    visible: editor.visibleEl(hueco.modelData)
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? bloque.altura : 0
                    radius: 8
                    color: Theme.islandBg

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        IconGlyph {
                            text: String.fromCodePoint(hueco.bloque.glifo)
                            color: Theme.dim
                            font.pixelSize: 10
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IslandLabel {
                            text: hueco.bloque.nombre
                            color: Theme.muted
                            font.pixelSize: 9
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item { Layout.fillWidth: true }

                        //  The shape hints.
                        Row {
                            visible: hueco.modelData === "toggles"
                            spacing: 5
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: [ Settings.panelTileWifi,
                                         Settings.panelTileBluetooth,
                                         Settings.panelTileSound ]

                                delegate: Rectangle {
                                    required property var modelData
                                    visible: modelData
                                    width: 34
                                    height: 12
                                    radius: 4
                                    color: Theme.surfaceHi
                                }
                            }
                        }

                        Row {
                            visible: hueco.modelData === "media"
                            spacing: 5
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                width: 18; height: 12; radius: 4
                                color: Theme.surfaceHi
                            }
                            Rectangle {
                                width: 8; height: 12; radius: 4
                                color: Theme.blue
                            }
                        }

                        Row {
                            visible: hueco.modelData === "shortcuts"
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    required property int index
                                    width: 12; height: 12; radius: 4
                                    color: index === 4 ? Theme.track
                                                       : Theme.surfaceHi
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    //  ── the blocks: order and eye ──────────────────────────
    Repeater {
        model: editor.orden

        delegate: Rectangle {
            id: fila
            required property var modelData

            readonly property var bloque: editor.bloque(fila.modelData)
            readonly property int posicion: editor.orden.indexOf(
                fila.modelData)

            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: 10
            color: filaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: filaMouse
                anchors.fill: parent
                hoverEnabled: true
                //  The row does not toggle: its eye is the precise control,
                //  and a 46 px accidental switch is a surprise nobody asked
                //  for. The hover is just the pointer saying hello.
                onClicked: function (mouse) { mouse.accepted = false }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                IconGlyph {
                    text: String.fromCodePoint(fila.bloque.glifo)
                    color: Theme.ink
                    font.pixelSize: 15
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    IslandLabel {
                        text: fila.bloque.nombre
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    IslandLabel {
                        text: fila.posicion === 0 ? "Top of the centre"
                            : fila.posicion === editor.orden.length - 1
                              ? "Bottom of the centre" : "In between"
                        color: Theme.dim
                        font.pixelSize: 9
                    }
                }

                //  ── the order arrows ────────────────────
                //
                //  Two chips and not a drag: the list is three rows, and a
                //  grab handle for three items is a ceremony. Up moves the
                //  block one place, down the other way, and a spent arrow
                //  stops answering — same rule as the steppers.
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 13
                    opacity: fila.posicion > 0 ? 1 : 0.35
                    color: arriba.containsMouse && fila.posicion > 0
                        ? Theme.surfaceHi : Theme.track

                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: arriba
                        enabled: fila.posicion > 0
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editor.mover(fila.modelData, -1)
                    }

                    IconGlyph {
                        anchors.centerIn: parent
                        text: Theme.ico.chevronUp
                        color: fila.posicion > 0 ? Theme.ink : Theme.muted
                        font.pixelSize: 14
                        renderType: Text.NativeRendering
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 13
                    opacity: fila.posicion < editor.orden.length - 1 ? 1 : 0.35
                    color: abajo.containsMouse
                           && fila.posicion < editor.orden.length - 1
                        ? Theme.surfaceHi : Theme.track

                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: abajo
                        enabled: fila.posicion < editor.orden.length - 1
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editor.mover(fila.modelData, 1)
                    }

                    IconGlyph {
                        anchors.centerIn: parent
                        text: Theme.ico.chevronDown
                        color: fila.posicion < editor.orden.length - 1
                            ? Theme.ink : Theme.muted
                        font.pixelSize: 14
                        renderType: Text.NativeRendering
                    }
                }

                IslandSwitch {
                    //  The block's own switch, in the row, where the order
                    //  also lives: what shows and where shows together.
                    checked: editor.visibleEl(fila.modelData)
                          || (fila.modelData === "toggles"
                              && Settings.panelShowToggles)
                    onToggled: {
                        if (fila.modelData === "toggles")
                            Settings.poner("panelShowToggles", !checked)
                        else if (fila.modelData === "media")
                            Settings.poner("panelShowMedia", !checked)
                        else if (fila.modelData === "shortcuts")
                            Settings.poner("panelShowShortcuts", !checked)
                    }
                }
            }
        }
    }
}
