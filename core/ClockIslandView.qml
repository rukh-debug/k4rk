// Native clock hover view: date, time, interactive indicators and tray,
// plus recent notifications. Hover-only; never intercepts outside clicks.

import QtQuick
import QtQuick.Layouts
import "../services"
import "../widgets"

FadeIn {
    id: view

    property var plugin: null

    readonly property int anchoIzquierdo: grupoIzq.implicitWidth
    readonly property int anchoCentro: reloj.implicitWidth
    readonly property int anchoDerecho: grupoDer.implicitWidth
    readonly property int hueco: 24

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 0
        anchors.bottomMargin: Notifs.recent.length > 0 ? 12 : 0
        spacing: 6

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
                anchors.left: grupoIzq.right
                anchors.leftMargin: view.hueco
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 30
                font.weight: Font.Light
            }

            RowLayout {
                id: grupoDer
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

                TrayRow {
                    iconSize: 16
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onMenuRequested: TrayIsland.toggle()
                }
            }
        }

        NotifStrip {
            max: 3
            Layout.fillWidth: true
        }
    }

    // Publish measurements to the native host for first-frame sizing.
    onAnchoIzquierdoChanged: if (plugin) plugin.anchoIzqMedido = Math.ceil(anchoIzquierdo)
    onAnchoCentroChanged: if (plugin) plugin.anchoCentroMedido = Math.ceil(anchoCentro)
    onAnchoDerechoChanged: if (plugin) plugin.anchoDerechoMedido = Math.ceil(anchoDerecho)
    Component.onCompleted: if (plugin) {
        plugin.anchoIzqMedido = Math.ceil(anchoIzquierdo)
        plugin.anchoCentroMedido = Math.ceil(anchoCentro)
        plugin.anchoDerechoMedido = Math.ceil(anchoDerecho)
    }
}
