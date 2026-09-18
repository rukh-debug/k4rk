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
import K4 as K4
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
    //  what is here is what you summon. Each card also carries the
    //  plugin's `summonCommand` — what the copy button hands out, empty
    //  when the surface cannot be opened from outside.
    //
    //  Every summoned surface, native or plugin: native bar chrome gets
    //  the same card as a summoned plugin view. Placement ids are stable
    //  across the migration, so entries users already saved keep working.
    readonly property var vistas: SurfaceRegistry.placeableSurfaces

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
    //  words should say what the view will do: attach to both.
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

    function parDe(p) {
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
                return pagina.parDe(tarjeta.propia ? tarjeta.efectiva : null)
            }
            readonly property var parEfectiva: pagina.parDe(tarjeta.efectiva)

            //  ── the copy button: the command out of the card ───────
            //
            //  What gets copied is a whole command line, ready to
            //  paste. The prefix is built here and not declared on
            //  the plugin because only the running instance knows the
            //  path `-p` needs — the mirror under Nix, the checkout
            //  anywhere else. The feedback stays with the card: the
            //  glyph flips to a check and the card says how to use
            //  what is now in the clipboard, then goes quiet.
            property bool copied: false

            Timer {
                id: copyTimer
                interval: 8000
                onTriggered: tarjeta.copied = false
            }

            function ipcCommand() {
                return "quickshell ipc -p \""
                       + K4.Paths.enRaiz("shell.qml") + "\" call "
                       + tarjeta.modelData.ipc
            }

            function copyIpc() {
                K4.Sistema.copiar(tarjeta.ipcCommand())
                tarjeta.copied = true
                copyTimer.restart()
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

            GridLayout {
                id: columna
                anchors.fill: parent
                anchors.margins: 12
                columns: width < 500 ? 1 : 2
                columnSpacing: 12
                rowSpacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        IslandLabel {
                            Layout.fillWidth: true
                            text: tarjeta.modelData.nombre
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        //  The command out: copies the whole line that
                        //  opens this view from outside — a terminal, a
                        //  bind, a script. No chip when the plugin
                        //  declares no summon command (the Hyprland
                        //  island opens when a mode does): a button
                        //  that copied nothing would lie.
                        K4.Boton {
                            visible: tarjeta.modelData.ipc.length > 0
                            glifo: tarjeta.copied ? Theme.ico.check : Theme.ico.copy
                            tamano: 16
                            color: tarjeta.copied ? Theme.blue : Theme.muted
                            Accessible.name: "Copy command for " + tarjeta.modelData.nombre
                            onPulsado: tarjeta.copyIpc()
                        }
                    }

                    //  The copied line, and what to do with it. The
                    //  clipboard already holds the whole command, so
                    //  the echo may elide — what it owes is
                    //  recognition, not completeness.
                    ColumnLayout {
                        visible: tarjeta.copied
                        Layout.fillWidth: true
                        spacing: 2

                        IslandLabel {
                            Layout.fillWidth: true
                            text: tarjeta.ipcCommand()
                            color: Theme.muted
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: "Command copied. Run it in a terminal or add it to your compositor's key bindings."
                            color: Theme.muted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
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
                            : pagina.palabraPunto(tarjeta.efectiva.side,
                                                  tarjeta.efectiva.align)
                        color: Theme.muted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    //  ── the side chips ────────────────────
                    //
                    // Coarse choice; the larger monitor is the precise one.
                    // Flow keeps the right-side controls reachable when the
                    // Settings window is at its minimum width.
                    Flow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: childrenRect.height
                        spacing: 8

                        Repeater {
                            model: pagina.lados

                            delegate: K4.ActionButton {
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

                                text: modelData.nombre
                                selected: puesta
                                Accessible.name: tarjeta.modelData.nombre + ": " + text
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

                    K4.Deslizador {
                        Layout.fillWidth: true
                        visible: tarjeta.propia !== null
                        etiqueta: "Alignment"
                        Accessible.name: "Alignment of " + tarjeta.modelData.nombre
                        valor: tarjeta.efectiva.align
                        sufijo: "%"
                        onMovido: function (value) {
                            Settings.ponerPlacementMemoria(tarjeta.idVista, tarjeta.efectiva.side, value)
                            if (!dragging) {
                                Settings.guardar()
                            }
                        }
                        onDraggingChanged: if (!dragging) {
                            Settings.guardar()
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

                    Layout.preferredWidth: columna.columns === 1 ? 210 : 148
                    Layout.maximumWidth: 230
                    Layout.preferredHeight: columna.columns === 1 ? 108 : 84
                    Layout.alignment: columna.columns === 1
                        ? Qt.AlignHCenter : Qt.AlignVCenter

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
                        radius: 9
                        color: ratonMonitor.containsMouse
                            ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        border.width: 1
                        border.color: Theme.track
                    }

                    // The four rails are both affordance and state. In
                    // particular, the right rail remains a large visible
                    // target instead of a final chip that can be clipped.
                    Repeater {
                        model: [
                            { side: "top", x: 8, y: 0,
                              w: monitor.width - 16, h: 4 },
                            { side: "bottom", x: 8, y: monitor.height - 4,
                              w: monitor.width - 16, h: 4 },
                            { side: "left", x: 0, y: 8,
                              w: 4, h: monitor.height - 16 },
                            { side: "right", x: monitor.width - 4, y: 8,
                              w: 4, h: monitor.height - 16 }
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool activa:
                                tarjeta.parEfectiva.h === modelData.side
                                || tarjeta.parEfectiva.v === modelData.side
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 2
                            color: activa ? Theme.blue : Theme.track
                            opacity: activa ? 0.8 : 0.45

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                        }
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

                    // A miniature of the real attached surface makes corner
                    // placement visible before opening the plugin.
                    Item {
                        id: miniatura

                        readonly property var p: monitor.puntoEn(
                            tarjeta.efectiva.side, tarjeta.efectiva.align)
                        readonly property bool vertical:
                            tarjeta.efectiva.side === "left"
                            || tarjeta.efectiva.side === "right"

                        width: vertical ? 15 : 34
                        height: vertical ? 30 : 16
                        readonly property real xCruda:
                            tarjeta.efectiva.side === "right"
                            ? p.x - width
                            : tarjeta.efectiva.side === "left"
                              ? p.x : p.x - width / 2
                        readonly property real yCruda:
                            tarjeta.efectiva.side === "bottom"
                            ? p.y - height
                            : tarjeta.efectiva.side === "top"
                              ? p.y : p.y - height / 2
                        x: Math.max(monitor.margenPunto, Math.min(
                            monitor.width - monitor.margenPunto - width,
                            xCruda))
                        y: Math.max(monitor.margenPunto, Math.min(
                            monitor.height - monitor.margenPunto - height,
                            yCruda))

                        EdgeAttachedShape {
                            anchors.fill: parent
                            attachTop: tarjeta.parEfectiva.h === "top"
                            attachBottom: tarjeta.parEfectiva.h === "bottom"
                            attachLeft: tarjeta.parEfectiva.v === "left"
                            attachRight: tarjeta.parEfectiva.v === "right"
                            cornerRadius: 5
                            rimThickness: 1
                            blendReach: 7
                            blendDepth: 4
                            fillColor: Theme.blue
                        }
                    }

                    // The handle marks the exact draggable anchor point.
                    Rectangle {
                        readonly property var p: monitor.puntoEn(
                            tarjeta.efectiva.side, tarjeta.efectiva.align)
                        x: p.x - 5
                        y: p.y - 5
                        width: 10
                        height: 10
                        radius: 5
                        color: Theme.ink
                        border.width: 2
                        border.color: Theme.islandBg
                    }

                    MouseArea {
                        id: ratonMonitor
                        property var previousPlacement: null
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        //  A click is one placement and one save. A drag
                        //  is dozens of moves: the dot follows in memory
                        //  and the disk is written once, on release —
                        //  not per pixel.
                        onPressed: function (mouse) {
                            previousPlacement = tarjeta.propia
                                ? { side: tarjeta.propia.side, align: tarjeta.propia.align } : null
                            const c = monitor.colocacionEn(mouse.x, mouse.y)
                            Settings.ponerPlacementMemoria(tarjeta.idVista,
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
                        onCanceled: {
                            Settings.ponerPlacementMemoria(tarjeta.idVista,
                                previousPlacement ? previousPlacement.side : "",
                                previousPlacement ? previousPlacement.align : 50)
                        }
                    }
                }
            }
        }
    }
}
