// Controlled filled slider. Direct manipulation is immediate; external changes ease.
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

    implicitHeight: etiqueta.length > 0 ? 60 : 32
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.Slider
    Accessible.name: etiqueta
    Accessible.description: valor + sufijo
    Accessible.onIncreaseAction: _move(Math.min(hasta, valor + paso))
    Accessible.onDecreaseAction: _move(Math.max(desde, valor - paso))
    Keys.onPressed: function (event) {
        if (!enabled) return
        let next = valor
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) next -= paso
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) next += paso
        else if (event.key === Qt.Key_Home) next = desde
        else if (event.key === Qt.Key_End) next = hasta
        else return
        _move(Math.max(desde, Math.min(hasta, next)))
        event.accepted = true
    }

    readonly property real fraccion: hasta > desde
        ? Math.max(0, Math.min(1, (valor - desde) / (hasta - desde))) : 0

    // Only user requests make a sound. Bound values may change in the background.
    function _move(next) {
        if (!enabled || next === valor) return
        movido(next)
        Feedback.tick()
    }

    function cuantizar(f) {
        const raw = desde + Math.max(0, Math.min(1, f)) * (hasta - desde)
        const step = paso > 0 ? paso : 1
        const snapped = desde + Math.round((raw - desde) / step) * step
        return Math.max(desde, Math.min(hasta, Number(snapped.toFixed(6))))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: control.etiqueta.length > 0 ? 6 : 0
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
            Layout.preferredHeight: 32
            Rectangle {
                anchors.fill: parent
                radius: 16
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
                height: Math.min(28, parent.height)
                radius: height / 2
                color: Tema.superficieAlta
                Rectangle {
                    id: fill
                    width: track.width * control.fraccion
                    height: parent.height
                    radius: Math.min(parent.radius, width / 2)
                    color: Tema.tinta
                    Behavior on width {
                        enabled: !control.dragging
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                    // An inset grip keeps the filled pill tactile without a
                    // separate circular thumb or a thin exposed track.
                    Rectangle {
                        visible: fill.width > 24
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: control.dragging ? 14 : 10
                        radius: 1.5
                        color: Tema.fondo
                        opacity: 0.6
                        Behavior on height { NumberAnimation { duration: 100 } }
                    }
                }
            }
            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function apply(x) {
                    const next = control.cuantizar((x - track.x) / Math.max(1, track.width))
                    control._move(next)
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
