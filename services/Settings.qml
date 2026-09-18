pragma Singleton

//  Bar preferences.
//
//  Only settings that actually change something live here: a disconnected
//  switch is worse than no switch. Each option identifies its reader so
//  refactoring cannot leave it orphaned.
//
//  ── the ownership rule ──────────────────────────────────────────
//  This is the HOST's registry, and it keeps the knobs that are
//  cross-cutting — read by more than one plugin, or previewed by
//  Settings' own mock pages (panelShowMedia is Panel's AND the preview's;
//  the workspace style is Panel's, Idle's and the preview's). A knob
//  only one plugin reads belongs to that plugin, through `K4.Ajustes` —
//  as Agents, Player, Submap and Terminal already do. Whole pages
//  belong to the plugin that does the work, through `K4.Pagina`. When in
//  doubt: two readers, this file; one reader, its plugin.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: ajustes

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/ajustes.json"

    // ── bar ───────────────────────────────────────────────────────
    //  The edge the bar lives on. shell.qml anchors the window, flips the
    //  silhouette and orients gestures with this; plugins read it through
    //  K4.Isla.posicion to adapt anything they draw outside.
    property string barPosition: "top"        // top · bottom
    //  Where the island is centered along the edge, as a percentage of the
    //  available width: 50 is the usual center. A plugin can move it
    //  TEMPORARILY with K4.Isla.colocar; this is the base it returns to.
    property int barAlignment: 50            // 0 · 15 · 50 · 85 · 100
    //  How the bar uses desktop space.
    //
    //  Reserve is the usual behavior: the folded strip is taken from the
    //  desktop, and no window goes beneath it. On top takes no space — the
    //  pill floats over windows — and hidden also withdraws it over the edge
    //  until there is something to show. Fullscreen auto-hide is a rule, not
    //  a fourth state: reserve as usual, but hide ONLY while a window fills
    //  the screen. shell.qml implements these choices.
    property string islandSpace: "reserve"    // reserve · auto · onTop · hidden
    //  Where the summoned views — control centre, settings, launcher… —
    //  open: deployed from the island, one at a time. shell.qml reads
    //  each view's placement for the island deployment.
    // widgets/TrayRow.qml: tray icons in the pill.
    // Off by default: tray icons in the pill are usually noise, and hovering
    // already opens the island where they are visible — and clickable,
    // unlike in the pill.
    // Kept for one-time migration into pillHiddenItems; new code reads
    // pillItemEnabled("tray") instead.
    property bool trayInPill: false
    // widgets/NotifStrip.qml: recent notifications on hover.
    property bool notificationsOnHover: true
    // services/Notifs.qml: dismiss an app's notifications when switching to it.
    property bool notificationsOnFocus: true
    // Native player peek preference. Migrated once from the old per-plugin
    // player estado.json; afterwards this is the single owner.
    property bool playerPeekOnChange: true

    // ── the at-rest pill ──────────────────────────────────────
    // The folded pill is one ordered row of coherent native blocks. The
    // preference says whether a block may appear; runtime data says whether
    // it currently has anything to show. Capsule extensions keep their own
    // declared left/right flank outside this order.
    property var pillOrder: ["media", "clock-workspaces", "minimized",
                             "plugin-indicators", "tray"]
    property var pillHiddenItems: ["tray"]
    // How many items each pill block shows before summarizing the rest as
    // "+N". Zero shows everything: no "+N" by default. Set a number to cap it.
    property int pillTrayMax: 0
    property int pillMinimizedMax: 0
    property int pillIndicatorsMax: 0

    readonly property var pillItemIds: ["media", "clock-workspaces",
        "minimized", "plugin-indicators", "tray"]

    // pillOrder made honest: unknown ids dropped, forgotten ids appended.
    // Disabled items stay in the saved order so re-enabling restores place.
    readonly property var pillEffectiveOrder: {
        const guardados = pillOrder || []
        const fuera = []
        for (let i = 0; i < guardados.length; ++i) {
            if (typeof guardados[i] === "string"
                    && pillItemIds.indexOf(guardados[i]) >= 0
                    && fuera.indexOf(guardados[i]) < 0)
                fuera.push(guardados[i])
        }
        for (let j = 0; j < pillItemIds.length; ++j) {
            if (fuera.indexOf(pillItemIds[j]) < 0)
                fuera.push(pillItemIds[j])
        }
        return fuera
    }

    function pillItemEnabled(id) {
        const ocultos = pillHiddenItems || []
        // Legacy switch still wins until migration runs once.
        if (id === "tray" && !pillMigrated && !trayInPill)
            return false
        return ocultos.indexOf(id) < 0
    }

    function setPillItemEnabled(id, enabled) {
        if (pillItemIds.indexOf(id) < 0)
            return
        const ocultos = (pillHiddenItems || []).slice()
        const at = ocultos.indexOf(id)
        if (enabled && at >= 0)
            ocultos.splice(at, 1)
        else if (!enabled && at < 0)
            ocultos.push(id)
        pillHiddenItems = ocultos
        guardar()
    }

    function movePillItem(id, delta) {
        const lista = pillEffectiveOrder.slice()
        const de = lista.indexOf(id)
        const a = de + delta
        if (de < 0 || a < 0 || a >= lista.length)
            return
        lista.splice(de, 1)
        lista.splice(a, 0, id)
        const missing = (pillOrder || []).filter(function (saved) {
            return lista.indexOf(saved) < 0
        })
        pillOrder = lista.concat(missing)
        guardar()
    }

    // One-shot migration marker: true once trayInPill has been folded into
    // pillHiddenItems. Persisted so the fold runs exactly once.
    property bool pillMigrated: false

    //  ── the Settings island ────────────────────
    //  plugins/Settings/SettingsPlugin.qml sizes its island with these. They
    //  are here —and not constants there— because the Island page lets the
    //  user set them, and a value nobody can read back is a setting that lies.
    //  The plugin clamps to the same bounds the steppers use, so a hand-edited
    //  file cannot open a window bigger than the screen or smaller than the
    //  sidebar.
    property int settingsIslandWidth: 940    // 720–1400, steps of 20
    property int settingsIslandHeight: 620    // 420–900, steps of 20

    //  The native wallpaper palette tints the bar's neutral scaffold; the
    //  wallpaper page turns it off and on.
    property bool wallpaperPalette: true

    //  ── the control centre ──────────────────
    //  The native control centre dresses itself with these. The WIDTH is a number you
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
    //  How the workspaces are told apart, in the centre's header and in the
    //  pill's flash when you switch: a dot per desk, or each desk's number.
    property string panelWorkspaceStyle: "dots"    // dots · numbers
    //  The scratchpad (Hyprland's `special:` desk) among the desks, in
    //  the header and in the pill's flash. Two readers — same switch.
    property bool panelShowScratchpad: true
    property bool panelShowClock: true
    //  Block ids top to bottom: "toggles", "media", "shortcuts", plus
    //  every registered card as "<plugin>.<name>".
    property var panelOrder: ["toggles", "media", "shortcuts"]

    //  Cards the user has hidden with the editor's eye — Settings owns
    //  a card's visibility, the plugin does not (the native blocks'
    //  own switches are the same deal, each in its own key).
    property var panelHiddenBlocks: []

    //  The universe of block ids the centre obeys: the native three
    //  plus whatever the registry holds. One source — the two copies
    //  of the hardcoded list were the old disease (an id accepted by
    //  one branch and dropped by the other).
    readonly property var idsBloques: {
        const todos = ["toggles", "media", "shortcuts"]
        const cards = Enganches.idsCards
        for (let i = 0; i < cards.length; ++i)
            if (todos.indexOf(cards[i]) < 0)
                todos.push(cards[i])
        return todos
    }

    //  panelOrder made honest, for the two readers (the centre and its
    //  editor): unknown ids dropped, forgotten ids appended at the end.
    //  An order is a list the user rewrites; this is the list the bar obeys.
    readonly property var panelOrdenEfectivo: {
        const guardados = panelOrder || []
        const fuera = []
        for (let i = 0; i < guardados.length; ++i)
            if (typeof guardados[i] === "string"
                && idsBloques.indexOf(guardados[i]) >= 0
                && fuera.indexOf(guardados[i]) < 0)
                fuera.push(guardados[i])
        const todos = idsBloques
        for (let i = 0; i < todos.length; ++i)
            if (fuera.indexOf(todos[i]) < 0)
                fuera.push(todos[i])
        return fuera
    }

    //  Whether a centre block is on show, by id — THE rule, read by the
    //  centre (its Loader), its height count and its editor's sketch.
    //  A block is on when its switch says so AND it has something to
    //  show: the toggles with every tile off are a row of nothing. A
    //  card ("<plugin>.<name>", the dot gives it away) is on unless
    //  the user hid it with the eye.
    function bloqueVisible(id) {
        if (id === "toggles")
            return panelShowToggles
                   && (panelTileWifi || panelTileBluetooth
                       || panelTileSound)
        if (id === "media")
            return panelShowMedia
        if (id === "shortcuts")
            return panelShowShortcuts
        if (String(id).indexOf(".") > 0) {
            const ocultos = panelHiddenBlocks || []
            return ocultos.indexOf(id) < 0
        }
        return false
    }

    //  ── where each view opens ────────────
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
    //  the bar's if it does not. Always a { side, align } with side
    //  one of top/bottom/left/right and align 0–100 — a map hand-edited
    //  into the file cannot smuggle anything stranger in.
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
    //
    //  Two doors: `ponerPlacementMemoria` moves the dot without touching
    //  the disk — the drag calls it on every move, and a drag is dozens of
    //  moves — and `ponerPlacement` is the same write plus the save. The
    //  drag saves once, on release.
    function ponerPlacementMemoria(id, side, align) {
        const d = Object.assign({}, islandPlacements || {})
        if (side === "") {
            delete d[id]
        } else {
            d[id] = { side: side, align: align }
        }
        islandPlacements = d
    }

    function ponerPlacement(id, side, align) {
        ponerPlacementMemoria(id, side, align)
        guardar()
    }

    //  ── the strip that brings it back ────────
    //  While the bar is away (hidden mode, retired), thin strips on the
    //  other three edges summon it back — the path TO it when it is not
    //  there. Off means reaching for the bar's own edge only, as before.
    property bool edgeZoneEnabled: true
    //  How many pixels of border, per edge. One is the thinnest
    //  promise the screen edge can make; every pixel above it is a
    //  pixel of desktop clicks the strip keeps. But the rim is also
    //  the FRAME the corner popups pour into — a fat rim (10–14) is
    //  what makes their fillets read as fused instead of bumpy, so
    //  the ceiling leaves room for a frame with real mass.
    property int edgeZoneSize: 1                // 1–16, steps of 1
    //  How rounded the rim's INSIDE corners are — where one border turns
    //  into the next. Six is quiet company for a 1 px rim; twenty-four is
    //  a bold arc. Zero is square, and the rim stays a frame.
    property int rimRadius: 6                   // 0–24, steps of 1

    //  ── the shell's typeface ─────────────
    //  The shell's typeface, as a family name. Empty is the shell's own
    //  default and not a state to repair: the row list shows it as
    //  «Shell default» and picking it again is picking nothing.
    //
    //  The value travels TO `Theme` (which stays the import-free base of
    //  the graph): every label that says `Theme.uiFont` follows along, and
    //  the whole bar re-letters itself the moment you pick one.
    property string shellFont: ""
    onShellFontChanged: Theme.chosenFont = shellFont

    // ── shortcuts ─────────────────────────────────────────────────
    //  Which applications appear in the control center strip, by plugin
    //  ID. core/PanelIslandView.qml draws it, and the application center
    //  edits it through each card's pin.
    //
    //  IDs rather than copies of names and icons: renaming a plugin or
    //  changing its icon updates the shortcut automatically, and one
    //  pointing to an uninstalled plugin simply is not drawn.
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

    // Change the value of an option that is not a switch.
    function poner(id, valor) {
        if (String(id).indexOf("ext_") === 0) {
            Enganches.ponerAjuste(id, valor)
            return
        }
        ajustes[id] = valor
        guardar()
    }

    readonly property var definicion: [
        {
            grupo: "Island",
            claves: ["pill", "at rest", "clock", "media", "workspace",
                     "minimized", "indicator", "tray", "order", "visibility",
                     "peek", "track"],
            glifo: 0xF1513,
            desc: "How much room the bar keeps, and when it gets out of the way.",
            //  Position, alignment and space usage are hard to explain in
            //  words: Reserve space and On top sound similar but do very
            //  different things to windows. A sketch above the options
            //  demonstrates them.
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
                { id: "edgeZoneSize", tipo: "numero", min: 1, max: 16,
                  paso: 1, unidad: "px",
                  requiere: "edgeZoneEnabled",
                  nombre: "Rim thickness",
                  desc: "Pixels of island colour along the borders — the frame the corner popups fuse into; each one also keeps its clicks",
                  glifo: 0xF00D0 },   // md-border_style
                { id: "rimRadius", tipo: "numero", min: 0, max: 24,
                  paso: 1, unidad: "px",
                  requiere: "edgeZoneEnabled",
                  nombre: "Rim corner radius",
                  desc: "How round the rim turns at the screen's corners",
                  glifo: 0xF0607 },   // md-rounded_corner
                { tipo: "titulo", nombre: "The pill" },
                { id: "pillTrayMax", tipo: "numero", min: 0, max: 32,
                  paso: 1, unidad: "items",
                  nombre: "Tray icons limit",
                  desc: "How many tray icons the pill shows before summarizing the rest as +N. 0 shows all.",
                  glifo: 0xF0FB0 },
                { id: "pillMinimizedMax", tipo: "numero", min: 0, max: 32,
                  paso: 1, unidad: "items",
                  nombre: "Minimized items limit",
                  desc: "How many minimized items the pill shows before summarizing the rest as +N. 0 shows all.",
                  glifo: 0xF0047 },
                { id: "pillIndicatorsMax", tipo: "numero", min: 0, max: 32,
                  paso: 1, unidad: "items",
                  nombre: "Plugin indicators limit",
                  desc: "How many plugin indicators the pill shows before summarizing the rest as +N. 0 shows all.",
                  glifo: 0xF0431 },
                { tipo: "titulo", nombre: "Automatic views" },
                { id: "playerPeekOnChange", nombre: "Peek when the track changes",
                  desc: "A few seconds with the new track, then it leaves on its own",
                  glifo: 0xF075A },
                { tipo: "titulo", nombre: "Notifications" },
                { id: "notificationsOnHover", nombre: "Notifications on hover",
                  desc: "Recent ones, under the clock and player", glifo: 0xF009A },
                { id: "notificationsOnFocus", nombre: "Dismiss when you switch to the app",
                  desc: "Switching to its window already counts as having attended to them", glifo: 0xF039F },
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
            //  One card per openable view: wrapping side controls with
            //  Follow bar first, plus a draggable monitor that previews the
            //  actual edge or corner attachment.
            vista: "placement",
            opciones: []
        },
        {
            grupo: "Control Centre",
            claves: ["panel", "centro de control", "control center",
                     "control centre", "toggles", "media", "shortcuts",
                     "accesos", "widgets", "workspace", "workspaces",
                     "dots", "numbers", "scratchpad", "special"],
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
                { id: "panelShowWorkspaces", nombre: "Workspace indicator",
                  desc: "In the centre's header",
                  glifo: 0xF15FC },   // md-dots_grid
                { id: "panelWorkspaceStyle", tipo: "eleccion",
                  de: "workspaceStyles",
                  requiere: "panelShowWorkspaces",
                  nombre: "Workspace style",
                  desc: "A dot per desk, or its number",
                  glifo: 0xF15FC },   // md-dots_grid
                { id: "panelShowScratchpad", requiere: "panelShowWorkspaces",
                  nombre: "Scratchpad desk",
                  desc: "The special workspace among the desks",
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
            //  the wallpaper at a glance and a card per child.
            vista: "display",
            opciones: []
        },
        {
            grupo: "Monitor",
            padre: "Display",
            claves: ["monitor", "resolution", "refresh rate", "scale", "rotation",
                     "orientation", "display", "arrangement", "mirror", "output"],
            glifo: 0xF0379,
            desc: "Arrange monitors, choose modes and safely save your layout.",
            vista: "monitor",
            opciones: []
        },
        {
            grupo: "Wallpaper",
            //  A child of Display (`padre`): it renders as a sub-tab under it
            //  in the sidebar, one level deep.
            padre: "Display",
            claves: ["fondo", "fondos", "wallpaper", "escritorio",
                     "imagen", "video", "pantalla", "palette", "monochrome",
                     "scheme", "accent"],
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
            grupo: "Plugins",
            glifo: 0xF0431,
            desc: "What you have installed: on, off, and where it came from.",
            //  This section is not drawn as a pile of switches: there are
            //  almost forty, and each plugin's settings used to be in ANOTHER
            //  section. Each now expands with its settings inside. The view
            //  recognizes this name; every other group is drawn as usual.
            vista: "plugins",
            opciones: PluginManager.opcionesAjustes
        }
    //  And at the end, what the plugins contribute. Option rows
    //  (`K4.Ajustes`) and whole pages (`K4.Pagina`) both go after the
    //  bar's own, which is the order people look in. The Display family's
    //  working pages — colour, windows, effects — live with the theme
    //  plugin now: they are here because IT says so, not because this
    //  file lists them.
    ].concat(Enganches.gruposAjustes).concat(Enganches.gruposPaginas)

    //  The alternatives for each multi-choice option.
    //
    //  Here and not in the view: each multi-choice option lists its
    //  alternatives here, so adding a choice never means touching the view.
    function opcionesDe(de) {
        if (de === "posiciones")
            return [{ codigo: "top",    nombre: "Top" },
                    { codigo: "bottom", nombre: "Bottom" }]
        //  In scale order: always take space, take it unless it gets in
        //  the way, take none, and be absent.
        if (de === "reservas")
            return [{ codigo: "reserve", nombre: "Reserve space" },
                    { codigo: "auto",    nombre: "Away when fullscreen" },
                    { codigo: "onTop",   nombre: "On top" },
                    { codigo: "hidden",  nombre: "Hidden" }]
        if (de === "alineaciones")
            //  The ends are corners, not "very left": 0 and 100 sit
            //  FLUSH against the side wall, so the bar attaches to
            //  two sides of the screen — its edge and the wall — and
            //  the rim carries the material into the turn. A gap you
            //  can see is 15 and 85; a corner is a corner.
            return [{ codigo: 0,   nombre: "Left corner" },
                    { codigo: 15,  nombre: "Left" },
                    { codigo: 50,  nombre: "Centre" },
                    { codigo: 85,  nombre: "Right" },
                    { codigo: 100, nombre: "Right corner" }]
        if (de === "workspaceStyles")
            return [{ codigo: "dots",    nombre: "Dots" },
                    { codigo: "numbers", nombre: "Numbers" }]
        return []
    }

    function alternar(id) {
        if (String(id).indexOf("plugin_") === 0) {
            PluginManager.alternarAjuste(id)
            return
        }
        //  A plugin saves its own settings. We only tell it the user acted;
        //  it replies with the new value in valores, so what is shown is
        //  always what was saved.
        if (String(id).indexOf("ext_") === 0) {
            Enganches.alternarAjuste(id)
            return
        }
        ajustes[id] = !ajustes[id]
        guardar()
    }

    //  A guarded action: the screen arms and confirms it, and this executes it.
    //  It belongs in the service where the option is declared, rather than
    //  in the view, which only knows how to draw rows.
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

    // ── persistence ───────────────────────────────────────────────
    //
    //  Keys live in one list. There used to be one line per key for saving
    //  and another for loading: fifteen preferences meant thirty places to
    //  forget one. Use a list rather than walking the entire object because
    //  a singleton has dozens of internal properties that are not settings.
    readonly property var claves: [
        "barPosition", "barAlignment", "islandSpace",
        "trayInPill", "notificationsOnHover", "notificationsOnFocus",
        "playerPeekOnChange",
        "pillOrder", "pillHiddenItems", "pillMigrated",
        "pillTrayMax", "pillMinimizedMax", "pillIndicatorsMax",
        "settingsIslandWidth", "settingsIslandHeight",
        "shellFont", "wallpaperPalette",
        "panelWidth", "panelShowToggles", "panelTileWifi",
        "panelTileBluetooth", "panelTileSound", "panelShowMedia",
        "panelShowShortcuts", "panelShowWorkspaces", "panelWorkspaceStyle",
        "panelShowClock", "panelShowScratchpad",
        "panelOrder", "panelHiddenBlocks",
        "islandPlacements",
        "edgeZoneEnabled", "edgeZoneSize", "rimRadius",
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
        sonido: "sound", agentes: "agents"
    })

    function migrarPildora() {
        if (pillMigrated)
            return
        // Fold the legacy tray switch into the new hidden-items list once.
        // An explicit new-model value wins; otherwise the old switch decides.
        const ocultos = (pillHiddenItems || []).slice()
        const at = ocultos.indexOf("tray")
        if (trayInPill && at >= 0)
            ocultos.splice(at, 1)
        else if (!trayInPill && at < 0)
            ocultos.push("tray")
        pillHiddenItems = ocultos
        pillMigrated = true
        guardar()
    }

    function migrarPlayerPeek() {
        // The host setting wins when already present. Otherwise read the
        // legacy per-plugin file; the migrated value is then persisted.
        if (_peekDesdeHost)
            return
        lectorPlayerPeek.cargar()
        guardar()
    }

    property var lectorPlayerPeek: FileView {
        path: (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins/player/estado.json"
        blockLoading: true
        function cargar() {
            if (ajustes.playerPeekOnChange !== undefined && ajustes._peekDesdeHost)
                return
            try {
                const bruto = text()
                if (!bruto || bruto.length === 0)
                    return
                const d = JSON.parse(bruto)
                if (!ajustes._peekDesdeHost) {
                    if (d && d.peekOnChange !== undefined)
                        ajustes.playerPeekOnChange = d.peekOnChange === true
                    else if (d && d.asomarAlCambiar !== undefined)
                        ajustes.playerPeekOnChange = d.asomarAlCambiar === true
                }
            } catch (e) {
            }
        }
    }
    // Tracks whether playerPeekOnChange came from ajustes.json this boot,
    // so the legacy file cannot overwrite an explicit host value.
    property bool _peekDesdeHost: false

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
                if (s.playerPeekOnChange !== undefined)
                    _peekDesdeHost = true
                for (let i = 0; i < claves.length; ++i)
                    if (s[claves[i]] !== undefined)
                        ajustes[claves[i]] = s[claves[i]]
                //  Retired keys are simply not copied: an old file's
                //  `popupMode` and `openOnHoverEnabled` stay on the disk
                //  it came from and never reach memory. The hover flag
                //  travels INSIDE `islandPlacements`, so it needs its
                //  own sweep: entries are rewritten as { side, align }.
                if (s.islandPlacements !== undefined
                        && s.islandPlacements !== null
                        && typeof s.islandPlacements === "object") {
                    const limpio = {}
                    for (const id in s.islandPlacements) {
                        const p = s.islandPlacements[id]
                        if (p && (p.side === "top" || p.side === "bottom"
                                  || p.side === "left"
                                  || p.side === "right")) {
                            let a = Number(p.align)
                            if (!isFinite(a))
                                a = 50
                            limpio[id] = {
                                side: p.side,
                                align: Math.max(0, Math.min(100, a))
                            }
                        }
                    }
                    ajustes.islandPlacements = limpio
                }
            } catch (e) {
                // Unreadable preferences: keep the defaults.
            }
        }

        cargado = true
        migrarPildora()
        migrarPlayerPeek()
    }
}
