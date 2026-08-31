//  Where each view opens from: which side of the screen, and where along
//  that side. One card per view — the side chips carry the big choice
//  («Follow bar» is the default and the first chip, so the page starts
//  showing what everything does).
//
//  The point along the side is not chips but the little monitor itself:
//  the dot is where the view opens, and you DRAG it — to the centre, to a
//  quarter, flush into a corner. Dragging near an edge picks that edge,
//  dragging along it picks the point, and corners are just the ends. A
//  placement is a point; chips could only ever offer the named few.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: pagina

    spacing: 10

    //  Everything that OPENS and takes the island: the live plugins that
    //  say so with `colocable`. Derived, not listed — a plugin that ships
    //  a summoned surface gets its card the day it is written, and one
    //  that is off has no surface to place, so it shows no card until it
    //  comes back. The pill is not in the list on purpose: it lives
    //  wherever the Island page says and drags its hover views with it;
    //  what is here is what you summon.
    readonly property var vistas: {
        const salida = []
        const lista = PluginManager.instancias
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (p.colocable)
                salida.push({ id: p.name, nombre: p.title || p.name })
        }
        return salida
    }

    //  «» is Follow bar: no entry of its own, the bar's edge and alignment.
    //  It is stored as an ABSENT key and not as a copy of the bar's
    //  placement, so moving the bar later moves its followers along.
    readonly property var lados: [
        { codigo: "",       nombre: "Follow bar" },
        { codigo: "top",    nombre: "Top" },
        { codigo: "bottom", nombre: "Bottom" },
        { codigo: "left",   nombre: "Left" },
        { codigo: "right",  nombre: "Right" }
    ]

    //  The placement words along the edge change with the edge: left and
    //  right run top to bottom, the horizontal ones end to end. For the
    //  little status line under the title.
    function palabraLado(lado) {
        if (lado === "left")
            return "left edge"
        if (lado === "right")
            return "right edge"
        return lado === "top" ? "top edge" : "bottom edge"
    }

    //  The view's own entry, if it has one. A hand-edited file cannot
    //  smuggle a stranger in: a side nobody knows is a view that follows.
    function suya(id) {
        const p = (Settings.islandPlacements || {})[id]
        if (p && (p.side === "top" || p.side === "bottom"
                  || p.side === "left" || p.side === "right"))
            return p
        return null
    }

    Repeater {
        model: pagina.vistas

        delegate: Rectangle {
            id: tarjeta
            required property var modelData

            readonly property string idVista: tarjeta.modelData.id
            readonly property var propia: pagina.suya(tarjeta.idVista)
            readonly property var efectiva:
                Settings.placementDe(tarjeta.idVista)

            Layout.fillWidth: true
            implicitHeight: columna.implicitHeight + 24
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: propia ? Theme.track : "transparent"

            RowLayout {
                id: columna
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    IslandLabel {
                        text: tarjeta.modelData.nombre
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    //  The state in words, because a dot alone does not say
                    //  «this one follows the bar».
                    IslandLabel {
                        text: tarjeta.propia === null
                            ? "Follows the bar — " + pagina.palabraLado(
                                  Settings.barPosition === "bottom"
                                  ? "bottom" : "top")
                            : pagina.palabraLado(tarjeta.propia.side)
                              + " · " + Math.round(tarjeta.propia.align) + "%"
                        color: tarjeta.propia === null ? Theme.dim : Theme.muted
                        font.pixelSize: 9
                    }

                    //  ── the side chips ────────────────────
                    //
                    //  Coarse choice; the fine one is the dot. Picking a
                    //  side here keeps the point the view already had.
                    RowLayout {
                        spacing: 5

                        Repeater {
                            model: pagina.lados

                            delegate: Rectangle {
                                id: chipLado
                                required property var modelData

                                readonly property bool puesta:
                                    tarjeta.propia === null
                                        ? chipLado.modelData.codigo === ""
                                        : tarjeta.propia.side
                                          === chipLado.modelData.codigo

                                implicitWidth: textoLado.implicitWidth + 20
                                implicitHeight: 24
                                radius: 12
                                color: puesta ? Theme.blue
                                    : (ratonLado.containsMouse
                                       ? Theme.surfaceHi : Theme.track)

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                IslandLabel {
                                    id: textoLado
                                    anchors.centerIn: parent
                                    text: chipLado.modelData.nombre
                                    color: chipLado.puesta ? Theme.ink
                                                           : Theme.muted
                                    font.pixelSize: 10
                                    font.weight: chipLado.puesta
                                        ? Font.DemiBold : Font.Normal
                                }

                                MouseArea {
                                    id: ratonLado
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Settings.ponerPlacement(
                                        tarjeta.idVista,
                                        chipLado.modelData.codigo,
                                        tarjeta.propia
                                            ? tarjeta.propia.align : 50)
                                }
                            }
                        }
                    }
                }

                //  ── the little monitor, and its dot is draggable ──
                //
                //  The strip is the pill on the bar's edge; the dot is where
                //  THIS view opens. Press anywhere on the monitor — or drag:
                //  the nearest edge becomes the side, the position along it
                //  the point, and the corner is just the end of the drag.
                //  Bigger than a decoration needs to be, on purpose: it is
                //  an input surface now, and a 72×44 one asks for tweezers.
                Item {
                    id: monitor

                    Layout.preferredWidth: 118
                    Layout.preferredHeight: 68
                    Layout.alignment: Qt.AlignVCenter

                    readonly property real margenPunto: 5
                    //  The bar's own edge, for the strip.
                    readonly property string ladoBarra:
                        Settings.barPosition === "bottom" ? "bottom" : "top"

                    function puntoEn(lado, align) {
                        const w = width, h = height, m = margenPunto
                        if (lado === "bottom")
                            return Qt.point(m + (w - 2 * m) * align / 100,
                                            h - m)
                        if (lado === "left")
                            return Qt.point(m, m + (h - 2 * m) * align / 100)
                        if (lado === "right")
                            return Qt.point(w - m,
                                            m + (h - 2 * m) * align / 100)
                        return Qt.point(m + (w - 2 * m) * align / 100, m)
                    }

                    //  A point on the monitor → the placement it names. The
                    //  nearest edge wins; the coordinate ALONG it is the
                    //  percentage. Clamped, so the drag cannot leave the
                    //  monitor and invent a 120%.
                    function colocacionEn(x, y) {
                        const w = width, h = height
                        const dArriba = y, dAbajo = h - y
                        const dIzq = x, dDer = w - x
                        const dMin = Math.min(dArriba, dAbajo, dIzq, dDer)
                        let lado, fraccion
                        if (dMin === dArriba) {
                            lado = "top"; fraccion = x / w
                        } else if (dMin === dAbajo) {
                            lado = "bottom"; fraccion = x / w
                        } else if (dMin === dIzq) {
                            lado = "left"; fraccion = y / h
                        } else {
                            lado = "right"; fraccion = y / h
                        }
                        return { side: lado,
                                 align: Math.round(
                                     Math.max(0, Math.min(1, fraccion)) * 100) }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: ratonMonitor.containsMouse
                            ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        border.width: 1
                        border.color: Theme.track
                    }

                    //  The pill: a strip along the bar's edge.
                    Rectangle {
                        readonly property var p: monitor.puntoEn(
                            monitor.ladoBarra, Settings.barAlignment)
                        x: p.x - 18
                        y: p.y - 1.5
                        width: 36
                        height: 3
                        radius: 1.5
                        color: Theme.track
                    }

                    //  The dot: where this view opens.
                    Rectangle {
                        readonly property var p: monitor.puntoEn(
                            tarjeta.efectiva.side, tarjeta.efectiva.align)
                        x: p.x - 4
                        y: p.y - 4
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.blue
                        border.width: 1
                        border.color: Theme.islandBg
                    }

                    MouseArea {
                        id: ratonMonitor
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: function (mouse) {
                            const c = monitor.colocacionEn(mouse.x, mouse.y)
                            Settings.ponerPlacement(tarjeta.idVista,
                                c.side, c.align)
                        }
                        onPositionChanged: function (mouse) {
                            if (!pressed)
                                return
                            const c = monitor.colocacionEn(mouse.x, mouse.y)
                            Settings.ponerPlacement(tarjeta.idVista,
                                c.side, c.align)
                        }
                    }
                }
            }
        }
    }
}
