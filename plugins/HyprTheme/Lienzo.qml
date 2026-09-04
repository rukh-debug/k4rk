//  The canvas: the desktop wallpaper, drawn by the bar itself.
//
//  Until now swaybg put up the wallpaper and the bar only handed it a
//  path. That leaves three things out at once: no transitions —the
//  module itself admitted it in its foot, «install awww to have
//  them»—, no video, and the bar does not know what it is showing,
//  so it cannot draw colors from it. Painting it here, in a
//  K4.Ventana on the bottom layer —which the API learned for this—,
//  the wallpaper comes INSIDE the same engine that draws the island.
//
//  And without a single new dependency: `AnimatedImage` comes in
//  QtQuick and `MediaPlayer` in QtMultimedia, already a declared
//  dependency since the video editor needs its decoder.
//
//  ── swaybg is NOT retired: it stays as the FLOOR ─────────────────
//
//  What the bar draws lives as long as the bar lives, and between
//  entering the session and quickshell starting there is a while
//  with nobody there. If in that while the wallpaper is a black
//  rectangle, we worsened something that worked. And if one day the
//  bar falls, the same. So swaybg keeps being given the still frame
//  —for a video, its poster— and the canvas paints on top: on
//  entering you see the photo, and when the bar arrives it gets
//  going.
//
//  ── what it costs, measured before writing it ────────────────────
//
//  On a separate bench, monitor at 60 Hz, on the process and not by
//  eye:
//
//      still             0.5 % of one core  (and of that, almost all
//                                              is the bench's fps
//                                              counter)
//      GIF 960 · 20 fps  11.9 %
//      video 1080p60     14–18 %   ·  that is 1.5 % of a 12-core
//                                  machine
//
//  A GIF costs nearly the same as a video for a quarter of the
//  quality: it decompresses on CPU and no decoder helps. Whoever
//  brings a big GIF does better converting it, and that is the
//  coming screen's business.

import QtQuick
import QtMultimedia
import QtQuick.Effects
import QtQuick.Shapes
import K4 as K4
import "../../services"

