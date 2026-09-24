import QtQuick
import QtTest
import Quickshell
import K4 as K4
import "../plugins/OpenWebUI" as Chat
import "../plugins/OpenWebUI/Api.js" as Api
import "../services" as Services

Item {
    id: fixture
    Component.onCompleted: K4.Puente.config = Services.ConfigStore
    Chat.OpenWebUIPlugin {
        id: engine
        open: true
        carpeta: Qt.resolvedUrl("../plugins/OpenWebUI").toString().replace("file://", "")
    }
    Chat.OpenWebUIView {
        id: chatView
        width: 660
        height: 560
        visible: false
        plugin: engine
    }
    K4.MarkdownView {
        id: markdown
        width: 500
        text: "# Heading\n\nReadable **prose** and `inline code`.\n\n```python\nprint('hello')\n```\n\n| A | B |\n| --- | --- |\n| One | Two |"
    }
    Chat.ChatMessage {
        id: prompt
        y: 350
        width: 500
        message: ({role: "user", content: "A literal <tag>\nAnd another line", id: "prompt"})
    }
    Chat.ChatMessage {
        id: response
        y: 440
        width: 500
        message: ({role: "assistant", content: "<think>Think carefully</think>\n\n**Answer**", id: "response"})
        onExpansionChanged: function (value) { expanded = value }
    }

    TestCase {
        function cleanup() {
            if (qtest_results.failed) console.error("FAILED: " + qtest_results.functionName)
        }
        name: "OpenWebUI"
        when: fixture.Window.window !== null && fixture.Window.window.visible
        function cleanupTestCase() {
            console.log("OpenWebUI UI: " + qtest_results.passCount + " passed, " + qtest_results.failCount + " failed")
            Qt.exit(qtest_results.failCount > 0 ? 1 : 0)
        }
        function test_markdownLayout() {
            tryVerify(function () { return markdown.height > 100 }, 8000)
            compare(markdown._fallback, false)
            verify(markdown.height < 600)
            verify(prompt.height > 70)
            verify(response.height > 50)
            const before = response.height
            response.expanded = true
            tryVerify(function () { return response.height > before }, 8000)
        }
        function test_reasoningWrappers() {
            let result = Api.presentation("<think>Reason\n</think>Answer", "")
            compare(result.answer, "Answer")
            compare(result.reasoning, "Reason")
            compare(result.thinking, false)
            result = Api.presentation("<think>Still working</thi", "")
            compare(result.answer, "")
            compare(result.reasoning, "Still working")
            compare(result.thinking, true)
            result = Api.presentation("<details type=\"reasoning\"><summary>Thought</summary>\n> Notes\n</details>Reply", "")
            compare(result.reasoning, "Notes")
            compare(result.answer, "Reply")
            const literal = "```html\n<think>example</think>\n```\n\nUse `<think>` literally."
            compare(Api.presentation(literal, "").answer, literal)
            compare(Api.presentation(literal, "").reasoning, "")
        }
        function test_historyRoundTrip() {
            const messages = [{id: "u", role: "user", content: "Question", selection: "Selected"},
                              {id: "a", role: "assistant", content: "Answer", reasoning: "Reason", model: "original", reasoningDuration: 4}]
            const first = Api.exportChat("Title", "default", messages)
            const next = Api.exportChat("Title", "other", [messages[0], {id: "b", role: "assistant", content: "Branch"}], first.chat)
            verify(next.chat.history.messages.a !== undefined)
            compare(next.chat.history.messages.u.childrenIds.length, 2)
            compare(next.chat.history.currentId, "b")
            const loaded = Api.orderedMessages(first)
            compare(loaded[0].content, "Question")
            compare(loaded[0].selection, "Selected")
            compare(loaded[1].model, "original")
            compare(loaded[1].reasoning, "Reason")
            compare(loaded[1].reasoningDuration, 4)
            verify(Api.payload("model", [], "remote-chat").chat_id === undefined)
        }
        function test_largeClipboard() {
            engine.copyText("large code block\n".repeat(12000))
            wait(300)
        }
        function test_profileAndHistoryStayLocal() {
            tryCompare(Services.ConfigStore, "ready", true)
            engine.baseUrl = Quickshell.env("K4_OPENWEBUI_TEST_URL")
            engine.draftEmail = "private-account@example.invalid"
            engine.currentModel = "private-model"
            engine.pinLists = [{ name: "Private models", models: ["private-model"] }]
            engine.guardarAjustes()
            tryCompare(Services.ConfigStore, "pendingCount", 0)
            compare(Services.ConfigStore.value(["plugins", "openwebui", "profile", "draftEmail"], ""), "private-account@example.invalid")
            const shared = JSON.stringify(Services.ConfigStore.data)
            verify(shared.indexOf("private-account") < 0)
            verify(shared.indexOf("private-model") < 0)
            verify(shared.indexOf(engine.baseUrl) < 0)
            engine.messages = [{ id: "private-message", role: "user", content: "Local-only conversation" }]
            engine.guardarEstado()
            tryCompare(Services.ConfigStore, "pendingCount", 0)
            compare(JSON.stringify(Services.ConfigStore.data), shared)
            compare(Services.ConfigStore.value(["plugins", "openwebui", "state", "messages"], [])[0].content, "Local-only conversation")
            engine.newChat()
        }
        function test_streamStatesAndPartialFailure() {
            engine.newChat()
            engine.generating = true
            engine.responseId = "fixture"
            engine.responseModel = "fixture-model"
            engine.lineaFlujo(JSON.stringify({type: "delta", content: "", reasoning: "Consider this"}))
            compare(engine.responsePhase, "Thinking")
            engine.lineaFlujo(JSON.stringify({type: "delta", content: "Partial answer", reasoning: ""}))
            compare(engine.responsePhase, "Responding")
            engine.lineaFlujo(JSON.stringify({type: "error", message: "Disconnected"}))
            engine.flujoTerminado(0)
            compare(engine.messages[0].content, "Partial answer")
            compare(engine.messages[0].reasoning, "Consider this")
            compare(engine.messages[0].status, "failed")
            compare(engine.messages[0].error, "Disconnected")
            compare(engine.currentResponse, "")
            compare(engine.currentReasoning, "")
        }
        function test_transportGenerationAndCancellation() {
            engine.newChat()
            engine.baseUrl = Quickshell.env("K4_OPENWEBUI_TEST_URL")
            engine.apiToken = "fixture-token"
            engine.currentModel = "fixture-model"
            engine.query = "Question"
            engine.selection = "Attached context"
            verify(engine.send())
            compare(engine.query, "")
            tryCompare(engine, "generating", false, 8000)
            compare(engine.messages.length, 2)
            compare(engine.messages[1].reasoning, "Consider the question.")
            compare(engine.messages[1].model, "fixture-model")
            verify(engine.messages[1].content.indexOf("A streamed reply") >= 0)
            tryCompare(engine, "currentChatId", "fixture-chat", 8000)
            engine.query = "Slow"
            verify(engine.send())
            wait(80)
            engine.stopGeneration()
            engine.query = "Fresh"
            verify(engine.send())
            tryCompare(engine, "generating", false, 8000)
            wait(500)
            compare(engine.messages.length, 6)
            compare(engine.messages[3].status, "stopped")
            compare(engine.messages[4].content, "Fresh")
            compare(engine.messages[5].status, "complete")
        }
        function test_viewComposerAndContinuousReply() {
            chatView.visible = true
            const input = findChild(chatView, "chatInput")
            verify(input !== null)
            engine.query = "First line"
            compare(input.text, "First line")
            input.forceActiveFocus()
            input.cursorPosition = input.text.length
            keyClick(Qt.Key_Return, Qt.ShiftModifier)
            compare(input.text, "First line\n")
            engine.query = ""
            compare(input.text, "")
            engine.editar(engine.messages[0].id)
            compare(input.text, "Question")
            engine.cancelarEdicion()
            compare(input.text, "")
            const list = findChild(chatView, "conversationList")
            verify(list !== null)
            engine.generating = true
            engine.currentResponse = "A long reply.\n\n".repeat(80)
            tryVerify(function () { return list.footerItem.height > 150 }, 8000)
            verify(list.contentHeight > list.height)
            engine.generating = false
            engine.currentResponse = ""
            chatView.visible = false
        }
        function test_zStaleHistoryAndSaveCallbacks() {
            engine.newChat()
            engine.cargarChat("slow")
            engine.cargarChat("fast")
            tryCompare(engine, "currentChatId", "fast", 8000)
            wait(450)
            compare(engine.currentChatId, "fast")
            compare(engine.messages[0].content, "fast")
            engine.newChat()
            engine.chatTitle = "Slow save"
            engine.query = "Test save ownership"
            verify(engine.send())
            tryCompare(engine, "generating", false, 8000)
            verify(engine.savingChat)
            engine.newChat()
            wait(500)
            compare(engine.currentChatId, "")
            compare(engine.chatTitle, "")
            compare(engine.messages.length, 0)
        }
    }
}
