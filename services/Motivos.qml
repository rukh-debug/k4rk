pragma Singleton

//  Why a tool call failed, by error code.
//
//  The scripts in tools/ report failures as CODES — "sin-clonar",
//  "sin-entrada" — and the bar writes the sentence. A code never needs
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
        "fallo": "Something went wrong",
        "ilegible": "I couldn't read it",
        "sin-registro": "I couldn't read the registry",
        "sin-clonar": "I couldn't clone the repository",
        "sin-commit": "I can't find that commit",
        "sin-plugin": "I can't find a plugin in there",
        "commit-raro": "That isn't a commit",
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
