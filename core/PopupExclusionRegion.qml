import QtQuick
import Quickshell
import "../services"

// Cut independent cards out of an outside-click catcher, regardless of which
// layer surface the compositor currently stacks first.
Region {
    id: region
    property string screenName: ""
    property string exceptId: ""
    intersection: Intersection.Subtract

    property Instantiator holes: Instantiator {
        model: Object.keys(PopupLayout.placements)
        delegate: Region {
            required property string modelData
            readonly property var rect: PopupLayout.placements[modelData]
            readonly property bool included: !!rect && rect.screen === region.screenName
                && modelData !== region.exceptId
            x: included ? Math.floor(rect.x) : 0
            y: included ? Math.floor(rect.y) : 0
            width: included ? Math.ceil(rect.width) : 0
            height: included ? Math.ceil(rect.height) : 0
        }
        onObjectAdded: function (index, object) { region.regions.push(object) }
        onObjectRemoved: function (index, object) {
            const at = region.regions.indexOf(object)
            if (at >= 0)
                region.regions.splice(at, 1)
        }
    }
}
