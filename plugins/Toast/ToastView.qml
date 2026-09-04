import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    readonly property var notification: Notifs.latest
    readonly property string icon: Notifs.iconFor(notification)
    readonly property var actions: Notifs.buttons(notification)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            Layout.alignment: Qt.AlignVCenter
            radius: 19
            color: Theme.surface
            clip: true

            // the icon the application sends; the bell is the last
            // resort
            Image {
                anchors.fill: parent
                anchors.margins: 6
                source: view.icon
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 76
                sourceSize.height: 76
                visible: status === Image.Ready
            }

            IconGlyph {
                anchors.centerIn: parent
                visible: view.icon.length === 0
                text: Theme.ico.bell
                color: Theme.ink
                font.pixelSize: 17
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 6

                IslandLabel {
                    //  No breaks: the title is ONE line, and one with
                    //  `\n` inside pushed the whole band down.
                    text: view.notification
                        ? view.notification.summary.replace(/\s*\n\s*/g, " ")
                        : "Notification"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }

                IslandLabel {
                    text: view.notification ? view.notification.appName : ""
                    color: Theme.muted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.maximumWidth: 90
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                //  The body's line breaks, to spaces: here there IS
                //  a line cap, but a body of three short lines spent
                //  the two on the break and left half the band empty
                //  with the important part out. Run together, the
                //  elide finishes it.
                text: view.notification
                    ? view.notification.body.replace(/\s*\n\s*/g, " ") : ""
                color: Theme.muted
                font.pixelSize: 11
                maximumLineCount: view.actions.length > 0 ? 1 : 2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }

            // Buttons the application sends. k4 declares
            // actionsSupported, so if they are not painted the user
            // can never press them.
            RowLayout {
                visible: view.actions.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6

                Repeater {
                    model: view.actions

                    delegate: Rectangle {
                        id: actionChip
                        required property var modelData
                        Layout.preferredWidth: Math.min(actionLabel.implicitWidth + 20, 150)
                        Layout.preferredHeight: 20
                        radius: 10
                        color: actionMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: actionLabel
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: actionChip.modelData.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Notifs.invokeAction(view.notification, actionChip.modelData)
                                Notifs.dismissToast()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        MediaButton {
            glyph: Theme.ico.close
            glyphSize: 14
            glyphColor: Theme.muted
            onActivated: Notifs.dismissToast()
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
