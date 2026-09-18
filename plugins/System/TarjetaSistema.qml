// A glanceable summary; the detailed monitor owns histories and process actions.
import QtQuick
import K4 as K4

K4.Baldosa {
    id: card
    required property var plugin
    readonly property string samplingOwner: "system.card." + Math.random().toString(36).slice(2)
    objectName: "tile-system"
    radius: 14
    readonly property var metrics: ["cpu", "memory", "network"].filter(id =>
        id === "cpu" ? plugin.tarjetaCpu : id === "memory" ? plugin.tarjetaRam : plugin.tarjetaRed)
    readonly property bool wantsSamples: metrics.length > 0 && plugin.panel && plugin.panel.open && plugin.panel.tab === "controls"
    function reading(id) {
        if (id === "cpu") return { label: "CPU", value: K4.SystemMonitor.cpuPercent < 0 ? "—" : Math.round(K4.SystemMonitor.cpuPercent) + "%",
          detail: K4.SystemMonitor.cpuTemperature > 0 ? K4.SystemMonitor.temperature(K4.SystemMonitor.cpuTemperature) : "All logical CPUs",
          percent: K4.SystemMonitor.cpuPercent }
        if (id === "memory") return { label: "Memory", value: K4.SystemMonitor.memoryTotal > 0 ? K4.SystemMonitor.memoryUsed.toFixed(1) + " GiB" : "—",
          detail: K4.SystemMonitor.memoryTotal > 0 ? "of " + K4.SystemMonitor.memoryTotal.toFixed(1) + " GiB" : "Measuring…",
          percent: K4.SystemMonitor.memoryPercent }
        return { label: "Network", value: "↓ " + K4.SystemMonitor.rate(K4.SystemMonitor.download),
          detail: K4.SystemMonitor.interfaceName ? "↑ " + K4.SystemMonitor.rate(K4.SystemMonitor.upload) + " · " + K4.SystemMonitor.interfaceName : "No default route",
          percent: -1 }
    }
    Accessible.name: "Open system information"
    Accessible.description: metrics.map(id => { const m = reading(id); return m.label + " " + m.value + ", " + m.detail }).join(". ")
    onPulsada: {
        if (plugin.panel) plugin.panel.openTab("system")
        else plugin.toggle()
    }
    onWantsSamplesChanged: K4.SystemMonitor.sample(samplingOwner, wantsSamples, false)
    Component.onCompleted: K4.SystemMonitor.sample(samplingOwner, wantsSamples, false)
    Component.onDestruction: K4.SystemMonitor.sample(samplingOwner, false, false)
    Connections {
        target: K4.SystemMonitor
        function onAvailableChanged() { K4.SystemMonitor.sample(card.samplingOwner, card.wantsSamples, false) }
    }
    K4.Etiqueta {
        x: 16; y: 12
        text: "System"
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
    K4.Glifo {
        anchors.right: parent.right; anchors.rightMargin: 14
        y: 12; text: String.fromCodePoint(0xF0142)
        color: K4.Tema.apagado; font.pixelSize: 14
    }
    Row {
        x: 16; y: 36; width: parent.width - 32; height: 62
        spacing: 24
        Repeater {
            model: card.metrics
            delegate: Item {
                id: metric
                required property var modelData
                readonly property var reading: card.reading(modelData)
                width: (parent.width - 24 * (card.metrics.length - 1)) / card.metrics.length
                height: 62
                K4.Etiqueta {
                    width: parent.width; text: metric.reading.label
                    color: K4.Tema.apagado; font.pixelSize: 11
                }
                K4.Etiqueta {
                    y: 17; width: parent.width; text: metric.reading.value
                    font.pixelSize: 20; font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                K4.Etiqueta {
                    y: 43; width: parent.width; text: metric.reading.detail
                    color: K4.Tema.apagado; font.pixelSize: 11; elide: Text.ElideRight
                }
                Rectangle {
                    y: 61; width: parent.width; height: 2; radius: 1
                    visible: metric.reading.percent >= 0
                    color: K4.Tema.carril
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, metric.reading.percent)) / 100
                        height: 2; radius: 1; color: K4.Tema.azul; opacity: 0.8
                        Behavior on width { NumberAnimation { duration: 180 } }
                    }
                }
            }
        }
    }
    K4.Etiqueta {
        anchors.centerIn: parent; width: parent.width - 32
        visible: card.metrics.length === 0
        text: "Metrics hidden · Configure in Settings → Plugins"
        color: K4.Tema.apagado; font.pixelSize: 12; elide: Text.ElideRight
    }
}
