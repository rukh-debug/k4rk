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
    let settled = false
    xhr.open(metodo, url)
    xhr.setRequestHeader("Content-Type", "application/json")
    if (token && String(token).length > 0)
        xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function () {
        if (settled || xhr.readyState !== XMLHttpRequest.DONE)
            return
        settled = true
        if (xhr.status >= 200 && xhr.status < 300) {
            let response
            try {
                response = JSON.parse(xhr.responseText)
            } catch (e) {
                alFallo("Bad JSON from the server: " + e)
                return
            }
            alOk(response)
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
    xhr.onerror = function () {
        if (!settled) { settled = true; alFallo("Network error") }
    }
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
    get(url, "/api/models", token, function (resp) {
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
    get(url, "/api/v1/chats/" + encodeURIComponent(id), token, alOk, alFallo)
}

//  Create or update the server-side chat. An empty `chatId` creates;
//  anything else updates that one. The callback receives the saved
//  chat — its `id` is what a follow-up turn needs.
function saveChat(url, token, chatId, chatData, alOk, alFallo) {
    post(url, chatId ? "/api/v1/chats/" + encodeURIComponent(chatId) : "/api/v1/chats/new",
         token, chatData, alOk, alFallo)
}

//  The OpenWebUI chat document: a linear chain of messages with
//  parent/children links, mirrored in the map the web client walks
//  and the array the API reads. Local-only messages (errors) stay
//  out: the server never saw them.
function exportChat(titulo, model, messages, existing) {
    const document = existing ? JSON.parse(JSON.stringify(existing)) : {}
    const usedModels = (document.models || []).slice()
    if (usedModels.indexOf(model) < 0) usedModels.push(model)
    const nodos = document.history && document.history.messages
        ? document.history.messages : {}
    const orden = []
    let ultimo = null
    for (let i = 0; i < messages.length; ++i) {
        const m = messages[i]
        if (m.role === "error")
            continue
        const id = m.id || ("msg-" + i)
        const previous = nodos[id] || {}
        nodos[id] = Object.assign({}, previous, { id: id, role: m.role, content: m.apiContent || m.content,
                      timestamp: m.timestamp || ahora(),
                      parentId: ultimo, childrenIds: previous.childrenIds || [], models: [m.model || model] })
        if (m.role === "assistant") {
            Object.assign(nodos[id], { model: m.model || model, modelName: m.model || model,
                modelIdx: 0, done: true, reasoning_content: m.reasoning || "",
                reasoningDuration: m.reasoningDuration || 0, status: m.status || "complete",
                error: m.error || "" })
        }
        if (m.selection) {
            if (!Array.isArray(m.apiContent))
                nodos[id].content = m.content + "\n\nSelected text:\n" + m.selection
            nodos[id].k4Prompt = m.content
            nodos[id].k4Selection = m.selection
        }
        if (m.files) nodos[id].files = m.files
        if (ultimo && nodos[ultimo].childrenIds.indexOf(id) < 0)
            nodos[ultimo].childrenIds.push(id)
        orden.push(id)
        ultimo = id
    }
    return {
        title: titulo,
        chat: Object.assign(document, {
            title: titulo, models: usedModels, params: document.params || {},
            history: { messages: nodos, currentId: ultimo },
            messages: orden.map(function (id) { return nodos[id] }),
            tags: document.tags || [], timestamp: document.timestamp || Date.now()
        })
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
        out.unshift({ id: id, role: m.role, content: m.k4Prompt || plainContent(m.content),
                      apiContent: m.content, files: m.files || [], model: m.model || "",
                      selection: m.k4Selection || "", error: m.error || "",
                      reasoning: m.reasoning_content || m.reasoning || "",
                      reasoningDuration: m.reasoningDuration || 0,
                      status: m.status || "complete", timestamp: m.timestamp })
        id = m.parentId
    }
    return out
}

// ── completions ──────────────────────────────────────────────────

function payload(model, history, chatId) {
    // Direct HTTP streaming: persistence is handled separately. Supplying web
    // client routing IDs can hand the stream to the server's WebSocket path.
    return { model: model, messages: history, stream: true }
}

function plainContent(content) {
    if (typeof content === "string") return content
    if (!Array.isArray(content)) return ""
    return content.filter(function (part) { return part.type === "text" })
        .map(function (part) { return part.text || "" }).join("\n")
}

function messageId() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        const r = Math.floor(Math.random() * 16)
        return (c === "x" ? r : (r & 3) | 8).toString(16)
    })
}

// Separate provider-supplied reasoning without interpreting literal examples in
// fenced or inline code. Partial opening/closing markers stay out of the answer.
function presentation(content, reasoning) {
    const source = String(content || "")
    if (source.indexOf("<") < 0)
        return { answer: source, reasoning: String(reasoning || ""), thinking: false }
    let answer = "", thought = "", mode = "", fence = "", inline = 0
    const lines = source.split("\n")
    for (let n = 0; n < lines.length; ++n) {
        const line = lines[n] + (n < lines.length - 1 ? "\n" : "")
        const marker = line.match(/^ {0,3}(`{3,}|~{3,})/)
        if (marker) {
            if (!fence) fence = marker[1]
            else if (marker[1][0] === fence[0] && marker[1].length >= fence.length) fence = ""
            if (mode) thought += line; else answer += line
            continue
        }
        if (fence) { if (mode) thought += line; else answer += line; continue }
        for (let i = 0; i < line.length;) {
            if (line[i] === "`") {
                const ticks = line.substring(i).match(/^`+/)[0]
                if (!inline) inline = ticks.length
                else if (inline === ticks.length) inline = 0
                if (mode) thought += ticks; else answer += ticks
                i += ticks.length
                continue
            }
            if (!inline && line[i] === "<") {
                const rest = line.substring(i)
                const open = rest.match(/^<(think|thinking|reasoning)>/i)
                    || rest.match(/^<details\b[^>]*\btype=["']reasoning["'][^>]*>/i)
                const close = mode && rest.match(new RegExp("^</" + mode + ">", "i"))
                if (!mode && open) {
                    mode = open[1] ? open[1].toLowerCase() : "details"
                    i += open[0].length
                    continue
                }
                if (close) { mode = ""; i += close[0].length; continue }
                if (n === lines.length - 1) {
                    const partial = rest.toLowerCase()
                    const tags = mode ? ["</" + mode + ">"] : ["<think>", "<thinking>", "<reasoning>", "<details"]
                    if (tags.some(function (tag) { return tag.indexOf(partial) === 0 })
                            || (!mode && /^<details\b[^>]*$/i.test(rest))) break
                }
            }
            if (mode) thought += line[i]; else answer += line[i]
            i++
        }
    }
    thought = thought.replace(/<summary>[\s\S]*?<\/summary>/gi, "").replace(/^> ?/gm, "").trim()
    return { answer: answer.replace(/^\n+|\n+$/g, ""), reasoning: [String(reasoning || "").trim(), thought].filter(Boolean).join("\n\n"), thinking: mode.length > 0 }
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
