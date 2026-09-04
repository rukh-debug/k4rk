//  The application centre's grid.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    readonly property int celdaAncho: 128
    readonly property int celdaAlto: 104

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ── the search box ─────────────────────────────────────────
        Rectangle {
            visible: !view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 12
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconGlyph {
                    text: ""  // fa-search
                    color: Theme.muted
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: entrada
                        cursorDelegate: IslandCursor {}
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 16
                        focus: true
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.blue
                        text: view.plugin.busqueda

                        onTextEdited: {
                            view.plugin.busqueda = text
                            view.plugin.seleccion = 0
                        }

                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape)
                                view.plugin.cerrar()
                            else if (ev.key === Qt.Key_Return
                                     || ev.key === Qt.Key_Enter)
                                view.plugin.lanzarSeleccion()
                            else if (ev.key === Qt.Key_Right)
                                view.plugin.mover(1, 0)
                            else if (ev.key === Qt.Key_Left)
                                view.plugin.mover(-1, 0)
                            else if (ev.key === Qt.Key_Down)
                                view.plugin.mover(0, 1)
                            else if (ev.key === Qt.Key_Up)
                                view.plugin.mover(0, -1)
                            else
                                return
                            ev.accepted = true
                        }

                        IslandLabel {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: entrada.text.length === 0
                            text: "Search applications"
                            color: Theme.dim
                            font.pixelSize: 16
                        }
                    }
                }

                IslandLabel {
                    text: view.plugin.lista.length
                    color: Theme.muted
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // ── the grid ───────────────────────────────────────────────
        K4.Rodillo {
            visible: !view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.fillHeight: true
            muesca: view.celdaAlto

            Flow {
                width: parent.width
                spacing: 4

                Repeater {
                    model: view.plugin.lista

                    delegate: IslandTile {
                        id: celda
                        required property var modelData
                        required property int index

                        width: view.celdaAncho
                        height: view.celdaAlto

                        //  The keyboard-chosen one carries a blue border,
                        //  not just the light background: the light
                        //  background is already put by the mouse on
                        //  hover and the two got confused — one did not
                        //  know what Enter was going to open.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.blue
                            visible: celda.index === view.plugin.seleccion
                        }
                        //  An off one does not open, but it can be
                        //  clicked: the click leads to Settings, which
                        //  is what is needed.
                        onPulsada: modelData.habilitado
                            ? view.plugin.lanzar(modelData.id)
                            : view.plugin.lanzar("settings")

                        //  The pin: it puts or removes this application
                        //  from the control centre's strip. Only on
                        //  hover —or if already pinned, always—,
                        //  otherwise the grid fills up with icons that
                        //  are not the app.
                        IconGlyph {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            z: 2
                            text: String.fromCodePoint(0xF0403)   // md-pin
                            font.pixelSize: 13
                            visible: celda.encima
                                || Settings.esAccesoDirecto(celda.modelData.id)
                            color: Settings.esAccesoDirecto(celda.modelData.id)
                                ? Theme.blue : Theme.dim
                            rotation: Settings.esAccesoDirecto(celda.modelData.id)
                                ? 0 : 45

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Settings.alternarAcceso(celda.modelData.id)
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            K4.IconoPlugin {
                                anchors.horizontalCenter: parent.horizontalCenter
                                imagen: celda.modelData.imagen
                                glifo: celda.modelData.glifo
                                tamano: 30
                                //  Off in gray, broken in red. An author's
                                //  own image does not take the tint —it
                                //  is theirs— but it does dim, otherwise
                                //  an off one is noticed less than the
                                //  rest and disorients.
                                opacity: celda.modelData.habilitado ? 1 : 0.35
                                color: celda.modelData.habilitado
                                    ? (celda.modelData.disponible ? Theme.ink
                                                                  : Theme.red)
                                    : Theme.dim
                            }

                            IslandLabel {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: view.celdaAncho - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: celda.modelData.nombre
                                font.pixelSize: 11
                                color: celda.modelData.habilitado ? Theme.ink
                                                                  : Theme.dim
                            }
                        }
                    }
                }
            }
        }

        // ── choosing what to update ───────────────────────────────
        //
        //  The grid steps aside and the pending list comes out, each
        //  with its switch. Choosing here is EXCLUDING: what is
        //  unchecked stays put with --ignore and the rest goes up in
        //  a full upgrade — uploading single packages onto an old
        //  system is the classic way to break an Arch, and this is
        //  the one pacman contemplates from the factory.
        Rectangle {
            visible: view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 12
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 14
                spacing: 8

                MediaButton {
                    glyph: String.fromCodePoint(0xF004D)   // md-arrow_left
                    glyphSize: 15
                    glyphColor: Theme.muted
                    onActivated: view.plugin.modoActualizaciones = false
                }

                IslandLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Choose what to update"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.ink
                }

                IslandLabel {
                    text: `${String(view.plugin.paq.marcadas)} of ${String(view.plugin.paq.pendientes)} selected`
                    color: Theme.muted
                    font.pixelSize: 11
                }
            }
        }

        K4.Rodillo {
            visible: view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.fillHeight: true
            muesca: 38

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: view.plugin.modoActualizaciones
                        ? view.plugin.paq.detalles : []

                    delegate: Rectangle {
                        id: fila
                        required property var modelData
                        //  Checked = it upgrades. Read from the service
                        //  and not from local state so the header's
                        //  count, the foot button and the row all tell
                        //  the same thing.
                        readonly property bool dentro:
                            !view.plugin.paq.excluidos[modelData.nombre]

                        width: parent.width
                        height: 34
                        radius: 10
                        color: filaRaton.containsMouse
                            ? Qt.lighter(Theme.surface, 1.4) : Theme.surface

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 10

                            //  This app's switch, what the question
                            //  asked for: blue with its mark when it is
                            //  going up, hollow when it stays.
                            Rectangle {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: fila.dentro ? Theme.blue : "transparent"
                                border.width: fila.dentro ? 0 : 1
                                border.color: Theme.dim

                                IconGlyph {
                                    anchors.centerIn: parent
                                    visible: fila.dentro
                                    text: String.fromCodePoint(0xF012C) // md-check
                                    font.pixelSize: 11
                                    color: Theme.ink
                                }
                            }

                            IslandLabel {
                                text: fila.modelData.nombre
                                font.pixelSize: 12
                                color: fila.dentro ? Theme.ink : Theme.dim
                            }

                            IslandLabel {
                                visible: fila.modelData.aur
                                text: "AUR"
                                font.pixelSize: 9
                                color: Theme.yellow
                            }

                            Item { Layout.fillWidth: true }

                            IslandLabel {
                                Layout.maximumWidth: 280
                                elide: Text.ElideLeft
                                text: fila.modelData.de + "  →  "
                                    + fila.modelData.a
                                font.pixelSize: 10
                                color: Theme.dim
                            }
                        }

                        MouseArea {
                            id: filaRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.plugin.paq.alternarExcluida(
                                           fila.modelData.nombre)
                        }
                    }
                }
            }
        }

        // ── the system updates ────────────────────────────────────
        //
        //  The centre's foot: how many are waiting and the button
        //  that applies them. Here and not in another module because
        //  this IS the applications' place, and keeping them current
        //  is part of having them.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 12
            color: Theme.surface

            //  Clicking the strip opens (or closes) the choosing list.
            //  It goes BELOW the button row: the ones carrying their
            //  own mouse —look again, update— keep the click for
            //  themselves.
            MouseArea {
                anchors.fill: parent
                enabled: view.plugin.paq.pendientes > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: view.plugin.modoActualizaciones =
                               !view.plugin.modoActualizaciones
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF06B0)  // md-update
                    color: view.plugin.paq.pendientes > 0 ? Theme.yellow
                                                      : Theme.dim
                    font.pixelSize: 14
                }

                ColumnLayout {
                    id: pieTextos
                    Layout.fillWidth: true
                    spacing: 0

                    IslandLabel {
                        text: view.plugin.paq.comprobando
                            ? "Checking for updates…"
                            : view.plugin.paq.pendientesRepo < 0
                            ? "Updates not checked yet"
                            : view.plugin.paq.pendientes === 0
                            ? "The system is up to date"
                            : `${String(view.plugin.paq.pendientes)} updates (${Math.max(0, view.plugin.paq.pendientesRepo)
                                    + " repos · "
                                    + Math.max(0, view.plugin.paq.pendientesAur)
                                    + " AUR"})`
                        color: view.plugin.paq.pendientes > 0 ? Theme.ink
                                                          : Theme.muted
                        font.pixelSize: 11
                    }

                    IslandLabel {
                        visible: view.plugin.paq.nombresPendientes.length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: view.plugin.paq.nombresPendientes.slice(0, 8)
                            .join("  ·  ")
                        color: Theme.dim
                        font.pixelSize: 9
                    }
                }

                IconGlyph {
                    visible: view.plugin.paq.pendientes > 0
                    text: String.fromCodePoint(
                              view.plugin.modoActualizaciones
                                  ? 0xF0140 : 0xF0143)  // chevron down / up
                    color: Theme.dim
                    font.pixelSize: 14
                }

                //  Look again, skipping the ten-minute cache.
                MediaButton {
                    glyph: String.fromCodePoint(0xF0450)   // md-refresh
                    glyphSize: 13
                    glyphColor: Theme.dim
                    onActivated: view.plugin.paq.refresh(true)
                }

                //  With nothing checked the button dims: an empty
                //  batch is not an order, it is a slip.
                Rectangle {
                    visible: view.plugin.paq.pendientes > 0
                    Layout.preferredWidth: actualizarTexto.implicitWidth + 22
                    Layout.preferredHeight: 26
                    radius: 13
                    color: view.plugin.paq.marcadas === 0 ? Theme.surface
                        : actualizarRaton.containsMouse
                        ? Qt.lighter(Theme.blue, 1.15) : Theme.blue

                    IslandLabel {
                        id: actualizarTexto
                        anchors.centerIn: parent
                        text: view.plugin.paq.marcadas < view.plugin.paq.pendientes
                            ? `Update ${String(view.plugin.paq.marcadas)}`
                            : "Update"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: view.plugin.paq.marcadas === 0 ? Theme.dim : Theme.ink
                    }

                    MouseArea {
                        id: actualizarRaton
                        anchors.fill: parent
                        enabled: view.plugin.paq.marcadas > 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.paq.updateSelected()
                            view.plugin.cerrar()
                        }
                    }
                }
            }
        }
    }

    //  The keyboard in the list: the search box is hidden and
    //  somebody has to answer — Escape returns to the grid, Enter
    //  applies what is checked.
    Item {
        id: tecladoLista
        visible: view.plugin.modoActualizaciones

        Keys.onPressed: function (ev) {
            if (ev.key === Qt.Key_Escape) {
                view.plugin.modoActualizaciones = false
                ev.accepted = true
            } else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)
                       && view.plugin.paq.marcadas > 0) {
                view.plugin.paq.updateSelected()
                view.plugin.cerrar()
                ev.accepted = true
            }
        }
    }

    //  Focus to the search box as soon as it opens —it opens to be
    //  typed in—, or to the list if it is the list in front.
    FocoInicial {
        id: foco
        objetivo: view.plugin.modoActualizaciones ? tecladoLista : entrada
    }
    Component.onCompleted: foco.reclamar()

    Connections {
        target: view.plugin
        function onModoActualizacionesChanged() { foco.reclamar() }
    }
}
