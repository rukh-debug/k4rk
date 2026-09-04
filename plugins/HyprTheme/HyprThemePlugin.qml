//  Theming Hyprland from the island: colors, windows, effects and
//  wallpaper.
//
//  Two roads, one language. Live it goes through `hyprctl eval`, which
//  evaluates Lua in the running Hyprland — `hyprctl keyword` is no
//  use here: with the new parser it answers "keyword can't work with
//  non-legacy parsers".
//
//  To survive a restart, k4 owns config/k4-theme.lua and appends it at
//  the end of hyprland.lua. Going last, its values win without
//  touching a single line of CachyOS's configuration: delete the
//  file and the `require` line, and everything is back as it was.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "hyprtheme"
    title: "Hyprland theme"
    //  No `active`, no `view`, no keyboard: this plugin no longer
    //  draws.
    //
    //  It had its own screen with four tabs —color, windows,
    //  effects and wallpaper— and it was one more place to configure
    //  things. All of that now lives in the Settings window, in its
    //  sections, with the same widgets. What stays here is what
    //  nobody else knows how to do: writing Hyprland's Lua, talking
    //  to awww/swww/swaybg and painting the floor.
    //
    //  It is the same road the plugin store and Settings themselves
    //  took: what opens and gets used is an application, and what
    //  knows how to do something is an engine. Only the engine
    //  remains here.

    //  Big on purpose, and above all TALL.
    //
    //  At 470 the wallpaper grid showed two and a half rows of fifty:
    //  finding one meant walking it blind, which is exactly what a
    //  thumbnail grid exists to avoid. At 780 four long rows fit and
    //  one chooses by looking, which is how a wallpaper is chosen.
    //
    //  780 and no more: the surface's ceiling is 880
    //  (`Theme.maxIslandHeight`) and it pays to leave air, since
    //  under the island some desktop still has to fit so it does not
    //  look like a fullscreen window that is not one.

    // Opened with the mouse, so it leaves with it. With more margin
    // than the panel: sliders get dragged here and overshooting the
    // edge is easy.
    closeOnHoverExit: true
    hoverExitDelay: 1000
    //  Except with the file picker open: choosing requires taking the
    //  mouse out of here, and closing then is closing exactly when
    //  the user is doing what we asked of them.
    onHoverTimedOut: if (!eligiendo) close()

    readonly property string hyprDir: K4.Sistema.entorno("HOME") + "/.config/hypr"
    readonly property string themeFile: hyprDir + "/config/k4-theme.lua"
    readonly property string entryFile: hyprDir + "/hyprland.lua"
    readonly property string stateFile: K4.Sistema.entorno("HOME") + "/.local/state/k4/hyprtheme.json"

    // ── ajustes ───────────────────────────────────────────────────
    property string preset: "cachyos"
    property color accentFrom: "#82dccc"
    property color accentTo: "#007d6f"
    property color inactive: "#798bb2"
    property int angle: 45

    property int gapsIn: 3
    property int gapsOut: 8
    property int borderSize: 2
    property int rounding: 10

    property bool blur: true
    property int blurSize: 5
    property int blurPasses: 4
    property real activeOpacity: 0.95
    property real inactiveOpacity: 0.85
    property bool shadow: true

    property bool animEnabled: true
    property int animSpeed: 3

    property string wallpaper: ""

    //  ── the wallpaper, per screen now ────────────────────────────
    //
    //  `{ "DP-3": "/path/a.mp4", "HDMI-A-1": "/path/b.png" }`. With
    //  two monitors, a single one for both was a limitation with no
    //  reason to exist: the surface is already one per screen.
    //
    //  `wallpaper` is not retired and not for decorative
    //  compatibility: it is what whoever already used this has
    //  saved, and whoever has chosen nothing for a given screen
    //  must keep seeing what they saw.
    property var fondos: ({})

    //  How one wallpaper gives way to the next.
    //
    //   · "fundido"  — the honest one: one leaves while the other
    //     arrives. Works for any pair of wallpapers and tells
    //     nothing but the truth.
    //   · "iris"     — a circle growing FROM THE ISLAND, the one that
    //     just changed the wallpaper: the change comes from where
    //     you asked for it.
    //   · "marea"    — the new one rises from the bottom edge with a
    //     wavy front, which is the house's liquid grammar.
    //   · "ninguna"  — hard cut, for whoever changes wallpapers
    //     twenty times a day and wants no movie each time.
    readonly property var transiciones: ["fundido", "iris", "marea", "ninguna"]
    property string transicion: "fundido"

    function fondoDe(pantalla) {
        const propio = fondos[pantalla]
        return propio && propio.length > 0 ? propio : wallpaper
    }

    //  A NEW container and not mutating the existing one: QML only
    //  propagates when the property's IDENTITY changes, so touching
    //  the inside tells the canvas nothing.
    function ponerFondoEn(pantalla, ruta) {
        if (!pantalla || pantalla.length === 0)
            return
        const d = ({})
        for (const k in fondos)
            d[k] = fondos[k]
        //  Empty is REMOVING that screen's choice, not saving an empty
        //  string: `fondoDe` already knows to fall back to the common
        //  wallpaper when there is no key, and a key holding "" is a
        //  state that means nothing and that every reader of the map
        //  would have to remember to filter.
        if (String(ruta || "").length === 0)
            delete d[pantalla]
        else
            d[pantalla] = String(ruta)
        fondos = d
        saveState()
        ponerSuelo()
        sacarPaleta()
    }

    // Watermark: presets only look "chosen" while you touch nothing.
    property bool dirty: false

    //  ── the palette, drawn from the wallpaper ────────────────────
    //
    //  On —the factory state—, colors come from whatever wallpaper
    //  you set and spread to the two places they show: the bar's
    //  tint and Hyprland's borders. Change the wallpaper and the
    //  whole ambiance rearranges itself.
    //
    //  And there is a third place for free: `services/Ambiente.qml`
    //  already publishes the TINTED theme in `tema.json` for
    //  whoever lives outside the bar, so k4term tints with the
    //  wallpaper without one extra line.
    //
    //  It turns itself off when a preset is touched: whoever picks a
    //  color by hand does not want the next wallpaper stepping on it,
    //  and turning it off by itself avoids the setting nobody finds.
    property bool paletaAuto: true

    //  Which wallpaper it comes from. With two monitors and two
    //  different wallpapers one has to rule, and the ruler is the one
    //  on the screen the island lives on: it is what you are looking
    //  at when the bar tints.
    function fondoDeReferencia() {
        const p = K4.Isla.pantalla
        const propio = p && p.length > 0 ? fondoDe(p) : ""
        return propio.length > 0 ? propio : wallpaper
    }

    property var paletaSacada: []

    K4.Process {
        id: sacaColores
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            const lineas = String(texto).split("\n")
            const cols = []
            for (let i = 0; i < lineas.length; ++i) {
                //  «   8392: (39,39,113) #272771 srgb(39,39,113)»
                const m = lineas[i].match(/^\s*(\d+):\s*\(\s*(\d+),\s*(\d+),\s*(\d+)/)
                if (!m)
                    continue
                cols.push({ peso: parseInt(m[1], 10), r: +m[2], g: +m[3], b: +m[4] })
            }
            if (cols.length === 0)
                return
            self.paletaSacada = cols
            self.repartirPaleta(cols)
        }
    }

    function sacarPaleta() {
        if (!paletaAuto)
            return
        const fondo = fondoDeReferencia()
        if (fondo.length === 0)
            return
        //  From a video or a GIF, its poster: magick would open the
        //  whole video to pull one frame, and the poster is already
        //  made.
        const fuente = esQuieto(fondo) ? fondo : posterDe(fondo)
        sacaColores.running = false
        //  Cropped to the center and to 200×200 before counting: it
        //  is much faster and the result does not change — what rules
        //  in a wallpaper are the masses of color, not stray corner
        //  pixels.
        sacaColores.command = ["sh", "-c",
            "[ -f \"$1\" ] || exit 0; magick \"$1\" -resize 200x200^"
            + " -gravity center -extent 200x200 -colors 8 -depth 8"
            + " -format %c histogram:info:-", "sh", fuente]
        sacaColores.running = true
    }

    //  ── from a list of colors to an ambiance ─────────────────────
    //
    //  The most frequent will not do: in most wallpapers it is a gray
    //  or a near-black, and a gray accent is no accent. What is
    //  searched for is the one with the most COLOR and enough
    //  weight, and the extremes are discarded — near-black does not
    //  show on the bar and near-white eats the text.
    function _hsv(c) {
        const r = c.r / 255, g = c.g / 255, b = c.b / 255
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b)
        return { v: mx, s: mx <= 0 ? 0 : (mx - mn) / mx }
    }

    function repartirPaleta(cols) {
        let total = 0
        for (let i = 0; i < cols.length; ++i)
            total += cols[i].peso

        let mejor = null, mejorNota = -1
        for (let i = 0; i < cols.length; ++i) {
            const c = cols[i]
            const h = _hsv(c)
            if (h.v < 0.18 || h.v > 0.94 || h.s < 0.12)
                continue
            //  The score rewards color and hardly punishes weight: an
            //  accent covering 5 % of the wallpaper is still that
            //  wallpaper's accent, and rewarding weight always picked
            //  the sky or the wall.
            const nota = h.s * (0.55 + 0.45 * Math.min(1, c.peso / total * 4))
            if (nota > mejorNota) {
                mejorNota = nota
                mejor = c
            }
        }
        //  With no usable color —a black and white wallpaper— whatever
        //  was there stays: inventing an accent is worse than having
        //  none.
        if (!mejor)
            return

        const base = Qt.rgba(mejor.r / 255, mejor.g / 255, mejor.b / 255, 1)
        accentFrom = Qt.lighter(base, 1.25)
        accentTo = Qt.darker(base, 1.9)
        //  The inactive one must READ as off next to the active one,
        //  so it loses color besides light: darkening alone leaves two
        //  borders of the same tone and one cannot tell which holds
        //  focus.
        const gris = (mejor.r + mejor.g + mejor.b) / 3 / 255
        inactive = Qt.rgba((mejor.r / 255 * 0.35 + gris * 0.65) * 0.75,
                           (mejor.g / 255 * 0.35 + gris * 0.65) * 0.75,
                           (mejor.b / 255 * 0.35 + gris * 0.65) * 0.75, 1)
        dirty = false
        preset = "fondo"
        apply()
        saveState()

        //  And the bar. The strength is low on purpose: the island is
        //  black and must stay so — this is an ambiance, not a coat of
        //  paint. The house ceiling is 0.45 and half of it is plenty
        //  here.
        K4.Tema.tintar("hyprtheme", base, 0.22, 0)
    }

    readonly property var presets: [
        { id: "cachyos", name: "CachyOS",  from: "#82dccc", to: "#007d6f", inactive: "#798bb2" },
        { id: "noche",   name: "Night",    from: "#5e5ce6", to: "#1c1c3a", inactive: "#3a3a4c" },
        { id: "ambar",   name: "Amber",    from: "#ff9f0a", to: "#c1440e", inactive: "#5c4a3a" },
        { id: "malva",   name: "Mauve",    from: "#bf5af2", to: "#5e2b8a", inactive: "#4a3a5c" },
        { id: "menta",   name: "Mint",    from: "#30d158", to: "#0a6b3d", inactive: "#3a5c48" },
        { id: "acero",   name: "Steel",    from: "#98a5b8", to: "#3a4654", inactive: "#4a5462" }
    ]

    function applyPreset(id) {
        for (let i = 0; i < presets.length; ++i) {
            if (presets[i].id !== id)
                continue

            //  Choosing a preset is choosing by hand: whoever does it
            //  does not want the next wallpaper stepping on it.
            paletaAuto = false
            K4.Tema.destintar("hyprtheme")
            preset = id
            accentFrom = presets[i].from
            accentTo = presets[i].to
            inactive = presets[i].inactive
            dirty = false
            apply()
            return
        }
    }

    // ── color → the format Hyprland expects ──────────────────────
    // hl.config wants "rgba(rrggbbaa)"; QML gives "#rrggbb" or
    // "#aarrggbb".
    function hypr(color) {
        const hex = String(color)
        if (hex.length === 9)                       // #aarrggbb
            return "rgba(" + hex.substring(3) + hex.substring(1, 3) + ")"
        return "rgba(" + hex.substring(1) + "ff)"   // #rrggbb
    }

    // ── the Lua describing the theme ──────────────────────────────
    function luaBody() {
        return 'hl.config({\n'
            + '    general = {\n'
            + '        gaps_in = ' + gapsIn + ',\n'
            + '        gaps_out = ' + gapsOut + ',\n'
            + '        border_size = ' + borderSize + ',\n'
            + '        col = {\n'
            + '            active_border = { colors = { "' + hypr(accentFrom) + '", "'
                + hypr(accentTo) + '" }, angle = ' + angle + ' },\n'
            + '            inactive_border = "' + hypr(inactive) + '",\n'
            + '        },\n'
            + '    },\n'
            + '    decoration = {\n'
            + '        rounding = ' + rounding + ',\n'
            + '        active_opacity = ' + activeOpacity.toFixed(2) + ',\n'
            + '        inactive_opacity = ' + inactiveOpacity.toFixed(2) + ',\n'
            + '        blur = {\n'
            + '            enabled = ' + (blur ? "true" : "false") + ',\n'
            + '            size = ' + blurSize + ',\n'
            + '            passes = ' + blurPasses + ',\n'
            + '        },\n'
            + '        shadow = { enabled = ' + (shadow ? "true" : "false") + ' },\n'
            + '    },\n'
            + '})\n\n'
            + 'hl.animation({ leaf = "global", enabled = ' + (animEnabled ? "true" : "false")
                + ', speed = ' + animSpeed + ', bezier = "quick" })\n'
    }

    // ── applying live ──────────────────────────────────────────────
    //
    //  What waits its turn: the last step of a drag can arrive while
    //  the previous `hyprctl eval` is still alive, and a
    //  `running = true` there is a no-op that would eat that step.
    //  It waits for `onTerminado`.
    property bool applyPendiente: false

    function apply() {
        evalProcess.command = ["hyprctl", "eval", luaBody()]
        if (evalProcess.running)
            applyPendiente = true
        else
            evalProcess.running = true
        saveState()
    }

    // ── persisting ────────────────────────────────────────────────
    function persist() {
        themeView.setText(
            '-- Generated by k4 · HyprTheme module.\n'
            + '-- Do not edit by hand: it is rewritten every time you save from the bar.\n'
            + '-- To revert: delete this file and its require line from hyprland.lua.\n\n'
            + luaBody())

        ensureRequire()
        saveState()
        _refrescarPersistido()
    }

    // Appends the require at the end of hyprland.lua if missing. Last
    // on purpose: what applies later is what rules.
    function ensureRequire() {
        const current = entryView.text()
        if (current.length === 0 || current.indexOf("config.k4-theme") !== -1)
            return

        entryView.setText(current.replace(/\s*$/, "")
            + '\n\n-- k4: theme managed from the bar (must stay last)\n'
            + 'require("config.k4-theme")\n')
    }

    function isPersisted() {
        return entryView.text().indexOf("config.k4-theme") !== -1
    }

    //  The badge in every section binds to THIS, not to `isPersisted()`:
    //  a method result is not a notifiable, and a binding that calls one
    //  never re-evaluates — the badge kept saying «session only» after a
    //  save until the whole motor was rebuilt. It is refreshed wherever
    //  the file can change: on load, and after `persist()`.
    property bool persistido: false

    function _refrescarPersistido() {
        persistido = isPersisted()
    }

    // ── own state, to reopen with the same values ─────────────────
    function saveState() {
        stateView.setText(JSON.stringify({
            preset: preset,
            accentFrom: String(accentFrom),
            accentTo: String(accentTo),
            inactive: String(inactive),
            angle: angle,
            gapsIn: gapsIn, gapsOut: gapsOut, borderSize: borderSize, rounding: rounding,
            blur: blur, blurSize: blurSize, blurPasses: blurPasses,
            activeOpacity: activeOpacity, inactiveOpacity: inactiveOpacity, shadow: shadow,
            animEnabled: animEnabled, animSpeed: animSpeed,
            wallpaper: wallpaper,
            wallpapers: fondos,
            extras: extras,
            transition: transicion,
            autoPalette: paletaAuto,
            dirty: dirty
        }, null, 2))
    }

    function loadState() {
        const raw = stateView.text()
        if (raw.length === 0)
            return

        let s
        try {
            s = JSON.parse(raw)
        } catch (e) {
            return
        }

        preset = s.preset !== undefined ? s.preset : preset
        accentFrom = s.accentFrom !== undefined ? s.accentFrom : accentFrom
        accentTo = s.accentTo !== undefined ? s.accentTo : accentTo
        inactive = s.inactive !== undefined ? s.inactive : inactive
        angle = s.angle !== undefined ? s.angle : angle
        gapsIn = s.gapsIn !== undefined ? s.gapsIn : gapsIn
        gapsOut = s.gapsOut !== undefined ? s.gapsOut : gapsOut
        borderSize = s.borderSize !== undefined ? s.borderSize : borderSize
        rounding = s.rounding !== undefined ? s.rounding : rounding
        blur = s.blur !== undefined ? s.blur : blur
        blurSize = s.blurSize !== undefined ? s.blurSize : blurSize
        blurPasses = s.blurPasses !== undefined ? s.blurPasses : blurPasses
        activeOpacity = s.activeOpacity !== undefined ? s.activeOpacity : activeOpacity
        inactiveOpacity = s.inactiveOpacity !== undefined ? s.inactiveOpacity : inactiveOpacity
        shadow = s.shadow !== undefined ? s.shadow : shadow
        animEnabled = s.animEnabled !== undefined ? s.animEnabled : animEnabled
        animSpeed = s.animSpeed !== undefined ? s.animSpeed : animSpeed
        wallpaper = s.wallpaper !== undefined ? s.wallpaper : wallpaper
        //  Keys are English now; the Spanish trio is the pre-rename file
        //  saying something — both are honored, new wins.
        const fondosLeidos = (s.wallpapers !== undefined ? s.wallpapers : s.fondos)
        fondos = (fondosLeidos && typeof fondosLeidos === "object") ? fondosLeidos : ({})
        //  Checked against the list: a hand-written file with anything
        //  else would leave an effect nobody paints, that is, a
        //  wallpaper change left half done without saying why.
        extras = (s.extras && s.extras.length !== undefined) ? s.extras : []
        const transicionLeida = (s.transition !== undefined ? s.transition : s.transicion)
        if (transicionLeida && transiciones.indexOf(transicionLeida) >= 0)
            transicion = transicionLeida
        const paletaLeida = (s.autoPalette !== undefined ? s.autoPalette : s.paletaAuto)
        if (paletaLeida !== undefined)
            paletaAuto = !!paletaLeida
        //  And on loading it is remade, since the tint lives in memory
        //  and does not survive a bar restart.
        if (paletaAuto)
            sacarPaleta()
        dirty = s.dirty === true

        //  The floor is restored on load: swaybg does not survive a
        //  session restart and what is underneath must be what was
        //  chosen.
        ponerSuelo()

        // If the daemon detector finished before the state was read,
        // there will be no wallTool change to fire the application;
        // that initialization order is covered too.
        if (wallTool.length > 0 && wallpaper.length > 0)
            applyWallpaper(wallpaper)
    }

    // ── wallpaper ─────────────────────────────────────────────────
    // The swww project renamed itself to awww, so either is
    // accepted; swaybg is plan C: no transitions and it needs
    // relaunching.
    property string wallTool: ""       // "awww" | "swww" | "swaybg" | ""

    //  What the scan found, and what you brought yourself.
    //
    //  Kept by PATH and not by copying the file. Copying would be
    //  more robust —a wallpaper on a USB stick stops existing when
    //  unplugged— but it would also silently duplicate a
    //  three-hundred-megabyte video because you dragged it onto a
    //  grid. If the path stops existing, it drops off the next scan
    //  on its own and that is that.
    property var encontrados: []
    property var extras: []

    //  Yours first: if you went to the trouble of bringing it, do not
    //  go looking for it later among forty-five others.
    readonly property var wallpapers: {
        const fuera = []
        for (let i = 0; i < extras.length; ++i)
            fuera.push(extras[i])
        for (let j = 0; j < encontrados.length; ++j)
            if (extras.indexOf(encontrados[j]) < 0)
                fuera.push(encontrados[j])
        return fuera
    }

    //  ── bringing one from outside ────────────────────────────────
    //
    //  Through the system dialog and not by dragging, and it is not
    //  the first option tried: the dragging one was written and
    //  cannot work HERE. This module closes when the mouse leaves
    //  (`closeOnHoverExit`), so to go get the file you have to
    //  leave, and once out there is nowhere to drop it. A surface
    //  that closes on losing the pointer cannot be a drag target,
    //  however well written the `DropArea`.
    //
    //  Zenity also brings a preview, which for choosing a wallpaper
    //  is exactly what is needed: a wallpaper is recognized by
    //  looking at it.
    property bool eligiendo: false

    K4.Process {
        id: selectorFondo
        //  While the dialog is open the island steps aside: it rides
        //  a layer above everything and the selector would come out
        //  underneath it, where it can neither be seen nor clicked.
        onArrancado: { self.eligiendo = true; Island.abrirDialogo() }
        onTerminado: { self.eligiendo = false; Island.cerrarDialogo() }
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n",
                  "--title=" + "Choose a background",
                  "--file-filter=" + "Backgrounds"
                  + " | *.jpg *.jpeg *.png *.webp *.avif *.gif *.apng"
                  + " *.mp4 *.webm *.mkv *.mov *.m4v"]

        onSalida: function (texto) {
            const rutas = String(texto).trim().split("\n")
                .filter(function (r) { return r.length > 0 })
            //  Empty means you hit cancel, which is not a failure.
            if (rutas.length === 0)
                return
            if (self.sumarFondos(rutas) > 0)
                self.ponerEnElegida(self.extras[0])
        }
    }

    function elegirFondo() {
        if (!selectorFondo.running)
            selectorFondo.running = true
    }

    //  And removing it. Being able to add without being able to
    //  remove is a dead end: a path that no longer exists keeps
    //  showing a broken thumbnail forever. It is only taken off the
    //  list; the file is not touched, it is not ours.
    function quitarFondo(ruta) {
        const l = extras.filter(function (x) { return x !== ruta })
        if (l.length === extras.length)
            return false
        extras = l
        saveState()
        return true
    }

    //  Add what was dropped. Returns how many got in, which is what
    //  the screen needs to say something sensible when none do.
    function sumarFondos(rutas) {
        const nuevos = []
        for (let i = 0; i < rutas.length; ++i) {
            const r = String(rutas[i])
            if (!Fondos.admitido(r) || extras.indexOf(r) >= 0)
                continue
            nuevos.push(r)
        }
        if (nuevos.length === 0)
            return 0
        //  A NEW container: mutating the array does not repaint the
        //  grid.
        extras = nuevos.concat(extras)
        saveState()
        prepararPosters()
        return nuevos.length
    }

    //  Where to look, what to skip and what counts as a wallpaper: one list
    //  of each, kept by Fondos — the service this grid and Ajustes both read,
    //  so the two can never drift apart again. The old copies had already
    //  drifted: duplicated entries, and the Spanish-named picture folders
    //  only Fondos knew about.
    readonly property var wallDirs: Fondos.carpetas
    readonly property var carpetasFuera: Fondos.carpetasFuera
    readonly property var extensionesFondo: Fondos.extensiones

    //  A wallpaper's thumbnail: the image itself if still, and the
    //  cached poster if it moves. `posterSello` is in the count on
    //  purpose: a file path does not change when the file appears,
    //  so without something moving the binding a video's thumbnail
    //  would stay broken until you closed and reopened.
    property int posterSello: 0
    function miniaturaDe(ruta) {
        if (esQuieto(ruta))
            return ruta
        return posterSello >= 0 ? posterDe(ruta) : ""
    }

    //  The posters, all in one go and in ONE process.
    //
    //  One per file would be thirty ffmpegs fighting for the CPU
    //  exactly when you just opened the screen and want to see it.
    //  In a queue, and one that already exists is not touched.
    K4.Process {
        id: cocinaPosters
        onTerminado: self.posterSello += 1
    }

    function prepararPosters() {
        const ordenes = []
        for (let i = 0; i < wallpapers.length; ++i) {
            const r = wallpapers[i]
            if (esQuieto(r))
                continue
            const d = posterDe(r)
            ordenes.push("[ -f " + JSON.stringify(d) + " ] || ffmpeg -v error -y"
                         + " -ss 1 -i " + JSON.stringify(r)
                         + " -frames:v 1 -vf scale=480:-1 " + JSON.stringify(d)
                         + " >/dev/null 2>&1")
        }
        if (ordenes.length === 0)
            return
        cocinaPosters.running = false
        cocinaPosters.command = ["sh", "-c",
            "mkdir -p " + JSON.stringify(cachePosters) + "; " + ordenes.join("; ")]
        cocinaPosters.running = true
    }

    //  Which screen the Settings screen is working on. Empty means
    //  «all»: the common wallpaper goes up and the individual choices
    //  are forgotten.
    property string pantallaElegida: ""

    function ponerEnElegida(ruta) {
        if (pantallaElegida.length > 0) {
            ponerFondoEn(pantallaElegida, ruta)
            return
        }
        //  All: the common wallpaper rules and per-screen choices get
        //  in the way, because `fondoDe` prefers them and the change
        //  would not show on monitors that had one.
        wallpaper = ruta
        fondos = ({})
        saveState()
        ponerSuelo()
        sacarPaleta()
    }

    //  ── the floor ────────────────────────────────────────────────
    //
    //  swaybg stays underneath with each screen's still frame. What
    //  the bar draws lives as long as the bar lives, and between
    //  entering the session and quickshell starting there is a while
    //  with nobody; if the wallpaper is black there, we worsened
    //  something that worked. For a video or a GIF, the floor is its
    //  poster (see `posterDe`).
    //
    //  One call with every screen: swaybg accepts repeating `-o/-i`,
    //  and killing and raising it twice —once per monitor— leaves the
    //  second without the first image, because the new process keeps
    //  both outputs.
    //  The screens there are, asked of the canvas and not of
    //  `fondos`.
    //
    //  Walking `fondos`'s keys only yields those with a choice of
    //  their OWN, and the rest were left without a floor: with two
    //  monitors and a wallpaper chosen on one, swaybg started with
    //  bare `-o HDMI-A-1` and the other was left wallpaper-less
    //  whenever the bar was not there. Whoever knows how many
    //  screens there are is the canvas, which is one per each.
    function pantallasConocidas() {
        const l = []
        for (let i = 0; i < lienzo.instances.length; ++i) {
            const t = lienzo.instances[i]
            if (t && t.cual && t.cual.length > 0)
                l.push(t.cual)
        }
        return l
    }

    //  The floor is in no hurry —it is for when the bar is NOT
    //  there— so it is debounced. Without this, two wallpaper changes
    //  in a row left TWO swaybg alive: the second's `pkill` came out
    //  before the first reached existing, and the desktop ended up
    //  with two daemons fighting over the same layer. Measured:
    //  `pgrep -c -x swaybg` gave 2.
    property Timer esperaSuelo: Timer {
        interval: 300
        onTriggered: self.ponerSueloYa()
    }

    function ponerSuelo() { esperaSuelo.restart() }

    function ponerSueloYa() {
        const trozos = []
        const pantallas = pantallasConocidas()
        for (let i = 0; i < pantallas.length; ++i) {
            const suelo = sueloDe(fondoDe(pantallas[i]))
            if (suelo.length > 0)
                trozos.push("-o " + JSON.stringify(pantallas[i])
                            + " -i " + JSON.stringify(suelo) + " -m fill")
        }
        //  And if the canvas does not exist yet —at startup—, the
        //  usual one for all, which is exactly what this did before.
        if (trozos.length === 0 && wallpaper.length > 0)
            trozos.push("-i " + JSON.stringify(sueloDe(wallpaper)) + " -m fill")
        if (trozos.length === 0)
            return

        //  `pkill -x`, never `-f`: with `-f` the pattern also matches
        //  this very command's line and kills itself before reaching
        //  swaybg.
        //
        //  And a short wait before raising the new one: killing is
        //  not instantaneous, and starting while the old one dies
        //  leaves both.
        K4.Sistema.lanzar(["sh", "-c",
            "pkill -x swaybg 2>/dev/null; sleep 0.2; swaybg " + trozos.join(" ")
            + " >/dev/null 2>&1 &"])
    }

    //  Which still image stands for a wallpaper. For a photo,
    //  itself; for what moves, its cached poster — and if it does not
    //  exist yet it is sent to make and for now no floor is set,
    //  which is better than setting an empty one.
    readonly property string cachePosters:
        K4.Sistema.entorno("HOME") + "/.cache/k4/fondos"

    function esQuieto(ruta) {
        return !/\.(mp4|webm|mkv|mov|m4v|avi|gif|webp|apng)$/i.test(String(ruta))
    }

    function posterDe(ruta) {
        return cachePosters + "/" + Qt.md5(String(ruta)) + ".png"
    }

    //  ── the video, cut to the screen's measure ───────────────────
    //
    //  A 4K video on a 1920 monitor is decoded and uploaded whole to
    //  show EXACTLY the same: four times the pixels that fit. It is
    //  the same arithmetic the photo already did with `sourceSize`
    //  in Capa.qml —«a 6000 px photo on a 1920 monitor is 140 MB of
    //  texture»— and the video lacked that half.
    //
    //  Measured on the process itself, with a 3840×2160 clip at
    //  47 Mbps and the bar folded:
    //
    //      the original   27 % of one core  ·  1 GB of memory
    //      the 1920 copy  15 %              ·  553 MB
    //
    //  And it is not the decoding: ffmpeg's threads add up to 2 % in
    //  both cases. What costs is presenting that frame.
    //
    //  The copy is made ONCE and lives in the cache. Until it is
    //  there the original keeps showing: a late wallpaper is worse
    //  than an expensive one.
    property var escalados: ({})        // "ruta|ancho" -> la copia, ya hecha
    property var escaladosPedidos: ({})

    //  The `gif|webp|apng` that `esQuieto` admits does NOT go here:
    //  an AnimatedImage paints that, not the player, and converting
    //  it to mp4 would change its type behind its back.
    function esVideo(ruta) {
        return /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(String(ruta))
    }

    function escaladoDe(ruta, ancho) {
        return cachePosters + "/" + Qt.md5(String(ruta)) + "-" + ancho + ".mp4"
    }

    //  What truly has to play. PURE read —the map is filled by the
    //  cooking below— so it can be asked from a binding without
    //  asking having effects.
    function videoAMedida(ruta, ancho) {
        const hecho = escalados[String(ruta) + "|" + ancho]
        return hecho ? hecho : String(ruta)
    }

    //  And this one does have an effect, so it is called from a
    //  handler and never from a binding: Capa.qml does it when the
    //  path or the screen changes.
    function pedirEscalado(ruta, ancho) {
        if (!esVideo(ruta) || !(ancho > 0))
            return
        const clave = String(ruta) + "|" + ancho
        if (escalados[clave] !== undefined || escaladosPedidos[clave])
            return
        escaladosPedidos[clave] = true
        juntarEscalados.restart()
    }

    //  Requests are gathered before cooking: with two monitors and
    //  a transition, this arrives four times in a row for the same
    //  thing.
    Timer {
        id: juntarEscalados
        interval: 400
        onTriggered: self.cocinarEscalados()
    }

    K4.Process {
        id: cocinaEscalados
        onSalida: function (texto) {
            const d = Object.assign({}, self.escalados)
            const lineas = String(texto).split("\n")
            for (let i = 0; i < lineas.length; ++i) {
                const partes = lineas[i].split("\t")
                if (partes.length === 2 && partes[1].length > 0)
                    d[partes[0]] = partes[1]
            }
            self.escalados = d
        }
    }

    function cocinarEscalados() {
        const claves = Object.keys(escaladosPedidos)
        if (claves.length === 0 || cocinaEscalados.running)
            return

        const ordenes = []
        for (let i = 0; i < claves.length; ++i) {
            const corte = claves[i].lastIndexOf("|")
            const ruta = claves[i].substring(0, corte)
            const ancho = claves[i].substring(corte + 1)
            ordenes.push([
                's=' + JSON.stringify(ruta),
                'd=' + JSON.stringify(escaladoDe(ruta, ancho)),
                'a=' + JSON.stringify(ancho),
                'k=' + JSON.stringify(claves[i]),
                //  Measured before touching anything: a video that
                //  already fits is left alone, since scaling up is
                //  spending to make things worse.
                'if [ ! -f "$d" ]; then',
                '  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$s" 2>/dev/null | head -1)',
                '  case "$w" in ""|*[!0-9]*) w=0 ;; esac',
                //  To a temporary file then `mv`: renaming is atomic,
                //  so if two screens ask for the same at once neither
                //  gets to read a half-written copy.
                //  In ONE line: joined with newlines, each piece would
                //  be a loose command and the `&&` would chain
                //  nothing.
                '  if [ "$w" -gt "$a" ]; then ffmpeg -nostdin -v error -y -i "$s"'
                + ' -vf "scale=$a:-2" -c:v libx264 -preset veryfast -crf 23 -an'
                + ' "$d.parcial.mp4" && mv -f "$d.parcial.mp4" "$d"; fi',
                'fi',
                '[ -f "$d" ] && printf "%s\\t%s\\n" "$k" "$d"'
            ].join("\n"))
        }

        escaladosPedidos = ({})
        cocinaEscalados.running = false
        //  In a queue and in ONE process, like the posters: two 4K
        //  ffmpegs at once eat the machine exactly when you just
        //  changed the wallpaper.
        cocinaEscalados.command = ["sh", "-c",
            //  And a `:` at the end to exit zero: if the last copy is
            //  missing, its `[ -f ]` would set the whole script's
            //  exit code.
            "mkdir -p " + JSON.stringify(cachePosters) + "\n"
            + ordenes.join("\n") + "\n:"]
        cocinaEscalados.running = true
    }

    property var postersPedidos: ({})

    function sueloDe(ruta) {
        if (!ruta || ruta.length === 0)
            return ""
        if (esQuieto(ruta))
            return ruta

        const destino = posterDe(ruta)
        if (postersPedidos[destino] === true)
            return destino
        postersPedidos[destino] = true

        //  The second frame, not the first: many videos start black,
        //  and a black poster is the same as no poster.
        K4.Sistema.lanzar(["sh", "-c",
            "mkdir -p " + JSON.stringify(cachePosters)
            + "; [ -f " + JSON.stringify(destino) + " ] || ffmpeg -v error -y"
            + " -ss 1 -i " + JSON.stringify(ruta) + " -frames:v 1 "
            + JSON.stringify(destino) + " >/dev/null 2>&1"])
        return destino
    }

    function applyWallpaper(path) {
        if (path.length === 0 || wallTool.length === 0)
            return false

        if (wallTool === "swaybg") {
            // swaybg cannot reload: it is killed and another raised.
            K4.Sistema.lanzar(["sh", "-c",
                "pkill -x swaybg 2>/dev/null || true; swaybg -i "
                + JSON.stringify(path) + " -m fill >/dev/null 2>&1 &"])
        } else {
            // awww and swww take the same command. If the daemon is
            // not up yet, it is started and the image retried.
            K4.Sistema.lanzar(["sh", "-c",
                wallTool + " img " + JSON.stringify(path)
                + " --transition-type grow --transition-fps 60 >/dev/null 2>&1"
                + " || { " + wallTool + "-daemon >/dev/null 2>&1 & sleep 1; "
                + wallTool + " img " + JSON.stringify(path) + " >/dev/null 2>&1; }"])
        }
        return true
    }

    function setWallpaper(path) {
        if (path.length === 0)
            return

        // The click is the whole action: the session is updated and
        // only the wallpaper's state is written at once, without
        // saving other theme tweaks by rebound. onWallToolChanged
        // will apply it when ready.
        wallpaper = path
        saveState()
        applyWallpaper(path)
    }

    function refreshWallpapers() {
        const args = ["find"]
        for (let i = 0; i < wallDirs.length; ++i)
            args.push(wallDirs[i])
        args.push("-maxdepth")
        args.push("3")
        //  Las carpetas excluidas se podan ANTES de mirar ficheros: con un
        //  `-not -path` cada fichero de dentro se examina igualmente, y en una
        //  carpeta de capturas con cientos eso es recorrer para descartar.
        for (let i = 0; i < carpetasFuera.length; ++i) {
            args.push("(")
            args.push("-type"); args.push("d")
            args.push("-name"); args.push(carpetasFuera[i])
            args.push("-prune")
            args.push(")")
            args.push("-o")
        }
        args.push("(")
        args.push("-type"); args.push("f")
        args.push("(")
        for (let j = 0; j < extensionesFondo.length; ++j) {
            if (j > 0)
                args.push("-o")
            args.push("-iname")
            args.push("*." + extensionesFondo[j])
        }
        args.push(")")
        args.push("-print")
        args.push(")")
        wallScan.command = args
        wallScan.running = true
    }

    //  The wallpaper scan is asked for by whoever shows them —the
    //  grid, on becoming visible— and not a tab change, which no
    //  longer exists. What remains here is reapplying if the tool
    //  appears after the wallpaper.
    onWallToolChanged: if (wallTool.length > 0 && wallpaper.length > 0)
        applyWallpaper(wallpaper)


    // ── archivos ──────────────────────────────────────────────────
    K4.Fichero { id: themeView; path: self.themeFile }
    //  entryView: besides being the persist target, its text is what
    //  `persistido` is derived from — recomputed when it loads, so a
    //  fresh bar says the truth about yesterday's save.
    K4.Fichero {
        id: entryView
        path: self.entryFile
        blockLoading: true
        onLoaded: self._refrescarPersistido()
    }
    K4.Fichero { id: stateView; path: self.stateFile; blockLoading: true }

    K4.Process {
        id: evalProcess
        onTerminado: function (codigo) {
            if (self.applyPendiente) {
                self.applyPendiente = false
                evalProcess.running = true
            }
        }
    }

    K4.Process {
        // the state lives in ~/.local/state/k4, which may not exist
        // yet
        command: ["mkdir", "-p", K4.Paths.estado]
        running: true
        onTerminado: self.loadState()
    }

    K4.Process {
        id: toolScan
        command: ["sh", "-c",
            "command -v awww || command -v swww || command -v swaybg || true"]
        running: true

        onSalida: function (texto) {
            const found = texto.trim().split("\n")[0]
            if (found.length === 0)
                return
            self.wallTool = found.substring(found.lastIndexOf("/") + 1)
        }
    }

    K4.Process {
        id: wallScan

        onSalida: function (texto) {
            const found = texto.trim().split("\n").filter(function (p) { return p.length > 0 })
            found.sort()
            self.encontrados = found.slice(0, 200)
            self.prepararPosters()
        }
    }

    //  Whoever draws. It lives in the plugin and not in `view`
    //  because a view only exists while it holds the island, and the
    //  wallpaper must be set whether the module is open or not.
    Lienzo { id: lienzo; plugin: self }

    K4.Ipc {
        target: "k4.theme"
        //  The verb stays because it may be bound in Hyprland: it
        //  opens Settings, where what this configured now lives.
        function toggle(): void { PluginManager.abrirAplicacion("settings") }
        function apply(): void { self.apply() }
        function save(): void { self.persist() }
        function preset(id: string): void { self.applyPreset(id) }
        function wallpaper(path: string): void { self.setWallpaper(path) }

        //  ── the canvas, while it has no screen of its own ────────
        //
        //  Driven from here on purpose: this way the drawing part can
        //  be tested whole —video, GIF, photo, two monitors— before a
        //  single button exists, and without the interface
        //  conditioning what it does.
        function wallpaperOn(pantalla: string, ruta: string): void {
            self.ponerFondoEn(pantalla, ruta)
        }

        function wallpaperState(): string { return self.fondosEstado() }

        //  Change the transition with no screen yet. Returns what
        //  ended up set, so it does not have to be asked separately.
        //  The palette: on, off, and a look at what it drew.
        function palette(auto: string): string {
            if (auto === "si" || auto === "no") {
                self.paletaAuto = (auto === "si")
                if (self.paletaAuto)
                    self.sacarPaleta()
                else
                    K4.Tema.destintar("hyprtheme")
                self.saveState()
            }
            return JSON.stringify({ auto: self.paletaAuto,
                                    fuente: self.fondoDeReferencia(),
                                    from: String(self.accentFrom),
                                    to: String(self.accentTo),
                                    inactive: String(self.inactive),
                                    sacados: self.paletaSacada })
        }

        //  To test the dragging thing without dragging.
        function add(ruta: string): string {
            return JSON.stringify({ entraron: self.sumarFondos([ruta]),
                                    extras: self.extras })
        }

        function remove(ruta: string): string {
            return JSON.stringify({ quitado: self.quitarFondo(ruta),
                                    extras: self.extras })
        }

        function transition(cual: string): string {
            if (self.transiciones.indexOf(cual) >= 0) {
                self.transicion = cual
                self.saveState()
            }
            return self.transicion
        }
    }

    //  The canvas's state, in a plugin function and not only inside
    //  the IpcHandler: this way whoever loads it on their own —a test
    //  bench— can ask for it without fighting the live bar over the
    //  IPC name.
    function fondosEstado() {
        const salida = []
        for (let i = 0; i < lienzo.instances.length; ++i) {
            const t = lienzo.instances[i]
            if (t && typeof t.estado === "function")
                salida.push(t.estado())
        }
        return JSON.stringify({ telas: salida, guardado: self.fondos,
                                global: self.wallpaper })
    }

    //  ── the Settings pages this plugin ships ────────────────────
    //
    //  The Display family's working pages live here now, not in Settings:
    //  the engine that writes the Hyprland Lua owns the screens that drive
    //  it. Each one rides into Settings' sidebar through K4.Pagina, under
    //  the host's «Display» family, with its Save row inside — the page
    //  and its author leave together, which is the whole point: nothing
    //  renders a dead engine's knobs.
    K4.Pagina {
        plugin: "hyprtheme"
        name: "colour"
        titulo: "Colour"
        padre: "Display"
        glifo: 0xF03D8       // md-palette
        desc: "Where the colours come from: the wallpaper, or a preset you pick."
        claves: ["color", "colour", "colores", "preset", "acento",
                 "accent", "paleta", "palette", "tema", "theme",
                 "degradado"]
        componente: Component {
            ColumnLayout {
                spacing: 0
                AjustesTema {
                    motor: self
                    Layout.fillWidth: true
                }
                GuardarTema {
                    motor: self
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                }
            }
        }
    }

    K4.Pagina {
        plugin: "hyprtheme"
        name: "windows"
        titulo: "Windows"
        padre: "Display"
        glifo: 0xF10AC
        desc: "Borders, gaps and corners of Hyprland's windows."
        claves: ["ventanas", "windows", "borde", "border", "hueco",
                 "huecos", "gap", "gaps", "redondeo", "rounding",
                 "esquina", "esquinas"]
        componente: Component {
            ColumnLayout {
                spacing: 0
                AjustesVentanas {
                    motor: self
                    Layout.fillWidth: true
                }
                GuardarTema {
                    motor: self
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                }
            }
        }
    }

    K4.Pagina {
        plugin: "hyprtheme"
        name: "effects"
        titulo: "Effects"
        padre: "Display"
        glifo: 0xF00B5
        desc: "Blur, opacity, shadows and animations."
        claves: ["efectos", "effects", "blur", "desenfoque", "opacidad",
                 "opacity", "sombra", "sombras", "shadow", "animacion",
                 "animaciones", "animation"]
        componente: Component {
            ColumnLayout {
                spacing: 0
                AjustesEfectos {
                    motor: self
                    Layout.fillWidth: true
                }
                GuardarTema {
                    motor: self
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                }
            }
        }
    }

}
