import QtQuick
import QtQuick.Controls
import "markdown" as Markdown

// Selectable native markdown with independently scrollable code and tables.
Column {
    id: root
    property string text: ""
    property bool streaming: false
    property color color: Tema.tinta
    property int fontSize: 14
    signal linkActivated(string url)
    signal copyRequested(string text)
    signal selectionStarted()

    property int _reader: 0
    property int _revision: 0
    property bool _complete: false
    property bool _fallback: false
    readonly property var _palette: ({
        ink: String(root.color), muted: String(Tema.apagado), surface: String(Tema.superficie),
        track: String(Tema.carril), link: "#70b7ff", keyword: "#9dbfff",
        string: "#a6cfb0", number: "#d8bd91"
    })
    spacing: 10
    onTextChanged: schedule()
    on_PaletteChanged: schedule()
    onStreamingChanged: if (!streaming) schedule()
    Component.onCompleted: { _reader = ++Markdown.Renderer.nextId; _complete = true; schedule() }
    Component.onDestruction: Markdown.Renderer.release(_reader)

    function schedule() {
        if (!_complete) return
        _revision++
        if (!text.length) blocks.clear()
        // Throttle rather than debounce: a continuous stream must still paint.
        if (!renderTimer.running) renderTimer.start()
    }

    Timer {
        id: renderTimer
        interval: root.streaming ? 100 : 1
        onTriggered: Markdown.Renderer.request(root._reader, root._revision, root.text, root._palette)
    }

    ListModel { id: blocks }
    Connections {
        target: Markdown.Renderer
        function onRendered(reader, revision, result) {
            if (reader !== root._reader || revision !== root._revision) return
            root._fallback = false
            // Keep unchanged blocks and their selection/scroll state alive.
            for (let i = 0; i < result.length; ++i) {
                if (i >= blocks.count) blocks.append(result[i])
                else if (blocks.get(i).html !== result[i].html || blocks.get(i).kind !== result[i].kind)
                    blocks.set(i, result[i])
            }
            while (blocks.count > result.length) blocks.remove(blocks.count - 1)
        }
        function onFailed(reader, revision) {
            if (reader !== root._reader || revision !== root._revision) return
            blocks.clear()
            root._fallback = true
        }
    }

    TextEdit {
        visible: root._fallback
        width: root.width
        height: visible ? implicitHeight : 0
        text: root.text
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        color: root.color
        font.family: Tema.fuente
        font.pixelSize: root.fontSize
    }

    Repeater {
        model: blocks
        delegate: Rectangle {
            id: block
            required property string kind
            required property string html
            required property string text
            required property string language
            readonly property bool code: kind === "code"
            readonly property bool wide: kind !== "text"
            width: root.width
            height: body.height + (code ? 42 : 0) + (wide ? 12 : 0)
            radius: 10
            color: code ? Tema.superficie : "transparent"
            border.width: code ? 1 : 0
            border.color: Tema.superficieAlta

            Text {
                x: 12; y: 12
                visible: block.code
                text: block.language || "Code"
                textFormat: Text.PlainText
                color: Tema.apagado
                font.family: Tema.fuente
                font.pixelSize: 11
            }
            ActionButton {
                id: copy
                visible: block.code
                anchors.right: parent.right
                anchors.rightMargin: 5
                y: 4
                text: copied.running ? "Copied" : "Copy"
                Accessible.name: "Copy code"
                onClicked: { root.copyRequested(block.text); copied.restart() }
                Timer { id: copied; interval: 1400 }
            }
            Flickable {
                id: body
                x: block.code ? 12 : 0
                y: block.code ? 42 : 0
                width: parent.width - (block.code ? 24 : 0)
                height: content.implicitHeight + (block.wide && contentWidth > width ? 10 : 0)
                contentWidth: block.wide ? Math.max(width, content.implicitWidth) : width
                contentHeight: content.implicitHeight
                flickableDirection: Flickable.HorizontalFlick
                interactive: block.wide && contentWidth > width
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.horizontal: Desplazador {}

                TextEdit {
                    id: content
                    property string heldMarkup: ""
                    width: block.wide ? Math.max(body.width, implicitWidth) : body.width
                    text: heldMarkup || block.html
                    textFormat: TextEdit.RichText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: block.wide ? TextEdit.NoWrap : TextEdit.Wrap
                    color: root.color
                    selectionColor: Tema.azul
                    selectedTextColor: "white"
                    font.family: block.code ? "monospace" : Tema.fuente
                    font.pixelSize: block.code ? root.fontSize - 1 : root.fontSize
                    onLinkActivated: function (url) { root.linkActivated(url) }
                    onSelectedTextChanged: {
                        if (selectedText.length) {
                            if (!heldMarkup) heldMarkup = block.html
                            root.selectionStarted()
                        } else {
                            heldMarkup = ""
                        }
                    }
                    HoverHandler { cursorShape: content.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                }
            }
        }
    }
}
