pragma Singleton

//  Desktop wallpapers: which exist, how they look, where their thumbnail
//  lives.
//
//  They were born inside the `HyprTheme` plugin, and that was fine while
//  only its own screen used them. It stopped being fine when Settings
//  wanted the same grid: a plugin does not import another plugin's folder
//  — nobody in this repo does, and for good reason — so the shared part
//  moved down here and both use it without knowing each other.
//
//  Here is the CATALOG and how it looks. Applying a wallpaper is the
//  WallpaperPalette service's business — it is the one that talks to
//  `awww`/`swww`/`swaybg` and knows transitions: that is doing, not
//  looking.
//
//  A service cannot use `K4.Process` or `K4.Sistema` — that is the
//  plugins' API — so this talks to Quickshell directly, the way the other
//  services do.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: fondos

    // ── where it searches ─────────────────────────────────────────
    readonly property string casa: Quickshell.env("HOME") || ""

    readonly property var carpetas: [
        casa + "/Pictures",
        casa + "/Imágenes",
        casa + "/Videos",
        casa + "/Vídeos",
        casa + "/Descargas",
        "/usr/share/wallpapers",
        "/usr/share/backgrounds"
    ]

    //  And what does NOT count as a wallpaper even when it is in there.
    //
    //  "Capturas" and "Screenshots" are where screenshots end up, and a
    //  wallpaper picker that fills with terminal screenshots is a picker
    //  you have never looked at: on this machine, of 120 images found
    //  the overwhelming majority were exactly that.
    readonly property var carpetasFuera: ["Capturas", "Screenshots", ".thumbnails"]

    //  What is admitted. The usual ones plus the moving ones, which is
    //  what all of this was about.
    readonly property var extensiones: [
        "jpg", "jpeg", "png", "webp", "avif",
        "gif", "apng",
        "mp4", "webm", "mkv", "mov", "m4v"
    ]

    function admitido(ruta) {
        const r = String(ruta || "").toLowerCase()
        for (let i = 0; i < extensiones.length; ++i)
            if (r.endsWith("." + extensiones[i]))
                return true
        return false
    }

    // ── what exists ───────────────────────────────────────────────
    //
    //  They are kept by PATH and not by copying the file. Copying would
    //  be more robust —a wallpaper on a USB stick stops existing when
    //  you pull it out— but it would also silently duplicate a
    //  three-hundred-megabyte video because you dragged it into a grid.
    //  If a path stops existing, it drops out of the next scan by
    //  itself and that is that.
    property var encontrados: []
    property var extras: []

    //  Yours first: if you went to the trouble of bringing one in, you
    //  should not have to hunt for it among forty-five later.
    readonly property var lista: {
        const fuera = []
        for (let i = 0; i < fondos.extras.length; ++i)
            fuera.push(fondos.extras[i])
        for (let j = 0; j < fondos.encontrados.length; ++j)
            if (fondos.extras.indexOf(fondos.encontrados[j]) < 0)
                fuera.push(fondos.encontrados[j])
        return fuera
    }

    property bool rastreando: false

    function sumar(rutas) {
        const d = fondos.extras.slice()
        let hubo = false
        for (let i = 0; i < rutas.length; ++i) {
            const r = String(rutas[i])
            if (admitido(r) && d.indexOf(r) < 0) {
                d.unshift(r)
                hubo = true
            }
        }
        if (hubo) {
            fondos.extras = d
            persistir()
        }
    }

    function quitar(ruta) {
        const d = fondos.extras.filter(function (x) { return x !== String(ruta) })
        if (d.length !== fondos.extras.length) {
            fondos.extras = d
            persistir()
        }
    }

    // ── what you brought in survives the bar ──────────────────────
    //
    //  The scan results are rediscovered every time; the paths the user
    //  added by hand are not — without this file they were memory-only
    //  and every restart silently forgot them.
    readonly property string rutaEstado:
        casa + "/.local/state/k4/fondos.json"

    function persistir() {
        estado.setText(JSON.stringify({ extras: extras }, null, 1))
    }

    FileView {
        id: estado
        path: fondos.rutaEstado
        blockLoading: true
        onLoaded: fondos.cargarEstado()
    }

    function cargarEstado() {
        try {
            const d = JSON.parse(estado.text())
            if (d.extras && d.extras.length !== undefined)
                extras = d.extras
        } catch (e) {
            //  A half-written state is not an emergency: the extras stay
            //  empty and the next change writes the file whole.
            migrar()
        }
        if (extras.length === 0)
            migrar()
    }

    //  One shot, from the state the deleted theme plugin used to own:
    //  the paths its picker had added. Old key, read once, kept ours.
    FileView {
        id: antiguo
        path: fondos.casa + "/.local/state/k4/hyprtheme.json"
        blockLoading: true
        onLoaded: fondos.migrar()
    }

    function migrar() {
        if (migrado || extras.length > 0)
            return
        migrado = true
        try {
            const s = JSON.parse(antiguo.text())
            const leidos = (s.extras && s.extras.length !== undefined)
                ? s.extras : []
            const d = extras.slice()
            for (let i = 0; i < leidos.length; ++i)
                if (admitido(leidos[i]) && d.indexOf(leidos[i]) < 0)
                    d.push(leidos[i])
            if (d.length !== extras.length) {
                extras = d
                persistir()
            }
            if (s.gapsOut !== undefined)
                huecos = parseInt(s.gapsOut, 10) || 8
        } catch (e) {
            //  Nothing to migrate from: first run, or never used the old
            //  picker. Either way the answer is the same — start empty.
        }
    }

    property bool migrado: false

    // ── how they look ─────────────────────────────────────────────
    readonly property string cache: casa + "/.cache/k4/fondos"

    //  `gif|webp|apng` counts as STILL even when it moves: an
    //  AnimatedImage paints it and not the player, so for thumbnails the
    //  image itself is good enough.
    function esQuieto(ruta) {
        return !/\.(mp4|webm|mkv|mov|m4v|avi|gif|webp|apng)$/i.test(String(ruta))
    }

    function esVideo(ruta) {
        return /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(String(ruta))
    }

    //  Where the cached frame of a moving wallpaper lives.
    //
    //  `Qt.md5` and not a per-process `md5sum`: the path is computed on
    //  the spot, launching nothing. It is the same name the poster
    //  preparation writes, so both halves look at the same file.
    function posterDe(ruta) {
        return cache + "/" + Qt.md5(String(ruta)) + ".png"
    }

    //  The thumbnail: the image itself when still, the poster when it
    //  moves.
    //
    //  `sello` is in the account on purpose: a file path does not change
    //  when the file appears, so without something moving the link a
    //  video's thumbnail would stay broken until closing and reopening.
    property int sello: 0

    function miniaturaDe(ruta) {
        //  Qt can decode an animated image's first frame immediately. Waiting
        //  for ffmpeg to finish the whole poster batch made GIFs appear last.
        if (/\.(gif|apng)$/i.test(String(ruta)))
            return ruta
        if (esQuieto(ruta))
            return ruta
        return fondos.sello >= 0 ? posterDe(ruta) : ""
    }

    // ── Hyprland's gaps, for whoever draws a desktop preview ──────
    //
    //  A window glued to the edges would show something that does not
    //  happen; the island preview reads this to frame itself honestly.
    //  It came from the old theme plugin's state and is migrated from
    //  there once; nothing rewrites it anymore, and the default is the
    //  value the preview was drawn against all along.
    property int huecos: 8

    // ── the scan ──────────────────────────────────────────────────
    function rastrear() {
        const args = ["find"]
        for (let i = 0; i < fondos.carpetas.length; ++i)
            args.push(fondos.carpetas[i])
        args.push("-maxdepth")
        args.push("3")
        //  Excluded folders are pruned BEFORE looking at files: with a
        //  `-not -path` every file inside gets examined all the same, and
        //  in a screenshots folder with hundreds that is walking the tree
        //  to then discard it.
        for (let i = 0; i < fondos.carpetasFuera.length; ++i) {
            args.push("(")
            args.push("-type"); args.push("d")
            args.push("-name"); args.push(fondos.carpetasFuera[i])
            args.push("-prune")
            args.push(")")
            args.push("-o")
        }
        args.push("(")
        args.push("-type"); args.push("f")
        args.push("(")
        for (let j = 0; j < fondos.extensiones.length; ++j) {
            if (j > 0)
                args.push("-o")
            args.push("-iname")
            args.push("*." + fondos.extensiones[j])
        }
        args.push(")")
        args.push("-print")
        args.push(")")
        rastreo.command = args
        rastreo.running = true
    }

    Process {
        id: rastreo
        onStarted: fondos.rastreando = true
        stdout: StdioCollector {
            onStreamFinished: {
                const rutas = String(this.text).split("\n").filter(function (r) {
                    return r.length > 0 && fondos.admitido(r)
                })
                fondos.encontrados = rutas
                fondos.prepararPosters()
            }
        }
        onExited: fondos.rastreando = false
    }

    //  The posters, all in one go and in ONE process.
    //
    //  One per file would be thirty ffmpregs fighting for the CPU right
    //  when you just opened the screen and want to see it. In a queue,
    //  and the one that already exists is not touched.
    Process {
        id: cocina
        onExited: fondos.sello += 1
    }

    function prepararPosters() {
        const ordenes = []
        for (let i = 0; i < fondos.lista.length; ++i) {
            const r = fondos.lista[i]
            if (esQuieto(r))
                continue
            const d = posterDe(r)
            ordenes.push("[ -f " + JSON.stringify(d) + " ] || ffmpeg -nostdin -v error -y"
                         + " -ss 1 -i " + JSON.stringify(r)
                         + " -frames:v 1 -vf scale=480:-1 " + JSON.stringify(d)
                         + " >/dev/null 2>&1")
        }
        if (ordenes.length === 0)
            return
        cocina.running = false
        //  `timeout` bounds the whole batch: a bar restart cannot leave
        //  an orphaned pipeline behind (see WallpaperPalette.extract).
        cocina.command = ["timeout", "-k", "5", "120", "sh", "-c",
            "mkdir -p " + JSON.stringify(fondos.cache) + "; " + ordenes.join("; ")]
        cocina.running = true
    }
}
