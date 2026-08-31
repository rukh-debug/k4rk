//  The landing page of a family: what a parent group shows when you land on
//  it instead of on one of its children.
//
//  «Display» is the first family, and its landing answers the question you
//  bring when you open it — what does my screen look like right now? — with
//  the wallpaper at a glance, and then hands you the drawer's rows again,
//  big: a card per child, for the first visit, before you learn the sidebar.
//
//  It does not know its children by name: it reads them from the same tree
//  the sidebar reads (`Settings.definicion` → `hijosDe`), so a family that
//  grows tomorrow gets its card for free. A group may also carry an `app`:
//  a full application that belongs to the subject — the displays tool —
//  which opens as itself and not as a page here, because arranging monitors
//  is a screen of its own.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: portada

    //  The family this is the landing of.
    required property var familia

    //  A child card was clicked. The view decides what «going there» means
    //  (opening the family's drawer on the way in) — this page only knows
    //  its own cards.
    signal pedida(var grupo)

    //  The family's tool card was clicked: open the application, which in
    //  practice means the hosting view steps aside first. Again the view's
    //  call; the card just says it was asked.
    signal pedidaApp()

    //  The theme engine, for the wallpaper the hero shows. Passed in by the
    //  hosting view, which holds the injected reference.
    required property var motor

    //  The wallpaper currently applied, exactly the way the grid decides it:
    //  the chosen monitor's if one is chosen, the common one otherwise.
    readonly property string fondo: motor ? (motor.pantallaElegida.length > 0
        ? motor.fondoDe(motor.pantallaElegida) : motor.wallpaper) : ""

    //  Its file name without folders, for the label. Empty when nothing is
    //  set, which is its own honest state: the hero says so instead of
    //  painting a stale image.
    readonly property string nombreFondo: fondo.length > 0
        ? fondo.substring(fondo.lastIndexOf("/") + 1) : ""

    spacing: 14

    //  The drawer's rows, read from the same definition the sidebar reads.
    //  Here and not «passed in» because the cards and the sidebar must never
    //  disagree about who belongs to the family — one source, two readers.
    readonly property var hijos: Settings.definicion.filter(function (g) {
        return g.padre === portada.familia.grupo && g.enLateral !== false
    })

    //  ── the hero: the desktop at a glance ─────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        radius: 12
        clip: true
        color: Theme.islandBg

        Image {
            visible: portada.fondo.length > 0
            anchors.fill: parent
            source: portada.fondo.length > 0
                ? "file://" + Fondos.miniaturaDe(portada.fondo) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 900
        }

        //  The name rides on a floor of its own: readable over a snowfield
        //  and over a night sky alike.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 34
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#cc000000" }
                GradientStop { position: 1; color: "#66000000" }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                IconGlyph {
                    text: Theme.ico.wallpaper
                    color: Theme.ink
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignVCenter
                }

                IslandLabel {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    //  With the engine off, «No wallpaper set» would be a
                    //  lie: there may well be one — we just cannot ask the
                    //  only one who knows. The honest line names the cause.
                    text: !portada.motor
                        ? "The theme plugin is off"
                        : (portada.nombreFondo.length > 0
                           ? portada.nombreFondo
                           : "No wallpaper set")
                    textFormat: Text.PlainText
                    color: Theme.ink
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }

                IslandLabel {
                    visible: portada.nombreFondo.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: Fondos.lista.length + " in the grid"
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }
        }
    }

    //  ── a card per child ──────────────────────────────────────
    //
    //  Two by two for four; one row of three for three. The grid wraps, so
    //  the family can grow a fifth without this page noticing.
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: portada.hijos

            delegate: K4.Baldosa {
                id: tarjeta
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 72
                radius: 12

                onPulsada: portada.pedida(tarjeta.modelData)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
                        color: Qt.rgba(Theme.blue.r, Theme.blue.g,
                                       Theme.blue.b, 0.16)

                        IconGlyph {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(
                                tarjeta.modelData.glifo
                                    ? tarjeta.modelData.glifo : 0xF0431)
                            color: Theme.blue
                            font.pixelSize: 16
                            renderType: Text.NativeRendering
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        IslandLabel {
                            Layout.fillWidth: true
                            text: tarjeta.modelData.grupo
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: tarjeta.modelData.desc || ""
                            textFormat: Text.PlainText
                            color: Theme.dim
                            font.pixelSize: 9
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                        }
                    }

                    IconGlyph {
                        Layout.alignment: Qt.AlignVCenter
                        text: Theme.ico.forward
                        color: Theme.dim
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    //  ── the family's tool ─────────────────────────────────────
    //
    //  `app` on the group: an application that belongs to the subject but is
    //  a screen of its own — the displays arrangement. It opens as itself:
    //  this view steps aside first, because the island hosts one view at a
    //  time and a hidden switcher would be a lie.
    K4.Baldosa {
        id: tarjetaApp
        visible: String(portada.familia.app || "").length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 46 : 0
        radius: 10

        //  Off or broken, the door says so instead of pretending: a card
        //  that does nothing teaches that cards do nothing.
        readonly property bool lista: PluginManager.estaHabilitado(
            String(portada.familia.app || ""))

        opacity: tarjetaApp.lista ? 1 : 0.45

        onPulsada: {
            if (tarjetaApp.lista)
                portada.pedidaApp()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            spacing: 12

            IconGlyph {
                Layout.alignment: Qt.AlignVCenter
                //  md-monitor: the tool this card is, in this family.
                text: String.fromCodePoint(0xF0379)
                color: Theme.muted
                font.pixelSize: 15
                renderType: Text.NativeRendering
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                IslandLabel {
                    Layout.fillWidth: true
                    text: "Monitor layout"
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: tarjetaApp.lista
                        ? "Arrange and enable your screens"
                        : "The displays plugin is off"
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            //  It leaves, it does not dig: the arrow says «this opens
            //  elsewhere», the same glyph the footer's tool tiles use.
            IconGlyph {
                Layout.alignment: Qt.AlignVCenter
                text: Theme.ico.forward
                color: Theme.dim
                font.pixelSize: 13
                renderType: Text.NativeRendering
            }
        }
    }
}
