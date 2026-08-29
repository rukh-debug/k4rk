//  El menú de sesión, y el ensayo de la contraseña.
//
//  Fila de tarjetas grandes: son seis acciones como mucho y algunas apagan el
//  ordenador, así que lo que interesa es que se distingan de un vistazo y que
//  no se acierte ninguna por error. Las que no tienen vuelta atrás preguntan
//  antes, y la que pregunta se pone roja: la confirmación se ve, no se supone.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    focus: true

    //  El foco se reparte según el modo, y hay que ser explícito porque las
    //  dos mitades lo quieren para cosas distintas: en el menú lo necesita
    //  esta raíz, que es quien lee las flechas y el Intro; en el ensayo lo
    //  necesita el campo de la contraseña.
    //
    //  Reclamarlo aquí sin mirar el modo era peor que no reclamarlo: el panel
    //  del ensayo se abría sin cursor y las teclas se quedaban en esta raíz,
    //  que en ese modo no hace nada con ellas. Y no se ve venir, porque las
    //  teclas no van a ninguna parte en vez de ir a otro sitio.
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

    // ── el menú ───────────────────────────────────────────────────
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

                    // El borde solo aparece en la señalada: marca dónde estás
                    // sin encender seis cajas a la vez.
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

                    // Señalar con el ratón mueve la selección, pero no
                    // arrastra la confirmación pendiente: pasar por encima de
                    // «Apagar» no debe dejarlo a un clic de apagarse.
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

            // La red de seguridad. Bloquear sin saber si la contraseña abre es
            // la única forma de quedarse fuera de tu propia sesión.
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

    // ── el ensayo ─────────────────────────────────────────────────
    ColumnLayout {
        id: ensayoCaja

        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        visible: view.plugin.modo === "comprobar"

        //  El foco hace falta en dos momentos distintos: al cambiar de modo
        //  desde el menú, y al crearse ya en modo ensayo —que es lo que pasa
        //  llegando por IPC, y entonces `visible` nunca cambia porque nace
        //  valiendo true—. Reclamar solo en uno de los dos deja el panel
        //  abierto sin poder escribir.
        FocoInicial { id: focoEnsayo; objetivo: ensayo }

        // Al vaciar el campo desde aquí hay que avisar, porque el propio
        // vaciado dispara onTextChanged y borraría el resultado que acabamos
        // de dar: te quedarías sin saber si la contraseña valía.
        property bool limpiando: false

        K4.Autenticacion {
            id: auth
            onResuelto: function (correcto) {
                // Se borra acierte o falle: una contraseña no tiene por qué
                // seguir ahí después de haber servido para lo que servía.
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
