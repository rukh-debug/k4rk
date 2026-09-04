//  The lock screen.
//
//  The compositor creates one of these per monitor and gives them
//  the keyboard exclusively: nothing behind can paint over it or
//  hear what you type. In exchange, while this lives there is no
//  desktop, so it pays for it to be simple and to depend on nothing
//  that can be slow.
//
//  Full black on purpose: it is what consumes least on OLED, what
//  bothers least if you get up at night and what shows least of
//  your desktop to whoever passes by.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4.SuperficieBloqueo {
    id: pantalla

    color: "black"

    K4.Autenticacion {
        id: auth
        onResuelto: function (correcto) {
            if (correcto) {
                clave.text = ""
                Sesion.desbloquear()
            } else {
                clave.text = ""
                tiritona.restart()
                clave.forceActiveFocus()
            }
        }
    }

    // On mounting, focus must be asked for by hand: the surface has
    // it, but inside nobody has claimed it and the first character
    // would be lost.
    Component.onCompleted: clave.forceActiveFocus()

    Item {
        anchors.fill: parent

        // ── the time, up top and big ───────────────────────────────
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.22
            spacing: 2

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.date.toLocaleTimeString(Qt.locale(), "HH:mm")
                color: Theme.ink
                font.pixelSize: 92
                font.weight: Font.Light
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.date.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                color: Theme.muted
                font.pixelSize: 17
            }
        }

        // ── who you are and the password ───────────────────────────
        Column {
            id: acceso
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: parent.height * 0.11
            spacing: 14

            // The box's shake when the password is no good. Understood
            // without reading anything, which is what it is about
            // right after typing blind.
            SequentialAnimation {
                id: tiritona
                NumberAnimation { target: acceso; property: "x"; to: -9; duration: 45 }
                NumberAnimation { target: acceso; property: "x"; to: 9; duration: 90 }
                NumberAnimation { target: acceso; property: "x"; to: -6; duration: 90 }
                NumberAnimation { target: acceso; property: "x"; to: 0; duration: 60 }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76
                height: 76
                radius: 38
                color: Theme.surface
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)

                IslandLabel {
                    anchors.centerIn: parent
                    text: Sesion.inicial
                    color: Theme.ink
                    font.pixelSize: 34
                    font.weight: Font.Light
                }
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Sesion.visible
                color: Theme.ink
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            // ── the password box ────────────────────────────────────
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                height: 42
                radius: 21
                color: Theme.surface
                border.width: 1
                border.color: auth.estado === "fallo" ? Theme.red
                    : (clave.activeFocus ? Theme.blue : Qt.rgba(1, 1, 1, 0.1))

                Behavior on border.color { ColorAnimation { duration: 160 } }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 15
                    spacing: 10

                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(auth.estado === "correcto"
                                                   ? 0xF033F : 0xF033E)
                        color: auth.estado === "fallo" ? Theme.red
                            : (auth.estado === "correcto" ? Theme.green : Theme.muted)
                        font.pixelSize: 16
                    }

                    TextInput {
                        id: clave
                        cursorDelegate: IslandCursor {}
                        width: parent.width - 60
                        anchors.verticalCenter: parent.verticalCenter

                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        passwordMaskDelay: 0
                        enabled: !auth.ocupado
                        color: Theme.ink
                        font.pixelSize: 15
                        font.family: Theme.uiFont
                        selectByMouse: true
                        selectionColor: Theme.blue
                        clip: true

                        onAccepted: auth.comprobar(text)
                        onTextChanged: if (auth.estado === "fallo") auth.reiniciar()

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: clave.text.length === 0 && !auth.ocupado
                            text: "Password"
                            color: Theme.dim
                            font.pixelSize: 15
                        }
                    }

                    // While PAM thinks. It is not instantaneous:
                    // pam_unix deliberately puts in a couple of
                    // seconds' delay after a failure so it cannot be
                    // brute-forced, and with no signal at all it looks
                    // hung.
                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: auth.ocupado
                        text: String.fromCodePoint(0xF051F)
                        color: Theme.muted
                        font.pixelSize: 15

                        RotationAnimation on rotation {
                            running: auth.ocupado
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 1600
                        }
                    }
                }
            }

            // ── qué ha pasado ─────────────────────────────────────
            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: auth.mensaje.length > 0 ? auth.mensaje
                    : (auth.motivo === "demasiados-intentos" ? "Too many attempts"
                       : auth.motivo === "sin-pam" ? "Could not talk to PAM"
                       : auth.motivo.length > 0 ? "Wrong password" : "")
                color: Theme.red
                font.pixelSize: 12
                opacity: auth.mensaje.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }

        // ── the emergency exit ─────────────────────────────────────
        //
        //  After several failures in a row it stops being «I
        //  mistyped» and starts being «this will not let me in».
        //  Before panic spreads, the way out: a tty is still there
        //  behind.
        IslandLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 34
            horizontalAlignment: Text.AlignHCenter
            visible: auth.fallos >= 3
            text: "Locked out? Ctrl+Alt+F2 opens a text console to log in."
            color: Theme.dim
            font.pixelSize: 11
        }
    }
}
