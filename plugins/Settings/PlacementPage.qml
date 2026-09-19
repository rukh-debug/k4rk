// Popup presentation settings. Stable IDs keep disclosure state across rebuilds.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: page
    property var expandedCards: ({})
    signal expansionChanged(var cards)
    signal collapseAllRequested()
    readonly property var surfaces: SurfaceRegistry.placeableSurfaces
    readonly property int expandedCount: surfaces.filter(function (surface) {
        return page.expandedCards[surface.id] === true
    }).length
    spacing: 10

    function setExpanded(id, expanded) {
        const next = Object.assign({}, expandedCards)
        if (expanded) next[id] = true
        else delete next[id]
        expansionChanged(next)
    }

    function expandAll(expanded) {
        const next = {}
        if (expanded)
            for (const surface of surfaces) next[surface.id] = true
        expansionChanged(next)
        if (!expanded) collapseAllRequested()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        IslandLabel {
            Layout.fillWidth: true
            text: page.surfaces.length + " popups"
            color: Theme.muted
            font.pixelSize: 11
        }
        K4.ActionButton {
            objectName: "popup-expand-all"
            text: "Expand all"
            enabled: page.expandedCount < page.surfaces.length
            onClicked: page.expandAll(true)
        }
        K4.ActionButton {
            objectName: "popup-collapse-all"
            text: "Collapse all"
            enabled: page.expandedCount > 0
            onClicked: page.expandAll(false)
        }
    }
    IslandLabel {
        Layout.fillWidth: true
        text: "Use Separate popup to keep other views open. Expand a row to adjust its size and position."
        color: Theme.muted
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        Layout.bottomMargin: 4
    }
    Repeater {
        model: page.surfaces
        PopupCard {
            required property var modelData
            Layout.fillWidth: true
            surfaceInfo: modelData
            expanded: page.expandedCards[modelData.id] === true
            onExpansionRequested: function (expanded) { page.setExpanded(modelData.id, expanded) }
        }
    }
}
