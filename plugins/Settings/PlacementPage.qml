//  Where each view opens from: which sides of the screen, and where
//  along them. One card per view — the side chips carry the big choice
//  («Follow bar» is the default and the first chip, so the page starts
//  showing what everything does), and the chips TOGGLE: one side is an
//  edge, two adjacent sides are the corner between them — Top then
//  Right, or Right then Top, is the top-right corner.
//
//  The point along the side is not chips but the little monitor itself:
//  the dot is where the view opens, and you DRAG it — to the centre, to
//  a quarter, along an edge. The monitor's corners are zones of their
//  own: a fifth of it at each corner answers to the click directly and
//  pairs the two sides, because a corner is a place, not «100% of an
//  edge». A placement is a point; chips could only ever offer the
//  named few.

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

    //  The placement in words, ends included: an align flush at either
    //  end is a CORNER — two walls, not "top edge · 100%" — and the
    //  words should say what the drawer will do: attach to both.
    function palabraPunto(lado, align) {
        const esqIni = align <= 0.5
        const esqFin = align >= 99.5
        if (lado === "top")
            return esqFin ? "top-right corner"
                 : esqIni ? "top-left corner"
                 : "top edge · " + Math.round(align) + "%"
        if (lado === "bottom")
            return esqFin ? "bottom-right corner"
                 : esqIni ? "bottom-left corner"
                 : "bottom edge · " + Math.round(align) + "%"
        if (lado === "left")
            return esqFin ? "bottom-left corner"
                 : esqIni ? "top-left corner"
                 : "left edge · " + Math.round(align) + "%"
        return esqFin ? "bottom-right corner"
             : esqIni ? "top-right corner"
             : "right edge · " + Math.round(align) + "%"
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

            //  The placement as the chips read it: which horizontal
            //  side, which vertical side — a corner is simply BOTH.
            //  Normalized, because a corner has two honest spellings
            //  («top, 100%» and «right, 0%») and the chips should
            //  light the same pair for either.
            readonly property var parLados: {
                const p = tarjeta.propia
                if (!p)
                    return { h: "", v: "" }
                const ini = p.align <= 0.5
                const fin = p.align >= 99.5
                if (p.side === "top" || p.side === "bottom") {
                    if (ini)
                        return { h: p.side, v: "left" }
                    if (fin)
                        return { h: p.side, v: "right" }
                    return { h: p.side, v: "" }
                }
                if (ini)
                    return { h: "top", v: p.side }
                if (fin)
                    return { h: "bottom", v: p.side }
                return { h: "", v: p.side }
            }

            //  A side chip press. The chips TOGGLE: one side is an
            //  edge, two adjacent sides are the corner between them.
            //  Opposite sides never pair — one replaces the other.
            //  Pressing the lit side of a pair leaves the other side
            //  alone as a plain edge; pressing a lone lit side hands
            //  the view back to the bar.
            function pulsarLado(cod) {
                const actual = tarjeta.parLados
                const esH = cod === "top" || cod === "bottom"
                const mismo = esH ? actual.h === cod : actual.v === cod
                if (mismo) {
                    if (actual.h !== "" && actual.v !== "") {
                        const otro = esH ? actual.v : actual.h
                        Settings.ponerPlacement(tarjeta.idVista, otro, 50)
                    } else {
                        Settings.ponerPlacement(tarjeta.idVista, "", 50)
                    }
                    return
                }
                const h = esH ? cod : actual.h
                const v = esH ? actual.v : cod
                if (h !== "" && v !== "")
                    Settings.ponerPlacement(tarjeta.idVista, h,
                                             v === "right" ? 100 : 0)
                else
                    Settings.ponerPlacement(tarjeta.idVista, cod, 50)
            }

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
                    //  «this one follows the bar». The bar's own words go
                    //  through the same corner-aware wording: a bar in a
                    //  corner follows as a corner, not as «100%».
                    IslandLabel {
                        text: tarjeta.propia === null
                            ? "Follows the bar — " + pagina.palabraPunto(
                                  Settings.barPosition === "bottom"
                                      ? "bottom" : "top",
                                  Settings.barAlignment)
                            : pagina.palabraPunto(tarjeta.propia.side,
                                                  tarjeta.propia.align)
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

                                //  Follow lights when there is no
                                //  placement of its own; a side lights
                                //  for its edge AND for the corner it
                                //  pairs into.
                                readonly property bool puesta:
                                    chipLado.modelData.codigo === ""
                                        ? tarjeta.propia === null
                                        : tarjeta.parLados.h
                                          === chipLado.modelData.codigo
                                          || tarjeta.parLados.v
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
                                    onClicked: {
                                        if (chipLado.modelData.codigo === "")
                                            Settings.ponerPlacement(
                                                tarjeta.idVista, "", 50)
                                        else
                                            tarjeta.pulsarLado(
                                                chipLado.modelData.codigo)
                                    }
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

                    //  A point on the monitor → the placement it names.
                    //  The corners answer FIRST: a fifth of the monitor
                    //  at each corner belongs to the corner itself, so
                    //  a plain click — not only a drag to the very end
                    //  — pairs the two sides. Then the nearest edge
                    //  wins, the coordinate along it is the percentage,
                    //  and the ends still snap flush for a drag that
                    //  approaches them. Clamped, so nothing invents a
                    //  120%.
                    function colocacionEn(x, y) {
                        const w = width, h = height
                        const fx = Math.max(0, Math.min(1, x / w))
                        const fy = Math.max(0, Math.min(1, y / h))
                        const c = 0.2
                        if (fx <= c && fy <= c)
                            return { side: "top", align: 0 }
                        if (fx >= 1 - c && fy <= c)
                            return { side: "top", align: 100 }
                        if (fx <= c && fy >= 1 - c)
                            return { side: "bottom", align: 0 }
                        if (fx >= 1 - c && fy >= 1 - c)
                            return { side: "bottom", align: 100 }
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
                        if (fraccion <= 0.08)
                            fraccion = 0
                        else if (fraccion >= 0.92)
                            fraccion = 1
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
                        //  A click is one placement and one save. A drag
                        //  is dozens of moves: the dot follows in memory
                        //  and the disk is written once, on release —
                        //  not per pixel.
                        onPressed: function (mouse) {
                            const c = monitor.colocacionEn(mouse.x, mouse.y)
                            Settings.ponerPlacement(tarjeta.idVista,
                                c.side, c.align)
                        }
                        onPositionChanged: function (mouse) {
                            if (!pressed)
                                return
                            const c = monitor.colocacionEn(mouse.x, mouse.y)
                            Settings.ponerPlacementMemoria(tarjeta.idVista,
                                c.side, c.align)
                        }
                        onReleased: function (mouse) {
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
