// One responsive row for host and plugin settings. Values remain owner-controlled.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
    id: opcion
    required property var modelData
    property bool highlighted: false

    readonly property bool esTitulo: modelData.tipo === "titulo"
    readonly property bool activa: !!Settings.valor(modelData.id)
    readonly property bool disponible:
        (!modelData.requiere || Settings.valor(modelData.requiere))
        && modelData.disponible !== false && modelData.error !== "fijo"
    readonly property string valorTexto: {
        const v = Settings.valor(modelData.id)
        return v === undefined || v === null || v === false ? "" : String(v)
    }
    readonly property bool stacked: width < 520 && !!modelData.tipo
    readonly property string description: {
        if (armada)
            return modelData.descArmado || modelData.desc || ""
        if (modelData.requiere && !Settings.valor(modelData.requiere))
            return (modelData.desc || "") + " · Enable the parent setting to adjust this."
        return modelData.desc || ""
    }
    property bool armada: false

    objectName: "setting-" + (modelData.id || "")
    Layout.fillWidth: true
    implicitHeight: esTitulo ? 32 : Math.max(52, body.implicitHeight + 24)
    Layout.preferredHeight: implicitHeight
    radius: 10
    color: esTitulo ? "transparent" : Theme.surface
    border.width: highlighted || armada ? 1 : 0
    border.color: armada ? Theme.red : Theme.blue

    onVisibleChanged: if (!visible) armada = false
    Timer { id: disarm; interval: 4000; onTriggered: opcion.armada = false }

    IslandLabel {
        visible: opcion.esTitulo
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        text: opcion.modelData.nombre || ""
        color: Theme.muted
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        enabled: !opcion.modelData.tipo && opcion.disponible
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Settings.alternar(opcion.modelData.id)
            K4.Feedback.click()
        }
    }

    GridLayout {
        id: body
        visible: !opcion.esTitulo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        columns: opcion.stacked ? 1 : 2
        columnSpacing: 16
        rowSpacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            K4.IconoPlugin {
                imagen: opcion.modelData.imagen || ""
                glifo: opcion.modelData.glifo || 0
                tamano: 16
                color: opcion.disponible ? Theme.muted : Theme.dim
                Layout.preferredWidth: 20
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                IslandLabel {
                    Layout.fillWidth: true
                    text: opcion.armada
                        ? (opcion.modelData.nombreArmado || "Confirm this action")
                        : (opcion.modelData.nombre || "")
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: opcion.armada ? Theme.red : Theme.ink
                    wrapMode: Text.WordWrap
                }
                IslandLabel {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: opcion.description
                    font.pixelSize: 11
                    color: opcion.modelData.error ? Theme.red : Theme.muted
                    wrapMode: Text.WordWrap
                }
            }
        }

        Loader {
            id: editor
            Layout.fillWidth: opcion.stacked
            Layout.preferredWidth: item ? item.implicitWidth : 0
            Layout.preferredHeight: item ? item.implicitHeight : 0
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            enabled: opcion.disponible
            visible: !opcion.esTitulo && opcion.modelData.tipo !== "eleccion"
            sourceComponent: opcion.modelData.error === "recargable" ? retryControl
                : !opcion.modelData.tipo ? switchControl
                : opcion.modelData.tipo === "numero" ? numberControl
                : opcion.modelData.tipo === "texto" ? textControl
                : opcion.modelData.tipo === "peligro" ? actionControl : null
        }

        Flow {
            id: choices
            visible: opcion.modelData.tipo === "eleccion"
            Layout.columnSpan: body.columns
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.preferredHeight: implicitHeight
            spacing: 8
            enabled: opcion.disponible

            Repeater {
                id: choiceRepeater
                model: opcion.modelData.alternativas
                    || Settings.opcionesDe(opcion.modelData.de)
                delegate: K4.ActionButton {
                    required property var modelData
                    required property int index
                    text: modelData.nombre
                    width: Math.min(implicitWidth, choices.width)
                    selected: Settings.valor(opcion.modelData.id) === modelData.codigo
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: selected
                    Accessible.name: opcion.modelData.nombre + ": " + text
                    onClicked: Settings.poner(opcion.modelData.id, modelData.codigo)
                    Keys.onPressed: function (event) {
                        const direction = event.key === Qt.Key_Right ? 1
                            : event.key === Qt.Key_Left ? -1 : 0
                        if (!direction) return
                        const next = choiceRepeater.itemAt(
                            (index + direction + choiceRepeater.count) % choiceRepeater.count)
                        if (next) { next.forceActiveFocus(); next.clicked() }
                        event.accepted = true
                    }
                }
            }
        }
    }

    Component {
        id: switchControl
        K4.Interruptor {
            marcado: opcion.activa
            Accessible.name: opcion.modelData.nombre || ""
            onAlternado: Settings.alternar(opcion.modelData.id)
        }
    }

    Component {
        id: retryControl
        K4.ActionButton {
            text: "Retry"
            onClicked: PluginManager.reintentar(opcion.modelData.pluginId)
        }
    }

    Component {
        id: numberControl
        RowLayout {
            id: number
            spacing: 8
            readonly property int value: Number(Settings.valor(opcion.modelData.id)) || 0
            readonly property int minimum: opcion.modelData.min ?? -2147483647
            readonly property int maximum: opcion.modelData.max ?? 2147483647
            function setValue(value) {
                if (!opcion.disponible || !Number.isFinite(value)) return
                Settings.poner(opcion.modelData.id,
                    Math.max(minimum, Math.min(maximum, Math.round(value))))
            }
            K4.ActionButton {
                text: "−"
                implicitWidth: 32
                enabled: number.value > number.minimum
                Accessible.name: "Decrease " + opcion.modelData.nombre
                onClicked: number.setValue(number.value - (opcion.modelData.paso || 1))
            }
            K4.TextField {
                id: numericInput
                Layout.preferredWidth: 64
                horizontalAlignment: TextInput.AlignHCenter
                Accessible.name: opcion.modelData.nombre || ""
                validator: IntValidator { bottom: number.minimum; top: number.maximum }
                text: String(number.value)
                onEditingFinished: {
                    if (acceptableInput) number.setValue(Number(text))
                    text = Qt.binding(function () { return String(number.value) })
                }
                Keys.onEscapePressed: function (event) {
                    text = Qt.binding(function () { return String(number.value) })
                    focus = false
                    event.accepted = true
                }
                Keys.onUpPressed: number.setValue(number.value + (opcion.modelData.paso || 1))
                Keys.onDownPressed: number.setValue(number.value - (opcion.modelData.paso || 1))
            }
            IslandLabel {
                visible: text.length > 0
                text: opcion.modelData.unidad || ""
                color: Theme.muted
                font.pixelSize: 11
            }
            K4.ActionButton {
                text: "+"
                implicitWidth: 32
                enabled: number.value < number.maximum
                Accessible.name: "Increase " + opcion.modelData.nombre
                onClicked: number.setValue(number.value + (opcion.modelData.paso || 1))
            }
        }
    }

    Component {
        id: textControl
        K4.TextField {
            Accessible.name: opcion.modelData.nombre || ""
            placeholderText: opcion.modelData.pista || ""
            echoMode: opcion.modelData.secreto ? TextInput.Password : TextInput.Normal
            text: opcion.valorTexto
            onEditingFinished: {
                if (opcion.disponible && text !== opcion.valorTexto)
                    Settings.poner(opcion.modelData.id, text)
                text = Qt.binding(function () { return opcion.valorTexto })
            }
            Keys.onEscapePressed: function (event) {
                text = Qt.binding(function () { return opcion.valorTexto })
                focus = false
                event.accepted = true
            }
        }
    }

    Component {
        id: actionControl
        RowLayout {
            spacing: 8
            K4.ActionButton {
                visible: opcion.armada
                text: "Cancel"
                onClicked: { opcion.armada = false; disarm.stop() }
            }
            K4.ActionButton {
                text: opcion.armada ? (opcion.modelData.confirmar || "Confirm")
                    : (opcion.modelData.accion || "Run")
                onClicked: {
                    if (opcion.armada) {
                        Settings.ejecutar(opcion.modelData.id)
                        opcion.armada = false
                        disarm.stop()
                    } else {
                        opcion.armada = true
                        disarm.restart()
                    }
                }
            }
        }
    }
}
