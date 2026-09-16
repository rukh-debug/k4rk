// Pinned applications keep useful cell widths; overflow scrolls beside All apps.
import QtQuick
import K4 as K4
import "../../core"
import "../../services"

Item {
    id: strip
    signal abrir(string id)
    readonly property int altura: 40
    readonly property bool dragging: dragIndex >= 0
    readonly property var available: {
        const apps = PluginManager.aplicaciones
        return (Settings.quickAccess || []).map(function (id) {
            return apps.find(function (app) {
                return app.id === id && app.habilitado && app.disponible
            })
        }).filter(function (app) { return !!app })
    }
    readonly property bool overflow: available.length * 120 > Math.max(0, width - 104)
    readonly property real cellWidth: available.length > 0
        ? Math.max(112, (viewport.width - 8 * (available.length - 1)) / available.length) : 112
    property int dragIndex: -1
    property int targetIndex: -1
    property string focusedId: ""

    function slot(index) {
        if (dragIndex < 0 || targetIndex < 0) return index
        if (index === dragIndex) return targetIndex
        if (dragIndex < targetIndex && index > dragIndex && index <= targetIndex) return index - 1
        if (dragIndex > targetIndex && index >= targetIndex && index < dragIndex) return index + 1
        return index
    }
    function move(from, to) {
        if (from < 0 || to < 0 || to >= available.length || from === to) return
        const ids = available.map(function (app) { return app.id })
        focusedId = ids[from]
        ids.splice(to, 0, ids.splice(from, 1)[0])
        Settings.quickAccess = ids.concat((Settings.quickAccess || []).filter(function (id) {
            return ids.indexOf(id) < 0
        }))
        Settings.guardar()
        Qt.callLater(function () {
            for (let i = 0; i < cells.count; ++i) {
                const cell = cells.itemAt(i)
                if (cell && cell.modelData.id === strip.focusedId) cell.forceActiveFocus()
            }
        })
    }
    function scroll(delta) {
        viewport.contentX = Math.max(0, Math.min(Math.max(0, viewport.contentWidth - viewport.width),
            viewport.contentX + delta))
    }

    K4.Boton {
        visible: strip.overflow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        glifo: Theme.ico.back
        tamano: 16
        activo: viewport.contentX > 0
        Accessible.name: "Previous shortcuts"
        onPulsado: strip.scroll(-strip.cellWidth - 8)
    }
    IslandLabel {
        visible: strip.available.length === 0
        anchors.left: parent.left
        anchors.right: viewport.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Pin applications from All apps"
        color: Theme.muted
        font.pixelSize: 11
        elide: Text.ElideRight
    }
    Flickable {
        id: viewport
        x: strip.overflow ? 32 : 0
        width: Math.max(0, strip.width - 104 - (strip.overflow ? 64 : 0))
        height: strip.altura
        contentWidth: strip.available.length * (strip.cellWidth + 8) - (strip.available.length ? 8 : 0)
        contentHeight: height
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        Repeater {
            id: cells
            model: strip.available
            delegate: K4.Baldosa {
                id: cell
                required property var modelData
                required property int index
                property real dragX: 0
                x: strip.dragIndex === index ? dragX : strip.slot(index) * (strip.cellWidth + 8)
                width: strip.cellWidth
                height: strip.altura
                radius: 10
                pulsable: false
                activa: pointer.containsMouse || strip.dragIndex === index
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.nombre
                Accessible.description: "Open application. Use Control and Left or Right to reorder."
                Keys.onReturnPressed: strip.abrir(modelData.id)
                Keys.onSpacePressed: strip.abrir(modelData.id)
                Keys.onPressed: function (event) {
                    if (!(event.modifiers & Qt.ControlModifier)) return
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                        strip.move(index, index + (event.key === Qt.Key_Right ? 1 : -1))
                        event.accepted = true
                    }
                }
                onActiveFocusChanged: if (activeFocus) {
                    if (x < viewport.contentX) strip.scroll(x - viewport.contentX)
                    else if (x + width > viewport.contentX + viewport.width)
                        strip.scroll(x + width - viewport.width - viewport.contentX)
                }
                Behavior on x {
                    enabled: strip.dragIndex !== cell.index
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                K4.IconoPlugin {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    imagen: cell.modelData.imagen
                    glifo: cell.modelData.glifo
                    tamano: 16
                }
                IslandLabel {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 36
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.modelData.nombre
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    property real startX: 0
                    property bool moved: false
                    onPressed: function (event) {
                        cell.forceActiveFocus(Qt.MouseFocusReason)
                        startX = event.x
                        moved = false
                        cell.dragX = cell.x
                        strip.dragIndex = cell.index
                        strip.targetIndex = cell.index
                    }
                    onPositionChanged: function (event) {
                        if (!pressed || strip.dragIndex !== cell.index) return
                        if (!moved && Math.abs(event.x - startX) < 6) return
                        moved = true
                        cell.dragX = Math.max(0, Math.min(viewport.contentWidth - cell.width,
                            cell.dragX + event.x - startX))
                        strip.targetIndex = Math.max(0, Math.min(strip.available.length - 1,
                            Math.round(cell.dragX / (strip.cellWidth + 8))))
                    }
                    onReleased: {
                        const from = strip.dragIndex, to = strip.targetIndex
                        const id = cell.modelData.id, reorder = moved
                        strip.dragIndex = -1
                        strip.targetIndex = -1
                        if (reorder) strip.move(from, to)
                        else strip.abrir(id)
                    }
                    onCanceled: { strip.dragIndex = -1; strip.targetIndex = -1 }
                    onWheel: function (event) {
                        if (strip.overflow) strip.scroll(-event.angleDelta.y / 120 * 120)
                        else event.accepted = false
                    }
                }
            }
        }
    }
    K4.Boton {
        visible: strip.overflow
        x: viewport.x + viewport.width
        anchors.verticalCenter: parent.verticalCenter
        glifo: Theme.ico.forward
        tamano: 16
        activo: viewport.contentX < viewport.contentWidth - viewport.width
        Accessible.name: "More shortcuts"
        onPulsado: strip.scroll(strip.cellWidth + 8)
    }
    K4.ActionButton {
        anchors.right: parent.right
        width: 96
        height: strip.altura
        text: "All apps"
        onClicked: strip.abrir("apps")
    }
}
