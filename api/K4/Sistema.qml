pragma Singleton

//  General utilities: launch commands, read the environment and find icons.
//
//  Groups Quickshell's global utility functions so plugins do not need to
//  import the platform directly.

import QtQuick
import Quickshell

Singleton {
    //  Environment markers used by an agent to identify child sessions.
    //
    //  Restarting the shell from a Claude session makes it inherit these
    //  markers and pass them to every terminal and application it launches.
    //  A new `claude` process then considers itself a child session, which
    //  does not write its transcript. History stops being saved and `/resume`
    //  lists nothing. This occurred during agent-assisted development and
    //  initially looked like a Claude Code failure.
    //
    //  The shell is not an agent subshell: its launched applications start fresh.
    readonly property var marcasDeAgente: [
        "CLAUDECODE",
        "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_EXECPATH",
        "CLAUDE_PID",
        "CLAUDE_EFFORT",
        "AI_AGENT"
    ]

    //  Wrap only when the shell inherited markers. On an ordinary startup,
    //  leave the command exactly as supplied.
    function sinMarcas(orden) {
        const fuera = []
        for (let i = 0; i < marcasDeAgente.length; i++)
            if (Quickshell.env(marcasDeAgente[i]))
                fuera.push("-u", marcasDeAgente[i])

        return fuera.length > 0 ? ["env"].concat(fuera).concat(orden) : orden
    }

    // Fire and forget when no output is needed: open a folder, copy or notify.
    function lanzar(orden) { Quickshell.execDetached(sinMarcas(orden)) }

    function entorno(nombre) { return Quickshell.env(nombre) || "" }

    // An application icon, looked up by name.
    function icono(nombre) { return Quickshell.iconPath(nombre, true) || "" }

    // Open with the desktop's default application for this file type.
    function abrir(ruta) {
        if (ruta && String(ruta).length > 0)
            lanzar(["xdg-open", String(ruta)])
    }

    // A system notification, visible even while the island is closed.
    function avisar(titulo, detalle, urgente) {
        const orden = ["notify-send", "-a", "k4"]
        if (urgente === true)
            orden.push("-u", "critical")
        orden.push(String(titulo || ""))
        if (detalle !== undefined && String(detalle).length > 0)
            orden.push(String(detalle))
        Quickshell.execDetached(orden)
    }

    // Copy to the clipboard. Images below specify their MIME type so another
    // application receives image data rather than a guessed representation.
    function copiar(texto) {
        Quickshell.execDetached(["wl-copy", "--", String(texto)])
    }

    function copiarImagen(ruta) {
        Quickshell.execDetached(["sh", "-c",
            "wl-copy -t image/png < " + entrecomillar(ruta)])
    }

    // Shell quoting, escaping embedded single quotes. This keeps spaces and
    // quotes in a path from breaking the command.
    function entrecomillar(s) {
        return "'" + String(s).split("'").join("'\\''") + "'"
    }
}
