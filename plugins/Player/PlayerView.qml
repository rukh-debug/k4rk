import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var panel: null
    property var tray: null

    //  Whoever opened it and in which mode. The plugin passes it in
    //  —the host injects nothing— and out of it comes the only
    //  question this view asks: whether this is a PEEK, shown and
    //  gone, or the whole player.
    property var plugin: null

    //  Peeking: cover, title and artist, and nothing else. What is
    //  below —the timeline, the transport, the recent
    //  notifications— is for when you come to use it, not to learn
    //  the song changed. A thirty-second video deserves no half
    //  island.
    readonly property bool asomo: !!(view.plugin && view.plugin.asomando)

    readonly property var player: Media.activePlayer
    readonly property real progress: player && player.length > 0
        ? Math.max(0, Math.min(1, player.position / player.length))
        : 0

    // MPRIS does not notify position: it is polled only while this
    // view exists
    Component.onCompleted: Media.watchPosition()
    Component.onDestruction: Media.unwatchPosition()

    // ── the peek: the pill, telling what plays ────────────────────
    //
    //  Pill height and a single line. The whole player is for when
    //  you come to use it; learning the song changed deserves no
    //  half island, and less so every thirty seconds with any
    //  video.
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 8
        visible: view.asomo

        Artwork {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: view.player && view.player.trackTitle.length > 0
                ? view.player.trackTitle : "Nothing playing"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        //  The artist only if it fits comfortably: on one line, a
        //  long title and a long artist end up two clips and neither
        //  reads.
        IslandLabel {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 96
            visible: text.length > 0
            text: view.player && view.player.trackArtist.length > 0
                ? view.player.trackArtist : ""
            color: Theme.muted
            font.pixelSize: 11
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Visualizer {
            Layout.alignment: Qt.AlignVCenter
        }
    }

    ColumnLayout {
        visible: !view.asomo
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 13

        // ── the track
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 44
            spacing: 11

            Artwork {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                IslandLabel {
                    Layout.fillWidth: true
                    text: view.player && view.player.trackTitle.length > 0
                        ? view.player.trackTitle
                        : "Nothing playing"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: view.player && view.player.trackArtist.length > 0
                        ? view.player.trackArtist
                        : (view.player ? view.player.identity : "")
                    color: Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 4
            }

            // With music playing, the island opening on hover is
            // this one and not the clock's: whatever is not
            // clickable here has no other way to be touched with
            // the mouse.
            Minimizados {
                interactive: true
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
            }

            PluginPildora {
                interactive: true
                Layout.leftMargin: 2
                Layout.alignment: Qt.AlignVCenter
            }

            // Same as in the clock: it is here, with the island
            // already unfolded, where tray icons can be clicked.
            TrayRow {
                max: 4
                iconSize: 16
                interactive: true
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
                onMenuRequested: if (view.tray) view.tray.toggle()
            }
        }

        // ── the timeline
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 12
            spacing: 8
            //  Both conditions in ONE: it already carried its own,
            //  and QML admits `visible` twice —«Property value set
            //  multiple times», and the whole plugin fails to
            //  load—.
            visible: Media.hasTimeline

            IslandLabel {
                text: view.player ? Media.formatTime(view.player.position) : "0:00"
                color: Theme.muted
                font.pixelSize: 10
                Layout.preferredWidth: 28
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 12
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: seekMouse.containsMouse ? 6 : 4
                    radius: height / 2
                    color: Theme.track

                    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Rectangle {
                        width: seekTrack.width * view.progress
                        height: parent.height
                        radius: parent.radius
                        color: Theme.ink

                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    id: seekMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (mouse) { Media.seekTo(mouse.x / width) }
                }
            }

            IslandLabel {
                text: view.player && view.player.length > 0
                    ? "-" + Media.formatTime(view.player.length - view.player.position)
                    : "0:00"
                color: Theme.muted
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 32
            }
        }

        // ── transporte
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 0

            MediaButton {
                glyph: Theme.ico.shuffle
                glyphSize: 14
                glyphColor: view.player && view.player.shuffle ? Theme.ink : Theme.muted
                enabledAction: !!view.player && view.player.shuffleSupported
                onActivated: view.player.shuffle = !view.player.shuffle
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.prev
                glyphSize: 20
                enabledAction: !!view.player && view.player.canGoPrevious
                onActivated: view.player.previous()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Media.isPlaying ? Theme.ico.pause : Theme.ico.play
                glyphSize: 24
                enabledAction: !!view.player && view.player.canTogglePlaying
                onActivated: view.player.togglePlaying()
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.next
                glyphSize: 20
                enabledAction: !!view.player && view.player.canGoNext
                onActivated: view.player.next()
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.output
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: if (view.panel) view.panel.toggle()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // What just arrived, also with music playing.
        NotifStrip {
            max: 3
            Layout.fillWidth: true
            Layout.topMargin: 2
        }
    }
}
