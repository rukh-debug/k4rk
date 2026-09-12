//  A quick chat with an OpenWebUI instance: streaming answers, the
//  model list, and the conversations the server already keeps —
//  opened from the bar's island, from a keybind or over IPC.
//
//  What Ask used to do with a local Codex binary, this does with a
//  server: the same island, the same screen-and-selection
//  attachments (sent as images the model can see), and the set-aside
//  pill that keeps a half-read answer one keypress away.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"
import "Api.js" as Api

K4Plugin {
    id: self

    name: "openwebui"
    title: "OpenWebUI"
    priority: 90
    colocable: true
    active: habilitado && open
    grabKeyboard: true

    // they step aside when this opens; the host injects them
    property var panel: null
    property var launcher: null
    property var settings: null

    // ── the knobs the Settings page edits ─────────────────────────
    property string baseUrl: ""
    property string apiToken: ""
    property string currentModel: ""
    property bool rememberHistory: true
    //  A background answer reopens the island — keyboard and all —
    //  so it is off by default: the notification asks, it does not
    //  take the desk.
    property bool openAfterResponse: false

    //  What the Settings page was told, mid-typing. Reopening the
    //  page must find the words where they were left, not start
    //  over: a server half-written, an email, a key pasted but not
    //  yet applied. Saved with the knobs, applied only when the
    //  user says so (Enter, «Save», or leaving the page).
    property string draftServer: ""
    property string draftEmail: ""
    property string draftPassword: ""
    property string draftApiKey: ""

    readonly property bool autenticado: apiToken.length > 0

    // ── the conversation ──────────────────────────────────────────
    property bool open: false
    property var messages: []          // [{ id, role, content, timestamp, imagen? }]
    property string currentChatId: ""  // the server's id for this chat
    property string chatTitle: ""
    property bool generating: false
    property string currentResponse: "" // the stream, as it lands
    property string errorMessage: ""
    property bool manuallyStopped: false
    property bool sidebarVisible: false

    // ── attachments, offered and taken ────────────────────────────
    property string query: ""
    property string image: ""               // path of the shot to send
    property string selection: ""           // truly attached (opt-in)
    property string selectionCandidate: ""  // what was selected, not yet attached
    property bool attachSelectionOnOpen: false

    //  The message being taken back for a rewrite. Its old words
    //  sit in the input; the next send cuts the conversation AT it
    //  — the answer it got and everything said afterwards belonged
    //  to a future that no longer is, and the chat continues from
    //  the new wording. The server chat follows on the next sync:
    //  the whole document is replaced, branch and all.
    property string editingId: ""

    // ── the lists the sidebar and the selector show ───────────────
    property var chatList: []           // [{ id, title, updated_at }]
    property bool fetchingChats: false
    property string chatsError: ""
    property bool hasMoreChats: true
    property int chatPage: 0
    property var models: []
    property bool fetchingModels: false
    property string modelsError: ""

    //  What the sign-in card is doing, for the page to show.
    property bool signingIn: false
    property string signInError: ""

    //  ── pin lists ────────────────────────────────────────────────
    //
    //  Named sets of models, kept with the knobs. The island's
    //  selector shows EVERY list as its own group — not the whole
    //  catalog: twenty models is a scroll, four is a choice. The
    //  default model rides on top of whatever is shown. Which
    //  models belong where is decided in Settings, where the whole
    //  catalog is there to search.
    property var pinLists: []          // [{ name, models: [id…] }]

    //  The selector popup is open: the island grows so the list is
    //  read in place, not through a keyhole. The view owns the
    //  flag's life; this side only lends it height.
    property bool selectorOpen: false

    //  Turning memory off also empties what it holds: a knob that
    //  says «do not keep this» cannot leave yesterday's chat on disk.
    onRememberHistoryChanged: if (!rememberHistory) guardarEstado()

    readonly property string dir: "/tmp/k4-openwebui"

    islandWidth: !autenticado ? 520
                 : sidebarVisible ? 900 : 660
    //  The height the chat itself asks for; the selector popup —
    //  30 px down plus up to 360 of list — is taller than the empty
    //  state, so while it is open the island stands up for it.
    readonly property int altoBase:
        (messages.length > 0 || sidebarVisible) ? 470 : 128
    islandHeight: !autenticado ? 340
                  : selectorOpen ? Math.max(altoBase, 410)
                  : altoBase

    // ── persistence ───────────────────────────────────────────────
    //
    //  Two files under the plugin's state dir: the knobs (`ajustes`)
    //  and the conversation left half-done (`estado`). The token
    //  lives in the first one — local, like the web client's cookie.

    K4.Guardado {
        id: ajustes
        plugin: "openwebui"
        nombre: "ajustes"
        onCargado: function (d) {
            self.baseUrl = d.baseUrl || ""
            self.apiToken = d.apiToken || ""
            self.currentModel = d.currentModel || ""
            self.rememberHistory = d.rememberHistory !== false
            self.openAfterResponse = d.openAfterResponse === true
            self.draftServer = d.draftServer || d.baseUrl || ""
            self.draftEmail = d.draftEmail || ""
            self.draftPassword = d.draftPassword || ""
            self.draftApiKey = d.draftApiKey || ""
            self.pinLists = Array.isArray(d.pinLists) ? d.pinLists : []
            //  The two files load in any order: if this one lands
            //  after the conversation, its verdict on remembering is
            //  the one that counts.
            if (!self.rememberHistory) {
                self.messages = []
                self.currentChatId = ""
                self.chatTitle = ""
            }
        }
    }

    function guardarAjustes() {
        ajustes.guardar({ baseUrl: baseUrl, apiToken: apiToken,
                          currentModel: currentModel,
                          rememberHistory: rememberHistory,
                          openAfterResponse: openAfterResponse,
                          draftServer: draftServer,
                          draftEmail: draftEmail,
                          draftPassword: draftPassword,
                          draftApiKey: draftApiKey,
                          pinLists: pinLists })
    }

    // ── pin lists, from the Settings page ─────────────────────────

    function nuevaListaPin(nombre) {
        const n = String(nombre || "").trim()
        if (n.length === 0)
            return
        for (let i = 0; i < pinLists.length; ++i)
            if (pinLists[i].name === n)
                return
        pinLists = pinLists.concat([{ name: n, models: [] }])
        guardarAjustes()
    }

    function borrarListaPin(nombre) {
        pinLists = pinLists.filter(function (l) {
            return l.name !== nombre
        })
        guardarAjustes()
    }

    function pinear(nombre, model) {
        for (let i = 0; i < pinLists.length; ++i) {
            if (pinLists[i].name !== nombre)
                continue
            if (pinLists[i].models.indexOf(model) >= 0)
                return
            const listas = pinLists.slice()
            listas[i] = { name: pinLists[i].name,
                          models: pinLists[i].models.concat([model]) }
            pinLists = listas
            guardarAjustes()
            return
        }
    }

    function despinear(nombre, model) {
        for (let i = 0; i < pinLists.length; ++i) {
            if (pinLists[i].name !== nombre)
                continue
            const listas = pinLists.slice()
            listas[i] = { name: pinLists[i].name,
                          models: pinLists[i].models.filter(function (m) {
                              return m !== model
                          }) }
            pinLists = listas
            guardarAjustes()
            return
        }
    }

    //  The page's fields, committed when it goes away: the server
    //  takes effect (typed but never Entering is the normal way to
    //  leave a field), the rest only keep their place for next time.
    //  An empty server is never applied — clearing the box is not a
    //  wish to point at nothing.
    function confirmarBorradores() {
        const nuevo = draftServer.trim()
        if (nuevo.length > 0 && nuevo !== baseUrl) {
            baseUrl = nuevo
            if (autenticado) {
                fetchModels()
                refreshChats()
            }
        }
        guardarAjustes()
    }

    K4.Guardado {
        id: estado
        plugin: "openwebui"
        nombre: "estado"
        onCargado: function (d) {
            if (!self.rememberHistory)
                return
            self.messages = Array.isArray(d.messages) ? d.messages : []
            self.currentChatId = d.currentChatId || ""
            self.chatTitle = d.chatTitle || ""
            self.sidebarVisible = d.sidebarVisible === true
        }
    }

    function guardarEstado() {
        if (!rememberHistory) {
            estado.guardar({})
            return
        }
        //  A cap, so the file stays small; the server keeps the whole
        //  conversation anyway, and the sidebar can bring it back.
        estado.guardar({ messages: messages.slice(-200),
                         currentChatId: currentChatId,
                         chatTitle: chatTitle,
                         sidebarVisible: sidebarVisible })
    }

    // ── opening and closing, with the set-aside ───────────────────
    //
    //  Opening RESUMES whatever was set aside — with Escape or with
    //  the −, all the same: pressing the shortcut again must not cost
    //  the conversation left half-done. To start fresh there is the
    //  «new» button (and `fresco: true`).
    function openAsk(adjuntar, fresco) {
        const retomar = fresco !== true && messages.length > 0
        Modulos.quitar("openwebui")
        if (!retomar)
            newChat()
        if (panel) panel.close()
        if (launcher) launcher.close()
        Notifs.dismissToast()
        attachSelectionOnOpen = adjuntar === true
        // it is read so it can be offered, but not attached without
        // permission
        selectionProcess.running = true
        if (autenticado) {
            if (models.length === 0)
                fetchModels()
            if (chatList.length === 0)
                refreshChats()
        }
        open = true
    }

    //  Closing sets the conversation aside, it does not throw it
    //  away: the pill keeps a summary, and the server keeps the chat.
    function close() {
        if (messages.length > 0) {
            Modulos.minimizar("openwebui", "OpenWebUI",
                              resumen(), Theme.ico.ask.codePointAt(0))
            guardarEstado()
        }
        open = false
    }

    // Truly discarding: this one forgets.
    function cerrarYOlvidar() {
        Modulos.quitar("openwebui")
        newChat()
        open = false
        image = ""
    }

    // The first words of what you asked, to recognize it in the pill
    // without having to open it.
    function resumen() {
        for (let i = 0; i < messages.length; ++i) {
            if (messages[i].role === "user") {
                const t = String(messages[i].content || "").trim()
                return t.length > 26 ? t.substring(0, 26) + "…" : t
            }
        }
        return ""
    }

    function newChat() {
        if (generating)
            stopGeneration()
        query = ""
        messages = []
        currentChatId = ""
        chatTitle = ""
        currentResponse = ""
        errorMessage = ""
        selection = ""
        selectionCandidate = ""
        attachSelectionOnOpen = false
        image = ""
        editingId = ""
        guardarEstado()
    }

    // ── sending ───────────────────────────────────────────────────
    //
    //  A question from outside, in one call: open if closed, ask,
    //  send. The host's ask verbs walk in here — and `fresco` is
    //  askNow's way of saying this one does not continue the thread
    //  left on the pill: coming from a script, mixing them would be
    //  worse.
    function preguntar(texto, fresco) {
        if (fresco === true)
            openAsk(false, true)
        else if (!open)
            openAsk(false)
        query = texto
        send()
    }

    function send() {
        const texto = query.trim()
        if (texto.length === 0 || generating)
            return
        if (baseUrl.trim().length === 0 || !autenticado) {
            openAsk(false)
            return
        }
        if (currentModel.length === 0) {
            errorMessage = "No model selected — pick one in Settings."
            return
        }

        errorMessage = ""
        //  A rewrite continues from itself: the conversation is cut
        //  at the message being edited — it and everything after it
        //  go — and the new wording is sent as this turn. The image
        //  of the old turn does not come back: what the rewrite
        //  carries is what was just attached.
        if (editingId.length > 0) {
            const idx = indiceDe(editingId)
            if (idx >= 0)
                messages = messages.slice(0, idx)
            editingId = ""
        }

        despachar(texto, image)
    }

    //  The turn leaves through a script of our own: the payload —
    //  and a screenshot's data URL above all — cannot travel as a
    //  command-line argument, where the kernel caps one word at
    //  128 KB. The JSON goes to a file the script reads, the image
    //  goes as a path it embeds, and what comes back is the same
    //  line-by-line stream the parser below has always read.
    function despachar(texto, rutaImagen) {
        appendMessage("user", texto, image)
        generating = true
        manuallyStopped = false
        currentResponse = ""
        timeoutTimer.restart()

        const history = []
        for (let i = 0; i < messages.length; ++i) {
            const m = messages[i]
            if (m.role === "error")
                continue
            history.push({ role: m.role, content: m.content })
        }

        carga.setText(JSON.stringify(
            Api.payload(currentModel, history, currentChatId)))

        flujo.command = ["python3", fichero("enviar.py"),
                         Api.base(baseUrl), apiToken, carga.path,
                         rutaImagen.length > 0 ? rutaImagen : ""]
        flujo.running = true

        // attachments belong to this turn, not the whole conversation
        query = ""
        image = ""
        selection = ""
    }

    // ── editing a sent turn ───────────────────────────────────────

    function indiceDe(id) {
        for (let i = 0; i < messages.length; ++i)
            if (messages[i].id === id)
                return i
        return -1
    }

    //  Take a turn back: its words go to the input for a rewrite.
    //  A stream still running is stopped — the rewrite is the
    //  user's verdict on where this is going.
    function editar(id) {
        if (generating)
            stopGeneration()
        for (let i = 0; i < messages.length; ++i) {
            if (messages[i].id === id) {
                query = String(messages[i].content || "")
                editingId = id
                return
            }
        }
    }

    //  Changed one's mind about changing it: the words leave the
    //  input and the conversation stands as it was.
    function cancelarEdicion() {
        editingId = ""
        query = ""
    }

    function appendMessage(role, content, imagen) {
        const m = { id: String(Date.now()) + "-" + messages.length,
                    role: role, content: content,
                    imagen: imagen || "",
                    timestamp: Api.ahora() }
        messages = messages.concat([m])
        return m
    }

    function stopGeneration() {
        if (!generating)
            return
        manuallyStopped = true
        if (flujo.running)
            flujo.running = false
        generating = false
        timeoutTimer.stop()
        // a partial answer is still an answer
        if (currentResponse.trim().length > 0)
            finalizeAssistant()
        currentResponse = ""
    }

    // ── the stream, line by line ──────────────────────────────────
    //
    //  curl --no-buffer hands us the SSE as it happens: `data: {…}`
    //  chunks with a delta each, a final `data: [DONE]`, and — when
    //  things go wrong — a plain JSON error with no prefix at all,
    //  which may arrive split across lines. Both shapes are read.
    function lineaFlujo(linea) {
        const t = String(linea).trim()
        if (t.length === 0)
            return
        if (t.indexOf("data: ") === 0) {
            const json = t.substring(6).trim()
            if (json === "[DONE]")
                return
            try {
                const ev = JSON.parse(json)
                if (ev.choices && ev.choices[0]) {
                    const delta = ev.choices[0].delta
                    if (delta && delta.content)
                        currentResponse += delta.content
                    else if (ev.choices[0].message
                             && ev.choices[0].message.content)
                        currentResponse = ev.choices[0].message.content
                }
            } catch (e) {
                //  A chunk cut mid-line arrives whole on the next
                //  one; parse errors here are noise, not failure.
            }
            return
        }
        flujo.buffer += t
        try {
            const err = JSON.parse(flujo.buffer)
            if (err.error)
                errorMessage = err.error.message || "API error"
            else if (err.detail)
                errorMessage = String(err.detail)
            flujo.buffer = ""
        } catch (e) {
            // incomplete JSON, keep buffering
        }
    }

    function flujoTerminado(code) {
        if (manuallyStopped) {
            manuallyStopped = false
            return
        }
        generating = false
        timeoutTimer.stop()

        if (currentResponse.trim().length > 0) {
            finalizeAssistant()
            sincronizarServidor()
            //  Set aside while it thought: say it is done, which is
            //  what setting it aside was for — or come back to the
            //  front, if that is what was asked.
            if (!open) {
                if (openAfterResponse)
                    openAsk(false)
                else
                    K4.Sistema.avisar("Answer ready", resumen(), false)
            }
            return
        }

        if (errorMessage.length > 0)
            appendMessage("error", errorMessage)
        else if (code !== 0)
            appendMessage("error", "The request failed (exit "
                                   + code + "). Check the server and key.")
        else
            appendMessage("error", "The model returned an empty answer.")
        currentResponse = ""
        errorMessage = ""
    }

    function finalizeAssistant() {
        appendMessage("assistant", currentResponse.trim())
        currentResponse = ""
        guardarEstado()
    }

    // ── the server's memory of this chat ──────────────────────────
    //
    //  After a completed exchange the chat is written back: created
    //  on the first turn, updated afterwards. Only once the id is
    //  known can the title be asked for — so that happens here too.
    function sincronizarServidor() {
        if (!autenticado || messages.length === 0)
            return
        const datos = Api.exportChat(chatTitle.length > 0
                                     ? chatTitle : tituloProvisional(),
                                     currentModel, messages)
        Api.saveChat(baseUrl, apiToken, currentChatId, datos,
            function (resp) {
                if (resp && resp.id && resp.id !== currentChatId) {
                    currentChatId = resp.id
                    guardarEstado()
                }
                if (messages.length === 2)
                    ponerTitulo()
                refreshChats()
            }, function (fallo) {
                //  Not fatal: the conversation goes on, it just won't
                //  be in the web UI's list. The next exchange retries.
                errorMessage = ""
                console.warn("k4.openwebui: " + fallo)
            })
    }

    function tituloProvisional() {
        for (let i = 0; i < messages.length; ++i) {
            if (messages[i].role === "user") {
                const t = String(messages[i].content || "").trim()
                return t.length > 50 ? t.substring(0, 47) + "…" : t
            }
        }
        return "New chat"
    }

    //  The server names the chat after the first exchange, the way it
    //  does for its own web client. Only once: a chat that already
    //  has a name keeps it, which is also what stops the save→title
    //  →save cycle from chasing its own tail.
    function ponerTitulo() {
        if (chatTitle.length > 0 || currentChatId.length === 0
                || messages.length < 2)
            return
        const primeros = []
        for (let i = 0; i < messages.length && primeros.length < 2; ++i)
            if (messages[i].role === "user"
                    || messages[i].role === "assistant")
                primeros.push({ role: messages[i].role,
                                content: messages[i].content })
        Api.generateTitle(baseUrl, apiToken, currentModel, primeros,
            function (titulo) {
                chatTitle = titulo
                guardarEstado()
                // the title travels with the next save; a save with
                // nothing new would be the same chat, so it is safe
                sincronizarServidor()
                refreshChats()
            }, function (fallo) {
                console.warn("k4.openwebui: title: " + fallo)
            })
    }

    // ── the sidebar's list ────────────────────────────────────────

    function refreshChats() {
        chatPage = 0
        hasMoreChats = true
        chatList = []
        cargarMasChats()
    }

    function cargarMasChats() {
        if (fetchingChats || !autenticado || !hasMoreChats)
            return
        fetchingChats = true
        chatsError = ""
        const pagina = chatPage + 1
        Api.fetchChats(baseUrl, apiToken, pagina,
            function (lista) {
                fetchingChats = false
                chatPage = pagina
                hasMoreChats = lista.length > 0
                const juntas = chatList.concat(lista)
                chatList = pagina === 1 ? lista : juntas
            }, function (fallo) {
                fetchingChats = false
                chatsError = fallo
            })
    }

    function cargarChat(id) {
        if (id === currentChatId)
            return
        if (generating)
            stopGeneration()
        fetchingChatId = id
        Api.fetchChat(baseUrl, apiToken, id,
            function (remoto) {
                fetchingChatId = ""
                const orden = Api.orderedMessages(remoto)
                if (orden.length === 0)
                    return
                messages = orden
                currentChatId = remoto.id || id
                chatTitle = remoto.title || ""
                currentResponse = ""
                errorMessage = ""
                image = ""
                selection = ""
                selectionCandidate = ""
                editingId = ""
                chatLoads++
                guardarEstado()
            }, function (fallo) {
                fetchingChatId = ""
                chatsError = fallo
            })
    }

    property string fetchingChatId: ""

    //  Bumped every time a WHOLE chat is (re)loaded — from the
    //  sidebar, or the state file at birth. The view listens and
    //  lands the conversation at its freshest words: the bottom.
    //  Appending to the live chat does not bump it; that is the
    //  stream's business, and following it is the reader's call.
    property int chatLoads: 0

    // ── models ────────────────────────────────────────────────────

    function fetchModels() {
        if (fetchingModels || !autenticado)
            return
        fetchingModels = true
        modelsError = ""
        Api.fetchModels(baseUrl, apiToken,
            function (lista) {
                fetchingModels = false
                models = lista
                //  A first run has no model chosen; the first one the
                //  server offers is a better default than a blank.
                if (currentModel.length === 0 && lista.length > 0)
                    setModel(lista[0])
            }, function (fallo) {
                fetchingModels = false
                modelsError = fallo
            })
    }

    function setModel(nombre) {
        if (!nombre || nombre.length === 0)
            return
        currentModel = nombre
        guardarAjustes()
    }

    // ── auth, driven from the Settings page ───────────────────────

    function iniciarSesion(correo, clave) {
        signingIn = true
        signInError = ""
        Api.signin(baseUrl, correo, clave,
            function (token) {
                signingIn = false
                apiToken = token
                currentChatId = ""       // the token's account, not
                chatList = []            // whoever was there before
                models = []
                guardarAjustes()
                fetchModels()
                refreshChats()
            }, function (fallo) {
                signingIn = false
                signInError = fallo
            })
    }

    function guardarClave(clave) {
        if (clave.trim().length === 0)
            return
        apiToken = clave.trim()
        guardarAjustes()
        fetchModels()
        refreshChats()
    }

    function salir() {
        apiToken = ""
        guardarAjustes()
        newChat()
        chatList = []
        models = []
    }

    //  The auth wall's only exit: straight to this plugin's page.
    function abrirAjustes() {
        if (settings)
            settings.abrirPagina("OpenWebUI")
    }

    // ── what gets attached must be seen ───────────────────────────
    //
    //  A text the user no longer remembers having marked poisons the
    //  answer without a trace, and a screenshot nobody looked at
    //  does the same with pixels.

    function attach() {
        if (selectionCandidate.length > 0)
            selection = selectionCandidate
    }

    function preview(source) {
        const text = String(source).replace(/\s+/g, " ").trim()
        return text.length > 30 ? text.substring(0, 30) + "…" : text
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
        shotProcess.command = ["sh", "-c",
            "grim -g \"$(slurp -d)\" " + dir + "/shot.png"]
        shotProcess.running = true
    }

    function copyAnswer() {
        for (let i = messages.length - 1; i >= 0; --i) {
            if (messages[i].role === "assistant"
                    && messages[i].content.length > 0) {
                K4.Sistema.lanzar(["wl-copy", "--", messages[i].content])
                return
            }
        }
    }

    // ── processes and clocks ──────────────────────────────────────

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

    //  The payload file the sender script reads — text only, small;
    //  the image it names is embedded inside the script, where a
    //  megabyte is not a crime.
    K4.Fichero {
        id: carga
        path: self.dir + "/payload.json"
        blockLoading: true
    }

    K4.Process {
        id: flujo
        porLineas: true
        property string buffer: ""

        onLinea: function (linea) { self.lineaFlujo(linea) }

        onLineaError: function (linea) {
            if (linea.indexOf("enviar.py") !== -1
                    || linea.indexOf("python") !== -1)
                console.warn("k4.openwebui: " + linea)
        }

        onTerminado: function (code) { self.flujoTerminado(code) }
    }

    Timer {
        id: timeoutTimer
        interval: 300000
        onTriggered: {
            if (flujo.running) {
                //  Marked as voluntary so `flujoTerminado` does not
                // treat the corpse's last breath as an answer on top
                // of the timeout error.
                self.manuallyStopped = true
                flujo.running = false
                self.generating = false
                self.appendMessage("error",
                                   "The model didn't answer within "
                                   + "5 minutes.")
                self.currentResponse = ""
            }
        }
    }

    Connections {
        target: Modulos
        function onRestaurado(id) {
            if (id === "openwebui")
                self.open = true
        }
    }

    K4.Ipc {
        target: "k4.openwebui"

        function toggle(): void {
            if (self.open) self.close()
            else self.openAsk(false)
        }
        //  A background question: the answer announces itself, the
        //  island stays out of the way.
        function send(message: string): void {
            if (!message || message.trim().length === 0)
                return
            self.query = message.trim()
            self.send()
        }
        function stop(): void { self.stopGeneration() }
        function newChat(): void { self.newChat() }
        function setModel(model: string): void { self.setModel(model) }
    }

    //  The Settings page: server, sign-in and behavior, shipped by
    //  the plugin that knows the work. `plugin: self` hands the page
    //  the live engine — the knobs it edits are the ones above.
    K4.Pagina {
        plugin: "openwebui"
        name: "conexion"
        titulo: "OpenWebUI"
        glifo: 0xF0B79 // md-chat
        desc: "Server, sign-in and chat behavior"
        claves: ["openwebui", "chat", "ai", "model", "llm"]
        componente: Component { OpenWebUIPagina { plugin: self } }
    }

    view: Component {
        OpenWebUIView { plugin: self }
    }
}
