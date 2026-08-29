pragma Singleton

//  Why a tool call failed, by error code.
//
//  The scripts in tools/ report failures as CODES — "sin-audio",
//  "fuera-del-disco" — and the bar writes the sentence. A code never needs
//  translating when a message is reworded, and it works just as well for
//  deciding what to do next.
//
//  Anything unrecognized is returned as-is: a Spanish reason beats no
//  reason, and a brand-new script stays audible until someone adds it here.

import QtQuick
import Quickshell

Singleton {
    id: motivos

    readonly property var tabla: ({
        "cancelado": "Cancelled",
        "fallo": "Something went wrong",
        "ilegible": "I couldn't read it",
        "no-existe": "It doesn't exist",
        "nada-que-hacer": "There was nothing to do",
        "sin-fichero": "I can't find the file",
        "sin-audio": "It has no audio",
        "sin-video": "It has no video",
        "sin-clips": "There are no clips",
        "sin-fuentes": "The project has no sources",
        "sin-plan": "I can't find the project",
        "sin-rastro": "There's no cursor trail",
        "sin-fotograma": "I couldn't pull the frame",
        "sin-ffmpeg": "ffmpeg is missing",
        "sin-modelo": "The whisper model is missing",
        "sin-whisper": "whisper is missing",
        "fallo-whisper": "Whisper failed",
        "fuera": "It went out",
        "sin pacman": "pacman is missing",
        "sin Steam": "Steam is missing",
        "fuera-del-disco": "The project points off this disk",
        "no-es-local": "That isn't a file on this computer",
        "no-responde": "The file isn't responding",
        "fuera-de-carpeta": "The output escapes its folder",
        "sin-registro": "I couldn't read the registry",
        "sin-clonar": "I couldn't clone the repository",
        "sin-commit": "I can't find that commit",
        "sin-plugin": "I can't find a plugin in there",
        "commit-raro": "That isn't a commit",
        "sin-monitor": "I can't find that display",
        "sin-proyecto": "No project is open",
        "no-es-imagen": "That isn't an image",
        "no-se-puede-soltar": "You can't drop it there",
        "no-se-puede-medir": "I couldn't measure the video",
        "no-se-pudo-limpiar": "I couldn't clean up the audio",
        "no-se-pudo-grabar-la-voz": "I couldn't record the voice-over",
        "sin-microfono": "The microphone never started",
        "miniatura": "I couldn't save the thumbnail",
        "congelar": "I couldn't freeze that moment",
        "sin-manifiesto": "It has no plugin.json",
        "manifiesto-ilegible": "Its plugin.json can't be read",
        "id-invalido": "Its id won't do",
        "id-no-coincide": "Its id doesn't match the folder",
        "id-ocupado": "A built-in plugin already uses that id",
        "entrada-fuera": "Its entry points outside its folder",
        "sin-entrada": "I can't find its entry file",
        "sin-qmldir": "I couldn't write its qmldir",
        "barra-vieja": "It needs a newer bar than this one",
        "icono-malo": "Its icon won't do",
        "permisos-raros": "It declares permissions that don't exist",
        "sin-declarar": "It uses things it doesn't declare",
        "superficies-raras": "It declares surfaces that don't exist",
        "superficie-sin-declarar": "It occupies places it doesn't declare",
        "no-cargable": "That plugin can't be loaded",
    })

    //  The reason as a sentence, with its detail behind if it brings one.
    function porque(codigo, detalle) {
        const c = String(codigo || "")
        if (c.length === 0)
            return ""
        const frase = motivos.tabla[c] !== undefined ? motivos.tabla[c] : c
        return detalle ? frase + ": " + detalle : frase
    }
}
