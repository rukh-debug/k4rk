//  The terminal inside the island.
//
//  Nothing is emulated here: what gets painted is the grid k4term-isla
//  sends, already resolved by ghostty's VT, and what gets typed is
//  handed back as-is. The view is a window onto a session that lives
//  outside — which is why closing it stops nothing and reopening leaves
//  you where you were.
//
//  The keyboard: while open it keeps all of it, like the launcher or
//  the AI question. But ESC does NOT close —it goes to the terminal—,
//  and there the house convention is broken on purpose: ESC is the
//  cancel key of claude, of codex and of vim, and keeping it left those
//  programs with no way to receive it. To hide the view there is the
//  header button and the same key that opened it.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: vista

    //  Clipped, which is now needed: the content goes to the target size
    //  from the first moment and the box arrives behind, so while growing
    //  there are extra rows that must not spill out the bottom.
    clip: true

    required property var plugin

    readonly property var marco: plugin.marco

    //  The same font as the window terminal: truly monospaced, so the
    //  cell width comes from measuring one em.
    //
    //  The plugin takes the measurement, not this view, though the view
    //  uses it for everything: with it the plugin decides the island's
    //  height and with it the count of fitting rows is computed here,
    //  and those two numbers HAVE to come from the same place. When
    //  they did not —18 there, 17 here— the island asked for one row
    //  more than it had and never grew again.
    readonly property int cuerpo: plugin.cuerpo
    readonly property real anchoCelda: plugin.anchoCelda
    readonly property real altoLinea: plugin.altoLinea
    readonly property int margen: 14

    //  Home with a tilde and no more than three segments: in a
    //  ten-pixel foot, a whole path is not read, it gets in the way.
    function corto(ruta) {
        const casa = String(ruta).replace(/^\/home\/[^/]+/, "~")
        const partes = casa.split("/").filter(function (x) { return x.length > 0 })
        if (partes.length <= 3)
            return casa
        return (casa.charAt(0) === "~" ? "" : "…/") + partes.slice(-3).join("/")
    }

    //  How many columns and rows are asked of the session, the one that
    //  resizes the PTY: the shell must know its width or it wraps lines
    //  where it should not.
    //
    //  The rows are the island's DESTINATION, not those fitting the
    //  current height. The difference showed: since the height is
    //  animated, asking by current height made the PTY resize in chunks
    //  chasing the animation, and text arrived late and in stumbles —
    //  first the box moved then the content, or the other way. Asking
    //  for the destination from the first instant, the content is
    //  already where it will be and the box merely uncovers it.
    readonly property int cols: Math.max(20, Math.floor((width - margen * 2) / anchoCelda))
    readonly property int filas: Math.max(4, plugin.filasDeseadas)

    //  Where you are inside history, as the session tells it: the row
    //  what is seen starts at, and how many there are in all.
    readonly property int arriba: marco ? marco.scroll[0] : 0
    readonly property int historial: marco ? Math.max(1, marco.scroll[1]) : 1
    readonly property real recorrido: Math.min(1, (marco ? marco.filas_n : filas) / historial)
    readonly property real asomado: arriba / historial

    //  ── from pixels to cells ──────────────────────────────────────
    //
    //  Everything the mouse does passes through here, and that is why
    //  it lives in one place: the grid paints each run anchored at
    //  `(columna - 1) * anchoCelda`, so reading it backwards must do
    //  the same arithmetic or the click would land one cell left of
    //  where it looks.
    function colDe(x) {
        return Math.max(1, Math.min(cols, Math.floor((x - margen) / anchoCelda) + 1))
    }

    function filaDe(y) {
        const n = marco ? marco.filas_n : filas
        return Math.max(1, Math.min(n, Math.floor((y - margen - altoCabecera) / altoLinea) + 1))
    }

    //  The HISTORY row a grid row corresponds to. Everything kept —
    //  the selection, the marks— goes in these coordinates: they are
    //  the only ones that do not move while output keeps coming.
    //
    //  And it is not a subtraction: with folded output, the grid is no
    //  longer a tracing of the visible gap —one row can stand for
    //  fifty—, so the session dictates the correspondence, it is the
    //  one folding.
    function absoluta(filaVista) {
        if (marco && marco.filas_abs && filaVista >= 1 && filaVista <= marco.filas_abs.length)
            return marco.filas_abs[filaVista - 1]
        return arriba + filaVista - 1
    }

    //  The other way around: which grid row a history row has landed
    //  on, or -1 if it is not currently visible (folded, or off
    //  screen).
    function enRejilla(filaAbs) {
        if (!marco || !marco.filas_abs)
            return filaAbs - arriba
        for (let i = 0; i < marco.filas_abs.length; ++i)
            if (marco.filas_abs[i] === filaAbs)
                return i
        return -1
    }

    //  Is that grid row the line of a folded output?
    function esResumen(i) {
        return !!(marco && marco.resumidas && marco.resumidas.indexOf(i) >= 0)
    }

    //  Fold or unfold a command's output. Named by the history row it
    //  starts at: grid indexes change the moment one more line comes
    //  out.
    function plegar(filaAbs) {
        if (filaAbs !== undefined && filaAbs >= 0)
            plugin.mandar({ que: "plegar", fila: filaAbs })
    }

    function plegarUltimo() {
        if (ultimoBloque && ultimoBloque.fin > ultimoBloque.fila)
            plegar(ultimoBloque.fila)
    }

    //  A grid row as text, padding the gaps between runs with spaces:
    //  runs come with their column, and without the padding the
    //  positions would not line up with what is seen.
    function textoFila(i) {
        if (!marco || i < 0 || i >= marco.filas.length)
            return ""
        const tramos = marco.filas[i]
        let linea = ""
        for (let k = 0; k < tramos.length; ++k) {
            while (linea.length < tramos[k].c - 1)
                linea += " "
            linea += tramos[k].t
        }
        return linea
    }

    //  ── the selection ─────────────────────────────────────────────
    //
    //  Two ends in history coordinates. Kept exactly as clicked,
    //  unsorted: which way you are going is the dragger's business,
    //  and sorting them on the fly is cheaper than keeping them
    //  sorted.
    property var selA: null
    property var selB: null
    readonly property bool haySeleccion: selA !== null && selB !== null

    function ordenada() {
        if (!haySeleccion)
            return null
        const antes = selA.fila < selB.fila
                   || (selA.fila === selB.fila && selA.col <= selB.col)
        return antes ? { desde: selA, hasta: selB } : { desde: selB, hasta: selA }
    }

    function limpiarSeleccion() { selA = null; selB = null }

    //  Which stretch of grid row `i` is selected, or nothing.
    function tramoSeleccion(i) {
        const s = ordenada()
        if (!s)
            return null
        const abs = absoluta(i + 1)
        if (abs < s.desde.fila || abs > s.hasta.fila)
            return null
        const a = abs === s.desde.fila ? s.desde.col : 1
        const b = abs === s.hasta.fila ? s.hasta.col : cols
        return b >= a ? { a: a, b: b } : null
    }

    //  The SESSION composes the text, it is the one holding history:
    //  the grid only knows what is visible, and a selection can start
    //  higher than what is on screen.
    function copiarSeleccion(motivo) {
        const s = ordenada()
        if (!s)
            return false
        plugin.mandar({ que: "texto_de",
                        desde: s.desde.fila, hasta: s.hasta.fila,
                        col_desde: s.desde.col, col_hasta: s.hasta.col,
                        motivo: motivo || "copiar" })
        return true
    }

    function seleccionarTodo() {
        selA = { fila: absoluta(1), col: 1 }
        selB = { fila: absoluta(marco ? marco.filas_n : filas), col: cols }
    }

    //  Double click: the word underneath. «Word» is what is neither
    //  space nor quote — in a terminal what one wants to grab is
    //  almost always a path, a hash or a URL, and splitting them at
    //  dots or slashes would be exactly the opposite of what is
    //  sought.
    function palabraEn(filaVista, col) {
        const linea = textoFila(filaVista - 1)
        if (col > linea.length)
            return null
        const corte = /[\s"'`]/
        if (corte.test(linea.charAt(col - 1)))
            return null
        let a = col, b = col
        while (a > 1 && !corte.test(linea.charAt(a - 2)))
            --a
        while (b < linea.length && !corte.test(linea.charAt(b)))
            ++b
        return { a: a, b: b }
    }

    //  A link under that cell, if any.
    //
    //  First the real one: the OSC 8 one, which the application hid
    //  behind the text and travels in the run. If there is none, it is
    //  guessed by looking at whether something looks like an address,
    //  which is what saves `ls` and the error messages of all time.
    function urlEn(filaVista, col) {
        const tramos = marco && marco.filas[filaVista - 1] ? marco.filas[filaVista - 1] : []
        for (let k = 0; k < tramos.length; ++k) {
            const tr = tramos[k]
            if (tr.u && col >= tr.c && col < tr.c + tr.t.length)
                return tr.u
        }

        const linea = textoFila(filaVista - 1)
        const patron = /(https?:\/\/|www\.)[^\s"'`<>()\[\]]+/g
        let m
        while ((m = patron.exec(linea)) !== null) {
            const a = m.index + 1
            const b = m.index + m[0].length
            if (col >= a && col <= b)
                return m[0]
        }
        return ""
    }

    //  ── search ────────────────────────────────────────────────────
    //
    //  The split: digging through history belongs to the session, the
    //  one keeping it; painting what is visible yellow belongs here,
    //  which already has the text in front and needs to ask nothing.
    property bool buscando: false

    function abrirBusqueda() {
        buscando = true
        campoBusqueda.forceActiveFocus()
        campoBusqueda.selectAll()
    }

    function cerrarBusqueda() {
        buscando = false
        plugin.aguja = ""
        plugin.sinRastro = false
        plugin.filaHallada = -1
        campo.forceActiveFocus()
    }

    //  At which columns the searched-for shows up on grid row `i`.
    function hallazgosEn(i) {
        const aguja = String(plugin.aguja).toLowerCase()
        if (!buscando || aguja.length === 0)
            return []
        const linea = textoFila(i).toLowerCase()
        const sitios = []
        let donde = linea.indexOf(aguja)
        while (donde >= 0) {
            sitios.push(donde + 1)
            donde = linea.indexOf(aguja, donde + aguja.length)
        }
        return sitios
    }

    //  ── the blocks ────────────────────────────────────────────────
    //
    //  What the session already knew and was not visible: where each
    //  command starts and how it ended. The margin's fillet is that,
    //  and nothing more — nothing until it means something.
    readonly property var ultimoBloque: marco && marco.ultimo ? marco.ultimo : null

    //  Ctrl+Shift+N to go to terminal N. With Shift, the number row
    //  gives a different symbol per layout —Spanish `!\"·$%&/()`,
    //  American `!@#$%^&*(`— and Qt delivers THAT symbol, not the
    //  digit: looking only at digits would leave the shortcut dead in
    //  half the world.
    readonly property var simbolosNumero: [
        [Qt.Key_Exclam, Qt.Key_QuoteDbl, 0xb7, Qt.Key_Dollar, Qt.Key_Percent,
         Qt.Key_Ampersand, Qt.Key_Slash, Qt.Key_ParenLeft, Qt.Key_ParenRight],
        [Qt.Key_Exclam, Qt.Key_At, Qt.Key_NumberSign, Qt.Key_Dollar, Qt.Key_Percent,
         Qt.Key_AsciiCircum, Qt.Key_Ampersand, Qt.Key_Asterisk, Qt.Key_ParenLeft]
    ]

    function numeroDe(tecla) {
        if (tecla >= Qt.Key_1 && tecla <= Qt.Key_9)
            return tecla - Qt.Key_1 + 1
        for (let d = 0; d < simbolosNumero.length; ++d) {
            const donde = simbolosNumero[d].indexOf(tecla)
            if (donde >= 0)
                return donde + 1
        }
        return 0
    }

    function copiarUltimaSalida() {
        if (!ultimoBloque)
            return
        //  The start mark lands on the output's FIRST row, and the end
        //  mark on the one after the last —that is where the shell will
        //  paint its next prompt—, so the last good one is `fin - 1`.
        //  While the command runs there is no end: it copies as far as
        //  it reaches.
        plugin.mandar({ que: "texto_de",
                        desde: ultimoBloque.fila,
                        hasta: ultimoBloque.fin > ultimoBloque.fila
                             ? ultimoBloque.fin - 1 : 0,
                        motivo: "copiar" })
    }

    onColsChanged: medir.restart()
    onFilasChanged: medir.restart()
    Component.onCompleted: {
        plugin.mandar({ que: "medida", cols: cols, filas: filas })
        plugin.mandar({ que: "pinta" })
        forzarFoco.start()
        pintadoX = destinoX
        pintadoY = destinoY
    }


    Timer {
        id: medir
        //  Short on purpose: it only exists to join the row change with
        //  the column one if they arrive together, not to wait for
        //  anything.
        interval: 16
        onTriggered: vista.plugin.mandar({ que: "medida", cols: vista.cols,
                                           filas: vista.filas })
    }

    //  Focus arrives a hair after the island opens; without this wait
    //  the first keys are lost.
    Timer {
        id: forzarFoco
        interval: 60
        onTriggered: campo.forceActiveFocus()
    }

    //  ── the header: which terminals there are and how to hide them ──
    //
    //  Always a strip, even with a single session: with one it acts as
    //  title —it says what runs inside and where— and with several it
    //  is the selector. Appearing and disappearing by count would
    //  move the whole grid out of place every time you open a new
    //  terminal.
    readonly property int altoCabecera: 22

    Item {
        id: cabecera
        x: vista.margen
        y: 6
        width: vista.width - vista.margen * 2
        height: vista.altoCabecera

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: vista.plugin.vivas

                delegate: Rectangle {
                    id: pestana
                    required property var modelData
                    required property int index

                    readonly property bool esta: index === vista.plugin.actual

                    //  What runs in here and whether it is calling you.
                    //  The plugin's MAPS are read, not a function
                    //  looking inside them: a QML binding only
                    //  re-evaluates when a PROPERTY it read changes,
                    //  and with `trabajos` buried inside a call the
                    //  tab would keep whatever was there at birth. It
                    //  is `advanceWidth`'s trap.
                    readonly property string clave: "isla." + modelData.numero
                    readonly property var trabajo: vista.plugin.trabajos[clave]
                    readonly property bool llamando:
                        vista.plugin.esperas[clave] !== undefined

                    //  The bell first: an agent having finished its
                    //  shift and waiting for you matters more than
                    //  knowing it keeps thinking. With neither, the
                    //  tab goes clean.
                    readonly property var insignia: llamando
                        ? ({ glifo: Theme.ico.bell.codePointAt(0),
                             color: Theme.yellow })
                        : (trabajo ? vista.plugin.insigniaDe(trabajo.mandato)
                                   : null)

                    //  WHERE you are and WHAT runs, both things. It
                    //  used to be one or the other, and with two
                    //  agents in two repos the title alone tells
                    //  nothing apart: what separates them is the
                    //  directory, and what says which one walks where
                    //  is the command.
                    readonly property string donde: modelData.cwd
                        ? vista.corto(modelData.cwd)
                        : "terminal" + " " + (index + 1)

                    //  What runs, bare: the program, no path no
                    //  arguments, the only thing readable in a
                    //  two-finger tab. The jobs clock puts it, and it
                    //  only counts what has been alive a few seconds:
                    //  hence this does not blink with every `ls`, and
                    //  hence a resting tab says nothing extra.
                    //
                    //  The application's title does NOT go here, however
                    //  tempting. A resting shell puts it in
                    //  `abel@abel:~`, the directory again in worse
                    //  lettering; and what does have its own title
                    //  —vim, btop— is exactly what the clock is
                    //  already counting.
                    readonly property string que: trabajo
                        ? vista.plugin.programaDe(trabajo.mandato) : ""

                    readonly property string nombre:
                        que ? donde + "  ·  " + que : donde

                    height: vista.altoCabecera - 4
                    //  The cross's slot is ALWAYS reserved even when the
                    //  cross is invisible: if it appeared on hover, the
                    //  tab would grow and push the others exactly as
                    //  you go to click them.
                    width: fila.width + 18 + 14
                    radius: height / 2
                    color: esta ? Theme.surfaceHi : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: fila
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        //  The same glyph its pill wears, and for the
                        //  same reason: knowing WHICH of the four has
                        //  the agent waiting for you without tabbing
                        //  through them. A row skips what it cannot see
                        //  on its own, so without a badge not even the
                        //  slot remains.
                        IconGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pestana.insignia !== null
                            text: visible
                                ? String.fromCodePoint(pestana.insignia.glifo)
                                : ""
                            color: visible ? pestana.insignia.color : Theme.dim
                            font.pixelSize: 11
                        }

                        IslandLabel {
                            id: etiqueta
                            anchors.verticalCenter: parent.verticalCenter
                            text: (pestana.index + 1) + "  " + pestana.nombre
                            color: pestana.esta ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            //  A long name cannot push the rest out.
                            width: Math.min(implicitWidth, 190)
                        }
                    }

                    MouseArea {
                        id: pestanaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function (raton) {
                            //  The middle button closes, as in any tab;
                            //  the left one goes to it.
                            if (raton.button === Qt.MiddleButton)
                                vista.plugin.cerrarSesion(parent.index)
                            else
                                vista.plugin.irA(parent.index)
                        }
                    }

                    //  Close this terminal. Only on approach: at rest
                    //  the header says what there is, it does not offer
                    //  buttons.
                    IslandLabel {
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        font.pixelSize: 10
                        color: aspaRaton.containsMouse ? Theme.ink : Theme.muted
                        opacity: pestanaRaton.containsMouse || aspaRaton.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        MouseArea {
                            id: aspaRaton
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vista.plugin.cerrarSesion(parent.parent.index)
                        }
                    }
                }
            }

            //  One more.
            IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0415)
                color: masRaton.containsMouse ? Theme.ink : Theme.dim
                font.pixelSize: 13

                MouseArea {
                    id: masRaton
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.nueva()
                }
            }
        }

        //  Hide it without touching what runs inside. It exists
        //  because ESC no longer closes: the terminal takes it.
        IconGlyph {
            id: menos
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0374)
            color: menosRaton.containsMouse ? Theme.ink : Theme.dim
            font.pixelSize: 14

            MouseArea {
                id: menosRaton
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: vista.plugin.cerrar()
            }
        }
    }

    //  ── the grid ─────────────────────────────────────────────────────
    //
    //  A terminal is NOT chained text: it is a lattice of equal cells,
    //  and each run goes in the column it belongs to. Painting by
    //  column and not by natural width is not a quirk —it is the only
    //  way it lines up—: the moment a glyph that does not measure the
    //  same as the rest appears (claude's box frames, a Nerd Font
    //  icon, a hard space), chaining advances shifts the line right
    //  while the cursor, which does go by column, stays where it
    //  should. The result was exactly that: the cursor «drifted» from
    //  the text.
    //
    //  So the glyph's width chooses the drawing and the GRID decides
    //  where it goes. Each row is a canvas and each run anchors at
    //  `(columna - 1) * anchoCelda`, so a crooked run does not drag
    //  the ones after it.
    //  The selection, UNDER the text: declared before the grid on
    //  purpose, since in QML the last declared is what sits on top,
    //  and a selection covering the letters is good for nothing.
    Repeater {
        model: vista.marco ? vista.marco.filas.length : 0

        delegate: Rectangle {
            required property int index
            readonly property var tramo: vista.tramoSeleccion(index)

            visible: tramo !== null
            x: vista.margen + ((tramo ? tramo.a : 1) - 1) * vista.anchoCelda
            y: vista.margen + vista.altoCabecera + index * vista.altoLinea
            width: tramo ? (tramo.b - tramo.a + 1) * vista.anchoCelda : 0
            height: vista.altoLinea
            color: Theme.blue
            opacity: 0.3
        }
    }

    //  What was searched for, highlighted on every row it peeks
    //  from: the active one solid and the others hinted. Also under
    //  the text.
    Repeater {
        model: vista.buscando && vista.marco ? vista.marco.filas.length : 0

        delegate: Item {
            id: filaBuscada
            required property int index
            readonly property bool esLaBuena: vista.absoluta(index + 1) === vista.plugin.filaHallada

            Repeater {
                model: vista.hallazgosEn(filaBuscada.index)

                delegate: Rectangle {
                    required property var modelData

                    x: vista.margen + (modelData - 1) * vista.anchoCelda
                    y: vista.margen + vista.altoCabecera
                       + filaBuscada.index * vista.altoLinea
                    width: String(vista.plugin.aguja).length * vista.anchoCelda
                    height: vista.altoLinea
                    color: Theme.yellow
                    opacity: filaBuscada.esLaBuena ? 0.5 : 0.25
                }
            }
        }
    }

    //  Each command's fillet: two pixels in the margin, green if it
    //  went well and red if not. It is the blocks' aspect done the
    //  house way — it takes no space, asks for nothing and only
    //  appears when there is something to say.
    Repeater {
        model: vista.marco && vista.marco.bloques ? vista.marco.bloques : []

        delegate: Item {
            required property var modelData
            readonly property int enFila: vista.enRejilla(modelData.fila)

            visible: enFila >= 0
            x: vista.margen - 12
            y: vista.margen + vista.altoCabecera + enFila * vista.altoLinea
            width: 10
            height: vista.altoLinea

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 4
                width: 2
                height: parent.height
                radius: 1
                color: parent.modelData.estado === "bien" ? Theme.green
                     : (parent.modelData.estado === "mal" ? Theme.red : Theme.muted)
                opacity: parent.modelData.estado === "corre" ? 0.6
                       : (filete.containsMouse ? 1 : 0.9)
            }

            //  Clicking the fillet folds that command's output. It is
            //  the natural spot —it marks exactly the block— but two
            //  pixels cannot be hit with a mouse, so the sensitive
            //  zone is wider than the stripe.
            MouseArea {
                id: filete
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: parent.modelData.fin > parent.modelData.fila
                onClicked: vista.plegar(parent.modelData.fila)
            }
        }
    }

    Column {
        id: rejilla
        x: vista.margen
        y: vista.margen + vista.altoCabecera
        spacing: 0

        Repeater {
            model: vista.marco ? vista.marco.filas : []

            delegate: Item {
                required property var modelData
                required property int index
                width: vista.width - vista.margen * 2
                height: vista.altoLinea

                //  A folded output's line stands out: a soft
                //  background saying «something is folded here», and
                //  the mouse as a hand when passing over it.
                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: parent.width * 0.55
                    visible: vista.esResumen(parent.index)
                    color: Theme.surfaceHi
                    opacity: 0.35
                    radius: 4
                }

                //  Quiet mode: what came before the last command dims.
                //  In a long session with an agent inside, knowing
                //  where the new part starts is worth more than any
                //  color.
                opacity: vista.plugin.tranquilo && vista.ultimoBloque
                         && vista.absoluta(index + 1) < vista.ultimoBloque.fila ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }

                Repeater {
                    model: parent.modelData

                    delegate: Item {
                        required property var modelData
                        //  Its place in the grid, not wherever the
                        //  neighbor ended.
                        x: (modelData.c - 1) * vista.anchoCelda
                        width: modelData.t.length * vista.anchoCelda
                        height: vista.altoLinea

                        Rectangle {
                            anchors.fill: parent
                            color: modelData.b
                            visible: modelData.b !== String(Theme.islandBg)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            //  **The most important thing in the whole
                            //  file.**
                            //
                            //  This is your commands' output: bytes
                            //  coming from wherever they come from.
                            //  Without `PlainText`, a `cat` of a file
                            //  with `<img src="http://…">` inside
                            //  would make the bar go out and request
                            //  that image. The VT already carries its
                            //  own bold by bits; markup paints
                            //  nothing here.
                            textFormat: Text.PlainText
                            text: modelData.t
                            color: modelData.f
                            font.family: plugin.fuente
                            font.pixelSize: vista.cuerpo
                            //  The VT's 0x02 bit is bold.
                            font.weight: (modelData.n & 0x02) ? Font.Bold : Font.Normal
                            font.italic: (modelData.n & 0x04) !== 0
                            font.underline: (modelData.n & 0x08) !== 0
                            font.strikeout: (modelData.n & 0x40) !== 0
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }

    //  ── the cursor and its trail ─────────────────────────────────────
    //
    //  The cursor goes apart from the rows: it belongs to the session,
    //  not to the text. And it does not teleport, it glides leaving a
    //  trail — the same trail as the window, with the same curve,
    //  because they are the same terminal and it would not be
    //  understood for one to have the effect and not the other.
    //
    //  How many ghosts is the session's say, it reads k4term's
    //  settings: nothing is decided here, only painted.
    //
    //  No `Behavior on x`: what wants to be shown is the REAL path,
    //  with its acceleration, so where it has been is kept instead of
    //  interpolating when painting. Hence a heartbeat instead of an
    //  animation.
    readonly property real destinoX: margen + (marco ? (marco.cursor[0] - 1) : 0) * anchoCelda
    readonly property real destinoY: margen + altoCabecera + (marco ? (marco.cursor[1] - 1) : 0) * altoLinea

    //  Initialized by hand and not by a binding to `destino`: a
    //  binding would plant the cursor at the destination BEFORE the
    //  first heartbeat, and that first move —the only one visible on
    //  opening— would come out without a trail.
    property real pintadoX: 0
    property real pintadoY: 0
    property var fantasmas: []

    onDestinoXChanged: latido.start()
    onDestinoYChanged: latido.start()

    Timer {
        id: latido
        interval: 16
        repeat: true
        onTriggered: {
            const dx = Math.abs(vista.destinoX - vista.pintadoX)
            const dy = Math.abs(vista.destinoY - vista.pintadoY)
            const anterior = { x: vista.pintadoX, y: vista.pintadoY }

            //  The farther, the faster: that way a line jump does not
            //  drag and moving one letter stays smooth. And a huge
            //  jump is a new screen, not a movement: it plants there.
            const lejos = (dx + dy) / Math.max(1, vista.altoLinea)
            const paso = Math.min(0.35 + lejos * 0.06, 0.75)
            const enorme = dy > vista.altoLinea * 12

            if (enorme) {
                vista.pintadoX = vista.destinoX
                vista.pintadoY = vista.destinoY
            } else {
                vista.pintadoX += (vista.destinoX - vista.pintadoX) * paso
                vista.pintadoY += (vista.destinoY - vista.pintadoY) * paso
            }

            //  Under half a pixel it is already in place. Stopping
            //  the beat here is what avoids burning a timer forever.
            const quieto = Math.abs(vista.pintadoX - vista.destinoX) < 0.5
                        && Math.abs(vista.pintadoY - vista.destinoY) < 0.5
            if (quieto) {
                vista.pintadoX = vista.destinoX
                vista.pintadoY = vista.destinoY
            }

            let rastro = vista.fantasmas.slice()
            if (vista.plugin.estela > 0) {
                if (quieto) {
                    //  Still, the trail folds itself: one less per
                    //  beat until empty. No keep noting the still
                    //  position —that leaves the trail glued to the
                    //  cursor forever and the beat never stops.
                    rastro.shift()
                } else {
                    rastro.push(anterior)
                    if (rastro.length > vista.plugin.estela)
                        rastro = rastro.slice(rastro.length - vista.plugin.estela)
                }
            } else {
                rastro = []
            }
            vista.fantasmas = rastro

            if (quieto && rastro.length === 0)
                latido.stop()
        }
    }

    //  The ghosts, oldest to newest and ever more present. Declared
    //  before the cursor so it stays on top.
    Repeater {
        model: vista.fantasmas

        delegate: Rectangle {
            required property var modelData
            required property int index
            x: modelData.x
            y: modelData.y + (vista.figuraCursor === "subrayado"
                              ? vista.altoLinea - vista.altoCursor : 0)
            width: vista.anchoCursor
            height: vista.altoCursor
            color: Theme.ink
            opacity: (index + 1) / Math.max(1, vista.fantasmas.length) * 0.35
        }
    }

    //  Whatever shape the program asks for (DECSCUSR): bar while
    //  typing, block in vim's normal mode, underline if asked. And if
    //  it asks for blinking, it blinks — but only it: not the trail's
    //  ghosts, which would be a disco.
    readonly property string figuraCursor: marco && marco.cursor_figura
        ? marco.cursor_figura : "barra"
    readonly property real anchoCursor: figuraCursor === "bloque" ? anchoCelda : 2
    readonly property real altoCursor: figuraCursor === "subrayado" ? 2 : altoLinea

    Rectangle {
        id: cursor

        visible: vista.marco !== null
        x: vista.pintadoX
        y: vista.pintadoY + (vista.figuraCursor === "subrayado"
                             ? vista.altoLinea - vista.altoCursor : 0)
        width: vista.anchoCursor
        height: vista.altoCursor
        color: Theme.ink
        //  The block is translucent on purpose: it covers the letter
        //  underneath and it reads the same, which is what a terminal
        //  does when inverting.
        opacity: vista.figuraCursor === "bloque" ? 0.45 : 0.9

        Behavior on width { NumberAnimation { duration: 90 } }
        Behavior on height { NumberAnimation { duration: 90 } }

        SequentialAnimation on opacity {
            running: vista.marco !== null && vista.marco.cursor_parpadea === true
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.05; duration: 530; easing.type: Easing.InOutQuad }
            NumberAnimation {
                to: vista.figuraCursor === "bloque" ? 0.45 : 0.9
                duration: 530
                easing.type: Easing.InOutQuad
            }
        }
    }

    //  ── the mouse ─────────────────────────────────────────────────
    //
    //  Two possible owners and one rule to decide: if the application
    //  inside has asked for the mouse (htop, vim, claude's interface),
    //  the clicks are ITS OWN and nothing gets selected here; if not,
    //  they are the view's, which uses them to select and copy. Shift
    //  always forces the second case — the age-old emergency exit to
    //  copy inside a program that keeps the mouse.
    //
    //  Declared before the scrollbar so dragging it stays its
    //  business, and with the top margin just under the header,
    //  since the tabs have their own clicks.
    MouseArea {
        id: raton

        //  How much lower this receiver sits than the view. Mouse
        //  events come in ITS coordinates, not the view's, so without
        //  adding it the row count comes out nearly two lines off —
        //  seen at first sight: a drag over one line selected three.
        readonly property int desfase: vista.altoCabecera + 4

        anchors.fill: parent
        anchors.topMargin: desfase
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: (enlace || sobreResumen) ? Qt.PointingHandCursor : Qt.IBeamCursor
        //  Over a folded output, the hand: there one clicks, one does
        //  not select.
        property bool sobreResumen: false

        //  A drag that has moved nothing yet is not a selection: if
        //  it were, every loose click would copy one letter to the
        //  primary.
        property bool arrastrando: false
        property bool movido: false
        property bool reportando: false
        property string enlace: ""

        function nombreBoton(b) {
            if (b === Qt.MiddleButton)
                return "medio"
            return b === Qt.RightButton ? "derecho" : "izquierdo"
        }

        function conMods(orden, m) {
            return Object.assign(orden, {
                shift: (m & Qt.ShiftModifier) !== 0,
                control: (m & Qt.ControlModifier) !== 0,
                alt: (m & Qt.AltModifier) !== 0
            })
        }

        function esSuyo(m) {
            return vista.marco && vista.marco.raton && (m & Qt.ShiftModifier) === 0
        }

        function contar(tipo, boton, x, y, m) {
            vista.plugin.mandar(conMods({ que: "raton", tipo: tipo, boton: boton,
                                          col: vista.colDe(x), fila: vista.filaDe(y + desfase) }, m))
        }

        onPressed: function (e) {
            campo.forceActiveFocus()

            if (esSuyo(e.modifiers)) {
                reportando = true
                contar("pulsar", nombreBoton(e.button), e.x, e.y, e.modifiers)
                return
            }
            reportando = false

            //  The middle one pastes the primary selection, as in any
            //  terminal ever.
            if (e.button === Qt.MiddleButton) {
                vista.plugin.pegar(true)
                return
            }
            if (e.button !== Qt.LeftButton)
                return

            //  Ctrl+click opens the link underneath, and then there is
            //  no selection to start.
            const url = (e.modifiers & Qt.ControlModifier)
                ? vista.urlEn(vista.filaDe(e.y + desfase), vista.colDe(e.x)) : ""
            if (url) {
                vista.plugin.abrirEnlace(url)
                return
            }

            //  Clicking a folded output unfolds it. It goes before
            //  selection: whoever clicks that line wants to open it,
            //  not to grab its text.
            const filaPulsada = vista.filaDe(e.y + desfase)
            if (vista.esResumen(filaPulsada - 1)) {
                vista.plegar(vista.absoluta(filaPulsada))
                return
            }

            vista.limpiarSeleccion()
            arrastrando = true
            movido = false
            const punto = { fila: vista.absoluta(vista.filaDe(e.y + desfase)),
                            col: vista.colDe(e.x) }
            vista.selA = punto
            vista.selB = punto
        }

        onPositionChanged: function (e) {
            if (reportando) {
                contar("mover", nombreBoton(pressedButtons & Qt.MiddleButton ? Qt.MiddleButton
                                          : (pressedButtons & Qt.RightButton ? Qt.RightButton
                                                                             : Qt.LeftButton)),
                       e.x, e.y, e.modifiers)
                return
            }

            if (arrastrando) {
                const punto = { fila: vista.absoluta(vista.filaDe(e.y + desfase)),
                                col: vista.colDe(e.x) }
                if (punto.fila !== vista.selA.fila || punto.col !== vista.selA.col)
                    movido = true
                vista.selB = punto
                return
            }

            //  No button: only whether there is a link underneath is
            //  looked at, and only with Ctrl, which is what opens it.
            //  Underlining everything that looks like a URL while you
            //  stroll with the mouse would be noise.
            const filaBajoElRaton = vista.filaDe(e.y + desfase)
            sobreResumen = vista.esResumen(filaBajoElRaton - 1)
            enlace = (e.modifiers & Qt.ControlModifier)
                ? vista.urlEn(filaBajoElRaton, vista.colDe(e.x)) : ""
        }

        onReleased: function (e) {
            if (reportando) {
                contar("soltar", nombreBoton(e.button), e.x, e.y, e.modifiers)
                reportando = false
                return
            }
            if (!arrastrando)
                return
            arrastrando = false

            //  On release, the selected goes to the primary: that is
            //  what whoever later pastes with the middle button
            //  expects.
            if (movido)
                vista.copiarSeleccion("primaria")
            else
                vista.limpiarSeleccion()
        }

        onDoubleClicked: function (e) {
            if (esSuyo(e.modifiers))
                return
            const fila = vista.filaDe(e.y + desfase)
            const tramo = vista.palabraEn(fila, vista.colDe(e.x))
            if (!tramo)
                return
            vista.selA = { fila: vista.absoluta(fila), col: tramo.a }
            vista.selB = { fila: vista.absoluta(fila), col: tramo.b }
            vista.copiarSeleccion("primaria")
        }

        //  The wheel: three lines per notch, as everywhere. Whoever
        //  decides whether it moves history or the application takes
        //  it is the session, the one knowing which modes are set;
        //  with shift it is told history is ours whatever happens.
        onWheel: function (rueda) {
            const pasos = rueda.angleDelta.y > 0 ? 3 : -3
            vista.plugin.mandar({ que: "rueda", lineas: -pasos,
                                  col: vista.colDe(rueda.x),
                                  fila: vista.filaDe(rueda.y + desfase),
                                  historial: (rueda.modifiers & Qt.ShiftModifier) !== 0 })
            rueda.accepted = true
        }
    }

    //  And the house's little bar, the same piece as the rest of the
    //  island: here it cannot hang off a Flickable —the grid is not
    //  one, history lives in the session— so `size` and `position`
    //  are given by hand from what the frame says. It comes out on
    //  its own when there is something to travel and fades when
    //  stopping, as everywhere.
    IslandScrollBar {
        id: barra

        orientation: Qt.Vertical
        anchors.right: parent.right
        anchors.rightMargin: 4
        y: vista.margen
        height: vista.height - vista.margen * 2

        size: vista.recorrido
        position: vista.asomado

        //  Dragging it also moves the session. On grabbing it, Qt
        //  writes to `position` and breaks the binding to the frame on
        //  the way; hence it is re-tied on release, otherwise the bar
        //  stays dead from the first drag and nobody says so.
        onPressedChanged: {
            if (pressed) {
                arrastre.start()
            } else {
                arrastre.stop()
                position = Qt.binding(function () { return vista.asomado })
            }
        }

        //  In tugs and not per pixel: the session only knows how to
        //  move relatively, so each beat recomputes what is missing
        //  from where it truly is. With that the error does not pile
        //  up even if frames arrive late.
        Timer {
            id: arrastre
            interval: 50
            repeat: true
            onTriggered: {
                const destino = Math.round(barra.position * vista.historial)
                const salto = destino - vista.arriba
                if (salto !== 0)
                    vista.plugin.mandar({ que: "rueda", lineas: salto })
            }
        }
    }

    Item {
        id: campo
        focus: true
        anchors.fill: parent

        readonly property var nombres: ({})

        Keys.onPressed: function (e) {
            const mods = {
                shift: (e.modifiers & Qt.ShiftModifier) !== 0,
                control: (e.modifiers & Qt.ControlModifier) !== 0,
                alt: (e.modifiers & Qt.AltModifier) !== 0
            }

            const conNombre = function (nombre) {
                vista.plugin.mandar(Object.assign({ que: "tecla", nombre: nombre }, mods))
                e.accepted = true
            }

            //  ── what belongs to the terminal and not to what runs
            //  inside it ──
            //
            //  All with Ctrl+Shift, same as the window and any modern
            //  terminal. This used to go with Alt and the price was
            //  steep: the programs inside were left without
            //  alt+arrows —how half the console walks by words— and
            //  without alt+letter for their own menus. Now Alt is
            //  wholly theirs again.
            if (mods.control && mods.shift) {
                switch (e.key) {
                case Qt.Key_V: vista.plugin.pegar(false); e.accepted = true; return
                case Qt.Key_C: vista.copiarSeleccion("copiar"); e.accepted = true; return
                case Qt.Key_A: vista.seleccionarTodo(); e.accepted = true; return
                //  The last command's output, without having to select
                //  it.
                case Qt.Key_E: vista.copiarUltimaSalida(); e.accepted = true; return
                case Qt.Key_Q: vista.plugin.alternarTranquilo(); e.accepted = true; return
                //  Fold the last command's output. A three-hundred-line
                //  `make` becomes one, and the island shrinks with it;
                //  it unfolds by clicking it or repeating the key.
                case Qt.Key_Z: vista.plegarUltimo(); e.accepted = true; return
                case Qt.Key_F:
                    if (vista.buscando)
                        vista.cerrarBusqueda()
                    else
                        vista.abrirBusqueda()
                    e.accepted = true
                    return
                //  To today's note: the last command with its output,
                //  or the whole session. With no Edinot open, the
                //  session says so.
                case Qt.Key_N: vista.plugin.anotar(false); e.accepted = true; return
                case Qt.Key_M: vista.plugin.anotar(true); e.accepted = true; return
                case Qt.Key_T: vista.plugin.nueva(); e.accepted = true; return
                //  Close the front one. With `exit` it also goes —the
                //  session dies and the tab with it—, but that asks
                //  the shell to be free; this works even with
                //  something running.
                case Qt.Key_W:
                    vista.plugin.cerrarSesion(vista.plugin.actual)
                    e.accepted = true
                    return
                case Qt.Key_Right: vista.plugin.siguiente(); e.accepted = true; return
                case Qt.Key_Left:  vista.plugin.anterior();  e.accepted = true; return
                //  From one prompt to the previous or the next: in a
                //  long session it is the difference between searching
                //  and finding.
                case Qt.Key_Up:
                    vista.plugin.mandar({ que: "saltar", hacia: -1 })
                    e.accepted = true
                    return
                case Qt.Key_Down:
                    vista.plugin.mandar({ que: "saltar", hacia: 1 })
                    e.accepted = true
                    return
                case Qt.Key_Plus:
                case Qt.Key_Equal:
                    vista.plugin.acercar(1)
                    e.accepted = true
                    return
                }

                const cual = vista.numeroDe(e.key)
                if (cual > 0) {
                    vista.plugin.irA(cual - 1)
                    e.accepted = true
                    return
                }
            }

            //  History with the keyboard, with shift and the page keys
            //  as in any terminal. Without this one could only go up
            //  with the wheel or by dragging the little bar.
            if (mods.shift && !mods.control) {
                const salto = Math.max(1, (vista.marco ? vista.marco.filas_n : vista.filas) - 1)
                if (e.key === Qt.Key_PageUp || e.key === Qt.Key_PageDown) {
                    vista.plugin.mandar({ que: "rueda", historial: true,
                                          lineas: e.key === Qt.Key_PageUp ? -salto : salto })
                    e.accepted = true
                    return
                }
                if (e.key === Qt.Key_Home || e.key === Qt.Key_End) {
                    vista.plugin.mandar({ que: "tope", arriba: e.key === Qt.Key_Home })
                    e.accepted = true
                    return
                }
            }

            //  Font size, here and now. It does not touch settings:
            //  whoever enlarges to read for a while is not changing
            //  their preference.
            if (mods.control && !mods.shift) {
                if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                    vista.plugin.acercar(1)
                    e.accepted = true
                    return
                }
                if (e.key === Qt.Key_Minus) {
                    vista.plugin.acercar(-1)
                    e.accepted = true
                    return
                }
                if (e.key === Qt.Key_0) {
                    vista.plugin.zoomNormal()
                    e.accepted = true
                    return
                }
            }

            switch (e.key) {
            //  ESC goes TO THE TERMINAL, where it is needed: it is
            //  the cancel key of claude, of codex and of vim, and
            //  while the island kept it there was no way to send it.
            //  To hide the view there is the button above and the same
            //  key that opened it.
            case Qt.Key_Return:
            case Qt.Key_Enter:        return conNombre("enter")
            case Qt.Key_Backspace:    return conNombre("backspace")
            case Qt.Key_Tab:          return conNombre("tab")
            case Qt.Key_Backtab:      return conNombre("tab")
            case Qt.Key_Up:           return conNombre("up")
            case Qt.Key_Down:         return conNombre("down")
            case Qt.Key_Left:         return conNombre("left")
            case Qt.Key_Right:        return conNombre("right")
            case Qt.Key_Home:         return conNombre("home")
            case Qt.Key_End:          return conNombre("end")
            case Qt.Key_PageUp:       return conNombre("pageup")
            case Qt.Key_PageDown:     return conNombre("pagedown")
            case Qt.Key_Delete:       return conNombre("delete")
            case Qt.Key_Insert:       return conNombre("insert")
            }

            if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12)
                return conNombre("f" + (e.key - Qt.Key_F1 + 1))

            //  The rest goes as text. Qt already delivers the control
            //  character when Ctrl+something is pressed, so a Ctrl+C
            //  arrives done.
            if (e.text.length > 0) {
                //  Typing undoes the selection: the selected stopped
                //  making sense the moment the screen changes
                //  underneath.
                vista.limpiarSeleccion()
                //  Alt+letter is ESCAPE then the letter —what
                //  terminals call «meta sends escape»—, which is how
                //  emacs, zsh's line and half the console's menus
                //  expect it. Qt delivers only the letter: without
                //  putting the escape in front, an alt+B arrived as a
                //  bare «b».
                vista.plugin.mandar({ que: "texto",
                                      valor: (mods.alt ? String.fromCharCode(0x1b) : "")
                                             + e.text })
                e.accepted = true
            }
        }
    }

    //  ── the search box ───────────────────────────────────────────
    //
    //  Dressed like the island's overlays and not like a gray text
    //  box: house surface, wing radius split in two, and it slides
    //  in. Placed top right because the bottom holds the foot with
    //  the directory, and covering where you are while you search is
    //  a dirty trick.
    Rectangle {
        id: cajaBusqueda

        visible: opacity > 0
        anchors.right: parent.right
        anchors.rightMargin: vista.margen + 10
        y: vista.margen + vista.altoCabecera - 3 + (vista.buscando ? 0 : -14)
        width: 250
        height: 26
        radius: 8
        color: Theme.surface
        border.width: 1
        border.color: vista.plugin.sinRastro ? Theme.red : Theme.surfaceHi
        opacity: vista.buscando ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        IconGlyph {
            id: lupa
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0349)
            color: Theme.muted
            font.pixelSize: 12
        }

        IslandLabel {
            anchors.left: lupa.right
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            visible: campoBusqueda.text.length === 0
            text: "search"
            color: Theme.dim
            font.pixelSize: 11
        }

        TextInput {
            id: campoBusqueda

            anchors.left: lupa.right
            anchors.leftMargin: 7
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            cursorDelegate: IslandCursor {}
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 11
            clip: true
            selectByMouse: true
            selectionColor: Theme.blue

            onTextEdited: {
                vista.plugin.aguja = text
                vista.plugin.sinRastro = false
            }

            Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Escape) {
                    vista.cerrarBusqueda()
                    e.accepted = true
                    return
                }
                //  Enter searches BACKWARDS. In a terminal what is
                //  searched for has almost always just happened and
                //  sits above; with shift, forward.
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    vista.plugin.buscar((e.modifiers & Qt.ShiftModifier) ? 1 : -1)
                    e.accepted = true
                }
            }
        }
    }

    //  ── the path of a connection ──────────────────────────────────
    //
    //  While `ssh` negotiates NOTHING is visible —not a dot— and
    //  three seconds of still screen look like a hung terminal.
    //  This says «I am going»: from here, through the key, to there.
    //  The servers plugin lights it and the first output that arrives
    //  puts it out.
    Item {
        anchors.fill: parent
        visible: Consola.conectando !== ""
        z: 10

        //  Opaque, not translucent: underneath pass the command, the
        //  machine's greeting and ssh's notices, and watching them run
        //  behind the animation is the opposite of what the animation
        //  comes to say. The same decision as the window.
        //
        //  And with the bottom corners rounded like the island's: a
        //  bare rectangle left it square at the foot for as long as
        //  the connection lasted, one of those things seen without
        //  looking. The same radius the silhouette uses —32, or half
        //  the height if short—, and zero up top because there is no
        //  corner to cover there: the tabs' header is there.
        Rectangle {
            anchors.fill: parent
            color: Theme.islandBg
            bottomLeftRadius: Math.min(32, vista.height / 2)
            bottomRightRadius: Math.min(32, vista.height / 2)
        }

        Column {
            anchors.centerIn: parent
            spacing: 10

            Item {
                width: 220
                height: 26
                anchors.horizontalCenter: parent.horizontalCenter

                //  The line, and over it the spark that travels it.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 2
                    color: Theme.blue
                    opacity: 0.25
                }

                Rectangle {
                    id: chispa
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 2
                    color: Theme.blue

                    //  From one side to the other and back to the
                    //  start. It rides the animation engine and not a
                    //  Timer, like everything that moves in this
                    //  house.
                    NumberAnimation on x {
                        running: Consola.conectando !== ""
                        loops: Animation.Infinite
                        from: 0
                        to: 210
                        duration: 1500
                        easing.type: Easing.InOutSine
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.blue
                }

                //  The key: a drawn keyhole, not a glyph — a letter
                //  leans on its baseline and inside a circle it always
                //  sits off-center.
                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 13
                    color: Theme.blue

                    SequentialAnimation on opacity {
                        running: Consola.conectando !== ""
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutQuad }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 7
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.islandBg
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 13
                        width: 3
                        height: 6
                        radius: 1
                        color: Theme.islandBg
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width - 16
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.blue
                    opacity: chispa.x > 180 ? 1 : 0.25

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "connecting to " + Consola.conectando + "…"
                color: Theme.muted
                font.pixelSize: 12
            }
        }
    }

    //  Discreet foot: where you are, which is what one looks at, and
    //  the exit reminder in small type on the right. With the same
    //  margin as the grid, since the island has rounded corners and
    //  what hugs the edge spills under the clip.
    IslandLabel {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: vista.margen
        anchors.bottomMargin: 6
        text: vista.marco && vista.marco.cwd ? vista.corto(vista.marco.cwd) : ""
        color: Theme.muted
        font.pixelSize: 10
    }

    IslandLabel {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: vista.margen
        anchors.bottomMargin: 6
        text: "ctrl+shift: ←→ switches · T new · V paste · C copy · F find"
        color: Theme.dim
        font.pixelSize: 10
    }
}
