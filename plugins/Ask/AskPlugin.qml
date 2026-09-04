//  A quick question to Codex CLI, authenticated with the user's
//  ChatGPT account. No automating chatgpt.com: this is the official
//  binary.
//
//  Every opening starts a new conversation, so the previous
//  question's context is not inherited, nor that of other Codex
//  sessions lying around.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "ask"
    title: "Ask"
    priority: 90
    colocable: true
    active: habilitado && open
    grabKeyboard: true

    // they step aside when it opens; the host injects them
    property var panel: null
    property var launcher: null

    property bool open: false
    property string query: ""
    property string status: ""        // "" | "thinking" | "error"
    property string image: ""
    property string selection: ""           // truly attached (opt-in)
    property string selectionCandidate: ""  // what was selected, not yet attached
    property bool attachSelectionOnOpen: false
    property var messages: []         // [{ role: "user"|"assistant"|"error", text }]
    property string lastError: ""

    // THIS conversation's Codex session id. Empty = new session.
    // Never resumed with --last, which would hook other sessions.
    property string threadId: ""

    readonly property string dir: "/tmp/k4-ask"
    readonly property string script: K4.Paths.enRaiz("ask.sh")

    islandWidth: 700
    islandHeight: messages.length > 0 ? 430 : 128

    //  Opening RESUMES whatever was set aside — with Escape or with
    //  the −, all the same: pressing the shortcut again must not
    //  cost the conversation left half-done. To start fresh there
    //  is the «new» button (and `fresco: true`, used by the direct
    //  question IPC).
    //  A question from outside, in one call: open if closed, ask, send.
    //  The host's ask verbs used to poke openAsk/query/send one by one —
    //  three properties that only made sense in this order — and now the
    //  sequence lives with the only one who knows what it is for.
    function preguntar(texto) {
        if (!open)
            openAsk(false)
        query = texto
        send()
    }

    function openAsk(attach, fresco) {
        const retomar = fresco !== true && messages.length > 0
        Modulos.quitar("ask")
        if (!retomar)
            newConversation()
        if (panel) panel.close()
        if (launcher) launcher.close()
        Notifs.dismissToast()
        attachSelectionOnOpen = attach === true
        // it is read so it can be offered, but not attached without
        // permission
        selectionProcess.running = true
        open = true
    }

    function attach() {
        if (selectionCandidate.length > 0)
            selection = selectionCandidate
    }

    function newConversation() {
        if (askProcess.running)
            askProcess.parar(15)

        timeoutTimer.stop()
        query = ""
        messages = []
        threadId = ""
        lastError = ""
        status = ""
        imagenVista = ""
        selection = ""
        selectionCandidate = ""
        attachSelectionOnOpen = false
    }

    function appendMessage(role, text, imagen) {
        messages = messages.concat([{
            role: role, text: text, imagen: imagen || ""
        }])
    }

    // Images in the answer, by two roads:
    //
    //  - A loose absolute path: Codex touched a file and names it.
    //  - `attachment://exec-<id>.png`: its image GENERATING tool.
    //    That scheme is no path at all, but the real file lives in
    //    ~/.codex/generated_images/<session>/ and the session is our
    //    threadId — so it is reconstructed. This used to get lost:
    //    the image was generated and the conversation showed a
    //    broken link.
    function imagenEn(texto) {
        const t = String(texto)
        const adjunto = t.match(/attachment:\/\/([^\s"'`)]+\.(?:png|jpe?g|webp|gif))/i)
        if (adjunto && threadId.length > 0)
            return K4.Sistema.entorno("HOME") + "/.codex/generated_images/"
                + threadId + "/" + adjunto[1]
        const ruta = t.match(/(\/[^\s"'`)]+\.(?:png|jpe?g|webp|gif))/i)
        return ruta ? ruta[1] : ""
    }

    //  The markdown of an image already shown separately is a broken
    //  link in the middle of the text: out.
    function sinAdjuntos(texto) {
        return String(texto)
            .replace(/!?\[[^\]]*\]\(attachment:\/\/[^\)]*\)/g, "")
            .replace(/attachment:\/\/[^\s"'`)]+/g, "")
            .trim()
    }

    function updateLastMessage(role, text) {
        const list = messages.slice()
        for (let i = list.length - 1; i >= 0; --i) {
            if (list[i].role === "assistant" || list[i].role === "error") {
                const imagen = imagenEn(text)
                list[i] = { role: role,
                            text: imagen ? sinAdjuntos(text) : text,
                            imagen: imagen }
                messages = list
                return
            }
        }
        appendMessage(role, text)
    }

    function attachScreenshot() {
        // captured before the island expands, so it is not in the
        // photo
        image = ""
        attachSelectionOnOpen = false
        shotProcess.command = ["grim", dir + "/shot.png"]
        shotProcess.running = true
    }

    function attachRegion() {
        image = ""
        shotProcess.command = ["sh", "-c", "grim -g \"$(slurp -d)\" " + dir + "/shot.png"]
        shotProcess.running = true
    }

    //  Closing sets the conversation aside, it does not throw it away.
    //
    //  `close()` used to call newConversation() and with that
    //  everything was lost: the question, the answer and the Codex
    //  thread. That forced keeping the island occupied until done
    //  reading, because closing it cost the whole conversation.
    function close() {
        if (messages.length > 0) {
            Modulos.minimizar("ask", "Ask",
                              resumenConversacion(), Theme.ico.ask.codePointAt(0))
        }
        open = false
    }

    // Truly discarding: this one forgets.
    function cerrarYOlvidar() {
        Modulos.quitar("ask")
        newConversation()
        open = false
        image = ""
    }

    // The first words of what you asked, to recognize it in the pill
    // without having to open it.
    function resumenConversacion() {
        for (let i = 0; i < messages.length; ++i) {
            if (messages[i].role === "user") {
                const t = String(messages[i].text || "").trim()
                return t.length > 26 ? t.substring(0, 26) + "…" : t
            }
        }
        return ""
    }

    function send() {
        const question = query.trim()
        if (question.length === 0 || status === "thinking")
            return

        lastError = ""
        status = "thinking"
        appendMessage("user", question, image)
        appendMessage("assistant", "")
        query = ""

        // the preamble only on the first turn: afterwards it lives in
        // the session
        let prompt = threadId.length === 0
            ? "You are a quick assistant built into the desktop bar. "
                + "Reply in English, short and direct. You may use simple markdown: "
                + "bold, italics, code and links. No tables or headings. "
                + "Do not run commands or read files unless the question explicitly asks.\n\n"
                + "Pregunta: " + question
            : question

        if (selection.length > 0)
            prompt += "\n\nText the user has selected on screen:\n" + selection

        if (image.length > 0)
            prompt += "\n\nA screenshot of the user's screen is attached."

        // through a wrapper: it needs stdin closed, otherwise
        // `codex exec` hangs waiting for EOF (Quickshell leaves the
        // pipe open)
        askProcess.command = [script, prompt, image, threadId]
        askProcess.running = true
        timeoutTimer.restart()

        // attachments belong to this turn, not the whole
        // conversation
        image = ""
        selection = ""
    }

    //  Codex's image-generating tool leaves no reliable trace in the
    //  text: sometimes `attachment://...`, sometimes an EMPTY final
    //  message — the image only exists as a file in
    //  generated_images/<session>/. So at the end of the turn that
    //  place is looked at directly, and if there is a new one it is
    //  hooked to the last message (even if it was an «error» for an
    //  empty answer: an image IS the answer).
    property string imagenVista: ""

    function buscarImagenGenerada() {
        if (threadId.length === 0)
            return
        buscadorImagen.command = ["sh", "-c",
            "ls -t " + K4.Sistema.entorno("HOME") + "/.codex/generated_images/"
            + threadId + "/*.png 2>/dev/null | head -1"]
        buscadorImagen.running = true
    }

    K4.Process {
        id: buscadorImagen
        onSalida: function (texto) {
            const ruta = texto.trim()
            if (ruta.length === 0 || ruta === self.imagenVista)
                return
            self.imagenVista = ruta
            const list = self.messages.slice()
            for (let i = list.length - 1; i >= 0; --i) {
                if (list[i].role === "assistant" || list[i].role === "error") {
                    const t = (list[i].role === "assistant"
                               && list[i].text.length > 0)
                        ? list[i].text : "Here it is:"
                    list[i] = { role: "assistant", text: t, imagen: ruta }
                    self.messages = list
                    if (self.status === "error")
                        self.status = ""
                    return
                }
            }
        }
    }

    function handleEvent(line) {
        const text = line.trim()
        if (text.length === 0 || text.charAt(0) !== "{")
            return

        let event
        try {
            event = JSON.parse(text)
        } catch (error) {
            return
        }

        if (event.type === "thread.started" && event.thread_id) {
            threadId = event.thread_id
        } else if ((event.type === "item.completed" || event.type === "item.updated") && event.item) {
            if (event.item.type === "agent_message" && event.item.text)
                updateLastMessage("assistant", event.item.text)
        } else if (event.type === "turn.failed" || event.type === "error") {
            status = "error"
            updateLastMessage("error",
                event.error && event.error.message ? event.error.message : "Codex returned an error.")
        } else if (event.type === "turn.completed") {
            if (status === "thinking")
                status = ""
            buscarImagenGenerada()
        }
    }

    // What gets attached must be seen: a text the user no longer
    // remembers having marked poisons the answer without a trace.
    function preview(source) {
        const text = source.replace(/\s+/g, " ").trim()
        return text.length > 30 ? text.substring(0, 30) + "…" : text
    }

    function guardarImagen(ruta) {
        if (!ruta || ruta.length === 0)
            return
        const destino = K4.Sistema.entorno("HOME") + "/Pictures"
        K4.Sistema.lanzar(["sh", "-c",
            "mkdir -p " + JSON.stringify(destino)
            + " && cp -n " + JSON.stringify(ruta) + " " + JSON.stringify(destino) + "/"])
    }

    function abrirExterno(ruta) {
        if (ruta && ruta.length > 0)
            K4.Sistema.lanzar(["xdg-open", ruta])
    }

    function copyAnswer() {
        for (let i = messages.length - 1; i >= 0; --i) {
            if (messages[i].role === "assistant" && messages[i].text.length > 0) {
                K4.Sistema.lanzar(["wl-copy", "--", messages[i].text])
                return
            }
        }
    }

    K4.Process {
        command: ["mkdir", "-p", self.dir]
        running: true
    }

    K4.Process {
        id: selectionProcess
        command: ["wl-paste", "--primary", "--no-newline"]

        onSalida: function (texto) {
            self.selectionCandidate = texto.trim().substring(0, 4000)
            // attached only if explicitly asked
            if (self.attachSelectionOnOpen)
                self.selection = self.selectionCandidate
        }
    }

    K4.Process {
        id: shotProcess
        onTerminado: function (code) {
            const shot = code === 0 ? self.dir + "/shot.png" : ""
            self.openAsk(false)
            self.image = shot
        }
    }

    K4.Process {
        id: askProcess
        porLineas: true

        onLinea: function (line) { self.handleEvent(line) }

        onLineaError: function (line) {
            if (line.indexOf("ERROR") !== -1 || line.indexOf("error:") !== -1)
                self.lastError = line
        }

        onTerminado: function (code) {
            timeoutTimer.stop()

            const last = self.messages.length > 0
                ? self.messages[self.messages.length - 1] : null
            const answered = last && last.role === "assistant" && last.text.length > 0

            if (!answered) {
                self.status = "error"
                self.updateLastMessage("error", self.lastError.length > 0
                    ? self.lastError
                    : "Codex exited with code " + code + " and no answer.")
            } else if (self.status === "thinking") {
                self.status = ""
                // Set aside while it thought: announce it is done,
                // which is what setting it aside was for — so one
                // does not keep staring.
                if (!self.open)
                    K4.Sistema.avisar("Answer ready",
                                      self.resumenConversacion(), false)
            }

            //  And in any case, look whether this turn left an
            //  image: the «no answer» verdict corrects itself only
            //  if one appears.
            self.buscarImagenGenerada()
        }
    }

    Timer {
        id: timeoutTimer
        interval: 120000
        onTriggered: {
            if (askProcess.running) {
                askProcess.parar(15)
                self.status = "error"
                self.updateLastMessage("error", "Codex didn't answer within 2 minutes.")
            }
        }
    }

    Connections {
        target: Modulos
        function onRestaurado(id) {
            if (id === "ask")
                self.open = true
        }
    }

    K4.Ipc {
        target: "k4.ask"
        function toggle(): void {
            if (self.open) self.close()
            else self.openAsk(false)
        }
        function selection(): void { self.openAsk(true) }
        function screen(): void { self.attachScreenshot() }
        function region(): void { self.attachRegion() }
        function now(question: string): void {
            //  Direct question: this one does start fresh, coming
            //  from a script, and mixing threads would be worse.
            self.openAsk(false, true)
            self.query = question
            self.send()
        }
        function followUp(question: string): void {
            if (!self.open)
                self.openAsk(false)
            self.query = question
            self.send()
        }
    }

    view: Component {
        AskView { plugin: self }
    }
}
