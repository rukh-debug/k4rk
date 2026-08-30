pragma Singleton

//  Preferencias de la barra.
//
//  Solo vive aquí lo que de verdad cambia algo: un interruptor que no está
//  conectado a nada es peor que no tenerlo. Cada opción dice qué módulo la
//  lee, para que no queden huérfanas al refactorizar.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: ajustes

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/ajustes.json"

    // ── barra ─────────────────────────────────────────────────────
    //  En qué borde vive la barra. shell.qml ancla la ventana, voltea la
    //  silueta y orienta los gestos con esto; los plugins lo leen por
    //  K4.Isla.posicion para adaptar lo que pinten fuera.
    property string barPosition: "top"        // top · bottom
    //  En qué punto del borde se centra la island, en tanto por ciento del
    //  ancho libre: 50 es el centro de siempre. Un plugin puede desplazarla
    //  TEMPORALMENTE con K4.Isla.colocar; esto es la base a la que vuelve.
    property int barAlignment: 50            // 15 · 50 · 85
    //  Qué hace la barra con el sitio del escritorio.
    //
    //  «reserva» es lo de siempre: la franja plegada se le quita al escritorio
    //  y ninguna ventana se mete debajo. «encima» no le quita nada —la píldora
    //  flota sobre las ventanas— y «escondida» además la retira por el borde
    //  hasta que hay algo que enseñar. Y «completa» no es un cuarto estado
    //  sino una regla: reserva como siempre, y se esconde SOLO mientras una
    //  ventana llena la pantalla. shell.qml es quien las obedece.
    property string islandSpace: "reserve"    // reserve · auto · onTop · hidden
    //  Click outside the bar closes whatever view is deployed, like Escape.
    //  shell.qml grows its surface to the whole screen while a view is open
    //  and spends the outside tap on closing it. Off is the old behavior:
    //  the click passes through to the desktop and the view stays.
    property bool cerrarConClicFuera: true
    // widgets/TrayRow.qml: iconos de bandeja en la píldora
    // Apagada de fábrica: en la píldora los iconos de bandeja son ruido casi
    // siempre, y al acercar el ratón la island ya se abre y ahí sí se ven —y
    // encima se pueden pulsar, que en la píldora no—.
    property bool trayInPill: false
    // widgets/NotifStrip.qml: notificaciones recientes al pasar el ratón
    property bool notificationsOnHover: true
    // services/Notifs.qml: descartar las de una aplicación al ir a su ventana
    property bool notificationsOnFocus: true

    //  ── la isla de Ajustes ──────────────────────
    //  plugins/Settings/SettingsPlugin.qml sizes its island with these. They
    //  are here —and not constants there— because the Island page lets the
    //  user set them, and a value nobody can read back is a setting that lies.
    //  The plugin clamps to the same bounds the steppers use, so a hand-edited
    //  file cannot open a window bigger than the screen or smaller than the
    //  sidebar.
    property int settingsIslandWidth: 940    // 720–1400, steps of 20
    property int settingsIslandHeight: 620    // 420–900, steps of 20

    //  ── the control centre ──────────────────
    //  plugins/Panel dresses itself with these. The WIDTH is a number you
    //  turn; the height is not, and on purpose: it is derived from what is
    //  on show (each block brings its own height), so hiding the media row
    //  makes the centre shorter instead of leaving a hole. Blocks can be
    //  turned off (`panelShow*`, and the tiles one by one) and re-ordered
    //  (`panelOrder`, top to bottom). The header keeps its bells and
    //  whistles always; its two decorations are optional.
    property int panelWidth: 860              // 640–1100, steps of 20
    property bool panelShowToggles: true
    property bool panelTileWifi: true
    property bool panelTileBluetooth: true
    property bool panelTileSound: true
    property bool panelShowMedia: true
    property bool panelShowShortcuts: true
    property bool panelShowWorkspaces: true
    property bool panelShowClock: true
    //  Block ids top to bottom: "toggles", "media", "shortcuts".
    property var panelOrder: ["toggles", "media", "shortcuts"]

    //  panelOrder made honest, for the two readers (the centre and its
    //  editor): unknown ids dropped, forgotten ids appended at the end.
    //  An order is a list the user rewrites; this is the list the bar obeys.
    readonly property var panelOrdenEfectivo: {
        const guardados = panelOrder || []
        const fuera = []
        for (let i = 0; i < guardados.length; ++i)
            if (typeof guardados[i] === "string"
                && ["toggles", "media", "shortcuts"].indexOf(guardados[i]) >= 0
                && fuera.indexOf(guardados[i]) < 0)
                fuera.push(guardados[i])
        const todos = ["toggles", "media", "shortcuts"]
        for (let i = 0; i < todos.length; ++i)
            if (fuera.indexOf(todos[i]) < 0)
                fuera.push(todos[i])
        return fuera
    }

    //  ── dónde abre cada vista ─────────────
    //  Which edge each openable view comes from, and where along that
    //  edge — the control centre from the left, Settings from the bottom
    //  corner, whatever the user draws. A map pluginId → placement, and an
    //  EMPTY entry is not "none" but "follow the bar": the view opens on
    //  the bar's edge, at the bar's alignment, which is what every view did
    //  before placement existed and stays the default so nothing jumps
    //  after the update.
    //
    //  The pill itself is not in this map — it lives wherever `barPosition`
    //  says and drags its hover views with it. What is here is what OPENS:
    //  the views you summon.
    property var islandPlacements: {}

    //  The placement a plugin opens with, resolved: its own if it has one,
    //  the bar's if it does not. Always a { side, align } with side one of
    //  top/bottom/left/right and align 0–100 — a map hand-edited into the
    //  file cannot smuggle anything stranger in.
    function placementDe(id) {
        const p = (islandPlacements || {})[id]
        if (p && (p.side === "top" || p.side === "bottom"
                  || p.side === "left" || p.side === "right")) {
            let a = Number(p.align)
            if (!isFinite(a))
                a = 50
            return { side: p.side, align: Math.max(0, Math.min(100, a)) }
        }
        return { side: barPosition === "bottom" ? "bottom" : "top",
                 align: barAlignment }
    }

    //  Writing one placement. side "" is the row's «Follow the bar» chip:
    //  the entry leaves the map instead of storing a copy of the bar's own
    //  placement, so moving the bar later moves the views that follow it.
    function ponerPlacement(id, side, align) {
        const d = Object.assign({}, islandPlacements || {})
        if (side === "")
            delete d[id]
        else
            d[id] = { side: side, align: align }
        islandPlacements = d
        guardar()
    }

    //  ── la franja que la trae de vuelta ───────
    //  While the bar is away (hidden mode, retired), thin strips on the
    //  other three edges summon it back — the path TO it when it is not
    //  there. Off means reaching for the bar's own edge only, as before.
    property bool edgeZoneEnabled: true
    //  How many pixels of border answer, per edge. One is the default on
    //  purpose: it is the thinnest promise the screen edge can make, and
    //  every pixel above it is a pixel of desktop clicks the strip keeps.
    property int edgeZoneSize: 1                // 1–8, steps of 1
    //  How rounded the rim's INSIDE corners are — where one border turns
    //  into the next. Six is quiet company for a 1 px rim; twenty-four is
    //  a bold arc. Zero is square, and the rim stays a frame.
    property int rimRadius: 6                   // 0–24, steps of 1

    //  ── la letra del shell ───────────────
    //  The shell's typeface, as a family name. Empty is the shell's own
    //  default and not a state to repair: the row list shows it as
    //  «Shell default» and picking it again is picking nothing.
    //
    //  The value travels TO `Theme` (which stays the import-free base of
    //  the graph): every label that says `Theme.uiFont` follows along, and
    //  the whole bar re-letters itself the moment you pick one.
    property string shellFont: ""
    onShellFontChanged: Theme.chosenFont = shellFont

    // ── accesos directos ──────────────────────────────────────────
    //  Qué aplicaciones salen en la franja del centro de control, por id de
    //  plugin. plugins/Panel/PanelView.qml la pinta y el centro de
    //  aplicaciones la edita con la chincheta de cada tarjeta.
    //
    //  Ids y no una copia de nombres e iconos: así al renombrar un plugin o
    //  cambiarle el icono el acceso directo se entera solo, y uno que apunte a
    //  un plugin desinstalado simplemente no se pinta.
    property var quickAccess: ["game", "settings", "system", "clipboard"]

    function esAccesoDirecto(id) {
        return (quickAccess || []).indexOf(id) >= 0
    }

    function alternarAcceso(id) {
        const l = (quickAccess || []).slice()
        const i = l.indexOf(id)
        if (i >= 0)
            l.splice(i, 1)
        else
            l.push(id)
        quickAccess = l
        guardar()
    }

    // Cambia el valor de una opción que no es un interruptor.
    function poner(id, valor) {
        if (String(id).indexOf("ext_") === 0) {
            Enganches.ponerAjuste(id, valor)
            return
        }
        ajustes[id] = valor
        guardar()
    }

    readonly property var definicion: [,,
        {
            grupo: "Island",
            glifo: 0xF1513,
            desc: "How much room the bar keeps, and when it gets out of the way.",
            //  Dónde vive, cómo se alinea y cómo ocupa el sitio se explican mal
            //  con palabras: «Reservar sitio» y «Encima» suenan parecido y
            //  hacen cosas muy distintas con tus ventanas. Encima de las
            //  opciones va un croquis que lo enseña.
            vista: "island",
            opciones: [
                { tipo: "titulo", nombre: "Where it lives" },
                { id: "barPosition", tipo: "eleccion", de: "posiciones",
                  nombre: "Where the bar lives",
                  desc: "The island and its wings flip on their own",
                  glifo: 0xF10A9 },
                { id: "barAlignment", tipo: "eleccion", de: "alineaciones",
                  nombre: "Island alignment",
                  desc: "Where along the edge it sits",
                  glifo: 0xF11C3 },
                { tipo: "titulo", nombre: "Room on the desktop" },
                { id: "islandSpace", tipo: "eleccion", de: "reservas",
                  nombre: "How it takes up space",
                  desc: "Pushes windows aside, floats over them, or hides",
                  glifo: 0xF003E },   // md-arrange_bring_to_front
                { tipo: "titulo", nombre: "The rim" },
                { id: "edgeZoneEnabled", nombre: "Island rim around the screen",
                  desc: "The island's own colour as a strip along every border — and while the bar is away, touching a border brings it back",
                  glifo: 0xF0741 },   // md-gesture_tap
                { id: "edgeZoneSize", tipo: "numero", min: 1, max: 8,
                  paso: 1, unidad: "px",
                  requiere: "edgeZoneEnabled",
                  nombre: "Rim thickness",
                  desc: "Pixels of island colour along the borders — each one also keeps its clicks",
                  glifo: 0xF00D0 },   // md-border_style
                { id: "rimRadius", tipo: "numero", min: 0, max: 24,
                  paso: 1, unidad: "px",
                  requiere: "edgeZoneEnabled",
                  nombre: "Rim corner radius",
                  desc: "How round the rim turns at the screen's corners",
                  glifo: 0xF0607 },   // md-rounded_corner
                { tipo: "titulo", nombre: "The pill" },
                { id: "trayInPill", nombre: "Tray in the pill",
                  desc: "Icons of background apps", glifo: 0xF0FB0 },
                { tipo: "titulo", nombre: "Notifications" },
                { id: "notificationsOnHover", nombre: "Notifications on hover",
                  desc: "Recent ones, under the clock and player", glifo: 0xF009A },
                { id: "notificationsOnFocus", nombre: "Dismiss when you switch to the app",
                  desc: "Switching to its window already counts as having attended to them", glifo: 0xF039F },
                { tipo: "titulo", nombre: "Clicks" },
                { id: "cerrarConClicFuera", nombre: "Click outside closes what's open",
                  desc: "Same as Escape: a deployed view closes when you click outside the bar",
                  glifo: 0xF037D },   // md-cursor_default
                { tipo: "titulo", nombre: "This window" },
                { id: "settingsIslandWidth", tipo: "numero",
                  min: 720, max: 1400, paso: 20, unidad: "px",
                  nombre: "Settings window width",
                  desc: "How wide these pages open",
                  glifo: 0xF084E },   // md-arrow_expand_horizontal
                { id: "settingsIslandHeight", tipo: "numero",
                  min: 420, max: 900, paso: 20, unidad: "px",
                  nombre: "Settings window height",
                  desc: "How tall these pages open",
                  glifo: 0xF084F }    // md-arrow_expand_vertical
            ]
        },
        {
            grupo: "Placement",
            claves: ["placement", "position", "posicion", "side",
                     "lado", "lados", "edge", "corner", "esquina",
                     "donde", "abrir", "abre", "sale"],
            glifo: 0xF09BB,        // md-arrow_decision
            desc: "Which side each view opens from, and where along that side — drag the dot to any point, corners included. The pill keeps its own home — see Island.",
            //  One card per openable view: side chips («Follow bar» is the
            //  default and the first chip) and alignment chips, with a
            //  little monitor that shows the point the words are choosing.
            vista: "placement",
            opciones: []
        },
        {
            grupo: "Control Centre",
            claves: ["panel", "centro de control", "control center",
                     "control centre", "toggles", "media", "shortcuts",
                     "accesos", "widgets"],
            glifo: 0xF1947,        // md-view_dashboard_edit
            desc: "What the control centre shows, in what order, and how wide it opens.",
            //  The page carries a sketch of the centre and the block order
            //  as a custom view; the simple knobs are plain option rows.
            vista: "panel",
            opciones: [
                { id: "panelWidth", tipo: "numero", min: 640, max: 1100,
                  paso: 20, unidad: "px",
                  nombre: "Width",
                  desc: "How wide the control centre opens",
                  glifo: 0xF084E },   // md-arrow_expand_horizontal
                { id: "panelShowToggles", nombre: "Quick toggles row",
                  desc: "Wi‑Fi, Bluetooth and sound, as tiles",
                  glifo: 0xF056E },   // md-view_dashboard
                { id: "panelTileWifi", requiere: "panelShowToggles",
                  nombre: "Wi‑Fi tile",
                  desc: "The radio and its network",
                  glifo: 0xF05A9 },   // md-wifi
                { id: "panelTileBluetooth", requiere: "panelShowToggles",
                  nombre: "Bluetooth tile",
                  desc: "The adapter and its devices",
                  glifo: 0xF00AF },   // md-bluetooth
                { id: "panelTileSound", requiere: "panelShowToggles",
                  nombre: "Sound tile",
                  desc: "The volume slider and its output",
                  glifo: 0xF057E },   // md-volume_high
                { id: "panelShowMedia", nombre: "Media row",
                  desc: "What is playing, with its controls",
                  glifo: 0xF0387 },   // md-music_note
                { id: "panelShowShortcuts", nombre: "Shortcuts strip",
                  desc: "Pinned apps — pin them from the app drawer",
                  glifo: 0xF003B },   // md-apps
                { id: "panelShowWorkspaces", nombre: "Workspace dots",
                  desc: "In the centre's header",
                  glifo: 0xF15FC },   // md-dots_grid
                { id: "panelShowClock", nombre: "Clock",
                  desc: "In the centre's header",
                  glifo: 0xF0150 }    // md-clock_outline
            ]
        },
        {
            grupo: "Display",
            //  Words the search engine should find this section by. Needed
            //  because its controls live inside a widget and not as
            //  `opciones`: without them, typing «blur» found NOTHING even
            //  though the switch sits right there.
            //
            //  Never shown, only searched: typing «gaps» deserves to find
            //  this section even though the switch lives inside a widget.
            //
            //  Wallpaper AND colour keys: the two halves are siblings under
            //  this group now, and a search word should find it whichever
            //  half it names.
            claves: ["fondo", "fondos", "wallpaper", "escritorio", "desktop",
                     "imagen", "video", "monitor", "pantalla",
                     "color", "colour", "colores", "preset", "acento",
                     "accent", "paleta", "palette", "tema", "theme", "degradado"],
            glifo: 0xF0379,      // md-monitor
            desc: "The screen: its wallpaper, its colours, its windows, its effects.",
            //  The parent of the sub-tab family. Its own page is the landing:
            //  the wallpaper at a glance and a card per child. `app` marks a
            //  card that opens a full application instead of a child page —
            //  the displays tool, which is a screen of its own and stays one;
            //  what was missing was reaching it from the place where the
            //  screen is configured.
            vista: "display",
            app: "displays",
            opciones: []
        },
        {
            grupo: "Wallpaper",
            //  A child of Display (`padre`): it renders as a sub-tab under it
            //  in the sidebar, one level deep.
            padre: "Display",
            claves: ["fondo", "fondos", "wallpaper", "escritorio",
                     "imagen", "video", "pantalla"],
            glifo: 0xF0E09,      // md-wallpaper
            desc: "The desktop wallpaper.",
            //  The grid sizes itself to its rows (`fitContent`) so the page
            //  scrolls as one in the outer Rodillo. No options declared: what
            //  gets chosen here is an image, and that does not fit a switch
            //  row.
            vista: "wallpaper",
            opciones: []
        },
        {
            grupo: "Colour",
            padre: "Display",
            claves: ["color", "colour", "colores", "preset", "acento",
                     "accent", "paleta", "palette", "tema", "theme", "degradado"],
            glifo: 0xF03D8,      // md-palette
            desc: "Where the colours come from: the wallpaper, or a preset you pick.",
            vista: "color",
            opciones: []
        },
        {
            grupo: "Fonts",
            padre: "Display",
            claves: ["font", "fuente", "fonts", "fuentes", "tipografia",
                     "typography", "letra", "typeface"],
            glifo: 0xF06D6,        // md-format_font
            desc: "The typeface the shell is written in.",
            vista: "fonts",
            opciones: []
        },
        {
            grupo: "Windows",
            padre: "Display",
            claves: ["ventanas", "windows", "borde", "border", "hueco", "huecos", "gap", "gaps", "redondeo", "rounding", "esquina", "esquinas"],
            glifo: 0xF10AC,
            desc: "Borders, gaps and corners of Hyprland's windows.",
            vista: "ventanas",
            opciones: []
        },
        {
            grupo: "Effects",
            padre: "Display",
            claves: ["efectos", "effects", "blur", "desenfoque", "opacidad", "opacity", "sombra", "sombras", "shadow", "animacion", "animaciones", "animation"],
            glifo: 0xF00B5,
            desc: "Blur, opacity, shadows and animations.",
            vista: "efectos",
            opciones: []
        },
        {
            grupo: "Plugins",
            glifo: 0xF0431,
            desc: "What you have installed: on, off, and where it came from.",
            //  Esta sección no se pinta como una pila de interruptores: son
            //  casi cuarenta, y el ajuste de cada plugin estaba en OTRA
            //  sección. Se despliega cada uno con lo suyo dentro. La vista lo
            //  mira por este nombre; cualquier otro grupo se pinta como
            //  siempre.
            vista: "plugins",
            opciones: PluginManager.opcionesAjustes
        }
    //  Y al final, lo que aporten los plugins con K4.Ajustes. Van los
    //  últimos a propósito: lo de la barra primero, y lo instalado después,
    //  que es el orden en que la gente busca.
    ].concat(Enganches.gruposAjustes)

    //  Las alternativas de cada opción de varias respuestas.
    //
    //  Here and not in the view: each multi-choice option lists its
    //  alternatives here, so adding a choice never means touching the view.
    function opcionesDe(de) {
        if (de === "posiciones")
            return [{ codigo: "top",    nombre: "Top" },
                    { codigo: "bottom", nombre: "Bottom" }]
        //  De menos a más, que es como se lee una escala: quitar sitio
        //  siempre, quitarlo salvo cuando estorba, no quitarlo, y no estar.
        if (de === "reservas")
            return [{ codigo: "reserve", nombre: "Reserve space" },
                    { codigo: "auto",    nombre: "Away when fullscreen" },
                    { codigo: "onTop",   nombre: "On top" },
                    { codigo: "hidden",  nombre: "Hidden" }]
        if (de === "alineaciones")
            return [{ codigo: 15, nombre: "Left" },
                    { codigo: 50, nombre: "Centre" },
                    { codigo: 85, nombre: "Right" }]
        return []
    }

    function alternar(id) {
        if (String(id).indexOf("plugin_") === 0) {
            PluginManager.alternarAjuste(id)
            return
        }
        //  Los de un plugin no se guardan aquí: los guarda él. Nosotros solo
        //  le decimos que el usuario ha tocado, y él contesta con el valor
        //  nuevo en su `valores` — así lo que se ve es siempre lo guardado.
        if (String(id).indexOf("ext_") === 0) {
            Enganches.alternarAjuste(id)
            return
        }
        ajustes[id] = !ajustes[id]
        guardar()
    }

    //  Una acción con red: la pantalla la arma y la confirma, y aquí se hace.
    //  Va en el servicio y no en la vista porque es donde se declara la
    //  opción — la pantalla solo sabe pintar filas.
    function ejecutar(id) {
        if (String(id).indexOf("ext_") === 0)
            Enganches.alternarAjuste(id)
    }

    function valor(id) {
        if (String(id).indexOf("plugin_") === 0)
            return PluginManager.valorAjuste(id)
        if (String(id).indexOf("ext_") === 0)
            return Enganches.valorAjuste(id)
        return ajustes[id]
    }

    // ── persistencia ──────────────────────────────────────────────
    //
    //  Las claves, en una lista. Antes eran una línea por clave al guardar y otra
    //  al cargar, y con quince preferencias eso son treinta sitios donde
    //  olvidarse de una. Y una lista y no un recorrido del objeto entero porque
    //  un singleton tiene decenas de propiedades internas que no son ajustes.
    readonly property var claves: [
        "barPosition", "barAlignment", "islandSpace", "cerrarConClicFuera",
        "trayInPill", "notificationsOnHover", "notificationsOnFocus",
        "settingsIslandWidth", "settingsIslandHeight",
        "shellFont",
        "panelWidth", "panelShowToggles", "panelTileWifi",
        "panelTileBluetooth", "panelTileSound", "panelShowMedia",
        "panelShowShortcuts", "panelShowWorkspaces", "panelShowClock",
        "panelOrder",
        "islandPlacements", "edgeZoneEnabled", "edgeZoneSize", "rimRadius",
        "quickAccess"
    ]

    function guardar() {
        if (!cargado)
            return
        const d = {}
        for (let i = 0; i < claves.length; ++i)
            d[claves[i]] = ajustes[claves[i]]
        vista.setText(JSON.stringify(d, null, 1))
    }

    property bool cargado: false

    FileView { id: vista; path: ajustes.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: ajustes.cargar()
    }

    //  One-shot migration from the Spanish-era settings file: old key
    //  names, old stored values and old plugin ids become their English
    //  equivalents on load, so nobody loses their bar by updating.
    readonly property var clavesViejas: ({
        posicionBarra: "barPosition",
        alineacionBarra: "barAlignment",
        reservaIsla: "islandSpace",
        bandejaEnPildora: "trayInPill",
        notificacionesAlPasar: "notificationsOnHover",
        notificacionesAlEnfocar: "notificationsOnFocus",
        accesosDirectos: "quickAccess"
    })
    readonly property var valoresViejos: ({
        barPosition: { "arriba": "top", "abajo": "bottom" },
        islandSpace: { "reserva": "reserve", "completa": "auto",
                       "encima": "onTop", "escondida": "hidden" }
    })
    readonly property var idsViejos: ({
        sonido: "sound", pantallas: "displays", agentes: "agents"
    })

    function cargar() {
        const bruto = vista.text()

        if (bruto.length > 0) {
            try {
                let s = JSON.parse(bruto)
                for (const vieja in clavesViejas)
                    if (s[vieja] !== undefined && s[clavesViejas[vieja]] === undefined)
                        s[clavesViejas[vieja]] = s[vieja]
                for (const clave in valoresViejos)
                    if (typeof s[clave] === "string"
                        && valoresViejos[clave][s[clave]] !== undefined)
                        s[clave] = valoresViejos[clave][s[clave]]
                if (Array.isArray(s.quickAccess))
                    s.quickAccess = s.quickAccess.map(function (id) {
                        return idsViejos[id] !== undefined ? idsViejos[id] : id
                    })
                for (let i = 0; i < claves.length; ++i)
                    if (s[claves[i]] !== undefined)
                        ajustes[claves[i]] = s[claves[i]]
            } catch (e) {
                // preferencias ilegibles: se quedan las de fábrica
            }
        }

        cargado = true
    }
}
