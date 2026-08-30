//  Where each view opens from: which side of the screen, and where along
//  that side. One card per view — the side chips carry the big choice
//  («Follow bar» is the default and the first chip, so the page starts
//  showing what everything does), and the alignment chips below refine it
//  once a side of its own is picked.
//
//  The little monitor on the right is not decoration: a placement is a
//  POINT, and a point reads better drawn than described. The strip on the
//  bar's own edge is the pill itself, so it is visible what «Follow bar»
//  means — the dot rides the strip when following, and leaves it when a
//  side is chosen.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: pagina

    spacing: 10

    //  Everything that OPENS and takes the island. The pill is not in the
    //  list: it lives wherever the Island page says and drags its hover
    //  views with it; what is here is what you summon.
    readonly property var vistas: [
        { id: "panel",     nombre: "Control centre" },
        { id: "settings",  nombre: "Settings" },
        { id: "launcher",  nombre: "Launcher" },
        { id: "clipboard", nombre: "Clipboard" },
        { id: "system",    nombre: "System" },
        { id: "keys",      nombre: "Shortcuts" },
        { id: "session",   nombre: "Session" },
        { id: "tray",      nombre: "Tray" },
        { id: "ask",       nombre: "Ask" },
        { id: "apps",      nombre: "Apps" },
        { id: "terminal",  nombre: "Terminal" },
        { id: "ssh",       nombre: "Servers" },
        { id: "agents",    nombre: "Agents" },
        { id: "hyprtheme", nombre: "Hyprland theme" },
        { id: "displays",  nombre: "Displays" },
        { id: "toast",     nombre: "Notification toast" }
    ]

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
    //  right are aligned top to bottom, the horizontal sides end to end.
    function alineacionesDe(lado) {
        if (lado === "left" || lado === "right")
            return [{ codigo: 15, nombre: "Top" },
                    { codigo: 50, nombre: "Centre" },
                    { codigo: 85, nombre: "Bottom" }]
        return [{ codigo: 15, nombre: "Left" },
                { codigo: 50, nombre: "Centre" },
                { codigo: 85, nombre: "Right" }]
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

                    //  ── the side chips ────────────────────
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

                    //  ── the alignment chips ───────────────
                    //
                    //  Only with a side of its own: a view that follows the
                    //  bar has no alignment to pick — it borrows the bar's.
                    RowLayout {
                        visible: tarjeta.propia !== null
                        spacing: 5

                        Repeater {
                            model: tarjeta.propia
                                ? pagina.alineacionesDe(
                                      tarjeta.propia.side)
                                : []

                            delegate: Rectangle {
                                id: chipAlineacion
                                required property var modelData

                                readonly property bool puesta:
                                    tarjeta.propia
                                    && tarjeta.propia.align
                                       === chipAlineacion.modelData.codigo

                                implicitWidth: textoAlineacion.implicitWidth
                                               + 20
                                implicitHeight: 22
                                radius: 11
                                color: puesta ? Theme.blue
                                    : (ratonAlineacion.containsMouse
                                       ? Theme.surfaceHi : Theme.track)

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                IslandLabel {
                                    id: textoAlineacion
                                    anchors.centerIn: parent
                                    text: chipAlineacion.modelData.nombre
                                    color: chipAlineacion.puesta ? Theme.ink
                                                                 : Theme.muted
                                    font.pixelSize: 10
                                    font.weight: chipAlineacion.puesta
                                        ? Font.DemiBold : Font.Normal
                                }

                                MouseArea {
                                    id: ratonAlineacion
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Settings.ponerPlacement(
                                        tarjeta.idVista,
                                        tarjeta.propia.side,
                                        chipAlineacion.modelData.codigo)
                                }
                            }
                        }
                    }
                }

                //  ── the little monitor ──────────────────
                //
                //  The strip is the pill on the bar's edge; the dot is
                //  where THIS view opens. Following paints the dot on the
                //  strip — it goes wherever the pill goes.
                Item {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignVCenter

                    readonly property real margenPunto: 4
                    //  The bar's own edge and point, for the strip.
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

                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.track
                    }

                    //  The pill: a strip along the bar's edge.
                    Rectangle {
                        readonly property var p: parent.puntoEn(
                            parent.ladoBarra, Settings.barAlignment)
                        x: p.x - 12
                        y: p.y - 1.5
                        width: 24
                        height: 3
                        radius: 1.5
                        color: Theme.track
                    }

                    //  The dot: where this view opens.
                    Rectangle {
                        readonly property var p: parent.puntoEn(
                            tarjeta.efectiva.side, tarjeta.efectiva.align)
                        x: p.x - 3.5
                        y: p.y - 3.5
                        width: 7
                        height: 7
                        radius: 3.5
                        color: Theme.blue
                        border.width: 1
                        border.color: Theme.islandBg
                    }
                }
            }
        }
    }
}
