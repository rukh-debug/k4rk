//  The shell's typeface, chosen from the families the system has.
//
//  A list page and not a dropdown on a row: fonts are a thing you JUDGE by
//  looking, dozens at a time, and a dropdown shows one candidate per click.
//  Here every row is set in the family it names — the list is its own
//  preview — and picking one re-letters the whole bar on the spot, labels
//  and search fields and all, because they all follow `Theme.uiFont`.
//
//  The filter is not decoration: a Nix system carries hundreds of families,
//  and «I want the one called something like Jost» is a search, not a
//  stroll.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: fuentes

    spacing: 10

    //  What the filter field holds. Empty is everything.
    property string filtro: ""

    //  The family in force right now, resolved the same way `Theme` resolves
    //  it: the stored one if any, the shell's default otherwise. Reading the
    //  stored value alone would mark nothing when you are on the default.
    readonly property string enUso: {
        const v = Settings.valor("shellFont")
        return typeof v === "string" && v.length > 0
            ? v : Theme.uiFont
    }

    //  Every family the system has, alphabetical. `Qt.fontFamilies()` is
    //  Qt's own question to fontconfig — no process, no parsing, and the
    //  answer matches what a Text can actually use.
    readonly property var familias: {
        const lista = []
        const todas = Qt.fontFamilies()
        for (let i = 0; i < todas.length; ++i)
            lista.push(String(todas[i]))
        lista.sort(function (a, b) {
            return a.localeCompare(b)
        })
        return lista
    }

    //  ── the filter ──────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: campoFuente.activeFocus ? Theme.blue : "transparent"

        Behavior on border.color { ColorAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 9
            spacing: 8

            IconGlyph {
                text: Theme.ico.search
                color: campoFuente.activeFocus ? Theme.muted : Theme.dim
                font.pixelSize: 13
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: campoFuente.text.length === 0
                    text: "Search fonts"
                    color: Theme.dim
                    font.pixelSize: 12
                }

                TextInput {
                    id: campoFuente
                    anchors.fill: parent
                    cursorDelegate: IslandCursor {}
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 12
                    clip: true
                    selectByMouse: true
                    selectionColor: Theme.blue
                    onTextEdited: fuentes.filtro = text

                    Keys.onEscapePressed: {
                        text = ""
                        fuentes.filtro = ""
                    }
                }
            }
        }
    }

    //  ── the shell's own default ─────────────────────────────
    //
    //  A row of its own and first: the way back should not depend on
    //  finding one family among hundreds. Picking it stores nothing —
    //  «no choice» is the default, and a stored default would survive a
    //  change of heart in the shell itself.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        radius: 9
        color: fuentes.enUso === "Adwaita Sans"
            ? Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.15)
            : (ratonDefecto.containsMouse ? Qt.rgba(1, 1, 1, 0.05)
                                          : Theme.surface)

        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: ratonDefecto
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Settings.poner("shellFont", "")
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            IconGlyph {
                text: Theme.ico.check
                color: fuentes.enUso === "Adwaita Sans" ? Theme.blue
                                                        : Theme.dim
                font.pixelSize: 13
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: "Shell default"
                color: fuentes.enUso === "Adwaita Sans" ? Theme.ink
                                                       : Theme.muted
                font.pixelSize: 12
                font.weight: fuentes.enUso === "Adwaita Sans"
                    ? Font.DemiBold : Font.Normal
            }

            IslandLabel {
                Layout.alignment: Qt.AlignVCenter
                text: "Adwaita Sans"
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }

    //  ── the families ────────────────────────────────────────
    Repeater {
        model: {
            const q = fuentes.filtro.trim().toLowerCase()
            if (q.length === 0)
                return fuentes.familias
            return fuentes.familias.filter(function (f) {
                return f.toLowerCase().indexOf(q) >= 0
            })
        }

        delegate: Rectangle {
            id: filaFuente
            required property var modelData

            readonly property bool puesta:
                fuentes.enUso === filaFuente.modelData

            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 9
            color: puesta
                ? Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.15)
                : (ratonFuente.containsMouse ? Qt.rgba(1, 1, 1, 0.05)
                                             : Theme.surface)

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
                id: ratonFuente
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Settings.poner("shellFont", filaFuente.modelData)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                IconGlyph {
                    text: Theme.ico.check
                    visible: filaFuente.puesta
                    color: Theme.blue
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 13
                }

                //  Set in its own family: the row IS the preview, and the
                //  name is the sample. `Theme.uiFont` is what the rest of
                //  the row uses, so only this label changes clothes.
                IslandLabel {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: filaFuente.modelData
                    textFormat: Text.PlainText
                    font.family: filaFuente.modelData
                    font.pixelSize: 13
                    color: filaFuente.puesta ? Theme.ink : Theme.muted
                    elide: Text.ElideRight
                }
            }
        }
    }

    IslandLabel {
        visible: fuentes.familias.length === 0
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        topPadding: 20
        text: "No font families found"
        color: Theme.dim
        font.pixelSize: 12
    }
}
