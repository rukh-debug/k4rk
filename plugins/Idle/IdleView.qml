//  The folded pill, in three CHAINED zones: the cover, the time
//  hanging from the cover and the indicators hanging from the time.
//
//  Each zone starts where the previous one ends, and that is the
//  whole rule. The three used to be anchored to their edge —left,
//  center, right—, and that forces what is reserved to match to the
//  pixel what it truly measures: the moment they came apart, the
//  right row walked over the time and the clip hid it instead of
//  fixing it. Chained, overlap does not merely not happen: it does
//  not fit.
//
//  Not with flexible spacers either: a RowLayout centers the middle
//  group against the flanks' CONTENT, so the time shifted half the
//  width of whatever sat on the right and danced whenever a tray
//  icon appeared.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var plugin: null
    property var tray: null
    property int shown: 0

    // ── los escritorios asoman al cambiar ─────────────────────────
    property bool mostrandoEscritorios: false

    //  The parade shows EVERY desk — the whole roster the Control
    //  Centre hasn't hidden, scratchpad included. The pill lends the
    //  centre the width of the row for as long as the parade lasts
    //  (see `centro` below) and takes it back for the clock.
    readonly property var escritoriosVisibles: Workspaces.shownList

    //  The first change of `activo` is the startup one —it goes from
    //  -1 to whatever—, and it is not a desk switch: without this
    //  guard the pill would show the dots every time the bar
    //  reloads.
    property bool arrancado: false

    Component.onCompleted: {
        arranque.start()
    }

    Timer {
        id: arranque
        interval: 700
        onTriggered: view.arrancado = true
    }

    Connections {
        target: Workspaces
        function onActivoChanged() {
            if (!view.arrancado)
                return
            view.mostrandoEscritorios = true
            volver.restart()
        }
    }

    Timer {
        id: volver
        interval: 1800
        onTriggered: view.mostrandoEscritorios = false
    }

    //  The parade's room, handed out and taken back: the plugin sizes
    //  the pill from this, so the desks get their width while they
    //  show and the clock keeps its 46 the rest of the day.
    onMostrandoEscritoriosChanged: if (plugin)
        plugin.centroAncho = mostrandoEscritorios
            ? Math.max(46, Math.ceil(deskRow.implicitWidth)) : 46

    Item {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11

        // ── izquierda
        RowLayout {
            id: izquierda
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            //  Same as the right: the real width, to the plugin. This
            //  flank opens the chain, so what it measures runs to the
            //  other two, and an eyeball count here shows as much as
            //  one on the other side.
            onImplicitWidthChanged: if (view.plugin)
                view.plugin.ladoIzqMedido = Math.ceil(implicitWidth)
            Component.onCompleted: if (view.plugin)
                view.plugin.ladoIzqMedido = Math.ceil(implicitWidth)

            //  Flank extensions, first thing on this flank: it is what
            //  hugs the screen's edge closest, which is where they
            //  grow.
            ExtensionZone {
                side: "left"
                Layout.alignment: Qt.AlignVCenter
            }

            Artwork {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                visible: Media.isPlaying
            }

            // The bars, glued to the cover. They used to be on the
            // other side of the pill, and that forced looking at two
            // places to know whether something plays and what it is:
            // they are the same information.
            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 12
                visible: Media.isPlaying
            }

        }

        // ── centro
        //
        //  The time almost always, and the desks only when you switch:
        //  they appear in their place, show themselves a couple of
        //  seconds and leave. The fixed dots on the left were there
        //  all day to say something that only matters in the instant
        //  it changes.
        Item {
            id: centro

            // Hanging from the cover, not centered in the box: the box
            // no longer reserves the same on both sides, so its
            // center is not where the time goes.
            anchors.left: izquierda.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            //  The clock's 46, or the parade's: while the desks show,
            //  the centre lends the row its width and the pill breathes
            //  wide for the moment — reserving parade room all day was
            //  the old disease (ten desks ate half the bar).
            width: view.mostrandoEscritorios
                ? Math.max(46, deskRow.implicitWidth) : 46

            Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            height: parent.height

            IslandLabel {
                anchors.centerIn: parent
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Media.hasPlayer ? Theme.ink : Theme.muted

                opacity: view.mostrandoEscritorios ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                id: deskRow
                anchors.centerIn: parent
                spacing: 4

                opacity: view.mostrandoEscritorios ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                //  The row's real width, published to the plugin the
                //  moment it dresses up: the pill lends the centre what
                //  the parade needs (see `centro`), and this is the
                //  number that says what it needs.
                onImplicitWidthChanged: if (view.plugin && view.mostrandoEscritorios)
                    view.plugin.centroAncho = Math.max(46, Math.ceil(implicitWidth))

                //  One size for every bubble, measured over the WHOLE
                //  roster the switch leaves in — a bubble that gains or
                //  loses focus never moves its neighbours, and a desk
                //  joining or leaving the roster doesn't either.
                readonly property real bubbleWidth: {
                    let w = 0
                    for (let i = 0; i < Workspaces.shownList.length; ++i) {
                        const texto = Workspaces.label(Workspaces.shownList[i])
                        w = Math.max(w, numberMetric.advanceWidth(texto),
                                        focusMetric.advanceWidth(texto))
                    }
                    return Math.max(16, w + 10)
                }

                FontMetrics {
                    id: numberMetric
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
                FontMetrics {
                    id: focusMetric
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: view.escritoriosVisibles

                    delegate: Rectangle {
                        //  Same dress the header wears, chosen in the same
                        //  place: a dot per desk, or its number.
                        id: sitio
                        required property var modelData
                        readonly property bool numeros:
                            Settings.panelWorkspaceStyle === "numbers"

                        Layout.preferredWidth: numeros
                            ? deskRow.bubbleWidth
                            : (modelData.focused ? 18 : 6)
                        Layout.preferredHeight: numeros ? 16 : 6
                        Layout.alignment: Qt.AlignVCenter
                        radius: numeros ? 8 : 3
                        color: modelData.focused
                            ? Theme.ink : (numeros ? "transparent" : Theme.track)

                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        Behavior on color { ColorAnimation { duration: 200 } }

                        IslandLabel {
                            id: numero
                            anchors.centerIn: parent
                            visible: sitio.numeros
                            text: Workspaces.label(sitio.modelData)
                            color: sitio.modelData.focused
                                ? Theme.islandBg : Theme.muted
                            font.pixelSize: 10
                            font.weight: sitio.modelData.focused
                                ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }

        // ── derecha
        //  Indicators only: nothing is clickable here, because on
        //  the mouse's approach the island has already switched to
        //  the clock or player view. It is in those that the row is
        //  clickable.
        RowLayout {
            id: derecha

            //  Hanging from the TIME, closing the chain.
            anchors.left: centro.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            //  The row's real width, published to the plugin: the pill
            //  widens with what IS, not with what somebody remembered
            //  to add. implicitWidth does not depend on the parent's
            //  width, so no binding loop is possible.
            onImplicitWidthChanged: if (view.plugin)
                view.plugin.ladoDerMedido = Math.ceil(implicitWidth)
            Component.onCompleted: if (view.plugin)
                view.plugin.ladoDerMedido = Math.ceil(implicitWidth)

            Minimizados { Layout.alignment: Qt.AlignVCenter }

            PluginPildora { Layout.alignment: Qt.AlignVCenter }

            TrayRow {
                max: view.shown
                iconSize: 14
                interactive: false
                Layout.alignment: Qt.AlignVCenter
            }

            //  And the flank extensions close the chain: last in the
            //  row, glued to the screen's edge, which is where they
            //  grow. Each paints only its own — the other instance
            //  looks at the other side.
            ExtensionZone {
                side: "right"
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
