//  The in-house text cursor, with a motion trail.
//
//  Use as a text field's `cursorDelegate`. The field supplies x, y and
//  height; this component only decides how to draw it. It matches k4term's
//  moving cursor so typing feels consistent between the terminal and the
//  rest of the island.
//
//      TextInput { cursorDelegate: K4.Estela {} }
//
//  With core's `IslandCursor`, even the color is supplied for you.
//
//  The trail RECORDS positions rather than interpolating between endpoints:
//  it must show the cursor's actual accelerated path, which a declarative
//  animation does not know. Hence the sampling timer and no `Behavior on x`.

import QtQuick

Item {
    id: raiz

    //  Number of trail segments. Set 0 for an ordinary cursor without a trail.
    property int largo: 8
    property color color: Tema.tinta
    property int grosor: 2
    //  Standard blinking, but only while stationary: blinking in mid-motion
    //  would break the trail.
    property bool parpadeo: true

    width: grosor

    //  Positions use field coordinates, as the trail does. The cursor itself
    //  moves, so recording positions relative to it would be incorrect.
    //
    //  Initialize explicitly rather than binding to x/y: a binding would
    //  place the cursor at its destination before the first timer tick,
    //  leaving the first movement without a trail.
    property real pintadoX: 0
    property real pintadoY: 0
    property var fantasmas: []
    property bool moviendose: false

    Component.onCompleted: {
        pintadoX = x
        pintadoY = y
    }

    onXChanged: latido.start()
    onYChanged: latido.start()
    onLargoChanged: if (largo === 0) fantasmas = []

    Timer {
        id: latido
        interval: 16
        repeat: true
        onTriggered: {
            const dx = Math.abs(raiz.x - raiz.pintadoX)
            const dy = Math.abs(raiz.y - raiz.pintadoY)
            const anterior = { x: raiz.pintadoX, y: raiz.pintadoY }

            //  Greater distance means greater speed: jumping to the end of
            //  a line stays quick, while moving one character remains smooth.
            //  A very large jump is a new location; snap to it directly.
            const alto = Math.max(1, raiz.height)
            const lejos = (dx + dy) / alto
            const paso = Math.min(0.35 + lejos * 0.06, 0.75)

            if (dy > alto * 12) {
                raiz.pintadoX = raiz.x
                raiz.pintadoY = raiz.y
            } else {
                raiz.pintadoX += (raiz.x - raiz.pintadoX) * paso
                raiz.pintadoY += (raiz.y - raiz.pintadoY) * paso
            }

            //  Within half a pixel, consider it settled. Stopping here avoids
            //  leaving a roughly 60 Hz timer running forever in a shell that
            //  spends most of its time idle.
            const quieto = Math.abs(raiz.pintadoX - raiz.x) < 0.5
                        && Math.abs(raiz.pintadoY - raiz.y) < 0.5
            if (quieto) {
                raiz.pintadoX = raiz.x
                raiz.pintadoY = raiz.y
            }

            let rastro = raiz.fantasmas.slice()
            if (raiz.largo > 0) {
                if (quieto) {
                    //  Once stationary, drain one trail segment per tick.
                    //  Recording the stationary position instead would keep
                    //  the trail attached forever and prevent the timer
                    //  from ever stopping.
                    rastro.shift()
                } else {
                    rastro.push(anterior)
                    if (rastro.length > raiz.largo)
                        rastro = rastro.slice(rastro.length - raiz.largo)
                }
            } else {
                rastro = []
            }
            raiz.fantasmas = rastro
            raiz.moviendose = !quieto || rastro.length > 0

            if (!raiz.moviendose)
                latido.stop()
        }
    }

    //  Trail segments, oldest to newest with increasing opacity. Declare
    //  them before the cursor so it stays above them. Subtract the cursor's
    //  position because these are its children and it moves independently.
    Repeater {
        model: raiz.fantasmas

        delegate: Rectangle {
            required property var modelData
            required property int index
            x: modelData.x - raiz.x
            y: modelData.y - raiz.y
            width: raiz.grosor
            height: raiz.height
            color: raiz.color
            opacity: (index + 1) / Math.max(1, raiz.fantasmas.length) * 0.35
        }
    }

    Rectangle {
        id: barra
        x: raiz.pintadoX - raiz.x
        y: raiz.pintadoY - raiz.y
        width: raiz.grosor
        height: raiz.height
        color: raiz.color

        //  Blink while stationary; stay fully visible while moving. Restore
        //  full opacity before blinking resumes, or the first blink could
        //  leave the cursor invisible just as typing stops.
        opacity: 1
        SequentialAnimation on opacity {
            running: raiz.parpadeo && !raiz.moviendose
            loops: Animation.Infinite
            alwaysRunToEnd: false
            PauseAnimation { duration: 530 }
            NumberAnimation { to: 0; duration: 90 }
            PauseAnimation { duration: 440 }
            NumberAnimation { to: 1; duration: 90 }
        }
        onOpacityChanged: if (raiz.moviendose && opacity !== 1) opacity = 1
    }
}
