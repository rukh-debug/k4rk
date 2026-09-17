import QtQuick
import K4 as K4

Rectangle {
    id: row
    required property var plugin
    required property var provider
    property bool expanded: false
    signal toggleDetails()

    height: contents.implicitHeight + 24
    radius: 12
    color: K4.Tema.superficie
    border.width: expanded ? 1 : 0
    border.color: K4.Tema.carril

    Column {
        id: contents
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 10

        Row {
            width: parent.width
            spacing: 12
            K4.IconoPlugin {
                imagen: row.provider.logo || ""
                glifo: 0xF06A9
                tamano: 24
            }
            Column {
                width: parent.width - 24 - usageToggle.width - 24
                spacing: 3
                K4.Etiqueta {
                    width: parent.width
                    text: row.provider.name
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                K4.Etiqueta {
                    width: parent.width
                    text: row.provider.scope || "Usage tracking not supported yet"
                    color: row.provider.adapter ? K4.Tema.apagado : K4.Tema.tenue
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
            K4.Interruptor {
                id: usageToggle
                objectName: "usage-" + row.provider.id
                enabled: row.plugin.settingsReady && !!row.provider.adapter
                marcado: row.plugin.providerEnabled(row.provider.adapter)
                Accessible.name: "Enable usage tracking for " + row.provider.name
                onAlternado: row.plugin.setProviderEnabled(row.provider.adapter, !marcado)
            }
        }
        K4.Etiqueta {
            width: parent.width
            visible: !!row.provider.adapter
            text: row.plugin.providerStatus(row.provider.adapter)
            color: K4.Tema.apagado
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        K4.ActionButton {
            objectName: "details-" + row.provider.id
            text: row.expanded ? "Hide details" : "Details & setup"
            Accessible.name: (row.expanded ? "Hide details for " : "Show details for ") + row.provider.name
            onClicked: row.toggleDetails()
        }
        Loader {
            width: parent.width
            active: row.expanded
            visible: active
            sourceComponent: Component { ProviderDetails { objectName: "providerDetails"; provider: row.provider } }
        }
    }
}
