// Plugin-owned Settings page using the shared control and section vocabulary.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "Api.js" as Api

ColumnLayout {
    id: page
    required property var plugin
    property string authMode: "password"
    property string editList: ""
    property int modelPage: 0
    property var deletedList: null
    readonly property string currentList: plugin.pinLists.some(function (list) {
        return list.name === page.editList
    }) ? editList : plugin.pinLists.length ? plugin.pinLists[0].name : ""
    readonly property var pinned: {
        const list = plugin.pinLists.find(function (entry) { return entry.name === page.currentList })
        return list ? list.models || [] : []
    }
    readonly property var filteredModels: Api.withDefaultFirst(plugin.models, plugin.currentModel)
        .filter(function (model) { return model.toLowerCase().indexOf(modelSearch.text.trim().toLowerCase()) >= 0 })
    readonly property int pageCount: Math.max(1, Math.ceil(filteredModels.length / 8))
    onPageCountChanged: modelPage = Math.min(modelPage, pageCount - 1)
    spacing: 16

    Component.onCompleted: if (plugin.autenticado && !plugin.connectionVerified) plugin.fetchModels()
    Component.onDestruction: {
        plugin.draftPassword = ""
        plugin.draftApiKey = ""
    }

    function signIn() {
        plugin.draftServer = server.text
        plugin.draftEmail = email.text.trim()
        plugin.iniciarSesion(email.text.trim(), password.text)
    }
    function saveKey() {
        plugin.draftServer = server.text
        plugin.guardarClave(apiKey.text)
        if (plugin.autenticado) apiKey.clear()
    }
    function addList() {
        if (!listName.text.trim()) return
        plugin.nuevaListaPin(listName.text)
        editList = listName.text.trim()
        listName.clear()
    }

    component Section: Rectangle {
        id: section
        property string title: ""
        default property alias contents: sectionBody.data
        Layout.fillWidth: true
        implicitHeight: sectionBody.implicitHeight + 24
        radius: 12
        color: K4.Tema.superficie
        ColumnLayout {
            id: sectionBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 12
            K4.Etiqueta { text: section.title; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
    }
    component Help: K4.Etiqueta {
        Layout.fillWidth: true
        color: K4.Tema.apagado
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }

    Section {
        title: "Connection"
        RowLayout {
            Layout.fillWidth: true
            Help {
                text: page.plugin.signingIn ? "Signing in…"
                    : page.plugin.fetchingModels ? "Checking connection…"
                    : page.plugin.connectionVerified ? "Connected to " + page.plugin.baseUrl
                    : page.plugin.modelsError ? "Connection could not be verified"
                    : page.plugin.autenticado ? "Credentials saved · connection not verified" : "Not signed in"
                color: page.plugin.connectionVerified ? K4.Tema.verde : K4.Tema.apagado
            }
            K4.ActionButton {
                visible: page.plugin.autenticado
                text: "Log out"
                enabled: !page.plugin.generating
                onClicked: page.plugin.salir()
            }
        }
        K4.Etiqueta { text: "Server address"; font.pixelSize: 12 }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            K4.TextField {
                id: server
                Layout.fillWidth: true
                text: page.plugin.draftServer || page.plugin.baseUrl
                placeholderText: "http://localhost:3000"
                Accessible.name: "Server address"
                enabled: !page.plugin.signingIn && !page.plugin.generating
                onAccepted: {
                    page.plugin.draftServer = text
                    page.plugin.confirmarBorradores()
                }
                Keys.onEscapePressed: function (event) {
                    text = page.plugin.baseUrl
                    focus = false
                    event.accepted = true
                }
            }
            K4.ActionButton {
                text: "Apply"
                enabled: !page.plugin.signingIn && !page.plugin.generating
                    && !page.plugin.fetchingModels && !page.plugin.fetchingChats
                onClicked: {
                    page.plugin.draftServer = server.text
                    page.plugin.confirmarBorradores()
                }
            }
        }
        Help { text: "Apply saves the server address. Changing servers signs out of the previous server." }
        Help {
            visible: page.plugin.signInError.length > 0
            text: page.plugin.signInError
            color: K4.Tema.rojo
        }
        ColumnLayout {
            visible: !page.plugin.autenticado
            Layout.fillWidth: true
            spacing: 12
            RowLayout {
                spacing: 8
                K4.ActionButton { text: "Email and password"; selected: page.authMode === "password"; onClicked: page.authMode = "password" }
                K4.ActionButton { text: "API key"; selected: page.authMode === "key"; onClicked: page.authMode = "key" }
            }
            ColumnLayout {
                visible: page.authMode === "password"
                Layout.fillWidth: true
                spacing: 8
                K4.Etiqueta { text: "Email" }
                K4.TextField {
                    id: email
                    Layout.fillWidth: true
                    text: page.plugin.draftEmail
                    Accessible.name: "Email"
                    placeholderText: "you@example.com"
                    enabled: !page.plugin.signingIn
                }
                K4.Etiqueta { text: "Password" }
                K4.TextField {
                    id: password
                    Layout.fillWidth: true
                    Accessible.name: "Password"
                    echoMode: TextInput.Password
                    enabled: !page.plugin.signingIn
                    onAccepted: page.signIn()
                    Keys.onEscapePressed: function (event) { clear(); focus = false; event.accepted = true }
                }
                K4.ActionButton {
                    text: page.plugin.signingIn ? "Signing in…" : "Sign in"
                    enabled: !page.plugin.signingIn && email.text.trim().length > 0 && password.text.length > 0
                    onClicked: page.signIn()
                }
            }
            ColumnLayout {
                visible: page.authMode === "key"
                Layout.fillWidth: true
                spacing: 8
                K4.Etiqueta { text: "API key" }
                K4.TextField {
                    id: apiKey
                    Layout.fillWidth: true
                    Accessible.name: "API key"
                    echoMode: TextInput.Password
                    placeholderText: "sk-…"
                    onAccepted: page.saveKey()
                    Keys.onEscapePressed: function (event) { clear(); focus = false; event.accepted = true }
                }
                K4.ActionButton { text: "Use API key"; enabled: apiKey.text.trim().length > 0; onClicked: page.saveKey() }
            }
            Help { text: "Your authentication token is saved locally. Password and API-key drafts are cleared when you leave this page." }
        }
    }

    Section {
        title: "Models"
        visible: page.plugin.autenticado
        RowLayout {
            Layout.fillWidth: true
            Help { text: "Default · " + (page.plugin.currentModel || "Choose a model below") }
            K4.ActionButton {
                text: page.plugin.fetchingModels ? "Loading…" : "Refresh"
                enabled: !page.plugin.fetchingModels
                onClicked: page.plugin.fetchModels()
            }
        }
        Help { visible: page.plugin.modelsError.length > 0; text: page.plugin.modelsError; color: K4.Tema.rojo }
        K4.TextField {
            id: modelSearch
            Layout.fillWidth: true
            Accessible.name: "Search models"
            placeholderText: "Search models"
            onTextChanged: page.modelPage = 0
            Keys.onEscapePressed: function (event) {
                if (text.length > 0) { clear(); event.accepted = true }
                else event.accepted = false
            }
        }
        Help {
            text: page.currentList ? "Pin buttons edit “" + page.currentList + "”. Manage pin lists below."
                : "Choose a default model. Create a pin list below to organize favorites."
        }
        Repeater {
            model: page.filteredModels.slice(page.modelPage * 8, page.modelPage * 8 + 8)
            delegate: K4.Baldosa {
                id: modelRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 8
                activa: modelData === page.plugin.currentModel
                Accessible.name: "Use " + modelData + " as the default model"
                onPulsada: page.plugin.setModel(modelData)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 12
                    K4.Glifo {
                        text: String.fromCodePoint(0xF012C)
                        opacity: modelRow.activa ? 1 : 0
                        color: K4.Tema.azul
                        font.pixelSize: 14
                        Layout.preferredWidth: 20
                    }
                    K4.Etiqueta { Layout.fillWidth: true; text: modelRow.modelData; elide: Text.ElideRight }
                    K4.ActionButton {
                        visible: page.currentList.length > 0
                        text: page.pinned.indexOf(modelRow.modelData) >= 0 ? "Unpin" : "Pin"
                        Accessible.name: text + " " + modelRow.modelData + " in " + page.currentList
                        onClicked: page.pinned.indexOf(modelRow.modelData) >= 0
                            ? page.plugin.despinear(page.currentList, modelRow.modelData)
                            : page.plugin.pinear(page.currentList, modelRow.modelData)
                    }
                }
            }
        }
        Help {
            visible: page.filteredModels.length === 0
            text: page.plugin.fetchingModels ? "Loading models…" : page.plugin.models.length > 0
                ? "No matching models. Try a different name." : "No models available. Refresh to try again."
        }
        RowLayout {
            visible: page.pageCount > 1
            Layout.fillWidth: true
            K4.ActionButton { text: "Previous"; enabled: page.modelPage > 0; onClicked: page.modelPage-- }
            Help { text: "Page " + (page.modelPage + 1) + " of " + page.pageCount; horizontalAlignment: Text.AlignHCenter }
            K4.ActionButton { text: "Next"; enabled: page.modelPage + 1 < page.pageCount; onClicked: page.modelPage++ }
        }
    }

    Section {
        title: "Pin lists"
        visible: page.plugin.autenticado
        Help { text: "Organize models into named groups for the chat's model picker." }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: page.plugin.pinLists
                delegate: K4.ActionButton {
                    required property var modelData
                    text: modelData.name
                    selected: text === page.currentList
                    width: Math.min(implicitWidth, parent.width)
                    onClicked: page.editList = modelData.name
                }
            }
        }
        K4.Etiqueta { text: "New list name" }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            K4.TextField { id: listName; Layout.fillWidth: true; Accessible.name: "New list name"; onAccepted: page.addList() }
            K4.ActionButton { text: "Add list"; enabled: listName.text.trim().length > 0; onClicked: page.addList() }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: page.pinned
                delegate: K4.ActionButton {
                    required property var modelData
                    text: modelData + "  ×"
                    width: Math.min(implicitWidth, parent.width)
                    Accessible.name: "Unpin " + modelData + " from " + page.currentList
                    onClicked: page.plugin.despinear(page.currentList, modelData)
                }
            }
        }
        Help { visible: page.currentList.length > 0 && page.pinned.length === 0; text: "This list is empty. Pin models from the Models section." }
        K4.ActionButton {
            visible: page.currentList.length > 0
            text: "Delete list"
            onClicked: {
                const list = page.plugin.pinLists.find(function (entry) { return entry.name === page.currentList })
                page.deletedList = { name: list.name, models: list.models.slice() }
                page.plugin.borrarListaPin(page.currentList)
            }
        }
        RowLayout {
            visible: page.deletedList !== null
            Layout.fillWidth: true
            Help { text: page.deletedList ? "Deleted “" + page.deletedList.name + "”." : "" }
            K4.ActionButton {
                text: "Undo"
                onClicked: {
                    const list = page.deletedList
                    page.plugin.nuevaListaPin(list.name)
                    for (const model of list.models) page.plugin.pinear(list.name, model)
                    page.editList = list.name
                    page.deletedList = null
                }
            }
        }
    }

    Section {
        title: "Chat behavior"
        Repeater {
            model: [
                { key: "rememberHistory", label: "Remember chat history", help: "Keep conversations across restarts and while set aside." },
                { key: "openAfterResponse", label: "Reopen when an answer arrives", help: "Bring the chat forward when a background response finishes." }
            ]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    K4.Etiqueta { Layout.fillWidth: true; text: modelData.label; wrapMode: Text.WordWrap }
                    Help { text: modelData.help }
                }
                K4.Interruptor {
                    marcado: page.plugin[modelData.key]
                    Accessible.name: modelData.label
                    onAlternado: {
                        page.plugin[modelData.key] = !marcado
                        page.plugin.guardarAjustes()
                    }
                }
            }
        }
    }
    Connections {
        target: page.plugin
        function onAutenticadoChanged() {
            if (page.plugin.autenticado) { password.clear(); apiKey.clear() }
        }
    }
}
