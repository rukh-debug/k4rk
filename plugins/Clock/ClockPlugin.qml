//  Hover with no music: date and time. It shares its trigger with the player
//  (the mouse on top) but has lower priority, so if something is playing the
//  player wins.
//
//  It also carries the clickable tray icons: in the pill they cannot be
//  touched, because bringing the mouse close has already swapped it for this
//  view.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "clock"
    title: "Clock"
    priority: 50
    active: habilitado && Island.hovered

    //  No outside-click catcher for this one. It opens by HOVER — nobody
    //  asked for it — so an outside tap is not "close what I opened": the
    //  tap belongs to whatever it was aimed at, and the view already leaves
    //  by itself when the pointer does. Same call as the volume HUD.
    //  See `closeOnClickOutside` in the plugin contract.
    closeOnClickOutside: false

    // the tray module; the host injects it
    property var tray: null

    // Same layout criteria as the pill, and now the same shape too: each zone
    // takes up ITS OWN space and chains with the next, instead of both flanks
    // reserving the width of the wider one.
    //
    //  ── why nothing is reserved on both sides anymore ──────────────
    //
    //  With the clock at the exact center of the box, `islandWidth` reserved
    //  `ladoAncho` on EACH side, so every indicator pixel cost two, and a cap
    //  was needed so the island would not eat the screen. And hitting that cap
    //  ended badly: the right-hand row was anchored to the right edge, grew
    //  inwards and ended up painted ON TOP of the clock. With two agents
    //  working it showed up almost always.
    //
    //  Chained — date, clock, indicators, each hanging from the previous one —
    //  overlap stops being possible: whatever does not fit spills out to the
    //  right and the island clips it. And since every pixel now costs one, the
    //  same island width fits almost twice as much right flank as before.
    //
    //  ── why this is MEASURED and not summed ────────────────────────
    //
    //  The tally below used to be the only source, and it did not count the
    //  chips contributed by plugins — an agent bell, a limit percentage, a
    //  long command: it summed `Modulos.count`, which is the list of
    //  minimized modules, a different thing. With a bell showing, the
    //  right-hand group grew without anyone having reserved room for it,
    //  pushed towards the center and ended up drawn ON TOP of the clock.
    //
    //  And stretching the sum with another constant fixed nothing: how much
    //  "🔔 claude · k4" takes up depends on its text and its font, so the only
    //  one who can say is whoever paints it. The view measures it and
    //  publishes it in `anchoDerecho`; it is picked up here.
    //
    //  The sum stays as a floor, not as the truth: while the island is closed
    //  there is no view to measure, and when it opens the size is decided
    //  before the view lays itself out. Without that floor the first frame
    //  would come out narrow. The larger of the two wins.
    property int anchoIzqMedido: 0
    property int anchoCentroMedido: 0
    property int anchoDerechoMedido: 0

    readonly property int ladoEstimado: (Tray.count > 0
        ? Math.min(Tray.count, 5) * 24 + 8 : 0) + 48
        + Modulos.count * 180
        + Indicadores.anchoAproximado

    //  The sums and floors stay as the STARTING point and safety net, and as
    //  soon as the view exists the measured value rules — which is what the
    //  folded pill already does. The date hovered around 96 and the clock
    //  around 92, and those numbers are good for the first frame: when the
    //  island opens, its size is decided before the view lays itself out.
    //
    //  This used to be `Math.max(suma, medido)` and the larger of the two
    //  always ruled. With anchored zones it made no difference — the surplus
    //  was split between the two flanks and went unseen — but chained it
    //  shows: the sum estimates 510 where the row measures 406, so almost a
    //  hundred pixels of empty island were left over to the right of the
    //  icons.
    readonly property int izqAncho: anchoIzqMedido > 0 ? anchoIzqMedido : 96
    readonly property int centroAncho: anchoCentroMedido > 0
        ? anchoCentroMedido : 92
    readonly property int derMedido: anchoDerechoMedido > 0
        ? anchoDerechoMedido : ladoEstimado

    //  And a ceiling for the right flank, still needed: the real one is set by
    //  each chip eliding its text, and this is the belt — even if one day
    //  someone registers twenty indicators, the island does not eat the
    //  screen. 480 and not the old 380, because before it was paid twice:
    //  with 380 on each side the island's ceiling was 896 px, and with 480 on
    //  one side only it stays at 760 and a hundred more pixels of indicators
    //  fit.
    readonly property int derAncho: Math.min(derMedido, 480)

    //  The air between zones is the same number the view distributes.
    readonly property int hueco: 24

    islandWidth: 44 + izqAncho + hueco + centroAncho + hueco + derAncho
    // grows to make room for the recent notifications
    //  68 for the clock zone, and if there are notifications, whatever the
    //  strip measures plus the 6 gap and the 12 of bottom air the view adds.
    //  Those 18 were the missing piece: without them the layout crushed the
    //  rows against the edge.
    readonly property int alturaTira: Settings.notificationsOnHover
        ? Notifs.stripHeight(3) : 0
    islandHeight: 68 + (alturaTira > 0 ? alturaTira + 18 : 0)

    view: Component {
        ClockView {
            tray: self.tray
            //  By Binding and not by assigning in an `on…Changed`: this way
            //  the value also arrives at the first layout pass, which is
            //  exactly when it is needed.
            Binding {
                target: self
                property: "anchoIzqMedido"
                value: anchoIzquierdo
            }
            Binding {
                target: self
                property: "anchoCentroMedido"
                value: anchoCentro
            }
            Binding {
                target: self
                property: "anchoDerechoMedido"
                value: anchoDerecho
            }
        }
    }
}
