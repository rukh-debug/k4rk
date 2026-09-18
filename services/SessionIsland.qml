pragma Singleton

// Native session menu: lock, suspend, hibernate, logout, reboot, shutdown.
//
// The real ext-session-lock surface lives in the Sesion service so locking
// never depends on this island view. This surface only asks Sesion to act,
// offers two-press confirmation for irreversible actions, and rehearses the
// PAM password without locking via `k4.session check`.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: self

    readonly property string name: "session"
    readonly property string title: "Session"
    readonly property int priority: 86
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: open

    readonly property bool colocable: true
    readonly property string summonCommand: "k4.session toggle"
    readonly property bool transitorio: false
    property bool viewLoaded: open
    property bool grabKeyboard: open
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnClickOutside: true
    property bool handlesBackgroundTap: false

    property var panel: null

    property bool open: false
    property int index: 0
    property string modo: "menu"
    property int confirmando: -1

    readonly property var acciones: {
        const l = [
            { clave: "bloquear", texto: "Lock",
              icono: 0xF033E, color: Theme.blue, confirma: false },
            { clave: "suspender", texto: "Suspend",
              icono: 0xF04B2, color: Theme.blue, confirma: false }
        ]
        if (Sesion.hibernacionPosible)
            l.push({ clave: "hibernar", texto: "Hibernate",
                     icono: 0xF0904, color: Theme.blue, confirma: true })
        l.push({ clave: "salir", texto: "Log out",
                 icono: 0xF0343, color: Theme.muted, confirma: true })
        l.push({ clave: "reiniciar", texto: "Reset",
                 icono: 0xF0709, color: Theme.muted, confirma: true })
        l.push({ clave: "apagar", texto: "Shut down",
                 icono: 0xF0425, color: Theme.red, confirma: true })
        return l
    }

    readonly property int count: acciones.length
    readonly property int islandWidth: modo === "comprobar" ? 420 : Math.min(760, 40 + count * 118)
    readonly property int islandHeight: modo === "comprobar" ? 172 : 200

    property bool closeOnHoverExit: false
    property int hoverExitDelay: 0
    signal hoverTimedOut()
    property var barraApartada
    property var reservaBarra

    property Component view: Component {
        SessionIslandView { plugin: self }
    }

    function abrir() {
        index = 0
        confirmando = -1
        modo = "menu"
        open = true
        if (panel)
            panel.close()
    }

    function close() {
        open = false
        confirmando = -1
        modo = "menu"
    }

    function comprobarClave() {
        modo = "comprobar"
        open = true
    }

    function atras() {
        if (modo === "comprobar")
            modo = "menu"
        else
            close()
    }

    function toggle() { open ? close() : abrir() }

    function avanzar()    { index = (index + 1) % count; confirmando = -1 }
    function retroceder() { index = (index - 1 + count) % count; confirmando = -1 }

    function ejecutar(i) {
        const a = acciones[i]
        if (!a)
            return
        if (a.confirma && confirmando !== i) {
            index = i
            confirmando = i
            return
        }
        close()
        if (a.clave === "bloquear")       Sesion.bloquear()
        else if (a.clave === "suspender") Sesion.suspender()
        else if (a.clave === "hibernar")  Sesion.hibernar()
        else if (a.clave === "salir")     Sesion.cerrarSesion()
        else if (a.clave === "reiniciar") Sesion.reiniciar()
        else if (a.clave === "apagar")    Sesion.apagar()
    }

    function elegir() { ejecutar(index) }

    onCountChanged: if (index >= count) index = Math.max(0, count - 1)

    IpcHandler {
        target: "k4.session"
        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
        function lock(): void { Sesion.bloquear() }
        function unlock(): void { Sesion.desbloquear() }
        function check(): void { self.comprobarClave() }
    }
}
