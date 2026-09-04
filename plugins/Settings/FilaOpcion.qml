//  A Settings row: the icon, the name, the explanation and the control.
//
//  It lived inside `SettingsView.qml`, embedded as a delegate. It
//  moves to its own file because TWO views use it now —the usual
//  panel and the sidebar window— and two copies of three hundred
//  lines diverge at the first fix: one gets fixed and the other
//  keeps lying.
//
//  It does not know where it is painted. It receives the option's
//  definition and talks to the `Settings` service, same as before.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
    id: opcion
    required property var modelData
    //  With `!!` and not bare. `Settings.valor`
    //  answers `undefined` for options with nothing
    //  saved yet and for those that are not
    //  switches, and assigning that to a bool is a
    //  log warning for EVERY row and EVERY time
    //  Settings opens — noise covering the real
    //  warnings.
    //
    //  Coerce and not compare with `true`: this
    //  lights the row's ICON, and a choice is worth
    //  «travel» and a text field is worth a URL.
    //  With `=== true` every row that was not a
    //  switch went dark.
    readonly property bool activa:
        !!Settings.valor(modelData.id)

    //  A section title inside the stack of rows: not a setting, a divider
    //  that names the group the rows below it belong to. One `tipo` more in
    //  the option definitions — and a page stops being a wall of
    //  forty-pixel rectangles that all weigh the same.
    readonly property bool esTitulo: modelData.tipo === "titulo"

    //  A text option's value, always as a string:
    //  an external registry answers `false` when
    //  nothing is saved yet.
    readonly property string valorTexto: {
        const v = Settings.valor(modelData.id)
        return (v === undefined || v === null || v === false)
            ? "" : String(v)
    }

    // Some options paint nothing when their master
    // switch is off: they dim and stop responding,
    // instead of lying about what they do.
    //  And plain `disponible: false`, for what does
    //  not depend on another setting but on the
    //  world: a program not installed. Without
    //  this, the only way to say «this cannot work
    //  here» was not offering it, and then nobody
    //  learns it exists.
    readonly property bool disponible:
        (!modelData.requiere
         || Settings.valor(modelData.requiere))
        && modelData.disponible !== false

    //  Network actions go in two beats: the first
    //  touch arms and the second executes, and if
    //  you think it over for more than a few
    //  seconds it disarms itself. A modal dialog
    //  would be more pompous and protect no
    //  better.
    property bool armada: false

    Timer {
        id: desarmar
        interval: 4000
        onTriggered: opcion.armada = false
    }

    //  Close and reopen must not leave a row armed, waiting for a stray
    //  click. The signal is the row's OWN — the context's `view` is not
    //  guaranteed here, and a Connections to something without the signal
    //  warns once per row and disarms nothing.
    onVisibleChanged: if (!visible)
        opcion.armada = false

    opacity: disponible ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Layout.fillWidth: true
    Layout.preferredHeight: esTitulo ? 24 : 40
    radius: 10
    color: esTitulo ? "transparent"
         : opcion.armada ? "#2a0f12"
         : (filaMouse.containsMouse ? Theme.surfaceHi : Theme.surface)
    border.width: !esTitulo && opcion.armada ? 1 : 0
    border.color: Theme.red

    Behavior on color { ColorAnimation { duration: 120 } }

    //  ── the section title ───────────────
    //
    //  Small, spaced-out letters over a hairline: enough to part groups,
    //  quiet enough not to compete with the rows it names. It takes the
    //  place of the whole row — no icon, no switch, nothing to press.
    IslandLabel {
        visible: opcion.esTitulo
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.bottom: underline.top
        anchors.bottomMargin: 3
        text: opcion.modelData.nombre
        color: Theme.muted
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.1
    }

    Rectangle {
        id: underline
        visible: opcion.esTitulo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.track
    }

    RowLayout {
        visible: !opcion.esTitulo
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 11

        K4.IconoPlugin {
            //  A plugin can bring its own image;
            //  the rest of the options are glyphs
            //  and fall in the same place.
            imagen: opcion.modelData.imagen || ""
            glifo: opcion.modelData.glifo || 0
            color: opcion.activa ? Theme.ink : Theme.dim
            tamano: 15
            Layout.preferredWidth: 18
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            IslandLabel {
                text: (opcion.armada
                       ? (opcion.modelData.nombreArmado
                          || "Are you sure? This cannot be undone")
                       : opcion.modelData.nombre) || ""
                color: opcion.armada ? Theme.red : Theme.ink
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: (opcion.armada
                       ? (opcion.modelData.descArmado
                          || opcion.modelData.desc)
                       : opcion.modelData.desc) || ""
                //  A broken plugin's reason goes
                //  in red: it is the difference
                //  between «off» and «cannot».
                color: opcion.armada ? "#ff9f9f"
                     : (opcion.modelData.error ? Theme.red : Theme.muted)
                font.pixelSize: 9
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        //  A plugin that cannot load carries no
        //  switch: turning on the impossible is
        //  lying. If the failure was at load, the
        //  whole row retries.
        IslandLabel {
            visible: opcion.modelData.error === "recargable"
            text: "retry"
            color: Theme.blue
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: PluginManager.reintentar(
                    opcion.modelData.pluginId)
            }
        }

        //  ── a network action ────────────────
        RowLayout {
            visible: opcion.modelData.tipo === "peligro"
            spacing: 8
            Layout.alignment: Qt.AlignVCenter

            //  A way out without scares: cancel
            //  sits next to the red button.
            IslandLabel {
                visible: opcion.armada
                text: "cancel"
                color: Theme.muted
                font.pixelSize: 10

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        opcion.armada = false
                        desarmar.stop()
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: etiquetaAccion.implicitWidth + 24
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                radius: 13
                color: opcion.armada
                    ? (accionRaton.containsMouse ? "#ff6961" : Theme.red)
                    : (accionRaton.containsMouse ? Theme.surfaceHi : Theme.track)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: etiquetaAccion
                    anchors.centerIn: parent
                    text: opcion.armada
                        ? (opcion.modelData.confirmar || "Yes")
                        : (opcion.modelData.accion || "Do it")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: accionRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (opcion.armada) {
                            Settings.ejecutar(opcion.modelData.id)
                            opcion.armada = false
                            desarmar.stop()
                        } else {
                            opcion.armada = true
                            desarmar.restart()
                        }
                    }
                }
            }
        }

        IslandSwitch {
            //  Only the default type: a choice
            //  carries chips and a text carries a
            //  field.
            visible: !opcion.modelData.tipo
                     && opcion.modelData.error !== "fijo"
            checked: opcion.activa
            onToggled: if (opcion.disponible) Settings.alternar(opcion.modelData.id)
            Layout.alignment: Qt.AlignVCenter
        }

        // ── multi-answer options
        //  The alternatives come from the service. This used to
        //  have `de === "idiomas"` hard-wired and anything else
        //  returned an empty list, so adding a choice forced
        //  touching this screen.
        //
        //  An outside plugin cannot add its case to the service:
        //  it brings its own in `alternativas`, exactly as
        //  K4.Ajustes has promised from the start — until now
        //  that promise painted an empty row.
        RowLayout {
            visible: opcion.modelData.tipo === "eleccion"
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 5

            Repeater {
                model: opcion.modelData.alternativas
                       || Settings.opcionesDe(opcion.modelData.de)

                delegate: Rectangle {
                    id: eleccion
                    required property var modelData
                    readonly property bool puesta:
                        Settings.valor(opcion.modelData.id) === modelData.codigo

                    Layout.preferredWidth: textoEleccion.implicitWidth + 20
                    Layout.preferredHeight: 24
                    radius: 12
                    color: puesta ? Theme.blue
                        : (eleccionRaton.containsMouse
                           ? Theme.surfaceHi : Theme.track)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: textoEleccion
                        anchors.centerIn: parent
                        text: eleccion.modelData.nombre
                        color: eleccion.puesta ? Theme.ink : Theme.muted
                        font.pixelSize: 10
                        font.weight: eleccion.puesta
                            ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: eleccionRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.poner(opcion.modelData.id,
                                                  eleccion.modelData.codigo)
                    }
                }
            }
        }

        //  ── numeric options ───────────
        //  Widths and heights: a value you nudge, not one you type. Two
        //  steppers and the number between them, in the same chip language
        //  as the choices above — a spinbox with a text field would ask for
        //  the keyboard in a page that never needed it.
        RowLayout {
            id: numerico
            visible: opcion.modelData.tipo === "numero"
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            //  The current value, as a number: what arrives from `Settings`
            //  after a `poner` is an int, but a hand-edited file can hold a
            //  string, and `parseInt` of nothing is NaN — which would render
            //  as "NaN px" and clamp to nonsense.
            readonly property int valor: {
                const v = parseInt(Settings.valor(opcion.modelData.id), 10)
                return isNaN(v) ? 0 : v
            }

            //  One step in one direction, clamped to the option's bounds.
            function paso(cuantos) {
                const paso = opcion.modelData.paso || 1
                let n = numerico.valor + cuantos * paso
                if (opcion.modelData.min !== undefined)
                    n = Math.max(opcion.modelData.min, n)
                if (opcion.modelData.max !== undefined)
                    n = Math.min(opcion.modelData.max, n)
                if (n !== numerico.valor)
                    Settings.poner(opcion.modelData.id, n)
            }

            //  A spent stepper does not answer and says so, at 35 % — `enabled`
            //  and not just opacity, or it teaches that clicking does nothing.
            //  The minus goes by codepoint like the ×: a literal minus in a
            //  `text:` is harvested by the text extractor.
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                opacity: menosRaton.enabled ? 1 : 0.35
                color: menosRaton.enabled && menosRaton.containsMouse
                    ? Theme.surfaceHi : Theme.track

                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: menosRaton
                    enabled: numerico.valor
                        > (opcion.modelData.min ?? -Infinity)
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: numerico.paso(-1)
                }

                IslandLabel {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0x2212)
                    color: menosRaton.enabled ? Theme.ink : Theme.muted
                    font.pixelSize: 14
                }
            }

            IslandLabel {
                text: numerico.valor
                    + (opcion.modelData.unidad ? " " + opcion.modelData.unidad : "")
                color: Theme.ink
                font.pixelSize: 11
                font.weight: Font.DemiBold
                Layout.preferredWidth: 64
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                opacity: masRaton.enabled ? 1 : 0.35
                color: masRaton.enabled && masRaton.containsMouse
                    ? Theme.surfaceHi : Theme.track

                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: masRaton
                    enabled: numerico.valor
                        < (opcion.modelData.max ?? Infinity)
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: numerico.paso(1)
                }

                IslandLabel {
                    anchors.centerIn: parent
                    text: "+"
                    color: masRaton.enabled ? Theme.ink : Theme.muted
                    font.pixelSize: 14
                }
            }
        }

        // ── free-text options
        //  A URL, a model, an API key: what a switch cannot
        //  say. El valor se entrega
        //  al confirmar —Intro o clic fuera—, no tecla a
        //  tecla: quien guarda escribe un fichero cada vez.
        Rectangle {
            visible: opcion.modelData.tipo === "texto"
            Layout.preferredWidth: 210
            Layout.preferredHeight: 26
            Layout.alignment: Qt.AlignVCenter
            radius: 13
            color: campo.activeFocus ? Theme.surfaceHi : Theme.track
            border.width: campo.activeFocus ? 1 : 0
            border.color: Theme.blue

            Behavior on color { ColorAnimation { duration: 120 } }

            //  The hint only with the field empty and unfocused:
            //  en cuanto tecleas ya no hace falta.
            IslandLabel {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 11
                visible: campo.text.length === 0 && !campo.activeFocus
                text: opcion.modelData.pista || ""
                color: Theme.dim
                font.pixelSize: 10
            }

            TextInput {
                id: campo
                cursorDelegate: IslandCursor {}
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 10
                clip: true
                selectByMouse: true
                selectionColor: Theme.blue
                //  A secret shows while typed and covers
                //  when stopped: it can be corrected without
                //  the whole token being left in sight.
                echoMode: opcion.modelData.secreto
                    ? TextInput.PasswordEchoOnEdit
                    : TextInput.Normal
                text: opcion.valorTexto
                onEditingFinished: {
                    if (text !== opcion.valorTexto)
                        Settings.poner(opcion.modelData.id, text)
                }
                //  Escape descarta lo tecleado, no lo guarda.
                Keys.onEscapePressed: {
                    text = opcion.valorTexto
                    focus = false
                }
            }
        }
    }

    //  The whole row toggles, not just the switch: they are
    //  40 px tall targets, it would be absurd to force aiming
    //  at the 24 px one.
    //
    //  But only on switch rows. On multi-answer ones this area
    //  sits OVER the chips —it is declared later— and ate their
    //  clicks: the 54 px right margin lets the last one through
    //  and nothing else, so in the language picker only
    //  «English» could be chosen. It had been there since the
    //  screen exists. And the same on text ones: the click is
    //  for the field.
    MouseArea {
        id: filaMouse
        enabled: !opcion.modelData.tipo
        anchors.fill: parent
        anchors.rightMargin: 54     // lets the switch through
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (opcion.disponible)
                Settings.alternar(opcion.modelData.id)
    }
}
