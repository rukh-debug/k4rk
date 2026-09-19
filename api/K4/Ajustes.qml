//  Your plugin's settings, inside the shell's Settings window.
//
//  Without this, a plugin with two options had to invent its own screen,
//  its own button to open it, and its own way to save them. Users then had
//  to learn a new location for each plugin. Here, those options appear as
//  another Settings section with the same presentation as the rest.
//
//  YOU persist the values: the shell reads `valores` and reports changes
//  through `cambiado`. The displayed state is therefore the state you
//  actually saved, not a copy that drifts after the first failed write.
//
//      K4.Ajustes {
//          plugin: "hola"
//          grupo: "Hello"
//          opciones: [{ id: "sonar", nombre: "Play a sound on open",
//                       desc: "A short click", glifo: 0xF057E }]
//          valores: ({ sonar: self.sonar })
//          onCambiado: function (id, valor) {
//              if (id === "sonar") { self.sonar = valor; guardar() }
//          }
//      }

import QtQuick

QtObject {
    id: aporte

    //  Your id, matching the manifest. It separates your options from
    //  another plugin's options with the same names.
    required property string plugin

    //  The section title in Settings.
    property string grupo: ""

    //  The section's appearance in the Settings sidebar: an icon and one
    //  line explaining its purpose. Both are optional: without `glifo`, use
    //  the plugin's manifest icon; without `desc`, omit the subtitle.
    //
    //  `glifo` is a Nerd Font code point, like the manifest's icon. Find it
    //  with `tools/glyphs.py` and verify its appearance rather than guessing.
    property int glifo: 0
    property string desc: ""

    //  `[{ id, nombre, desc, glifo }]`. `glifo` is a Nerd Font code point;
    //  find it with `tools/glyphs.py`. Each option is a switch unless you
    //  specify another `tipo`:
    //
    //   · "eleccion": chips offering several choices. Supply them in
    //     `alternativas: [{ codigo, nombre }]`; `cambiado` receives the
    //     selected `codigo`.
    //   · "texto": a free-text field for a URL, model or API key. `pista`
    //     is the empty field's gray placeholder; `secreto: true` masks input
    //     with dots after typing. `cambiado` receives the value on commit
    //     (Enter or clicking outside), rather than on every keystroke.
    property var opciones: []

    //  Each option's CURRENT value, keyed by id. The shell reads it to render.
    property var valores: ({})

    //  The user changed an option: persist it and update `valores`.
    signal cambiado(string id, var valor)

    function _registrar() {
        if (Puente.enganches)
            Puente.enganches.registrarAjustes(aporte)
    }

    Component.onCompleted: _registrar()

    //  Register again whenever these change: registration takes a SNAPSHOT
    //  of the list at plugin creation. Otherwise, options that depend on a
    //  later discovery, such as an installed program or network access,
    //  would always or never appear according to that initial state.
    //  Empty `opciones` hides the entire section, expressing that these
    //  settings do not currently apply.
    onOpcionesChanged: _registrar()
    onGrupoChanged: _registrar()
    onGlifoChanged: _registrar()
    onDescChanged: _registrar()

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
