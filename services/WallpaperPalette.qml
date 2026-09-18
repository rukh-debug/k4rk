pragma Singleton

// Native wallpaper selection, application and palette extraction.

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import "../core"
import K4 as K4

Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME")
        + "/.local/state/k4/wallpaper-palette.json"
    property string source: ""
    readonly property string wallpaper: source
    property string wallTool: ""
    property string pantallaElegida: ""
    readonly property var transiciones: ["fade", "grow", "wave", "none"]
    property string transicion: "fade"
    property string applyStatus: "idle"
    property string applyError: ""
    property bool applyPending: false
    property string applyingSource: ""
    property string applyingTool: ""
    property string playingVideoSource: ""
    signal retryVideo()
    readonly property bool supportsTransitions: (wallTool === "awww" || wallTool === "swww")
        && !isMoving(source)

    //  ── palette styles ────────────────────────────────────────────
    //
    //  "sampled" is the classic: the magick histogram and a saturated
    //  pick. The rest are matugen's Material You schemes — the ids it
    //  takes after "scheme-" — and they run through matugen when the
    //  binary is there. An empty `scheme` means «never chosen»: the
    //  effective style then follows the tool — tonal when matugen is
    //  here, the sampled classic when it is not.
    readonly property var schemes: [
        { id: "sampled",     nombre: "Sampled" },
        { id: "tonal-spot",  nombre: "Tonal" },
        { id: "vibrant",     nombre: "Vibrant" },
        { id: "monochrome",  nombre: "Monochrome" },
        { id: "neutral",     nombre: "Neutral" },
        { id: "content",     nombre: "Content" },
        { id: "expressive",  nombre: "Expressive" },
        { id: "fidelity",    nombre: "Fidelity" },
        { id: "rainbow",     nombre: "Rainbow" },
        { id: "fruit-salad", nombre: "Fruit salad" }
    ]
    property string scheme: ""
    property bool matugenOk: false
    readonly property string activeScheme: scheme.length > 0
        ? scheme : (matugenOk ? "tonal-spot" : "sampled")
    //  Which pipeline an extraction run belongs to. A superseded
    //  process still fires its collector with half its output; the
    //  flag is how a stale finish learns to keep quiet.
    property string pipeline: ""
    //  A scheme switch while its own pipeline is still running cannot
    //  restart the process (`command` only applies to the next launch),
    //  so the request waits here the way `apply()` queues behind
    //  `applicator`. `runningScheme`/`runningSource` mark what the live
    //  run is working on, so its late output cannot paint over the
    //  newly wanted variant.
    property bool extractPending: false
    property string runningScheme: ""
    property string runningSource: ""

    function schemeIdValido(id) {
        for (let i = 0; i < schemes.length; ++i)
            if (schemes[i].id === String(id))
                return true
        return false
    }

    property color accentFrom: "#82dccc"
    property color accentTo: "#007d6f"
    property color inactive: "#798bb2"
    property var extracted: []
    property bool ready: false

    function select(path) {
        const next = String(path || "")
        if (next.length === 0)
            return
        source = next
        save()
        apply()
        extract()
    }

    function fondoDe(screen) { return source }
    function pantallasConocidas() { return [] }
    function ponerEnElegida(path) { select(path) }
    function quitarFondo(path) { Fondos.quitar(path) }
    function isVideo(path) { return /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(path) }
    function isAnimated(path) { return /\.(gif|apng)$/i.test(path) }
    // awww handles animated images and transitions natively. Qt's media
    // surface is only needed for video formats the wallpaper daemon rejects.
    function isMoving(path) { return isVideo(path) }

    function apply() {
        if (source.length === 0)
            return
        if (applicator.running) {
            applyPending = true
            return
        }
        applyPending = false
        applyingSource = source
        applyingTool = isMoving(source) ? "video" : wallTool
        applyStatus = "applying"
        applyError = ""
        if (isMoving(source)) {
            if (playingVideoSource === source)
                applyStatus = "applied"
            else
                retryVideo()
            // Remove external background layers before the native animated
            // surface starts decoding its first frame.
            applicator.command = ["sh", "-c",
                "pkill -x swaybg 2>/dev/null || true; awww kill 2>/dev/null || true;"
                + " swww kill 2>/dev/null || true"]
            applicator.running = true
            return
        }
        if (wallTool.length === 0) {
            applyStatus = "failed"
            applyError = "Install awww, swww or swaybg to apply wallpapers."
            return
        }
        if (wallTool === "swaybg") {
            applicator.command = ["sh", "-c", "pkill -x swaybg 2>/dev/null || true;"
                + " swaybg -i " + JSON.stringify(source) + " -m fill >/dev/null 2>&1 &"]
        } else {
            applicator.command = ["sh", "-c", "pkill -x swaybg 2>/dev/null || true; "
                + wallTool + " img "
                + JSON.stringify(source)
                + " --transition-type " + transicion
                + " --transition-fps 60 >/dev/null 2>&1"
                + " || { " + wallTool + "-daemon >/dev/null 2>&1 & sleep 1; "
                + wallTool + " img " + JSON.stringify(source)
                + " >/dev/null 2>&1; }"]
        }
        applicator.running = true
    }

    function elegirFondo() {
        if (!selector.running)
            selector.running = true
    }

    function save() {
        if (ready)
            state.setText(JSON.stringify({ source: source,
                                           transition: transicion,
                                           scheme: scheme }, null, 1))
    }

    function load() {
        try {
            const saved = JSON.parse(state.text())
            source = String(saved.source || "")
            if (transiciones.indexOf(saved.transition) >= 0)
                transicion = saved.transition
            if (schemeIdValido(saved.scheme))
                scheme = String(saved.scheme)
        } catch (error) {
        }
        //  First run after the theme plugin's removal: its state file
        //  still says which wallpaper and transition were in force, and
        //  an upgrade must not forget the desktop. Read once, keep ours.
        if (source.length === 0) {
            try {
                const viejo = JSON.parse(anterior.text())
                source = String(viejo.wallpaper || "")
                if (transiciones.indexOf(viejo.transition) >= 0)
                    transicion = viejo.transition
                if (source.length > 0)
                    save()
            } catch (error) {
            }
        }
        ready = true
        apply()
        extract()
    }

    function hsv(color) {
        const r = color.r / 255, g = color.g / 255, b = color.b / 255
        const max = Math.max(r, g, b), min = Math.min(r, g, b)
        return { value: max, saturation: max <= 0 ? 0 : (max - min) / max }
    }

    function distribute(colors) {
        let total = 0
        for (let i = 0; i < colors.length; ++i)
            total += colors[i].weight

        let best = null, score = -1
        for (let i = 0; i < colors.length; ++i) {
            const color = colors[i]
            const value = hsv(color)
            if (value.value < 0.18 || value.value > 0.94 || value.saturation < 0.12)
                continue
            const next = value.saturation * (0.55 + 0.45
                * Math.min(1, color.weight / total * 4))
            if (next > score) {
                score = next
                best = color
            }
        }
        if (!best)
            return

        const base = Qt.rgba(best.r / 255, best.g / 255, best.b / 255, 1)
        accentFrom = Qt.lighter(base, 1.25)
        accentTo = Qt.darker(base, 1.9)
        const gray = (best.r + best.g + best.b) / 3 / 255
        inactive = Qt.rgba((best.r / 255 * 0.35 + gray * 0.65) * 0.75,
                           (best.g / 255 * 0.35 + gray * 0.65) * 0.75,
                           (best.b / 255 * 0.35 + gray * 0.65) * 0.75, 1)
        if (Settings.wallpaperPalette)
            Theme.tintar("wallpaper", base, 0.22, 0)
    }

    //  Tint from the generated scheme rather than its source seed. The seed
    //  is identical across variants, while the dark primary container is the
    //  variant-specific accent intended for dark surfaces.
    function tintFromScheme(color) {
        if (Settings.wallpaperPalette)
            Theme.tintar("wallpaper", color, 0.22, 0)
    }

    function extract() {
        if (!Settings.wallpaperPalette || source.length === 0)
            return
        const wantMatugen = activeScheme !== "sampled" && matugenOk
        const wantPipeline = wantMatugen ? "matugen" : "magick"
        //  One pipeline owns the palette at a time: park the other.
        //  Its dying collector still fires, and `pipeline` keeps it quiet.
        if (wantMatugen)
            sampler.running = false
        else
            esquemador.running = false
        if ((wantMatugen ? esquemador.running : sampler.running)) {
            //  Same-pipeline switch while the old run owns the process:
            //  assigning `command` now would only change the NEXT launch,
            //  leaving the old variant to finish and paint over the new
            //  selection. Queue instead; `onExited` drains it.
            pipeline = wantPipeline
            extractPending = true
            return
        }
        startExtraction(wantPipeline)
    }

    function startExtraction(wantPipeline) {
        extractPending = false
        pipeline = wantPipeline
        runningScheme = activeScheme
        runningSource = source
        //  The poster decision is made HERE and not in a shell `case`:
        //  the glob `*.mp4` is case-sensitive, and an uppercase `.MP4`
        //  slipped past it straight into magick, which forked its own
        //  ffmpeg delegate to decode the video. A bar restart in the
        //  middle left that pair blocked on a dead pipe — forever.
        const needsPoster = isVideo(source) || isAnimated(source)
        //  A matugen scheme goes to matugen; everything else — the
        //  sampled classic, or a scheme with no matugen to run it —
        //  goes to the histogram. Whichever runs, the other is
        //  stopped: one pipeline owns the palette at a time.
        if (wantPipeline === "matugen") {
            sampler.running = false
            //  Same frame contract as the histogram pipeline: a video
            //  or an animation is sampled from its cached poster, and
            //  the poster is built here if it does not exist yet.
            //  `esq` is read before `set --` replaces the positionals.
            esquemador.command = ["timeout", "-k", "3", "30", "sh", "-c",
                "[ -f \"$1\" ] || exit 0;"
                + " esq=\"$4\";"
                + " if [ \"$3\" = \"1\" ]; then"
                + " mkdir -p \"$(dirname \"$2\")\";"
                + " [ -f \"$2\" ] || ffmpeg -nostdin -v error -y -ss 1 -i \"$1\""
                + " -frames:v 1 \"$2\" >/dev/null 2>&1;"
                + " set -- \"$2\"; fi;"
                + " [ -f \"$1\" ] || exit 0;"
                + " matugen image \"$1\" -t \"scheme-$esq\" -m dark"
                + " --dry-run -j hex --prefer saturation",
                "sh", source, Fondos.posterDe(source), needsPoster ? "1" : "0",
                activeScheme]
            esquemador.running = true
            return
        }
        esquemador.running = false
        //  `timeout` on both levels so no sampler run can outlive its
        //  welcome: the outer one bounds the whole pipeline, the inner
        //  one SIGKILLs magick, whose dying fds unblock any delegate.
        sampler.command = ["timeout", "-k", "3", "30", "sh", "-c",
            "[ -f \"$1\" ] || exit 0;"
            + " if [ \"$3\" = \"1\" ]; then"
            + " mkdir -p \"$(dirname \"$2\")\";"
            + " [ -f \"$2\" ] || ffmpeg -nostdin -v error -y -ss 1 -i \"$1\""
            + " -frames:v 1 \"$2\" >/dev/null 2>&1;"
            + " set -- \"$2\"; fi;"
            + " [ -f \"$1\" ] || exit 0;"
            + " timeout -k 2 20 magick \"$1\" -resize 200x200^"
            + " -gravity center -extent 200x200 -colors 8 -depth 8"
            + " -format %c histogram:info:-",
            "sh", source, Fondos.posterDe(source), needsPoster ? "1" : "0"]
        sampler.running = true
    }

    //  A collector result is fresh only when nothing newer was asked
    //  for while it ran: same pipeline, same variant, same wallpaper.
    function extractionFresh(wantPipeline) {
        return pipeline === wantPipeline
            && !extractPending
            && runningScheme === activeScheme
            && runningSource === source
    }

    //  Drain a queued variant switch once the superseded run lands.
    //  Called from `onExited`, so the wanted process is free by now.
    function drainExtraction(wantPipeline) {
        if (pipeline !== wantPipeline)
            return
        if (!extractPending && runningScheme === activeScheme
                && runningSource === source)
            return
        if (!Settings.wallpaperPalette || source.length === 0) {
            extractPending = false
            return
        }
        Qt.callLater(root.extract)
    }

    onSourceChanged: {
        playingVideoSource = ""
        if (ready) extract()
    }
    onTransicionChanged: save()
    //  A new style is both a save and a re-derivation: the swatches
    //  and the tint follow the chip as it is pressed.
    onSchemeChanged: if (ready) { save(); extract() }

    Connections {
        target: Settings
        function onWallpaperPaletteChanged() {
            if (Settings.wallpaperPalette)
                root.extract()
            else
                Theme.destintar("wallpaper")
        }
    }

    FileView {
        id: state
        path: root.path
        blockLoading: true
    }

    //  The retired theme plugin's state, read once for migration.
    FileView {
        id: anterior
        path: Quickshell.env("HOME") + "/.local/state/k4/hyprtheme.json"
        blockLoading: true
    }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: root.load()
    }

    Process {
        id: toolScan
        command: ["sh", "-c", "command -v awww || command -v swww || command -v swaybg || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const found = String(this.text).trim().split("\n")[0]
                if (found.length > 0) {
                    root.wallTool = found.substring(found.lastIndexOf("/") + 1)
                    root.apply()
                }
            }
        }
    }

    Process {
        id: applicator
        onExited: function (code, status) {
            if (root.applyPending || root.applyingSource !== root.source) {
                Qt.callLater(root.apply)
                return
            }
            if (code !== 0) {
                root.applyStatus = "failed"
                root.applyError = "Could not apply this wallpaper. Check the file and try again."
            } else if (root.applyingTool !== "video") {
                // swaybg detaches: process launch alone cannot confirm the rendered image.
                root.applyStatus = root.applyingTool === "swaybg" ? "unverified" : "applied"
            }
        }
    }

    Process {
        id: selector
        command: ["zenity", "--file-selection", "--title=Choose a wallpaper",
                  "--file-filter=Wallpapers | *.jpg *.jpeg *.png *.webp *.avif *.gif *.apng"
                  + " *.mp4 *.webm *.mkv *.mov *.m4v"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = String(this.text).trim()
                if (path.length > 0) {
                    Fondos.sumar([path])
                    root.select(path)
                }
            }
        }
    }

    Process {
        id: sampler
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                //  A run stopped mid-flight by the other pipeline still
                //  finishes here with half a histogram; stale colors
                //  would overwrite the palette the winner is building.
                //  Same-pipeline supersedes count as stale too: the late
                //  variant must not paint over the newly picked one.
                if (!root.extractionFresh("magick"))
                    return
                const rows = String(this.text).split("\n")
                const colors = []
                for (let i = 0; i < rows.length; ++i) {
                    const match = rows[i].match(/^\s*(\d+):\s*\(\s*(\d+),\s*(\d+),\s*(\d+)/)
                    if (match)
                        colors.push({ weight: parseInt(match[1], 10), r: +match[2],
                                      g: +match[3], b: +match[4] })
                }
                if (colors.length > 0) {
                    root.extracted = colors
                    root.distribute(colors)
                }
            }
        }
        onExited: root.drainExtraction("magick")
    }

    //  The matugen pipeline: same contract as `sampler` — stdout in,
    //  palette out — but the payload is one JSON object. `--prefer
    //  saturation` picks the seed without a terminal to ask; the
    //  scheme itself is the tool's own doing.
    Process {
        id: esquemador
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.extractionFresh("matugen"))
                    return
                try {
                    const c = JSON.parse(String(this.text)).colors || {}
                    const hex = function (role) {
                        const entry = c[role]
                        if (!entry)
                            return ""
                        const v = entry.dark || entry.default
                        return v && v.color ? String(v.color) : ""
                    }
                    const from = hex("primary"), to = hex("primary_container")
                    if (from.length === 0 || to.length === 0)
                        return
                    root.accentFrom = from
                    root.accentTo = to
                    const sec = hex("secondary")
                    if (sec.length > 0)
                        root.inactive = sec
                    root.tintFromScheme(to)
                } catch (error) {
                }
            }
        }
        onExited: root.drainExtraction("matugen")
    }

    //  Whether the scheme styles can run at all. A nix install ships
    //  matugen with the bar and this lands true; elsewhere the card
    //  hides its chips and the sampled classic keeps the palette.
    Process {
        command: ["sh", "-c", "command -v matugen || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.matugenOk = String(this.text).trim().length > 0
                //  The empty-scheme default follows the tool: when the
                //  state was loaded before the scan answered, the tonal
                //  default has not had its extraction yet.
                if (root.matugenOk && root.scheme.length === 0 && root.ready)
                    root.extract()
            }
        }
    }

    K4.PorPantalla {
        delegate: K4.Ventana {
            required property var modelData
            screen: modelData
            nombre: "k4-wallpaper"
            capa: "fondo"
            reserva: -1
            zonaActiva: noInput
            visible: root.isMoving(root.source)

            Item { id: noInput; width: 0; height: 0 }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                visible: root.isVideo(root.source)
                fillMode: VideoOutput.PreserveAspectCrop
            }

            MediaPlayer {
                id: player
                videoOutput: videoOutput
                loops: MediaPlayer.Infinite
                source: root.isVideo(root.source)
                    ? "file://" + root.source : ""
                onSourceChanged: if (source !== "") play()
                onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState
                        && String(source) === "file://" + root.source) {
                    root.playingVideoSource = root.source
                    root.applyStatus = "applied"
                    root.applyError = ""
                }
                onErrorOccurred: function (error, message) {
                    if (String(source) !== "file://" + root.source) return
                    root.playingVideoSource = ""
                    root.applyStatus = "failed"
                    root.applyError = message || "Could not play this wallpaper."
                }
            }
            Connections {
                target: root
                function onRetryVideo() {
                    if (String(player.source) === "file://" + root.source) {
                        player.stop()
                        player.play()
                    }
                }
            }
        }
    }
}
