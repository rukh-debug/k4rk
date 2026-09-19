// Position controls and a proportional preview share one placement model.
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"
import "../../services/PopupPlacement.js" as Placement

ColumnLayout {
    id: editor
    required property var surface
    readonly property var placement: Settings.placementDe(surface.name)
    readonly property bool followsBar: !(Settings.islandPlacements || {})[surface.name]
    readonly property var sides: sidePair(placement)
    spacing: 10

    function sidePair(point) {
        const horizontal = point.side === "top" || point.side === "bottom"
        return {
            h: horizontal ? point.side : point.align <= 0.5 ? "top" : point.align >= 99.5 ? "bottom" : "",
            v: !horizontal ? point.side : point.align <= 0.5 ? "left" : point.align >= 99.5 ? "right" : ""
        }
    }

    function positionLabel() {
        const description = sides.h && sides.v ? sides.h + "-" + sides.v + " corner"
            : placement.side + " edge · " + Math.round(placement.align) + "%"
        return (followsBar ? "Follows bar · " : "") + description
    }

    function chooseSide(side) {
        if (!side) {
            Settings.ponerPlacement(surface.name, "", 50)
            return
        }
        const current = followsBar ? { h: "", v: "" } : sides
        const horizontal = side === "top" || side === "bottom"
        let h = current.h, v = current.v
        if (horizontal) h = h === side ? "" : side
        else v = v === side ? "" : side
        Settings.ponerPlacement(surface.name, h || v,
            h && v ? (v === "right" ? 100 : 0) : 50)
    }

    RowLayout {
        Layout.fillWidth: true
        IslandLabel { text: "Position"; font.weight: Font.DemiBold; Layout.fillWidth: true }
        K4.ActionButton {
            text: "Reset position"
            enabled: !editor.followsBar
            onClicked: editor.chooseSide("")
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 500 ? 2 : 1
        columnSpacing: 20
        rowSpacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            IslandLabel {
                Layout.fillWidth: true
                text: editor.positionLabel()
                color: Theme.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 6
                Repeater {
                    model: [
                        { side: "", label: "Follow bar" },
                        { side: "top", label: "Top" }, { side: "bottom", label: "Bottom" },
                        { side: "left", label: "Left" }, { side: "right", label: "Right" }
                    ]
                    K4.ActionButton {
                        required property var modelData
                        text: modelData.label
                        selected: modelData.side === "" ? editor.followsBar
                            : !editor.followsBar && (editor.sides.h === modelData.side || editor.sides.v === modelData.side)
                        Accessible.name: editor.surface.title + ": " + text
                        onClicked: editor.chooseSide(modelData.side)
                    }
                }
            }
            K4.Deslizador {
                Layout.fillWidth: true
                enabled: !editor.followsBar
                etiqueta: "Alignment"
                valor: editor.placement.align
                sufijo: "%"
                Accessible.name: editor.surface.title + ": alignment"
                onMovido: function (value) {
                    Settings.ponerPlacementMemoria(editor.surface.name, editor.placement.side, value)
                    if (!dragging) Settings.guardar()
                }
                onDraggingChanged: if (!dragging) Settings.guardar()
            }
        }
        ColumnLayout {
            Layout.preferredWidth: 200
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            spacing: 8
            Item {
                id: monitor
                objectName: "popup-position-preview-" + editor.surface.name
                Layout.fillWidth: true
                Layout.preferredHeight: width * screenHeight / screenWidth
                readonly property real screenWidth: Screen.width || 1920
                readonly property real screenHeight: Screen.height || 1080
                readonly property real scale: width / screenWidth
                readonly property var rect: Placement.rectangle(editor.placement,
                    Math.min(screenWidth, Settings.popupSizeFor(editor.surface, "width")),
                    Math.min(screenHeight, Settings.popupSizeFor(editor.surface, "height")),
                    screenWidth, screenHeight)

                function placementAt(x, y) {
                    const fx = Math.max(0, Math.min(1, x / width))
                    const fy = Math.max(0, Math.min(1, y / height))
                    if ((fx <= 0.2 || fx >= 0.8) && (fy <= 0.2 || fy >= 0.8))
                        return { side: fy <= 0.2 ? "top" : "bottom", align: fx <= 0.2 ? 0 : 100 }
                    const nearest = Math.min(y, height - y, x, width - x)
                    const side = nearest === y ? "top" : nearest === height - y ? "bottom"
                        : nearest === x ? "left" : "right"
                    const fraction = side === "top" || side === "bottom" ? fx : fy
                    return { side: side, align: fraction <= 0.08 ? 0 : fraction >= 0.92 ? 100 : Math.round(fraction * 100) }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Theme.islandBg
                    border.width: 1
                    border.color: Theme.track
                }
                Rectangle {
                    x: (parent.width - width) * Settings.barAlignment / 100
                    y: Settings.barPosition === "bottom" ? parent.height - height : 0
                    width: 30
                    height: 3
                    radius: 1.5
                    color: Theme.muted
                }
                Item {
                    x: monitor.rect.x * monitor.scale
                    y: monitor.rect.y * monitor.scale
                    width: Math.max(4, monitor.rect.width * monitor.scale)
                    height: Math.max(4, monitor.rect.height * monitor.scale)
                    EdgeAttachedShape {
                        anchors.fill: parent
                        attachTop: editor.sides.h === "top"
                        attachBottom: editor.sides.h === "bottom"
                        attachLeft: editor.sides.v === "left"
                        attachRight: editor.sides.v === "right"
                        cornerRadius: 5
                        rimThickness: 1
                        blendReach: 5
                        blendDepth: 2
                        fillColor: Theme.blue
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property var previousPlacement: null
                    function move(x, y) {
                        const next = monitor.placementAt(x, y)
                        Settings.ponerPlacementMemoria(editor.surface.name, next.side, next.align)
                    }
                    onPressed: function (mouse) {
                        previousPlacement = editor.followsBar ? null
                            : { side: editor.placement.side, align: editor.placement.align }
                        move(mouse.x, mouse.y)
                    }
                    onPositionChanged: function (mouse) { if (pressed) move(mouse.x, mouse.y) }
                    onReleased: Settings.guardar()
                    onCanceled: Settings.ponerPlacementMemoria(editor.surface.name,
                        previousPlacement ? previousPlacement.side : "", previousPlacement ? previousPlacement.align : 50)
                }
            }
            IslandLabel {
                Layout.fillWidth: true
                Layout.maximumWidth: 200
                text: "Drag to an edge or corner, or combine two adjacent sides."
                color: Theme.muted
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }
}
