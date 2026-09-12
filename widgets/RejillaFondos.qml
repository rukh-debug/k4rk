//  The desktop wallpaper grid.
//
//  It was born inside the theme plugin's own screen. It moved here when
//  TWO places came to show it — the theme screen and Settings' Appearance
//  section — and two copies of three hundred lines diverge at the first
//  fix: one gets repaired, the other keeps lying.
//
//  ── where things come from ───────────────────────────────────────
//
//  What it LOOKS at comes from the `Fondos` service: what exists, how
//  each one looks, which one is set. That is nobody's in particular.
//
//  What it DOES goes through the `motor` it is handed: apply, remove,
//  bring one in from outside, the transitions. That motor is the host's
//  WallpaperPalette service, which talks to awww/swww/swaybg. It is an
//  object and not an import so the widget stays a dumb surface: the
//  service could be swapped without this file noticing.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../core"
import "../services"

ColumnLayout {
    id: rejilla

    //  Who knows how to apply a wallpaper: the host's WallpaperPalette
    //  service, handed in so the widget never imports the engine.
    property var motor: WallpaperPalette

    //  `true`: the grid drops its own scrolling and sizes itself to its rows,
    // so the page hosting it scrolls EVERYTHING as one — the Settings view,
    // where the colour block follows the grid and a scroll inside a scroll
    // would wall it off. `false` (default): the grid scrolls inside, which is
    // what a screen of its own wants — the whole viewport for thumbnails.
    property bool fitContent: false
    property int thumbnailsReady: 4

    Timer {
        id: thumbnailQueue
        interval: 150
        repeat: true
        onTriggered: {
            //  The scan is asynchronous: an empty list is "not here yet",
            //  not "nothing to show" — keep ticking until it lands.
            if (Fondos.lista.length === 0)
                return
            rejilla.thumbnailsReady += 4
            if (rejilla.thumbnailsReady >= Fondos.lista.length)
                stop()
        }
    }

    //  The monitors, for the filter above. The motor knows them.
    readonly property var pantallas: rejilla.motor
        && typeof rejilla.motor.pantallasConocidas === "function"
        ? rejilla.motor.pantallasConocidas() : []

    //  Which one is set NOW on what is being looked at: the chosen
    //  monitor's if there is one chosen, and otherwise the common one.
    //  It is what marks the thumbnail in blue, so it has to follow the
    //  filter above.
    //  The scan is asked for when shown and only if there is nothing: a
    //  `find` over seven folders on every bar start would be paying for a
    //  list that is almost never looked at. And showing it again does not
    //  repeat it — the list is already there and the refresh button
    //  exists for that.
    function pedirLista() {
        if (Fondos.lista.length === 0 && !Fondos.rastreando)
            Fondos.rastrear()
    }

    Component.onCompleted: if (visible) { pedirLista(); thumbnailQueue.start() }
    onVisibleChanged: if (visible) { pedirLista(); thumbnailQueue.start() }
    onThumbnailsReadyChanged: if (thumbnailsReady >= Fondos.lista.length)
        thumbnailQueue.stop()

    readonly property string destinoActual: rejilla.motor
        ? (rejilla.motor.pantallaElegida.length > 0
           ? rejilla.motor.fondoDe(rejilla.motor.pantallaElegida)
           : rejilla.motor.wallpaper)
        : ""

    //  No `anchors.fill`: that was for when this lived inside a screen of
    //  its own. Here the section's column places it, and mixing anchors
    //  with Layout leaves the widget the wrong size.
    Layout.fillWidth: true
    spacing: 10

    //  ── which screen we are working on ─────────────
    //
    //  With two monitors, "set this wallpaper" is ambiguous, and the
    //  old grid decided for you: one for both. Here one picks the
    //  destination first and then the image, which is the order one
    //  thinks in.
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [""].concat(rejilla.pantallas)

            delegate: Rectangle {
                id: chipPantalla
                required property var modelData
                readonly property bool puesta:
                    !!rejilla.motor
                    && rejilla.motor.pantallaElegida === modelData

                Layout.preferredWidth: textoPantalla.implicitWidth + 22
                Layout.preferredHeight: 24
                radius: 12
                color: puesta ? Theme.blue
                    : (ratonPantalla.containsMouse ? Theme.surfaceHi
                                                   : Theme.surface)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: textoPantalla
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: chipPantalla.modelData.length === 0
                        ? "All" : chipPantalla.modelData
                    color: chipPantalla.puesta ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                    font.weight: chipPantalla.puesta
                        ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: ratonPantalla
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (rejilla.motor)
                        rejilla.motor.pantallaElegida =
                            chipPantalla.modelData
                }
            }
        }

        Item { Layout.fillWidth: true }

        IslandLabel {
            text: Fondos.lista.length + " backgrounds"
            color: Theme.dim
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        //  ── bringing one in from outside ───────────
        //
        //  The scan looks at a few folders and none of them has to be
        //  yours: the wallpaper you just downloaded to an odd place does
        //  not show up, and the only way out used to be moving it.
        Rectangle {
            Layout.preferredWidth: textoAnadir.implicitWidth + 22
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignVCenter
            radius: 12
            color: anadirRaton.containsMouse ? Theme.surfaceHi
                                             : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            IslandLabel {
                id: textoAnadir
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Add…"
                color: Theme.muted
                font.pixelSize: 10
            }

            MouseArea {
                id: anadirRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (rejilla.motor) rejilla.motor.elegirFondo()
            }
        }

        MediaButton {
            glyph: Theme.ico.loading
            glyphSize: 14
            glyphColor: Theme.muted
            onActivated: Fondos.rastrear()
            Layout.alignment: Qt.AlignVCenter
        }
    }

    //  ── how one passes to another ──────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        IslandLabel {
            text: "Transition"
            color: Theme.dim
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        Repeater {
            model: rejilla.motor ? rejilla.motor.transiciones : []

            delegate: Rectangle {
                id: chipTrans
                required property var modelData
                readonly property bool puesta:
                    !!rejilla.motor
                    && rejilla.motor.transicion === modelData

                Layout.preferredWidth: textoTrans.implicitWidth + 20
                Layout.preferredHeight: 22
                radius: 11
                color: puesta ? Theme.blue
                    : (ratonTrans.containsMouse ? Theme.surfaceHi
                                                : Theme.track)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: textoTrans
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: chipTrans.modelData
                    color: chipTrans.puesta ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                }

                MouseArea {
                    id: ratonTrans
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (rejilla.motor)
                        rejilla.motor.transicion = chipTrans.modelData
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(wallpaperGrid.implicitHeight,
                                         Math.round(width / 4 * 0.6) * 2)
        clip: true
        //  A GridView sized to all its content creates delegates from the end
        //  of the model. A plain Grid constructs the first row first, so the
        //  wallpapers visible at the top get the first decode slots.
        Grid {
            id: wallpaperGrid
            width: parent.width
            columns: 4
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                model: Fondos.lista

                delegate: Item {
            id: wallCell
            required property var modelData
            required property int index
            width: Math.floor(wallpaperGrid.width / wallpaperGrid.columns)
            height: Math.round(width * 0.6)

            //  The outer page owns scrolling in fit-content mode, so this
            //  GridView initially creates every delegate. Render the first
            //  rows immediately; the rest can decode off the UI path.
            readonly property bool firstRows: index < 4

            //  What is set ON the chosen destination, not the common
            //  wallpaper: with "HDMI-A-1" selected, what must be marked
            //  is that screen's.
            readonly property bool current: rejilla.destinoActual === modelData
            readonly property bool mueve: !Fondos.esQuieto(modelData)
            //  Did you bring it yourself? Only those can be removed.
            readonly property bool propio:
                Fondos.extras.indexOf(modelData) >= 0

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 10
                color: Theme.islandBg
                border.width: wallCell.current ? 2
                    : (wallMouse.containsMouse ? 1 : 0)
                border.color: wallCell.current ? Theme.blue : Theme.surfaceHi
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: wallCell.current ? 2 : 0
                    //  Videos and GIFs use the poster prepared during the
                    //  scan, rather than opening the moving source here.
                    source: wallCell.index < rejilla.thumbnailsReady
                        ? "file://" + Fondos.miniaturaDe(wallCell.modelData) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: !wallCell.firstRows
                    cache: true
                    sourceSize.width: 320
                    sourceSize.height: 192
                    autoTransform: true
                    mipmap: true
                }

                //  It moves, and what it is. Without this, a video and a
                //  photo look identical in the grid — the poster IS a
                //  photo — and you do not know what you are choosing.
                Rectangle {
                    visible: wallCell.mueve
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: etiquetaMueve.implicitWidth + 12
                    height: 16
                    radius: 8
                    color: "#cc000000"

                    IslandLabel {
                        id: etiquetaMueve
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: /\.(gif|apng)$/i.test(wallCell.modelData)
                            ? "GIF" : "video"
                        color: Theme.ink
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }

                //  The name, readable over any image
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 20
                    color: "#cc000000"
                    visible: wallMouse.containsMouse || wallCell.current

                    IslandLabel {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: wallCell.modelData.substring(
                            wallCell.modelData.lastIndexOf("/") + 1)
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }
                }

                //  The removal cross, only on the ones you brought in
                //  yourself: the ones the scan found cannot be removed
                //  from a list they are not in.
                Rectangle {
                    visible: wallCell.propio
                        && (wallMouse.containsMouse || quitarRaton.containsMouse)
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 6
                    width: 18
                    height: 18
                    radius: 9
                    color: quitarRaton.containsMouse
                        ? Theme.red : "#cc000000"

                    IslandLabel {
                        anchors.centerIn: parent
                        //  By codepoint and not as a literal: the text
                        //  extractor sees any string in a `text:` and
                        //  puts it in the template, and a cross does
                        //  not translate.
                        text: String.fromCodePoint(0x00d7)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: quitarRaton
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (rejilla.motor)
                            rejilla.motor.quitarFondo(wallCell.modelData)
                    }
                }

                MouseArea {
                    id: wallMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    //  Below the cross on purpose: declared after it
                    //  it would sit on top and eat its click.
                    z: -1
                    onClicked: {
                        if (rejilla.motor
                                && typeof rejilla.motor.ponerEnElegida === "function")
                            rejilla.motor.ponerEnElegida(wallCell.modelData)
                        else
                            WallpaperPalette.select(wallCell.modelData)
                    }
                }
            }
                }
            }
        }

        IslandLabel {
            anchors.centerIn: parent
            visible: Fondos.lista.length === 0
            text: "No backgrounds in your picture folders or the system ones"
            color: Theme.muted
            font.pixelSize: 12
        }

    }

    //  The status line, which travelled with the deleted screen and is
    //  still needed: without a tool installed the grid looks fine and
    //  applies nothing, and without this that read as a failure.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8

        readonly property bool hay: !!rejilla.motor
            && String(rejilla.motor.wallTool || "").length > 0
        readonly property bool puesto: !!rejilla.motor
            && String(rejilla.motor.wallpaper || "").length > 0

        IconGlyph {
            text: parent.hay && parent.puesto ? Theme.ico.check : Theme.ico.alert
            color: parent.hay && parent.puesto ? Theme.green : Theme.muted
            font.pixelSize: 12
            renderType: Text.NativeRendering
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            Layout.fillWidth: true
            text: !parent.hay
                ? "Install awww, swww or swaybg to apply wallpapers"
                : (parent.puesto
                   ? "Wallpaper applied and saved automatically"
                   : "Pick an image to change the wallpaper")
            color: Theme.muted
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
