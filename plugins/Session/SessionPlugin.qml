//  Session: the shutdown menu and the lock screen.
//
//  Two very different things living together because they share a
//  service. The menu is an ordinary island module. The lock is NOT:
//  it is an `ext-session-lock` surface, a separate protocol the
//  compositor draws above everything and gives the keyboard
//  exclusively. Neither the island nor any window can paint over
//  it, which is exactly the point.
//
//  Careful with that last one: if quickshell dies with the lock up,
//  the compositor leaves the session locked with nobody to open
//  it. The way out is a tty (Ctrl+Alt+F2) and killing Hyprland
//  from there. Hence `k4.session test`: it checks the password with
//  the same PAM the lock uses, but without locking anything, so it
//  can be verified before trusting it.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "session"
    title: "Session"
    priority: 86
    colocable: true
    active: habilitado && open
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property int index: 0

    // "menu" · "comprobar" — the second is the password rehearsal.
    property string modo: "menu"

    // What is about to be done, if it is the kind with no way back.
    property int confirmando: -1

    // ── the menu's actions ────────────────────────────────────────
    //
    //  `confirma` marks the ones that cannot be undone: they take two
    //  presses. Powering off the machine by grazing a key is the kind
    //  of thing that happens once and is never forgotten.
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

    islandWidth: modo === "comprobar" ? 420 : Math.min(760, 40 + count * 118)
    islandHeight: modo === "comprobar" ? 172 : 200

    view: Component {
        SessionView { plugin: self }
    }

    // ── the menu ───────────────────────────────────────────────────
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

    // The rehearsal: the same check the lock will do, without
    // locking. If it gets in here, it will get in there.
    function comprobarClave() {
        modo = "comprobar"
        open = true
    }

    // ESC returns to the menu before closing entirely: inside the
    // checker, leaving the whole thing on one keypress is harsher
    // than expected.
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

        // first press on something irreversible: it asks, it does
        // not obey
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

    // ── the lock screen ───────────────────────────────────────────
    K4.BloqueoSesion {
        id: cerradura
        surface: BloqueoSurface {}
    }

    //  Watch out for two things here, which cost a session.
    //
    //  One: WlSessionLock's default property is `surface`, so this
    //  cannot go inside the block above —it would end up assigned as
    //  the surface, without a single complaint: the lock simply does
    //  not engage.
    //
    //  Two: it opens and closes by writing `locked`. The `unlock()`
    //  shown in the documentation exists in C++ but is not exposed
    //  to QML, and calling it the warning gets lost among startup's
    //  while the session stays locked. It is the kind of failure one
    //  only notices when one can no longer get out.
    Connections {
        target: Sesion

        function onBloqueadoChanged() {
            if (Sesion.bloqueado)
                self.close()
            if (cerradura.locked !== Sesion.bloqueado)
                cerradura.locked = Sesion.bloqueado
        }

        //  On config reload —and quickshell reloads the moment you
        //  touch a file— the lock object keeps the real state and
        //  the service starts from zero. The compositor rules here,
        //  always.
        //
        //  The other way was tempting and is exactly what breaks:
        //  the service would say «you are not locked» and release a
        //  half lock, leaving Hyprland with an orphan. From there
        //  every lock request is a protocol error that takes the
        //  whole Wayland connection down —that is, the whole bar—
        //  and there is no way to fix it without closing the
        //  session.
        Component.onCompleted: {
            if (cerradura.locked !== Sesion.bloqueado)
                Sesion.bloqueado = cerradura.locked
        }
    }

    K4.Ipc {
        target: "k4.session"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }

        function lock(): void { Sesion.bloquear() }
        function unlock(): void { Sesion.desbloquear() }

        // Rehearses the password with the same PAM the lock uses,
        // without locking anything: it serves to check you will be
        // able to get out before entrusting the session to it.
        function check(): void { self.comprobarClave() }
    }
}
