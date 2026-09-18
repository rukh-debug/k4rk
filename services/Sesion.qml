pragma Singleton

//  Session identity, power actions and the real screen lock.
//
//  The lock lives here — not in the island menu — so `k4 lock` works even
//  when the menu surface fails to load, and so the compositor's real lock
//  state stays authoritative across reloads. The menu itself is the native
//  SessionIsland surface; it only asks this service to act.
//
//  On hibernate: the kernel saying it knows ("disk" in /sys/power/state) is
//  not enough. A real swap to dump memory into and a `resume=` boot entry
//  are both required; with only zram — which lives in the very RAM being
//  powered off — hibernation goes nowhere, so the option is not offered.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import K4 as K4
import "../core"

Singleton {
    id: sesion

    // ── who you are ─────────────────────────────────────────────
    readonly property string usuario: Quickshell.env("USER") || ""
    property string nombre: ""
    readonly property string visible: nombre.length > 0 ? nombre : usuario
    readonly property string inicial:
        visible.length > 0 ? visible.charAt(0).toUpperCase() : "?"

    // ── the real lock ───────────────────────────────────────────
    //  WlSessionLock's default property is `surface`, so the surface must
    //  stay OUTSIDE the lock block: inside, it would be assigned as the
    //  surface silently and the lock would never engage. It opens and
    //  closes by writing `locked`; the C++ unlock() is not exposed to QML.
    property bool bloqueado: false

    function bloquear() { bloqueado = true }
    function desbloquear() { bloqueado = false }

    property var cerradura: K4.BloqueoSesion {
        surface: BloqueoSurface {}
    }

    Connections {
        target: sesion
        function onBloqueadoChanged() {
            // The island menu closes itself through SurfaceRegistry.
            try {
                const menu = SurfaceRegistry.instance("session")
                if (menu && sesion.bloqueado && typeof menu.close === "function")
                    menu.close()
            } catch (e) {
            }
            if (sesion.cerradura.locked !== sesion.bloqueado)
                sesion.cerradura.locked = sesion.bloqueado
        }
    }

    //  On reload the lock object keeps the real state and the service
    //  starts from zero. The compositor rules, always: the reverse would
    //  release a half lock, orphan Hyprland state, and turn every later
    //  lock request into a protocol error that takes the bar down.
    Component.onCompleted: {
        if (sesion.cerradura && sesion.cerradura.locked !== sesion.bloqueado)
            sesion.bloqueado = sesion.cerradura.locked
    }

    // ── qué puede hacer esta máquina ──────────────────────────────
    property bool swapReal: false
    property bool resumeConfigurado: false
    readonly property bool hibernacionPosible: swapReal && resumeConfigurado

    // ── acciones ──────────────────────────────────────────────────
    //
    //  systemd-logind se encarga de todas menos cerrar sesión, que es del
    //  compositor: salir de Hyprland cierra la sesión gráfica sin tirar de
    //  `loginctl terminate-user`, que se llevaría por delante también lo que
    //  tengas corriendo en un tty.
    function apagar()    { correr(["systemctl", "poweroff"]) }
    function reiniciar() { correr(["systemctl", "reboot"]) }
    function hibernar()  { correr(["systemctl", "hibernate"]) }

    // Dormir con la sesión ya bloqueada: si no, al despertar queda el
    // escritorio a la vista el instante que tarda el bloqueo en montarse.
    function suspender() {
        bloquear()
        dormir.start()
    }

    function cerrarSesion() { Hyprland.dispatch("hl.dsp.exit()") }

    function correr(cmd) {
        accion.command = cmd
        accion.running = true
    }

    Process { id: accion }

    // Un respiro antes de suspender para que la pantalla de bloqueo esté
    // dibujada cuando la máquina se duerma, no a medio montar.
    Timer {
        id: dormir
        interval: 400
        onTriggered: sesion.correr(["systemctl", "suspend"])
    }

    // El nombre bonito sale del quinto campo de passwd, hasta la primera coma:
    // el resto del GECOS son despacho y teléfonos que no pintan nada aquí.
    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("sesion:", l)
            }
        }
        command: ["getent", "passwd", sesion.usuario]
        running: sesion.usuario.length > 0

        stdout: StdioCollector {
            onStreamFinished: {
                const campos = String(this.text).trim().split(":")
                if (campos.length >= 5)
                    sesion.nombre = campos[4].split(",")[0].trim()
            }
        }
    }

    // ¿Hay algún swap que no sea zram? Es la condición que falla en la mayoría
    // de equipos actuales, y sin ella hibernar no vuelve.
    FileView {
        path: "/proc/swaps"
        blockLoading: true

        onLoaded: {
            const lineas = String(text()).trim().split("\n")
            for (let i = 1; i < lineas.length; ++i) {
                const dispositivo = lineas[i].split(/\s+/)[0] || ""
                if (dispositivo.length > 0 && dispositivo.indexOf("zram") === -1)
                    sesion.swapReal = true
            }
        }
    }

    FileView {
        path: "/proc/cmdline"
        blockLoading: true
        onLoaded: sesion.resumeConfigurado = String(text()).indexOf("resume=") !== -1
    }
}
