//  A showcase of the API's visual components.
//
//  It serves as a catalog for plugin authors and a visual check that every
//  component still works: failures show up here. It also demonstrates that
//  an external plugin can look exactly like the bar without drawing a
//  single rectangle by hand.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "piezas"
    title: "Pieces"
    priority: 64
    active: abierto
    islandWidth: 480
    islandHeight: 560

    property bool abierto: false

    //  State changed by the components, so their responses are visible.
    property bool encendido: true
    property real nivel: 40
    property bool baldosaActiva: false
    property int pulsaciones: 0

    view: Component { PiezasView { plugin: self } }

    K4.Ipc {
        target: "k4.piezas"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void { self.abierto = false }
        function estado(): string {
            return JSON.stringify({ encendido: self.encendido,
                                    nivel: self.nivel,
                                    baldosa: self.baldosaActiva,
                                    pulsaciones: self.pulsaciones })
        }
    }
}
