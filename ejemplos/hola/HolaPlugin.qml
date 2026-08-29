//  El plugin mínimo: un saludo en la island.
//
//  Es el ejemplo de docs/PLUGINS.md, completo y cargable tal cual: copia la
//  carpeta a ~/.config/k4/plugins/hola, enciéndelo en Ajustes, y
//  `quickshell ipc -p <ruta>/shell.qml call k4.hola toggle` lo abre.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "hola"
    title: "Hola"
    priority: 65
    active: abierto
    islandWidth: 360
    islandHeight: 100

    property bool abierto: false
    property int visitas: 0
    property bool saludar: true
    property string aQuien: ""

    view: Component { HolaView { plugin: self } }

    //  El estado propio: sobrevive a reiniciar la barra.
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

    //  Mis ajustes, dentro de los Ajustes de la barra. Los valores los guardo
    //  yo; la barra solo pregunta y avisa.
    property var misAjustes: K4.Ajustes {
        plugin: "hola"
        grupo: "Hello"
        opciones: [
            { id: "saludar", nombre: "Greet on open",
              desc: "Otherwise just show the counter",
              glifo: 0xF1821 },
            //  Un campo libre: aquí un nombre; en un plugin de verdad, la
            //  URL de un servicio o —con `secreto: true`— su clave.
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

    //  Y una entrada en el lanzador, para abrirse escribiendo.
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
