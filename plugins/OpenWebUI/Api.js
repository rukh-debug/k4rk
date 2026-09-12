//  OpenWebUI's HTTP surface, gathered in one place: the XHR helpers
//  the chat engine and the Settings page share, plus the builders that
//  know OpenWebUI's payload shapes.
//
//  Every call takes the base URL as humans write it — trailing slash
//  and all — and trims it once, here. Callback style because QML has
//  no promises worth using from a library.

.pragma library

function base(url) {
    return String(url || "").replace(/\/+$/, "")
}

function ahora() {
    return Math.floor(Date.now() / 1000)
}

// ── the one XHR everything goes through ──────────────────────────

function pedir(metodo, url, token, cuerpo, alOk, alFallo) {
    const xhr = new XMLHttpRequest()
    xhr.open(metodo, url)
    xhr.setRequestHeader("Content-Type", "application/json")
    if (token && String(token).length > 0)
        xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                alOk(JSON.parse(xhr.responseText))
            } catch (e) {
                alFallo("Bad JSON from the server: " + e)
            }
            return
        }
        //  OpenWebUI speaks {detail: …} on errors and OpenAI-style
        //  {error: {message}}; both are worth a look before falling
        //  back to the bare code.
        let detalle = ""
        try {
            const d = JSON.parse(xhr.responseText)
            detalle = d.detail
                    || (d.error && d.error.message)
                    || (d.message)
                    || ""
        } catch (e) { }
        alFallo("HTTP " + xhr.status
                + (String(detalle).length > 0 ? ": " + detalle : ""))
    }
    xhr.onerror = function () { alFallo("Network error") }
    xhr.send(cuerpo === null ? null : JSON.stringify(cuerpo))
}

function get(url, camino, token, alOk, alFallo) {
    pedir("GET", base(url) + camino, token, null, alOk, alFallo)
}

function post(url, camino, token, cuerpo, alOk, alFallo) {
    pedir("POST", base(url) + camino, token, cuerpo, alOk, alFallo)
}

// ── auth ─────────────────────────────────────────────────────────

//  Email and password in, the API token out. The credentials are
//  never kept: only the token is stored, exactly like the web client
//  keeps its session cookie and not your password.
function signin(url, correo, clave, alOk, alFallo) {
    post(url, "/api/v1/auths/signin", "",
         { email: correo, password: clave },
         function (resp) {
             if (resp && resp.token)
                 alOk(resp.token)
             else
                 alFallo("The server answered without a token")
         }, alFallo)
}

// ── models ───────────────────────────────────────────────────────

//  Three response shapes in the wild — OpenAI-style {data: […]}, a
//  bare array, and {models: […]} — and all three are honored so the
//  list survives whatever the instance feels like answering.
function fetchModels(url, token, alOk, alFallo) {
    get(url, "/api/v1/models", token, function (resp) {
        const bruto = (resp && resp.data) ? resp.data
                    : Array.isArray(resp) ? resp
                    : (resp && resp.models) ? resp.models : []
        alOk(bruto.map(function (m) {
            return m.id || m.name || String(m)
        }).filter(function (id) {
            return id.length > 0
        }))
    }, alFallo)
}

// ── chats ────────────────────────────────────────────────────────

function fetchChats(url, token, pagina, alOk, alFallo) {
    get(url, "/api/v1/chats/?page=" + pagina, token, function (resp) {
        alOk(Array.isArray(resp) ? resp : [])
    }, alFallo)
}

function fetchChat(url, token, id, alOk, alFallo) {
    get(url, "/api/v1/chats/" + id, token, alOk, alFallo)
}

//  Create or update the server-side chat. An empty `chatId` creates;
//  anything else updates that one. The callback receives the saved
//  chat — its `id` is what a follow-up turn needs.
function saveChat(url, token, chatId, chatData, alOk, alFallo) {
    post(url, chatId ? "/api/v1/chats/" + chatId : "/api/v1/chats/new",
         token, chatData, alOk, alFallo)
}

