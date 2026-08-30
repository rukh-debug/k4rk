//  The drop: an arrival that tells a detaching, not a move.
//
//  Ported from upstream k4's plugins/Dual/Caida.qml (k4ditano/k4), where it
//  animates the bar becoming a dock. That one is the reference — read its
//  comments before touching this — and everything that makes it read as
//  LIQUID is kept here: the phases, the hand-made curves, the neck that
//  thins until it snaps, the stretch of the fall, the puddle that lands as
//  EXACTLY the shape it hands over to.
//
//  One clock, `t`, 0 → 1, LINEAR on purpose — the easing lives in the shape
//  as math, not in the animation, because no single easing curve can do the
//  three things this arrival must do: swell slowly, fall accelerating, land
//  braking. Three phases:
//
//    0 … corte      the source and the bead, joined by a neck that thins.
//    corte … suelo  the fall: squared time, stretching, sharpening its tail.
//    suelo … 1      the landing: flatten against the point, spread with a
//                   hand-written OutBack into EXACTLY the seed of the view
//                   that opens beneath — the handover must be invisible.
//
//  This item only draws. It takes no input, decides nothing about the island,
//  and fires two signals — cortado() when the neck snaps, impacto() when the
//  splash starts — so the host can hide the island at the snap and grow it
//  under the splash at the landing. The splash lingers its beat past the
//  landing (relevo) to cover the first frames of that growth, then leaves.

import QtQuick
import QtQuick.Shapes
import "."

