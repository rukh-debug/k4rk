import QtQuick
import K4 as K4
import "Api.js" as Api

Item {
    id: root
    required property var message
    property bool streaming: false
    property string phase: ""
    property int elapsed: 0
    property bool editing: false
    property bool expanded: false
    property bool canRetry: false
    signal editRequested()
    signal retryRequested()
    signal expansionChanged(bool expanded)
    signal copyRequested(string text)
    signal selectionStarted()
    readonly property bool mine: message.role === "user"
    readonly property var parts: mine ? ({answer: message.content || "", reasoning: "", thinking: false})
                                     : Api.presentation(message.content, message.reasoning)
    readonly property string state: streaming ? (parts.thinking ? "Thinking" : phase) : ""
    readonly property bool hasThinking: parts.reasoning.length > 0 || state === "Thinking"
    readonly property int duration: streaming ? elapsed : (message.reasoningDuration || 0)
    readonly property string imageSource: {
        if (message.imagen) return "file://" + message.imagen
        if (!Array.isArray(message.apiContent)) return ""
        for (const part of message.apiContent) {
            const url = part.type === "image_url" && part.image_url ? part.image_url.url : ""
            if (/^(https?:\/\/|data:image\/)/i.test(url)) return url
        }
        return ""
    }
    width: parent ? parent.width : 0
    implicitHeight: stack.height + 8
    height: implicitHeight
    HoverHandler { id: hover }

    TextMetrics {
        id: measure
        font.family: K4.Tema.fuente
        font.pixelSize: 14
        text: root.parts.answer.split("\n").reduce(function (a, b) { return a.length > b.length ? a : b }, "")
    }

    Column {
        id: stack
        width: parent.width
        spacing: 7

        Text {
            visible: !root.mine
            text: root.message.role === "error" ? "Request failed" : root.message.model || "Assistant"
            textFormat: Text.PlainText
            color: root.message.role === "error" ? K4.Tema.rojo : K4.Tema.apagado
            font.family: K4.Tema.fuente
            font.pixelSize: 11
            elide: Text.ElideRight
            width: parent.width
        }

        Column {
            visible: root.hasThinking
            width: parent.width
            spacing: 8
            K4.ActionButton {
                text: (root.expanded ? "⌄  " : "›  ")
                    + (root.state === "Thinking" ? "Thinking" : "Thought process")
                    + (root.duration > 0 ? " · " + root.duration + "s" : "")
                Accessible.name: (root.expanded ? "Collapse" : "Expand") + " thought process"
                onClicked: root.expansionChanged(!root.expanded)
            }
            Loader {
                active: root.expanded
                width: parent.width
                sourceComponent: Component {
                    Item {
                        width: parent.width
                        height: reasoning.height
                        Rectangle { width: 2; height: parent.height; color: K4.Tema.carril; radius: 1 }
                        K4.MarkdownView {
                            id: reasoning
                            x: 14
                            width: parent.width - 14
                            text: root.parts.reasoning
                            streaming: root.streaming
                            color: K4.Tema.apagado
                            fontSize: 13
                            onCopyRequested: function (text) { root.copyRequested(text) }
                            onSelectionStarted: root.selectionStarted()
                            onLinkActivated: function (url) { Qt.openUrlExternally(url) }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: bubble
            x: root.mine ? parent.width - width : 0
            width: root.mine ? Math.min(parent.width * 0.84, Math.max(64, measure.advanceWidth + 32,
                root.imageSource ? 200 : 0)) : parent.width
            height: contents.height + (root.mine ? 24 : 0)
            radius: 15
            color: root.mine ? K4.Tema.superficieAlta : "transparent"
            border.width: root.editing ? 1 : 0
            border.color: K4.Tema.azul
            Column {
                id: contents
                x: root.mine ? 16 : 0
                y: root.mine ? 12 : 0
                width: parent.width - (root.mine ? 32 : 0)
                spacing: 10
                Loader {
                    width: parent.width
                    sourceComponent: root.mine ? prompt : answer
                }
                Image {
                    visible: root.imageSource.length > 0
                    width: Math.min(200, parent.width)
                    height: visible ? 112 : 0
                    source: root.imageSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: 400
                }
                Text {
                    visible: !!root.message.selection
                    width: parent.width
                    text: "Attached selection · " + String(root.message.selection || "").length + " characters"
                    textFormat: Text.PlainText
                    color: K4.Tema.apagado
                    font.family: K4.Tema.fuente
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        Text {
            visible: root.streaming && root.state !== "Thinking"
            text: root.state ? root.state + "…" : "Waiting…"
            color: K4.Tema.apagado
            font.family: K4.Tema.fuente
            font.pixelSize: 11
            textFormat: Text.PlainText
        }

        Text {
            width: parent.width
            visible: !!root.message.error || root.message.status === "stopped"
            text: root.message.error || "Stopped · partial response saved"
            color: root.message.error ? K4.Tema.rojo : K4.Tema.apagado
            font.family: K4.Tema.fuente
            font.pixelSize: 11
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        Row {
            x: root.mine ? parent.width - width : 0
            height: 28
            spacing: 4
            visible: !root.streaming
            opacity: hover.hovered || actionsFocused || root.canRetry || root.editing ? 1 : 0
            // Keep focusable actions in the layout so tab navigation reveals them.
            readonly property bool actionsFocused: copy.activeFocus || edit.activeFocus || retry.activeFocus
            Behavior on opacity { NumberAnimation { duration: 100 } }
            K4.ActionButton {
                id: copy
                height: 28
                text: copied.running ? "Copied" : "Copy"
                onClicked: { root.copyRequested(root.parts.answer); copied.restart() }
                Timer { id: copied; interval: 1400 }
            }
            K4.ActionButton {
                id: edit
                height: 28
                visible: root.mine
                text: root.editing ? "Editing" : "Edit"
                onClicked: root.editRequested()
            }
            K4.ActionButton {
                id: retry
                height: 28
                visible: root.canRetry
                text: "Retry"
                onClicked: root.retryRequested()
            }
        }
    }

    Component {
        id: prompt
        TextEdit {
            text: root.parts.answer
            textFormat: TextEdit.PlainText
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: K4.Tema.tinta
            selectionColor: K4.Tema.azul
            font.family: K4.Tema.fuente
            font.pixelSize: 14
            onSelectedTextChanged: if (selectedText.length) root.selectionStarted()
        }
    }
    Component {
        id: answer
        K4.MarkdownView {
            text: root.parts.answer
            streaming: root.streaming
            color: root.message.role === "error" ? K4.Tema.rojo : K4.Tema.tinta
            onCopyRequested: function (text) { root.copyRequested(text) }
            onSelectionStarted: root.selectionStarted()
            onLinkActivated: function (url) { Qt.openUrlExternally(url) }
        }
    }
}
