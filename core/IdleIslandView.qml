// The folded pill as one ordered row of native blocks.
//
// Left capsule extensions stay on the left flank, the enabled native blocks
// follow in Settings.pillEffectiveOrder, and right extensions close the row.
// A block preference says whether it may appear; runtime data says whether
// it currently has anything to show. Nothing here is clickable: hover swaps
// the island to the clock or player view before the pointer can land.

import QtQuick
import QtQuick.Layouts
import "../services"
import "../widgets"

FadeIn {
    id: view

    property var plugin: null
    property int shown: 0

    property bool mostrandoEscritorios: false
    readonly property var escritoriosVisibles: Workspaces.shownList
    property bool arrancado: false

    Component.onCompleted: arranque.start()

    Timer {
        id: arranque
        interval: 700
        onTriggered: view.arrancado = true
    }

    Connections {
        target: Workspaces
        function onActivoChanged() {
            if (!view.arrancado)
                return
            view.mostrandoEscritorios = true
            volver.restart()
        }
    }

    Timer {
        id: volver
        interval: 1800
        onTriggered: view.mostrandoEscritorios = false
    }

    onMostrandoEscritoriosChanged: if (plugin)
        plugin.centroAncho = mostrandoEscritorios
            ? Math.max(46, Math.ceil(deskMetrics.implicitWidth)) : 46

    // Hidden measuring row for the workspace parade width. The visible
    // delegate reads plugin.centroAncho so the pill lends the parade its
    // room only while it shows.
    Item {
        id: deskMetrics
        visible: false
        implicitWidth: deskRowHidden.implicitWidth
        RowLayout {
            id: deskRowHidden
            spacing: 4
            Repeater {
                model: view.escritoriosVisibles
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool numeros:
                        Settings.panelWorkspaceStyle === "numbers"
                    Layout.preferredWidth: numeros ? 26
                        : (modelData.focused ? 18 : 6)
                    Layout.preferredHeight: numeros ? 16 : 6
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11

        RowLayout {
            id: contentRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            spacing: 11

            onImplicitWidthChanged: if (view.plugin)
                view.plugin.contenidoMedido = Math.ceil(implicitWidth)
            Component.onCompleted: if (view.plugin)
                view.plugin.contenidoMedido = Math.ceil(implicitWidth)

            ExtensionZone {
                side: "left"
                Layout.alignment: Qt.AlignVCenter
            }

            Repeater {
                model: Settings.pillEffectiveOrder
                delegate: Loader {
                    required property var modelData
                    Layout.alignment: Qt.AlignVCenter
                    active: Settings.pillItemEnabled(modelData)
                    visible: active && item && item.tieneContenido
                    sourceComponent: modelData === "media" ? mediaBlock
                        : modelData === "clock-workspaces" ? centroBlock
                        : modelData === "minimized" ? minimizadosBlock
                        : modelData === "plugin-indicators" ? indicadoresBlock
                        : modelData === "tray" ? bandejaBlock : null
                }
            }

            ExtensionZone {
                side: "right"
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Component {
        id: mediaBlock
        RowLayout {
            spacing: 8
            readonly property bool tieneContenido: Media.isPlaying
            visible: tieneContenido
            Artwork {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
            }
            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 12
            }
        }
    }

    Component {
        id: centroBlock
        Item {
            id: centro
            readonly property bool tieneContenido: true
            implicitWidth: view.mostrandoEscritorios
                ? Math.max(46, deskRow.implicitWidth) : 46
            implicitHeight: 20
            Behavior on implicitWidth {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            IslandLabel {
                anchors.centerIn: parent
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Media.hasPlayer ? Theme.ink : Theme.muted
                opacity: view.mostrandoEscritorios ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            RowLayout {
                id: deskRow
                anchors.centerIn: parent
                spacing: 4
                opacity: view.mostrandoEscritorios ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                onImplicitWidthChanged: if (view.plugin && view.mostrandoEscritorios)
                    view.plugin.centroAncho = Math.max(46, Math.ceil(implicitWidth))
                readonly property real bubbleWidth: {
                    let w = 0
                    for (let i = 0; i < Workspaces.shownList.length; ++i) {
                        const texto = Workspaces.label(Workspaces.shownList[i])
                        w = Math.max(w, numberMetric.advanceWidth(texto),
                                        focusMetric.advanceWidth(texto))
                    }
                    return Math.max(16, w + 10)
                }
                FontMetrics {
                    id: numberMetric
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
                FontMetrics {
                    id: focusMetric
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: view.escritoriosVisibles
                    delegate: Rectangle {
                        id: sitio
                        required property var modelData
                        readonly property bool numeros:
                            Settings.panelWorkspaceStyle === "numbers"
                        Layout.preferredWidth: numeros
                            ? deskRow.bubbleWidth
                            : (modelData.focused ? 18 : 6)
                        Layout.preferredHeight: numeros ? 16 : 6
                        Layout.alignment: Qt.AlignVCenter
                        radius: numeros ? 8 : 3
                        color: modelData.focused
                            ? Theme.ink : (numeros ? "transparent" : Theme.track)
                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        IslandLabel {
                            anchors.centerIn: parent
                            visible: sitio.numeros
                            text: Workspaces.label(sitio.modelData)
                            color: sitio.modelData.focused
                                ? Theme.islandBg : Theme.muted
                            font.pixelSize: 10
                            font.weight: sitio.modelData.focused
                                ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }
    }

    Component {
        id: minimizadosBlock
        Item {
            readonly property bool tieneContenido: Modulos.count > 0
            visible: tieneContenido
            implicitWidth: minis.implicitWidth
            implicitHeight: 20
            Minimizados {
                id: minis
                anchors.centerIn: parent
            }
        }
    }

    Component {
        id: indicadoresBlock
        Item {
            readonly property bool tieneContenido: Indicadores.anchoAproximado > 0
            visible: tieneContenido
            implicitWidth: pildora.implicitWidth
            implicitHeight: 20
            PluginPildora {
                id: pildora
                anchors.centerIn: parent
            }
        }
    }

    Component {
        id: bandejaBlock
        Item {
            readonly property bool tieneContenido: Tray.count > 0
            visible: tieneContenido
            implicitWidth: fila.implicitWidth
            implicitHeight: 20
            TrayRow {
                id: fila
                anchors.centerIn: parent
                visible: true
                max: view.shown
                iconSize: 14
                interactive: false
            }
        }
    }
}
