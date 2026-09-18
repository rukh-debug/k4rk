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
    property string selectedPage: "island"
    readonly property int seccion: {
        const index = lateral.findIndex(function (g) { return pageKey(g) === selectedPage })
        return Math.max(0, index)
    }
    property string busqueda: ""
    readonly property string query: busqueda.trim().toLowerCase()
    readonly property bool searching: query.length > 0
    property var scrollPositions: ({})
    property string highlightedSetting: ""

    function pageKey(group) {
        return group.pagina ? group.pagina.plugin + "." + group.pagina.name
            : group.vista || group.grupo
    }

    function saveScroll() {
        if (!searching)
            scrollPositions[selectedPage] = pageScroll.contentY
    }

    function search(text) {
        saveScroll()
        busqueda = text
        pageScroll.contentY = 0
        if (!searching)
            Qt.callLater(function () {
                pageScroll.contentY = Math.min(scrollPositions[selectedPage] || 0,
                    Math.max(0, pageScroll.contentHeight - pageScroll.height))
            })
    }

    function openResult(group) {
        if (group.dePlugin) {
            ponerFilaAbierta(group.dePlugin, true)
            irASeccion("plugins")
        } else irASeccion(group.grupo)
        highlightedSetting = group.opciones.length > 0 ? group.opciones[0].id : ""
        revealResult.restart()
    }

    function findSetting(item, name) {
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; ++i) {
            const found = findSetting(item.children[i], name)
            if (found) return found
        }
        return null
    }

    Timer {
        id: revealResult
        interval: 80
        onTriggered: {
            if (!vista.highlightedSetting) return
            const row = vista.findSetting(pageScroll.contentItem,
                "setting-" + vista.highlightedSetting)
            if (row) {
                const position = row.mapToItem(pageScroll.contentItem, 0, 0)
                pageScroll.contentY = Math.max(0, Math.min(position.y - 8,
                    pageScroll.contentHeight - pageScroll.height))
            }
            clearHighlight.restart()
        }
    }
    Timer { id: clearHighlight; interval: 1800; onTriggered: vista.highlightedSetting = "" }

    Keys.onEscapePressed: function (event) {
        if (campo.text.length > 0) {
            campo.text = ""
            search("")
            campo.forceActiveFocus()
        } else plugin.close()
        event.accepted = true
    }
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_F && event.modifiers & Qt.ControlModifier) {
            campo.forceActiveFocus()
            campo.selectAll()
            event.accepted = true
        }
    }

    //  The keyboard: typing searches, ESC undoes and then closes. The layer
    //  takes a moment to grant focus, so it is asked with retries — the same
    //  dance the launcher and the store do.
    property int intentos: 0

    Component.onCompleted: {
        campo.forceActiveFocus()
        foco.start()
        aterrizar()
        reportPage()
    }

    //  The landing note can also arrive while the view is open: Super+W on
    //  another page switches to Wallpaper through it, rather than being
    //  swallowed because the view was created earlier.
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
    onLateralChanged: Qt.callLater(function () {
        if (!vista.lateral.some(function (g) { return vista.pageKey(g) === vista.selectedPage }))
            vista.elegir(0)
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

    //  Which plugin rows stand open in the Plugins page. It lives HERE
    //  and not in the row: the row list is rebuilt whenever the plugin
    //  roster changes — which is exactly when you flip a switch inside
    //  one of them — and a state that dies with its delegate reads as
    //  the row snapping shut at you. The view is the one thing that
    //  survives the rebuild, so the view keeps the memory.
    property var filasAbiertas: ({})

    function ponerFilaAbierta(id, valor) {
        const d = {}
        Object.assign(d, vista.filasAbiertas)
        d[id] = valor
        vista.filasAbiertas = d
    }

    //  What gets painted on the right.
    //
    //  Without a search: the chosen section, that's all. Searching: the
    //  matches of EVERY section, each under its own title — whoever types
    //  «capture» does not know which drawer it is in, or they would not be
    //  typing.
    readonly property var contenido: {
        const q = vista.query
        if (q.length === 0)
            return vista.seccion < vista.lateral.length
                ? [vista.lateral[vista.seccion]] : []

        const fuera = []
        for (let i = 0; i < vista.todas.length; ++i) {
            const g = vista.todas[i]
            const casaGrupo = String(g.grupo).toLowerCase().indexOf(q) >= 0
                || String(g.desc || "").toLowerCase().indexOf(q) >= 0
                || (g.claves || []).some(function (c) {
                    return String(c).toLowerCase().indexOf(q) >= 0
                })
            let heading = ""
            const ops = (g.opciones || []).filter(function (o) {
                if (o.tipo === "titulo") { heading = o.nombre || ""; return false }
                const choices = o.alternativas || Settings.opcionesDe(o.de)
                return casaGrupo || heading.toLowerCase().indexOf(q) >= 0
                    || String(o.nombre || "").toLowerCase().indexOf(q) >= 0
                    || String(o.desc || "").toLowerCase().indexOf(q) >= 0
                    || choices.some(function (choice) {
                        return String(choice.nombre).toLowerCase().indexOf(q) >= 0
                    })
            })
            if (ops.length > 0) {
                fuera.push(Object.assign({}, g, { opciones: ops }))
            } else if (casaGrupo) {
                //  A section that matches but has no options of its own: its
                //  controls live inside a widget. Offer it as a destination
                //  instead of dropping it — «blur» used to find NOTHING even
                //  though the switch sits right there.
                fuera.push(Object.assign({}, g, { opciones: [], atajo: i }))
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
                || String(g.vista || "").toLowerCase() === n
                || String(g.pagina ? g.pagina.name : "").toLowerCase() === n) {
                //  A child opens its family's drawer on the way in — landing
                //  on a page whose row is hidden is landing nowhere.
                if (g.padre)
                    vista.ponerExpandido(g.padre, true)
                vista.elegir(i)
                return
            }
        }
    }

    // Disclosure is independent from navigation to the overview.
    function tocarPadre(grupo) {
        vista.ponerExpandido(grupo.grupo, !vista.expandidos[grupo.grupo])
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

    //  Tell the plugin which page is on screen — the same id `irASeccion`
    //  accepts, lowercase — so its toggle(page) can tell "standing on it"
    //  from "somewhere else". Called on arrival and from `elegir`, the one
    //  door every section change walks through.
    function reportPage() {
        const g = vista.lateral[vista.seccion]
        if (g)
            vista.plugin.currentPage =
                String(g.vista || g.grupo).toLowerCase()
    }

    function elegir(i) {
        //  Out of range is a closed door, not a page: an index nobody has
        //  would leave the content empty and every row comparing itself
        //  against nothing.
        if (i < 0 || i >= vista.lateral.length)
            return
        saveScroll()
        vista.selectedPage = pageKey(vista.lateral[i])
        vista.busqueda = ""
        campo.text = ""
        highlightedSetting = ""
        reportPage()
        Qt.callLater(function () {
            pageScroll.contentY = Math.min(scrollPositions[selectedPage] || 0,
                Math.max(0, pageScroll.contentHeight - pageScroll.height))
        })
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
                                color: Theme.muted
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
                                activeFocusOnTab: true
                                Accessible.name: "Search settings"
                                onTextEdited: vista.search(text)

                                //  ESC undoes the inside first and only closes
                                //  when there is nothing left to undo. If it
                                //  always bubbled up, clearing a search would
                                //  cost the whole view.
                                Keys.onPressed: function (ev) {
                                    if (ev.key !== Qt.Key_Escape)
                                        return
                                    if (campo.text.length > 0) {
                                        campo.text = ""
                                        vista.search("")
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
                                    !vista.searching
                                    && !rama.acogida
                                    && vista.seccion === rama.indice

                                Rectangle {
                                    id: parentNavigation
                                    width: parent.width
                                    height: 34
                                    radius: 9
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: rama.modelData.grupo
                                    Keys.onReturnPressed: vista.elegir(rama.indice)
                                    Keys.onSpacePressed: vista.elegir(rama.indice)
                                    border.width: activeFocus ? 1 : 0
                                    border.color: Theme.blue
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
                                        onClicked: {
                                            parentNavigation.forceActiveFocus(Qt.MouseFocusReason)
                                            vista.elegir(rama.indice)
                                        }
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

                                        K4.Boton {
                                            visible: rama.despliega
                                            Layout.alignment: Qt.AlignVCenter
                                            glifo: rama.abierta ? Theme.ico.chevronDown : Theme.ico.forward
                                            color: Theme.muted
                                            tamano: 13
                                            Accessible.name: (rama.abierta ? "Collapse " : "Expand ") + rama.modelData.grupo
                                            onPulsado: vista.tocarPadre(rama.modelData)
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
                                    enabled: rama.abierta
                                    opacity: rama.abierta ? 1 : 0

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 180
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
                                                    !vista.searching
                                                    && vista.seccion === hija.indice

                                                width: parent.width
                                                height: 30
                                                radius: 8
                                                activeFocusOnTab: rama.abierta
                                                Accessible.role: Accessible.Button
                                                Accessible.name: modelData.grupo
                                                Keys.onReturnPressed: vista.elegirHijo(modelData)
                                                Keys.onSpacePressed: vista.elegirHijo(modelData)
                                                border.width: activeFocus ? 1 : 0
                                                border.color: Theme.blue
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
                                                    onClicked: {
                                                        hija.forceActiveFocus(Qt.MouseFocusReason)
                                                        vista.elegirHijo(hija.modelData)
                                                    }
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
                            vista.searching ? 0xF0349
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
                        text: vista.searching
                            ? `${vista.cuantasCasan} ${vista.cuantasCasan === 1 ? "result" : "results"}`
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
                        text: vista.searching
                            ? `Settings matching “${vista.busqueda.trim()}”`
                            : (vista.contenido.length > 0
                               ? (vista.contenido[0].vista === "display"
                                  ? "Wallpaper, palette, fonts and monitor layout."
                                  : vista.contenido[0].vista === "placement"
                                  ? "Choose where each view opens. Follow the bar or set its own position."
                                  : vista.contenido[0].desc || "") : "")
                        textFormat: Text.PlainText
                        color: Theme.muted
                        font.pixelSize: 11
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
                K4.ActionButton {
                    id: novedad
                    visible: vista.plugin.version.hayNovedad
                    Layout.alignment: Qt.AlignVCenter
                    text: vista.plugin.version.sucio ? "Update pending"
                        : "Update (" + vista.plugin.version.detras + ")"
                    enabled: !vista.plugin.version.sucio
                    Accessible.description: vista.plugin.version.sucio
                        ? "Save your local changes before updating" : "Update k4"
                    onClicked: {
                        vista.plugin.version.actualizar()
                        vista.plugin.close()
                    }
                }
            }

            // ── the options ──────────────────────────────────────
            K4.Rodillo {
                id: pageScroll
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
                            spacing: 8

                            //  While searching there are several sections at
                            //  once, and without their titles the matches read
                            //  as a loose list with no context. With a single
                            //  section the title is already in the header and
                            //  repeating it would be noise.
                            K4.ActionButton {
                                visible: vista.searching && bloque.modelData.atajo === undefined
                                text: bloque.modelData.grupo + "  →"
                                Accessible.name: "Open in " + bloque.modelData.grupo
                                onClicked: vista.openResult(bloque.modelData)
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
                                        && !vista.searching
                                sourceComponent: Component {
                                    PortadaFamilia {
                                        familia: bloque.modelData
                                        onPedida: function (grupo) {
                                            vista.elegirHijo(grupo)
                                        }
                                    }
                                }
                            }

                            //  The accent belongs with the image it is sampled
                            //  from, rather than the manual colour presets.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "wallpaper"
                                        && !vista.searching
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    PaletteFromWallpaper {}
                                }
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
                                        && !vista.searching
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    RejillaFondos {
                                        motor: WallpaperPalette
                                        fitContent: true
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
                                        && !vista.searching
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
                                Accessible.name: "Open " + bloque.modelData.grupo

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

                            //  ── a page some plugin contributes ──────────
                            //
                            //  Any plugin can ship a whole page — the theme
                            //  engine ships the Display family's working
                            //  pages this way. The Component is asked to the
                            //  registry BY NAME: a Repeater hands its
                            //  delegates a copy of the model object, and a
                            //  Component that travelled inside a copy does
                            //  not instantiate. The section vanishes with
                            //  its plugin — nobody renders a page whose
                            //  author is gone, which is why the null-motor
                            //  question never comes up for these.
                            //
                            //  Height rides `implicitHeight`, like every
                            //  native page: an inactive Loader still measures
                            //  what you ask of it.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.pagina !== undefined
                                        && !vista.searching
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: bloque.modelData.pagina
                                    ? Enganches.componenteDe(
                                        bloque.modelData.pagina.plugin,
                                        bloque.modelData.pagina.name)
                                    : null
                            }

                            //  The placement editor: one card per
                            //  openable view, wrapping side controls and a
                            //  draggable monitor preview for precise placement.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "placement"
                                        && !vista.searching
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
                                        && !vista.searching
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component { PanelEditor {} }
                            }

                            //  And a section can bring something of its own on
                            //  top of its options. The Island one carries a
                            //  sketch of the screen: it turns three similar
                            //  words into a difference you can see. Below it,
                            //  the at-rest pill editor edits composition.
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
                                        && !vista.searching
                                sourceComponent: Component { PrevioIsland {} }
                            }

                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "island"
                                        && bloque.modelData.atajo === undefined
                                        && !vista.searching
                                sourceComponent: Component { PillEditor {} }
                            }

                            //  Each group chooses how it paints. Today only
                            //  Plugins asks for something different —almost
                            //  forty rows, each with its own inside— and the
                            //  rest paint as always. When another section
                            //  wants its own, it is added here and nothing else
                            //  is touched.
                            Repeater {
                                model: vista.searching ? bloque.modelData.opciones
                                    : (bloque.modelData.opciones || []).filter(function (option) {
                                        if (bloque.modelData.vista === "placement") return false
                                        return bloque.modelData.vista !== "panel"
                                            || ["panelShowToggles", "panelShowMedia", "panelShowShortcuts"].indexOf(option.id) < 0
                                    })
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
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // ── the two ways to paint a row ──────────────────────────────
    Component {
        id: comoOpcion
        FilaOpcion {
            modelData: parent.dato
            highlighted: vista.highlightedSetting === modelData.id
        }
    }

    Component {
        id: comoPlugin
        FilaPlugin { modelData: parent.dato }
    }
}
