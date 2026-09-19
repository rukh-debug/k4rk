//  The in-house scrollbar, available to plugins.
//
//  Thin, rounded and muted like the island, without a painted track: a
//  permanent line on the dark background adds no information. Position and
//  size changes reveal it for 900 ms; once that timer expires and it is no
//  longer active, hovered or pressed, it fades over 300 ms. Its grab area
//  remains available. This is the SAME scrollbar used throughout the shell,
//  so plugins match the rest without drawing their own.
//
//      ListView {
//          ScrollBar.vertical: K4.Desplazador {}
//      }
//
//  With `K4.Rodillo`, even that is unnecessary: it already includes one.

import QtQuick
import QtQuick.Controls

ScrollBar {
    id: barra

    policy: ScrollBar.AsNeeded
    minimumSize: 0.08

    //  Thin by default and slightly wider under the pointer: grabbing three
    //  pixels should not require perfect aim.
    implicitWidth: 10
    implicitHeight: 10

    //  Reveal on POSITION changes, whoever caused them. `active` alone
    //  proved insufficient: it responds to actual dragging, while many wheel
    //  handlers adjust `contentY` directly, as Rodillo does. Qt does not
    //  treat those assignments as an active scroll interaction.
    property bool asomo: false
    property real _posVista: -1

    onPositionChanged: {
        if (_posVista >= 0 && Math.abs(position - _posVista) > 0.0005) {
            asomo = true
            recogida.restart()
        }
        _posVista = position
    }

    //  Also reveal when overflowing content appears: a scrollable panel
    //  without a scrolling cue looks as though half of it is missing.
    onSizeChanged: if (size > 0 && size < 0.999) {
        asomo = true
        recogida.restart()
    }

    Timer {
        id: recogida
        interval: 900
        onTriggered: barra.asomo = false
    }

    contentItem: Rectangle {
        implicitWidth: barra.hovered || barra.pressed ? 6 : 3
        implicitHeight: implicitWidth
        radius: width / 2
        color: barra.pressed ? Qt.rgba(1, 1, 1, 0.5)
             : barra.hovered ? Qt.rgba(1, 1, 1, 0.35)
                             : Qt.rgba(1, 1, 1, 0.22)

        Behavior on implicitWidth { NumberAnimation { duration: 100 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        //  Visible during movement or interaction, hidden afterward. Apply
        //  opacity here, not to the entire scrollbar: the grab area must
        //  remain available even while its thumb is invisible.
        opacity: barra.asomo || barra.active || barra.hovered || barra.pressed
            ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    background: null
}
