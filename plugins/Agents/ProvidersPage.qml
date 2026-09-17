// Settings owns scrolling; this page reports its complete content height.
import QtQuick
import K4 as K4

Column {
    id: page
    required property var plugin
    property string filter: "all"
    property string selected: ""
    property int pageIndex: 0
    readonly property int pageSize: 12
    readonly property var matches: plugin.catalogProviders.filter(function (provider) {
        const query = search.text.trim().toLowerCase()
        const text = [provider.name, provider.id, provider.scope].concat(provider.env || []).join(" ").toLowerCase()
        return (!query || text.indexOf(query) >= 0)
            && (page.filter === "all" || (page.filter === "supported" && !!provider.adapter)
                || (page.filter === "enabled" && page.plugin.providerEnabled(provider.adapter)))
    })
    readonly property int pageCount: Math.max(1, Math.ceil(matches.length / pageSize))
    onPageCountChanged: pageIndex = Math.min(pageIndex, pageCount - 1)
    onFilterChanged: pageIndex = 0
    spacing: 12

    Component.onCompleted: {
        plugin.providersPageOpen = true
        plugin.loadCatalog(false, "")
        plugin.refrescar()
    }
    Component.onDestruction: plugin.providersPageOpen = false

    K4.Etiqueta {
        width: parent.width
        text: "Choose what to keep an eye on"
        font.pixelSize: 18
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
    }
    K4.Etiqueta {
        width: parent.width
        text: "Browse every provider in models.dev. Supported integrations can check your subscription quotas; provider details explain the setup."
        color: K4.Tema.apagado
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
    Rectangle {
        width: parent.width
        height: network.implicitHeight + 24
        color: K4.Tema.superficie
        radius: 12
        Row {
            id: network
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 12
            Column {
                width: parent.width - online.width - 12
                spacing: 4
                K4.Etiqueta { text: "Live checks"; font.pixelSize: 12; font.weight: Font.DemiBold }
                K4.Etiqueta {
                    width: parent.width
                    text: page.plugin.enVivo ? "Usage APIs, catalog refreshes and selected provider logos are available."
                        : "Offline: local CLI usage and the saved provider catalog remain available."
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    color: K4.Tema.apagado
                }
            }
            K4.Interruptor {
                id: online
                marcado: page.plugin.enVivo
                enabled: page.plugin.settingsReady
                Accessible.name: "Allow live usage and catalog requests"
                onAlternado: {
                    page.plugin.enVivo = !marcado
                    page.plugin.apuntar()
                }
            }
        }
    }
    K4.TextField {
        id: search
        objectName: "providerSearch"
        width: parent.width
        placeholderText: "Search providers, integrations or environment variables"
        Accessible.name: "Search all agent providers"
        onTextChanged: page.pageIndex = 0
    }
    Flow {
        width: parent.width
        spacing: 8
        Repeater {
            model: [{ id: "all", title: "All providers" }, { id: "supported", title: "Supported" }, { id: "enabled", title: "Enabled" }]
            delegate: K4.ActionButton {
                required property var modelData
                text: modelData.title
                selected: page.filter === modelData.id
                onClicked: page.filter = modelData.id
            }
        }
        K4.ActionButton {
            text: page.plugin.catalogBusy ? "Loading…" : "Refresh catalog"
            enabled: page.plugin.enVivo && !page.plugin.catalogBusy
            onClicked: page.plugin.loadCatalog(true, "")
        }
        K4.ActionButton {
            text: "Check usage"
            enabled: page.plugin.settingsReady && page.plugin.enabledProviders.length > 0 && !page.plugin.usageBusy
            onClicked: page.plugin.refrescar()
        }
    }
    K4.Etiqueta {
        width: parent.width
        text: page.matches.length + " providers · " + page.plugin.enabledProviders.length + " usage integrations enabled"
        color: K4.Tema.apagado
        font.pixelSize: 11
    }
    K4.Etiqueta {
        width: parent.width
        visible: !!page.plugin.catalogError
        text: page.plugin.catalogError
        color: K4.Tema.amarillo
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Repeater {
        model: page.matches.slice(page.pageIndex * page.pageSize, (page.pageIndex + 1) * page.pageSize)
        delegate: ProviderRow {
            required property var modelData
            width: page.width
            plugin: page.plugin
            provider: modelData
            expanded: page.selected === modelData.id
            onToggleDetails: {
                page.selected = expanded ? "" : modelData.id
                if (page.selected && !modelData.logo && page.plugin.enVivo)
                    page.plugin.loadCatalog(false, modelData.id)
            }
        }
    }
    K4.Etiqueta {
        width: parent.width
        visible: !page.matches.length
        text: !page.plugin.catalogLoaded && page.plugin.catalogBusy ? "Loading the provider catalog…" : "No providers match this search"
        color: K4.Tema.apagado
        wrapMode: Text.Wrap
        font.pixelSize: 12
    }
    Flow {
        width: parent.width
        spacing: 8
        K4.ActionButton {
            text: "Previous"
            enabled: page.pageIndex > 0
            onClicked: page.pageIndex--
        }
        K4.Etiqueta {
            height: 32
            verticalAlignment: Text.AlignVCenter
            text: "Page " + (page.pageIndex + 1) + " of " + page.pageCount
            color: K4.Tema.apagado
            font.pixelSize: 11
        }
        K4.ActionButton {
            text: "Next"
            enabled: page.pageIndex + 1 < page.pageCount
            onClicked: page.pageIndex++
        }
    }
    K4.Etiqueta {
        width: parent.width
        text: "Provider information: models.dev · " + (page.plugin.catalogInfo.origin || "bundled")
            + (page.plugin.catalogInfo.updated ? " · " + Qt.formatDateTime(new Date(page.plugin.catalogInfo.updated * 1000), "yyyy-MM-dd HH:mm") : "")
        color: K4.Tema.apagado
        wrapMode: Text.Wrap
        font.pixelSize: 10
    }
}
