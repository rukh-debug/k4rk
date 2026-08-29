//  A zone that scrolls with a real mouse wheel, even when there are
//  clickable things inside.
//
//  It exists because of a trap that has bitten this bar twice: a MouseArea
//  **accepts wheel events whether or not it has a handler**, so as soon as
//  your rows have hover or click —that is, always— the Flickable outside
//  never sees the wheel. The list could only be dragged, and the failure
//  gives no error: simply nothing happens, which is the worst kind to find.
//
//  The fix is the bottom layer: a MouseArea that listens to no button and
//  therefore steals no clicks, but does receive the wheel and translates it
//  to scrolling. It ships here by default so nobody else discovers it by
//  not understanding why their list does not move.
//
//      K4.Rodillo {
//          anchors.fill: parent
//          Column { id: content; width: parent.width }
//      }

import QtQuick
import QtQuick.Controls

Flickable {
    id: rodillo

    //  How far each notch travels. 60 px is roughly one row.
    property int muesca: 60

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: contentItem.childrenRect.height
    flickableDirection: Flickable.VerticalFlick

    //  The wheel catcher must live on the FLICKABLE, not in the content.
    //
    //  Everything declared inside a Flickable is reparented into its
    //  contentItem — and anchored to that, this MouseArea measured
    //  `contentHeight` itself. `contentHeight` feeds on
    //  `contentItem.childrenRect`, which included it, so the two fed each
    //  other: the scroll range could only ratchet UP, to the tallest
    //  content ever shown, and never back down. Every page after it kept
    //  that much dead scroll below its real content. Reparented here it
    //  covers the viewport, stays glued while the content scrolls, and the
    //  content measures only the content.
    MouseArea {
        parent: rodillo
        //  Below everything and deaf to buttons: clicks pass to the rows.
        z: -1
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        onWheel: function (ev) {
            const alto = rodillo.contentHeight - rodillo.height
            if (alto <= 0)
                return
            //  angleDelta comes in eighths of a degree; 120 is one notch.
            const pasos = ev.angleDelta.y / 120
            rodillo.contentY = Math.max(0, Math.min(alto,
                rodillo.contentY - pasos * rodillo.muesca))
        }
    }

    //  The in-house scrollbar, by default: it shows up on its own when
    //  there is something to travel and fades when released. Anyone who
    //  wants another one can override the attached property, but nobody
    //  should have to set it.
    ScrollBar.vertical: Desplazador {}
}
