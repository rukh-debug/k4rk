import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null

    //  What EACH zone truly measures, so the plugin knows how much
    //  to reserve. It is measured here because it is here the
    //  widgets sit with their font set: how much «🔔 claude · k4»
    //  takes is not known by counting constants, and counting them
    //  is how it was known —hence the agents' pills ending up
    //  painted over the time—.
    //
    //  All three and not just the right: with chained zones,
    //  whatever the date measures runs the clock, and whatever the
    //  clock measures runs the indicators.
    readonly property int anchoIzquierdo: grupoIzq.implicitWidth
    readonly property int anchoCentro: reloj.implicitWidth
    readonly property int anchoDerecho: grupoDer.implicitWidth

    //  The air between one zone and the next. The plugin lays out
    //  with this same number, so if it changes, it changes in both
    //  places or the count stops adding up and the overlap
    //  returns.
    readonly property int hueco: 24

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 0
        anchors.bottomMargin: Notifs.recent.length > 0 ? 12 : 0
        spacing: 6

        //  Three CHAINED zones, same as the folded pill: each starts
        //  where the previous one ends, and that is the whole rule.
        //
        //  They were anchored to their edge —date left, time at the
        //  box's center, indicators right—, and that forces what is
        //  reserved to match TO THE PIXEL what it truly measures.
        //  It did not match: the plugin bounded the right flank so
        //  the island would not eat the screen, and on passing that
        //  cap the row grew inward from the right edge and ended up
        //  painted over the time. It is exactly the failure already
        //  fixed in the pill, and the same cure: hanging from one
        //  another, overlap does not merely not happen, it does not
        //  fit. What does not fit spills right and the island clips
        //  it, which is the lesser of the two evils.
        //
        //  The price is the same as there: the time stops sitting at
        //  the box's exact center and stays wherever the date and
        //  its air leave it. In exchange every indicator pixel is
        //  worth one and not two, so now nearly twice the right
        //  flank fits before touching the cap.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 68

            ColumnLayout {
                id: grupoIzq
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Qt.locale(), "dddd")
                    color: Theme.muted
                    font.pixelSize: 11
                    font.capitalization: Font.Capitalize
                }

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Qt.locale(), "d MMMM")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            IslandLabel {
                id: reloj

                //  Hanging from the date, not centered in the box:
                //  the box no longer reserves the same on both sides,
                //  so its center is not where the time goes.
                anchors.left: grupoIzq.right
                anchors.leftMargin: view.hueco
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 30
                font.weight: Font.Light
            }

            RowLayout {
                id: grupoDer

                //  And the indicators hanging from the TIME, closing
                //  the chain.
                anchors.left: reloj.right
                anchors.leftMargin: view.hueco
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Minimizados {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                }

                PluginPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                }

                // The island is already unfolded and still: here
                // things can be clicked.
                TrayRow {
                    max: 5
                    iconSize: 16
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onMenuRequested: if (view.tray) view.tray.toggle()
                }
            }
        }

        // What just arrived, without having to open the panel.
        NotifStrip {
            max: 3
            Layout.fillWidth: true
        }
    }
}