K4.PorPantalla {
    id: lienzo

    //  Whoever knows which wallpaper goes on each screen. It is asked
    //  instead of keeping it here because the state is the plugin's —
    //  it saves it, loads it and publishes it over IPC— and this only
    //  paints.
    required property var plugin

    //  Which transition and how long. They come from the plugin,
    //  which is the one keeping them.
    readonly property string transicion: lienzo.plugin
        ? lienzo.plugin.transicion : "fundido"
    readonly property int duracion: 900

    //  Putting a path on a layer is putting TWO things —the path and
    //  its type— and doing them separately leaves one frame with the
    //  previous one's type.
    function poner(c, r) {
        c.ruta = String(r || "")
        c.tipo = lienzo.tipoDe(c.ruta)
    }

    //  By extension and not by asking the user: nobody wants to pick
    //  from a dropdown whether their file is a video. `webp` goes the
    //  animated way on purpose — a still one paints just as well
    //  there, and guessing which is which asks to open the file.
    //  ── how much is visible, and therefore whether moving is worth it ──
    //
    //  An animated wallpaper does NOT stop just because it is
    //  covered. Measured before writing anything: 16 % of a core
    //  decoding a video with a 1900×1026 terminal on top. That is
    //  all day spending for nobody, and it is the only one of this
    //  phase's three things no background daemon hands you done —
    //  hence the worth of drawing it here.
    //
    //  It is measured by SAMPLING and not by computing the union of
    //  rectangles: the exact union of N overlapping windows is an
    //  algorithm with rare cases, and what is needed here is not an
    //  exact area but an answer to «is any wallpaper left in
    //  sight?». A 16×9 grid is 144 points, each resolves with four
    //  comparisons, and it is wrong by at most one sixteenth of the
    //  screen.
    readonly property int rejillaX: 24
    readonly property int rejillaY: 14

    //  Below this it stops. Not 0 %: with tiled windows the gaps'
    //  slivers always peek out, and leaving a video running for
    //  eight pixels of sliver is exactly what was to be avoided.
    //
    //  And it is 3 % and not 8 because the count is made over the
    //  USABLE area (see `libresEn`): without discounting the
    //  reserved space, the dock's strip —62 px— was worth 6 % on its
    //  own and with the dock up it never stopped.
    readonly property real umbralVisible: 0.03

    //  The windows in front, in desktop coordinates.
    //  ── the windows in front ─────────────────────────────────────
    //
    //  Asked of `hyprctl` directly and not of the windows service,
    //  and not for taste: `Ventanas.refrescar()` calls
    //  `Hyprland.refreshToplevels()` **if it exists**, and in this
    //  Quickshell version it does not — the guarding `typeof` turns
    //  it into a silent no-op. Measured consequence: a freshly
    //  opened window came out in the list with its `lastIpcObject`
    //  EMPTY (`ws=None at=None`), fell off the filter, the canvas
    //  gave `free 144/144` and the video kept running under a window
    //  that covered it whole.
    //
    //  Which workspaces are in front does come out of `Workspaces`,
    //  which keeps each one's `active` up to date — that was checked
    //  and came out right.
    property var cajas: []

    //  What each monitor has reserved for bars, by name.
    property var reservas: ({})

    //  In a named property and not as a loose child: `Variants`'s
    //  default property is `delegate`, so a bare child gets assigned
    //  there and the id never comes to exist. Symptom:
    //  `ReferenceError: mirarVentanas is not defined` and zero
    //  windows counted, with the delegate working the same because
    //  its explicit assignment wins.
    property var procVentanas: K4.Process {
        //  Both at once and in a single process: the windows AND the
        //  reserved space are needed, and two processes would be two
        //  out-of-step answers and a count made of half of each
        //  photo.
        command: ["sh", "-c",
            "hyprctl monitors -j; echo '@@@'; hyprctl clients -j"]

        onSalida: function (texto) {
            const partes = String(texto).split("@@@")
            if (partes.length < 2)
                return
            let mons = [], l = []
            try {
                mons = JSON.parse(partes[0])
                l = JSON.parse(partes[1])
            } catch (e) {
                return
            }
            const res = ({})
            for (let i = 0; i < mons.length; ++i) {
                const r = mons[i].reserved
                res[mons[i].name] = (r && r.length === 4) ? r : [0, 0, 0, 0]
            }
            lienzo.reservas = res
            const delante = ({})
            const ws = Workspaces.list
            for (let i = 0; i < ws.length; ++i)
                if (ws[i].active)
                    delante[ws[i].id] = true

            const nuevas = []
            for (let i = 0; i < l.length; ++i) {
                const c = l[i]
                if (!c || !c.at || !c.size || c.hidden === true)
                    continue
                if (!c.workspace || delante[c.workspace.id] !== true)
                    continue
                nuevas.push([c.at[0], c.at[1],
                             c.at[0] + c.size[0], c.at[1] + c.size[1]])
            }
            //  A NEW container: mutating the existing one repaints
            //  nothing in QML, and then `aLaVista` never learns the
            //  world changed.
            lienzo.cajas = nuevas
        }
    }

    function pedirVentanas() {
        if (lienzo.procVentanas && !lienzo.procVentanas.running)
            lienzo.procVentanas.running = true
    }

    function cajasVistas() { return lienzo.cajas }

    //  Is anything moving right now? From the kept list and not
    //  from the canvases, because this has to be REACTIVE and
    //  `instances` is not.
    readonly property bool hayMovimiento: {
        if (!lienzo.plugin)
            return false
        const mueve = function (r) {
            const t = lienzo.tipoDe(r)
            return t === "video" || t === "animado"
        }
        const f = lienzo.plugin.fondos || ({})
        for (const k in f)
            if (mueve(f[k]))
                return true
        return mueve(lienzo.plugin.wallpaper)
    }

    //  Two triggers. The good one is a window opening or closing,
    //  which does arrive by signal and makes the pause answer at
    //  once; the clock is the net for what gives no notice —moving
    //  or resizing— and only runs while something moves. With
    //  everything still not a single process is launched.
    property Connections escucha: Connections {
        target: Ventanas
        function onListaChanged() { lienzo.pedirVentanas() }
    }

    property Timer vigia: Timer {
        interval: 2000
        repeat: true
        running: lienzo.hayMovimiento
        triggeredOnStart: true
        onTriggered: lienzo.pedirVentanas()
    }

    //  The grid points no window covers, counted over the monitor's
    //  USABLE area and not over the whole monitor.
    //
    //  The reserved space —the bar's strip on top, the dock's below—
    //  is covered by the bar or the dock themselves, which are not
    //  windows and therefore do not show up in `hyprctl clients`.
    //  Counting it, a screen with a maximized window and the dock up
    //  gave 16 of 144 points «free» —11 %— and the video never
    //  stopped. Which is exactly what was seen.
    function libresEn(nombre, x0, y0, ancho, alto) {
        const r = lienzo.reservas[nombre] || [0, 0, 0, 0]
        x0 += r[0]
        y0 += r[1]
        ancho -= r[0] + r[2]
        alto -= r[1] + r[3]
        if (ancho <= 0 || alto <= 0)
            return 0
        const cajas = lienzo.cajasVistas()
        let libres = 0
        for (let ix = 0; ix < lienzo.rejillaX; ++ix) {
            const px = x0 + ancho * (ix + 0.5) / lienzo.rejillaX
            for (let iy = 0; iy < lienzo.rejillaY; ++iy) {
                const py = y0 + alto * (iy + 0.5) / lienzo.rejillaY
                let tapado = false
                for (let c = 0; c < cajas.length; ++c) {
                    const b = cajas[c]
                    if (px >= b[0] && px < b[2] && py >= b[1] && py < b[3]) { tapado = true; break }
                }
                if (!tapado) libres += 1
            }
        }
        return libres
    }

    //  And the answer: is enough wallpaper left in sight for moving
    //  to be worth it?
    function seVeAlgoEn(nombre, x0, y0, ancho, alto) {
        if (!nombre || ancho <= 0 || alto <= 0)
            return true
        if (lienzo.cajasVistas().length === 0)
            return true
        return lienzo.libresEn(nombre, x0, y0, ancho, alto)
            / (lienzo.rejillaX * lienzo.rejillaY) > lienzo.umbralVisible
    }

    function tipoDe(ruta) {
        const r = String(ruta || "").toLowerCase()
        if (/\.(mp4|webm|mkv|mov|m4v|avi)$/.test(r))
            return "video"
        if (/\.(gif|webp|apng)$/.test(r))
            return "animado"
        if (r.length === 0)
            return "nada"
        return "quieto"
    }

    delegate: K4.Ventana {
        id: tela

        required property var modelData
        screen: modelData

        nombre: "k4-fondo"

        //  Under the windows. And collecting not a single click:
        //  without `zonaActiva` the mask stays `null` and this
        //  surface takes ALL the desktop's clicks — which on the
        //  bottom layer means a desktop that stops responding with
        //  nobody knowing why (see api/K4/Ventana.qml).
        capa: "fondo"

        //  And FULLSCREEN, skipping other people's reservations.
        //
        //  With `reserva: 0` —the factory value— the window reserves
        //  no space but does respect everyone else's, so the bar's
        //  34 px strip pushed it: measured, it came out `1920x1046
        //  at (…,34)`. A desktop wallpaper starting where the bar
        //  ends leaves a dead band on top and skews the image's fit.
        //  `-1` is reserving nothing AND skipping others', which is
        //  exactly what is needed under everything.
        reserva: -1

        zonaActiva: nada

        Item { id: nada; width: 0; height: 0 }

        readonly property string cual: modelData ? modelData.name : ""
        readonly property string ruta: lienzo.plugin
            ? lienzo.plugin.fondoDe(cual) : ""

        //  It only exists if there is something to paint. With no
        //  wallpaper assigned the surface is not created: then
        //  swaybg's floor shows, which is exactly what was there
        //  before all this.
        //
        //  ── and a PHOTO is painted by swaybg, not this ───────────
        //
        //  With a still wallpaper this layer draws exactly what the
        //  floor is already drawing underneath. Measured on the
        //  process: **80 MiB of VRAM** and some 18 MB of RSS for
        //  contributing nothing —the bar was the machine's biggest
        //  video consumer, ahead of the browser—. So with a photo
        //  the bar steps aside and the floor shows; it keeps only
        //  what swaybg cannot do, which is video, GIF and
        //  transitions.
        //
        //  The after-GRACE is not decoration. At the end of the fade
        //  swaybg must be given time to have the NEW image, and
        //  setting it is not instantaneous: `ponerSuelo` debounces
        //  300 ms, kills the old one, waits 200 more and raises the
        //  new. Dropping the layer at the end of the transition
        //  shows a flicker of the old wallpaper, or of the void.
        //
        //  And it arms at startup too, for the same reason: between
        //  entering the session and swaybg being set there is a gap,
        //  and covering it is exactly what the floor is for.
        readonly property bool loPintaElSuelo: lienzo.tipoDe(ruta) === "quieto"
            && !tela.cambiando && !gracia.running

        visible: lienzo.tipoDe(ruta) !== "nada" && !tela.loPintaElSuelo

        Timer {
            id: gracia
            interval: 2500
        }

        onCambiandoChanged: if (!tela.cambiando) gracia.restart()

        // ── the two layers and the handover ────────────────────
        //
        //  A transition needs BOTH at once: the leaving one stays up
        //  until the end, and the arriving one is revealed on top.
        //  `viva` says which has the wallpaper set; the other is the
        //  one coming in, and always rides on top.
        property int viva: 0
        property real avance: 1
        readonly property bool cambiando: tela.avance < 1

        readonly property var capaViva: tela.viva === 0 ? capaA : capaB
        readonly property var capaEntra: tela.viva === 0 ? capaB : capaA

        //  Is any of this wallpaper visible? It recomputes itself:
        //  it depends on `Ventanas.lista`, which is reactive, so
        //  opening or closing a window and switching desktops fire
        //  the count already. A still wallpaper does not ask: it
        //  spends nothing even unseen.
        readonly property bool aLaVista: lienzo.tipoDe(ruta) === "quieto"
            || lienzo.tipoDe(ruta) === "nada"
            || !tela.screen
            || lienzo.seVeAlgoEn(tela.cual, tela.screen.x, tela.screen.y,
                                 tela.screen.width, tela.screen.height)

        Capa {
            id: capaA
            anchors.fill: parent
            z: tela.viva === 0 ? 0 : 1
            animando: tela.aLaVista
            plugin: lienzo.plugin
            anchoPantalla: tela.screen ? tela.screen.width : 1920
            altoPantalla: tela.screen ? tela.screen.height : 1080
        }

        Capa {
            id: capaB
            anchors.fill: parent
            z: tela.viva === 1 ? 0 : 1
            animando: tela.aLaVista
            plugin: lienzo.plugin
            anchoPantalla: tela.screen ? tela.screen.width : 1920
            altoPantalla: tela.screen ? tela.screen.height : 1080
        }

        onRutaChanged: tela.relevar()

        Component.onCompleted: {
            tela.relevar()
            gracia.restart()
        }

        function relevar() {
            const nueva = tela.ruta
            //  With nothing set yet —at startup— or no effect, there
            //  is no transition: it just goes up. Fading from a
            //  wallpaper that does not exist is fading from black,
            //  which is worse than not fading.
            if (tela.capaViva.ruta === nueva)
                return
            if (tela.capaViva.ruta.length === 0
                    || nueva.length === 0
                    || lienzo.transicion === "ninguna") {
                lienzo.poner(tela.capaViva, nueva)
                lienzo.poner(tela.capaEntra, "")
                tela.avance = 1
                return
            }
            lienzo.poner(tela.capaEntra, nueva)
            tela.avance = 0
            paso.restart()
        }

        NumberAnimation {
            id: paso
            target: tela
            property: "avance"
            to: 1
            duration: lienzo.duracion
            //  Starts soft and stops soft: what is shown is a
            //  surface changing, not an object being thrown.
            easing.type: Easing.InOutCubic
            onFinished: {
                //  The handover: the one coming in becomes the set
                //  one, and the other is emptied. Emptying it BEFORE
                //  changing `viva` would erase the one being
                //  watched.
                tela.viva = tela.viva === 0 ? 1 : 0
                lienzo.poner(tela.capaEntra, "")
            }
        }

        // ── how the incoming one is revealed ───────────────────
        //
        //  One road for all three effects: the incoming layer is
        //  ALWAYS painted through the effect, and what changes is
        //  whether it carries a mask or only opacity. Having them on
        //  separate roads was having two places for the handover to
        //  go wrong.
        ShaderEffectSource {
            id: texturaEntra
            anchors.fill: parent
            sourceItem: tela.capaEntra
            //  It hides it: the effect paints it, and drawn twice
            //  the one below would peek through where the mask cuts
            //  it.
            hideSource: true
            live: true
            visible: false
        }

        //  The mask's mold. It does not draw —its own texture hides
        //  it— and it exists only so the effect has somewhere to take
        //  the shape from. White means «the new one shows here».
        Item {
            id: molde
            anchors.fill: parent

            //  ── iris: a circle growing FROM THE ISLAND ──────
            //
            //  From the island and not from the screen's center
            //  because the island is what just changed the
            //  wallpaper: the change comes from where you asked for
            //  it. On a screen without it deployed, its pill is still
            //  there, so the point works the same.
            Rectangle {
                visible: lienzo.transicion === "iris"
                color: "white"
                width: tela.radioIris * 2
                height: width
                radius: width / 2
                x: tela.focoX - width / 2
                y: tela.focoY - height / 2
            }

            //  ── tide: rises from the bottom edge ────────
            //
            //  With a wavy front and not straight, which is what
            //  tells it apart from a curtain: two sines of different
            //  length dephased, so the pattern cannot be read. The
            //  wave dies out at the end —`Math.sin(pi·avance)` is 0
            //  at both extremes— because a wavy front just reaching
            //  the edge leaves the last finger of old wallpaper
            //  peeking.
            Shape {
                anchors.fill: parent
                visible: lienzo.transicion === "marea"
                antialiasing: true

                ShapePath {
                    //  With an id, and NOT by `parent`, which is
                    //  what the log complained about on every
                    //  transition: a `PathQuad` is not an Item —it
                    //  is a pathing element— so it has no `parent`,
                    //  and `parent.frente` read `undefined`. The
                    //  control points came out undefined and the
                    //  front's wave did not draw: the tide rose
                    //  STRAIGHT, which is exactly the curtain the
                    //  comment above says it wants to tell itself
                    //  apart from.
                    id: marea

                    fillColor: "white"
                    strokeWidth: 0
                    strokeColor: "transparent"

                    readonly property real frente: tela.height * (1 - tela.avance)
                    readonly property real onda: tela.height * 0.06
                        * Math.sin(Math.PI * tela.avance)

                    startX: 0
                    startY: frente

                    PathQuad {
                        x: tela.width * 0.5; y: marea.frente
                        controlX: tela.width * 0.25
                        controlY: marea.frente - marea.onda * 2
                    }
                    PathQuad {
                        x: tela.width; y: marea.frente
                        controlX: tela.width * 0.75
                        controlY: marea.frente + marea.onda * 2
                    }
                    PathLine { x: tela.width; y: tela.height }
                    PathLine { x: 0; y: tela.height }
                }
            }
        }

        ShaderEffectSource {
            id: texturaMolde
            anchors.fill: parent
            sourceItem: molde
            hideSource: true
            live: true
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            z: 2
            visible: tela.cambiando
            source: texturaEntra
            //  The fade is opacity and the other two are mask. A
            //  fade done with a mask would ask for a uniform-gray
            //  mold and a sweeping threshold, which is taking the
            //  long way to the same place.
            opacity: lienzo.transicion === "fundido" ? tela.avance : 1
            maskEnabled: lienzo.transicion !== "fundido"
            maskSource: texturaMolde
        }

        //  Where the iris starts and how far it must grow to cover
        //  the screen: the farthest corner, which is the one that
        //  rules.
        readonly property var rectIsla: K4.Isla.rectEn(tela.cual)
        readonly property real focoX: rectIsla && rectIsla.ancho > 0
            ? rectIsla.x + rectIsla.ancho / 2 : tela.width / 2
        readonly property real focoY: rectIsla && rectIsla.alto > 0
            ? rectIsla.y + rectIsla.alto : 0
        readonly property real radioIris: {
            const dx = Math.max(tela.focoX, tela.width - tela.focoX)
            const dy = Math.max(tela.focoY, tela.height - tela.focoY)
            return Math.sqrt(dx * dx + dy * dy) * tela.avance
        }

        //  Para poder mirarle las tripas desde fuera.
        function estado() {
            return { pantalla: tela.cual, tipo: lienzo.tipoDe(tela.ruta),
                     ruta: tela.ruta,
                     aLaVista: tela.aLaVista,
                     ventanasDelante: lienzo.cajasVistas().length,
                     libres: tela.screen ? lienzo.libresEn(
                         tela.cual, tela.screen.x, tela.screen.y,
                         tela.screen.width, tela.screen.height) : -1,
                     puntos: lienzo.rejillaX * lienzo.rejillaY,
                     avance: Math.round(tela.avance * 100) / 100,
                     viva: tela.viva,
                     reproduciendo: tela.capaViva.reproduciendo,
                     error: tela.capaViva.fallo }
        }
    }
}
