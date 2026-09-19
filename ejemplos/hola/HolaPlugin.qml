//  The minimal plugin: a greeting in the island.
//
//  The example from docs/PLUGINS.md, complete and loadable as is: copy the
//  folder to ~/.config/k4/plugins/hola, enable it in Settings, and open it
//  with `quickshell ipc -p <path>/shell.qml call k4.hola toggle`.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "hola"
    title: "Hello"
    priority: 65
    active: abierto
    islandWidth: 360
    islandHeight: 100

    property bool abierto: false
    property int visitas: 0
    property bool saludar: true
    property string aQuien: ""

    view: Component { HolaView { plugin: self } }

    //  The plugin's own state survives a bar restart.
    property var guardado: K4.Guardado {
        plugin: "hola"
        onCargado: function (d) {
            self.visitas = d.visitas || 0
            self.saludar = d.saludar !== false
            self.aQuien = d.aQuien || ""
        }
    }

    function apuntar() {
        guardado.guardar({ visitas: visitas, saludar: saludar,
                           aQuien: aQuien })
    }

    //  Plugin settings inside the bar's Settings. The plugin stores the
    //  values; the bar only reads them and reports changes.
    property var misAjustes: K4.Ajustes {
        plugin: "hola"
        grupo: "Hello"
        opciones: [
            { id: "saludar", nombre: "Greet on open",
              desc: "Otherwise just show the counter",
              glifo: 0xF1821 },
            //  A free-text field: a name here; in a real plugin, a service
            //  URL or its key with `secreto: true`.
            { id: "aQuien", tipo: "texto",
              nombre: "Who to greet",
              desc: "Shows up in the island greeting",
              pista: "the world", glifo: 0xF17C4 }
        ]
        valores: ({ saludar: self.saludar, aQuien: self.aQuien })
        onCambiado: function (id, valor) {
            if (id === "saludar")
                self.saludar = valor
            if (id === "aQuien")
                self.aQuien = String(valor).trim()
            self.apuntar()
        }
    }

    //  A launcher entry, so typing can open the plugin.
    property var enElLanzador: K4.Lanzador {
        plugin: "hola"
        onBuscando: function (texto) {
            const t = texto.trim().toLowerCase()
            resultados = (t.length >= 2 && "hola".indexOf(t) === 0)
                ? [{ id: "abrir", titulo: "Open Hello",
                     desc: "The example plugin" }]
                : []
        }
        onElegido: function (id) { if (id === "abrir") self.abierto = true }
    }

    K4.Ipc {
        target: "k4.hola"
        function toggle(): void {
            self.abierto = !self.abierto
            if (self.abierto) {
                self.visitas += 1
                self.apuntar()
            }
        }
        function close(): void { self.abierto = false }
    }
}
