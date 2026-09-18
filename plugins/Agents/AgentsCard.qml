import QtQuick
import QtQuick.Layouts
import K4 as K4

K4.Baldosa {
    id: cardView

    required property var plugin
    required property var card

    readonly property var tightest: plugin.apurado
    readonly property real percentage: tightest ? Math.max(0, Math.min(100, tightest.pct || 0)) : 0
    readonly property string summary: !plugin.enabledProviders.length
        ? "No providers enabled"
        : plugin.usageBusy && !plugin.cargado ? "Checking usage…"
        : tightest ? tightest.agente + " · " + tightest.nombre
        : plugin.usageError || "No quota data available"

    radius: 12
    color: K4.Tema.superficie
    Accessible.name: "Open agent usage"
    onPulsada: card.openDetail()

    Component.onCompleted: {
        plugin.controlCardOpen = true
        plugin.refrescar()
    }
    Component.onDestruction: if (plugin) plugin.controlCardOpen = false

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            K4.Etiqueta {
                text: "Agent usage"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            K4.Etiqueta {
                Layout.fillWidth: true
                text: cardView.summary
                color: K4.Tema.apagado
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        K4.Medidor {
            visible: cardView.tightest !== null
            Layout.preferredWidth: 120
            valor: cardView.percentage
            maximo: 100
            grosor: 6
            minimo: 3
            tono: cardView.percentage >= 85 ? K4.Tema.rojo
                : cardView.percentage >= 60 ? K4.Tema.amarillo : K4.Tema.verde
        }
        K4.Etiqueta {
            visible: cardView.tightest !== null
            text: Math.round(cardView.percentage) + "%"
            color: cardView.percentage >= 85 ? K4.Tema.rojo
                : cardView.percentage >= 60 ? K4.Tema.amarillo : K4.Tema.verde
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        K4.Etiqueta {
            text: String.fromCodePoint(0xF0142)
            color: K4.Tema.apagado
            font.pixelSize: 16
        }
    }
}
