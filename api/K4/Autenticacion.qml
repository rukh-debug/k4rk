//  Verify that the person at the keyboard is who they claim to be.
//
//  Underneath is PAM, which does more than accept a password and return yes
//  or no: it opens a conversation in which the system asks and you answer.
//  It may ask several times, or issue a notice without a question, such as
//  when two attempts remain before the account locks itself. This collects
//  that conversation and exposes it as a four-state machine.
//
//  Reasons are KEYS, not sentences: this layer does not translate them. The
//  system message already uses the machine's language and passes through
//  unchanged, because PAM supplies it and it often contains useful details.

import QtQuick
import Quickshell.Services.Pam

QtObject {
    id: auth

    // "listo" · "verificando" · "correcto" · "fallo"
    property string estado: "listo"

    // Reason key for the last failure: "" · "sin-pam" · "incorrecta" ·
    // "demasiados-intentos" · "error"
    property string motivo: ""

    // The system's message, already in its language. May be empty.
    property string mensaje: ""

    property int fallos: 0

    readonly property bool ocupado: estado === "verificando"

    signal resuelto(bool correcto)

    function comprobar(clave) {
        if (ocupado || !clave || clave.length === 0)
            return
        pendiente = clave
        mensaje = ""
        motivo = ""
        estado = "verificando"
        if (!pam.start()) {
            estado = "fallo"
            motivo = "sin-pam"
            resuelto(false)
        }
    }

    function reiniciar() {
        estado = "listo"
        motivo = ""
        mensaje = ""
    }

    // Keep the password only from submission until PAM requests it.
    property string pendiente: ""

    property PamContext pam: PamContext {
        // Use the same rules as logging into the machine, as expected from
        // a screen lock: authenticate with the user's login password.
        config: "login"
        configDirectory: "/etc/pam.d"

        onPamMessage: {
            if (responseRequired) {
                respond(auth.pendiente)
                auth.pendiente = ""
            } else if (message.length > 0) {
                // Notices without a question: usually the remaining attempt
                // count. These are worth showing.
                auth.mensaje = message
            }
        }

        onCompleted: function (resultado) {
            auth.pendiente = ""
            if (resultado === PamResult.Success) {
                auth.estado = "correcto"
                auth.fallos = 0
                auth.motivo = ""
                auth.mensaje = ""
                auth.resuelto(true)
            } else {
                auth.estado = "fallo"
                auth.fallos += 1
                auth.motivo = resultado === PamResult.MaxTries
                    ? "demasiados-intentos" : "incorrecta"
                auth.resuelto(false)
            }
        }

        onError: function (e) {
            auth.pendiente = ""
            auth.estado = "fallo"
            auth.motivo = "error"
            auth.mensaje = PamError.toString(e)
            auth.resuelto(false)
        }
    }
}
