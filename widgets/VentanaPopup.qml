//  A summoned view, in a drawer of its own.
//
//  One of these exists per OPEN plugin while Settings.popupMode is
//  "window": the host instantiates them from shell.qml, outside the
//  per-screen bar, and hands each the plugin. The plugin's contract
//  does not change — same view, same size, same verbs — only the room
//  it happens in changes. The island keeps the pill, the hover views
//  and the transients; everything a user SUMMONS (colocable, in the
//  contract's words) comes out here and, unlike the island, several
//  can be open at once.
//
//  A window does not float in the middle of anything: it comes OUT of
//  the frame, on the edge and at the point its placement in Settings
//  says — the same placement the island would deploy it at, resolved
//  the same way, so a view lives where its user put it in BOTH modes.
//  The corners on the edge are square and the free ones round: a
//  drawer, not a card. Several on one edge stack away from it.
//
//  A CORNER placement — align flush at either end — is its own thing:
//  the drawer attaches to two walls at once and GROWS out of the
//  corner, sliding in along the diagonal instead of the edge. And it
//  does not sit BESIDE the frame — it FUSES into it, the way a shell
//  of one material would grow a panel out of its own frame: where the
//  card's sides arrive at each wall, a concave fillet — one circular
//  arc, tangent to the side and tangent to the rim's inner wall —
//  carries the card into the frame line, so the material flows from
//  rim to card with no seam and no bump. The corner dug into the
//  screen's own corner stays square; the free corner keeps the card's
//  plain round. All of it plain rectangles: the fillet is a rounded
//  rect whose working corner is the blend, tucked into the card and
//  the rim where its other corners cannot be seen.
//
//  While any window is open the host dims the rest of the screen (the
//  Top-layer backdrop in shell.qml) — except the island, which lives
//  above the dim and stays alive: the pill still answers the hover.
//  The dim's click dismisses every window at once; Escape here closes
//  this one. The keyboard is one per session: the NEWEST window holds
//  it exclusively when its plugin asks, the rest type again the
//  moment they are clicked.

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