//  The OpenWebUI chat document: a linear chain of messages with
//  parent/children links, mirrored in the map the web client walks
//  and the array the API reads. Local-only messages (errors) stay
//  out: the server never saw them.
function exportChat(titulo, model, messages) {
    const nodos = {}
    const orden = []
    let ultimo = null
    for (let i = 0; i < messages.length; ++i) {
        const m = messages[i]
        if (m.role === "error")
            continue
        const id = m.id || ("msg-" + i)
        nodos[id] = { id: id, role: m.role, content: m.content,
                      timestamp: m.timestamp || ahora(),
                      parentId: ultimo, childrenIds: [], models: [model] }
        if (ultimo)
            nodos[ultimo].childrenIds.push(id)
        orden.push(id)
        ultimo = id
    }
    return {
        title: titulo,
        chat: {
            id: "", title: titulo, models: [model], params: {},
            history: { messages: nodos, currentId: ultimo },
            messages: orden.map(function (id) { return nodos[id] }),
            tags: [], timestamp: Date.now()
        },
        folder_id: null
    }
}

//  OpenWebUI keeps its history as a tree; the live branch is the walk
//  from `currentId` up the `parentId` chain. A visited-set guards
//  against cycles a branched history could leave behind.
function orderedMessages(chat) {
    const history = chat && chat.chat ? chat.chat.history : null
    if (!history || !history.currentId || !history.messages)
        return []
    const out = []
    const vistos = {}
    let id = history.currentId
    while (id && !vistos[id]) {
        const m = history.messages[id]
        if (!m)
            break
        vistos[id] = true
        out.unshift({ id: id, role: m.role, content: m.content,
                      timestamp: m.timestamp })
        id = m.parentId
    }
    return out
}

// ── completions ──────────────────────────────────────────────────

function payload(model, history, chatId) {
    const p = { model: model, messages: history, stream: true }
    if (chatId && chatId.length > 0)
        p.chat_id = chatId
    return p
}

//  Ask the server to name the conversation, using its own title task.
//  The answer arrives as a completion whose content is sometimes bare
//  text, sometimes a JSON object with a title field, sometimes JSON
//  with spaces around the quotes — all three are the same task.
function generateTitle(url, token, model, messages, alOk, alFallo) {
    post(url, "/api/v1/tasks/title/completions", token,
         { model: model, messages: messages },
         function (resp) {
             const contenido = resp && resp.choices && resp.choices[0]
                     && resp.choices[0].message
                     && resp.choices[0].message.content
             if (!contenido) {
                 alFallo("The server answered without a title")
                 return
             }
             let titulo = ""
             try {
                 const comoJson = JSON.parse(contenido)
                 titulo = comoJson && comoJson.title
                         ? String(comoJson.title) : String(contenido)
             } catch (e) {
                 const entrecomillado = contenido.match(/"title"\s*:\s*"([^"]*)"/)
                 titulo = entrecomillado ? entrecomillado[1]
                                       : String(contenido)
             }
             titulo = titulo.replace(/^["']|["']$/g, "").trim()
             if (titulo.length === 0)
                 alFallo("The title came back empty")
             else
                 alOk(titulo)
         }, alFallo)
}

//  The chosen default, said first: every list that offers models
//  shows the default on top, whether it came from the pin list or
//  from the whole catalog.
function withDefaultFirst(models, def) {
    if (!def || def.length === 0)
        return models.slice()
    const resto = models.filter(function (m) { return m !== def })
    return [def].concat(resto)
}

// ── time, as the sidebar tells it ────────────────────────────────

function relativeTime(segs) {
    const delta = ahora() - Number(segs || 0)
    if (delta < 60)
        return "now"
    if (delta < 3600)
        return Math.floor(delta / 60) + "m ago"
    if (delta < 86400)
        return Math.floor(delta / 3600) + "h ago"
    if (delta < 604800)
        return Math.floor(delta / 86400) + "d ago"
    return new Date(Number(segs) * 1000).toLocaleDateString()
}
