// Wallpaper collection with one page-owned scroll, staged previews and honest status.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../core"
import "../services"

ColumnLayout {
    id: grid
    property var motor: WallpaperPalette
    property bool fitContent: false
    property int thumbnailsReady: 8
    Layout.fillWidth: true
    spacing: 12

    function requestList() {
        if (Fondos.lista.length === 0 && !Fondos.rastreando) Fondos.rastrear()
    }
    Component.onCompleted: if (visible) requestList()
    onVisibleChanged: if (visible) requestList()
    Timer {
        interval: 100
        repeat: true
        running: grid.visible && grid.thumbnailsReady < Fondos.lista.length
        onTriggered: grid.thumbnailsReady += 8
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        IslandLabel {
            Layout.fillWidth: true
            text: Fondos.rastreando ? "Scanning wallpapers…" : Fondos.lista.length + " wallpapers · all displays"
            color: Theme.muted
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        K4.ActionButton { text: "Add…"; enabled: !!grid.motor; onClicked: grid.motor.elegirFondo() }
        K4.Boton {
            glifo: Theme.ico.loading
            tamano: 16
            activo: !Fondos.rastreando
            Accessible.name: "Refresh wallpaper collection"
            onPulsado: Fondos.rastrear()
        }
    }
    IslandLabel { text: "Transition"; color: Theme.muted; font.pixelSize: 12; font.weight: Font.Medium }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        enabled: !!grid.motor && grid.motor.supportsTransitions
        Repeater {
            model: grid.motor ? grid.motor.transiciones : []
            delegate: K4.ActionButton {
                required property var modelData
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                selected: !!grid.motor && grid.motor.transicion === modelData
                Accessible.name: "Wallpaper transition: " + text
                onClicked: grid.motor.transicion = modelData
            }
        }
    }
    IslandLabel {
        visible: !!grid.motor && !grid.motor.supportsTransitions
        Layout.fillWidth: true
        text: "Transitions are available for images with awww or swww."
        color: Theme.muted
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    Grid {
        id: thumbnails
        Layout.fillWidth: true
        columns: Math.max(2, Math.floor(width / 160))
        spacing: 8
        Repeater {
            model: Fondos.lista
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property string name: modelData.substring(modelData.lastIndexOf("/") + 1)
                readonly property bool selected: !!grid.motor && grid.motor.wallpaper === modelData
                readonly property bool removable: Fondos.extras.indexOf(modelData) >= 0
                width: Math.max(0, (thumbnails.width - thumbnails.spacing * (thumbnails.columns - 1)) / thumbnails.columns)
                height: Math.round(width * 0.625)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Use wallpaper " + name
                Keys.onReturnPressed: if (grid.motor) grid.motor.ponerEnElegida(modelData)
                Keys.onSpacePressed: if (grid.motor) grid.motor.ponerEnElegida(modelData)
                ToolTip.visible: pointer.containsMouse
                ToolTip.delay: 700
                ToolTip.text: name
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.surface
                    clip: true
                    Image {
                        id: thumbnail
                        anchors.fill: parent
                        anchors.margins: 2
                        source: cell.index < grid.thumbnailsReady ? "file://" + Fondos.miniaturaDe(cell.modelData) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 320
                        sourceSize.height: 200
                        autoTransform: true
                    }
                    IconGlyph {
                        anchors.centerIn: parent
                        visible: thumbnail.status !== Image.Ready
                        text: Theme.ico.wallpaper
                        font.pixelSize: 24
                        color: Theme.muted
                    }
                    MouseArea {
                        id: pointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            cell.forceActiveFocus(Qt.MouseFocusReason)
                            if (grid.motor) grid.motor.ponerEnElegida(cell.modelData)
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 26
                        color: "#cc000000"
                        visible: pointer.containsMouse || cell.activeFocus || remove.activeFocus || cell.selected
                        IslandLabel {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: cell.name
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    K4.Boton {
                        id: remove
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 4
                        visible: cell.removable
                        glifo: Theme.ico.close
                        tamano: 16
                        Accessible.name: "Remove " + cell.name + " from collection"
                        onPulsado: if (grid.motor) grid.motor.quitarFondo(cell.modelData)
                        Rectangle { z: -1; anchors.fill: parent; radius: 8; color: "#cc000000" }
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 24
                        height: 24
                        radius: 12
                        color: cell.selected ? Theme.blue : "#cc000000"
                        visible: cell.selected || !Fondos.esQuieto(cell.modelData)
                        IconGlyph {
                            anchors.centerIn: parent
                            text: cell.selected ? Theme.ico.check : Theme.ico.play
                            font.pixelSize: 13
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "transparent"
                        border.width: cell.selected || cell.activeFocus ? 2 : 1
                        border.color: cell.selected || cell.activeFocus ? Theme.blue : Theme.track
                    }
                }
            }
        }
    }
    IslandLabel {
        visible: Fondos.lista.length === 0
        Layout.fillWidth: true
        topPadding: 24
        bottomPadding: 24
        text: Fondos.rastreando ? "Looking in your picture folders…" : "No wallpapers found. Add an image to start your collection."
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        IslandLabel {
            Layout.fillWidth: true
            text: !grid.motor ? "Wallpaper service unavailable"
                : grid.motor.applyStatus === "failed" ? grid.motor.applyError
                : grid.motor.applyStatus === "applying" ? "Applying wallpaper…"
                : grid.motor.applyStatus === "applied" ? "Wallpaper applied and selection saved"
                : grid.motor.applyStatus === "unverified" ? "Selection saved · wallpaper process started"
                : "Choose a wallpaper to apply it to all displays"
            color: grid.motor && grid.motor.applyStatus === "failed" ? Theme.red : Theme.muted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        K4.ActionButton {
            visible: !!grid.motor && grid.motor.applyStatus === "failed"
            text: "Retry"
            onClicked: grid.motor.apply()
        }
    }
}
