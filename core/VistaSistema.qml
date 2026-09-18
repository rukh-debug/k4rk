// Shared by the control centre and the standalone System surface.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../services"

ColumnLayout {
    id: view
    spacing: 10
    property string sortKey: "cpu"
    readonly property bool narrow: width < 760
    readonly property var sortedProcesses: Sistema.procesos.slice().sort((a, b) =>
        b[sortKey] - a[sortKey] || a.pid - b.pid)
    function percent(value) { return value >= 0 ? Math.round(value) + "%" : "—" }
    function metric(id) {
        if (id === "cpu") return {
            label: "CPU", value: percent(Sistema.cpuUso),
            detail: Sistema.cpuTemp > 0 ? Sistema.grados(Sistema.cpuTemp) + " · " + Sistema.cpuHilos + " threads" : Sistema.cpuHilos + " logical CPUs",
            history: Sistema.cpuHist, note: "Busy time across all logical CPUs. I/O wait is excluded."
        }
        if (id === "memory") return {
            label: "Memory", value: percent(Sistema.ramPct),
            detail: Sistema.ramTotal > 0 ? Sistema.ramUsada.toFixed(1) + " / " + Sistema.ramTotal.toFixed(1) + " GiB" : "Measuring…",
            history: Sistema.ramHist, note: "Uses the kernel's available-memory estimate, including reclaimable cache.\nSwap: " + Sistema.swapUsada.toFixed(2) + " / " + Sistema.swapTotal.toFixed(1) + " GiB."
        }
        if (id === "gpu") return {
            label: "GPU", value: percent(Sistema.gpuUso),
            detail: (Sistema.gpuTemp > 0 ? Sistema.grados(Sistema.gpuTemp) + " · " : "")
                + (Sistema.gpuMemUsada >= 0 ? Math.round(Sistema.gpuMemUsada) + " MiB graphics memory" : Sistema.gpuNombre || "Telemetry unavailable"),
            history: Sistema.gpuHist, note: Sistema.gpuNombre ? Sistema.gpuNombre + "\n" + Sistema.gpuMemoryLabel + ": "
                + (Sistema.gpuMemUsada >= 0 ? Math.round(Sistema.gpuMemUsada) + " / "
                    + (Sistema.gpuMemTotal > 0 ? Math.round(Sistema.gpuMemTotal) : "—") + " MiB" : "unavailable")
                + "\nIntegrated graphics may also use shared system memory." : "No supported GPU counters were found."
        }
        return {
            label: "Network", value: "↓ " + Sistema.tasa(Sistema.redRx),
            detail: "↑ " + Sistema.tasa(Sistema.redTx), history: Sistema.redHist,
            note: Sistema.redIface ? "Interface: " + Sistema.redIface + "\nDefault-route interface traffic, not internet speed.\nGraph: combined download and upload; automatic scale."
                : "No default-route interface is available."
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        IslandLabel {
            Layout.fillWidth: true
            text: Sistema.cpuName
            font.pixelSize: 11; color: Theme.muted; elide: Text.ElideRight
        }
        IslandLabel {
            text: "Up " + Sistema.duration(Sistema.uptime)
            font.pixelSize: 11; color: Theme.muted
        }
    }

    GridLayout {
        objectName: "system-metrics"
        Layout.fillWidth: true
        columns: view.narrow ? 2 : 4
        columnSpacing: 10; rowSpacing: 10
        Repeater {
            model: ["cpu", "memory", "gpu", "network"]
            delegate: Rectangle {
                id: tile
                required property string modelData
                readonly property var reading: view.metric(modelData)
                objectName: "system-" + modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 108
                Layout.minimumHeight: 108
                radius: 12; color: Theme.surface
                activeFocusOnTab: true
                Accessible.role: Accessible.StaticText
                Accessible.name: reading.label + ": " + reading.value + ". " + reading.detail
                Accessible.description: reading.note
                border.width: activeFocus ? 1 : 0
                border.color: Theme.blue
                HoverHandler { id: metricHover }
                ToolTip.visible: metricHover.hovered || tile.activeFocus
                ToolTip.delay: 500
                ToolTip.text: reading.note
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12
                    spacing: 3
                    IslandLabel {
                        text: tile.reading.label; color: Theme.muted; font.pixelSize: 11
                    }
                    IslandLabel {
                        Layout.fillWidth: true
                        text: tile.reading.value
                        font.pixelSize: tile.modelData === "network" ? 20 : 24
                        font.weight: Font.DemiBold; elide: Text.ElideRight
                    }
                    IslandLabel {
                        Layout.fillWidth: true
                        text: tile.reading.detail; font.pixelSize: 11
                        color: Theme.muted; elide: Text.ElideRight
                    }
                    Grafica {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.minimumHeight: 12
                        valores: tile.reading.history
                        tono: Theme.blue
                        techo: tile.modelData === "network" ? 0 : 100
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: 48
        color: "transparent"
        HoverHandler { id: storageHover }
        ToolTip.visible: storageHover.hovered
        ToolTip.delay: 500
        ToolTip.text: Sistema.diskDevice + " · " + Sistema.diskFilesystem + " · mounted at " + Sistema.diskMount
            + "\nFilesystem containing " + Sistema.diskPath
            + "\n" + Sistema.discoTotal.toFixed(1) + " GiB total · " + Sistema.diskReserved.toFixed(1)
            + " GiB reserved / unavailable to this user.\nUsage percentage excludes reserved space, matching df."
        RowLayout {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            spacing: 12
            IslandLabel {
                text: "Storage"; font.pixelSize: 12; font.weight: Font.Medium
            }
            IslandLabel {
                Layout.fillWidth: true
                text: Sistema.discoPct >= 0 ? Sistema.diskMount + " · " + Sistema.discoUsado.toFixed(1) + " GiB used" : "Measuring…"
                color: Theme.muted; font.pixelSize: 11; elide: Text.ElideRight
            }
            IslandLabel {
                text: Sistema.discoPct >= 0 ? Sistema.diskAvailable.toFixed(1) + " GiB available · " + Math.ceil(Sistema.discoPct) + "%" : "—"
                color: Theme.muted; font.pixelSize: 11
            }
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; y: 28
            height: 3; radius: 2; color: Theme.surfaceHi
            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, Sistema.discoPct)) / 100
                height: parent.height; radius: 2
                color: Sistema.discoPct >= 95 ? Theme.yellow : Theme.muted
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        IslandLabel {
            text: "Processes"; font.pixelSize: 13; font.weight: Font.DemiBold
            Layout.fillWidth: true
        }
        IslandLabel {
            visible: processList.activeFocus || processHover.hovered
            text: "Order held"; color: Theme.muted; font.pixelSize: 10
        }
        K4.ActionButton {
            text: "CPU"; selected: view.sortKey === "cpu"
            Accessible.name: "Sort processes by CPU usage"
            onClicked: view.sortKey = "cpu"
        }
        K4.ActionButton {
            text: "Memory"; selected: view.sortKey === "ram"
            Accessible.name: "Sort processes by resident memory"
            onClicked: view.sortKey = "ram"
        }
    }

    RowLayout {
        Layout.fillWidth: true; Layout.leftMargin: 10; Layout.rightMargin: 10
        spacing: 12
        IslandLabel { text: "Name"; color: Theme.muted; font.pixelSize: 10; Layout.fillWidth: true }
        IslandLabel { text: "PID"; color: Theme.muted; font.pixelSize: 10; Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight }
        IslandLabel { text: "CPU"; color: Theme.muted; font.pixelSize: 10; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
        IslandLabel { text: "Resident"; color: Theme.muted; font.pixelSize: 10; Layout.preferredWidth: 85; horizontalAlignment: Text.AlignRight }
        Item { Layout.preferredWidth: 52 }
    }

    ListModel { id: processes }
    // Update by process identity: a sample should not destroy a focused action.
    function updateProcesses() {
        if (!processList || !processHover || !processes) return
        let rows = sortedProcesses
        // Keep targets still while a pointer or keyboard is inside the list.
        // Values remain live; sorting resumes as soon as the interaction ends.
        if (processList.activeFocus || processHover.hovered) {
            const previous = []
            for (let i = 0; i < processes.count; ++i) previous.push(processes.get(i).identity)
            rows = rows.slice().sort((a, b) => {
                const ai = previous.indexOf(a.pid + ":" + a.start)
                const bi = previous.indexOf(b.pid + ":" + b.start)
                return (ai < 0 ? 1000 : ai) - (bi < 0 ? 1000 : bi)
            })
        }
        rows = rows.slice(0, 40)
        const identities = rows.map(p => p.pid + ":" + p.start)
        for (let i = processes.count - 1; i >= 0; --i)
            if (identities.indexOf(processes.get(i).identity) < 0) processes.remove(i)
        for (let i = 0; i < rows.length; ++i) {
            const row = Object.assign({ identity: identities[i] }, rows[i])
            let previous = -1
            for (let j = i; j < processes.count; ++j)
                if (processes.get(j).identity === row.identity) { previous = j; break }
            if (previous < 0) processes.insert(i, row)
            else {
                if (previous !== i) processes.move(previous, i, 1)
                processes.set(i, row)
            }
        }
    }
    onSortedProcessesChanged: updateProcesses()
    Component.onCompleted: updateProcesses()

    ListView {
        id: processList
        objectName: "system-processes"
        Layout.fillWidth: true; Layout.fillHeight: true
        Layout.minimumHeight: 80
        clip: true; spacing: 2
        model: processes
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: IslandScrollBar {}
        onActiveFocusChanged: Qt.callLater(view.updateProcesses)
        HoverHandler {
            id: processHover
            onHoveredChanged: Qt.callLater(view.updateProcesses)
        }
        delegate: Rectangle {
            id: row
            required property int pid
            required property string start
            required property string nombre
            required property real cpu
            required property real ram
            required property int index
            onIndexChanged: if (endAction && endAction.activeFocus)
                Qt.callLater(processList.positionViewAtIndex, index, ListView.Contain)
            width: processList.width; height: 36
            radius: 8; color: rowHover.hovered || endAction.activeFocus ? Theme.surface : "transparent"
            HoverHandler { id: rowHover }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                spacing: 12
                IslandLabel {
                    text: row.nombre; font.pixelSize: 12
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                IslandLabel { text: row.pid; color: Theme.muted; font.pixelSize: 11; Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight }
                IslandLabel { text: row.cpu.toFixed(1) + "%"; font.pixelSize: 12; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                IslandLabel {
                    text: row.ram >= 1024 ? (row.ram / 1024).toFixed(1) + " GiB" : Math.round(row.ram) + " MiB"
                    color: Theme.muted; font.pixelSize: 11; Layout.preferredWidth: 85; horizontalAlignment: Text.AlignRight
                }
                K4.ActionButton {
                    id: endAction
                    text: "End"; Layout.preferredWidth: 52
                    Accessible.name: "End " + row.nombre + ", process " + row.pid
                    onActiveFocusChanged: if (activeFocus) processList.positionViewAtIndex(row.index, ListView.Contain)
                    onClicked: Sistema.matar(row.pid, row.start)
                }
            }
        }
        IslandLabel {
            anchors.centerIn: parent
            visible: processList.count === 0
            text: Sistema.processesReady ? "No process readings available" : "Measuring process activity…"
            color: Theme.muted; font.pixelSize: 12
        }
    }
    IslandLabel {
        Layout.fillWidth: true
        text: Sistema.processNotice || "Process CPU: 100% = one logical CPU · History: up to 90s · Charts / processes: 2s"
        color: Theme.muted; font.pixelSize: 10; elide: Text.ElideRight
    }
}
