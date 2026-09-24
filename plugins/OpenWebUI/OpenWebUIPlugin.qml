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
    summonCommand: "k4.openwebui toggle"
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

    // Non-secret drafts may survive reopening. Credentials are transient;
    // changing servers is an explicit action, never a page-destruction effect.
    property string draftServer: ""
    property string draftEmail: ""
    property string draftPassword: ""
    property string draftApiKey: ""

    readonly property bool autenticado: apiToken.length > 0
    property bool connectionVerified: false
    property int connectionEpoch: 0
    onBaseUrlChanged: invalidateConnection()
    onApiTokenChanged: invalidateConnection()
    function invalidateConnection() {
        connectionEpoch++
        if (generating) stopGeneration(true)
        savingChat = false
        saveAgain = false
        connectionVerified = false
        fetchingModels = false
        fetchingChats = false
        fetchingChatId = ""
        signingIn = false
    }

    // ── the conversation ──────────────────────────────────────────
    property bool open: false
    property var messages: []          // [{ id, role, content, timestamp, imagen? }]
    property string currentChatId: ""  // the server's id for this chat
    property string chatTitle: ""
    property bool generating: false
    property string currentResponse: "" // the stream, as it lands
    property string currentReasoning: ""
    property string responseId: ""
    property string responseModel: ""
    property string responsePhase: "Waiting"
    property double reasoningStarted: 0
    property int reasoningSeconds: 0
    property int generationSerial: 0
    property var activeStream: null
    property int chatEpoch: 0
    property int chatRequest: 0
    property var chatDocument: ({})
    property string syncError: ""
    property bool savingChat: false
    property bool saveAgain: false
    property bool titlingChat: false
    property int composerHeight: 42
    property var outgoingIds: []
    property string errorMessage: ""
    property bool sidebarVisible: false

    // ── attachments, offered and taken ────────────────────────────
    property string query: ""
    property string image: ""               // path of the shot to send
    property string selection: ""           // truly attached (opt-in)
    property string selectionCandidate: ""  // what was selected, not yet attached
    property bool attachSelectionOnOpen: false

    // Editing replaces the active branch from this turn. Already saved branches
    // remain in the server document and the new leaf becomes currentId.
    property string editingId: ""

    // ── the lists the sidebar and the selector show ───────────────
    property var chatList: []           // [{ id, title, updated_at }]
    property bool fetchingChats: false
    property string chatsError: ""
    property bool hasMoreChats: true
    property int chatPage: 0
    property int chatListRequest: 0
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
    onRememberHistoryChanged: if (!rememberHistory && ajustes.ready && !loadingPreferences) guardarAjustes()
    property bool loadingPreferences: false

    readonly property string dir: "/tmp/k4-openwebui"

    islandWidth: !autenticado ? 520
                 : sidebarVisible ? 900 : 660
    //  The height the chat itself asks for; the selector popup —
    //  30 px down plus up to 360 of list — is taller than the empty
    //  state, so while it is open the island stands up for it.
    readonly property int altoBase:
        (messages.length > 0 || sidebarVisible) ? 560 : 174 + Math.max(0, composerHeight - 42)
    islandHeight: !autenticado ? 340
                  : selectorOpen ? Math.max(altoBase, 410)
                  : altoBase

    // ── persistence ───────────────────────────────────────────────
    //
    // Shareable behavior preferences use config.json. Server profiles and
    // conversations are owner-local state; tokens are keyring entries.
    K4.Credential {
        id: credential
        plugin: "openwebui"
        account: self.baseUrl.replace(/\/+$/, "")
        onValueChanged: self.apiToken = value
        onErrorChanged: if (error) self.signInError = error
    }

    K4.PluginSettings {
        id: ajustes
        plugin: "openwebui"
        onLoaded: function (d) {
            self.loadingPreferences = true
            self.rememberHistory = d.rememberHistory !== false
            self.openAfterResponse = d.openAfterResponse === true
            self.loadingPreferences = false
            if (!self.rememberHistory) {
                self.messages = []
                self.currentChatId = ""
                self.chatTitle = ""
            } else if (estado.ready) self.restoreHistory(estado.value)
        }
    }
    K4.PluginState {
        id: profile
        plugin: "openwebui"
        name: "profile"
        onErrorChanged: if (error) self.signInError = error
        onLoaded: function (d) {
            self.baseUrl = d.baseUrl || ""
            self.currentModel = d.currentModel || ""
            self.draftServer = d.draftServer || d.baseUrl || ""
            self.draftEmail = d.draftEmail || ""
            self.draftPassword = ""
            self.draftApiKey = ""
            self.pinLists = Array.isArray(d.pinLists) ? d.pinLists : []
        }
    }

    function guardarAjustes() {
        if (!ajustes.ready || loadingPreferences) return
        const sections = {
            settings: { rememberHistory: rememberHistory, openAfterResponse: openAfterResponse }
        }
        if (profile.ready) sections.profile = { baseUrl: baseUrl, currentModel: currentModel,
            draftServer: draftServer, draftEmail: draftEmail, pinLists: pinLists }
        if (!rememberHistory) sections.state = {}
        ajustes.saveSections(sections)
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

    // Apply a server explicitly. Credentials belong to the server that issued them.
    function confirmarBorradores() {
        if (!profile.ready) {
            signInError = profile.error || "The local server profile is still loading"
            return false
        }
        const nuevo = draftServer.trim().replace(/\/+$/, "")
        if (!/^https?:\/\/[^/\s]+(?:\/[^\s]*)?$/.test(nuevo)) {
            signInError = "Enter a complete http:// or https:// server address."
            return false
        }
        if (nuevo !== baseUrl.replace(/\/+$/, "")) {
            if (signingIn || generating || fetchingModels || fetchingChats) {
                signInError = "Wait for the current request to finish before changing servers."
                return false
            }
            salir()
            baseUrl = nuevo
        }
        draftServer = nuevo
        signInError = ""
        guardarAjustes()
        return true
    }

    K4.PluginState {
        id: estado
        plugin: "openwebui"
        onLoaded: function (d) { self.restoreHistory(d) }
    }
    function restoreHistory(d) {
            if (!ajustes.ready || !rememberHistory) return
            self.messages = Array.isArray(d.messages) ? d.messages : []
            self.currentChatId = d.currentChatId || ""
            self.chatTitle = d.chatTitle || ""
            self.sidebarVisible = d.sidebarVisible === true
            self.chatDocument = d.chatDocument || {}
    }

    function guardarEstado() {
        if (!rememberHistory) {
            estado.save({})
            return
        }
        // Keep the full active branch so a reopened chat retains its parent chain.
        estado.save({ messages: messages,
                         currentChatId: currentChatId,
                         chatTitle: chatTitle,
                         chatDocument: chatDocument,
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

    //  The outside knock — quick access, the app centre — opens the
    //  way the keybind's toggle does: arrive asking, fresh.
    //  Overridden on purpose: the contract's default would flip
    //  `active` imperatively, breaking the `habilitado && open`
    //  binding and leaving a view that no longer closes when `open`
    //  does.
    function abrir() { openAsk(false) }

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
        chatEpoch++
        chatRequest++
        fetchingChatId = ""
        chatDocument = ({})
        savingChat = false
        saveAgain = false
        titlingChat = false
        syncError = ""
        query = ""
        messages = []
        currentChatId = ""
        chatTitle = ""
        currentResponse = ""
        currentReasoning = ""
        errorMessage = ""
        selection = ""
        selectionCandidate = ""
        attachSelectionOnOpen = false
        image = ""
        editingId = ""
        guardarEstado()
        chatLoads++
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
            return false
        if (baseUrl.trim().length === 0 || !autenticado) {
            openAsk(false)
            return false
        }
        if (currentModel.length === 0) {
            errorMessage = "No model selected — pick one in Settings."
            return false
        }

        errorMessage = ""
        // Start a new active branch at the edited turn. Attachments belong to
        // the composer, so only the currently attached context is sent.
        if (editingId.length > 0) {
            const idx = indiceDe(editingId)
            if (idx >= 0)
                messages = messages.slice(0, idx)
            editingId = ""
        }

        despachar(texto, image)
        return true
    }

    // The immutable payload and credentials travel on stdin, avoiding argv's
    // size limit and keeping overlapping generations independent.
    function despachar(texto, rutaImagen) {
        appendMessage("user", texto, rutaImagen, { selection: selection })
        startResponse()
        query = ""
        image = ""
        selection = ""
    }

    function startResponse() {
        generationSerial++
        chatRequest++
        fetchingChatId = ""
        generating = true
        currentResponse = ""
        currentReasoning = ""
        errorMessage = ""
        responseId = Api.messageId()
        responseModel = currentModel
        responsePhase = "Waiting"
        reasoningStarted = 0
        reasoningSeconds = 0
        timeoutTimer.restart()

        const history = []
        outgoingIds = []
        for (let i = 0; i < messages.length; ++i) {
            const m = messages[i]
            if (m.role === "error")
                continue
            let content = m.apiContent || m.content
            if (m.role === "assistant") content = Api.presentation(m.content, m.reasoning).answer
            if (m.role === "user" && m.selection && !Array.isArray(content))
                content = m.content + "\n\nSelected text:\n" + m.selection
            const turn = { role: m.role, content: content }
            if (m.imagen && !Array.isArray(content)) turn.local_image = m.imagen
            outgoingIds.push(m.id)
            history.push(turn)
        }
        activeStream = streamFactory.createObject(self, {
            serial: generationSerial,
            request: JSON.stringify({ url: Api.base(baseUrl), token: apiToken,
                payload: Api.payload(responseModel, history, currentChatId) })
        })
        activeStream.running = true
    }

    function retryLast() {
        if (generating || !autenticado || !currentModel) return
        let end = messages.length - 1
        while (end >= 0 && messages[end].role !== "user") end--
        if (end < 0) return
        messages = messages.slice(0, end + 1)
        startResponse()
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

    function appendMessage(role, content, imagen, metadata) {
        const m = Object.assign({ id: Api.messageId(),
                    role: role, content: content,
                    imagen: imagen || "",
                    timestamp: Api.ahora() }, metadata || {})
        messages = messages.concat([m])
        return m
    }

    function stopGeneration(skipSync) {
        if (!generating)
            return
        generationSerial++
        if (activeStream) activeStream.running = false
        activeStream = null
        generating = false
        timeoutTimer.stop()
        finalizeAssistant(errorMessage ? "failed" : "stopped")
        if (!skipSync) sincronizarServidor()
    }

    // The transport normalizes SSE and non-streaming JSON into the same events.
    function lineaFlujo(linea) {
        try {
            const event = JSON.parse(linea)
            if (event.type === "attachments") {
                const updated = messages.slice()
                for (const attachment of event.messages) {
                    const index = indiceDe(outgoingIds[attachment.index])
                    if (index >= 0)
                        updated[index] = Object.assign({}, updated[index], { apiContent: attachment.content })
                }
                messages = updated
                return
            }
            if (event.type === "error") {
                errorMessage = event.message || "The request failed."
                return
            }
            if (event.type !== "delta" && event.type !== "message") return
            currentResponse = event.type === "message" ? event.content : currentResponse + event.content
            currentReasoning = event.type === "message" ? event.reasoning : currentReasoning + event.reasoning
            const parts = Api.presentation(currentResponse, currentReasoning)
            if ((event.reasoning || parts.thinking) && !reasoningStarted)
                reasoningStarted = Date.now()
            const previousPhase = responsePhase
            responsePhase = parts.thinking || (event.reasoning && !event.content) ? "Thinking"
                          : parts.answer.length > 0 ? "Responding" : currentReasoning.length > 0 ? "Thinking" : "Waiting"
            if (previousPhase === "Thinking" && responsePhase !== "Thinking" && reasoningStarted)
                reasoningSeconds = Math.max(1, Math.ceil((Date.now() - reasoningStarted) / 1000))
            if (event.finish === "length") errorMessage = "The model reached its output limit."
            else if (event.finish === "content_filter") errorMessage = "The provider stopped this response."
        } catch (e) {
            errorMessage = "The server returned an unreadable response."
        }
    }

    function flujoTerminado(code) {
        generating = false
        activeStream = null
        timeoutTimer.stop()
        if (code !== 0 && !errorMessage)
            errorMessage = "The connection ended before the response completed."
        const parts = Api.presentation(currentResponse, currentReasoning)
        if (parts.reasoning && !parts.answer.trim() && !errorMessage)
            errorMessage = "The model returned reasoning without an answer."
        if (currentResponse.trim().length > 0 || currentReasoning.trim().length > 0) {
            finalizeAssistant(errorMessage ? "failed" : "complete")
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

        appendMessage("error", errorMessage || "The model returned an empty answer.")
        currentResponse = ""
        currentReasoning = ""
        errorMessage = ""
        guardarEstado()
    }

    function finalizeAssistant(status) {
        const parts = Api.presentation(currentResponse, currentReasoning)
        if (responsePhase === "Thinking" && reasoningStarted)
            reasoningSeconds = Math.max(1, Math.ceil((Date.now() - reasoningStarted) / 1000))
        appendMessage("assistant", parts.answer, "", {
            id: responseId, model: responseModel, reasoning: parts.reasoning,
            reasoningDuration: reasoningSeconds, status: status || "complete", error: errorMessage
        })
        currentResponse = ""
        currentReasoning = ""
        errorMessage = ""
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
        if (savingChat) { saveAgain = true; return }
        savingChat = true
        saveAgain = false
        syncError = ""
        const datos = Api.exportChat(chatTitle.length > 0
                                     ? chatTitle : tituloProvisional(),
                                     currentModel, messages, chatDocument)
        const epoch = connectionEpoch
        const conversation = chatEpoch
        Api.saveChat(baseUrl, apiToken, currentChatId, datos,
            function (resp) {
                if (epoch !== connectionEpoch || conversation !== chatEpoch) return
                savingChat = false
                chatDocument = datos.chat
                guardarEstado()
                if (resp && resp.id && resp.id !== currentChatId) {
                    currentChatId = resp.id
                    guardarEstado()
                }
                if (messages.length === 2)
                    ponerTitulo()
                refreshChats()
                if (saveAgain) sincronizarServidor()
            }, function (fallo) {
                //  Not fatal: the conversation goes on, it just won't
                //  be in the web UI's list. The next exchange retries.
                if (epoch !== connectionEpoch || conversation !== chatEpoch) return
                savingChat = false
                syncError = (rememberHistory ? "Chat saved locally. " : "") + "Server sync failed: " + fallo
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
        if (titlingChat || chatTitle.length > 0 || currentChatId.length === 0
                || messages.length < 2)
            return
        titlingChat = true
        const primeros = []
        for (let i = 0; i < messages.length && primeros.length < 2; ++i)
            if (messages[i].role === "user"
                    || messages[i].role === "assistant")
                primeros.push({ role: messages[i].role,
                                content: messages[i].content })
        const epoch = connectionEpoch
        const conversation = chatEpoch
        const titleChat = currentChatId
        Api.generateTitle(baseUrl, apiToken, currentModel, primeros,
            function (titulo) {
                if (epoch !== connectionEpoch || conversation !== chatEpoch || titleChat !== currentChatId) return
                titlingChat = false
                chatTitle = titulo
                guardarEstado()
                // the title travels with the next save; a save with
                // nothing new would be the same chat, so it is safe
                sincronizarServidor()
                refreshChats()
            }, function (fallo) {
                if (epoch !== connectionEpoch || conversation !== chatEpoch) return
                titlingChat = false
                console.warn("k4.openwebui: title: " + fallo)
            })
    }

    // ── the sidebar's list ────────────────────────────────────────

    function refreshChats() {
        chatListRequest++
        fetchingChats = false
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
        const epoch = connectionEpoch
        const request = chatListRequest
        Api.fetchChats(baseUrl, apiToken, pagina,
            function (lista) {
                if (epoch !== connectionEpoch || request !== chatListRequest) return
                fetchingChats = false
                chatPage = pagina
                hasMoreChats = lista.length > 0
                const juntas = chatList.concat(lista)
                chatList = pagina === 1 ? lista : juntas
            }, function (fallo) {
                if (epoch !== connectionEpoch || request !== chatListRequest) return
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
        const epoch = connectionEpoch
        const request = ++chatRequest
        Api.fetchChat(baseUrl, apiToken, id,
            function (remoto) {
                if (epoch !== connectionEpoch || request !== chatRequest) return
                fetchingChatId = ""
                const orden = Api.orderedMessages(remoto)
                if (orden.length === 0)
                    return
                messages = orden
                chatEpoch++
                chatDocument = remoto.chat || {}
                savingChat = false
                saveAgain = false
                titlingChat = false
                syncError = ""
                currentChatId = remoto.id || id
                chatTitle = remoto.title || ""
                currentResponse = ""
                currentReasoning = ""
                query = ""
                errorMessage = ""
                image = ""
                selection = ""
                selectionCandidate = ""
                editingId = ""
                chatLoads++
                guardarEstado()
            }, function (fallo) {
                if (epoch !== connectionEpoch || request !== chatRequest) return
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
        const epoch = connectionEpoch
        Api.fetchModels(baseUrl, apiToken,
            function (lista) {
                if (epoch !== connectionEpoch) return
                fetchingModels = false
                connectionVerified = true
                models = lista
                //  A first run has no model chosen; the first one the
                //  server offers is a better default than a blank.
                if (currentModel.length === 0 && lista.length > 0)
                    setModel(lista[0])
            }, function (fallo) {
                if (epoch !== connectionEpoch) return
                fetchingModels = false
                connectionVerified = false
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
        if (signingIn || !correo.trim() || !clave || !confirmarBorradores()) return
        signingIn = true
        signInError = ""
        const epoch = connectionEpoch
        Api.signin(baseUrl, correo, clave,
            function (token) {
                if (epoch !== connectionEpoch) return
                signingIn = false
                apiToken = token
                credential.save(token)
                currentChatId = ""       // the token's account, not
                chatList = []            // whoever was there before
                models = []
                draftPassword = ""
                draftApiKey = ""
                guardarAjustes()
                fetchModels()
                refreshChats()
            }, function (fallo) {
                if (epoch !== connectionEpoch) return
                signingIn = false
                signInError = fallo
            })
    }

    function guardarClave(clave) {
        if (signingIn || clave.trim().length === 0 || !confirmarBorradores())
            return
        apiToken = clave.trim()
        credential.save(apiToken)
        draftPassword = ""
        draftApiKey = ""
        guardarAjustes()
        fetchModels()
        refreshChats()
    }

    function salir() {
        apiToken = ""
        credential.save("")
        draftPassword = ""
        draftApiKey = ""
        modelsError = ""
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
        shotProcess.capturedPath = dir + "/shot-" + Date.now() + ".png"
        shotProcess.command = ["grim", shotProcess.capturedPath]
        shotProcess.running = true
    }

    function attachRegion() {
        image = ""
        shotProcess.capturedPath = dir + "/shot-" + Date.now() + ".png"
        shotProcess.command = ["sh", "-c",
            "grim -g \"$(slurp -d)\" " + shotProcess.capturedPath]
        shotProcess.running = true
    }

    function copyAnswer() {
        for (let i = messages.length - 1; i >= 0; --i) {
            if (messages[i].role === "assistant"
                    && messages[i].content.length > 0) {
                copyText(Api.presentation(messages[i].content, messages[i].reasoning).answer)
                return
            }
        }
    }

    // Send large code blocks through stdin, never a length-limited argv entry.
    function copyText(text) {
        const process = clipboardFactory.createObject(self, { value: text })
        process.running = true
    }

    Component {
        id: clipboardFactory
        K4.Process {
            property string value: ""
            command: ["wl-copy"]
            entradaAbierta: true
            onArrancado: { escribir(value); entradaAbierta = false }
            onTerminado: destroy()
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
        property string capturedPath: ""

        onTerminado: function (code) {
            const shot = code === 0 ? capturedPath : ""
            self.openAsk(false)
            self.image = shot
        }
    }

    Component {
        id: streamFactory
        K4.Process {
            property int serial: 0
            property string request: ""
            command: ["python3", self.fichero("enviar.py")]
            entradaAbierta: true
            porLineas: true
            onArrancado: { escribir(request + "\n"); request = "" }
            onLinea: function (line) { if (serial === self.generationSerial) self.lineaFlujo(line) }
            onTerminado: function (code) {
                if (serial === self.generationSerial) self.flujoTerminado(code)
                destroy()
            }
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: self.generating && self.responsePhase === "Thinking"
        onTriggered: if (self.reasoningStarted)
            self.reasoningSeconds = Math.max(1, Math.floor((Date.now() - self.reasoningStarted) / 1000))
    }

    Timer {
        id: timeoutTimer
        interval: 300000
        onTriggered: {
            self.errorMessage = "The response timed out after 5 minutes."
            self.stopGeneration()
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
        claves: ["openwebui", "chat", "ai", "model", "llm", "server", "sign in", "api key", "password", "history", "pin lists"]
        componente: Component { OpenWebUIPagina { plugin: self } }
    }

    view: Component {
        OpenWebUIView { plugin: self }
    }
}
