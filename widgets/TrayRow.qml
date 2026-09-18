//  Tray icon row.
//
//  It rides in the pill and also in the hover views (clock and player), and
//  that double seat is no whim: hovering swaps the island to another view,
//  so icons living only in the pill would vanish just before you could press
//  them. In the pill they are indicators; where they can really be pressed
//  is in the already unfolded view, which does not move while the pointer
//  stays over it.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: row

    // How many icons to show before summarizing the rest as "+n".
    // Zero shows everything: no "+N" by default. Follows the user's
    // pill setting unless a view overrides it.
    property int max: Settings.pillTrayMax
    property int iconSize: 14
    // Not in the pill: targets are tiny and a miss would launch an
    // application when what you wanted was the control centre.
    property bool interactive: false

    // Emitted when the whole tray is requested (right click).
    signal menuRequested()

    readonly property int shown: max > 0 ? Math.min(Tray.count, max) : Tray.count

    visible: Tray.count > 0 && (interactive || Settings.trayInPill)
    spacing: 4

    Repeater {
        model: Tray.sorted.slice(0, row.shown)

        delegate: Item {
            id: cell
            required property var modelData

            Layout.preferredWidth: row.iconSize + (row.interactive ? 8 : 0)
            Layout.preferredHeight: row.iconSize + (row.interactive ? 6 : 0)
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: 6
                visible: row.interactive && cellMouse.containsMouse
                color: Theme.surfaceHi
            }

            Image {
                anchors.centerIn: parent
                width: row.iconSize
                height: row.iconSize
                source: cell.modelData.icon
                sourceSize.width: row.iconSize * 2
                sourceSize.height: row.iconSize * 2
                fillMode: Image.PreserveAspectFit
                opacity: cell.modelData.status === 2 ? 1 : 0.85

                // NeedsAttention: blink, that is what it asks for
                SequentialAnimation on opacity {
                    running: cell.modelData.status === 2
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            MouseArea {
                id: cellMouse
                anchors.fill: parent
                enabled: row.interactive
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton)
                        row.menuRequested()          // the menu lives in the module
                    else if (mouse.button === Qt.MiddleButton)
                        Tray.secondary(cell.modelData)
                    else if (!Tray.primary(cell.modelData))
                        row.menuRequested()          // menu-only: show it
                }

                onWheel: function (wheel) {
                    cell.modelData.scroll(wheel.angleDelta.y, false)
                }
            }
        }
    }

    IslandLabel {
        visible: Tray.count > row.shown
        text: "+" + (Tray.count - row.shown)
        color: Theme.muted
        font.pixelSize: 10
        Layout.alignment: Qt.AlignVCenter

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            enabled: row.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: row.menuRequested()
        }
    }
}
