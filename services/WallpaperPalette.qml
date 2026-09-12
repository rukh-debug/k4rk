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
        applicator.running = false
        if (isMoving(source)) {
            // Remove external background layers before the native animated
            // surface starts decoding its first frame.
            applicator.command = ["sh", "-c",
                "pkill -x swaybg 2>/dev/null || true; awww kill 2>/dev/null || true;"
                + " swww kill 2>/dev/null || true"]
            applicator.running = true
            return
        }
        if (wallTool.length === 0)
            return
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
                                           transition: transicion }, null, 1))
    }

    function load() {
        try {
            const saved = JSON.parse(state.text())
            source = String(saved.source || "")
            if (transiciones.indexOf(saved.transition) >= 0)
                transicion = saved.transition
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

    function extract() {
        if (!Settings.wallpaperPalette || source.length === 0)
            return
        //  The poster decision is made HERE and not in a shell `case`:
        //  the glob `*.mp4` is case-sensitive, and an uppercase `.MP4`
        //  slipped past it straight into magick, which forked its own
        //  ffmpeg delegate to decode the video. A bar restart in the
        //  middle left that pair blocked on a dead pipe — forever.
        const needsPoster = isVideo(source) || isAnimated(source)
        sampler.running = false
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

    onSourceChanged: if (ready) extract()
    onTransicionChanged: save()

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

    Process { id: applicator }

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
            }
        }
    }
}
