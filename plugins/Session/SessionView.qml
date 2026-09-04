//  The session menu, and the password rehearsal.
//
//  A row of big cards: they are six actions at most and some power
//  off the machine, so what matters is that they stand apart at a
//  glance and that none gets hit by mistake. The ones with no way
//  back ask first, and the one asking turns red: the confirmation
//  is seen, not supposed.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    focus: true

    //  Focus is split by mode, and it pays to be explicit because
    //  the two halves want it for different things: in the menu
    //  this root needs it, the one reading arrows and Enter; in the
    //  rehearsal the password field needs it.
    //
    //  Claiming it here without looking at the mode was worse than
    //  not claiming it: the rehearsal panel opened with no cursor
    //  and the keys stayed in this root, which in that mode does
    //  nothing with them. And it gives no warning, because the keys
    //  go nowhere instead of going somewhere else.
    Component.onCompleted: view.repartirFoco()

    Connections {
        target: view.plugin
        function onModoChanged() { view.repartirFoco() }
    }

    function repartirFoco() {
        if (plugin.modo === "menu")
            forceActiveFocus()
        else
            focoEnsayo.reclamar()
    }

    Keys.onPressed: function (ev) {
        if (view.plugin.modo === "comprobar")
            return

        if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Tab) {
            view.plugin.avanzar(); ev.accepted = true
        } else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Backtab) {
            view.plugin.retroceder(); ev.accepted = true
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter
                   || ev.key === Qt.Key_Space) {
            view.plugin.elegir(); ev.accepted = true
        }
    }

    // ── the menu ───────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8
        visible: view.plugin.modo === "menu"

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            IslandLabel {
                text: "Session of " + Sesion.visible
                color: Theme.muted
                font.pixelSize: 11
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Repeater {
                model: view.plugin.acciones

                delegate: IslandTile {
                    id: casilla
                    required property var modelData
                    required property int index

                    readonly property bool elegida: index === view.plugin.index
                    readonly property bool preguntando: index === view.plugin.confirmando

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    activa: elegida
                    colorBase: Theme.surface
                    colorActiva: preguntando ? Qt.rgba(1, 0.27, 0.23, 0.16) : Theme.surfaceHi

                    // The border only appears on the pointed one: it
                    // marks where you are without lighting six boxes
                    // at once.
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        visible: casilla.elegida
                        border.width: 1
                        border.color: casilla.preguntando ? Theme.red : Theme.blue
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 7

                        IconGlyph {
                            Layout.alignment: Qt.AlignHCenter
                            text: String.fromCodePoint(casilla.modelData.icono)
                            color: casilla.preguntando ? Theme.red
                                : (casilla.elegida ? Theme.ink : casilla.modelData.color)
                            font.pixelSize: 30
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: casilla.preguntando ? "Are you sure?"
                                                      : casilla.modelData.texto
                            color: casilla.preguntando ? Theme.red : Theme.ink
                            font.pixelSize: 12
                            font.weight: casilla.elegida ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    onPulsada: view.plugin.ejecutar(casilla.index)

                    // Pointing with the mouse moves the selection, but
                    // does not drag the pending confirmation along:
                    // passing over «Power off» must not leave it one
                    // click from powering off.
                    onHoveredChanged: if (hovered) view.plugin.index = index
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            spacing: 8

            IslandLabel {
                text: "← → picks · enter confirms · esc cancels"
                color: Theme.dim
                font.pixelSize: 9
            }

            Item { Layout.fillWidth: true }

            // The safety net. Locking without knowing whether the
            // password opens is the only way to lock yourself out of
            // your own session.
            Rectangle {
                Layout.preferredWidth: ensayoTexto.implicitWidth + 18
                Layout.preferredHeight: 18
                radius: 9
                color: ensayoRaton.containsMouse ? Theme.surfaceHi : Theme.surface

                IslandLabel {
                    id: ensayoTexto
                    anchors.centerIn: parent
                    text: "Try password"
                    color: Theme.muted
                    font.pixelSize: 9
                }

                MouseArea {
                    id: ensayoRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.plugin.comprobarClave()
                }
            }
        }
    }

    // ── the rehearsal ─────────────────────────────────────────────
    ColumnLayout {
        id: ensayoCaja

        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        visible: view.plugin.modo === "comprobar"

        //  Focus is needed at two different moments: switching mode
        //  from the menu, and being born already in rehearsal mode —
        //  which is what happens arriving over IPC, and then
        //  `visible` never changes because it is born true—.
        //  Claiming it at only one of the two leaves the panel open
        //  and unable to type.
        FocoInicial { id: focoEnsayo; objetivo: ensayo }

        // Emptying the field from here must give notice, because
        // the emptying itself fires onTextChanged and would erase
        // the result just given: you would be left not knowing
        // whether the password was any good.
        property bool limpiando: false

        K4.Autenticacion {
            id: auth
            onResuelto: function (correcto) {
                // It clears hit or miss: a password has no business
                // staying after serving what it served for.
                ensayoCaja.limpiando = true
                ensayo.text = ""
                ensayoCaja.limpiando = false
            }
        }

        IslandLabel {
            Layout.fillWidth: true
            text: "Try password"
            color: Theme.ink
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        IslandLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Checked against the same PAM the lock uses, without locking anything. If it works here, the lock screen will open too."
            color: Theme.muted
            font.pixelSize: 11
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 19
            color: Theme.surface
            border.width: 1
            border.color: auth.estado === "correcto" ? Theme.green
                : (auth.estado === "fallo" ? Theme.red
                   : (ensayo.activeFocus ? Theme.blue : Qt.rgba(1, 1, 1, 0.1)))

            Behavior on border.color { ColorAnimation { duration: 160 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(auth.estado === "correcto" ? 0xF05E0
                        : (auth.estado === "fallo" ? 0xF0028 : 0xF033E))
                    color: auth.estado === "correcto" ? Theme.green
                        : (auth.estado === "fallo" ? Theme.red : Theme.muted)
                    font.pixelSize: 15
                }

                TextInput {
                    id: ensayo
                    cursorDelegate: IslandCursor {}
                    width: parent.width - 56
                    anchors.verticalCenter: parent.verticalCenter

                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    passwordMaskDelay: 0
                    enabled: !auth.ocupado
                    color: Theme.ink
                    font.pixelSize: 14
                    font.family: Theme.uiFont
                    clip: true

                    onAccepted: auth.comprobar(text)
                    onTextChanged: {
                        if (!ensayoCaja.limpiando && auth.estado !== "verificando")
                            auth.reiniciar()
                    }

                    Keys.onEscapePressed: function (ev) {
                        view.plugin.atras()
                        ev.accepted = true
                    }

                    IslandLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ensayo.text.length === 0 && !auth.ocupado
                        text: "Password"
                        color: Theme.dim
                        font.pixelSize: 14
                    }
                }
            }
        }

        IslandLabel {
            Layout.fillWidth: true
            text: auth.estado === "correcto" ? "Correct: the lock will work."
                : (auth.ocupado ? "Checking…"
                   : (auth.mensaje.length > 0 ? auth.mensaje
                      : (auth.motivo === "demasiados-intentos" ? "Too many attempts"
                         : auth.motivo === "sin-pam" ? "Could not talk to PAM"
                         : auth.motivo.length > 0 ? "Wrong password" : "")))
            color: auth.estado === "correcto" ? Theme.green
                : (auth.estado === "fallo" ? Theme.red : Theme.muted)
            font.pixelSize: 11
        }

        Item { Layout.fillHeight: true }
    }
}
