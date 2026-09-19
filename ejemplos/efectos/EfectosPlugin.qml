//  The island as a stage: tint the whole bar, request physical gestures,
//  and draw outside it in a separate window.
//
//  Copy the folder to ~/.config/k4/plugins/efectos, enable it in Settings,
//  and open it with `quickshell ipc -p <path>/shell.qml call k4.efectos toggle`.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "efectos"
    title: "Effects"
    priority: 64
    active: abierto
    islandWidth: 620
    islandHeight: 168

    property bool abierto: false
    //  The hand lives separately from the island: it can keep waving with
    //  the module closed, just as a mascot would.
    property bool manoFuera: false


    view: Component { EfectosView { plugin: self } }

    //  The hand's window exists only while needed.
    property var cargadorMano: K4.Cargador {
        active: self.manoFuera
        Mano { plugin: self }
    }

    K4.Ipc {
        target: "k4.efectos"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void {
            self.abierto = false
            self.manoFuera = false
        }
        function tinte(color: string): void {
            K4.Tema.tintar("efectos", color, 0.35, 4000)
        }
        function gesto(nombre: string): void {
            K4.Isla.efecto("efectos", nombre)
        }
        function mano(): void { self.manoFuera = !self.manoFuera }
        function paseo(fraccion: string): void {
            K4.Isla.colocar("efectos", Number(fraccion), 3000)
        }
    }
}
