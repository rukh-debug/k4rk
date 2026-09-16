pragma Singleton

// Terminal selection and the host-side connection state shared by providers.
// Window commands use the user's terminal; island sessions can use either
// k4term-isla or the bundled Python backend. Binary availability is tracked
// by Binarios, including installations made while the bar is running.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: consola

    property string binario: ""
    readonly property bool nativeIslandAvailable: Binarios.presentes["k4term-isla"] === true
    readonly property bool hayIsla: nativeIslandAvailable || Binarios.presente("python3")
    readonly property bool esNuestra: binario === "k4term"
    readonly property string themePath: Ambiente.ruta
    readonly property string focusedPid: String(Ventanas.pidActivo || "")

    Component.onCompleted: Binarios.sondear(["python3", "k4term-isla"])

    property var enIsla: null
    function registrarIsla(f) { enIsla = f }
    readonly property bool usaIsla: enIsla !== null && hayIsla
    readonly property string cierre: usaIsla
        ? "" : " printf '\\nPress Enter to close…'; read _;"

    property string conectando: ""
    property double conectandoDesde: 0
    property string tinteConexion: ""
    property string claveConexion: ""

    function conectandoA(destino, tinte, clave) {
        conectando = String(destino || "")
        tinteConexion = String(tinte || "")
        claveConexion = String(clave || "")
        conectandoDesde = Date.now()
    }

    function conectado() {
        conectando = ""
        claveConexion = ""
    }

    signal salioDe(string destino)

    property Timer topeConexion: Timer {
        interval: 25000
        running: consola.conectando !== ""
        onTriggered: consola.conectado()
    }

    function ejecutar(guion) {
        if (usaIsla)
            enIsla(guion)
        else
            Quickshell.execDetached(orden(guion))
    }

    // uwsm is optional: direct execution still inherits the desktop session.
    function envoltura(orden) { return orden }

    function orden(guion) {
        const bin = binario || "xterm"
        if (bin === "wezterm")
            return envoltura([bin, "start", "--", "sh", "-c", guion])
        if (bin === "gnome-terminal")
            return envoltura([bin, "--", "sh", "-c", guion])
        return envoltura([bin, "-e", "sh", "-c", guion])
    }

    function abrir(ruta) {
        const bin = binario || "xterm"
        if (!ruta)
            return envoltura([bin])
        if (bin === "k4term")
            return envoltura([bin, "-d", ruta])
        const script = "cd \"$0\" && exec ${SHELL:-/bin/sh}"
        if (bin === "wezterm")
            return envoltura([bin, "start", "--", "sh", "-c", script, ruta])
        if (bin === "gnome-terminal")
            return envoltura([bin, "--", "sh", "-c", script, ruta])
        return envoltura([bin, "-e", "sh", "-c", script, ruta])
    }

    // Notification routing belongs to the host, not to the terminal view.
    function trackNotice(title, pid) { Notifs.apuntarDestino("k4term", title, pid) }
    function clearNotice(title) {
        Notifs.descartarDeApp("k4term", title)
        Notifs.olvidarDestino("k4term", title)
    }

    property Timer revisor: Timer {
        interval: 60000
        repeat: true
        running: !consola.esNuestra
        onTriggered: buscador.running = true
    }

    function revisar() {
        buscador.running = true
        Binarios.sondear(["python3", "k4term-isla"])
    }

    Process {
        id: buscador
        running: true
        command: ["sh", "-c",
            "for t in k4term \"$TERMINAL\" kitty alacritty foot wezterm konsole gnome-terminal xterm; do\n" +
            "  [ -z \"$t\" ] && continue\n" +
            "  command -v \"$t\" >/dev/null 2>&1 && { printf '%s\\n' \"$t\"; exit; }\n" +
            "done\n"]
        stdout: StdioCollector {
            onStreamFinished: consola.binario = this.text.trim()
        }
    }
}