PanelWindow {
    id: ventana

    //  The plugin whose view this drawer hosts. Its `view` Component,
    //  its `islandWidth/Height` and its keyboard flags drive
    //  everything here.
    required property var plugin

    //  Newest of the open windows — the only one that may hold the
    //  keyboard exclusively. Set by the host.
    property bool esUltima: false

    //  Position among the windows on this edge: 0 sits flush, each
    //  extra one steps away so no drawer hides the one before it.
    property int indice: 0

    //  The frame around the view. Views carry their own padding,
    //  tuned for the island's body; this only keeps their rounded
    //  corners off the drawer's edge.
    readonly property int margen: 12
    readonly property int radio: 22

    //  The rim's thickness, as this drawer sees it: the frame is the
    //  bar's rim (Settings → Island), and the pour lands tangent on
    //  its inner wall. No rim, and there is nothing to pour into —
    //  the corner is just the card, flush.
    readonly property int grosorRim: Settings.edgeZoneEnabled
                                     ? Settings.edgeZoneSize : 0

    //  ── the pour into the frame ───────────────────────────
    //
    //  A tangent quarter-disc — the obvious fillet — is a BUMP: it
    //  rises a full radius off the wall and protrudes as far past the
    //  card's edge, so the card reads as sitting proud of the frame.
    //  What reads as POURED is the opposite proportion: long and
    //  shallow. An elliptical tongue hugging the wall — one
    //  rim-thickness of rise, three and a half of reach — so the
    //  frame visibly swells into the card and settles, never bumps.
    //
    //  Drawn as strips, pure rectangles: the ellipse's quarter
    //  profile stepped at fourteen slices, each tooth under 1.2 px,
    //  invisible against the island's own colour.
    readonly property real vertidoAlto: grosorRim * 1.25
    readonly property real vertidoLargo: grosorRim * 6.5
    readonly property int vertidoPasos: 20

    //  The quarter-ellipse profile, 0 at the wall's surface to 1 at
    //  the card's edge — the same curve for both pours, only rotated.
    function perfilVertido(u) {
        return 1 - Math.sqrt(2 * u - u * u)
    }

    //  The room the view asks for, clamped to what the screen can
    //  give a drawer: the ceiling the island enforces for its own,
    //  and air on the free side.
    readonly property int anchoVista: Math.min(
        plugin ? plugin.islandWidth : 300,
        Math.max(320, ventana.width - 120))
    readonly property int altoVista: Math.min(
        plugin ? plugin.islandHeight : 60,
        Math.min(Theme.maxIslandHeight, ventana.height - 120))

    //  The edge and the point along it: the view's own placement, or
    //  the bar's — resolved exactly as the island resolves it, so
    //  "follow the bar" means the same in both modes.
    readonly property var lugar: plugin
        ? Settings.placementDe(plugin.name)
        : ({ side: "top", align: 50 })
    readonly property bool ejeVertical: lugar.side === "left"
                                        || lugar.side === "right"

    //  A corner placement: align flush at either END of the edge. The
    //  drawer then attaches to the side wall as well — two walls, one
    //  corner, the way the bar itself attaches when the user corners
    //  it — and its shape turns with it (see the corner model below).
    readonly property bool esquinaInicio: lugar.align <= 0.5
    readonly property bool esquinaFin: lugar.align >= 99.5
    readonly property bool enEsquina: esquinaInicio || esquinaFin

    //  Which screen corner a corner placement names, as a two-letter
    //  compass point. Kept as its own property because the whole
    //  corner model keys off it.
    readonly property string esquinaPantalla: {
        if (lugar.side === "top")
            return esquinaFin ? "tr" : "tl"
        if (lugar.side === "bottom")
            return esquinaFin ? "br" : "bl"
        return lugar.side === "left"
            ? (esquinaFin ? "bl" : "tl")
            : (esquinaFin ? "br" : "tr")
    }

    //  Windows follow the screen the summon happened on — the same
    //  `Island.pantallaActiva` the island would have used.
    screen: {
        const nombre = Island.pantallaActiva
        const lista = Quickshell.screens
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].name === nombre)
                return lista[i]
        return lista.length > 0 ? lista[0] : null
    }

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    color: "transparent"
    visible: true

    //  Only the drawer takes input; everything around it stays usable —
    //  which is also what lets SEVERAL windows coexist: clicks fall
    //  through one drawer's surround to the next drawer or the dim.
    mask: Region { item: tarjeta }

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: -1

    WlrLayershell.namespace: "k4-popup-" + (plugin ? plugin.name : "x")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: {
        if (!plugin)
            return WlrKeyboardFocus.None
        //  The newest window holds the keyboard the way the island
        //  would; the older ones settle for typing once clicked.
        if (esUltima && plugin.grabKeyboard)
            return WlrKeyboardFocus.Exclusive
        if (plugin.grabKeyboard || plugin.tecladoOpcional)
            return WlrKeyboardFocus.OnDemand
        return WlrKeyboardFocus.None
    }

    // ── the slide out of the frame ─────────────────────────
    //
    //  The drawer is born fully beyond its edge and travels to its
    //  place in one move; `avance` is 0 tucked and 1 deployed. An
    //  edge drawer rides the perpendicular axis only — along the edge
    //  there is no travel: a drawer that also slid sideways would
    //  arrive somewhere it was never placed. A corner drawer is born
    //  beyond the CORNER and grows out of it: both axes ride the one
    //  slide, along the diagonal, so it never reads as «a bottom
    //  drawer pushed sideways» but as a thing the corner grew.
    property real avance: 0

    readonly property real tucke: ejeVertical ? tarjeta.width
                                              : tarjeta.height

    //  The stacked drawers' step, clamped so the last one still
    //  leaves its title bar's worth on screen.
    readonly property real escalon: Math.min(indice * 64,
        (ejeVertical ? ventana.width - tarjeta.width
                     : ventana.height - tarjeta.height) - 20)

    readonly property real perp: -tucke + avance * (tucke + Math.max(0, escalon))

    //  Where the drawer sits along its edge.
    readonly property real alLado: ejeVertical
        ? (ventana.height - tarjeta.height) * (lugar.align / 100)
        : (ventana.width - tarjeta.width) * (lugar.align / 100)

    //  ── the corner drawer's own geometry ───────────────────
    //
    //  One diagonal, two signs: the direction the drawer arrives
    //  FROM, which is also the wall each axis hugs. The stack step
    //  rides the same diagonal — a second corner drawer steps away
    //  from the corner, not from the edge.
    readonly property real haciaX: enEsquina
        ? ((esquinaPantalla === "tr" || esquinaPantalla === "br") ? 1 : -1)
        : 0
    readonly property real haciaY: enEsquina
        ? ((esquinaPantalla === "bl" || esquinaPantalla === "br") ? 1 : -1)
        : 0

    readonly property real xBase: (esquinaPantalla === "tr"
                                   || esquinaPantalla === "br")
        ? ventana.width - tarjeta.width : 0
    readonly property real yBase: (esquinaPantalla === "bl"
                                   || esquinaPantalla === "br")
        ? ventana.height - tarjeta.height : 0

    readonly property real extraX: enEsquina
        ? (1 - avance) * tarjeta.width + Math.max(0, escalon) : 0
    readonly property real extraY: enEsquina
        ? (1 - avance) * tarjeta.height + Math.max(0, escalon) : 0

    // ── the drawer ─────────────────────────────────────────
    Item {
        id: tarjeta

        width: ventana.anchoVista + ventana.margen * 2
        height: ventana.altoVista + ventana.margen * 2

        x: ventana.enEsquina
           ? ventana.xBase + ventana.haciaX * ventana.extraX
           : ventana.lugar.side === "left"
             ? ventana.perp
             : ventana.lugar.side === "right"
               ? ventana.width - tarjeta.width - ventana.perp
               : ventana.alLado
        y: ventana.enEsquina
           ? ventana.yBase + ventana.haciaY * ventana.extraY
           : ventana.lugar.side === "top"
             ? ventana.perp
             : ventana.lugar.side === "bottom"
               ? ventana.height - tarjeta.height - ventana.perp
               : ventana.alLado

        //  ── the card ────────────────────────────────────────
        //
        //  The classic rounded card. An EDGE drawer squares the two
        //  corners it opens from; a CORNER drawer squares only the
        //  one dug into the screen's own corner — its two wall
        //  corners are squared by the fillets that cover them (see
        //  below), and the free corner keeps the plain round.
        //  Patches fill the square corners the radius would leave
        //  open; they sit under the content, and what it carries
        //  renders on top.
        Rectangle {
            id: base
            anchors.fill: parent
            radius: ventana.radio
            color: Theme.islandBg
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
                visible: ventana.enEsquina
                         ? ventana.esquinaPantalla === "tl"
                         : (ventana.lugar.side === "top"
                            || ventana.lugar.side === "left")
                width: ventana.radio
                height: ventana.radio
                color: Theme.islandBg
            }
            Rectangle {
                visible: ventana.enEsquina
                         ? ventana.esquinaPantalla === "tr"
                         : (ventana.lugar.side === "top"
                            || ventana.lugar.side === "right")
                anchors.right: parent.right
                width: ventana.radio
                height: ventana.radio
                color: Theme.islandBg
            }
            Rectangle {
                visible: ventana.enEsquina
                         ? ventana.esquinaPantalla === "bl"
                         : (ventana.lugar.side === "bottom"
                            || ventana.lugar.side === "left")
                anchors.bottom: parent.bottom
                width: ventana.radio
                height: ventana.radio
                color: Theme.islandBg
            }
            Rectangle {
                visible: ventana.enEsquina
                         ? ventana.esquinaPantalla === "br"
                         : (ventana.lugar.side === "bottom"
                            || ventana.lugar.side === "right")
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: ventana.radio
                height: ventana.radio
                color: Theme.islandBg
            }
        }

        //  ── the pour into the frame ──────────────────────
        //
        //  Where the card's sides arrive at each wall, the frame
        //  swells to meet them: a long shallow tongue of the card's
        //  own colour, hugging the wall, one rim-thickness tall and
        //  reaching well past the card's side — the wall's material
        //  rising into the card and settling, the way a poured thing
        //  meets its mould. Strips of the ellipse profile, all one
        //  colour with the card and the rim, so card, pour and frame
        //  read as one body.
        Item {
            visible: ventana.enEsquina && ventana.grosorRim > 0

            //  On the horizontal wall: the card's far vertical side,
            //  the pour reaching along the rim past it.
            Repeater {
                model: ventana.vertidoPasos

                Rectangle {
                    required property int index

                    readonly property real dx: ventana.vertidoLargo
                        * ventana.perfilVertido(
                            index / ventana.vertidoPasos)
                    readonly property real paso:
                        ventana.vertidoAlto / ventana.vertidoPasos

                    x: ventana.haciaX > 0
                         ? -dx
                         : tarjeta.width - ventana.radio
                    y: ventana.haciaY > 0
                         ? tarjeta.height - ventana.grosorRim
                           - (index + 1) * paso
                         : ventana.grosorRim + index * paso
                    width: dx + ventana.radio
                    //  The strip nearest the wall runs on THROUGH the
                    //  rim band: it buries the card's border where
                    //  the wall takes over, which would otherwise
                    //  read as a seam between card and frame.
                    height: paso + 0.5
                            + (index === 0 ? ventana.grosorRim : 0)
                    color: Theme.islandBg
                }
            }

            //  On the vertical wall: the card's far horizontal side.
            Repeater {
                model: ventana.vertidoPasos

                Rectangle {
                    required property int index

                    readonly property real dy: ventana.vertidoLargo
                        * ventana.perfilVertido(
                            index / ventana.vertidoPasos)
                    readonly property real paso:
                        ventana.vertidoAlto / ventana.vertidoPasos

                    x: ventana.haciaX > 0
                         ? tarjeta.width - ventana.grosorRim
                           - (index + 1) * paso
                         : ventana.grosorRim + index * paso
                    y: ventana.haciaY > 0
                         ? -dy
                         : tarjeta.height - ventana.radio
                    //  Through the rim band at the wall, same as its
                    //  horizontal twin: no border seam at the frame.
                    width: paso + 0.5
                           + (index === 0 ? ventana.grosorRim : 0)
                    height: dy + ventana.radio
                    color: Theme.islandBg
                }
            }
        }

        //  Escape closes, like on the island — the key every view
        //  promises. It arrives while this drawer holds the focus,
        //  which the newest window claims on load and on promotion.
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Escape && ventana.plugin
                    && typeof ventana.plugin.close === "function") {
                ventana.plugin.close()
                e.accepted = true
            }
        }

        Loader {
            anchors.fill: parent
            anchors.margins: ventana.margen
            active: ventana.plugin && ventana.plugin.viewLoaded
            sourceComponent: ventana.plugin ? ventana.plugin.view : null

            onStatusChanged: {
                const p = ventana.plugin
                if (!p)
                    return
                if (status === Loader.Error)
                    PluginManager.registrarError(
                        p.name, "The view could not be loaded")
                else if (status === Loader.Ready)
                    PluginManager.limpiarError(p.name)
            }
        }

        Component.onCompleted: tarjeta.forceActiveFocus()
    }

    onEsUltimaChanged: {
        if (esUltima && plugin && plugin.grabKeyboard)
            tarjeta.forceActiveFocus()
    }

    Component.onCompleted: despliegue.restart()

    NumberAnimation {
        id: despliegue
        target: ventana
        property: "avance"
        from: 0
        to: 1
        duration: 200
        easing.type: Easing.OutCubic
    }
}
