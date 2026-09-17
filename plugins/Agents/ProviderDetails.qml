import QtQuick
import K4 as K4

Column {
    id: details
    required property var provider
    property string copied: ""
    spacing: 10

    K4.Etiqueta {
        width: parent.width
        text: "Usage tracking in k4"
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
    K4.Etiqueta {
        width: parent.width
        text: details.provider.setup
        wrapMode: Text.Wrap
        color: K4.Tema.apagado
        font.pixelSize: 11
    }
    Rectangle { width: parent.width; height: 1; color: K4.Tema.carril }
    K4.Etiqueta {
        width: parent.width
        text: "Provider setup · models.dev"
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
    K4.Etiqueta {
        width: parent.width
        text: details.provider.id + " · " + details.provider.modelCount + " models"
        wrapMode: Text.Wrap
        color: K4.Tema.apagado
        font.pixelSize: 11
    }
    K4.Etiqueta {
        width: parent.width
        text: (details.provider.env || []).length ? "Published credential variable names — click to copy a name:" : "This provider publishes no credential environment variables. See its documentation."
        wrapMode: Text.Wrap
        color: K4.Tema.apagado
        font.pixelSize: 11
    }
    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: details.provider.env || []
            delegate: K4.ActionButton {
                required property string modelData
                text: modelData
                width: Math.min(implicitWidth, details.width)
                Accessible.name: "Copy environment variable name " + modelData
                onClicked: {
                    K4.Sistema.copiar(modelData)
                    details.copied = modelData
                    feedback.restart()
                }
            }
        }
    }
    K4.Etiqueta {
        width: parent.width
        visible: !!details.copied
        text: "Copied " + details.copied + ". Configure it using the provider's documentation; k4 does not store your key."
        wrapMode: Text.Wrap
        color: K4.Tema.verde
        font.pixelSize: 11
    }
    K4.Etiqueta {
        width: parent.width
        visible: !!details.provider.api
        text: "API endpoint: " + (details.provider.api || "")
        wrapMode: Text.WrapAnywhere
        color: K4.Tema.apagado
        font.pixelSize: 10
    }
    K4.ActionButton {
        visible: !!details.provider.doc
        text: "Open provider documentation"
        width: Math.min(implicitWidth, details.width)
        onClicked: K4.Sistema.abrir(details.provider.doc)
    }
    Timer { id: feedback; interval: 5000; onTriggered: details.copied = "" }
}
