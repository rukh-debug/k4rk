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
    //  sketch need to draw them. The native blocks, plus every card the
    //  registry holds — the list is a binding, so a card born later
    //  shows up the moment its plugin registers it. Ids are the ones
    //  `panelOrder` stores and PanelView looks up — one list, two
    //  readers, same truth. The sketch heights are half the real ones,
    //  which is the sketch's own scale.
    readonly property var bloques: {
        const nativos = [
            { id: "toggles", nombre: "Quick controls", altura: PanelIsland.altoDe("toggles") / 2, desc: "Wi-Fi, Bluetooth, sound and brightness",
               glifo: 0xF056E },     // md-view_dashboard
            { id: "power-display", nombre: "Power & display", altura: PanelIsland.altoDe("power-display") / 2,
              desc: "Power profiles and scheduled night light", glifo: 0xF0425 },
            { id: "media", nombre: "Media", altura: PanelIsland.altoDe("media") / 2, desc: "Now playing and playback controls",
              glifo: 0xF0387 },     // md-music_note
            { id: "shortcuts", nombre: "Shortcuts", altura: PanelIsland.altoDe("shortcuts") / 2, desc: "Pinned applications",
              glifo: 0xF003B }      // md-apps
        ]
        const cards = Enganches.cards
        for (let i = 0; i < cards.length; ++i) {
            const f = cards[i].fuente
            nativos.push({
                id: cards[i].plugin + "." + cards[i].name,
                nombre: f.titulo || cards[i].name,
                altura: Math.max(8, Math.round((f.alto || 0) / 2)),
                glifo: f.glifo || SurfaceRegistry.iconFor(cards[i].plugin).glifo || 0xF0431,
                desc: f.desc || "Plugin card"
            })
        }
        return nativos
    }

    function bloque(id) {
        for (let i = 0; i < editor.bloques.length; ++i)
            if (editor.bloques[i].id === id)
                return editor.bloques[i]
        return null
    }

    //  A block is on show when its switch says so AND it has something to
    //  show — the rule lives in Settings (`bloqueVisible`), read here by
    //  the sketch and the eye like the centre and its height count read
    //  it. A rule told three ways drifts.
    function visibleEl(id) {
        return Settings.bloqueVisible(id)
    }

    //  The eye, generalized: the native blocks keep their own keys, a
    //  card ("<plugin>.<name>") joins or leaves `panelHiddenBlocks` —
    //  Settings owns a card's visibility, the plugin does not.
    function alternarBloque(id, encendido) {
        if (id === "power-display") {
            Settings.poner("panelShowPowerDisplay", encendido)
            return
        }
        if (id === "toggles") {
            Settings.poner("panelShowToggles", encendido)
            return
        }
        if (id === "media") {
            Settings.poner("panelShowMedia", encendido)
            return
        }
        if (id === "shortcuts") {
            Settings.poner("panelShowShortcuts", encendido)
            return
        }
        const ocultos = (Settings.panelHiddenBlocks || []).slice()
        const donde = ocultos.indexOf(id)
        if (encendido && donde >= 0)
            ocultos.splice(donde, 1)
        else if (!encendido && donde < 0)
            ocultos.push(id)
        Settings.poner("panelHiddenBlocks", ocultos)
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
        const unavailable = (Settings.panelOrder || []).filter(function (saved) {
            return lista.indexOf(saved) < 0
        })
        Settings.poner("panelOrder", lista.concat(unavailable))
    }

    //  ── the sketch ──────────────────────────────────────────
    //
    //  Same proportions as the real centre, shrunk to the page: the width
    //  maps panelWidth's range onto the sketch, so turning the width
    //  stepper visibly widens it.
    Rectangle {
        Layout.preferredWidth: Math.min(editor.width,
            Math.max(Math.min(340, editor.width), editor.width * Settings.panelWidth / 1100))
        Layout.alignment: Qt.AlignHCenter
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

            //  The header: the workspace indicator and the clock, the two
            //  things this page can remove from it. The bells and the close
            //  stay out of the argument — they are not optional.
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
                    id: deskRow
                    visible: Settings.panelShowWorkspaces
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    //  The mock wears the real dress — dots, or numbered
                    //  bubbles — and the bubbles are one uniform size,
                    //  measured like the real header measures them.
                    readonly property real bubbleWidth: {
                        let w = 0
                        for (let i = 1; i <= 4; ++i) {
                            const digits = String(i)
                            w = Math.max(w, numberMetric.advanceWidth(digits),
                                            focusMetric.advanceWidth(digits))
                        }
                        return Math.max(13, w + 8)
                    }

                    FontMetrics {
                        id: numberMetric
                        font.family: Theme.uiFont
                        font.pixelSize: 8
                    }
                    FontMetrics {
                        id: focusMetric
                        font.family: Theme.uiFont
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            visible: Settings.panelWorkspaceStyle !== "numbers"
                            width: 5
                            height: 5
                            radius: 3
                            color: index === 1 ? Theme.ink : Theme.surfaceHi
                        }
                    }

                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            visible: Settings.panelWorkspaceStyle === "numbers"
                            width: deskRow.bubbleWidth
                            height: 13
                            radius: 6.5
                            color: index === 1 ? Theme.ink : Theme.surfaceHi

                            IslandLabel {
                                anchors.centerIn: parent
                                text: index + 1
                                color: index === 1 ? Theme.islandBg : Theme.muted
                                font.pixelSize: 8
                                font.weight: index === 1 ? Font.DemiBold : Font.Normal
                            }
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
                    //  `bloque` can be null for one frame: `orden` and
                    //  `bloques` re-evaluate in engine order when a card
                    //  registers, and the model can know an id before the
                    //  list does. Guarded, that frame draws a blank slot
                    //  instead of throwing.
                    Layout.preferredHeight: visible && bloque ? bloque.altura : 0
                    radius: 8
                    color: Theme.islandBg

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        IconGlyph {
                            text: String.fromCodePoint(hueco.bloque ? hueco.bloque.glifo : 0xF0431)
                            color: Theme.dim
                            font.pixelSize: 10
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IslandLabel {
                            text: hueco.bloque ? hueco.bloque.nombre : hueco.modelData
                            color: Theme.muted
                            font.pixelSize: 9
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item { Layout.fillWidth: true }

                        IconGlyph {
                            visible: hueco.modelData === "power-display"
                            text: String.fromCodePoint(0xF0425) + "  " + String.fromCodePoint(0xF0594)
                            color: Theme.muted
                            font.pixelSize: 10
                        }

                        // The quick-control sketch follows the live wrapping rule.
                        GridLayout {
                            visible: hueco.modelData === "toggles"
                            columns: 2
                            columnSpacing: 4
                            rowSpacing: 4
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                visible: Settings.panelTileWifi
                                Layout.row: 0
                                Layout.column: 0
                                Layout.columnSpan: PanelIsland.radioCount === 1 ? 2 : 1
                                Layout.fillWidth: true
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 24
                                radius: 5
                                color: Theme.surface
                            }
                            Rectangle {
                                visible: Settings.panelTileBluetooth
                                Layout.row: 0
                                Layout.column: Settings.panelTileWifi ? 1 : 0
                                Layout.columnSpan: PanelIsland.radioCount === 1 ? 2 : 1
                                Layout.fillWidth: true
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 24
                                radius: 5
                                color: Theme.surface
                            }
                            Rectangle {
                                visible: Settings.panelTileSound
                                Layout.row: PanelIsland.radioCount ? 1 : 0
                                Layout.column: 0
                                Layout.columnSpan: PanelIsland.sliderCount === 1 ? 2 : 1
                                Layout.fillWidth: true
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 24
                                radius: 5
                                color: Theme.surface
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 12
                                    height: 2
                                    radius: 1
                                    color: Theme.muted
                                }
                            }
                            Rectangle {
                                visible: Settings.panelTileBrightness
                                Layout.row: PanelIsland.radioCount ? 1 : 0
                                Layout.column: Settings.panelTileSound ? 1 : 0
                                Layout.columnSpan: PanelIsland.sliderCount === 1 ? 2 : 1
                                Layout.fillWidth: true
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 24
                                radius: 5
                                color: Theme.surface
                                IconGlyph {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xF00E0)
                                    color: Theme.muted
                                    font.pixelSize: 10
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
                                color: Theme.ink
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

            readonly property var bloque: editor.bloque(fila.modelData)
            readonly property int posicion: editor.orden.indexOf(
                fila.modelData)

            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(56, blockLabels.implicitHeight + 24)
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
                    text: String.fromCodePoint(fila.bloque ? fila.bloque.glifo : 0xF0431)
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
                        text: fila.bloque ? fila.bloque.nombre : fila.modelData
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: fila.modelData === "toggles" && Settings.panelShowToggles
                                && !editor.visibleEl("toggles")
                            ? "All tiles are hidden. Enable a tile below."
                            : (fila.bloque ? fila.bloque.desc : "Plugin card")
                        color: Theme.muted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                //  ── the order arrows ────────────────────
                //
                //  Two chips and not a drag: the list is three rows, and a
                //  grab handle for three items is a ceremony. Up moves the
                //  block one place, down the other way, and a spent arrow
                //  stops answering — same rule as the steppers.
                K4.Boton {
                    tamano: 16
                    glifo: Theme.ico.chevronUp
                    activo: fila.posicion > 0
                    Accessible.name: "Move " + (fila.bloque ? fila.bloque.nombre : fila.modelData) + " up"
                    onPulsado: editor.mover(fila.modelData, -1)
                }

                K4.Boton {
                    tamano: 16
                    glifo: Theme.ico.chevronDown
                    activo: fila.posicion < editor.orden.length - 1
                    Accessible.name: "Move " + (fila.bloque ? fila.bloque.nombre : fila.modelData) + " down"
                    onPulsado: editor.mover(fila.modelData, 1)
                }

                IslandSwitch {
                    Accessible.name: "Show " + (fila.bloque ? fila.bloque.nombre : fila.modelData)
                    //  The block's own switch, in the row, where the order
                    //  also lives: what shows and where shows together.
                    checked: editor.visibleEl(fila.modelData)
                          || (fila.modelData === "toggles"
                              && Settings.panelShowToggles)
                    onToggled: editor.alternarBloque(fila.modelData, !checked)
                }
            }
        }
    }
}
