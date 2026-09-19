// Native Control Center detail; the services outlive this view.
import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../services"

Item {
    id: page
    required property var view
    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: view.plugin.tab === "power-mode" || view.plugin.tab === "night-light"
    property bool counted: false
    property bool choosingCity: false

    function syncVisibility() {
        if (visible === counted) return
        counted = visible
        PowerMode.viewers += visible ? 1 : -1
        NightLight.viewers += visible ? 1 : -1
        if (visible) { PowerMode.refresh(); NightLight.refresh() }
    }
    function timeLabel(stamp) {
        return stamp ? Qt.formatDateTime(new Date(stamp * 1000), "hh:mm") : "—"
    }
    onVisibleChanged: syncVisibility()
    Component.onCompleted: syncVisibility()
    Component.onDestruction: {
        if (counted) { PowerMode.viewers--; NightLight.viewers-- }
        view.plugin.interactionActive = false
    }

    K4.Rodillo {
        objectName: "power-display-scroll"
        anchors.fill: parent
        ColumnLayout {
            width: parent.width
            spacing: 16

            ColumnLayout {
                visible: page.view.plugin.tab === "power-mode"
                Layout.fillWidth: true
                spacing: 10
                RowLayout {
                    spacing: 10
                    IconGlyph { text: String.fromCodePoint(0xF0425); color: Theme.blue; font.pixelSize: 18 }
                    IslandLabel { text: "Choose your power profile"; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: ["power-saver", "balanced", "performance"]
                        delegate: K4.ActionButton {
                            required property string modelData
                            objectName: "profile-" + modelData
                            Layout.fillWidth: true
                            implicitHeight: 76
                            text: PowerMode.label(modelData)
                            selected: PowerMode.state.available && PowerMode.state.profile === modelData
                            enabled: PowerMode.state.available && !PowerMode.busy && PowerMode.state.profiles.indexOf(modelData) >= 0
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: selected
                            contentItem: Column {
                                spacing: 8
                                IconGlyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: String.fromCodePoint(modelData === "power-saver" ? 0xF032A : modelData === "performance" ? 0xF0463 : 0xF05D1)
                                    color: selected ? Theme.blue : Theme.muted
                                    font.pixelSize: 22
                                }
                                IslandLabel {
                                    width: parent.width
                                    text: PowerMode.label(modelData)
                                    color: selected ? Theme.ink : Theme.muted
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            onClicked: PowerMode.setProfile(modelData)
                        }
                    }
                }
                IslandLabel {
                    Layout.fillWidth: true
                    text: !PowerMode.state.available ? "Enable power-profiles-daemon to use power modes."
                        : PowerMode.busy ? "Checking power profile…"
                        : PowerMode.state.profile === "performance" ? "Prioritize speed, with higher power use."
                        : PowerMode.state.profile === "power-saver" ? "Reduce power use and extend battery life."
                        : "Balance performance and power use."
                    color: Theme.muted
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                IslandLabel {
                    visible: !!PowerMode.state.degraded
                    Layout.fillWidth: true
                    text: "Performance limited: " + (PowerMode.state.degraded || "").replace(/-/g, " ")
                    color: Theme.yellow
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: PowerMode.state.holds || []
                    delegate: IslandLabel {
                        required property var modelData
                        Layout.fillWidth: true
                        text: (modelData.ApplicationId || "Application") + ": " + modelData.Reason
                        color: Theme.muted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                IslandLabel {
                    visible: PowerMode.error.length > 0
                    Layout.fillWidth: true
                    text: PowerMode.error
                    color: Theme.red
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                visible: page.view.plugin.tab === "night-light"
                Layout.fillWidth: true
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    IconGlyph { text: String.fromCodePoint(0xF0594); color: Theme.blue; font.pixelSize: 22 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        IslandLabel { text: "A warmer display after dark"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        IslandLabel {
                            Layout.fillWidth: true
                            text: NightLight.summary
                            color: Theme.muted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                    IslandSwitch {
                        objectName: "night-light-switch"
                        checked: Settings.nightLightEnabled
                        Accessible.name: "Enable night light"
                        onToggled: NightLight.setEnabled(!Settings.nightLightEnabled)
                    }
                }
                K4.Deslizador {
                    objectName: "night-light-temperature"
                    Layout.fillWidth: true
                    etiqueta: "Color temperature"
                    valor: Settings.nightLightTemperature
                    desde: 2500
                    hasta: 6500
                    paso: 100
                    sufijo: " K"
                    onMovido: function(value) { NightLight.update("nightLightTemperature", value) }
                    onDraggingChanged: page.view.plugin.interactionActive = dragging
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
                    IconGlyph { text: String.fromCodePoint(0xF0594); color: Theme.muted; font.pixelSize: 14 }
                    IslandLabel { text: "Warmer"; color: Theme.muted; font.pixelSize: 11 }
                    Item { Layout.fillWidth: true }
                    IslandLabel { text: "Less warm"; color: Theme.muted; font.pixelSize: 11 }
                    IconGlyph { text: String.fromCodePoint(0xF0599); color: Theme.muted; font.pixelSize: 14 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    IconGlyph { text: String.fromCodePoint(0xF0150); color: Theme.muted; font.pixelSize: 16 }
                    IslandLabel { text: "Schedule"; Layout.fillWidth: true; font.pixelSize: 12 }
                    K4.ActionButton {
                        objectName: "night-light-manual"
                        text: "Manual"
                        selected: Settings.nightLightMode === "manual"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: selected
                        onClicked: NightLight.setMode("manual")
                    }
                    K4.ActionButton {
                        objectName: "night-light-solar"
                        text: "Sunset to sunrise"
                        selected: Settings.nightLightMode === "solar"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: selected
                        onClicked: NightLight.setMode("solar")
                    }
                }
                ColumnLayout {
                    visible: Settings.nightLightMode === "solar"
                    Layout.fillWidth: true
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        IconGlyph { text: String.fromCodePoint(0xF034E); color: Theme.muted; font.pixelSize: 18 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            IslandLabel {
                                Layout.fillWidth: true
                                text: Settings.nightLightLocation.name
                                    ? Settings.nightLightLocation.name + ", " + Settings.nightLightLocation.country : "Choose your city"
                                elide: Text.ElideRight
                                font.pixelSize: 12
                            }
                            IslandLabel {
                                Layout.fillWidth: true
                                text: !Settings.nightLightLocation.name ? "Save a city to calculate sunrise and sunset offline."
                                    : NightLight.state.polar ? "Polar day/night · schedule follows the sun's position"
                                    : "Sunset " + page.timeLabel(NightLight.state.sunset) + " · Sunrise " + page.timeLabel(NightLight.state.sunrise)
                                        + " · Times shown in your system timezone"
                                color: Theme.muted
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                        K4.ActionButton {
                            text: page.choosingCity ? "Done" : "Choose city"
                            onClicked: page.choosingCity = !page.choosingCity
                        }
                    }
                    ColumnLayout {
                        visible: page.choosingCity || !Settings.nightLightLocation.name
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            K4.TextField {
                                id: cityQuery
                                objectName: "night-light-city"
                                Layout.fillWidth: true
                                placeholderText: "City or postal code"
                                Accessible.name: "Search for a city"
                                enabled: !NightLight.searching
                                onAccepted: NightLight.search(text)
                            }
                            K4.ActionButton {
                                text: NightLight.searching ? "Searching…" : "Search"
                                enabled: !NightLight.searching
                                onClicked: NightLight.search(cityQuery.text)
                            }
                        }
                        Repeater {
                            model: NightLight.cities
                            delegate: K4.ActionButton {
                                required property var modelData
                                Layout.fillWidth: true
                                text: [modelData.name, modelData.admin1, modelData.country].filter(s => s.length > 0).join(", ")
                                onClicked: { NightLight.selectCity(modelData); page.choosingCity = false }
                            }
                        }
                        IslandLabel {
                            visible: NightLight.searchError.length > 0
                            Layout.fillWidth: true
                            text: NightLight.searchError
                            color: Theme.red
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        IslandLabel {
                            Layout.fillWidth: true
                            text: "City search by Open-Meteo · Location data by GeoNames"
                            color: Theme.muted
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        visible: Settings.nightLightEnabled && !!Settings.nightLightLocation.name
                        Layout.fillWidth: true
                        K4.ActionButton {
                            visible: !NightLight.state.overridden
                            enabled: NightLight.state.available && !NightLight.busy && !!NightLight.state.nextBoundary
                            text: (NightLight.state.active ? "Pause until " : "Turn on until ")
                                + (NightLight.state.nextEvent || "next transition")
                            onClicked: NightLight.overrideNow()
                        }
                        K4.ActionButton {
                            visible: !!NightLight.state.overridden
                            text: "Resume schedule"
                            onClicked: NightLight.update("nightLightOverride", {})
                        }
                        IslandLabel {
                            visible: !!NightLight.state.overridden
                            Layout.fillWidth: true
                            text: "Override until " + page.timeLabel(NightLight.state.overrideUntil)
                            color: Theme.muted
                            font.pixelSize: 11
                        }
                    }
                    IslandLabel {
                        text: "Automatic changes fade over 15 minutes around sunrise and sunset."
                        Layout.fillWidth: true
                        color: Theme.muted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                IslandLabel {
                    visible: !NightLight.state.available
                    Layout.fillWidth: true
                    text: "Night light needs the hyprsunset session service. " + (NightLight.state.error || "Connecting…")
                    color: Theme.red
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
