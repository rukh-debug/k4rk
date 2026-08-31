//  Settings, as an island view: sidebar on the left, one section at a time.
//
//  Settings used to live in its own layer window (K4.Ventana, "k4-ajustes").
//  A window has its own frame, its own focus rules and its own dismissal
//  gesture — three things the island already does. Here it opens from the
//  pill like the control center does, closes with Escape or a click outside
//  like every deployed view, and holds the keyboard while it is open.
//
//  ── where the data comes from ─────────────────────────────────────
//
//  From `Settings.definicion`, which already carries the bar's own groups
//  concatenated with whatever plugins register through `K4.Ajustes`. This
//  view declares not a single option: if a plugin adds a section tomorrow,
//  it shows up here on its own.
//
//  The rows are `FilaOpcion`, and plugin sections render with `FilaPlugin`
//  inside the Plugins group. One implementation of a switch cannot diverge
//  on the first fix.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: vista

    required property var plugin

    //  Which section is on screen, and what the search field holds. It lives
    //  here and not in the plugin: closing and reopening starts at the top
    //  with no filter, not where you left it three days ago.
    property int seccion: 0
    property string busqueda: ""

    //  The keyboard: typing searches, ESC undoes and then closes. The layer
    //  takes a moment to grant focus, so it is asked with retries — the same
    //  dance the launcher and the store do.
    property int intentos: 0

    Component.onCompleted: {
        campo.forceActiveFocus()
        foco.start()
        aterrizar()
    }

    //  The landing note can also arrive while the view is open: Super+W with
    //  Settings already on screen should still take you to the Wallpaper
    //  page, not be swallowed because the view was created earlier.
    Connections {
        target: vista.plugin
        function onPaginaPedidaChanged() { vista.aterrizar() }
    }

    Timer {
        id: foco
        interval: 140
        onTriggered: {
            campo.forceActiveFocus()
            if (!campo.activeFocus && vista.intentos < 6) {
                vista.intentos += 1
                restart()
            }
        }
    }

    readonly property var todas: Settings.definicion

    //  What the sidebar lists. Sections contributed by plugins do NOT go
    //  here: they live inside their plugin's row, in the Plugins section,
    //  next to the switch that turns them on. They stay in `todas`, and that
    //  matters — the search walks the whole list and finds them anyway.
    readonly property var lateral: vista.todas.filter(function (g) {
        return g.enLateral !== false
    })

    //  ── the tree ────────────────────────────────────────────
    //
    //  Top-level groups, and the children of one. `padre` is the only thing
    //  a group declares to join a family; the tree is derived, so a group
    //  can move houses by editing one word, and search keeps walking the
    //  flat list without knowing a tree exists.
    readonly property var padres: vista.lateral.filter(function (g) {
        return !g.padre
    })

    function hijosDe(grupo) {
        return vista.lateral.filter(function (g) {
            return g.padre === grupo.grupo
        })
    }

    //  A group's index among the sidebar groups. By NAME and not by
    //  object: a Repeater hands its delegates a COPY of every array-model
    //  object — `modelData === lateral[i]` is false, `indexOf` is -1, and
    //  navigation that trusts references lands nowhere (ask the all-blue
    //  sidebar of one bad evening). Names are the groups' stable ids:
    //  `grupo` is what search matches, what `padre` points at, and what the
    //  keybinds arrive as.
    function indiceDe(grupo) {
        for (let i = 0; i < vista.lateral.length; ++i)
            if (vista.lateral[i].grupo === grupo.grupo)
                return i
        return -1
    }

    //  Which drawers are open. Display starts open: a closed family at the
    //  top of the sidebar reads as a setting that is not there.
    property var expandidos: ({ Display: true })

    function ponerExpandido(grupo, valor) {
        const e = {}
        Object.assign(e, vista.expandidos)
        e[grupo] = valor
        vista.expandidos = e
    }

    //  What gets painted on the right.
    //
    //  Without a search: the chosen section, that's all. Searching: the
    //  matches of EVERY section, each under its own title — whoever types
    //  «capture» does not know which drawer it is in, or they would not be
    //  typing.
    readonly property var contenido: {
        const q = String(vista.busqueda).trim().toLowerCase()
        if (q.length === 0)
            return vista.seccion < vista.lateral.length
                ? [vista.lateral[vista.seccion]] : []

        const fuera = []
        for (let i = 0; i < vista.todas.length; ++i) {
            const g = vista.todas[i]
            const casaGrupo = String(g.grupo).toLowerCase().indexOf(q) >= 0
                || (g.claves || []).some(function (c) {
                    return String(c).toLowerCase().indexOf(q) >= 0
                })
            const ops = (g.opciones || []).filter(function (o) {
                return casaGrupo
                    || String(o.nombre || "").toLowerCase().indexOf(q) >= 0
                    || String(o.desc || "").toLowerCase().indexOf(q) >= 0
            })
            if (ops.length > 0) {
                fuera.push({ grupo: g.grupo, glifo: g.glifo, desc: g.desc,
                             vista: g.vista, opciones: ops })
            } else if (casaGrupo) {
                //  A section that matches but has no options of its own: its
                //  controls live inside a widget. Offer it as a destination
                //  instead of dropping it — «blur» used to find NOTHING even
                //  though the switch sits right there.
                fuera.push({ grupo: g.grupo, glifo: g.glifo, desc: g.desc,
                             vista: g.vista, opciones: [], atajo: i })
            }
        }
        return fuera
    }

    readonly property int cuantasCasan: {
        let n = 0
        for (let i = 0; i < vista.contenido.length; ++i) {
            const g = vista.contenido[i]
            //  An offered section counts as ONE: it is a result even without
            //  loose options. Without this the header said «0 match» with a
            //  result underneath, which is worse than saying nothing.
            n += g.atajo !== undefined ? 1 : g.opciones.length
        }
        return n
    }

    //  Jump to a section by name: used by the search result that offers a
    //  whole section, and by `k4 settingsSection <name>`. The name or the
    //  section id both work ("Wallpaper" and "wallpaper"), case-insensitive
    //  — whoever binds a key types it once, and getting the case wrong
    //  should open the top, not nothing.
    function irASeccion(nombre) {
        const n = String(nombre).toLowerCase()
        for (let i = 0; i < vista.lateral.length; ++i) {
            const g = vista.lateral[i]
            if (String(g.grupo).toLowerCase() === n
                || String(g.vista || "").toLowerCase() === n) {
                //  A child opens its family's drawer on the way in — landing
                //  on a page whose row is hidden is landing nowhere.
                if (g.padre)
                    vista.ponerExpandido(g.padre, true)
                vista.elegir(i)
                return
            }
        }
    }

    //  A parent row: opens its drawer and lands on its overview. Closing it
    //  while you stand inside (on it or on one of its children) takes you up
    //  to the overview, so the header never names a page whose row is hidden.
    function tocarPadre(grupo) {
        const idx = vista.indiceDe(grupo)
        if (idx < 0)
            return
        if (!vista.expandidos[grupo.grupo]) {
            vista.ponerExpandido(grupo.grupo, true)
            vista.elegir(idx)
        } else {
            vista.ponerExpandido(grupo.grupo, false)
            const sel = vista.lateral[vista.seccion]
            if (sel !== undefined
                && (sel.grupo === grupo.grupo
                    || sel.padre === grupo.grupo))
                vista.elegir(idx)
        }
    }

    function elegirHijo(grupo) {
        if (grupo.padre)
            vista.ponerExpandido(grupo.padre, true)
        vista.elegir(vista.indiceDe(grupo))
    }

    //  Land on a page asked for from outside (`k4 settingsSection`). Called
    //  on open, because the plugin note can arrive before the view exists,
    //  and every time the note changes, because it can also arrive while the
    //  view is open. Consumed here so reopening with the pill starts at the
    //  top: the landing is a favour to a keybind, not a new home.
    function aterrizar() {
        const p = vista.plugin.paginaPedida
        if (!p || p.length === 0)
            return
        vista.plugin.paginaPedida = ""
        vista.irASeccion(p)
    }

    function elegir(i) {
        //  Out of range is a closed door, not a page: an index nobody has
        //  would leave the content empty and every row comparing itself
        //  against nothing.
        if (i < 0 || i >= vista.lateral.length)
            return
        vista.seccion = i
        vista.busqueda = ""
        campo.text = ""
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        //  Same air below as on the sides: the last row of a page used to
        //  sit 10 px from the border while the sides kept 16, and the
        //  asymmetry read as a mistake.
        anchors.bottomMargin: 16
        spacing: 14

        // ── the sidebar ────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 224
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.03)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                //  The search field. With ~fifty options in ~fourteen
                //  drawers, this is what actually fixes «I can't find it».
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 16
                    color: Theme.surface
                    border.width: 1
                    border.color: campo.activeFocus
                        ? Theme.blue : "transparent"

                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 9
                        spacing: 8

                        IconGlyph {
                            text: Theme.ico.search
                            color: campo.activeFocus ? Theme.muted : Theme.dim
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            IslandLabel {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: campo.text.length === 0
                                text: "Search settings"
                                color: Theme.dim
                                font.pixelSize: 12
                            }

                            TextInput {
                                id: campo
                                anchors.fill: parent
                                cursorDelegate: IslandCursor {}
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true
                                selectionColor: Theme.blue
                                text: vista.busqueda
                                onTextEdited: vista.busqueda = text

                                //  ESC undoes the inside first and only closes
                                //  when there is nothing left to undo. If it
                                //  always bubbled up, clearing a search would
                                //  cost the whole view.
                                Keys.onPressed: function (ev) {
                                    if (ev.key !== Qt.Key_Escape)
                                        return
                                    if (campo.text.length > 0) {
                                        campo.text = ""
                                        vista.busqueda = ""
                                    } else {
                                        vista.plugin.close()
                                    }
                                    ev.accepted = true
                                }
                            }
                        }
                    }
                }

                // ── the sections ──────────────────────────────────
                //
                //  A tree, not a list: groups that declare `padre` render
                //  one level under it, and the parent opens like a drawer.
                //  The flat rows were fine with five sections; with the
                //  display family gathered under one roof, a list would make
                //  you read past three siblings to reach the next subject.
                K4.Rodillo {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: vista.padres

                            //  A bare rectangle and not `K4.Baldosa`: Baldosa
                            //  draws an inner border ALWAYS, and with a tree
                            //  in the sidebar it becomes a grid of boxes.
                            //  What must stand out here is ONE: the one you
                            //  are looking at.
                            delegate: Column {
                                id: rama
                                required property var modelData

                                width: parent.width
                                spacing: 2

                                //  Its index among ALL sidebar groups
                                //  (children included), which is what
                                //  `seccion` counts.
                                readonly property int indice:
                                    vista.indiceDe(rama.modelData)
                                readonly property var hijos:
                                    vista.hijosDe(rama.modelData)
                                readonly property bool despliega:
                                    rama.hijos.length > 0
                                readonly property bool abierta:
                                    rama.despliega
                                    && !!vista.expandidos[rama.modelData.grupo]
                                //  A child of this branch is on screen: the
                                //  parent stays softly lit, so the tree tells
                                //  you where you are even when the drawer is
                                //  closed.
                                readonly property bool acogida: {
                                    const sel = vista.lateral[vista.seccion]
                                    return sel !== undefined
                                        && sel.padre === rama.modelData.grupo
                                }
                                readonly property bool activa:
                                    vista.busqueda.length === 0
                                    && !rama.acogida
                                    && vista.seccion === rama.indice

                                Rectangle {
                                    width: parent.width
                                    height: 34
                                    radius: 9
                                    color: rama.activa
                                        ? Qt.rgba(Theme.blue.r, Theme.blue.g,
                                                  Theme.blue.b, 0.18)
                                        : (rama.acogida
                                           ? Qt.rgba(1, 1, 1, 0.04)
                                           : (raton.containsMouse
                                              ? Qt.rgba(1, 1, 1, 0.05)
                                              : "transparent"))

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: raton
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        //  A parent opens its drawer AND lands
                                        //  on its overview; closing it while
                                        //  you are inside takes you up to the
                                        //  overview too, so the header never
                                        //  names a page whose row you cannot
                                        //  see.
                                        onClicked: rama.despliega
                                            ? vista.tocarPadre(rama.modelData)
                                            : vista.elegir(rama.indice)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 10

                                        IconGlyph {
                                            Layout.alignment: Qt.AlignVCenter
                                            //  No icon of its own —a plugin section
                                            //  that did not declare one— gets the
                                            //  puzzle piece, which is how the bar
                                            //  draws «this is a plugin» everywhere.
                                            text: String.fromCodePoint(
                                                rama.modelData.glifo
                                                    ? rama.modelData.glifo : 0xF0431)
                                            color: rama.activa || rama.acogida
                                                ? Theme.blue : Theme.muted
                                            font.pixelSize: 14
                                            renderType: Text.NativeRendering
                                        }

                                        IslandLabel {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: rama.modelData.grupo
                                            textFormat: Text.PlainText
                                            color: rama.activa || rama.acogida
                                                ? Theme.ink : Theme.muted
                                            font.pixelSize: 12
                                            font.weight: rama.activa
                                                ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        //  The drawer's handle. It turns with
                                        //  the drawer and not on its own click:
                                        //  the whole row is the target, same as
                                        //  every other row — a 16 px chevron
                                        //  would ask for aim.
                                        IconGlyph {
                                            visible: rama.despliega
                                            Layout.alignment: Qt.AlignVCenter
                                            text: Theme.ico.chevronDown
                                            color: rama.acogida || rama.activa
                                                ? Theme.blue : Theme.dim
                                            font.pixelSize: 13
                                            renderType: Text.NativeRendering
                                            rotation: rama.abierta ? 0 : -90

                                            Behavior on rotation {
                                                NumberAnimation {
                                                    duration: 200
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }
                                }

                                //  ── the drawer ─────────────────────
                                //
                                //  Height 0 when closed, and `clip` so the
                                //  rows do not paint outside while the drawer
                                //  travels: the children SLIDE out, which is
                                //  what makes the tree feel like furniture
                                //  and not a list that reappears.
                                Item {
                                    width: parent.width
                                    height: rama.abierta
                                        ? columnaHijos.height : 0
                                    clip: true
                                    opacity: rama.abierta ? 1 : 0

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 240
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    Behavior on opacity {
                                        NumberAnimation { duration: 180 }
                                    }

                                    Column {
                                        id: columnaHijos
                                        width: parent.width
                                        spacing: 2

                                        Repeater {
                                            model: rama.hijos

                                            delegate: Rectangle {
                                                id: hija
                                                required property var modelData

                                                readonly property int indice:
                                                    vista.indiceDe(hija.modelData)
                                                readonly property bool activa:
                                                    vista.busqueda.length === 0
                                                    && vista.seccion === hija.indice

                                                width: parent.width
                                                height: 30
                                                radius: 8
                                                color: hija.activa
                                                    ? Qt.rgba(Theme.blue.r,
                                                              Theme.blue.g,
                                                              Theme.blue.b, 0.15)
                                                    : (ratonHija.containsMouse
                                                       ? Qt.rgba(1, 1, 1, 0.05)
                                                       : "transparent")

                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                //  The active sub-tab keeps a
                                                //  tick on its left edge: with
                                                //  the drawer open you find
                                                //  your page by the bar of
                                                //  blue, not by reading.
                                                Rectangle {
                                                    visible: hija.activa
                                                    x: 0
                                                    anchors.verticalCenter:
                                                        parent.verticalCenter
                                                    width: 3
                                                    height: parent.height - 12
                                                    radius: 1.5
                                                    color: Theme.blue
                                                }

                                                MouseArea {
                                                    id: ratonHija
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked:
                                                        vista.elegirHijo(hija.modelData)
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    //  One step in, so the
                                                    //  child belongs to its
                                                    //  parent's column and not
                                                    //  to the sidebar's edge.
                                                    anchors.leftMargin: 26
                                                    anchors.rightMargin: 10
                                                    spacing: 9

                                                    IconGlyph {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: String.fromCodePoint(
                                                            hija.modelData.glifo
                                                                ? hija.modelData.glifo
                                                                : 0xF0431)
                                                        color: hija.activa
                                                            ? Theme.blue
                                                            : Theme.muted
                                                        font.pixelSize: 12
                                                        renderType: Text.NativeRendering
                                                    }

                                                    IslandLabel {
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: hija.modelData.grupo
                                                        textFormat: Text.PlainText
                                                        color: hija.activa
                                                            ? Theme.ink
                                                            : Theme.muted
                                                        font.pixelSize: 11
                                                        font.weight: hija.activa
                                                            ? Font.DemiBold
                                                            : Font.Normal
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── the content ────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // The header: which section this is and what it is about.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 18
                    color: Qt.rgba(Theme.blue.r, Theme.blue.g,
                                   Theme.blue.b, 0.16)

                    IconGlyph {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(
                            vista.busqueda.length > 0 ? 0xF0349
                            : (vista.contenido.length > 0
                               && vista.contenido[0].glifo
                               ? vista.contenido[0].glifo : 0xF0431))
                        color: Theme.blue
                        font.pixelSize: 17
                        renderType: Text.NativeRendering
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    IslandLabel {
                        Layout.fillWidth: true
                        text: vista.busqueda.length > 0
                            ? `${vista.cuantasCasan} match “${vista.busqueda}”`
                            : (vista.contenido.length > 0
                               ? vista.contenido[0].grupo : "")
                        textFormat: Text.PlainText
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: vista.busqueda.length > 0
                            ? "From every section at once"
                            : (vista.contenido.length > 0
                               ? (vista.contenido[0].desc || "") : "")
                        textFormat: Text.PlainText
                        color: Theme.dim
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }

                //  Which commit the bar is on. Small and dim: it answers
                //  «what version do I have?», which nothing else asked, without
                //  competing with the title.
                IslandLabel {
                    Layout.alignment: Qt.AlignVCenter
                    text: vista.plugin.version.commit
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.pixelSize: 8
                }

                //  And a new version IS news, so it goes blue and clickable.
                //
                //  With unsaved changes the button is not offered: `./instalar`
                //  refuses to touch the code with a dirty tree —on purpose— so
                //  it would be a button that does not do what it says. The
                //  situation is stated and whoever reads it decides; the
                //  uncommitted work is theirs.
                Rectangle {
                    id: novedad
                    visible: vista.plugin.version.hayNovedad
                    Layout.preferredWidth: textoNovedad.implicitWidth + 20
                    Layout.preferredHeight: 22
                    Layout.alignment: Qt.AlignVCenter
                    radius: 11

                    readonly property bool ofrece: !vista.plugin.version.sucio

                    color: !ofrece ? Theme.track
                        : (ratonNovedad.containsMouse ? "#4a9eff" : Theme.blue)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: textoNovedad
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: novedad.ofrece
                            ? `${vista.plugin.version.detras} new · Update`
                            : `${vista.plugin.version.detras} new · save your changes first`
                        color: novedad.ofrece ? Theme.ink : Theme.muted
                        font.pixelSize: 9
                        font.weight: novedad.ofrece ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: ratonNovedad
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: novedad.ofrece
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            vista.plugin.version.actualizar()
                            vista.plugin.close()
                        }
                    }
                }
            }

            // ── the options ──────────────────────────────────────
            K4.Rodillo {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    width: parent.width
                    spacing: 12
                    topPadding: 2
                    bottomPadding: 20
                    //  A little air on each side: the sliders of the theme
                    //  pages draw their handle past the row's bounds, and
                    // with only 2 px it touched the edge of the view.
                    leftPadding: 12
                    rightPadding: 12

                    Repeater {
                        model: vista.contenido

                        delegate: ColumnLayout {
                            id: bloque
                            required property var modelData

                            width: parent.width - parent.leftPadding
                                   - parent.rightPadding
                            spacing: 6

                            //  While searching there are several sections at
                            //  once, and without their titles the matches read
                            //  as a loose list with no context. With a single
                            //  section the title is already in the header and
                            //  repeating it would be noise.
                            IslandLabel {
                                visible: vista.busqueda.length > 0
                                text: bloque.modelData.grupo
                                textFormat: Text.PlainText
                                color: Theme.dim
                                font.pixelSize: 9
                                font.capitalization: Font.AllUppercase
                                Layout.leftMargin: 2
                            }

                            //  ── the landing of a family ──────────────
                            //
                            //  A parent's own page: the desktop at a glance,
                            //  and a card per child. The hero answers «what
                            //  am I looking at» before anything is touched —
                            //  the wallpaper names itself — and the cards are
                            //  the drawer's rows again, big, for the first
                            //  time you come here.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "display"
                                        && bloque.modelData.atajo === undefined
                                        && vista.busqueda.length === 0
                                sourceComponent: Component {
                                    PortadaFamilia {
                                        familia: bloque.modelData
                                        motor: vista.plugin.hyprtheme
                                        onPedida: function (grupo) {
                                            vista.elegirHijo(grupo)
                                        }
                                        onPedidaApp: {
                                            vista.plugin.close()
                                            PluginManager.abrirAplicacion(
                                                bloque.modelData.app)
                                        }
                                    }
                                }
                            }

                            //  ── the engine's absence, said up front ───
                            //
                            //  Above the grid on purpose: the grid can run
                            //  for a whole screen, and a notice at its feet
                            //  is a notice nobody ever met.
                            IslandLabel {
                                Layout.fillWidth: true
                                visible: bloque.modelData.vista === "wallpaper"
                                         && !vista.plugin.hyprtheme
                                text: "The theme plugin is off: you can view the wallpapers, but not apply them."
                                color: Theme.dim
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }

                            //  ── the wallpaper grid ────────────────────
                            //
                            //  The engine is asked for by id and its folder
                            //  is not imported: with the plugin off this just
                            //  waits, without breaking.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                //  The grid sizes itself to its rows
                                //  (`fitContent`), so the page scrolls as one
                                //  in this outer Rodillo.
                                //
                                //  Conditional on `active`, and it is not a
                                //  detail: an inactive Loader STILL occupies
                                //  the height you ask of it, so without this
                                //  the other sections had an invisible ~400px
                                //  hole in front and their content fell out of
                                //  view. The header showed and nothing else,
                                //  without a single error in the log.
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "wallpaper"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    RejillaFondos {
                                        motor: vista.plugin.hyprtheme
                                        fitContent: true
                                    }
                                }
                            }


                            IslandLabel {
                                Layout.fillWidth: true
                                visible: bloque.modelData.vista === "wallpaper"
                                         && !vista.plugin.hyprtheme
                                text: "The theme plugin is off: you can view the wallpapers, but not apply them."
                                color: Theme.dim
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }

                            //  The colour picker, on its own sub-tab under the
                            //  same family as the wallpaper it can follow.
                            //
                            //  Loaders keep their height conditional on
                            //  `active`: an inactive one loads nothing but
                            //  STILL measures whatever you ask of it, and that
                            //  pushes the other sections' content out of view
                            //  without a single error.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "color"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    AjustesTema {
                                        motor: vista.plugin.hyprtheme
                                    }
                                }
                            }

                            //  The shell's typeface, from the families the
                            //  system has. It lives under Display with the
                            //  rest of the screen's look.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "fonts"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component { SelectorFuentes {} }
                            }

                            //  A section offered by the search: click and it
                            //  takes you there. Without this the match showed
                            //  and could not be followed.
                            K4.Baldosa {
                                Layout.fillWidth: true
                                Layout.preferredHeight: visible ? 42 : 0
                                visible: bloque.modelData.atajo !== undefined
                                radius: 10

                                onPulsada: vista.irASeccion(
                                    bloque.modelData.grupo)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 13
                                    anchors.rightMargin: 13
                                    spacing: 12

                                    IconGlyph {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: String.fromCodePoint(
                                            bloque.modelData.glifo
                                                ? bloque.modelData.glifo : 0xF0431)
                                        color: Theme.blue
                                        font.pixelSize: 15
                                        renderType: Text.NativeRendering
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        IslandLabel {
                                            Layout.fillWidth: true
                                            text: bloque.modelData.grupo
                                            textFormat: Text.PlainText
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        IslandLabel {
                                            Layout.fillWidth: true
                                            text: bloque.modelData.desc || ""
                                            textFormat: Text.PlainText
                                            color: Theme.dim
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }

                                    IconGlyph {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: String.fromCodePoint(0xF0142)
                                        color: Theme.dim
                                        font.pixelSize: 14
                                        renderType: Text.NativeRendering
                                    }
                                }
                            }

                            //  Windows and Effects, one loader per page,
                            //  and «Save» after them: they all write the
                            //  Hyprland Lua through the same motor.
                            //
                            //  These loaders keep their height conditional on
                            //  `active`. It is the lesson from before: an
                            //  inactive one loads nothing but STILL measures
                            //  whatever you ask of it, and that pushes the
                            //  other sections' content out of view without a
                            //  single error.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "ventanas"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    AjustesVentanas {
                                        motor: vista.plugin.hyprtheme
                                    }
                                }
                            }

                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "efectos"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    AjustesEfectos {
                                        motor: vista.plugin.hyprtheme
                                    }
                                }
                            }

                            //  «Save» travels with whatever the Hyprland Lua
                            //  writes. Wallpapers do not carry it —those save
                            //  on their own the moment you pick one— but the
                            //  colour block DOES write the Lua, so the bar
                            //  follows the colour half of the page.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.topMargin: active ? 12 : 0
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.atajo === undefined
                                    && (bloque.modelData.vista === "color"
                                        || bloque.modelData.vista === "ventanas"
                                        || bloque.modelData.vista === "efectos")
                                sourceComponent: Component {
                                    GuardarTema {
                                        motor: vista.plugin.hyprtheme
                                    }
                                }
                            }

                            //  The placement editor: one card per
                            //  openable view, side chips and alignment
                            //  chips with a little monitor each.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "placement"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component { PlacementPage {} }
                            }

                            //  The control centre editor: a sketch of the
                            //  centre, the blocks with their order and their
                            //  eye, and the plain knobs as option rows.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "panel"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component { PanelEditor {} }
                            }

                            //  And a section can bring something of its own on
                            //  top of its options. The Island one carries a
                            //  sketch of the screen: it turns three similar
                            //  words into a difference you can see.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.bottomMargin: active ? 6 : 0
                                //  Not while searching: a half-screen sketch in
                                //  front of two matches is not a result, it is
                                //  an obstacle. Results are pointers; to see
                                //  the section, you enter it.
                                active: bloque.modelData.vista === "island"
                                        && bloque.modelData.atajo === undefined
                                        && vista.busqueda.length === 0
                                sourceComponent: Component { PrevioIsland {} }
                            }

                            //  Each group chooses how it paints. Today only
                            //  Plugins asks for something different —almost
                            //  forty rows, each with its own inside— and the
                            //  rest paint as always. When another section
                            //  wants its own, it is added here and nothing else
                            //  is touched.
                            Repeater {
                                model: bloque.modelData.opciones
                                delegate: Loader {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: item
                                        ? item.Layout.preferredHeight : 40
                                    property var dato: modelData
                                    sourceComponent:
                                        bloque.modelData.vista === "plugins"
                                            ? comoPlugin : comoOpcion
                                }
                            }
                        }
                    }

                    //  Not a single option. Can only happen while searching: a
                    //  section without options is not offered in the sidebar.
                    IslandLabel {
                        visible: vista.contenido.length === 0
                        width: parent.width - parent.leftPadding
                               - parent.rightPadding
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 60
                        text: `Nothing matches “${vista.busqueda}”`
                        textFormat: Text.PlainText
                        color: Theme.dim
                        font.pixelSize: 12
                    }
                }
            }

            // ── the footer ────────────────────────────────────────
            //
            //  Loader status and the two system tools. The counter tells
            //  «you turned it off» from «it failed to load», which is what
            //  keeps you from diagnosing blind from a terminal.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF06A0)
                    color: Object.keys(PluginManager.errores).length > 0
                        ? Theme.red : Theme.green
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignVCenter
                }

                //  Two doors to what is NOT a setting but gets looked for
                //  from here: the store —bring, update, remove— and the
                //  Hyprland theme —wallpapers, colours, effects—. They are
                //  applications with their own screen, and those screens are
                //  fine as they are; what was missing was reaching them from
                //  the place where you configure things.
                //
                //  They open instead of hiding under this view: this closes
                //  first.
                Repeater {
                    model: [
                        { nombre: "Plugins", id: "tienda" }
                    ]

                    delegate: K4.Baldosa {
                        id: acceso
                        required property var modelData

                        Layout.preferredWidth: etiquetaAcceso.implicitWidth + 22
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12
                        onPulsada: {
                            vista.plugin.close()
                            PluginManager.abrirAplicacion(acceso.modelData.id)
                        }

                        IslandLabel {
                            id: etiquetaAcceso
                            anchors.centerIn: parent
                            text: acceso.modelData.nombre
                            textFormat: Text.PlainText
                            color: Theme.muted
                            font.pixelSize: 10
                        }
                    }
                }

                IslandLabel {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: PluginManager.catalogo.length + " plugins · "
                        + PluginManager.catalogo.filter(function (m) {
                            return PluginManager.estaHabilitado(m.id)
                        }).length + " enabled"
                        + (Object.keys(PluginManager.errores).length > 0
                           ? " · " + Object.keys(PluginManager.errores).length
                             + " with errors" : "")
                    color: Theme.dim
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                IslandLabel {
                    text: "System tools"
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignVCenter
                }

                Repeater {
                    model: [
                        { nombre: "Networks", glifo: 0xF05A9,
                          orden: ["nm-connection-editor"] },
                        { nombre: "Sound", glifo: 0xF057E,
                          orden: ["pavucontrol"] }
                    ]

                    delegate: K4.Baldosa {
                        id: herramienta
                        required property var modelData

                        Layout.preferredWidth: contenido.implicitWidth + 20
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12

                        onPulsada: {
                            K4.Sistema.lanzar(herramienta.modelData.orden)
                            vista.plugin.close()
                        }

                        RowLayout {
                            id: contenido
                            anchors.centerIn: parent
                            spacing: 6

                            IconGlyph {
                                text: String.fromCodePoint(herramienta.modelData.glifo)
                                color: Theme.muted
                                font.pixelSize: 12
                                renderType: Text.NativeRendering
                            }

                            IslandLabel {
                                text: herramienta.modelData.nombre
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }

    // ── the two ways to paint a row ──────────────────────────────
    Component {
        id: comoOpcion
        FilaOpcion { modelData: parent.dato }
    }

    Component {
        id: comoPlugin
        FilaPlugin { modelData: parent.dato }
    }
}
