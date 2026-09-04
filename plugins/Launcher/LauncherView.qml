import QtQuick
import QtQuick.Controls
import "../../services"
import QtQuick.Layouts
import K4 as K4
import "../../core"

FadeIn {
    id: view

    required property var plugin

    property int focusAttempts: 0

    Component.onCompleted: {
        view.plugin.rebuild()
        focusAttempts = 0
        focusTimer.start()
        Qt.callLater(function () { launcherInput.forceActiveFocus() })
    }

    // The layer surface takes a moment to receive focus: it is
    // retried a few times instead of assuming it arrived on the
    // first try.
    Timer {
        id: focusTimer
        interval: 140
        onTriggered: {
            if (!view.plugin.open)
                return

            launcherInput.forceActiveFocus()
            if (!launcherInput.activeFocus && view.focusAttempts < 6) {
                view.focusAttempts += 1
                restart()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 40
            spacing: 12

            IconGlyph {
                text: Theme.ico.search
                color: Theme.muted
                font.pixelSize: 20
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.plugin.query.length === 0
                    text: "Search applications"
                    color: Theme.dim
                    font.pixelSize: 19
                }

                TextInput {
                    id: launcherInput
                    cursorDelegate: IslandCursor {}
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 19
                    focus: true
                    activeFocusOnTab: true
                    clip: true
                    selectByMouse: true
                    cursorVisible: true
                    selectionColor: Theme.blue
                    text: view.plugin.query
                    onTextEdited: {
                        view.plugin.query = text
                        view.plugin.rebuild()
                    }

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Escape) {
                            view.plugin.close()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            view.plugin.launchSelected()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            view.plugin.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            view.plugin.moveSelection(-1)
                            event.accepted = true
                        }
                    }
                }
            }

            IslandLabel {
                text: "esc"
                color: Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.surfaceHi
        }

        // ── applications
        ListView {
            //  The house scrollbar: shows only if there is more than
            //  fits.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: view.plugin.matches
            currentIndex: view.plugin.index
            highlightMoveDuration: 140
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: appRow
                required property var modelData
                required property int index

                //  Does it carry its own icon —image or codepoint— or
                //  must one be looked up in the desktop theme by
                //  name?
                readonly property bool propio: !!modelData._imagen
                                            || !!modelData._glifo

                width: ListView.view.width
                height: 42
                radius: 10
                color: index === view.plugin.index ? Theme.surfaceHi : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    //  A system application brings a desktop icon
                    //  name; a plugin's contribution brings its own,
                    //  which is an image or a Nerd Font codepoint.
                    //  They are two different things and that is why
                    //  they are two pieces: one and the same does not
                    //  know how to paint both. Whoever has its own
                    //  icon rules.
                    K4.Icono {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        visible: !appRow.propio
                        source: appRow.modelData.icon.length > 0
                            ? K4.Apps.icono(appRow.modelData.icon, true) : ""
                    }

                    K4.IconoPlugin {
                        visible: appRow.propio
                        imagen: appRow.modelData._imagen || ""
                        glifo: appRow.modelData._glifo || 0
                        tamano: 22
                        color: Theme.ink
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        //  The title, and — for a contributed row that has
                        //  one — its badge: where a package comes from,
                        //  which repository answered. Generic on purpose:
                        //  the launcher renders a badge, not a package.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            IslandLabel {
                                text: appRow.modelData.name
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                visible: !!appRow.modelData._insignia
                                Layout.preferredWidth: insigniaTxt.implicitWidth + 12
                                Layout.preferredHeight: 15
                                Layout.alignment: Qt.AlignVCenter
                                radius: 7
                                color: appRow.modelData._insignia
                                          && appRow.modelData._insignia.acento
                                          ? "#3a2a12" : Theme.surfaceHi

                                IslandLabel {
                                    id: insigniaTxt
                                    anchors.centerIn: parent
                                    text: appRow.modelData._insignia
                                        ? appRow.modelData._insignia.texto : ""
                                    color: appRow.modelData._insignia
                                              && appRow.modelData._insignia.acento
                                              ? "#ff9f0a" : Theme.muted
                                    font.pixelSize: 9
                                }
                            }
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: appRow.modelData.genericName || appRow.modelData.id
                            color: Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    IconGlyph {
                        text: Theme.ico.enter
                        color: Theme.muted
                        font.pixelSize: 14
                        visible: appRow.index === view.plugin.index
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: view.plugin.index = appRow.index
                    onClicked: {
                        view.plugin.index = appRow.index
                        view.plugin.launchSelected()
                    }
                }
            }

            IslandLabel {
                anchors.centerIn: parent
                visible: view.plugin.matches.length === 0
                text: "No results"
                color: Theme.muted
                font.pixelSize: 13
            }
        }


        // ── the updates, on the way ─────────────────────────────────
        //
        //  The launcher is the everyday door, so the notice lives
        //  here — and ONLY when there is something to do: a
        //  permanent foot in a Spotlight-style launcher is furniture
        //  that gets in the way.
        Rectangle {
            id: avisoPaquetes

            //  The packages plugin feeds this; without it (off, or no
            //  backend on this machine) there is simply nothing to say.
            readonly property var paq: view.plugin.packages
            visible: paq && paq.pendientes > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 10
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF06B0)   // md-update
                    color: Theme.yellow
                    font.pixelSize: 13
                }

                IslandLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    //  Guarded in the binding and not just hidden: a false
                    //  `visible` does not stop a text binding from
                    //  evaluating, and the plugin's ref goes null the
                    //  moment it is switched off.
                    text: avisoPaquetes.paq
                        ? `${String(avisoPaquetes.paq.pendientes)} system updates
(${Math.max(0, avisoPaquetes.paq.pendientesRepo)
                                   + " repos · "
                                   + Math.max(0, avisoPaquetes.paq.pendientesAur)
                                   + " AUR"})`
                        : ""
                    color: Theme.muted
                    font.pixelSize: 11
                }

                //  Choosing which: it jumps to the application
                //  centre, where a list with a switch per package
                //  fits. The launcher warns; the fine choosing lives
                //  at the other door.
                Rectangle {
                    Layout.preferredWidth: elegirTexto.implicitWidth + 20
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    border.color: elegirRaton.containsMouse ? Theme.muted
                                                            : Theme.dim

                    IslandLabel {
                        id: elegirTexto
                        anchors.centerIn: parent
                        text: "Choose"
                        font.pixelSize: 10
                        color: elegirRaton.containsMouse ? Theme.ink
                                                         : Theme.muted
                    }

                    MouseArea {
                        id: elegirRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.close()
                            const apps = view.plugin.apps
                            if (apps)
                                apps.openTab("updates")
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: subirTexto.implicitWidth + 20
                    Layout.preferredHeight: 24
                    radius: 12
                    color: subirRaton.containsMouse
                        ? Qt.lighter(Theme.blue, 1.15) : Theme.blue

                    IslandLabel {
                        id: subirTexto
                        anchors.centerIn: parent
                        text: "Update"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: subirRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (view.plugin.packages)
                                view.plugin.packages.updateAll()
                            view.plugin.close()
                        }
                    }
                }
            }
        }
    }
}
