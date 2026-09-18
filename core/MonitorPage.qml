import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../services"

ColumnLayout {
    id: page
    spacing: 12
    property string selectedName: ""
    property bool snap: true
    readonly property var selected: Monitors.draft.find(o => o.name === selectedName) || Monitors.draft[0] || null
    readonly property var resolutions: selected ? Array.from(new Set(selected.modes.map(m => m.split("@")[0]))) : []
    readonly property string resolution: selected ? selected.mode.split("@")[0] : ""
    readonly property var rates: selected ? selected.modes.filter(m => m.split("@")[0] === resolution) : []
    readonly property var orientationNames: ["Landscape", "Portrait left", "Inverted", "Portrait right", "Flipped", "Flipped portrait left", "Flipped inverted", "Flipped portrait right"]
    readonly property var scales: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3].filter(s => {
        const size = resolution.split("x").map(Number)
        return size.length === 2 && size.every(v => Math.abs(v / s - Math.round(v / s)) < 0.001)
    })

    Component.onCompleted: { Monitors.viewers++; Monitors.refresh() }
    Component.onDestruction: Monitors.viewers--
    function size(output) {
        const mode = output.mode.split("@")[0].split("x").map(Number)
        let w = mode[0] || output.width || 1920
        let h = mode[1] || output.height || 1080
        if (output.transform % 2) { const tmp = w; w = h; h = tmp }
        return { w: w / output.scale, h: h / output.scale }
    }
    function bounds() {
        const list = Monitors.draft.filter(o => o.enabled && !o.mirror)
        if (!list.length) return { x: 0, y: 0, w: 1920, h: 1080 }
        const x = Math.min.apply(null, list.map(o => o.x))
        const y = Math.min.apply(null, list.map(o => o.y))
        return { x: x, y: y, w: Math.max.apply(null, list.map(o => o.x + size(o).w)) - x,
                 h: Math.max.apply(null, list.map(o => o.y + size(o).h)) - y }
    }
    function position(name, x, y) {
        const output = Monitors.draft.find(o => o.name === name)
        if (snap && output) {
            const own = size(output)
            for (const other of Monitors.draft) {
                if (other.name === name || !other.enabled || other.mirror) continue
                const dim = size(other)
                for (const edge of [other.x, other.x + dim.w, other.x - own.w])
                    if (Math.abs(x - edge) < 60) x = edge
                for (const edge of [other.y, other.y + dim.h, other.y - own.h])
                    if (Math.abs(y - edge) < 60) y = edge
            }
        }
        Monitors.change(name, "x", Math.round(x))
        Monitors.change(name, "y", Math.round(y))
    }

    RowLayout {
        Layout.fillWidth: true
        IslandLabel {
            Layout.fillWidth: true
            text: Monitors.persistent ? "Confirmed changes are saved by k4" : "Session only · enable programs.k4.monitors.enable for persistence"
            color: Theme.muted
            wrapMode: Text.WordWrap
        }
        K4.ActionButton { text: "Identify"; onClicked: Monitors.identify() }
        K4.ActionButton { text: "Refresh"; enabled: !Monitors.busy; onClicked: Monitors.refresh() }
    }
    Rectangle {
        id: canvas
        Layout.fillWidth: true
        Layout.preferredHeight: 230
        radius: 12
        color: Theme.surface
        clip: true
        readonly property var area: page.bounds()
        readonly property real factor: Math.min((width - 64) / area.w, (height - 48) / area.h)
        readonly property real originX: (width - area.w * factor) / 2
        readonly property real originY: (height - area.h * factor) / 2
        Repeater {
            model: Monitors.draft
            delegate: Rectangle {
                id: tile
                required property var modelData
                visible: modelData.enabled && !modelData.mirror
                x: canvas.originX + (modelData.x - canvas.area.x) * canvas.factor
                y: canvas.originY + (modelData.y - canvas.area.y) * canvas.factor
                width: page.size(modelData).w * canvas.factor
                height: page.size(modelData).h * canvas.factor
                radius: 6
                color: page.selected && page.selected.name === modelData.name ? Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.25) : Theme.surfaceHi
                border.width: 2
                border.color: page.selected && page.selected.name === modelData.name ? Theme.blue : Theme.track
                activeFocusOnTab: true
                Accessible.name: modelData.name + ", drag or use arrow keys to arrange"
                Accessible.role: Accessible.Button
                Keys.onPressed: function (event) {
                    let dx = 0, dy = 0
                    if (event.key === Qt.Key_Left) dx = -1
                    else if (event.key === Qt.Key_Right) dx = 1
                    else if (event.key === Qt.Key_Up) dy = -1
                    else if (event.key === Qt.Key_Down) dy = 1
                    else return
                    const step = event.modifiers & Qt.ShiftModifier ? 10 : 1
                    Monitors.change(modelData.name, "x", modelData.x + dx * step)
                    Monitors.change(modelData.name, "y", modelData.y + dy * step)
                    event.accepted = true
                }
                IslandLabel {
                    anchors.fill: parent
                    anchors.margins: 8
                    text: tile.modelData.name + "\n" + tile.modelData.mode.split("@")[0]
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !Monitors.busy
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: tile
                    drag.threshold: 5
                    property real startX: 0
                    property real startY: 0
                    property real startFactor: 1
                    onPressed: {
                        page.selectedName = tile.modelData.name
                        tile.forceActiveFocus()
                        startX = tile.x; startY = tile.y; startFactor = canvas.factor
                    }
                    onReleased: page.position(tile.modelData.name,
                        tile.modelData.x + (tile.x - startX) / startFactor,
                        tile.modelData.y + (tile.y - startY) / startFactor)
                }
            }
        }
        IslandLabel {
            anchors.centerIn: parent
            visible: Monitors.outputs.length === 0
            text: "Waiting for Hyprland monitors…"
            color: Theme.muted
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: Monitors.draft
            delegate: K4.ActionButton {
                required property var modelData
                text: modelData.name + (!modelData.enabled ? " · disabled" : modelData.mirror ? " · mirror" : "")
                selected: page.selected && page.selected.name === modelData.name
                onClicked: page.selectedName = modelData.name
            }
        }
        K4.ActionButton { text: page.snap ? "Snap edges: on" : "Snap edges: off"; onClicked: page.snap = !page.snap }
        K4.ActionButton {
            text: "Arrange in a row"
            enabled: !Monitors.busy
            onClicked: {
                let x = 0
                for (const output of Monitors.draft) {
                    if (!output.enabled || output.mirror) continue
                    Monitors.change(output.name, "x", Math.round(x))
                    Monitors.change(output.name, "y", 0)
                    x += page.size(output).w
                }
            }
        }
    }
    IslandLabel {
        Layout.fillWidth: true
        text: page.selected ? page.selected.description : "No connected monitors"
        wrapMode: Text.WordWrap
        font.weight: Font.DemiBold
    }
    GridLayout {
        visible: page.selected !== null
        enabled: !Monitors.busy
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 18
        rowSpacing: 8
        IslandLabel { text: "Output" }
        K4.ActionButton {
            text: page.selected && page.selected.enabled ? "Enabled" : "Disabled"
            selected: page.selected ? page.selected.enabled : false
            onClicked: Monitors.change(page.selected.name, "enabled", !page.selected.enabled)
        }
        IslandLabel { text: "Resolution" }
        MonitorChoice {
            Layout.fillWidth: true
            model: page.resolutions
            currentIndex: page.resolutions.indexOf(page.resolution)
            onActivated: {
                const mode = page.selected.modes.find(m => m.split("@")[0] === page.resolutions[currentIndex])
                Monitors.change(page.selected.name, "mode", mode)
            }
        }
        IslandLabel { text: "Refresh rate" }
        MonitorChoice {
            Layout.fillWidth: true
            model: page.rates.map(m => m.split("@")[1] + " Hz")
            currentIndex: page.selected ? page.rates.indexOf(page.selected.mode) : -1
            onActivated: Monitors.change(page.selected.name, "mode", page.rates[currentIndex])
        }
        IslandLabel { text: "Scale" }
        RowLayout {
            Layout.fillWidth: true
            MonitorChoice {
                Layout.fillWidth: true
                model: page.scales.map(s => Math.round(s * 100) + "%")
                currentIndex: page.selected ? page.scales.indexOf(page.selected.scale) : -1
                onActivated: Monitors.change(page.selected.name, "scale", page.scales[currentIndex])
            }
            K4.TextField {
                Layout.preferredWidth: 90
                text: page.selected ? String(Math.round(page.selected.scale * 10000) / 100) : "100"
                Accessible.name: "Custom scale percent"
                validator: DoubleValidator { bottom: 25; top: 800; locale: "C" }
                onEditingFinished: if (acceptableInput && page.selected) Monitors.change(page.selected.name, "scale", Number(text) / 100)
            }
            IslandLabel { text: "%" }
        }
        IslandLabel { text: "Orientation" }
        MonitorChoice {
            Layout.fillWidth: true
            model: page.orientationNames
            currentIndex: page.selected ? page.selected.transform : 0
            onActivated: Monitors.change(page.selected.name, "transform", currentIndex)
        }
        IslandLabel { text: "Display mode" }
        MonitorChoice {
            Layout.fillWidth: true
            readonly property var sources: Monitors.draft.filter(o => o.enabled && !o.mirror && page.selected && o.name !== page.selected.name).map(o => o.name)
            model: ["Extend desktop"].concat(sources.map(n => "Mirror " + n))
            currentIndex: page.selected && page.selected.mirror ? sources.indexOf(page.selected.mirror) + 1 : 0
            onActivated: Monitors.change(page.selected.name, "mirror", currentIndex === 0 ? "" : sources[currentIndex - 1])
        }
        IslandLabel { text: "Position" }
        RowLayout {
            Layout.fillWidth: true
            IslandLabel { text: "X" }
            K4.TextField {
                Layout.fillWidth: true
                text: page.selected ? String(page.selected.x) : "0"
                Accessible.name: "Horizontal monitor position"
                validator: IntValidator { bottom: -100000; top: 100000 }
                onEditingFinished: if (acceptableInput && page.selected) Monitors.change(page.selected.name, "x", Number(text))
            }
            IslandLabel { text: "Y" }
            K4.TextField {
                Layout.fillWidth: true
                text: page.selected ? String(page.selected.y) : "0"
                Accessible.name: "Vertical monitor position"
                validator: IntValidator { bottom: -100000; top: 100000 }
                onEditingFinished: if (acceptableInput && page.selected) Monitors.change(page.selected.name, "y", Number(text))
            }
        }
    }
    IslandLabel {
        Layout.fillWidth: true
        visible: Monitors.conflict || Monitors.error.length > 0
        text: Monitors.conflict ? "The layout changed externally. Discard your edits to use the current layout." : Monitors.error
        color: Theme.blue
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        IslandLabel {
            Layout.fillWidth: true
            text: Monitors.busy ? "Monitor preview: " + Monitors.transaction.state
                  : Monitors.dirty ? "Unapplied changes" : "Current monitor layout"
            color: Theme.muted
        }
        K4.ActionButton { text: "Discard"; enabled: Monitors.dirty && !Monitors.busy; onClicked: Monitors.discard() }
        K4.ActionButton { text: "Apply"; selected: true; enabled: Monitors.dirty && !Monitors.busy && !Monitors.conflict; onClicked: Monitors.apply() }
    }
}
