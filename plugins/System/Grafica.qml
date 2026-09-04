//  A bar chart with the latest samples.
//
//  Bars and not a line on purpose: with forty-five values in two
//  hundred pixels a polyline is a scribble, and bars read just as
//  well from afar. The last one is lit, the one saying how things
//  are now.

import QtQuick
import "../../core"

Item {
    id: grafica

    property var valores: []
    property real techo: 100            // 0 if it must be computed from the data
    property color tono: Theme.blue

    // When the ceiling is dynamic —network has no maximum— the
    // window's greatest is taken, with a floor so background noise
    // does not fill the chart.
    readonly property real limite: {
        if (techo > 0)
            return techo
        let m = 1
        for (let i = 0; i < valores.length; ++i)
            m = Math.max(m, valores[i])
        return m
    }

    readonly property int cuantas: 45
    readonly property real anchoBarra: Math.max(1, (width - (cuantas - 1) * 1) / cuantas)

    Row {
        anchors.fill: parent
        spacing: 1

        Repeater {
            model: grafica.cuantas

            delegate: Item {
                id: hueco
                required property int index

                // Samples paint glued to the right: the history
                // enters from the left as it fills.
                readonly property int desde: grafica.cuantas - grafica.valores.length
                readonly property real valor: index >= desde
                    ? grafica.valores[index - desde] : -1

                width: grafica.anchoBarra
                height: grafica.height

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: hueco.valor < 0 ? 0
                        : Math.max(1, parent.height
                            * Math.min(1, hueco.valor / grafica.limite))
                    radius: width > 2 ? 1 : 0
                    color: grafica.tono
                    opacity: hueco.index === grafica.cuantas - 1 ? 1 : 0.45

                    Behavior on height { NumberAnimation { duration: 220 } }
                }
            }
        }
    }
}
