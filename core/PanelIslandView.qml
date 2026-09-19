import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../core"
import "../services"
import "../widgets"

FadeIn {
    id: view
    required property var plugin
    property string lastDetail: "wifi"
    property string launchError: ""

    function focusBack() { backButton.forceActiveFocus(Qt.TabFocusReason) }
    function findTile(item, name) {
        if (item.objectName === name && item.visible) return item
        for (let i = 0; i < item.children.length; ++i) {
            const found = view.findTile(item.children[i], name)
            if (found) return found
        }
        return null
    }
    function focusView() {
        if (plugin.tab !== "controls") { focusBack(); return }
        const tile = view.findTile(dashboard.contentItem, "tile-" + lastDetail)
        if (tile && tile.visible) tile.forceActiveFocus(Qt.TabFocusReason)
        else {
            const first = view.findTile(dashboard.contentItem, "tile-wifi")
                || view.findTile(dashboard.contentItem, "tile-bluetooth")
                || view.findTile(dashboard.contentItem, "tile-sound")
                || view.findTile(dashboard.contentItem, "tile-power-mode")
            if (first && first.visible) first.forceActiveFocus(Qt.TabFocusReason)
            else bellButton.forceActiveFocus(Qt.TabFocusReason)
        }
    }
    Component.onCompleted: Qt.callLater(function() { view.focusView() })
    Connections {
        target: view.plugin
        function onTabChanged() {
            if (view.plugin.tab !== "controls") view.lastDetail = view.plugin.tab
            Qt.callLater(function() { view.focusView() })
        }
    }
    Keys.onEscapePressed: function (event) {
        if (Wifi.pskTarget) { Wifi.cancelPsk(); focusBack() }
        else if (plugin.tab !== "controls") plugin.openTab("controls")
        else plugin.close()
        event.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 16
        anchors.bottomMargin: 20
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 10
            K4.Boton {
                id: backButton
                visible: view.plugin.tab !== "controls"
                glifo: Theme.ico.back
                tamano: 16
                color: Theme.muted
                Accessible.name: "Back to control centre"
                onPulsado: view.plugin.openTab("controls")
            }
            IslandLabel {
                Layout.fillWidth: true
                text: view.plugin.tabTitle()
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            K4.ActionButton {
                visible: view.plugin.tab === "notifications" && Notifs.tracked.values.length > 0
                text: "Clear all"
                implicitHeight: 28
                onClicked: Notifs.clear()
            }
            Flickable {
                id: workspaceStrip
                visible: Settings.panelShowWorkspaces && view.plugin.tab === "controls"
                Layout.preferredWidth: Math.min(workspaceRow.implicitWidth, view.width * 0.25)
                Layout.preferredHeight: 28
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                contentWidth: workspaceRow.implicitWidth
                contentHeight: 28
                function revealWorkspace(position) {
                    contentX = Math.max(0, Math.min(position, contentWidth - width))
                }
                function revealCurrentWorkspace() {
                    for (const item of workspaceRow.children)
                        if (item.currentWorkspace) { revealWorkspace(item.x); return }
                }
                Row {
                    id: workspaceRow
                    spacing: 4
                    Repeater {
                        model: Workspaces.shownList
                        delegate: Rectangle {
                            id: workspace
                            required property var modelData
                            readonly property bool currentWorkspace: modelData.focused
                            width: Settings.panelWorkspaceStyle === "numbers" ? 36 : 24
                            height: 28
                            radius: 8
                            color: "transparent"
                            border.width: activeFocus ? 1 : 0
                            border.color: Theme.blue
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Workspace " + Workspaces.label(modelData)
                            function activateWorkspace() {
                                K4.Feedback.click()
                                modelData.activate()
                            }
                            Accessible.onPressAction: activateWorkspace()
                            Keys.onReturnPressed: activateWorkspace()
                            Keys.onEnterPressed: activateWorkspace()
                            Keys.onSpacePressed: activateWorkspace()
                            onActiveFocusChanged: if (activeFocus)
                                workspaceStrip.revealWorkspace(x)
                            onCurrentWorkspaceChanged: if (currentWorkspace)
                                Qt.callLater(workspaceStrip.revealCurrentWorkspace)
                            Rectangle {
                                anchors.centerIn: parent
                                width: Settings.panelWorkspaceStyle === "numbers" ? 32
                                    : workspace.modelData.focused ? 20 : 8
                                height: Settings.panelWorkspaceStyle === "numbers" ? 20 : 8
                                radius: height / 2
                                color: workspace.modelData.focused ? Theme.ink : Theme.surfaceHi
                                IslandLabel {
                                    anchors.fill: parent
                                    anchors.leftMargin: 3
                                    anchors.rightMargin: 3
                                    visible: Settings.panelWorkspaceStyle === "numbers"
                                    text: Workspaces.label(workspace.modelData)
                                    color: workspace.modelData.focused ? Theme.islandBg : Theme.muted
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { workspace.forceActiveFocus(); workspace.activateWorkspace() }
                                onWheel: function (event) {
                                    workspaceStrip.contentX = Math.max(0, Math.min(
                                        workspaceStrip.contentWidth - workspaceStrip.width,
                                        workspaceStrip.contentX - event.angleDelta.y / 120 * 48))
                                }
                            }
                        }
                    }
                }
            }
            IslandLabel {
                visible: Settings.panelShowClock && view.plugin.tab === "controls"
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                color: Theme.muted
                font.pixelSize: 13
            }
            K4.Boton {
                id: bellButton
                glifo: Notifs.count > 0 ? Theme.ico.bell : Theme.ico.bellOutline
                tamano: 16
                color: view.plugin.tab === "notifications" ? Theme.ink : Theme.muted
                Accessible.name: "Notifications, " + Notifs.count + " unread"
                onPulsado: view.plugin.openTab(view.plugin.tab === "notifications" ? "controls" : "notifications")
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Theme.blue
                    visible: Notifs.count > 0
                }
            }
            K4.Boton {
                glifo: Theme.ico.close
                tamano: 16
                color: Theme.muted
                Accessible.name: "Close control centre"
                onPulsado: view.plugin.close()
            }
        }

        // The header stays fixed; unusually tall card collections scroll inside it.
        K4.Rodillo {
            id: dashboard
            visible: view.plugin.tab === "controls"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                width: parent.width
                spacing: 16
                Repeater {
                    model: Settings.panelOrdenEfectivo
                    delegate: Loader {
                        required property var modelData
                        width: parent.width
                        height: active ? view.plugin.altoDe(modelData) : 0
                        visible: active
                        active: view.plugin.tab === "controls" && Settings.bloqueVisible(modelData)
                        sourceComponent: modelData === "toggles" ? quickControls
                            : modelData === "power-display" ? powerDisplay
                            : modelData === "media" ? media
                            : modelData === "shortcuts" ? shortcuts
                            : String(modelData).indexOf(".") > 0
                              ? Enganches.componenteDeCard(String(modelData).split(".")[0],
                                  String(modelData).split(".")[1]) : null
                    }
                }
                IslandLabel {
                    width: parent.width
                    visible: view.launchError.length > 0
                    text: view.launchError
                    color: Theme.red
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item {
            visible: view.plugin.tab === "notifications"
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
                id: notifications
                anchors.fill: parent
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: IslandScrollBar {}
                model: Notifs.tracked
                delegate: K4.Baldosa {
                    id: notification
                    required property var modelData
                    required property int index
                    readonly property var actions: Notifs.buttons(modelData)
                    readonly property string image: Notifs.iconFor(modelData)
                    width: ListView.view.width
                    height: notificationContent.implicitHeight + 24
                    radius: 12
                    Accessible.name: modelData.appName + ": " + modelData.summary
                    onPulsada: Notifs.activate(modelData)
                    onActiveFocusChanged: if (activeFocus)
                        notifications.positionViewAtIndex(index, ListView.Contain)
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        Image {
                            source: notification.image
                            visible: status === Image.Ready
                            sourceSize.width: 40
                            sourceSize.height: 40
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignTop
                            fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                            id: notificationContent
                            Layout.fillWidth: true
                            spacing: 4
                            IslandLabel {
                                Layout.fillWidth: true
                                text: notification.modelData.appName
                                color: Theme.muted
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            IslandLabel {
                                Layout.fillWidth: true
                                text: notification.modelData.summary
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                            }
                            IslandLabel {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: notification.modelData.body
                                color: Theme.muted
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.preferredHeight: implicitHeight
                                Layout.topMargin: visible ? 4 : 0
                                visible: notification.actions.length > 0
                                spacing: 8
                                Repeater {
                                    model: notification.actions
                                    delegate: K4.ActionButton {
                                        required property var modelData
                                        text: modelData.text
                                        width: Math.min(implicitWidth, parent.width)
                                        onClicked: Notifs.invokeAction(notification.modelData, modelData)
                                    }
                                }
                            }
                        }
                        K4.Boton {
                            Layout.alignment: Qt.AlignTop
                            glifo: Theme.ico.close
                            tamano: 16
                            color: Theme.muted
                            Accessible.name: "Dismiss " + notification.modelData.summary
                            onPulsado: notification.modelData.dismiss()
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: Notifs.tracked.values.length === 0
                    spacing: 10
                    IconGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Theme.ico.bellOutline
                        color: Theme.muted
                        font.pixelSize: 24
                    }
                    IslandLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "You're all caught up"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    IslandLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "New notifications will appear here"
                        color: Theme.muted
                        font.pixelSize: 11
                    }
                }
            }
        }
        DetalleWifi { view: view }
        DetalleBluetooth { view: view }
        DetalleSonido { view: view }
        DetalleSistema { view: view }
        PowerDisplayDetail { view: view }
        Loader {
            visible: active
            active: view.plugin.tab.indexOf("card:") === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: active ? Enganches.cardDetail(view.plugin.tab.slice(5)) : null
        }
    }

    component RadioTile: IslandTile {
        id: radio
        property string label
        property string status
        property string glyph
        property bool checked
        property bool available: true
        signal toggled()
        radius: 14
        Accessible.name: "Open " + label + " details"
        Accessible.description: status
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12
            K4.Boton {
                glifo: radio.glyph
                tamano: 18
                implicitWidth: 36
                implicitHeight: 36
                color: radio.checked ? Theme.blue : Theme.muted
                activo: radio.available
                Accessible.role: Accessible.CheckBox
                Accessible.checked: radio.checked
                Accessible.name: (radio.checked ? "Turn off " : "Turn on ") + radio.label
                Accessible.onToggleAction: if (radio.available) pulsado()
                onPulsado: radio.toggled()
                Rectangle {
                    anchors.fill: parent
                    z: -1
                    radius: 12
                    color: radio.checked ? Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.14)
                        : Theme.surfaceHi
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                IslandLabel {
                    Layout.fillWidth: true
                    text: radio.label
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                IslandLabel {
                    Layout.fillWidth: true
                    text: radio.status
                    color: Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            IconGlyph { text: Theme.ico.forward; color: Theme.muted; font.pixelSize: 14 }
        }
    }

    Component {
        id: quickControls
        GridLayout {
            columns: 2
            columnSpacing: 12
            rowSpacing: 12
            RadioTile {
                objectName: "tile-wifi"
                visible: Settings.panelTileWifi
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.row: 0
                Layout.column: 0
                Layout.columnSpan: view.plugin.radioCount === 1 ? 2 : 1
                Layout.preferredHeight: 96
                Layout.minimumWidth: 0
                label: "Wi-Fi"
                status: !Wifi.device ? "Unavailable" : !Wifi.activada ? "Off" : Wifi.name
                checked: Wifi.activada
                available: !!Wifi.device
                glyph: checked ? Theme.ico.wifi : Theme.ico.wifiOff
                onToggled: Wifi.activada = !Wifi.activada
                onPulsada: view.plugin.openTab("wifi")
            }
            RadioTile {
                objectName: "tile-bluetooth"
                visible: Settings.panelTileBluetooth
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.row: 0
                Layout.column: Settings.panelTileWifi ? 1 : 0
                Layout.columnSpan: view.plugin.radioCount === 1 ? 2 : 1
                Layout.preferredHeight: 96
                Layout.minimumWidth: 0
                label: "Bluetooth"
                status: !Bt.adapter ? "Unavailable" : !Bt.adapter.enabled ? "Off" : Bt.summary
                checked: !!Bt.adapter && Bt.adapter.enabled
                available: !!Bt.adapter
                glyph: checked ? Theme.ico.bluetooth : Theme.ico.bluetoothOff
                onToggled: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
                onPulsada: view.plugin.openTab("bluetooth")
            }
            IslandTile {
                objectName: "sound-card"
                visible: Settings.panelTileSound
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 120
                Layout.minimumWidth: 0
                Layout.row: view.plugin.radioCount ? 1 : 0
                Layout.column: 0
                Layout.columnSpan: view.plugin.sliderCount === 1 ? 2 : 1
                radius: 14
                pulsable: false
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    Item {
                        id: soundHeader
                        objectName: "tile-sound"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Open sound details"
                        function openDetails() {
                            K4.Feedback.click()
                            view.plugin.openTab("sound")
                        }
                        Accessible.onPressAction: openDetails()
                        Keys.onReturnPressed: openDetails()
                        Keys.onEnterPressed: openDetails()
                        Keys.onSpacePressed: openDetails()
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 6
                            color: soundPointer.containsMouse ? Theme.surfaceHi : "transparent"
                            border.width: soundHeader.activeFocus ? 1 : 0
                            border.color: Theme.blue
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 10
                            IslandLabel { text: "Sound"; font.pixelSize: 13; font.weight: Font.Medium }
                            IslandLabel {
                                Layout.fillWidth: true
                                text: Audio.salidaActiva ? Audio.nombreDe(Audio.salidaActiva) : "No output"
                                color: Theme.muted
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            IconGlyph { text: Theme.ico.forward; color: Theme.muted; font.pixelSize: 14 }
                        }
                        MouseArea {
                            id: soundPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                soundHeader.forceActiveFocus(Qt.MouseFocusReason)
                                soundHeader.openDetails()
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        K4.Boton {
                            glifo: Audio.muted ? Theme.ico.volOff : Theme.ico.volMed
                            implicitWidth: 28
                            implicitHeight: 28
                            tamano: 14
                            color: Audio.muted ? Theme.muted : Theme.ink
                            activo: !!Audio.salidaActiva && !!Audio.salidaActiva.audio
                            Accessible.name: Audio.muted ? "Unmute output" : "Mute output"
                            onPulsado: Audio.toggleMute()
                        }
                        K4.Deslizador {
                            objectName: "sound-slider"
                            Layout.fillWidth: true
                            enabled: !!Audio.salidaActiva && !!Audio.salidaActiva.audio
                            Accessible.name: "Output volume"
                            valor: Audio.volume
                            sufijo: "%"
                            onMovido: function (value) { Audio.setVolume(value) }
                            onDraggingChanged: view.plugin.interactionActive = dragging
                            Component.onDestruction: view.plugin.interactionActive = false
                        }
                        IslandLabel {
                            text: Audio.salidaActiva ? Audio.volume + "%" : "—"
                            color: Audio.volume > 100 ? Theme.yellow : Theme.muted
                            font.pixelSize: 11
                            Layout.preferredWidth: 36
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                    IslandLabel {
                        Layout.fillWidth: true
                        text: Audio.muted ? "Output muted" : "Output volume"
                        color: Theme.muted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
            BrightnessControl {
                objectName: "brightness-card"
                panel: view.plugin
                visible: Settings.panelTileBrightness
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 120
                Layout.minimumWidth: 0
                Layout.row: view.plugin.radioCount ? 1 : 0
                Layout.column: Settings.panelTileSound ? 1 : 0
                Layout.columnSpan: view.plugin.sliderCount === 1 ? 2 : 1
            }
        }
    }

    component DetailTile: IslandTile {
        id: detailTile
        property string title
        property string status
        property string glyph
        property string destination
        objectName: "tile-" + destination
        radius: 14
        Accessible.name: "Open " + title + " details"
        Accessible.description: status
        onPulsada: view.plugin.openTab(destination)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 12
                color: Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.14)
                IconGlyph { anchors.centerIn: parent; text: detailTile.glyph; color: Theme.blue; font.pixelSize: 18 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                IslandLabel { text: detailTile.title; font.pixelSize: 13; font.weight: Font.Medium }
                IslandLabel {
                    Layout.fillWidth: true
                    text: detailTile.status
                    color: Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            IconGlyph { text: Theme.ico.forward; color: Theme.muted; font.pixelSize: 14 }
        }
    }
    Component {
        id: powerDisplay
        RowLayout {
            spacing: 12
            DetailTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                title: "Power mode"
                status: PowerMode.summary
                glyph: PowerMode.state.profile === "power-saver" ? String.fromCodePoint(0xF032A)
                    : PowerMode.state.profile === "performance" ? String.fromCodePoint(0xF0463) : String.fromCodePoint(0xF05D1)
                destination: "power-mode"
            }
            DetailTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                title: "Night light"
                status: NightLight.summary.replace("Night light ", "")
                glyph: String.fromCodePoint(0xF0594)
                destination: "night-light"
            }
        }
    }
    Component {
        id: media
        Item {
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.surface
            }
            RowLayout {
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                spacing: 12
                Artwork {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    placeholder: Theme.surface
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    IslandLabel {
                        Layout.fillWidth: true
                        text: Media.hasPlayer && Media.activePlayer.trackTitle.length > 0
                            ? Media.activePlayer.trackTitle : "Nothing playing"
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    IslandLabel {
                        Layout.fillWidth: true
                        text: Media.hasPlayer ? (Media.activePlayer.trackArtist || Media.activePlayer.identity)
                            : "Play something to see it here"
                        color: Theme.muted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                K4.Boton {
                    glifo: Theme.ico.prev; tamano: 16; color: Theme.muted
                    activo: Media.hasPlayer && Media.activePlayer.canGoPrevious
                    Accessible.name: "Previous track"
                    onPulsado: Media.activePlayer.previous()
                }
                K4.Boton {
                    glifo: Media.isPlaying ? Theme.ico.pause : Theme.ico.play
                    tamano: 18
                    implicitWidth: 36
                    implicitHeight: 36
                    activo: Media.hasPlayer && Media.activePlayer.canTogglePlaying
                    Accessible.name: Media.isPlaying ? "Pause playback" : "Start playback"
                    onPulsado: Media.activePlayer.togglePlaying()
                    Rectangle {
                        anchors.fill: parent
                        z: -1
                        radius: 18
                        color: Theme.surfaceHi
                    }
                }
                K4.Boton {
                    glifo: Theme.ico.next; tamano: 16; color: Theme.muted
                    activo: Media.hasPlayer && Media.activePlayer.canGoNext
                    Accessible.name: "Next track"
                    onPulsado: Media.activePlayer.next()
                }
            }
        }
    }
    Component {
        id: shortcuts
        AccesosDirectos {
            onDraggingChanged: view.plugin.interactionActive = dragging
            Component.onDestruction: view.plugin.interactionActive = false
            onAbrir: function (id) {
                if (SurfaceRegistry.abrirAplicacion(id)) {
                    view.launchError = ""
                    view.plugin.close()
                } else view.launchError = "This application is unavailable."
            }
        }
    }
}
