// Controlled numeric slider. Direct manipulation is immediate; external changes ease.
import QtQuick
import QtQuick.Layouts

Item {
    id: control

    property string etiqueta: ""
    property real valor: 0
    property real desde: 0
    property real hasta: 100
    property real paso: 1
    property string sufijo: ""
    readonly property bool dragging: pointer.pressed
    signal movido(real valor)

    implicitHeight: etiqueta.length > 0 ? 48 : 28
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.Slider
    Accessible.name: etiqueta
    Accessible.description: valor + sufijo
    Accessible.onIncreaseAction: if (enabled) movido(Math.min(hasta, valor + paso))
    Accessible.onDecreaseAction: if (enabled) movido(Math.max(desde, valor - paso))
    Keys.onPressed: function (event) {
        if (!enabled) return
        let next = valor
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) next -= paso
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) next += paso
        else if (event.key === Qt.Key_Home) next = desde
        else if (event.key === Qt.Key_End) next = hasta
        else return
        movido(Math.max(desde, Math.min(hasta, next)))
        event.accepted = true
    }

    readonly property real fraccion: hasta > desde
        ? Math.max(0, Math.min(1, (valor - desde) / (hasta - desde))) : 0

    function cuantizar(f) {
        const raw = desde + Math.max(0, Math.min(1, f)) * (hasta - desde)
        const step = paso > 0 ? paso : 1
        const snapped = desde + Math.round((raw - desde) / step) * step
        return Math.max(desde, Math.min(hasta, Number(snapped.toFixed(6))))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            visible: control.etiqueta.length > 0
            Layout.fillWidth: true
            spacing: 8
            Etiqueta {
                text: control.etiqueta
                color: Tema.apagado
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Etiqueta {
                text: control.valor + control.sufijo
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.width: control.activeFocus ? 1 : 0
                border.color: Tema.azul
            }
            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: 2
                color: Tema.carril
                Rectangle {
                    width: track.width * control.fraccion
                    height: parent.height
                    radius: parent.radius
                    color: Tema.tinta
                    Behavior on width {
                        enabled: !control.dragging
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                }
            }
            Rectangle {
                x: track.x + track.width * control.fraccion - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: Tema.tinta
                Behavior on x {
                    enabled: !control.dragging
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }
            }
            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function apply(x) {
                    const next = control.cuantizar((x - track.x) / Math.max(1, track.width))
                    if (next !== control.valor) control.movido(next)
                }
                onPressed: function (event) {
                    control.forceActiveFocus(Qt.MouseFocusReason)
                    apply(event.x)
                }
                onPositionChanged: function (event) { if (pressed) apply(event.x) }
            }
        }
    }
}
