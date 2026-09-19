//  Snake in the island: a game built with the public API.
//
//  The game uses only K4 and QtQuick: board state lives in the plugin,
//  a Timer advances it, arrow keys control it with exclusive keyboard
//  access only during play, and K4.Guardado stores the high score.
//
//      cp -r ejemplos/snake ~/.config/k4/plugins/
//      quickshell ipc -p …/shell.qml call k4 pluginEnable snake
//      quickshell ipc -p …/shell.qml call k4.snake toggle

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "snake"
    title: "Snake"
    priority: 66
    active: abierto
    //  Exclusive keyboard access only while the game is running. Optional
    //  access is enough on the start screen, so Escape still belongs to the
    //  desktop until play starts.
    grabKeyboard: abierto && enMarcha
    tecladoOpcional: abierto
    islandWidth: 460
    islandHeight: 420

    property bool abierto: false

    // ── the board ─────────────────────────────────────────────────
    //  17×14 cells: fits in the island at 24 pixels per cell, with room for
    //  the score. The snake is a list of indices (x + y*ancho), head first.
    readonly property int ancho: 17
    readonly property int alto: 14

    property var serpiente: []
    property int comida: -1
    property int dx: 1
    property int dy: 0
    //  Apply the pending turn on the tick, not the keypress: two turns
    //  between ticks would let the snake reverse into its own neck,
    //  causing an unfair death.
    property int pdx: 1
    property int pdy: 0
    property bool enMarcha: false
    property bool muerto: false
    property int puntos: 0
    property int record: 0

    view: Component { SnakeView { plugin: self } }

    property var guardado: K4.Guardado {
        plugin: "snake"
        onCargado: function (d) { self.record = d.record || 0 }
    }

    function empezar() {
        const c = Math.floor(alto / 2) * ancho + 3
        serpiente = [c + 2, c + 1, c]
        dx = 1; dy = 0; pdx = 1; pdy = 0
        puntos = 0
        muerto = false
        enMarcha = true
        soltarComida()
    }

    function soltarComida() {
        //  Pick an empty cell. A nearly full board may take several tries;
        //  with 238 cells, this is not a practical concern.
        let sitio = -1
        do {
            sitio = Math.floor(Math.random() * ancho * alto)
        } while (serpiente.indexOf(sitio) >= 0)
        comida = sitio
    }

    function girar(gx, gy) {
        if (!enMarcha)
            return
        // No reversing direction: the snake cannot move backward.
        if (gx === -dx && gy === -dy)
            return
        pdx = gx
        pdy = gy
    }

    function tick() {
        dx = pdx
        dy = pdy
        const cabeza = serpiente[0]
        const x = cabeza % ancho + dx
        const y = Math.floor(cabeza / ancho) + dy

        //  Hitting the edge or the snake ends the game. The tail could be
        //  exempt when it moves away on this tick, but that adds complexity:
        //  here the tail counts, as in the Nokia game.
        const nueva = y * ancho + x
        if (x < 0 || x >= ancho || y < 0 || y >= alto
                || serpiente.indexOf(nueva) >= 0) {
            enMarcha = false
            muerto = true
            if (puntos > record) {
                record = puntos
                guardado.guardar({ record: record })
            }
            return
        }

        let s = [nueva].concat(serpiente)
        if (nueva === comida) {
            puntos += 1
            soltarComida()
            // Keep the tail: eating makes the snake grow.
        } else {
            s.pop()
        }
        serpiente = s
    }

    //  Each piece of food speeds up the tick: it starts slowly and runs
    //  twice as fast at 30 points, following the original game's curve.
    property var reloj: Timer {
        interval: Math.max(90, 180 - self.puntos * 3)
        repeat: true
        running: self.enMarcha && self.abierto
        onTriggered: self.tick()
    }

    K4.Ipc {
        target: "k4.snake"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void { self.abierto = false; self.enMarcha = false }
        //  Test the game without a mouse or window: start, turn, and read
        //  its state over IPC.
        function empezar(): void { self.empezar() }
        function girar(gx: int, gy: int): void { self.girar(gx, gy) }
        function estado(): string {
            return JSON.stringify({
                enMarcha: self.enMarcha, muerto: self.muerto,
                puntos: self.puntos, record: self.record,
                largo: self.serpiente.length,
                cabeza: self.serpiente[0], comida: self.comida,
                ancho: self.ancho })
        }
    }
}
