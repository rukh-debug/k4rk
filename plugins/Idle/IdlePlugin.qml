//  Folded pill: cover · workspaces · time · visualizer, plus the
//  tray icons if there are any.
//  Always active at priority 0, so it is the wardrobe back: it shows
//  when no other module wants the island.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "idle"
    title: "Pill"
    priority: 0
    active: habilitado

    // the tray module, which opens when its icons are clicked; the
    // host injects it
    property var tray: null

    // how many icons fit before the pill runs wild; the rest summarize
    readonly property int trayShown: Math.min(Tray.count, 4)
    readonly property int trayWidth: Tray.count === 0 || !Settings.trayInPill
        ? 0 : trayShown * 18 + (Tray.count > trayShown ? 18 : 0) + 6

    // Each flank takes its own and the time stays still thanks to the
    // anchor published below, not by reserving the same on both
    // sides. Symmetry made every indicator pixel cost two, and with
    // two or three agents the island went so wide it stopped
    // resembling an island.
    // The cover and the bars travel together on the left, so the
    // bars' slot is reserved there and not across.
    //  Flank extensions (K4.Capsule → services/Extensions.qml):
    //  what the capsule gains on each side while a plugin has
    //  something to say there. The pill only makes room on the
    //  flank in question — the anchoring that keeps the body still
    //  is done by the host with these same numbers.
    readonly property int ladoIzq: (Media.isPlaying ? 53 : 0)
        + Extensions.leftWidth
    // The same for the capsules of what you left half-done: each can
    // reach 116 px with its icon and its clipped detail.
    readonly property int minimizadosWidth: Modulos.count * 116

    readonly property int ladoDer: trayWidth
        + minimizadosWidth + Indicadores.anchoAproximado
        + Extensions.rightWidth

    //  Each row's REAL measurement, published by the view. The sums
    //  above stay as a starting point and safety net: the moment the
    //  view exists, what was measured rules — and adding a new
    //  indicator stops requiring remembering to add its slot here,
    //  which is how the time got stepped on twice.
    //
    //  Now the left flank too: with the island growing toward one
    //  side only, whatever the cover measures runs the left edge,
    //  and an eyeball count there shows as much as one on the
    //  right.
    property int ladoDerMedido: 0
    property int ladoIzqMedido: 0

    readonly property int derAncho: ladoDerMedido > 0 ? ladoDerMedido : ladoDer
    readonly property int izqAncho: ladoIzqMedido > 0 ? ladoIzqMedido : ladoIzq

    //  The centre is the clock's 46 — and while the desks parade, as
    //  wide as the row they wear: the view hands the number over on
    //  every show and takes it back on every hide, so the pill lends
    //  the parade its room for the moment instead of reserving it all
    //  day. (A fixed reservation for ten desks was the old disease:
    //  the centre ate half the bar to honor a flash.)
    property int centroAncho: 46

    //  The four 11 px gaps separating the three zones from each
    //  other and from the edges. The view lays out with these same
    //  numbers, so if they change, they change in both places at
    //  once or the count stops adding up.
    readonly property int holgura: 44

    //  Each flank takes its own and nothing more, instead of both
    //  reserving the wider one's. That made every indicator pixel
    //  cost two and with three agents the island took half the
    //  screen, half of it empty.
    //
    //  The price is the time shifting a little when an indicator
    //  appears or leaves: the island is centered, so it grows half
    //  on each side. Pinning it with an anchor was tried and comes
    //  out worse than what it fixes —the island stops opening
    //  evenly toward both sides, which is what one looks at every
    //  time the mouse passes—. This used to be paid with double the
    //  width ALWAYS, so it would not show in a case that happens
    //  now and then.
    islandWidth: izqAncho + holgura + centroAncho + derAncho
    islandHeight: Theme.baseHeight

    view: Component {
        IdleView { plugin: self; tray: self.tray; shown: self.trayShown }
    }
}
