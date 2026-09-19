import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "Api.js" as Api

FadeIn {
    id: view

    required property var plugin

    property int focusAttempts: 0
    property bool selectorVisible: false
    property var expandedThinking: ({})

    function setThinkingExpanded(id, expanded) {
        const next = Object.assign({}, expandedThinking)
        next[id] = expanded
        expandedThinking = next
    }

    function submit() {
        if (plugin.send()) {
            charla.sigue = true
            askInput.text = plugin.query
            Qt.callLater(function () { conversationList.positionViewAtEnd() })
        }
    }

    //  What the selector's search box has narrowed the model list
    //  to. The list itself is the PIN LISTS — every one its own
    //  group — not the whole catalog; the default model rides on
    //  top of its group, and «Show all» flattens the catalog back
    //  in. Recomputed per keystroke: a filter that lags a keystroke
    //  feels broken.
    property string modelFilter: ""
    property bool selectorAll: false

    //  The flag is the island's to know, not the view's alone: the
    //  popup needs more height than the empty state has, and the
    //  height binding lives in the plugin.
    onSelectorVisibleChanged: plugin.selectorOpen = selectorVisible

    readonly property var selectorEntries: {
        if (selectorAll)
            return Api.withDefaultFirst(plugin.models,
                                        plugin.currentModel).map(
                function (m) { return { lista: "", modelo: m } })
        //  The group holding the default goes first, and the default
        //  opens it — top of the list, where a default belongs.
        const def = plugin.currentModel
        const lists = plugin.pinLists.slice().sort(function (a, b) {
            return (a.models.indexOf(def) >= 0 ? 0 : 1)
                 - (b.models.indexOf(def) >= 0 ? 0 : 1)
        })
        const out = []
        let defVisto = false
        for (let i = 0; i < lists.length; ++i) {
            const modelos = Api.withDefaultFirst(lists[i].models, def)
            for (let j = 0; j < modelos.length; ++j) {
                if (modelos[j] === def)
                    defVisto = true
                out.push({ lista: lists[i].name, modelo: modelos[j] })
            }
        }
        //  A default nobody pinned still has to be pickable.
        if (!defVisto && def.length > 0)
            out.unshift({ lista: "Default", modelo: def })
        return out
    }
    readonly property var filteredModels: selectorEntries.filter(
        function (e) {
            const f = modelFilter.trim().toLowerCase()
            return f.length === 0
                || String(e.modelo).toLowerCase().indexOf(f) >= 0
        })
    readonly property bool hayPineados: {
        for (let i = 0; i < plugin.pinLists.length; ++i)
            if (plugin.pinLists[i].models.length > 0)
                return true
        return false
    }
    //  How many group headers the filtered list still shows — the
    //  popup's height counts them, or it clips the last rows again.
    readonly property int seccionesVisibles: {
        const vistos = []
        for (let i = 0; i < filteredModels.length; ++i)
            if (filteredModels[i].lista.length > 0
                    && vistos.indexOf(filteredModels[i].lista) < 0)
                vistos.push(filteredModels[i].lista)
        return vistos.length
    }

    Component.onCompleted: {
        focusAttempts = 0
        focusTimer.start()
        Qt.callLater(function () { askInput.forceActiveFocus() })
        aterrizar()
    }

    //  Landing at the bottom is decided at birth, not left to the
    //  follow logic: the view opens on the freshest words, and only
    //  the reader leaving the bottom changes that. The landing is
    //  two-step — once now, once after the first delegates settle —
    //  because the first pass positions against ListView's
    //  estimates, and a whole chat switched in from the sidebar
    //  needs the same fresh start.
    function aterrizar() {
        charla.sigue = true
        Qt.callLater(function () {
            conversationList.positionViewAtEnd()
            aterrizaje.restart()
        })
    }

    Timer {
        id: aterrizaje
        interval: 120
        onTriggered: {
            charla.sigue = true
            conversationList.positionViewAtEnd()
        }
    }

    Connections {
        target: plugin
        function onChatLoadsChanged() {
            view.expandedThinking = ({})
            view.aterrizar()
        }
        function onQueryChanged() {
            if (askInput.text !== view.plugin.query)
                askInput.text = view.plugin.query
        }
    }

    // The layer surface takes a moment to receive keyboard focus:
    // it is retried a few times instead of assuming it arrived on the
    // first try.
    Timer {
        id: focusTimer
        interval: 140
        onTriggered: {
            if (!view.plugin.open)
                return

            askInput.forceActiveFocus()
            if (!askInput.activeFocus && view.focusAttempts < 6) {
                view.focusAttempts += 1
                restart()
            }
        }
    }

    // A title cut to the width the row has room for, said in one
    // place so the sidebar and the header agree on what a «short»
    // title is.
    function corto(t, n) {
        const s = String(t || "")
        return s.length > n ? s.substring(0, n - 1) + "…" : s
    }

    // ── the model selector, over whatever is underneath ───────────

    MouseArea {
        z: 8
        anchors.fill: parent
        visible: view.selectorVisible
        onClicked: view.selectorVisible = false
    }

    Rectangle {
        id: selector
        z: 9
        visible: view.selectorVisible && view.plugin.autenticado
        x: parent.width - width - 12
        y: 30
        width: 280
        height: Math.min(360, 74 + view.filteredModels.length * 30
                             + view.seccionesVisibles * 20 + 26)
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.track

        //  Opening starts the search empty and holding the keys;
        //  closing hands them back to the chat input — the layer's
        //  keyboard is a spotlight, and it points where it is asked.
        onVisibleChanged: {
            if (visible) {
                view.modelFilter = ""
                view.selectorAll = false
                modelSearch.clear()
                modelSearch.forceActiveFocus()
            } else {
                askInput.forceActiveFocus()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                IconGlyph {
                    text: String.fromCodePoint(0xF06A9) // md-robot
                    color: Theme.muted
                    font.pixelSize: 12
                }

                IslandLabel {
                    text: "Model"
                    color: Theme.muted
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }

                MediaButton {
                    glyph: Theme.ico.close
                    glyphSize: 12
                    glyphColor: Theme.muted
                    onActivated: view.selectorVisible = false
                }
            }

            //  The filter: type a fragment, the list keeps the names
            //  that carry it. Enter takes the first one standing.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 7
                color: Theme.islandBg
                border.width: 1
                border.color: modelSearch.activeFocus ? Theme.blue
                                                      : Theme.track

                IslandLabel {
                    anchors.fill: parent
                    anchors.margins: 7
                    visible: modelSearch.text.length === 0
                    text: "Search models…"
                    color: Theme.dim
                    font.pixelSize: 10
                    verticalAlignment: Text.AlignVCenter
                }

                TextInput {
                    id: modelSearch
                    anchors.fill: parent
                    anchors.margins: 7
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    clip: true
                    selectByMouse: true
                    cursorDelegate: IslandCursor {}
                    text: view.modelFilter
                    onTextEdited: view.modelFilter = text

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Escape) {
                            view.selectorVisible = false
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return
                                   || event.key === Qt.Key_Enter) {
                            if (view.filteredModels.length > 0) {
                                view.plugin.setModel(
                                    view.filteredModels[0].modelo)
                                view.selectorVisible = false
                            }
                            event.accepted = true
                        }
                    }
                }
            }

            ListView {
                id: listaModelos
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: view.filteredModels.length > 0
                clip: true
                model: view.filteredModels
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: IslandScrollBar {}

                //  A header per pin list; empty titles (the «all»
                //  mode) take no room at all.
                section.property: "lista"
                section.delegate: Item {
                    width: ListView.view.width
                    height: section !== "" ? 20 : 0
                    visible: section !== ""

                    IslandLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 9
                        text: section
                        color: Theme.dim
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                    }
                }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    radius: 8
                    color: modelData.modelo === view.plugin.currentModel
                        ? Theme.surfaceHi
                        : (filaMouse.containsMouse ? Theme.surfaceHi
                                                   : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 7

                        IconGlyph {
                            text: String.fromCodePoint(0xF06A9) // md-robot
                            color: Theme.muted
                            font.pixelSize: 11
                        }

                        IslandLabel {
                            text: modelData.modelo
                            color: modelData.modelo
                                    === view.plugin.currentModel
                                ? Theme.ink : Theme.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        IconGlyph {
                            visible: modelData.modelo
                                     === view.plugin.currentModel
                            text: Theme.ico.check
                            color: Theme.blue
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: filaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.setModel(modelData.modelo)
                            view.selectorVisible = false
                        }
                    }
                }
            }

            //  Nothing left standing after the filter said its word
            IslandLabel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !view.plugin.fetchingModels
                          && view.filteredModels.length === 0
                text: !view.selectorAll && !view.hayPineados
                      ? "Nothing pinned — pin models in Settings"
                      : "No model matches"
                color: Theme.dim
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // fetching, failed or empty — the footer says which
            IslandLabel {
                Layout.fillWidth: true
                visible: view.plugin.fetchingModels
                text: "Loading models…"
                color: Theme.dim
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter

                SequentialAnimation on opacity {
                    running: view.plugin.fetchingModels
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                visible: !view.plugin.fetchingModels
                          && view.plugin.modelsError.length > 0
                text: view.corto(view.plugin.modelsError, 38)
                color: Theme.red
                font.pixelSize: 10
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            //  Pinned is the door, all is the corridor: the toggle
            //  stays in reach so the one model nobody pinned is two
            //  clicks away, not a trip to Settings.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                visible: view.plugin.autenticado

                IslandLabel {
                    anchors.centerIn: parent
                    text: view.selectorAll ? "Pinned only"
                                           : "Show all models"
                    color: todoMouse.containsMouse ? Theme.ink : Theme.blue
                    font.pixelSize: 10

                    MouseArea {
                        id: todoMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.selectorAll = !view.selectorAll
                    }
                }
            }
        }
    }

    // ── the auth wall ─────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        visible: !view.plugin.autenticado
        color: "transparent"

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 380)
            spacing: 10

            IconGlyph {
                Layout.alignment: Qt.AlignHCenter
                text: String.fromCodePoint(0xF0498) // md-shield
                color: Theme.muted
                font.pixelSize: 40
            }

            IslandLabel {
                Layout.alignment: Qt.AlignHCenter
                text: "Authentication required"
                color: Theme.ink
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            IslandLabel {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "This chat talks to an OpenWebUI server. Sign in, or paste an API key, in Settings."
                color: Theme.muted
                font.pixelSize: 11
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                Layout.preferredWidth: botonAjustes.implicitWidth + 26
                Layout.preferredHeight: 28
                radius: 14
                color: ajustesMouse.containsMouse ? Theme.track
                                                  : Theme.surfaceHi

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: botonAjustes
                    anchors.centerIn: parent
                    spacing: 6

                    IconGlyph {
                        text: Theme.ico.cog
                        color: Theme.ink
                        font.pixelSize: 11
                    }

                    IslandLabel {
                        text: "Open settings"
                        color: Theme.ink
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: ajustesMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.plugin.abrirAjustes()
                }
            }
        }
    }

    // ── the chat ──────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 10
        visible: view.plugin.autenticado

        // ── header: what gets sent and conversation control
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 22
            spacing: 8

            //  The chat history, one corner away — always offered,
            //  never forced: the sidebar itself stays closed until
            //  the button says otherwise.
            MediaButton {
                glyph: String.fromCodePoint(0xF06FD) // md-page_layout_sidebar_left
                Accessible.name: "Toggle chat history"
                HoverHandler { id: historyHover }
                ToolTip.visible: historyHover.hovered
                ToolTip.text: "Chat history"
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: {
                    view.plugin.sidebarVisible
                        = !view.plugin.sidebarVisible
                    view.plugin.guardarEstado()
                }
            }

            IslandLabel {
                text: view.plugin.chatTitle.length > 0
                        ? view.plugin.chatTitle
                        : "OpenWebUI"
                color: Theme.muted
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.maximumWidth: 190
                Layout.minimumWidth: 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            // the model, one tap away from changing
            Rectangle {
                visible: view.plugin.currentModel.length > 0
                Layout.preferredWidth: Math.min(filaModelo.implicitWidth + 18, 200)
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                radius: 10
                color: modeloMouse.containsMouse ? Theme.track
                                                 : Theme.surfaceHi

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: filaModelo
                    anchors.centerIn: parent
                    spacing: 5

                    IconGlyph {
                        text: String.fromCodePoint(0xF06A9) // md-robot
                        color: Theme.muted
                        font.pixelSize: 11
                    }

                    IslandLabel {
                        text: view.plugin.currentModel
                        color: Theme.muted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.maximumWidth: 150
                    }

                    IconGlyph {
                        text: view.selectorVisible ? Theme.ico.chevronUp
                                                   : Theme.ico.chevronDown
                        color: Theme.dim
                        font.pixelSize: 9
                    }
                }

                MouseArea {
                    id: modeloMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!view.selectorVisible
                                && view.plugin.models.length === 0)
                            view.plugin.fetchModels()
                        view.selectorVisible = !view.selectorVisible
                    }
                }
            }

            Repeater {
                parent: attachmentsRow
                model: [
                    { key: "image", on: view.plugin.image.length > 0,
                      attached: true, glyph: Theme.ico.shot,
                      label: "screenshot" },
                    { key: "selection",
                      on: view.plugin.selection.length > 0
                           || view.plugin.selectionCandidate.length > 0,
                      attached: view.plugin.selection.length > 0,
                      glyph: Theme.ico.selection,
                      label: view.plugin.selection.length > 0
                          ? view.plugin.preview(view.plugin.selection)
                          : "attach: "
                            + view.plugin.preview(view.plugin.selectionCandidate) }
                ]

                delegate: Rectangle {
                    id: attachmentChip
                    required property var modelData
                    visible: modelData.on
                    Layout.preferredWidth: Math.min(chipRow.implicitWidth + 18, 260)
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignVCenter
                    radius: 10
                    color: attachmentChip.modelData.attached
                        ? (attachmentMouse.containsMouse ? Theme.track : Theme.surfaceHi)
                        : (attachmentMouse.containsMouse ? Theme.surfaceHi : "transparent")
                    border.width: attachmentChip.modelData.attached ? 0 : 1
                    border.color: Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: chipRow
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 5

                        IconGlyph {
                            text: attachmentChip.modelData.glyph
                            color: attachmentChip.modelData.attached ? Theme.ink : Theme.muted
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IslandLabel {
                            text: attachmentChip.modelData.label
                            color: attachmentChip.modelData.attached ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IconGlyph {
                            text: attachmentChip.modelData.attached ? Theme.ico.close : "⇥"
                            color: attachmentMouse.containsMouse ? Theme.ink : Theme.dim
                            font.pixelSize: attachmentChip.modelData.attached ? 11 : 10
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    // click: attaches the offered one, or removes the
                    // already attached
                    MouseArea {
                        id: attachmentMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (attachmentChip.modelData.key === "image")
                                view.plugin.image = ""
                            else if (attachmentChip.modelData.attached)
                                view.plugin.selection = ""
                            else
                                view.plugin.attach()
                        }
                    }
                }
            }

            IslandLabel {
                text: view.plugin.editingId.length > 0
                           ? "editing · esc cancels"
                           : "esc"
                color: view.plugin.editingId.length > 0
                        && !view.plugin.generating ? Theme.blue : Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter

            }

            // actions on the conversation
            MediaButton {
                glyph: String.fromCodePoint(0xF0415) // md-plus
                Accessible.name: "New chat"
                HoverHandler { id: newChatHover }
                ToolTip.visible: newChatHover.hovered
                ToolTip.text: "New chat"
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.newChat()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                visible: view.plugin.messages.length > 0
                glyph: Theme.ico.copy
                Accessible.name: "Copy latest answer"
                HoverHandler { id: copyAnswerHover }
                ToolTip.visible: copyAnswerHover.hovered
                ToolTip.text: "Copy latest answer"
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.copyAnswer()
                Layout.alignment: Qt.AlignVCenter
            }

            //  Set aside and forget, in plain sight. Closing with
            //  Escape already set the conversation aside, but a
            //  gesture that cannot be seen does not exist: the −
            //  leaves it waiting in the pill and the ✕ truly throws
            //  it away.
            MediaButton {
                visible: view.plugin.messages.length > 0
                glyph: String.fromCodePoint(0xEABA)
                Accessible.name: "Set chat aside"
                HoverHandler { id: asideHover }
                ToolTip.visible: asideHover.hovered
                ToolTip.text: "Set aside · Escape"
                glyphSize: 12
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                visible: view.plugin.messages.length > 0
                glyph: Theme.ico.close
                Accessible.name: "Close and clear local chat"
                HoverHandler { id: clearChatHover }
                ToolTip.visible: clearChatHover.hovered
                ToolTip.text: "Close and clear local chat"
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.cerrarYOlvidar()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── sidebar and conversation
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            visible: view.plugin.messages.length > 0
                     || view.plugin.sidebarVisible

            // ── the server's chats
            Rectangle {
                id: barraLateral
                visible: view.plugin.sidebarVisible
                Layout.preferredWidth: 230
                Layout.fillHeight: true
                radius: 12
                color: Theme.islandBg
                border.width: 1
                border.color: Theme.surfaceHi

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        IslandLabel {
                            text: "Chats"
                            color: Theme.muted
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        MediaButton {
                            glyph: Theme.ico.loading
                            glyphSize: 12
                            glyphColor: Theme.muted
                            enabledAction: !view.plugin.fetchingChats
                            onActivated: view.plugin.refreshChats()
                        }

                        MediaButton {
                            glyph: String.fromCodePoint(0xF0415) // md-plus
                            glyphSize: 13
                            glyphColor: Theme.muted
                            onActivated: view.plugin.newChat()
                        }
                    }

                    ListView {
                        id: listaChats
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: view.plugin.chatList
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: IslandScrollBar {}

                        //  The list grows as it is scrolled: close to
                        //  the end is close enough to ask for more.
                        onContentYChanged: {
                            if (contentHeight - contentY - height < 200)
                                view.plugin.cargarMasChats()
                        }

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 38
                            radius: 8
                            property bool activo:
                                modelData.id === view.plugin.currentChatId
                            color: activo
                                ? (chatMouse.containsMouse ? Qt.darker(Theme.surfaceHi, 1.05) : Theme.surfaceHi)
                                : (chatMouse.containsMouse ? Theme.surfaceHi : "transparent")

                            Behavior on color { ColorAnimation { duration: 100 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 1

                                RowLayout {
                                    spacing: 6
                                    Layout.fillWidth: true

                                    IconGlyph {
                                        text: activo ? Theme.ico.ask
                                                     : String.fromCodePoint(0xF0B79) // md-chat
                                        color: activo ? Theme.ink : Theme.muted
                                        font.pixelSize: 10
                                    }

                                    IslandLabel {
                                        text: view.corto(
                                            modelData.title || "Untitled", 20)
                                        color: activo ? Theme.ink : Theme.muted
                                        font.pixelSize: 10
                                        font.weight: activo ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // the one being opened, spinning in place
                                    IconGlyph {
                                        visible: view.plugin.fetchingChatId
                                                 === modelData.id
                                        text: Theme.ico.loading
                                        color: Theme.blue
                                        font.pixelSize: 10

                                        RotationAnimation on rotation {
                                            running: visible
                                            loops: Animation.Infinite
                                            from: 0
                                            to: 360
                                            duration: 1000
                                        }
                                    }
                                }

                                IslandLabel {
                                    text: Api.relativeTime(modelData.updated_at)
                                    color: Theme.dim
                                    font.pixelSize: 9
                                }
                            }

                            MouseArea {
                                id: chatMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.plugin.cargarChat(modelData.id)
                            }
                        }

                        // what the list says when there is nothing in it
                        IslandLabel {
                            anchors.centerIn: parent
                            visible: view.plugin.chatList.length === 0
                                     && !view.plugin.fetchingChats
                            text: view.plugin.chatsError.length > 0
                                  ? view.corto(view.plugin.chatsError, 30)
                                  : "No chats yet"
                            color: view.plugin.chatsError.length > 0
                                   ? Theme.red : Theme.dim
                            font.pixelSize: 10
                        }

                        IslandLabel {
                            anchors.centerIn: parent
                            visible: view.plugin.fetchingChats
                                     && view.plugin.chatList.length === 0
                            text: "Loading chats…"
                            color: Theme.dim
                            font.pixelSize: 10

                            SequentialAnimation on opacity {
                                running: visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        visible: view.plugin.chatsError.length > 0
                                  && view.plugin.chatList.length > 0
                        text: view.corto(view.plugin.chatsError, 32)
                        color: Theme.red
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
            }

            // ── the conversation
            //
            //  Following is the reader's decision, not a law of the
            //  list: while the reader sits at the bottom, what
            //  arrives scrolls into view; the moment they leave the
            //  bottom — mid-drag, half a page up — the list holds
            //  still. Before, every contentHeight twitch (delegates
            //  settling above the viewport as ListView replaces its
            //  estimates with real heights) snapped the view to the
            //  end, and a long chat could not be scrolled back.
            Item {
                id: charla
                Layout.fillWidth: true
                Layout.fillHeight: true

                property bool sigue: true

                ListView {
                    id: conversationList
                    objectName: "conversationList"
                    anchors.fill: parent
                    visible: view.plugin.messages.length > 0
                    clip: true
                    spacing: 18
                    model: view.plugin.messages
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: IslandScrollBar {
                        onPressedChanged: charla.sigue = pressed ? false : conversationList.alFinal
                    }
                    WheelHandler {
                        target: null
                        onWheel: function (event) {
                            if (event.angleDelta.y > 0 || event.pixelDelta.y > 0) charla.sigue = false
                            event.accepted = false
                        }
                    }

                    readonly property bool alFinal:
                        contentY >= originY + contentHeight - height - 40

                    onCountChanged: if (charla.sigue)
                        Qt.callLater(function () { positionViewAtEnd() })
                    onContentHeightChanged: if (charla.sigue)
                        Qt.callLater(function () { positionViewAtEnd() })
                    //  The list shrinking — the streaming row growing
                    //  under it — moves the bottom too.
                    onHeightChanged: if (charla.sigue)
                        Qt.callLater(function () { positionViewAtEnd() })

                    //  Leaving the bottom disarms the following at
                    //  once, while the drag is still happening:
                    //  waiting for the movement to end left a window
                    //  where a settling delegate stole it back.
                    onContentYChanged: {
                        if (moving && !alFinal)
                            charla.sigue = false
                    }
                    onMovementEnded: charla.sigue = alFinal

                    delegate: ChatMessage {
                        required property var modelData
                        required property int index
                        width: conversationList.width - 12
                        message: modelData
                        editing: view.plugin.editingId === modelData.id
                        expanded: view.expandedThinking[modelData.id] === true
                        canRetry: !view.plugin.generating && index === view.plugin.messages.length - 1
                            && (modelData.role === "error" || modelData.status === "failed" || modelData.status === "stopped")
                        onExpansionChanged: function (expanded) { view.setThinkingExpanded(modelData.id, expanded) }
                        onSelectionStarted: charla.sigue = false
                        onCopyRequested: function (text) { view.plugin.copyText(text) }
                        onEditRequested: {
                            view.plugin.editar(modelData.id)
                            askInput.forceActiveFocus()
                            askInput.cursorPosition = askInput.text.length
                        }
                        onRetryRequested: view.plugin.retryLast()
                    }

                    footer: ChatMessage {
                        width: conversationList.width - 12
                        visible: view.plugin.generating
                        height: visible ? implicitHeight : 0
                        message: ({ id: view.plugin.responseId, role: "assistant",
                            content: view.plugin.currentResponse, reasoning: view.plugin.currentReasoning,
                            model: view.plugin.responseModel })
                        streaming: true
                        phase: view.plugin.responsePhase
                        elapsed: view.plugin.reasoningSeconds
                        expanded: view.expandedThinking[view.plugin.responseId] === true
                        onExpansionChanged: function (expanded) { view.setThinkingExpanded(view.plugin.responseId, expanded) }
                        onCopyRequested: function (text) { view.plugin.copyText(text) }
                        onSelectionStarted: charla.sigue = false
                        onHeightChanged: if (visible && charla.sigue)
                            Qt.callLater(function () { conversationList.positionViewAtEnd() })
                    }
                }

                //  The way back: once the reader has gone up, the
                //  bottom is one click away instead of a scroll.
                K4.ActionButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    visible: !charla.sigue && conversationList.visible
                    text: "↓  Latest"
                    Accessible.name: "Jump to latest message"
                    onClicked: {
                        charla.sigue = true
                        Qt.callLater(function () {
                            conversationList.positionViewAtEnd()
                        })
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 1
            color: Theme.surfaceHi
            visible: view.plugin.messages.length > 0
        }

        IslandLabel {
            Layout.fillWidth: true
            visible: view.plugin.errorMessage.length > 0 || view.plugin.syncError.length > 0
            text: view.plugin.errorMessage || view.plugin.syncError
            color: Theme.red
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        RowLayout {
            id: attachmentsRow
            Layout.fillWidth: true
            spacing: 6
            visible: view.plugin.image.length > 0 || view.plugin.selection.length > 0
                     || view.plugin.selectionCandidate.length > 0
            Item { Layout.fillWidth: true }
        }

        // A bounded multiline composer keeps the conversation readable.
        Rectangle {
            id: composer
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(110, Math.max(42, askInput.contentHeight + 22))
            onHeightChanged: view.plugin.composerHeight = height
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: askInput.activeFocus ? Theme.track : Theme.surfaceHi

            IslandLabel {
                x: 12
                y: 12
                visible: view.plugin.query.length === 0
                text: view.plugin.editingId.length > 0
                        ? "Rewrite it — Enter resends from there…"
                        : view.plugin.messages.length > 0 ? "Keep asking…" : "Ask anything…"
                color: Theme.muted
                font.pixelSize: 14
            }

            Flickable {
                id: inputScroll
                anchors.fill: parent
                anchors.margins: 11
                anchors.rightMargin: 46
                contentHeight: askInput.height
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: IslandScrollBar {}

            TextEdit {
                id: askInput
                objectName: "chatInput"
                cursorDelegate: IslandCursor {}
                width: inputScroll.width
                height: Math.max(inputScroll.height, contentHeight)
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: 14
                focus: true
                activeFocusOnTab: true
                clip: true
                selectByMouse: true
                cursorVisible: true
                selectionColor: Theme.blue
                text: view.plugin.query
                onTextChanged: if (view.plugin.query !== text) view.plugin.query = text
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < inputScroll.contentY)
                        inputScroll.contentY = cursorRectangle.y
                    else if (cursorRectangle.y + cursorRectangle.height > inputScroll.contentY + inputScroll.height)
                        inputScroll.contentY = cursorRectangle.y + cursorRectangle.height - inputScroll.height
                }

                Keys.onPressed: function (event) {
                    if (inputMethodComposing) return
                    if (event.key === Qt.Key_Escape) {
                        if (view.selectorVisible)
                            view.selectorVisible = false
                        else if (view.plugin.editingId.length > 0) {
                            view.plugin.cancelarEdicion()
                            askInput.text = ""
                        }
                        else
                            view.plugin.close()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (!(event.modifiers & Qt.ShiftModifier)) {
                            view.submit()
                            event.accepted = true
                        }
                    }
                }
            }
            }

            // send, or stop what is being thought
            MediaButton {
                id: botonEnviar
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                glyph: view.plugin.generating
                        ? String.fromCodePoint(0xF04DB) /* md-stop */
                        : String.fromCodePoint(0xF048A) /* md-send */
                glyphSize: 15
                glyphColor: view.plugin.generating ? Theme.red : Theme.muted
                enabledAction: view.plugin.generating || view.plugin.query.trim().length > 0
                Accessible.name: view.plugin.generating ? "Stop response" : "Send message"
                HoverHandler { id: sendHover }
                ToolTip.visible: sendHover.hovered
                ToolTip.text: view.plugin.generating ? "Stop response" : "Send · Enter"
                onActivated: {
                    if (view.plugin.generating)
                        view.plugin.stopGeneration()
                    else
                        view.submit()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IslandLabel {
                Layout.fillWidth: true
                text: view.plugin.editingId.length ? "Sending starts a new branch from this message."
                      : "Enter to send · Shift+Enter for a new line"
                color: Theme.muted
                font.pixelSize: 10
            }
            K4.ActionButton {
                visible: view.plugin.editingId.length > 0
                text: "Cancel edit"
                onClicked: view.plugin.cancelarEdicion()
            }
        }
    }
}
