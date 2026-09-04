import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    required property var plugin

    //  Whether a centre block is on show, by id. The rule itself lives
    //  in Settings — `bloqueVisible` — because three read it (this
    //  view, the height count in the plugin, and the editor's sketch),
    //  and a rule told three ways drifts.
    function editorVisibilidad(id) {
        return Settings.bloqueVisible(id)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 20
        spacing: 12

        // ── header
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 10

            MediaButton {
                visible: view.plugin.tab !== "controls"
                glyph: Theme.ico.back
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: {
                    Wifi.cancelPsk()
                    view.plugin.tab = "controls"
                }
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: view.plugin.tab === "notifications" ? "Notifications"
                    : view.plugin.tab === "wifi" ? "Wi‑Fi"
                    : view.plugin.tab === "bluetooth" ? "Bluetooth"
                    : view.plugin.tab === "sound" ? "Sound"
                    : "Control centre"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                visible: view.plugin.tab === "notifications" && Notifs.tracked.values.length > 0
                Layout.preferredWidth: clearAllFila.implicitWidth + 20
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                // Red on hover and with its icon: in gray on gray and
                // without a symbol it looked like one more label, not
                // something clickable.
                color: clearAllMouse.containsMouse ? Theme.red : Theme.surfaceHi

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: clearAllFila
                    anchors.centerIn: parent
                    spacing: 5

                    IconGlyph {
                        text: Theme.ico.clearAll
                        color: clearAllMouse.containsMouse ? Theme.ink : Theme.muted
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        id: clearAllLabel
                        text: "Clear all"
                        color: clearAllMouse.containsMouse ? Theme.ink : Theme.muted
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: clearAllMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.clear()
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                id: deskRow
                spacing: 5
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter

                //  One size for every bubble: the widest label in the
                //  roster, weighed in both dresses (the focused digit
                //  goes DemiBold and pays for it). A bubble that grows
                //  with its focus shoves the whole row sideways at every
                //  desk switch — uniform bubbles move nothing.
                readonly property real bubbleWidth: {
                    let w = 0
                    for (let i = 0; i < Workspaces.shownList.length; ++i) {
                        const texto = Workspaces.label(Workspaces.shownList[i])
                        w = Math.max(w, numberMetric.advanceWidth(texto),
                                        focusMetric.advanceWidth(texto))
                    }
                    return Math.max(18, w + 12)
                }

                FontMetrics {
                    id: numberMetric
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                }
                FontMetrics {
                    id: focusMetric
                    font.family: Theme.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: Workspaces.shownList

                    delegate: Rectangle {
                        //  The desks in the header are decoration, and the
                        //  header is theirs to dress: the Control Centre
                        //  page can turn them off, and the same page picks
                        //  their dress — a dot per desk, or its number.
                        id: sitio
                        visible: Settings.panelShowWorkspaces
                        required property var modelData
                        readonly property bool numeros:
                            Settings.panelWorkspaceStyle === "numbers"

                        Layout.preferredWidth: numeros
                            ? deskRow.bubbleWidth
                            : (modelData.focused ? 24 : 8)
                        Layout.preferredHeight: numeros ? 18 : 8
                        radius: numeros ? 9 : 4
                        color: modelData.focused ? Theme.ink : Theme.surfaceHi

                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        IslandLabel {
                            id: numero
                            anchors.centerIn: parent
                            visible: sitio.numeros
                            text: Workspaces.label(sitio.modelData)
                            color: sitio.modelData.focused
                                ? Theme.islandBg : Theme.muted
                            font.pixelSize: 10
                            font.weight: sitio.modelData.focused
                                ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.modelData.activate()
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            IslandLabel {
                //  The header's other decoration; same page, same switch.
                visible: Settings.panelShowClock
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                color: Theme.muted
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Notifs.count > 0 ? Theme.ico.bell : Theme.ico.bellOutline
                glyphSize: 15
                glyphColor: view.plugin.tab === "notifications" ? Theme.ink : Theme.muted
                Layout.alignment: Qt.AlignVCenter
                onActivated: {
                    view.plugin.tab = view.plugin.tab === "notifications" ? "controls" : "notifications"
                    if (view.plugin.tab === "notifications")
                        Notifs.markRead()
                }
            }

            MediaButton {
                glyph: Theme.ico.chevronUp
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── the centre's blocks, in the stored order ───────────
        //
        //  `Layout.order` does not exist in this QtQuick.Layouts, so the
        //  order is the MODEL's: one Repeater over panelOrdenEfectivo, one
        //  Loader per slot picking its block's Component. Moving a block is
        //  rewriting the list, and the column follows on the next polish.
        Repeater {
            model: Settings.panelOrdenEfectivo

            delegate: Loader {
                id: hueco
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: view.plugin.altoDe(hueco.modelData)
                //  Only while the tab is controls AND the block is on show —
                //  a hidden block is no height at all, and the centre's own
                //  height counts on this staying honest (alturaControles).
                visible: view.plugin.tab === "controls"
                         && editorVisibilidad(hueco.modelData)
                //  The native blocks are parked here as Components; a
                //  card ("<plugin>.<name>", the dot gives it away) is
                //  asked to the registry BY NAME — a Component that
                //  travelled inside a modelData copy does not
                //  instantiate.
                sourceComponent: hueco.modelData === "toggles" ? compToggles
                    : hueco.modelData === "media" ? compMedia
                    : hueco.modelData === "shortcuts" ? compAccesos
                    : String(hueco.modelData).indexOf(".") > 0
                      ? Enganches.componenteDeCard(
                            String(hueco.modelData).split(".")[0],
                            String(hueco.modelData).split(".")[1])
                      : null
            }
        }

        //  ── the blocks themselves, parked as Components ─────────
        //
        //  They keep their insides exactly as they were; what they lose is
        //  their Layout.* attacheds, because a Loader's loaded item is not
        //  the layout's child — the LOADER is, and it carries the sizes.
        Component {
            id: compToggles

            //  Only while some tile is on show: a row of three hidden tiles
            //  is a 78 px hole.
            RowLayout {
                width: parent.width
                height: parent.height
                spacing: 10

                IslandTile {
                    id: wifiTile
                    visible: Settings.panelTileWifi
                    Layout.fillWidth: true
                Layout.fillHeight: true
                // the icon's circle carries its own MouseArea on top,
                // so clicking it toggles the radio and the rest opens
                // the detail
                onPulsada: view.plugin.openTab("wifi")

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: Wifi.activada ? Theme.blue : Theme.surfaceHi

                            Behavior on color { ColorAnimation { duration: 180 } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: Wifi.activada ? Theme.ico.wifi : Theme.ico.wifiOff
                                font.pixelSize: 15
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Wifi.activada = !Wifi.activada
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Layout.fillHeight: false

                            IslandLabel { text: "Wi‑Fi"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            IslandLabel {
                                text: Wifi.activada ? Wifi.name : "Disabled"
                                color: Theme.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        IconGlyph {
                            text: Theme.ico.forward
                            color: wifiTile.hovered ? Theme.ink : Theme.dim
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            IslandTile {
                id: btTile
                visible: Settings.panelTileBluetooth
                Layout.fillWidth: true
                Layout.fillHeight: true
                onPulsada: view.plugin.openTab("bluetooth")

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: Bt.adapter && Bt.adapter.enabled ? Theme.blue : Theme.surfaceHi

                            Behavior on color { ColorAnimation { duration: 180 } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: Bt.adapter && Bt.adapter.enabled
                                    ? Theme.ico.bluetooth : Theme.ico.bluetoothOff
                                font.pixelSize: 15
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Layout.fillHeight: false

                            IslandLabel { text: "Bluetooth"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            IslandLabel {
                                text: Bt.adapter
                                    ? (Bt.adapter.enabled ? "Enabled" : "Disabled")
                                    : "No adapter"
                                color: Theme.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        IconGlyph {
                            text: Theme.ico.forward
                            color: btTile.hovered ? Theme.ink : Theme.dim
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            IslandTile {
                id: sonidoTile
                visible: Settings.panelTileSound
                Layout.fillWidth: true
                Layout.fillHeight: true
                //  The slider takes almost the whole tile and has its
                //  own mouse; what is left —the title row— opens the
                //  detail, same as in the Wi‑Fi one.
                onPulsada: view.plugin.openTab("sound")

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 8

                        IslandLabel { text: "Sound"; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        IslandLabel {
                            //  Which device is playing, which is what
                            //  one comes to look at here; the bar
                            //  already says the volume.
                            text: Audio.salidaActiva
                                ? Audio.nombreDe(Audio.salidaActiva)
                                : (Audio.muted ? "Muted" : Audio.volume + "%")
                            color: Theme.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                        }

                        IconGlyph {
                            text: Theme.ico.forward
                            color: sonidoTile.hovered ? Theme.ink : Theme.dim
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26

                        Rectangle {
                            id: volumeSliderTrack
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 26
                            radius: 13
                            color: Theme.surfaceHi
                            clip: true

                            Rectangle {
                                width: volumeSliderTrack.width * Math.max(0, Math.min(100, Audio.volume)) / 100
                                height: parent.height
                                radius: parent.radius
                                color: Audio.muted ? Theme.dim : Theme.ink

                                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            IconGlyph {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: Audio.muted ? Theme.ico.volOff : Theme.ico.volMed
                                color: Audio.volume > 12 && !Audio.muted ? "#000000" : Theme.muted
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function (mouse) { Audio.setVolume(mouse.x / width * 100) }
                            onPositionChanged: function (mouse) {
                                if (pressed)
                                    Audio.setVolume(mouse.x / width * 100)
                            }
                        }
                    }
                }
            }
        }
        }

        // ── playback, compact ─────────────────────────────────────
        // It used to take half a tab with a 52 px cover. In macOS's
        // control centre "Playing" is a discreet row, not the
        // protagonist: here it drops to 62 px tall and gains the
        // whole width.
        Component {
            id: compMedia

            IslandTile {
                width: parent.width
                height: parent.height
                pulsable: false

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 12

                Artwork {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    placeholder: Theme.surfaceHi
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    IslandLabel {
                        Layout.fillWidth: true
                        text: Media.hasPlayer && Media.activePlayer.trackTitle.length > 0
                            ? Media.activePlayer.trackTitle : "Nothing playing"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: Media.hasPlayer ? Media.activePlayer.trackArtist : ""
                        color: Theme.muted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Visualizer {
                    visible: Media.isPlaying
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 12
                    Layout.rightMargin: 2
                }

                MediaButton {
                    glyph: Theme.ico.prev
                    glyphSize: 16
                    glyphColor: Theme.muted
                    enabledAction: Media.hasPlayer && Media.activePlayer.canGoPrevious
                    onActivated: Media.activePlayer.previous()
                    Layout.alignment: Qt.AlignVCenter
                }

                MediaButton {
                    glyph: Media.isPlaying ? Theme.ico.pause : Theme.ico.play
                    glyphSize: 21
                    enabledAction: Media.hasPlayer && Media.activePlayer.canTogglePlaying
                    onActivated: Media.activePlayer.togglePlaying()
                    Layout.alignment: Qt.AlignVCenter
                }

                MediaButton {
                    glyph: Theme.ico.next
                    glyphSize: 16
                    glyphColor: Theme.muted
                    enabledAction: Media.hasPlayer && Media.activePlayer.canGoNext
                    onActivated: Media.activePlayer.next()
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
        }

        // ── shortcuts ──────────────────────────────────────────────
        //
        //  Whatever the user pinned, with its icon and name taken
        //  from the catalog, and at the end the button opening the
        //  whole drawer. They get pinned with the application
        //  center's pin and reordered by dragging them right here,
        //  where they are seen.
        Component {
            id: compAccesos

            AccesosDirectos {
                width: parent.width
                height: altura

            onAbrir: function (id) {
                view.plugin.close()
                PluginManager.abrirAplicacion(id)
            }
        }
        }

        // ── the notifications tab
        IslandTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            pulsable: false
            visible: view.plugin.tab === "notifications"

            ListView {
                //  The house scrollbar: comes out on its own when
                //  there is more than fits.
                ScrollBar.vertical: IslandScrollBar {}
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                spacing: 8
                model: Notifs.tracked

                delegate: Rectangle {
                    id: notificationCard
                    required property var modelData
                    readonly property var actions: Notifs.buttons(modelData)
                    readonly property string icon: Notifs.iconFor(modelData)

                    width: ListView.view.width
                    height: notificationBody.implicitHeight + 22
                        + (actions.length > 0 ? 28 : 0)
                    radius: 12
                    color: cardMouse.containsMouse ? "#38383a" : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Besides taking you to the application, it
                    // swallows clicks so a miss near the ✕ does not
                    // reach the island's background (which would
                    // close the panel).
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.activate(notificationCard.modelData)
                    }

                    Image {
                        id: cardIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 20
                        height: 20
                        source: notificationCard.icon
                        sourceSize.width: 40
                        sourceSize.height: 40
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }

                    Column {
                        id: notificationBody
                        anchors.left: cardIcon.visible ? cardIcon.right : parent.left
                        anchors.right: closeButton.left
                        anchors.top: parent.top
                        anchors.topMargin: 11
                        anchors.leftMargin: cardIcon.visible ? 10 : 14
                        anchors.rightMargin: 10
                        spacing: 2

                        IslandLabel {
                            text: notificationCard.modelData.appName
                            color: Theme.muted
                            font.pixelSize: 10
                        }
                        IslandLabel {
                            text: notificationCard.modelData.summary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        IslandLabel {
                            text: notificationCard.modelData.body
                            color: Theme.muted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            width: parent.width
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    // the buttons the application sends
                    Row {
                        anchors.left: notificationBody.left
                        anchors.top: notificationBody.bottom
                        anchors.topMargin: 6
                        spacing: 6
                        visible: notificationCard.actions.length > 0

                        Repeater {
                            model: notificationCard.actions

                            delegate: Rectangle {
                                id: cardAction
                                required property var modelData
                                width: Math.min(cardActionLabel.implicitWidth + 20, 160)
                                height: 22
                                radius: 11
                                color: cardActionMouse.containsMouse ? Theme.blue : Theme.track

                                Behavior on color { ColorAnimation { duration: 120 } }

                                IslandLabel {
                                    id: cardActionLabel
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: cardAction.modelData.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: cardActionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.invokeAction(notificationCard.modelData,
                                                                   cardAction.modelData)
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: closeButton
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 15
                        color: closeMouse.containsMouse ? Theme.track : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IconGlyph {
                            anchors.centerIn: parent
                            text: Theme.ico.close
                            color: closeMouse.containsMouse ? Theme.ink : Theme.muted
                            font.pixelSize: 15
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notificationCard.modelData.dismiss()
                        }
                    }
                }

                IslandLabel {
                    anchors.centerIn: parent
                    visible: Notifs.tracked.values.length === 0
                    text: "No notifications"
                    color: Theme.muted
                    font.pixelSize: 12
                }
            }
        }

        // ── the Wi‑Fi detail, in its own piece
        DetalleWifi { view: view }

        // ── detalle Bluetooth, en su propia pieza
        DetalleBluetooth { view: view }

        // ── the Sound detail: where it comes out and where it goes in
        DetalleSonido { view: view }
    }
}
