//  The control centre's shortcuts strip, reorderable.
//
//  It uses no RowLayout but computed positions, and it is because
//  of dragging: a Layout places its children itself, so while you
//  drag one the Layout gives it back its place and it cannot move.
//  With a computed `x` and a Behavior, the dragged one follows the
//  mouse and the others step aside on their own with an animation —
//  which is moreover what makes one understand they are being
//  reordered and not simply moved.
//
//  Click and drag share a single MouseArea: if on release there was
//  no real movement, it was a click and it opens. With two separate
//  areas —one to click, one to drag— one always wins and the other
//  looks broken.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

Item {
    id: franja

    //  What to do on opening one: the panel sets it, being the one
    //  that knows how to close itself.
    signal abrir(string id)

    readonly property int esp: 10
    readonly property int altura: 40

    //  The ones painted: the saved ones that also exist and are on.
    //  This list does not change while dragging: the new order is
    //  drawn with slots and only saved on release.
    readonly property var disponibles: {
        const apps = PluginManager.aplicaciones
        const salida = []
        const ids = Settings.quickAccess || []
        for (let i = 0; i < ids.length; ++i) {
            for (let j = 0; j < apps.length; ++j) {
                if (apps[j].id === ids[i] && apps[j].habilitado) {
                    salida.push(apps[j])
                    break
                }
            }
        }
        return salida
    }

    //  While dragging, the MODEL IS NOT TOUCHED.
    //
    //  It was tried the other way —reordering the list on every
    //  move— and the drag died at the first one: on the model
    //  changing, the Repeater destroys and recreates its cells, and
    //  the one being dragged took the mouse grip with it. It let go
    //  by itself and the click ended up opening something else.
    //
    //  So while dragging there are only two numbers —where it came
    //  from and where it goes— and each cell computes which SLOT is
    //  its own. It is pure drawing. The model is reordered once,
    //  on release.
    property int arrastrando: -1
    property int destino: -1

    readonly property var lista: disponibles

    //  One more than the shortcuts: the button opening the whole
    //  drawer.
    readonly property int anchoCelda:
        lista.length > 0
            ? (width - esp * lista.length) / (lista.length + 1)
            : width

    function posicion(i) { return i * (anchoCelda + esp) }

    //  Which slot each cell takes while dragging: the dragged one
    //  goes to the target's and those caught in between shift one
    //  place, which is what makes reordering visible and not just
    //  moving.
    function ranuraDe(i) {
        if (arrastrando < 0 || destino < 0 || arrastrando === destino)
            return i
        if (i === arrastrando)
            return destino
        if (arrastrando < destino && i > arrastrando && i <= destino)
            return i - 1
        if (arrastrando > destino && i >= destino && i < arrastrando)
            return i + 1
        return i
    }

    //  And here yes: once, on release.
    //
    //  It receives from and to instead of reading them off
    //  `arrastrando`, because the caller must have set them to -1
    //  already: otherwise the model changes with the drag still
    //  «alive», the slots are computed over the NEW list with the
    //  OLD shift, and the strip is left with a gap and one cell
    //  missing. It showed.
    function aplicar(de, a) {
        if (de < 0 || a < 0 || de === a)
            return
        const ids = disponibles.map(function (x) { return x.id })
        ids.splice(a, 0, ids.splice(de, 1)[0])
        //  Saved ones not painted now —a plugin off— are kept at the
        //  end: turning something off must not erase that you had it
        //  pinned.
        const resto = (Settings.quickAccess || []).filter(function (id) {
            return ids.indexOf(id) < 0
        })
        Settings.quickAccess = ids.concat(resto)
        Settings.guardar()
    }

    Repeater {
        model: franja.lista

        delegate: K4.Baldosa {
            id: celda
            required property var modelData
            required property int index

            //  The visuals are carried by the MouseArea below: the
            //  tile does not listen so as not to fight the drag.
            pulsable: false
            activa: raton.containsMouse || franja.arrastrando === index

            width: franja.anchoCelda
            height: franja.altura
            y: 0
            radius: 12
            z: franja.arrastrando === index ? 2 : 1

            //  The x is ALWAYS a binding, never an assignment.
            //  Assigning it by hand breaks the binding forever, and
            //  since the row has no width yet when the cells are
            //  created, they all stayed piled at zero — a single one
            //  showed.
            //
            //  So there are two sources and the dragging one rules
            //  while it lasts: on release, `arrastrando` returns to
            //  -1, the binding recovers its place and the Behavior
            //  carries it there with an animation.
            property real desplazado: 0

            x: franja.arrastrando === index
                ? desplazado
                : franja.posicion(franja.ranuraDe(index))

            //  The dragged one does NOT animate —it must stay glued
            //  to the mouse—; the ones stepping aside do.
            Behavior on x {
                enabled: franja.arrastrando !== celda.index
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Row {
                anchors.centerIn: parent
                spacing: 7

                K4.IconoPlugin {
                    imagen: celda.modelData.imagen
                    glifo: celda.modelData.glifo
                    tamano: 15
                    anchors.verticalCenter: parent.verticalCenter
                }

                IslandLabel {
                    text: celda.modelData.nombre
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: raton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                property real cogidoEn: 0
                property bool movido: false

                onPressed: function (ev) {
                    cogidoEn = ev.x
                    movido = false
                    celda.desplazado = celda.x
                    franja.arrastrando = celda.index
                    franja.destino = celda.index
                }

                onPositionChanged: function (ev) {
                    if (franja.arrastrando !== celda.index)
                        return
                    //  A short threshold: without it, the hand's
                    //  tremble on a click already counts as a drag
                    //  and the shortcut never opens.
                    if (!movido && Math.abs(ev.x - cogidoEn) < 6)
                        return
                    movido = true

                    celda.desplazado = Math.max(0,
                        Math.min(franja.width - celda.width,
                                 celda.desplazado + ev.x - cogidoEn))

                    const d = Math.round(
                        celda.desplazado / (franja.anchoCelda + franja.esp))
                    if (d >= 0 && d < franja.lista.length)
                        franja.destino = d
                }

                onReleased: {
                    //  Everything by hand BEFORE touching anything:
                    //  on reordering, this very cell is destroyed and
                    //  recreated, so reading it afterwards is reading
                    //  a corpse.
                    const hubo = movido
                    const de = franja.arrastrando
                    const a = franja.destino
                    const cual = celda.modelData.id

                    franja.arrastrando = -1
                    franja.destino = -1

                    if (hubo)
                        franja.aplicar(de, a)
                    else
                        franja.abrir(cual)
                }
            }
        }
    }

    //  The whole drawer, always last and still: it does not
    //  reorder because it is not a shortcut, it is the way out to
    //  all the others.
    K4.Baldosa {
        x: franja.posicion(franja.lista.length)
        width: franja.anchoCelda
        height: franja.altura
        radius: 12

        Behavior on x {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Row {
            anchors.centerIn: parent
            spacing: 7

            K4.Glifo {
                text: String.fromCodePoint(0xF02C1)     // md-grid
                color: Theme.muted
                font.pixelSize: 15
                anchors.verticalCenter: parent.verticalCenter
            }

            IslandLabel {
                text: "All"
                font.pixelSize: 11
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        onPulsada: franja.abrir("apps")
    }
}
