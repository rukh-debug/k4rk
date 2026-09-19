//  Contribute results to the shell's launcher.
//
//  Users open the launcher with a shortcut and start typing immediately.
//  Adding your notes, servers or other results there makes a plugin part
//  of the shell rather than another window the user must go looking for.
//
//  Respond when ready: the shell emits `buscando`, and you publish the
//  available results in `resultados`. Network queries and processes need
//  not block anyone; their results render when they arrive.
//
//  Contributions always appear BELOW system applications. Someone typing
//  "fire" expects Firefox; plugin results should not displace the item the
//  user came to find. Contributions make your content discoverable without
//  competing with the launcher's primary purpose.
//
//      K4.Lanzador {
//          plugin: "hola"
//          onBuscando: function (texto) {
//              resultados = texto.length < 2 ? [] : [{
//                  id: "saludo", titulo: "Greet " + texto,
//                  desc: "From the example plugin", glifo: 0xF02FC
//              }]
//          }
//          onElegido: function (id) { ... }
//      }

import QtQuick

QtObject {
    id: aporte

    required property string plugin

    //  `[{ id, titulo, desc }]` — the currently displayed results.
    //
    //  A row's icon, in order: `glifo`, a Nerd Font code point, or `imagen`,
    //  your own `file://` image; then `icono`, the NAME of a desktop icon for
    //  an installed application. If none is supplied, use the plugin's icon,
    //  usually the desired fallback. A row without any icon leaves a gap
    //  that looks broken beside rows with icons.
    //
    //  `insignia: { texto, acento }` is optional: a small badge after
    //  the title, accented (warm) or plain — where a thing comes from,
    //  which source answered. Rendered by the launcher for anyone.
    property var resultados: []

    //  The user is typing. Fires on every keystroke, so check the query length
    //  before starting expensive work.
    signal buscando(string texto)

    //  The user selected one of your results, identified by its `id`.
    signal elegido(string id)

    property Connections _puente: Connections {
        target: Puente.enganches
        function onBuscando(texto) { aporte.buscando(texto) }
    }

    Component.onCompleted: {
        if (Puente.enganches)
            Puente.enganches.registrarLanzador(aporte)
    }

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
