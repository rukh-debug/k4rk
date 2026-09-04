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
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    //  The house clock, to the minute. Passed as an argument to the
    //  functions that need it so the binding learns it depends on it:
    //  a countdown that does not re-evaluate stays frozen at opening
    //  time.
    readonly property date ahora: Clock.date

    //  Green until well in, amber when less than half is left and
    //  red when it pays to measure. The cutoffs are the same for all
    //  agents: if each had its own, color would stop meaning.
    function tono(pct) {
        if (pct >= 85) return Theme.red
        if (pct >= 60) return Theme.yellow
        return Theme.green
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

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 11
        anchors.bottomMargin: 12
        spacing: 8

        // ── header ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF06A9)
                color: Theme.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "Agents"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "how much of each quota you have spent"
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── one card per agent ─────────────────────────────────────
        Repeater {
            model: view.plugin.agentes

            delegate: Rectangle {
                id: tarjeta
                required property var modelData

                readonly property var limites: modelData.limites || []

                Layout.fillWidth: true
                Layout.preferredHeight: 40 + 28 * Math.max(1, limites.length)
                radius: 11
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        spacing: 7

                        IslandLabel {
                            text: tarjeta.modelData.nombre
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        IslandLabel {
                            visible: !!tarjeta.modelData.plan
                            text: tarjeta.modelData.plan || ""
                            color: Theme.muted
                            font.pixelSize: 10
                        }

                        IslandLabel {
                            visible: !!tarjeta.modelData.creditos
                            text: "credits " + (tarjeta.modelData.creditos || "")
                            color: Theme.dim
                            font.pixelSize: 9
                        }

                        Item { Layout.fillWidth: true }

                        //  Where the figure came from. Said only
                        //  when it is from the tool's cache, which
                        //  is when it can be hours behind: asked of
                        //  the server, «a moment ago» already says it
                        //  all and adding «live» would be row noise.
                        IslandLabel {
                            visible: tarjeta.modelData.fuente === "cache"
                            text: "cached"
                            color: Theme.dim
                            font.pixelSize: 9
                        }

                        IslandLabel {
                            text: view.frescura(tarjeta.modelData.actualizado, view.ahora)
                            color: Theme.dim
                            font.pixelSize: 9
                        }
                    }

                    //  Installed but never having talked to the server:
                    //  there is no percentage to show and saying so
                    //  is the answer.
                    IslandLabel {
                        visible: !tarjeta.limites.length
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        text: "No data yet — use it once and it will show up"
                        color: Theme.dim
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }

                    Repeater {
                        model: tarjeta.limites

                        delegate: RowLayout {
                            id: fila
                            required property var modelData

                            readonly property real pct: Math.max(0, Math.min(100, modelData.pct || 0))

                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            spacing: 9

                            IslandLabel {
                                text: fila.modelData.nombre
                                //  The one counting now, in ink; the rest, dimmed.
                                color: fila.modelData.activo ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                                font.weight: fila.modelData.activo ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.preferredWidth: 78
                            }

                            K4.Medidor {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                valor: fila.pct
                                maximo: 100
                                grosor: 6
                                tono: view.tono(fila.pct)
                                //  A freshly touched quota is still a
                                //  touched quota: without a minimum,
                                //  0.4% does not show and it looks
                                //  like nothing was spent.
                                minimo: 3
                            }

                            IslandLabel {
                                text: (fila.pct < 10 && fila.pct > 0
                                       ? fila.pct.toFixed(1) : Math.round(fila.pct)) + "%"
                                color: view.tono(fila.pct)
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 40
                            }

                            //  When it forgives you, both ways. No
                            //  gap between the two lines: they are
                            //  the same datum said twice, not two
                            //  different things.
                            ColumnLayout {
                                spacing: 0
                                Layout.preferredWidth: 92
                                Layout.alignment: Qt.AlignVCenter

                                IslandLabel {
                                    text: view.cuando(fila.modelData.reinicia, view.ahora)
                                    color: Theme.muted
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignRight
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 13
                                }

                                IslandLabel {
                                    text: view.cuanto(fila.modelData.reinicia, view.ahora)
                                    color: Theme.dim
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 11
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── while there is nothing to show ─────────────────────────
        IslandLabel {
            visible: !view.plugin.cargado || !view.plugin.agentes.length
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: !view.plugin.cargado
                ? "Looking…"
                : "No agent CLI is installed"
            color: Theme.dim
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
