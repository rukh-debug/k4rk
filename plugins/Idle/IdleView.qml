//  Píldora plegada, en tres zonas ENCADENADAS: la carátula, la hora colgada de
//  la carátula y los indicadores colgados de la hora.
//
//  Cada zona empieza donde acaba la anterior, y esa es toda la regla. Antes
//  iban las tres ancladas a su borde —izquierda, centro, derecha—, y eso obliga
//  a que lo reservado cuadre al píxel con lo que mide de verdad: en cuanto se
//  descuadraba, la fila de la derecha caminaba por encima de la hora y el clip
//  lo escondía en vez de arreglarlo. Encadenadas, el solape no es que no pase:
//  es que no cabe.
//
//  Con espaciadores flexibles tampoco: un RowLayout centra el grupo del medio
//  respecto al CONTENIDO de los flancos, así que la hora se corría medio ancho
//  de lo que hubiera a la derecha y bailaba al aparecer un icono de bandeja.

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

    //  El primer cambio de `activo` es el de arrancar —pasa de -1 al que
    //  toque—, y no es un cambio de escritorio: sin esta guarda la píldora
    //  enseñaría los puntos cada vez que se recarga la barra.
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

            //  Igual que la derecha: el ancho real, al plugin. Este flanco
            //  abre la cadena, así que lo que mida corre a los otros dos y una
            //  cuenta a ojo aquí se ve tanto como una al otro lado.
            onImplicitWidthChanged: if (view.plugin)
                view.plugin.ladoIzqMedido = Math.ceil(implicitWidth)
            Component.onCompleted: if (view.plugin)
                view.plugin.ladoIzqMedido = Math.ceil(implicitWidth)

            //  Las extensiones de flanco, lo primero de este flanco: es lo
            //  más pegado al borde de la pantalla, que es hacia donde crecen.
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

            // Las barras, pegadas a la carátula. Estaban al otro lado de la
            // píldora, y eso obligaba a mirar a dos sitios para saber si
            // suena algo y qué es: son la misma información.
            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 12
                visible: Media.isPlaying
            }

        }

        // ── centro
        //
        //  La hora casi siempre, y los escritorios solo cuando cambias de uno:
        //  aparecen en su sitio, se dejan ver un par de segundos y se van. Los
        //  puntos fijos a la izquierda estaban ahí todo el día para decir algo
        //  que solo importa en el instante en que cambia.
        Item {
            id: centro

            // Colgada de la carátula, no al centro de la caja: la caja ya
            // no reserva lo mismo a los dos lados, así que su centro no es
            // donde va la hora.
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
        //  Indicadores nada más: aquí no se puede pinchar, porque al acercar el
        //  ratón la island ya ha cambiado a la vista de reloj o de reproductor.
        //  Es en esas donde la fila es pulsable.
        RowLayout {
            id: derecha

            //  Colgada de la HORA, cerrando la cadena.
            anchors.left: centro.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            //  El ancho real de la fila, publicado al plugin: la píldora se
            //  ensancha con lo que HAY, no con lo que alguien recordó sumar.
            //  implicitWidth no depende del ancho del padre, así que no hay
            //  bucle de binding posible.
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

            //  Y las extensiones de flanco cierran la cadena: lo último de
            //  la fila, pegado al borde de la pantalla, que es hacia donde
            //  crecen. Solo pintan las suyas — la otra instancia mira al
            //  otro lado.
            ExtensionZone {
                side: "right"
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
