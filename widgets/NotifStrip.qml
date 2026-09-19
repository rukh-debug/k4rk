//  Recent-notification strip.
//
//  Appears below the clock or player while hovering over the island, when
//  the user is already looking there. Recent arrivals are accessible without
//  opening the panel. Clicking opens the associated application, as with a
//  toast; the close button dismisses the notification.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

ColumnLayout {
    id: strip

    // Limit the visible count so notifications do not overwhelm the island.
    property int max: 3

    readonly property int shown: Math.min(Notifs.recent.length, max)
    readonly property int rowHeight: 34

    // Required height, including the header. The service owns the formula
    // because plugins use it to size the island too.
    readonly property int neededHeight: Settings.notificationsOnHover
        ? Notifs.stripHeight(max) : 0

    visible: Notifs.recent.length > 0 && Settings.notificationsOnHover
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 14
        spacing: 6

        IconGlyph {
            text: Theme.ico.bell
            color: Theme.muted
            font.pixelSize: 11
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            text: Notifs.recent.length === 1
                ? "1 notification"
                : Notifs.recent.length + " notifications"
            color: Theme.muted
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        IslandLabel {
            visible: Notifs.recent.length > strip.shown
            text: "+" + (Notifs.recent.length - strip.shown) + " more"
            color: Theme.dim
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        // Clear everything here: without this action, a user viewing the
        // hover strip had to open the full panel merely to dismiss a few
        // notifications they had already read.
        Rectangle {
            Layout.preferredWidth: vaciarFila.implicitWidth + 12
            Layout.preferredHeight: 15
            Layout.alignment: Qt.AlignVCenter
            radius: 7
            color: vaciarRaton.containsMouse ? Theme.red : Theme.surfaceHi

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: vaciarFila
                anchors.centerIn: parent
                spacing: 3

                IconGlyph {
                    text: Theme.ico.clearAll
                    color: vaciarRaton.containsMouse ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                }

                IslandLabel {
                    text: "Clear all"
                    color: vaciarRaton.containsMouse ? Theme.ink : Theme.muted
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }

            MouseArea {
                id: vaciarRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.clear()
            }
        }
    }

    Repeater {
        model: Notifs.recent.slice(0, strip.shown)

        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string icon: Notifs.iconFor(modelData)

            Layout.fillWidth: true
            Layout.preferredHeight: strip.rowHeight
            radius: 9
            color: rowMouse.containsMouse ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 4
                spacing: 8

                Image {
                    source: row.icon
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignVCenter
                    visible: status === Image.Ready
                }

                IconGlyph {
                    visible: row.icon.length === 0
                    text: Theme.ico.bell
                    color: Theme.muted
                    font.pixelSize: 13
                    Layout.preferredWidth: 16
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    //  One line each, regardless of the input.
                    //
                    //  `elide` limits WIDTH, not height. Bodies with line
                    //  breaks, such as cronjob output with a response, job id
                    //  and separator on separate lines, used to render below
                    //  the fixed `rowHeight` box. The notification overlapped
                    //  whatever followed and made the card look broken.
                    //
                    //  Replace breaks with spaces rather than cutting at the
                    //  first one: cronjobs often start with a generic "Cronjob
                    //  Response" heading, followed by the useful content.
                    //  Joining the lines lets elision preserve that content.
                    IslandLabel {
                        text: row.modelData.summary.replace(/\s*\n\s*/g, " ")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }

                    IslandLabel {
                        text: (row.modelData.body.length > 0
                                ? row.modelData.body : row.modelData.appName)
                              .replace(/\s*\n\s*/g, " ")
                        color: Theme.muted
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }
                }

                MediaButton {
                    glyph: Theme.ico.close
                    glyphSize: 12
                    glyphColor: rowMouse.containsMouse ? Theme.ink : Theme.dim
                    onActivated: row.modelData.dismiss()
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // The close button sits above this and receives its own click.
                onClicked: Notifs.activate(row.modelData)
            }
        }
    }
}
