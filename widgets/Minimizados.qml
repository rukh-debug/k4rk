//  Set-aside modules, in the pill.
//
//  One capsule per thing left half-done. In the pill it is notice-only
//  —hovering already swaps the island to another view—; in the hover
//  views it is pressed and goes back to where it was.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: fila

    property bool interactive: false

    // How many items to show before summarizing the rest as "+n".
    // Zero shows everything: no "+N" by default. Follows the user's
    // pill setting unless a view overrides it.
    property int max: Settings.pillMinimizedMax

    readonly property int shown: max > 0 ? Math.min(Modulos.count, max) : Modulos.count

    visible: Modulos.count > 0
    spacing: 5

    Repeater {
        model: Modulos.lista.slice(0, fila.shown)

        delegate: Rectangle {
            id: capsula
            required property var modelData

            // The close-button gap is always reserved, even though it only
            // paints on hover: without it the capsule jumps in width just
            // as you go to press it and the button escapes you.
            Layout.preferredWidth: contenido.implicitWidth + (fila.interactive ? 38 : 10)
            Layout.preferredHeight: fila.interactive ? 22 : 17
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: raton.containsMouse && fila.interactive
                ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: contenido
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: fila.interactive ? 8 : 5
                spacing: 4

                IconGlyph {
                    visible: capsula.modelData.glifo > 0
                    text: capsula.modelData.glifo > 0
                        ? String.fromCodePoint(capsula.modelData.glifo) : ""
                    color: Theme.muted
                    font.pixelSize: fila.interactive ? 12 : 10
                }

                // In the pill only the icon and the short detail: the full
                // title reads on open, and what matters here is that
                // something is waiting for you.
                IslandLabel {
                    visible: capsula.modelData.detalle.length > 0
                    text: capsula.modelData.detalle
                    color: Theme.muted
                    font.pixelSize: fila.interactive ? 10 : 9
                    elide: Text.ElideRight
                    Layout.maximumWidth: fila.interactive ? 150 : 90
                }
            }

            MouseArea {
                id: raton
                anchors.fill: parent
                hoverEnabled: true
                enabled: fila.interactive
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: function (ev) {
                    if (ev.button === Qt.MiddleButton)
                        Modulos.quitar(capsula.modelData.id)
                    else
                        Modulos.restaurar(capsula.modelData.id)
                }
            }

            //  The close button to discard, on hover.
            //
            //  The middle button works too, but nobody guesses that:
            //  without something visible, what you set aside stays there
            //  forever with no obvious way to remove it.
            Rectangle {
                visible: fila.interactive && (raton.containsMouse || aspaRaton.containsMouse)
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 16
                height: 16
                radius: 8
                color: aspaRaton.containsMouse ? Theme.red : Theme.surfaceHi

                IconGlyph {
                    anchors.centerIn: parent
                    text: Theme.ico.close
                    color: Theme.ink
                    font.pixelSize: 10
                }

                MouseArea {
                    id: aspaRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Modulos.quitar(capsula.modelData.id)
                }
            }
        }
    }

    // Whatever does not fit goes into a capsule. It takes no clicks:
    // it would lead nowhere concrete — there are several — it is there
    // so the row never lies when a limit is set. With no limit (the
    // default) it never shows.
    Rectangle {
        visible: Modulos.count > fila.shown
        Layout.preferredWidth: resto.implicitWidth + (fila.interactive ? 16 : 10)
        Layout.preferredHeight: fila.interactive ? 22 : 17
        Layout.alignment: Qt.AlignVCenter
        radius: height / 2
        color: Theme.surface

        IslandLabel {
            id: resto
            anchors.centerIn: parent
            text: "+" + (Modulos.count - fila.shown)
            color: Theme.muted
            font.pixelSize: fila.interactive ? 10 : 9
            font.weight: Font.Medium
        }
    }
}
