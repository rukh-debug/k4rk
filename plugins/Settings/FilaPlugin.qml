//  An installed plugin, in a row that unfolds.
//
//  It used to be two places: a switch with the name here, and that same
//  plugin's settings in ANOTHER section of the sidebar. To turn off what
//  you had just configured you had to cross the window, and to know what
//  «senda» was you had to open its repository.
//
//  Closed, it says the least — name, version, whether it is on. Open, it
//  says what it does, where it came from, what it asks for, how it is
//  called, and what it BRINGS: its settings beside the switch that
//  enables them, and the Settings pages and launcher results that come
//  with turning it on.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
    id: fila

    required property var modelData

    //  `modelData` comes from `PluginManager.opcionesAjustes`: just
    //  enough for the closed row. The rest is looked up when needed.
    readonly property string ident: String(modelData.pluginId || "")
    readonly property var meta: PluginManager.metadata(fila.ident)

    //  Its settings, the ones it registered with `K4.Ajustes`. It may
    //  have none.
    readonly property var suGrupo: {
        const gs = Enganches.gruposAjustes
        for (let i = 0; i < gs.length; ++i)
            if (gs[i].dePlugin === fila.ident)
                return gs[i]
        return null
    }

    //  The Settings pages it ships with `K4.Pagina`, and whether it adds
    //  results to the launcher. Both lists are about the SAME thing —
    //  what enabling this plugin puts into the bar — so they are told
    //  together, as information: the switch above is the decision, this
    //  is what the decision buys.
    readonly property var susPaginas: {
        const salida = []
        const todas = Enganches.paginas
        for (let i = 0; i < todas.length; ++i)
            if (todas[i].plugin === fila.ident)
                salida.push(todas[i])
        return salida
    }

    readonly property bool enLanzador: {
        const ls = Enganches.lanzador
        for (let i = 0; i < ls.length; ++i)
            if (ls[i].plugin === fila.ident)
                return true
        return false
    }

    readonly property bool encendido: !!Settings.valor(modelData.id)

    //  Broken or missing requirements: it says so and cannot be touched.
    //  `fijo` means there is nothing to do from here; `recargable` means
    //  it can be retried.
    readonly property bool averiado: modelData.error === "fijo"

    //  The row's open state lives in the VIEW, not here: this row is
    //  rebuilt every time the roster changes — which is exactly when you
    //  flip the switch inside it — and a delegate that remembers nothing
    //  would snap shut under your hand.
    readonly property bool abierta:
        vista.filasAbiertas[fila.ident] === true

    Layout.fillWidth: true
    Layout.preferredHeight: cuerpo.implicitHeight + 18

    radius: 12
    color: fila.abierta ? Theme.surfaceHi
        : (raton.containsMouse ? Theme.surfaceHi : Theme.surface)

    Behavior on color { ColorAnimation { duration: 140 } }

    ColumnLayout {
        id: cuerpo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 9
        spacing: 10

        // ── what is always visible ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 11

            //  The arrow. It turns when opened, which is how you say
            //  «there is more here» without writing it.
            IconGlyph {
                Layout.alignment: Qt.AlignVCenter
                text: String.fromCodePoint(0xF0142)   // md-chevron_right
                color: Theme.dim
                font.pixelSize: 14
                renderType: Text.NativeRendering
                rotation: fila.abierta ? 90 : 0
                Behavior on rotation {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            //  Its icon: the image if it brings one, the codex if not.
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 18
                implicitHeight: 18

                Image {
                    anchors.fill: parent
                    visible: String(fila.modelData.imagen || "").length > 0
                    source: fila.modelData.imagen || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                IconGlyph {
                    anchors.centerIn: parent
                    visible: String(fila.modelData.imagen || "").length === 0
                    text: String.fromCodePoint(fila.modelData.glifo)
                    color: fila.encendido ? Theme.ink : Theme.muted
                    font.pixelSize: 15
                    renderType: Text.NativeRendering
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                IslandLabel {
                    Layout.fillWidth: true
                    text: fila.modelData.nombre
                    textFormat: Text.PlainText
                    color: fila.averiado ? Theme.red
                        : (fila.encendido ? Theme.ink : Theme.muted)
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                //  Closed, the description in one line. Open, it stays
                //  quiet: the whole thing goes below, uncut.
                IslandLabel {
                    Layout.fillWidth: true
                    visible: !fila.abierta
                    text: fila.modelData.desc
                    textFormat: Text.PlainText
                    color: fila.averiado ? Theme.red : Theme.dim
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            //  How many settings it brings, when it brings any. The hint
            //  that there is something inside, without opening to find
            //  out.
            Rectangle {
                visible: !fila.abierta && fila.suGrupo !== null
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: cuenta.implicitWidth + 14
                implicitHeight: 18
                radius: 9
                color: Theme.track

                IslandLabel {
                    id: cuenta
                    anchors.centerIn: parent
                    text: fila.suGrupo ? String(fila.suGrupo.opciones.length) : ""
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            //  The switch. The same as ever, in the same place.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 40
                implicitHeight: 22
                radius: 11
                opacity: fila.averiado ? 0.35 : 1
                color: fila.encendido ? Theme.green : Theme.track

                Behavior on color { ColorAnimation { duration: 140 } }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: fila.encendido ? parent.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !fila.averiado
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Settings.alternar(fila.modelData.id)
                }
            }
        }

        // ── what appears when it unfolds ────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 25
            Layout.bottomMargin: 9
            visible: fila.abierta
            spacing: 8

            IslandLabel {
                Layout.fillWidth: true
                visible: text.length > 0
                text: fila.modelData.desc
                textFormat: Text.PlainText
                color: fila.averiado ? Theme.red : Theme.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            //  Where it came from and what it keeps. An outside plugin
            //  runs inside the bar and can do what the bar can: knowing
            //  whose it is and what it asks for is not a spare detail.
            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: {
                        const m = fila.meta
                        if (!m)
                            return []
                        const chips = []
                        if (m.permisos)
                            for (let i = 0; i < m.permisos.length; ++i)
                                chips.push({ t: m.permisos[i], aviso: true })
                        const c = m.comandos || ({})
                        if (c.atajos)
                            for (let j = 0; j < c.atajos.length; ++j)
                                chips.push({ t: "k4:" + c.atajos[j], aviso: false })
                        if (c.ipc)
                            for (let k = 0; k < c.ipc.length; ++k)
                                chips.push({ t: c.ipc[k], aviso: false })
                        return chips
                    }

                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: etiqueta.implicitWidth + 16
                        implicitHeight: 20
                        radius: 10
                        color: modelData.aviso
                            ? Qt.rgba(Theme.yellow.r, Theme.yellow.g,
                                      Theme.yellow.b, 0.14)
                            : Theme.track

                        IslandLabel {
                            id: etiqueta
                            anchors.centerIn: parent
                            text: parent.modelData.t
                            textFormat: Text.PlainText
                            color: parent.modelData.aviso ? Theme.yellow : Theme.muted
                            font.pixelSize: 9
                        }
                    }
                }
            }

            // ── what enabling it brings ──────────────────────────────
            //
            //  Pages and launcher results are told, not switched: the
            //  plugin's own switch is the decision — this is what the
            //  decision buys, said plainly enough that nobody has to
            //  guess what a plugin will do to their bar.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: fila.susPaginas.length > 0 || fila.enLanzador
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.06)
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: "What it adds"
                    color: Theme.dim
                    font.pixelSize: 10
                }

                Repeater {
                    model: fila.susPaginas

                    delegate: RowLayout {
                        id: filaPagina
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 11

                        K4.IconoPlugin {
                            glifo: filaPagina.modelData.fuente.glifo
                            color: Theme.ink
                            tamano: 15
                            Layout.preferredWidth: 18
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            IslandLabel {
                                Layout.fillWidth: true
                                text: (filaPagina.modelData.fuente.titulo
                                       || filaPagina.modelData.name)
                                    + "  ·  "
                                    + (filaPagina.modelData.fuente.padre
                                       ? "in " + filaPagina.modelData.fuente.padre
                                       : "its own section")
                                textFormat: Text.PlainText
                                color: Theme.ink
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            IslandLabel {
                                Layout.fillWidth: true
                                text: filaPagina.modelData.fuente.desc
                                textFormat: Text.PlainText
                                color: Theme.dim
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }

                IslandLabel {
                    Layout.fillWidth: true
                    visible: fila.enLanzador
                    text: "Its own results in the launcher's search"
                    textFormat: Text.PlainText
                    color: Theme.ink
                    font.pixelSize: 12
                }
            }

            //  And its settings, right here. The same rows as the rest
            //  of the window: a plugin's switch has no reason to look
            //  different from one of the bar's own.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: fila.suGrupo !== null && fila.encendido
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.06)
                }

                Repeater {
                    model: fila.suGrupo ? fila.suGrupo.opciones : []
                    delegate: FilaOpcion {}
                }
            }

            //  It has settings but is off: say so, instead of showing
            //  controls that govern nothing.
            IslandLabel {
                Layout.fillWidth: true
                visible: fila.suGrupo !== null && !fila.encendido
                text: "Turn it on to see its settings"
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }

    //  The click that unfolds. It sits BELOW the controls — declared
    //  before them — so the switch and the rows inside keep their
    //  clicks to themselves.
    MouseArea {
        id: raton
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: vista.ponerFilaAbierta(fila.ident, !fila.abierta)
    }
}
