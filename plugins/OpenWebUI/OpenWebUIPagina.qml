import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "Api.js" as Api

//  The Settings page the plugin ships: server, sign-in and behavior.
//  Instantiated by the Settings window while its page is on screen;
//  `plugin` is the live engine, so the knobs edited here are the
//  ones the island reads.

ColumnLayout {
    id: pagina

    required property var plugin

    //  The model list, narrowed by the search field. Same rule as
    //  the island's selector: a fragment, case-blind. The chosen
    //  default always says first — `Api.withDefaultFirst`.
    property string modelFilter: ""

    //  Which pin list the editor below is working on. Clicking a
    //  chip moves the editor; every list shows in the island's
    //  picker as its own group, so there is no «active» one to
    //  promote — only this editor's subject.
    property string editList: ""

    Component.onCompleted: {
        editList = plugin.pinLists.length > 0
            ? plugin.pinLists[0].name : ""
    }

    readonly property string listaActual: {
        for (let i = 0; i < plugin.pinLists.length; ++i)
            if (plugin.pinLists[i].name === editList)
                return editList
        return plugin.pinLists.length > 0 ? plugin.pinLists[0].name : ""
    }

    readonly property var modelosDeLista: {
        for (let i = 0; i < plugin.pinLists.length; ++i)
            if (plugin.pinLists[i].name === listaActual)
                return plugin.pinLists[i].models || []
        return []
    }

    readonly property var filteredModels:
        Api.withDefaultFirst(plugin.models, plugin.currentModel).filter(
            function (m) {
                const f = modelFilter.trim().toLowerCase()
                return f.length === 0
                    || String(m).toLowerCase().indexOf(f) >= 0
            })

    spacing: 14

    //  Drafts are saved on a short delay, not per keystroke: writing
    //  the state file on every key is churn for nothing.
    Timer {
        id: borradorTimer
        interval: 500
        onTriggered: pagina.plugin.guardarAjustes()
    }

    //  Leaving the page is the quiet way to commit: the server typed
    //  but never Entered takes effect, and everything else has been
    //  kept along the way.
    Component.onDestruction: pagina.plugin.confirmarBorradores()

    // ── a field, the page's one input shape ───────────────────────

    component Campo: Rectangle {
        id: campo
        property string valor: ""
        property string pista: ""
        property bool secreto: false
        signal aceptado()
        signal editado()

        function clear() {
            entrada.text = ""
            valor = ""
        }

        implicitHeight: 30
        implicitWidth: 220
        radius: 8
        color: Theme.islandBg
        border.width: 1
        border.color: entrada.activeFocus ? Theme.blue : Theme.track

        IslandLabel {
            anchors.fill: parent
            anchors.margins: 8
            visible: entrada.text.length === 0
            text: campo.pista
            color: Theme.dim
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
        }

        TextInput {
            id: entrada
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 12
            clip: true
            selectByMouse: true
            cursorDelegate: IslandCursor {}
            echoMode: campo.secreto ? TextInput.Password : TextInput.Normal
            text: campo.valor

            onTextEdited: {
                campo.valor = text
                campo.editado()
            }
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter) {
                    campo.aceptado()
                    event.accepted = true
                }
            }
        }
    }

    // ── a pill button ─────────────────────────────────────────────

    component Boton: Rectangle {
        id: pastilla
        property string texto: ""
        signal activado()

        implicitHeight: 28
        implicitWidth: etiqueta.implicitWidth + 26
        radius: 14
        color: raton.containsMouse ? Theme.track : Theme.surfaceHi

        Behavior on color { ColorAnimation { duration: 120 } }

        IslandLabel {
            id: etiqueta
            anchors.centerIn: parent
            text: pastilla.texto
            color: Theme.ink
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pastilla.activado()
        }
    }

    // ── connection status ─────────────────────────────────────────

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: filaEstado.implicitHeight + 24
        radius: 14
        color: pagina.plugin.autenticado
            ? Qt.rgba(0.19, 0.82, 0.34, 0.10)
            : Qt.rgba(1.0, 0.27, 0.23, 0.10)

        RowLayout {
            id: filaEstado
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                width: 9
                height: 9
                radius: 5
                color: pagina.plugin.autenticado ? Theme.green : Theme.red

                SequentialAnimation on opacity {
                    running: pagina.plugin.signingIn
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 620; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                text: pagina.plugin.autenticado
                    ? "Connected to " + pagina.plugin.baseUrl
                    : (pagina.plugin.baseUrl.length > 0
                       ? "Not connected — " + pagina.plugin.baseUrl
                       : "Not connected")
                color: pagina.plugin.autenticado ? Theme.ink : Theme.muted
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Boton {
                visible: pagina.plugin.autenticado
                texto: "Log out"
                onActivado: pagina.plugin.salir()
            }
        }
    }

    // ── the server ────────────────────────────────────────────────

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: colServidor.implicitHeight + 24
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.03)

        ColumnLayout {
            id: colServidor
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            IslandLabel {
                text: "Server"
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Campo {
                id: campoServidor
                Layout.fillWidth: true
                valor: pagina.plugin.draftServer
                pista: "http://localhost:3000"

                //  Typing is remembered, not applied: a half-written
                //  URL only becomes the server on Enter — or when
                //  the page closes, in `confirmarBorradores`.
                onEditado: {
                    pagina.plugin.draftServer = valor
                    borradorTimer.restart()
                }

                onAceptado: {
                    pagina.plugin.draftServer = valor
                    pagina.plugin.baseUrl = valor.trim()
                    pagina.plugin.guardarAjustes()
                    if (pagina.plugin.autenticado) {
                        pagina.plugin.fetchModels()
                        pagina.plugin.refreshChats()
                    }
                }
            }

            IslandLabel {
                text: "Where your OpenWebUI lives. Enter applies it."
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }

    // ── sign in, or bring a key ───────────────────────────────────

    Rectangle {
        Layout.fillWidth: true
        visible: !pagina.plugin.autenticado
        implicitHeight: colSesion.implicitHeight + 24
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.03)

        ColumnLayout {
            id: colSesion
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            IslandLabel {
                text: "Sign in"
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Campo {
                id: campoCorreo
                Layout.fillWidth: true
                pista: "email"
                valor: pagina.plugin.draftEmail

                onEditado: {
                    pagina.plugin.draftEmail = valor
                    borradorTimer.restart()
                }
            }

            Campo {
                id: campoClave
                Layout.fillWidth: true
                pista: "password"
                secreto: true
                valor: pagina.plugin.draftPassword

                onEditado: {
                    pagina.plugin.draftPassword = valor
                    borradorTimer.restart()
                }

                onAceptado: pagina.plugin.iniciarSesion(
                    campoCorreo.valor.trim(), campoClave.valor)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Boton {
                    texto: pagina.plugin.signingIn ? "Signing in…" : "Sign in"
                    onActivado: pagina.plugin.iniciarSesion(
                        campoCorreo.valor.trim(), campoClave.valor)
                }

                IslandLabel {
                    Layout.fillWidth: true
                    visible: pagina.plugin.signInError.length > 0
                    text: pagina.plugin.signInError
                    color: Theme.red
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            // the divider that says the two roads are equal
            Item {
                Layout.fillWidth: true
                implicitHeight: 18

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: palabraIzquierda.left
                    anchors.rightMargin: 8
                    height: 1
                    color: Theme.surfaceHi
                }

                IslandLabel {
                    id: palabraIzquierda
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "or"
                    color: Theme.dim
                    font.pixelSize: 10
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: palabraIzquierda.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    height: 1
                    color: Theme.surfaceHi
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF0306) // md-key
                    color: Theme.muted
                    font.pixelSize: 13
                }

                Campo {
                    id: campoLlave
                    Layout.fillWidth: true
                    pista: "sk-…"
                    secreto: true
                    valor: pagina.plugin.draftApiKey

                    onEditado: {
                        pagina.plugin.draftApiKey = valor
                        borradorTimer.restart()
                    }

                    onAceptado: pagina.plugin.guardarClave(valor)
                }

                Boton {
                    texto: "Save"
                    onActivado: pagina.plugin.guardarClave(campoLlave.valor)
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                text: "The token is stored under ~/.local/state/k4, like the web client's cookie."
                color: Theme.dim
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── the model ─────────────────────────────────────────────────

    Rectangle {
        Layout.fillWidth: true
        visible: pagina.plugin.autenticado
        implicitHeight: colModelo.implicitHeight + 24
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.03)

        ColumnLayout {
            id: colModelo
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF06A9) // md-robot
                    color: Theme.muted
                    font.pixelSize: 13
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: "Model"
                    color: Theme.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Boton {
                    texto: pagina.plugin.fetchingModels ? "…" : "Refresh"
                    onActivado: pagina.plugin.fetchModels()
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                text: pagina.plugin.fetchingModels
                    ? "Loading models…"
                    : pagina.plugin.modelsError.length > 0
                        ? pagina.plugin.modelsError
                        : (pagina.plugin.models.length > 0
                           ? pagina.plugin.currentModel + "  ·  "
                             + pagina.plugin.models.length + " models"
                           : "No models yet — refresh to look")
                color: pagina.plugin.modelsError.length > 0
                        ? Theme.red : Theme.dim
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            // ── pin lists: what the island's picker speaks
            IslandLabel {
                Layout.fillWidth: true
                visible: pagina.plugin.autenticado
                text: "Pin lists"
                color: Theme.ink
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            //  The lists themselves: click one to edit it below.
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: pagina.plugin.pinLists.length > 0

                Repeater {
                    model: pagina.plugin.pinLists

                    delegate: Rectangle {
                        required property var modelData
                        width: chipLista.implicitWidth + 20
                        height: 24
                        radius: 12
                        color: modelData.name === pagina.listaActual
                            ? (chipMouse.containsMouse ? Theme.track : Theme.surfaceHi)
                            : (chipMouse.containsMouse ? Theme.surfaceHi : "transparent")

                        RowLayout {
                            id: chipLista
                            anchors.centerIn: parent
                            spacing: 5

                            IslandLabel {
                                text: modelData.name
                                color: modelData.name === pagina.listaActual
                                        ? Theme.ink : Theme.muted
                                font.pixelSize: 11
                            }

                            IconGlyph {
                                text: String.fromCodePoint(0xF0403) // md-pin
                                color: modelData.name === pagina.listaActual
                                        ? Theme.blue : Theme.dim
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pagina.editList = modelData.name
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Campo {
                    id: campoLista
                    Layout.fillWidth: true
                    pista: "new list name"

                    onAceptado: {
                        pagina.plugin.nuevaListaPin(valor)
                        pagina.editList = valor.trim()
                        campoLista.clear()
                    }
                }

                Boton {
                    texto: "Add"
                    onActivado: {
                        pagina.plugin.nuevaListaPin(campoLista.valor)
                        pagina.editList = campoLista.valor.trim()
                        campoLista.clear()
                    }
                }
            }

            //  The list under the editor: its models as chips, one
            //  click to take one out.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: pagina.listaActual.length > 0

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: pagina.modelosDeLista.length > 0

                    Repeater {
                        model: pagina.modelosDeLista

                        delegate: Rectangle {
                            required property var modelData
                            width: chipPineado.implicitWidth + 24
                            height: 24
                            radius: 12
                            color: pineadoMouse.containsMouse
                                ? Theme.track : Theme.surfaceHi

                            RowLayout {
                                id: chipPineado
                                anchors.centerIn: parent
                                spacing: 5

                                IslandLabel {
                                    text: modelData
                                    color: Theme.ink
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                IconGlyph {
                                    text: Theme.ico.close
                                    color: Theme.muted
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: pineadoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pagina.plugin.despinear(
                                    pagina.listaActual, modelData)
                            }
                        }
                    }
                }

                IslandLabel {
                    visible: pagina.modelosDeLista.length === 0
                    text: "Empty — pin models from the list below"
                    color: Theme.dim
                    font.pixelSize: 10
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Boton {
                        texto: "Delete list"
                        onActivado: pagina.plugin.borrarListaPin(
                            pagina.listaActual)
                    }

                    Item { Layout.fillWidth: true }

                    IslandLabel {
                        visible: pagina.modelosDeLista.length > 0
                        text: pagina.modelosDeLista.length + " pinned"
                        color: Theme.dim
                        font.pixelSize: 10
                    }
                }
            }

            //  Finding one name among dozens: the search narrows the
            //  list below as it is typed, case-blind.
            Campo {
                visible: pagina.plugin.models.length > 0
                Layout.fillWidth: true
                pista: "Search models…"

                onEditado: pagina.modelFilter = valor
            }

            ListView {
                Layout.fillWidth: true
                visible: pagina.plugin.models.length > 0
                implicitHeight: Math.min(240,
                                         pagina.filteredModels.length * 30 + 4)
                clip: true
                spacing: 2
                model: pagina.filteredModels
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: IslandScrollBar {}

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    radius: 8
                    color: modelData === pagina.plugin.currentModel
                        ? (ratonModelo.containsMouse ? Theme.track : Theme.surfaceHi)
                        : (ratonModelo.containsMouse ? Theme.surfaceHi : "transparent")

                    //  The row's click goes UNDER the content: the
                    //  pin icon carries a MouseArea of its own, and
                    //  a row declared later would sit on top of it
                    //  and eat every pin click — picking the default
                    //  instead, which is what the pin was not doing.
                    MouseArea {
                        id: ratonModelo
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pagina.plugin.setModel(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        IslandLabel {
                            text: modelData
                            color: modelData === pagina.plugin.currentModel
                                ? Theme.ink : Theme.muted
                            font.weight: modelData
                                === pagina.plugin.currentModel
                                ? Font.DemiBold : Font.Normal
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        IconGlyph {
                            visible: modelData === pagina.plugin.currentModel
                            text: Theme.ico.check
                            color: Theme.blue
                            font.pixelSize: 11
                        }

                        //  Pin it to the list being edited — or take
                        //  it out. With no list to edit, the pin is
                        //  asleep: nothing to pin to.
                        IconGlyph {
                            visible: pagina.listaActual.length > 0
                            text: pagina.modelosDeLista.indexOf(modelData) >= 0
                                ? String.fromCodePoint(0xF0403)      // md-pin
                                : String.fromCodePoint(0xF0931)      // md-pin_outline
                            color: pinMouse.containsMouse ? Theme.blue : Theme.muted
                            font.pixelSize: 12
                            Layout.leftMargin: 6

                            MouseArea {
                                id: pinMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (pagina.modelosDeLista.indexOf(
                                            modelData) >= 0)
                                        pagina.plugin.despinear(
                                            pagina.listaActual, modelData)
                                    else
                                        pagina.plugin.pinear(
                                            pagina.listaActual, modelData)
                                }
                            }
                        }
                    }
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                visible: pagina.plugin.models.length > 0
                          && pagina.filteredModels.length === 0
                text: "No model matches the search"
                color: Theme.dim
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }

            //  How the pieces meet, said where the pieces live: the
            //  island's picker shows every pin list as its own
            //  group, the default rides on top of its group, and
            //  everything here is remembered.
            IslandLabel {
                Layout.fillWidth: true
                visible: pagina.plugin.autenticado
                text: "The chat island's model picker shows every pin list as its own group — the default model's group first, the default on top of it — and grows tall enough to be read. «Show all models» there brings the whole catalog back for a moment. Clicking a row here sets the default; the pin puts a model in, or takes it out of, the list being edited. The default and the lists are kept in the plugin's state, across restarts."
                color: Theme.dim
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── behavior ──────────────────────────────────────────────────

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: colComportamiento.implicitHeight + 24
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.03)

        ColumnLayout {
            id: colComportamiento
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    IslandLabel {
                        text: "Remember chat history"
                        color: Theme.ink
                        font.pixelSize: 12
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: "Keep the conversation across restarts and in the set-aside pill"
                        color: Theme.dim
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }

                IslandSwitch {
                    checked: pagina.plugin.rememberHistory
                    onToggled: {
                        //  The switch never flips itself — the state
                        //  is the owner's to set, so say the opposite
                        //  of what it shows, not what it shows.
                        pagina.plugin.rememberHistory = !checked
                        pagina.plugin.guardarAjustes()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    IslandLabel {
                        text: "Reopen when an answer lands"
                        color: Theme.ink
                        font.pixelSize: 12
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: "A background answer brings the chat back to the front; off, it only notifies"
                        color: Theme.dim
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }

                IslandSwitch {
                    checked: pagina.plugin.openAfterResponse
                    onToggled: {
                        pagina.plugin.openAfterResponse = !checked
                        pagina.plugin.guardarAjustes()
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: false; implicitHeight: 1 }
}
