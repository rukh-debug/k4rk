// A font list previews each family while keeping the stored default distinct.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: fonts
    spacing: 8
    readonly property string selected: String(Settings.valor("shellFont") || "")
    readonly property var families: Qt.fontFamilies().slice().sort(function (a, b) {
        return a.localeCompare(b)
    })
    readonly property var filtered: families.filter(function (family) {
        return family.toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0
    })

    IslandLabel {
        Layout.fillWidth: true
        text: "Current font · " + (fonts.selected || "Shell default (Adwaita Sans)")
        color: Theme.muted
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    K4.TextField {
        id: search
        Layout.fillWidth: true
        Accessible.name: "Search fonts"
        placeholderText: "Search fonts"
        Keys.onEscapePressed: function (event) {
            if (text.length > 0) { clear(); event.accepted = true }
            else event.accepted = false
        }
    }
    K4.Baldosa {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: 10
        activa: fonts.selected === ""
        Accessible.name: "Use shell default font"
        onPulsada: Settings.poner("shellFont", "")
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            IconGlyph {
                text: Theme.ico.check
                opacity: fonts.selected === "" ? 1 : 0
                color: Theme.blue
                font.pixelSize: 14
                Layout.preferredWidth: 20
            }
            IslandLabel { Layout.fillWidth: true; text: "Shell default"; font.weight: Font.Medium }
            IslandLabel { text: "Adwaita Sans"; color: Theme.muted; font.pixelSize: 11 }
        }
    }
    IslandLabel {
        text: fonts.filtered.length + " font families"
        color: Theme.muted
        font.pixelSize: 11
        Layout.topMargin: 8
        Layout.bottomMargin: 4
    }
    Repeater {
        model: fonts.filtered
        delegate: K4.Baldosa {
            id: row
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 10
            activa: fonts.selected === modelData
            Accessible.name: "Use " + modelData
            onPulsada: Settings.poner("shellFont", modelData)
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                IconGlyph {
                    text: Theme.ico.check
                    opacity: row.activa ? 1 : 0
                    color: Theme.blue
                    font.pixelSize: 14
                    Layout.preferredWidth: 20
                }
                IslandLabel {
                    Layout.fillWidth: true
                    text: row.modelData
                    font.family: row.modelData
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
        }
    }
    IslandLabel {
        visible: fonts.filtered.length === 0
        Layout.fillWidth: true
        topPadding: 24
        text: "No matching fonts. Try a different name."
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
