//  Una fila de Ajustes: el icono, el nombre, la explicación y el control.
//
//  Vivía dentro de `SettingsView.qml`, incrustada como delegado. Sale a su
//  propio fichero porque ahora la usan DOS vistas —el panel de siempre y la
//  ventana con barra lateral— y dos copias de trescientas líneas divergen a la
//  primera corrección: se arregla una y la otra sigue mintiendo.
//
//  No sabe dónde la pintan. Recibe la definición de la opción y habla con el
//  servicio `Settings`, igual que hacía antes.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
    id: opcion
    required property var modelData
    //  Con `!!` y no a secas. `Settings.valor`
    //  contesta `undefined` a las opciones que aún
    //  no tienen nada guardado y a las que no son
    //  interruptores, y asignar eso a un bool es un
    //  aviso en el log por CADA fila y CADA vez que
    //  se abren los Ajustes — ruido que tapa los
    //  avisos de verdad.
    //
    //  Coaccionar y no comparar con `true`: esto
    //  enciende el ICONO de la fila, y una elección
    //  vale «viaje» y un campo de texto vale una
    //  URL. Con `=== true` se apagaban todas las
    //  filas que no fueran un interruptor.
    readonly property bool activa:
        !!Settings.valor(modelData.id)

    //  A section title inside the stack of rows: not a setting, a divider
    //  that names the group the rows below it belong to. One `tipo` more in
    //  the option definitions — and a page stops being a wall of
    //  forty-pixel rectangles that all weigh the same.
    readonly property bool esTitulo: modelData.tipo === "titulo"

    //  El valor de una opción de texto, siempre como
    //  cadena: un registro externo contesta `false`
    //  cuando todavía no hay nada guardado.
    readonly property string valorTexto: {
        const v = Settings.valor(modelData.id)
        return (v === undefined || v === null || v === false)
            ? "" : String(v)
    }

    // Algunas opciones no pintan nada si su interruptor
    // maestro está apagado: se atenúan y dejan de
    // responder, en vez de mentir sobre lo que hacen.
    //  Y `disponible: false` a secas, para lo que
    //  no depende de otro ajuste sino del mundo:
    //  un programa que no está instalado. Sin
    //  esto, la única forma de decir «esto no
    //  puede funcionar aquí» era no ofrecerlo, y
    //  entonces nadie se entera de que existe.
    readonly property bool disponible:
        (!modelData.requiere
         || Settings.valor(modelData.requiere))
        && modelData.disponible !== false

    //  Las acciones con red van en dos tiempos: el
    //  primer toque arma y el segundo ejecuta, y si
    //  te lo piensas más de unos segundos se
    //  desarma sola. Un diálogo modal sería más
    //  aparatoso y no protegería más.
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
            //  Un plugin puede traer su propia
            //  imagen; el resto de opciones son
            //  glifos y caen por el mismo sitio.
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
                //  El motivo de un plugin roto va
                //  en rojo: es la diferencia entre
                //  «apagado» y «no puede».
                color: opcion.armada ? "#ff9f9f"
                     : (opcion.modelData.error ? Theme.red : Theme.muted)
                font.pixelSize: 9
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        //  Un plugin que no puede cargar no lleva
        //  interruptor: encender lo imposible es
        //  mentir. Si el fallo fue al cargar, la
        //  fila entera reintenta.
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

        //  ── una acción con red ──────────────
        RowLayout {
            visible: opcion.modelData.tipo === "peligro"
            spacing: 8
            Layout.alignment: Qt.AlignVCenter

            //  Salida sin sustos: cancelar está al
            //  lado del botón rojo.
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
            //  Solo el tipo por defecto: una elección
            //  lleva chips y un texto lleva campo.
            visible: !opcion.modelData.tipo
                     && opcion.modelData.error !== "fijo"
            checked: opcion.activa
            onToggled: if (opcion.disponible) Settings.alternar(opcion.modelData.id)
            Layout.alignment: Qt.AlignVCenter
        }

        // ── opciones de varias respuestas
        //  Las alternativas las da el servicio. Aquí estaba
        //  `de === "idiomas"` a fuego y cualquier otra cosa
        //  devolvía una lista vacía, así que añadir una
        //  elección obligaba a tocar esta pantalla.
        //
        //  Un plugin de fuera no puede añadir su caso al
        //  servicio: trae las suyas en `alternativas`, tal
        //  como promete K4.Ajustes desde el principio —
        //  hasta ahora esa promesa pintaba una fila vacía.
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

        //  ── opciones numéricas ───────
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

        // ── opciones de texto libre
        //  Una URL, un modelo, una clave de API: lo que un
        //  interruptor no puede decir. El valor se entrega
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

            //  La pista solo con el campo vacío y sin foco:
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
                //  Un secreto se ve mientras se teclea y se
                //  tapa al parar: se puede corregir sin que
                //  el token entero quede a la vista.
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

    //  Toda la fila conmuta, no solo el interruptor: son
    //  objetivos de 40 px de alto, sería absurdo obligar a
    //  apuntar al de 24.
    //
    //  Pero solo en las filas de interruptor. En las de varias
    //  respuestas esta área va POR ENCIMA de los chips —se
    //  declara después— y les comía el clic: el margen de 54
    //  px por la derecha deja pasar el último y nada más, así
    //  que en el selector de idioma solo se podía elegir
    //  «English». Llevaba ahí desde que existe la pantalla.
    //  Y en las de texto igual: el clic es para el campo.
    MouseArea {
        id: filaMouse
        enabled: !opcion.modelData.tipo
        anchors.fill: parent
        anchors.rightMargin: 54     // deja pasar el interruptor
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (opcion.disponible)
                Settings.alternar(opcion.modelData.id)
    }
}
