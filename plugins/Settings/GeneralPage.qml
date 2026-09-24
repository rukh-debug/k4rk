import QtQuick
import K4 as K4

Column {
    id: page
    required property var configuration
    spacing: 16
    property bool copied: false

    K4.Etiqueta {
        text: "Configuration"
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }
    K4.Etiqueta {
        width: parent.width
        text: "Shareable appearance and behavior settings live in this file. Personal profiles, histories, caches, and credentials are stored separately."
        wrapMode: Text.WordWrap
        color: K4.Tema.apagado
    }
    Rectangle {
        width: parent.width
        implicitHeight: pathText.implicitHeight + 28
        radius: 10
        color: K4.Tema.superficie
        border.color: K4.Tema.carril
        TextEdit {
            id: pathText
            objectName: "configuration-path"
            anchors.fill: parent
            anchors.margins: 14
            text: page.configuration.path
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            color: K4.Tema.tinta
            font.family: K4.Tema.fuente
            font.pixelSize: 13
            Accessible.name: "Configuration file location"
        }
    }
    Flow {
        width: parent.width
        spacing: 10
        K4.ActionButton {
            objectName: "copy-configuration"
            text: page.configuration.copying ? "Copying…" : page.copied ? "Copied" : "Copy configuration"
            enabled: page.configuration.ready && !page.configuration.pendingCount && !page.configuration.error && !page.configuration.copying
            Accessible.name: "Copy configuration JSON to clipboard"
            onClicked: {
                page.configuration.copyConfiguration()
            }
        }
        K4.ActionButton {
            text: "Copy file path"
            onClicked: K4.Sistema.copiar(page.configuration.path)
        }
    }
    K4.Etiqueta {
        width: parent.width
        text: page.configuration.error || page.configuration.copyError || (page.configuration.pendingCount ? "Saving changes…" : "Changes are saved automatically.")
        color: page.configuration.error ? K4.Tema.rojo : K4.Tema.apagado
        wrapMode: Text.WordWrap
    }
    Timer { id: copiedTimer; interval: 2200; onTriggered: page.copied = false }
    Connections {
        target: page.configuration
        function onCopied() { page.copied = true; copiedTimer.restart() }
    }
}
