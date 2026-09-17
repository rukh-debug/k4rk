pragma Singleton

//  The system tray, owned by the host instead of a plugin.
//
//  The tray list and the StatusNotifier host registration live in the Tray
//  service; this is the summoned surface's state: whether it is open, which
//  application is selected, and the DBus menu subscription behind the
//  right-hand pane.
//
//  It used to be plugins/Tray/. A tray that can be disabled is a tray
//  whose icons (still painted by widgets/TrayRow.qml in the pill, the
//  clock and the player) open nothing when right-clicked, and a tray
//  whose surface competes in the plugin catalog is a category error:
//  it is bar chrome, not an extension. So the state lives here, always
//  on, and shell.qml arbitrates it next to the plugin instances.
//
//  Contract: this object quacks like a K4.Plugin surface. shell.qml reads
//  name/title/priority/habilitado/active/viewLoaded/colocable/transitorio,
//  islandWidth/islandHeight/view/summonCommand, the focus flags, the
//  hover-exit pair, handlesBackgroundTap/backgroundTapped and close().
//  Anything the host learns to read off a surface must be added here too,
//  or the tray silently drops out of that behavior. `nativo` marks the
//  object for the two places that must tell it apart from real plugins
//  (view-load error reporting, which has no catalog row to hang onto).

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: isla

    // ── what the host reads ──────────────────────────────────────
    readonly property string name: "tray"
    readonly property string title: "Tray"
    readonly property int priority: 63
    readonly property bool habilitado: true
    readonly property bool nativo: true

    property bool open: false
    readonly property bool active: open

    property bool viewLoaded: true
    readonly property bool colocable: true
    readonly property string summonCommand: "k4.tray toggle"
    readonly property bool transitorio: false

    readonly property int islandWidth: 640
    readonly property int islandHeight: 360

    property bool handlesBackgroundTap: true
    signal backgroundTapped()
    //  Swallows the click: closing is the button's and the catcher's job.
    onBackgroundTapped: {}

    property bool closeOnClickOutside: true

    //  The whole keyboard while open: «optional» is OnDemand and the
    //  compositor only gives it if you CLICK the surface, so opened
    //  from the application centre or by shortcut not even ESC
    //  arrived. See `tecladoOpcional` in api/K4/Plugin.qml.
    property bool grabKeyboard: open
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false

    property bool closeOnHoverExit: true
    property int hoverExitDelay: 900
    signal hoverTimedOut()
    //  Dying mid-fetch is what made reopening feel slow: the view was
    //  destroyed while the menu was still on the wire, so the next
    //  open paid the round trip again. While a menu is loading the
    //  close waits a beat instead; the timer below finishes the job
    //  if the pointer is still gone.
    onHoverTimedOut: {
        if (isla.menuLoading)
            esperaCierre.restart()
        else
            isla.close()
    }

    Timer {
        id: esperaCierre
        interval: 1500
        onTriggered: {
            if (!Island.hovered)
                isla.close()
        }
    }

    //  Never declared by anyone: read through `typeof x === "number"`
    //  guards (shell.qml's exclusiveZone) or skipped when undefined
    //  (the apartada sweep). Said once so a typo does not invent it.
    property var barraApartada
    property var reservaBarra

    property Component view: Component {
        TrayIslandView {}
    }

    // ── open state ───────────────────────────────────────────────
    property var selected: null

    function toggle() {
        open = !open
        if (open) {
            if (selected === null || Tray.sorted.indexOf(selected) === -1)
                selected = Tray.count > 0 ? Tray.sorted[0] : null
            //  The subscription survives the island being closed, so a
            //  reopen usually paints at once; only fetch when the shown
            //  entries are not this application's.
            if (selected !== null && modeloDe !== selected)
                pedir(selected)
        }
    }

    function close() { open = false }

    function select(item) {
        if (selected === item)
            return
        selected = item
        if (item !== null)
            pedir(item)
    }

    //  If the selected application disappears (closes), do not leave
    //  a dead reference hanging.
    Connections {
        target: Tray.items
        function onValuesChanged() {
            if (isla.selected !== null
                    && Tray.sorted.indexOf(isla.selected) === -1)
                isla.select(Tray.count > 0 ? Tray.sorted[0] : null)
        }
    }

    // ── the menu, fetched once and kept warm ─────────────────────
    //
    //  Two openers trading the subscription, not one rebound: a single
    //  QsMenuOpener clears its children the moment `menu` is repointed,
    //  so every click used to flash "Loading menu…" before the new
    //  entries arrived over DBus. Here the live opener keeps painting
    //  while the idle one fetches the next menu in the background, and
    //  the view flips only when there is something to show. The last
    //  menu stays subscribed while the island is closed, so reopening
    //  is paint, not a round trip — the open lag is gone by
    //  construction, not by caching anything by hand.

    QsMenuOpener {
        id: abridorA
    }

    QsMenuOpener {
        id: abridorB
    }

    //  Whose children the view paints. A stable object identity, never
    //  a copied array: the ListView keeps its delegates and the model
    //  updates incrementally instead of resetting on every DBus batch.
    property var modeloMenu: abridorA.children
    //  Which application those entries belong to. Stale entries are
    //  only shown while THEIR application is still selected (a
    //  revalidation); otherwise the view shows the loading state, so
    //  one application's menu never flashes under another's header.
    property var modeloDe: null

    property bool menuLoading: false

    //  The opener currently fetching (or null when idle). Late DBus
    //  replies belong to whatever `menu` the opener holds NOW, so a
    //  reply is only published when the opener still serves the
    //  current selection — rapid clicks cannot land a wrong menu.
    property var abridorFondo: null

    function pedir(item) {
        const menu = (item && item.hasMenu) ? item.menu : null
        if (!menu) {
            abridorFondo = null
            menuLoading = false
            esperaRespuesta.stop()
            return
        }
        const fondo = (modeloMenu === abridorA.children) ? abridorB : abridorA
        abridorFondo = fondo
        fondo.menu = menu
        menuLoading = true
        esperaRespuesta.restart()
    }

    function recargarMenu() {
        if (selected !== null)
            pedir(selected)
    }

    function publicarSiSirve(abridor) {
        if (abridor !== abridorFondo)
            return
        const menu = (selected && selected.hasMenu) ? selected.menu : null
        if (!menu || abridor.menu !== menu)
            return
        if (abridor.children.values.length === 0)
            return
        modeloMenu = abridor.children
        modeloDe = selected
        abridorFondo = null
        menuLoading = false
        esperaRespuesta.stop()
    }

    Connections {
        target: abridorA.children
        function onValuesChanged() { isla.publicarSiSirve(abridorA) }
    }

    Connections {
        target: abridorB.children
        function onValuesChanged() { isla.publicarSiSirve(abridorB) }
    }

    //  No answer is also an answer: an empty menu and a dead one both
    //  read as zero children, so after a wait the island says so and
    //  offers a retry instead of loading forever.
    Timer {
        id: esperaRespuesta
        interval: 2500
        onTriggered: {
            const fondo = isla.abridorFondo
            const menu = (isla.selected && isla.selected.hasMenu)
                ? isla.selected.menu : null
            if (fondo !== null && menu !== null && fondo.menu === menu) {
                isla.modeloMenu = fondo.children
                isla.modeloDe = isla.selected
                isla.abridorFondo = null
            }
            isla.menuLoading = false
        }
    }
}
