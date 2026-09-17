//  One card per agent, one row per limit.
//
//  What one wants to know is two numbers: where you stand and when
//  it forgives you. So each row is the window's name, its bar, its
//  percentage and when it resets —and nothing else.
//
//  The reset carries both ways of saying it, one over the other: day
//  and time on top and the countdown below. Neither is spare. «In
//  3 h 25 min» crosses nobody's schedule, and «today at 19:59» does
//  not say whether you have time to finish what you have open.
//
//  The window counting right now goes in ink and the rest in gray:
//  the five hours and the week do not squeeze at once, and telling
//  them apart at a glance is half the question answered.

import QtQuick
import K4 as K4

K4.Aparicion {
    id: view

    required property var plugin

    //  The house clock, to the minute. Passed as an argument to the
    //  functions that need it so the binding learns it depends on it:
    //  a countdown that does not re-evaluate stays frozen at opening
    //  time.
    readonly property date ahora: K4.Reloj.ahora

    //  Green until well in, amber when less than half is left and
    //  red when it pays to measure. The cutoffs are the same for all
    //  agents: if each had its own, color would stop meaning.
    function tono(pct) {
        if (pct >= 85) return K4.Tema.rojo
        if (pct >= 60) return K4.Tema.amarillo
        return K4.Tema.verde
    }

    function cuanto(segundos, reloj) {
        if (!segundos)
            return ""

        const falta = segundos * 1000 - reloj.getTime()
        if (falta <= 0)
            return "restarting"

        const min = Math.round(falta / 60000)
        if (min < 60)
            return `in ${min} min`

        const horas = Math.floor(min / 60)
        if (horas < 24) {
            const resto = min % 60
            return resto
                ? `in ${horas} h ${resto} min`
                : `in ${horas} h`
        }

        const dias = Math.round(horas / 24)
        return dias === 1 ? "in 1 day"
                          : `in ${dias} days`
    }

    //  Days by name, and in the bar's language. `Qt.formatDate`
    //  gives them in the system's, which here put «Sun» in the
    //  middle of a Spanish interface. Starts on Sunday because that
    //  is how `getDay()` numbers them.
    readonly property var nombresDia: [
        "Sun", "Mon", "Tue", "Wed",
        "Thu", "Fri", "Sat"
    ]

    //  The reset's day and time. Said the way one would say it:
    //  «today» and «tomorrow» have names, next week is named by its
    //  day, and beyond that the date is needed.
    function cuando(segundos, reloj) {
        if (!segundos)
            return ""

        const d = new Date(segundos * 1000)
        const hora = Qt.formatTime(d, "HH:mm")

        //  Days are counted midnight to midnight, not by the hours
        //  left: at eleven at night, something resetting in three
        //  hours is tomorrow, and saying «today» there would be a
        //  lie.
        const suyo = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const nuestro = new Date(reloj.getFullYear(), reloj.getMonth(), reloj.getDate())
        const dias = Math.round((suyo.getTime() - nuestro.getTime()) / 86400000)

        if (dias <= 0)
            return `today ${hora}`
        if (dias === 1)
            return `tomorrow ${hora}`
        if (dias < 7)
            return view.nombresDia[d.getDay()] + " " + hora
        //  No window today reaches that far, but if one a month out
        //  shows up tomorrow, the numeric date depends on no
        //  language.
        return Qt.formatDate(d, "d/M") + " " + hora
    }

    //  How old the data is. Always shown, even when it is from a
    //  moment ago: whoever reads it must know this is a snapshot,
    //  not a live counter.
    function frescura(segundos, reloj) {
        if (!segundos)
            return "no date"

        const min = Math.round((reloj.getTime() - segundos * 1000) / 60000)
        if (min < 1)
            return "just now"
        if (min < 60)
            return `${min} min ago`

        const horas = Math.round(min / 60)
        if (horas < 24)
            return horas === 1 ? "1 h ago"
                               : `${horas} h ago`

        const dias = Math.round(horas / 24)
        return dias === 1 ? "1 day ago"
                          : `${dias} days ago`
    }

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        height: 32

        K4.Etiqueta {
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Agents"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Row {
            id: actions
            anchors.right: parent.right
            spacing: 6
            K4.ActionButton {
                text: "Manage providers"
                enabled: !!view.plugin.settings
                onClicked: view.plugin.manageProviders()
            }
            K4.Boton {
                glifo: String.fromCodePoint(0xF0450)
                tamano: 14
                Accessible.name: "Refresh usage"
                activo: !view.plugin.usageBusy && view.plugin.enabledProviders.length > 0
                onPulsado: view.plugin.refrescar()
            }
            K4.Boton {
                glifo: String.fromCodePoint(0xF0156)
                tamano: 14
                Accessible.name: "Close Agents"
                onPulsado: view.plugin.close()
            }
        }
    }

    K4.Rodillo {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 14
        anchors.topMargin: 8

        Column {
            width: parent.width
            spacing: 8

            K4.Etiqueta {
                width: parent.width
                visible: !!view.plugin.usageError
                text: view.plugin.usageError
                color: K4.Tema.amarillo
                wrapMode: Text.Wrap
                font.pixelSize: 11
            }

            Repeater {
                model: view.plugin.agentes
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property var limits: modelData.limites || []
                    width: parent.width
                    height: body.implicitHeight + 20
                    radius: 11
                    color: K4.Tema.superficie

                    Column {
                        id: body
                        x: 10
                        y: 10
                        width: parent.width - 20
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 18
                            K4.Etiqueta {
                                anchors.left: parent.left
                                anchors.right: freshness.left
                                anchors.rightMargin: 8
                                text: card.modelData.nombre + (card.modelData.plan ? " · " + card.modelData.plan : "")
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            // The timestamp always identifies this as a snapshot.
                            // The cache badge also explains why it might be old.
                            K4.Etiqueta {
                                id: freshness
                                anchors.right: parent.right
                                text: (card.modelData.fuente === "cache" ? "cached · " : "")
                                    + view.frescura(card.modelData.actualizado, view.ahora)
                                color: K4.Tema.apagado
                                font.pixelSize: 9
                            }
                        }
                        K4.Etiqueta {
                            width: parent.width
                            visible: !!card.modelData.creditos
                            text: "Credits: " + (card.modelData.creditos || "")
                            color: K4.Tema.apagado
                            font.pixelSize: 10
                        }
                        K4.Etiqueta {
                            width: parent.width
                            visible: !card.limits.length
                            text: card.modelData.razon || "No usage data available"
                            wrapMode: Text.Wrap
                            color: K4.Tema.apagado
                            font.pixelSize: 11
                        }
                        Repeater {
                            model: card.limits
                            delegate: Item {
                                id: row
                                required property var modelData
                                readonly property real pct: Math.max(0, Math.min(100, modelData.pct || 0))
                                width: parent.width
                                height: 24
                                K4.Etiqueta {
                                    id: label
                                    width: 84
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.nombre
                                    elide: Text.ElideRight
                                    color: row.modelData.activo ? K4.Tema.tinta : K4.Tema.apagado
                                    font.pixelSize: 10
                                }
                                K4.Medidor {
                                    anchors.left: label.right
                                    anchors.right: percent.left
                                    anchors.margins: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    valor: row.pct
                                    maximo: 100
                                    grosor: 6
                                    tono: view.tono(row.pct)
                                    // A small amount spent must still be visible.
                                    minimo: 3
                                }
                                K4.Etiqueta {
                                    id: percent
                                    anchors.right: reset.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 42
                                    text: (row.pct < 10 && row.pct > 0 ? row.pct.toFixed(1) : Math.round(row.pct)) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    color: view.tono(row.pct)
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                // Date and countdown describe the same instant.
                                // Rolling recovery estimates are explicitly labeled.
                                Column {
                                    id: reset
                                    anchors.right: parent.right
                                    width: 112
                                    K4.Etiqueta {
                                        width: parent.width
                                        text: row.modelData.reinicia ? view.cuando(row.modelData.reinicia, view.ahora)
                                            : row.modelData.resetEstimated ? "Rolling window" : "Reset unavailable"
                                        horizontalAlignment: Text.AlignRight
                                        color: K4.Tema.apagado
                                        font.pixelSize: 10
                                    }
                                    K4.Etiqueta {
                                        width: parent.width
                                        text: row.modelData.reinicia ? (row.modelData.resetEstimated ? "≈ " : "")
                                            + view.cuanto(row.modelData.reinicia, view.ahora) : ""
                                        horizontalAlignment: Text.AlignRight
                                        color: K4.Tema.apagado
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }
                    }
                }
            }
            K4.Etiqueta {
                width: parent.width
                visible: !view.plugin.agentes.length
                text: !view.plugin.enabledProviders.length ? "No providers enabled — choose one in Manage providers"
                    : !view.plugin.cargado ? "Checking usage…" : "No usage data available"
                wrapMode: Text.Wrap
                color: K4.Tema.apagado
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
