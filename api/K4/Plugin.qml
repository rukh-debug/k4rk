// The k4 plugin contract: when to show, the requested size, and the view.
// Processes, timers and IPC handlers live on the plugin, independently of
// whether its view is mounted in the main island or an independent window.
//
//      K4.Plugin {
//          name: "launcher"
//          priority: 60
//          habilitado: true
//          active: open
//          islandWidth: 720
//          islandHeight: 480
//          view: Component { LauncherView {} }
//
//          K4.Ipc { target: "k4.launcher"; function toggle() { ... } }
//          K4.Process { id: apply }
//      }

import QtQuick

QtObject {
    // Processes, timers and IPC handlers are direct children by default.
    default property list<QtObject> services

    // The host fills the plugin's directory on creation. Processes need a
    // filesystem path rather than the URLs used for images and QML assets.
    property string carpeta: ""

    // A plugin-owned file, with its full path:
    //
    //      command: ["python3", fichero("tools/mio.py")]
    function fichero(relativa) {
        return carpeta.length > 0 ? carpeta + "/" + relativa : relativa
    }

    required property string name

    // Human-readable module name.
    property string title: name

    // Bound by PluginManager: enabled is permission to participate;
    // active is the request to show a view right now.
    property bool habilitado: true

    // Main-island arbitration: pill 0, volume 40, clock 50, player 55,
    // toast 59, panel 60, launcher 80, openwebui 90.
    //
    //  THE HOVER BAND — offering a view while the mouse rests on the
    //  pill is not a separate API: it is this ladder plus one readable
    //  fact. `K4.Isla.raton` says whether the mouse is on the pill,
    //  and the clock takes the stage exactly like this:
    //
    //      active: habilitado && K4.Isla.raton
    //      priority: 50
    //
    //  Pick your slot by who you want to beat: 1–39 stays under the
    //  clock (you show when the clock plugin is off), 51–54 stands
    //  over the clock and under the player, 56–58 over the player
    //  too. Leaving is the binding's job — `raton` clears a moment
    //  after the mouse goes, `active` follows, the stage returns to
    //  the pill. `closeOnHoverExit` is for SUMMONED views; a hover
    //  view never needs it. See `ejemplos/hoverpeek/`.
    property int priority: 50

    // Does this plugin request a view right now?
    property bool active: false

    // Unsolicited, self-expiring content. In the main island, the host closes
    // it when another surface takes over. Independent transients keep their
    // own lifetime. Use priority 56–59 to beat resting views but yield to
    // summoned views in main-island mode.
    property bool transitorio: false

    // Requested island size while active.
    property int islandWidth: 300
    property int islandHeight: 60

    // Content, instantiated only while the host presents this plugin.
    property Component view: null

    // Release the view while retaining its size for a closing grace period.
    property bool viewLoaded: true

    //  Does this plugin's surface deserve a card in Settings → Placement?
    //
    //  Mark it true if your view is a SUMMONED surface — something the
    //  user opens that takes the island for a while: the control centre,
    //  a drawer, a terminal. Not everything that paints is that: the
    //  pill's wings, transient notices and indicators ride along rather
    //  than open, and they get no card. Only what OPENS gets placed, and
    //  the card — its edge, its point along it — is then the user's to
    //  draw. A plugin that is off has no surface, and so no card: the
    //  list is derived from the live ones.
    property bool colocable: false

    // Open independently, leaving the main island and other views intact.
    // The host tries the configured placement, then corners clockwise, then
    // the least-overlapping corner. Settings → Placement overrides this
    // default for placeable surfaces. Applies to `view`, not custom windows.
    property bool independentIsland: false

    //  The IPC call that opens this surface, as the Placement card's
    //  copy button hands it out: everything AFTER `call` —
    //  "k4.launcher toggle". Only the plugin can say this for sure:
    //  target and verb are conventions, and conventions break — the
    //  terminal lives at `k4.term` and its toggle is called `island`.
    //  The prefix (`quickshell ipc -p … call`) is the host's business,
    //  added at copy time, because only the running instance knows the
    //  path. Empty (the default) hides the button: a surface nothing
    //  can open from outside should not offer a command.
    property string summonCommand: ""

    // Exclusive keyboard focus: while active, no window receives a
    // key. Only for what is truly typed into — the launcher, the AI
    // chat, the Wi-Fi password — because it blocks the rest of the
    // desktop.
    property bool grabKeyboard: false

    // On-demand focus: the compositor grants keys after clicking the surface.
    // A view opened by shortcut does not receive Escape until it is focused.
    // Use grabKeyboard when immediate keyboard interaction is required.
    property bool tecladoOpcional: false

    // Exclusive focus while hovered, released when the pointer leaves. Use
    // for interactive views such as games, not passive announcements.
    // Layer focus alone does not focus your item: reclaim it on pointer entry
    // as well as opening, since FocoInicial's initial retries may have ended.
    //
    //     property var foco: K4.FocoInicial { objetivo: raiz }
    //     HoverHandler { onHoveredChanged: if (hovered) raiz.foco.reclamar() }
    property bool tecladoAlPasar: false

    // Open from the application centre or a shortcut. Override to always
    // open instead of toggling, or to implement another arrival action.
    function abrir() {
        if (typeof toggle === "function")
            toggle()
        else
            active = true
    }

    //  ── the optional verbs the host knows ─────────────────────────
    //
    //  Not every plugin is addressable, but the host has things to say
    //  to those that are: open a tab, land on a page, arrive with a
    //  search already written. These stubs exist so the CALLER never has
    //  to know whether you serve the verb — override the ones you do,
    //  and the contract here is the list of names worth overriding.
    //
    //      · toggle(tab) — alternate your surface; the tab, if you have
    //        tabs, is yours to name.
    //      · openTab(tab) — go to that tab, opening if closed.
    //      · abrirPagina(page) — land on that page of your surface.
    //      · buscar(query) — arrive with a search already written.
    //      · preguntar(texto) — a question asked from outside.
    //      · openAsk(selection) — arrive asking: open with your picker
    //        ready (fresh, or on the region/screenshot picker when
    //        `selection` is true).
    //      · attachScreenshot() / attachRegion() — arrive with a fresh
    //        screenshot, or with the region picker running.
    //      · refresh() — look again at whatever you show (Packages
    //        re-checks for updates; anything with a cache re-reads it).
    //      · updateAll() / updateSelected() — do the work on everything,
    //        or on the user's current selection.
    //
    //  `toggle` has a working default for plugins with no view logic of
    //  their own; the rest are no-ops until you write them.
    function toggle(tab) { active = !active }
    function openTab(tab) { }
    function abrirPagina(page) { }
    function buscar(query) { }
    function preguntar(texto) { }
    function openAsk(selection) { }
    function attachScreenshot() { }
    function attachRegion() { }
    function refresh() { }
    function updateAll() { }
    function updateSelected() { }

    property bool handlesBackgroundTap: false
    signal backgroundTapped()

    //  Click OUTSIDE the shell closes this view, same as Escape.
    //
    //  The bar's layer surface stays screen-tall. While a view is deployed,
    //  the host expands its input mask so a tap outside the island closes the
    //  view instead of reaching the desktop. The click is SPENT on closing —
    //  it does not fall through — which is the point: it is the pointer's
    //  way of pressing Escape. This flag only controls taps around the view
    //  on its own monitor. Every summoned view closes when another monitor
    //  is clicked, regardless of this flag: that behavior is always on.
    //
    //  Mark it FALSE for a view that appears without being asked (the volume
    //  HUD): nobody clicks to dismiss something they did not open, and
    //  swallowing a click that was going somewhere else is worse than
    //  staying open a second longer. Truly transient views (`transitorio`)
    //  are already excluded by the host; this flag is for the rest.
    property bool closeOnClickOutside: true

    // Notify the plugin after the pointer leaves for hoverExitDelay. The
    // plugin decides whether to close. Armed only on departure, so a view
    // opened by shortcut stays open until the pointer has visited it.
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 700
    signal hoverTimedOut()
}
