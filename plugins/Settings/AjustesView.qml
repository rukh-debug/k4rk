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
    //  whole section.
    function irASeccion(nombre) {
        for (let i = 0; i < vista.lateral.length; ++i)
            if (vista.lateral[i].grupo === nombre) {
                vista.elegir(i)
                return
            }
    }

    function elegir(i) {
        vista.seccion = i
        vista.busqueda = ""
        campo.text = ""
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        anchors.bottomMargin: 10
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
                K4.Rodillo {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: vista.lateral

                            //  A bare rectangle and not `K4.Baldosa`: Baldosa
                            //  draws an inner border ALWAYS, and with fourteen
                            //  in a row the sidebar becomes a grid of boxes.
                            //  What must stand out here is ONE: the one you
                            //  are looking at.
                            delegate: Rectangle {
                                id: entrada
                                required property var modelData
                                required property int index

                                readonly property bool activa:
                                    vista.busqueda.length === 0
                                    && vista.seccion === entrada.index

                                width: parent.width
                                height: 34
                                radius: 9
                                color: entrada.activa
                                    ? Qt.rgba(Theme.blue.r, Theme.blue.g,
                                              Theme.blue.b, 0.18)
                                    : (raton.containsMouse
                                       ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                                Behavior on color { ColorAnimation { duration: 120 } }

                                MouseArea {
                                    id: raton
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: vista.elegir(entrada.index)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    IconGlyph {
                                        Layout.alignment: Qt.AlignVCenter
                                        //  No icon of its own —a plugin section
                                        //  that did not declare one— gets the
                                        //  puzzle piece, which is how the bar
                                        //  draws «this is a plugin» everywhere.
                                        text: String.fromCodePoint(
                                            entrada.modelData.glifo
                                                ? entrada.modelData.glifo : 0xF0431)
                                        color: entrada.activa
                                            ? Theme.blue : Theme.muted
                                        font.pixelSize: 14
                                        renderType: Text.NativeRendering
                                    }

                                    IslandLabel {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: entrada.modelData.grupo
                                        textFormat: Text.PlainText
                                        color: entrada.activa
                                            ? Theme.ink : Theme.muted
                                        font.pixelSize: 12
                                        font.weight: entrada.activa
                                            ? Font.DemiBold : Font.Normal
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

                            //  Appearance has no options: it carries the whole
                            //  wallpaper grid, the same one the theme screen
                            //  shows. The engine is asked for by id and its
                            //  folder is not imported: with the plugin off this
                            //  just waits, without breaking.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                //  As much as fits: what happens here is
                                //  looking at thumbnails — the more of them on
                                //  screen, the less scrolling.
                                //
                                //  Conditional on `active`, and it is not a
                                //  detail: an inactive Loader STILL occupies
                                //  the height you ask of it, so without this
                                //  the other sections had an invisible ~400px
                                //  hole in front and their content fell out of
                                //  view. The header showed and nothing else,
                                //  without a single error in the log.
                                Layout.preferredHeight: active
                                    ? Math.max(300, vista.height - 260) : 0
                                active: bloque.modelData.vista === "fondos"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    RejillaFondos {
                                        motor: PluginManager.instancia("hyprtheme")
                                    }
                                }
                            }

                            IslandLabel {
                                Layout.fillWidth: true
                                visible: bloque.modelData.vista === "fondos"
                                         && !PluginManager.instancia("hyprtheme")
                                text: "The theme plugin is off: you can view the wallpapers, but not apply them."
                                color: Theme.dim
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
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

                            //  Colour, in its own section.
                            //
                            //  The four loaders below keep their height
                            //  conditional on `active`. It is the lesson from
                            //  the commit before: an inactive one loads
                            //  nothing but STILL measures whatever you ask of
                            //  it, and that pushes the other sections' content
                            //  out of view without a single error.
                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "color"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    AjustesTema {
                                        motor: PluginManager.instancia("hyprtheme")
                                    }
                                }
                            }

                            Loader {
                                visible: active
                                Layout.fillWidth: true
                                Layout.preferredHeight: active && item
                                    ? item.implicitHeight : 0
                                active: bloque.modelData.vista === "ventanas"
                                        && bloque.modelData.atajo === undefined
                                sourceComponent: Component {
                                    AjustesVentanas {
                                        motor: PluginManager.instancia("hyprtheme")
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
                                        motor: PluginManager.instancia("hyprtheme")
                                    }
                                }
                            }

                            //  «Save» travels with whatever the Hyprland Lua
                            //  writes. Wallpapers do not carry it: those save
                            //  on their own the moment you pick one.
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
                                        motor: PluginManager.instancia("hyprtheme")
                                    }
                                }
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
