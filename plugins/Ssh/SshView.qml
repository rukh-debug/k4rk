//  The server list.
//
//  You type to filter, like in the launcher and the clipboard: the same
//  piece and the same keys, because a house where every drawer opens a
//  different way is not a house.
//
//  Each row says just enough to recognise the place —the alias big, the
//  real destination small— and nothing more. The rest (the key, the jump)
//  ssh knows, and there is no reason to repeat it here.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: vista

    required property var plugin

    //  Without this you have to click before you can type: the island's
    //  root keeps the focus and the surface is slow to receive it.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()

    //  And the same when moving to the form: the active field is noted here
    //  and its focus claimed with the same piece. Without this the form
    //  comes out painted but deaf — it looked perfect and did not receive a
    //  single key.
    property Item entradaActiva: null
    FocoInicial { id: focoCampo; objetivo: vista.entradaActiva }

    Connections {
        target: vista.plugin
        function onModoChanged() {
            if (vista.plugin.modo === "editar" && vista.entradaActiva)
                focoCampo.reclamar()
            else if (vista.plugin.modo === "lista")
                foco.reclamar()
        }
    }

    ColumnLayout {
        visible: vista.plugin.modo === "lista"
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 10
        spacing: 8

        // ── search ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF08C0)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: entrada
                cursorDelegate: IslandCursor {}
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                text: vista.plugin.busqueda
                onTextEdited: {
                    vista.plugin.busqueda = text
                    vista.plugin.indice = 0
                }

                color: Theme.ink
                font.pixelSize: 15
                font.family: Theme.uiFont
                selectByMouse: true
                selectionColor: Theme.blue
                cursorVisible: true
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                activeFocusOnTab: true
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: "Search for a server, or type user@host"
                    color: Theme.dim
                    font.pixelSize: 15
                }

                Keys.onPressed: function (ev) {
                    const conCtrl = (ev.modifiers & Qt.ControlModifier) !== 0
                    const conShift = (ev.modifiers & Qt.ShiftModifier) !== 0

                    if (ev.key === Qt.Key_Escape) {
                        vista.plugin.cerrar(); ev.accepted = true
                    } else if (ev.key === Qt.Key_Down) {
                        vista.plugin.mover(1); ev.accepted = true
                    } else if (ev.key === Qt.Key_Up) {
                        vista.plugin.mover(-1); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageDown) {
                        vista.plugin.mover(6); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageUp) {
                        vista.plugin.mover(-6); ev.accepted = true
                    } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                        //  With shift, in a big window. It is the same pair
                        //  as in the terminal: the island for the quick
                        //  thing, the window when you know you will be a
                        //  while.
                        vista.plugin.elegir(conShift); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_S) {
                        vista.plugin.guardarActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_E) {
                        vista.plugin.editarActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_N) {
                        vista.plugin.nuevoDesdeBusqueda(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_F) {
                        vista.plugin.favoritoActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_G) {
                        vista.plugin.alternarAgentes(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_K) {
                        vista.plugin.crearClave(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_I) {
                        vista.plugin.llevarIntegracion(); ev.accepted = true
                    } else if (ev.key === Qt.Key_Delete) {
                        vista.plugin.borrarActual(); ev.accepted = true
                    }
                }
            }

            IslandLabel {
                text: vista.plugin.cuantos + (vista.plugin.cuantos === 1
                    ? " server" : " servers")
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: vista.plugin.cerrar()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── the list ────────────────────────────────────────────
        ListView {
            id: filas
            ScrollBar.vertical: IslandScrollBar {}

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: vista.plugin.lista
            currentIndex: vista.plugin.indice
            highlightMoveDuration: 130
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: fila
                required property var modelData
                required property int index

                readonly property bool elegida: index === vista.plugin.indice

                width: ListView.view.width
                height: 44
                radius: 9
                color: elegida ? Theme.surfaceHi
                     : (raton.containsMouse ? Theme.surface : "transparent")

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    spacing: 10

                    //  An on-the-fly destination stands apart from a saved
                    //  one: the first is a jump into the void, the second
                    //  your home.
                    IconGlyph {
                        text: String.fromCodePoint(fila.modelData.rapido ? 0xF0432
                                                 : (fila.modelData.favorito ? 0xF04CE
                                                                            : 0xF08C0))
                        color: fila.modelData.favorito ? Theme.yellow
                             : (fila.elegida ? Theme.ink : Theme.muted)
                        font.pixelSize: 15
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        RowLayout {
                            spacing: 7

                            //  The agents' door, if it is open. It is a
                            //  permission: either you see it, or it never
                            //  gets reviewed.
                            IconGlyph {
                                visible: fila.modelData.agentes === true
                                text: String.fromCodePoint(0xF0493)   // md-cog
                                color: Theme.green
                                font.pixelSize: 11
                                Layout.alignment: Qt.AlignVCenter
                            }

                            IslandLabel {
                                text: fila.modelData.rapido
                                    ? "Connect to " + fila.modelData.host
                                    : fila.modelData.alias
                                color: Theme.ink
                                font.pixelSize: 14
                                font.weight: fila.elegida ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.maximumWidth: 330
                            }

                            //  The tags, if there are any: they are ours
                            //  —they go in hosts.json— and they serve to
                            //  group without folders, which in a list you
                            //  filter by typing are superfluous.
                            Repeater {
                                model: fila.modelData.etiquetas

                                delegate: Rectangle {
                                    required property var modelData
                                    height: 15
                                    width: etiqueta.implicitWidth + 12
                                    radius: 7
                                    color: Theme.surfaceHi

                                    IslandLabel {
                                        id: etiqueta
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: Theme.muted
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }

                        IslandLabel {
                            text: {
                                const m = fila.modelData
                                const usuario = m.usuario ? m.usuario + "@" : ""
                                const puerto = m.puerto && m.puerto !== "22" ? ":" + m.puerto : ""
                                const salto = m.salto ? "  ·  " + "by " + m.salto : ""
                                return usuario + m.host + puerto + salto
                            }
                            color: Theme.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    //  Saving what you have just typed, with no keys to
                    //  learn: the keybind is there, but the button is what
                    //  gets seen the first time.
                    Rectangle {
                        visible: fila.modelData.rapido && fila.elegida
                        Layout.preferredWidth: guardar.implicitWidth + 18
                        Layout.preferredHeight: 20
                        radius: 10
                        color: guardarRaton.containsMouse ? Theme.blue : Theme.surfaceHi

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: guardar
                            anchors.centerIn: parent
                            text: "Save"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: guardarRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vista.plugin.guardarActual()
                        }
                    }
                }

                MouseArea {
                    id: raton
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    //  The save button goes on top: if the mouse is over
                    //  it, this area does not keep the click.
                    z: -1
                    onPositionChanged: vista.plugin.indice = fila.index
                    onClicked: function (ev) {
                        vista.plugin.indice = fila.index
                        vista.plugin.conectar(fila.modelData,
                                              (ev.modifiers & Qt.ShiftModifier) !== 0)
                    }
                }
            }
        }

        //  ── the footer ────────────────────────────────────────────
        //
        //  What can be done here, and —if you have no key at all— what is
        //  really needed before anything else. That notice disappears on
        //  its own as soon as one exists.
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            IslandLabel {
                visible: vista.plugin.sinClaves
                text: "You have no key: ctrl+K creates one and sends it to the server"
                color: Theme.yellow
                font.pixelSize: 10
                Layout.fillWidth: true
            }

            IslandLabel {
                visible: !vista.plugin.sinClaves
                text: "enter connects · shift+enter window · ctrl+E edit · ctrl+F favourite · ctrl+G agents · ctrl+I integration · del removes"
                color: Theme.dim
                font.pixelSize: 10
                Layout.fillWidth: true
            }
        }
    }

    //  ── configuring a server ────────────────────────────────
    //
    //  The same window changes face instead of opening a dialogue on top:
    //  above, what ssh understands —and which scp, git and company
    //  therefore take advantage of too— and below, ours, separated by a
    //  line so that what goes where can be seen at a glance.
    ColumnLayout {
        visible: vista.plugin.modo === "editar"
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF08C0)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: vista.plugin.borrador.original
                    ? "Edit " + vista.plugin.borrador.original
                    : "New server"
                color: Theme.ink
                font.pixelSize: 15
                Layout.fillWidth: true
            }

            //  Favourite here too: it is part of how you want it, not a
            //  separate action.
            Rectangle {
                Layout.preferredWidth: estrella.implicitWidth + 20
                Layout.preferredHeight: 22
                radius: 11
                color: vista.plugin.borrador.favorito ? Theme.surfaceHi : "transparent"
                border.width: 1
                border.color: Theme.surfaceHi

                IslandLabel {
                    id: estrella
                    anchors.centerIn: parent
                    text: (vista.plugin.borrador.favorito ? "★ " : "☆ ") + "favourite"
                    color: vista.plugin.borrador.favorito ? Theme.yellow : Theme.muted
                    font.pixelSize: 10
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.ponerCampo("favorito",
                                                       !vista.plugin.borrador.favorito)
                }
            }
        }

        Repeater {
            model: vista.plugin.campos

            delegate: ColumnLayout {
                id: filaCampo
                required property var modelData
                required property int index

                readonly property bool activo: index === vista.plugin.campo

                Layout.fillWidth: true
                spacing: 6

                //  A line before ours: above what ssh understands, below
                //  what only we understand here. It goes in its own row —not
                //  inside the field's— or it would push the label aside.
                Rectangle {
                    visible: filaCampo.modelData.suyo
                             && !vista.plugin.campos[Math.max(0, filaCampo.index - 1)].suyo
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 2
                    Layout.preferredHeight: 1
                    color: Theme.surfaceHi
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 8

                IslandLabel {
                    text: filaCampo.modelData.nombre
                    color: filaCampo.activo ? Theme.ink : Theme.muted
                    font.pixelSize: 12
                    Layout.preferredWidth: 78
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    radius: 7
                    color: filaCampo.activo ? Theme.surfaceHi : Theme.surface
                    border.width: 1
                    border.color: filaCampo.activo ? Theme.blue : "transparent"

                    Behavior on color { ColorAnimation { duration: 110 } }

                    TextInput {
                        id: entradaCampo
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        cursorDelegate: IslandCursor {}
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.blue

                        text: vista.plugin.borrador[filaCampo.modelData.id] || ""
                        onTextEdited: vista.plugin.ponerCampo(filaCampo.modelData.id, text)

                        //  The secret field goes with dots until you ask to
                        //  see it: nobody wants their password on screen by
                        //  default with someone behind them.
                        echoMode: filaCampo.modelData.secreto && !vista.plugin.verClave
                            ? TextInput.Password : TextInput.Normal
                        passwordCharacter: "•"
                        passwordMaskDelay: 0

                        //  The active field carries the focus, and it is
                        //  asked for when it changes: this way the arrows
                        //  move between fields and whatever gets typed always
                        //  goes to the one that is marked.
                        focus: filaCampo.activo
                        onActiveFocusChanged: if (activeFocus) vista.plugin.campo = filaCampo.index

                        //  The active one is noted in the view so the focus
                        //  knows who to go to, and asked for as soon as it
                        //  changes.
                        Component.onCompleted: if (filaCampo.activo) vista.entradaActiva = entradaCampo

                        Connections {
                            target: vista.plugin
                            function onCampoChanged() {
                                if (filaCampo.activo) {
                                    vista.entradaActiva = entradaCampo
                                    entradaCampo.forceActiveFocus()
                                }
                            }
                        }

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entradaCampo.text.length === 0
                            text: filaCampo.modelData.ayuda
                            color: Theme.dim
                            font.pixelSize: 11
                        }

                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape) {
                                vista.plugin.cancelarEdicion(); ev.accepted = true
                            } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                                //  Enter saves from any field: it is an
                                //  eight-line form, not a formality.
                                vista.plugin.guardarBorrador(); ev.accepted = true
                            } else if ((ev.modifiers & Qt.ControlModifier)
                                       && ev.key === Qt.Key_O) {
                                //  The form's eye, with a key: there is no
                                //  mouse here to walk over to an icon.
                                vista.plugin.verClave = !vista.plugin.verClave
                                ev.accepted = true
                            } else if (ev.key === Qt.Key_Down
                                       || (ev.key === Qt.Key_Tab && !(ev.modifiers & Qt.ShiftModifier))) {
                                vista.plugin.moverCampo(1); ev.accepted = true
                            } else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
                                vista.plugin.moverCampo(-1); ev.accepted = true
                            }
                        }
                    }
                }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IslandLabel {
                text: "enter saves · esc cancels · ↑↓ or tab moves between fields"
                color: Theme.dim
                font.pixelSize: 10
                Layout.fillWidth: true
            }

            IslandLabel {
                text: "the above goes into ~/.ssh/config"
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }
}