Item {
    id: raiz

    visible: false

    property bool activo: false

    //  {x, y} center of the pill — where the bead swells and the neck hangs.
    property var origen: null
    //  {x, y} center of the seed strip — where the splash lands.
    property var destino: null
    //  {w, h} of the island at the moment of opening: the splash's final
    //  shape, so what it leaves behind is what was always going to be there.
    property var semilla: null

    signal cortado()
    signal impacto()

    readonly property real corte: 0.34      // the neck snaps
    readonly property real suelo: 0.86      // the splash starts
    readonly property int duracion: 1000

    //  The clock.
    property real t: 0

    // ── the curves, by hand ───────────────────────────────────────
    //  Straight from Caida.qml, with its reasons: swell and hang must NOT
    //  share an exponent or the source seems to spit a ball instead of
    //  sweating a bead; the fall runs on squared time with a pinch of line
    //  so it does not brake dead at the start; the landing is OutBack
    //  written as a VALUE because the shape needs the number, not an
    //  animation.
    function _lim(v) { return Math.max(0, Math.min(1, v)) }
    function _mezcla(a, b, k) { return a + (b - a) * k }
    function _hincha(u) { return Math.pow(u, 0.55) }
    function _cuelga(u) { return Math.pow(u, 1.7) }
    function _rxCuelga(h) { return raiz.radio * (0.05 + 0.95 * h) }
    function _ryCuelga(h) { return raiz._rxCuelga(h) * (1 + 0.18 * h) }
    function _rxCae(p) { return raiz.radio * (1 - 0.30 * p) }
    function _ryCae(p) { return raiz.radio * 1.18 * (1 + 0.62 * p) }
    function _gravedad(u) { return 0.18 * u + 0.82 * u * u }
    function _atras(u) {
        const s = 1.28
        const k = u - 1
        return k * k * ((s + 1) * k + s) + 1
    }

    //  How fat the bead gets. Out of the seed's own height — the mass comes
    //  from what is detaching — and never so fat it dwarfs a short view.
    readonly property real radio: Math.max(14,
        Math.min(26, semilla ? semilla.h * 0.75 : 24))
    //  And how far it hangs before the neck gives. Enough travel that the
    //  neck is SEEN stretching — snap it too soon and there was no thread.
    readonly property real hondo: raiz.radio * 2.8

    //  Where the fall starts: the bead, fully hung.
    readonly property real fondoSalida: origen ? origen.y + raiz.hondo
        + raiz._ryCuelga(1) : 0

    // ── the shape, entire, in one place ───────────────────────────
    //
    //  `arriba`/`abajo` are how pointed each end is — the tail behind, always
    //  — and `plano` is how much of its sides are straight instead of curved:
    //  an ellipse is not the strip it hands over to, and at the exchange its
    //  corners would show for a couple of frames. A splash flattens on BOTH
    //  sides against what it hits; landing, it ends with the exact silhouette
    //  it is about to become.
    readonly property var ahora: raiz.forma(raiz.t)

    function forma(t) {
        if (!origen || !destino || !semilla)
            return { rx: 0, ry: 0, x: 0, y: 0, arriba: 0, abajo: 0,
                     plano: 0, cuello: 0 }

        const uCorte = raiz._lim(t / raiz.corte)
        const uCae = raiz._lim((t - raiz.corte) / (raiz.suelo - raiz.corte))
        const uChoque = raiz._lim((t - raiz.suelo) / (1 - raiz.suelo))

        //  ── the landing ─────────────────────────────────────────
        if (t >= raiz.suelo) {
            const p = raiz._atras(uChoque)
            const punta = 0.85 * Math.pow(1 - uChoque, 1.6)
            return {
                rx: raiz._mezcla(raiz._rxCae(1), semilla.w / 2, p),
                ry: raiz._mezcla(raiz._ryCae(1), semilla.h / 2, p),
                x: destino.x,
                y: destino.y,
                arriba: 0,
                abajo: punta,
                plano: uChoque * 0.55,
                cuello: 0
            }
        }

        //  ── the fall ────────────────────────────────────────────
        //  Diagonal when it must be: x rides the same gravity as y, toward
        //  where it is called — not straight down a line it then slides
        //  along. With the view centred under the source it does not veer
        //  a pixel.
        if (t >= raiz.corte) {
            const ry = raiz._ryCae(uCae)
            return {
                rx: raiz._rxCae(uCae), ry: ry,
                x: raiz._mezcla(origen.x, destino.x, raiz._gravedad(uCae)),
                y: raiz._mezcla(raiz.fondoSalida, destino.y,
                                raiz._gravedad(uCae)) - ry,
                arriba: 0.55 + 0.30 * uCae, abajo: 0,
                plano: 0, cuello: 0
            }
        }

        //  ── hanging from the source ─────────────────────────────
        //  First it swells, THEN it hangs: the bead's center walks down with
        //  the hang, its bottom faster than its top, and subtracting its own
        //  ry to center it is what makes it grow as it goes.
        const h = raiz._hincha(uCorte)
        return {
            rx: raiz._rxCuelga(h), ry: raiz._ryCuelga(h),
            x: origen.x,
            y: origen.y + raiz.hondo * raiz._cuelga(uCorte),
            arriba: 0.55 * h, abajo: 0,
            plano: 0, cuello: uCorte
        }
    }

    // ── the neck ──────────────────────────────────────────────────
    //
    //  What holds the bead to the source and then lets go. Three widths
    //  thinning at three different rates is the whole effect: the mouth
    //  holds, the foot follows, and the WAIST gives way first — the
    //  hourglass opens, and it snaps. It cuts at a pixel and a half and not
    //  at zero: below that the fill covers no whole pixel and what shows is
    //  a dotted thread; cutting while it can still be seen is also what
    //  makes the snap read as a snap.
    readonly property real cuelloU: ahora.cuello
    readonly property real bocaCuello:
        raiz.radio * 0.80 * Math.pow(1 - raiz.cuelloU, 0.55)
    readonly property real cinturaCuello:
        raiz.radio * 0.62 * Math.pow(1 - raiz.cuelloU, 1.15)
    readonly property real pieCuello:
        raiz.radio * 0.70 * Math.pow(1 - raiz.cuelloU, 0.80)

    //  Bites 4 px into where the pill's edge was, not flush with it: a neck
    //  born exactly on the silhouette line leaves a visible seam the moment
    //  the two antialiased edges disagree by half a pixel.
    readonly property real bocaY: origen ? origen.y + semilla.h / 2 - 4 : 0

    //  Solved from the quadratic: the midpoint of a quadratic Bézier is
    //  (P0 + 2C + P2) / 4, so to pass through the waist the control goes
    //  twice as far the other way.
    readonly property real mandoCuello:
        (4 * raiz.cinturaCuello - raiz.bocaCuello - raiz.pieCuello) / 2

    // ── the drawing ───────────────────────────────────────────────
    //
    //  Both pieces in one Shape, one colour, overlapping on purpose — the
    //  neck ends INSIDE the bead — so there is no seam to see. Quadratics
    //  and not elliptical arcs: an arc demands the sweep direction be
    //  guessed right, and this shape changes proportion every frame, so a
    //  wrong sign shows up one run in ten. A quadratic has no sign to get
    //  wrong.
    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            id: trazoGota
            fillColor: Theme.islandBg
            strokeWidth: 0
            strokeColor: "transparent"

            readonly property real gx: raiz.ahora.x
            readonly property real gy: raiz.ahora.y
            readonly property real rx: raiz.ahora.rx
            readonly property real ry: raiz.ahora.ry

            //  The straight flanks: zero when not flattened, and the shape
            //  is exactly the ellipse it was.
            readonly property real llano: rx * raiz.ahora.plano

            //  Each half's control: on the corner when that end is not
            //  pointed — a quarter ellipse — and nearly on the axis when it
            //  is, which is what pulls the tip out.
            readonly property real mandoAltoX:
                rx * (1 - 0.92 * raiz.ahora.arriba)
            readonly property real mandoAltoY:
                gy - ry * (1 - 0.06 * raiz.ahora.arriba)
            readonly property real mandoBajoX:
                rx * (1 - 0.92 * raiz.ahora.abajo)
            readonly property real mandoBajoY:
                gy + ry * (1 - 0.06 * raiz.ahora.abajo)

            startX: trazoGota.gx - trazoGota.rx
            startY: trazoGota.gy

            PathQuad {
                x: trazoGota.gx - trazoGota.llano
                y: trazoGota.gy + trazoGota.ry
                controlX: trazoGota.gx - trazoGota.mandoBajoX
                controlY: trazoGota.mandoBajoY
            }
            PathLine {
                x: trazoGota.gx + trazoGota.llano
                y: trazoGota.gy + trazoGota.ry
            }
            PathQuad {
                x: trazoGota.gx + trazoGota.rx; y: trazoGota.gy
                controlX: trazoGota.gx + trazoGota.mandoBajoX
                controlY: trazoGota.mandoBajoY
            }
            PathQuad {
                x: trazoGota.gx + trazoGota.llano
                y: trazoGota.gy - trazoGota.ry
                controlX: trazoGota.gx + trazoGota.mandoAltoX
                controlY: trazoGota.mandoAltoY
            }
            PathLine {
                x: trazoGota.gx - trazoGota.llano
                y: trazoGota.gy - trazoGota.ry
            }
            PathQuad {
                x: trazoGota.gx - trazoGota.rx; y: trazoGota.gy
                controlX: trazoGota.gx - trazoGota.mandoAltoX
                controlY: trazoGota.mandoAltoY
            }
        }

        //  The neck. Lives only while there is something to hold: past the
        //  snap it draws DEGENERATE — all mouth, no area — instead of
        //  hiding, because a ShapePath has no `visible` and swapping it
        //  through a Loader rebuilds the whole path mid-animation.
        ShapePath {
            id: trazoCuello
            fillColor: Theme.islandBg
            strokeWidth: 0
            strokeColor: "transparent"

            readonly property bool vivo: raiz.t < raiz.corte
                && raiz.cinturaCuello > 1.5
            readonly property real gx: raiz.ahora.x
            readonly property real boca: vivo ? raiz.bocaCuello : 0
            readonly property real pie: vivo ? raiz.pieCuello : 0
            readonly property real mando: vivo ? raiz.mandoCuello : 0
            readonly property real abajo: vivo ? raiz.ahora.y : raiz.bocaY
            readonly property real medio: (raiz.bocaY + abajo) / 2

            startX: trazoCuello.gx - trazoCuello.boca
            startY: raiz.bocaY

            PathLine {
                x: trazoCuello.gx + trazoCuello.boca; y: raiz.bocaY
            }
            PathQuad {
                x: trazoCuello.gx + trazoCuello.pie; y: trazoCuello.abajo
                controlX: trazoGota.gx + trazoCuello.mando
                controlY: trazoCuello.medio
            }
            PathLine {
                x: trazoCuello.gx - trazoCuello.pie; y: trazoCuello.abajo
            }
            PathQuad {
                x: trazoCuello.gx - trazoCuello.boca; y: raiz.bocaY
                controlX: trazoGota.gx - trazoCuello.mando
                controlY: trazoCuello.medio
            }
        }
    }

    // ── the telling of time ───────────────────────────────────────
    NumberAnimation {
        id: viaje
        target: raiz
        property: "t"
        from: 0
        to: 1
        duration: raiz.duracion
        //  Linear on purpose: the curves are in the shape, not here.
        easing.type: Easing.Linear
    }

    //  The snap and the landing are instants of the schedule, not properties
    //  of the shape: timers, not per-frame watching.
    Timer {
        id: relojCorte
        interval: Math.round(raiz.duracion * raiz.corte)
        onTriggered: raiz.cortado()
    }

    Timer {
        id: relojSuelo
        interval: Math.round(raiz.duracion * raiz.suelo)
        onTriggered: {
            raiz.impacto()
            //  The splash outlives its own landing by a beat, covering the
            //  first frames of the growth it hands over to. Leaving sooner
            //  shows a half-built view; leaving later paints over content
            //  that is already arriving.
            relevo.restart()
        }
    }

    Timer {
        id: relevo
        interval: 180
        onTriggered: raiz.parar()
    }

    // ── the doors ─────────────────────────────────────────────────
    function play(origenN, destinoN, semillaN) {
        origen = origenN
        destino = destinoN
        semilla = semillaN
        t = 0
        activo = true
        visible = true
        relevo.stop()
        relojCorte.restart()
        relojSuelo.restart()
        viaje.restart()
    }

    function parar() {
        viaje.stop()
        relojCorte.stop()
        relojSuelo.stop()
        relevo.stop()
        activo = false
        visible = false
        t = 0
    }
}
