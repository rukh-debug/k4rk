//  The island shape: a rounded body and two inverted corners that merge
//  it into the screen edge.
//
//  It used to live inside `shell.qml`. It is a component because both the
//  real bar and the Settings preview draw it; a rounded blue rectangle is
//  not a preview of this silhouette.
//
//  Small sizes need care: the path needs `2 * (wing + radius)` of length.
//  Below that the two curves cross, so both values are clamped by length as
//  well as thickness.
//
//  The path uses edge coordinates: u runs along the edge and v away from
//  it. `punto()` maps that one drawing to all four sides, keeping the
//  inverted corners against the wall and the rounded corners inside.

import QtQuick
import QtQuick.Shapes

Shape {
    id: silueta

    // How far each inverted corner reaches into the body.
    property real ala: Theme.wing

    // Rounding on the two corners facing the desktop.
    property real cuerpoRadio: 20

    property color relleno: Theme.islandBg

    // The edge carrying the island: top, bottom, left, or right.
    property string lado: "top"

    // CurveRenderer drops the inverted wings, so use MSAA instead.
    antialiasing: true
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    // Bottom and left reflect the path, which also reverses arc direction.
    readonly property bool voltear: lado === "bottom" || lado === "left"

    // Length along the edge and thickness away from it.
    readonly property real largo:
        (lado === "left" || lado === "right") ? height : width
    readonly property real grueso:
        (lado === "left" || lado === "right") ? width : height

    function punto(u, v) {
        if (lado === "bottom")
            return Qt.point(u, height - v)
        if (lado === "left")
            return Qt.point(v, u)
        if (lado === "right")
            return Qt.point(width - v, u)
        return Qt.point(u, v)
    }

    ShapePath {
        id: trazo

        fillColor: silueta.relleno
        strokeWidth: 0
        strokeColor: "transparent"

        readonly property real largo: silueta.largo
        readonly property real grueso: silueta.grueso
        // Clamp by length as well as thickness; see the note above.
        readonly property real g: Math.max(0, Math.min(silueta.ala,
                                                       grueso / 2,
                                                       largo / 6))
        readonly property real r: Math.max(0, Math.min(silueta.cuerpoRadio,
                                                       grueso / 2,
                                                       largo / 3 - trazo.g))

        // Every path node, mapped into item coordinates.
        readonly property var p0: silueta.punto(0, 0)
        readonly property var p1: silueta.punto(trazo.g, trazo.g)
        readonly property var p2: silueta.punto(trazo.g, grueso - trazo.r)
        readonly property var p3: silueta.punto(trazo.g + trazo.r, grueso)
        readonly property var p4: silueta.punto(largo - trazo.g - trazo.r, grueso)
        readonly property var p5: silueta.punto(largo - trazo.g, grueso - trazo.r)
        readonly property var p6: silueta.punto(largo - trazo.g, trazo.g)
        readonly property var p7: silueta.punto(largo, 0)

        startX: trazo.p0.x
        startY: trazo.p0.y

        // Inverted corner at the beginning of the edge.
        PathArc {
            x: trazo.p1.x; y: trazo.p1.y
            radiusX: trazo.g; radiusY: trazo.g
            direction: silueta.voltear ? PathArc.Counterclockwise
                                       : PathArc.Clockwise
        }

        PathLine { x: trazo.p2.x; y: trazo.p2.y }

        // First rounded interior corner.
        PathArc {
            x: trazo.p3.x; y: trazo.p3.y
            radiusX: trazo.r; radiusY: trazo.r
            direction: silueta.voltear ? PathArc.Clockwise
                                       : PathArc.Counterclockwise
        }

        PathLine { x: trazo.p4.x; y: trazo.p4.y }

        // Last rounded interior corner.
        PathArc {
            x: trazo.p5.x; y: trazo.p5.y
            radiusX: trazo.r; radiusY: trazo.r
            direction: silueta.voltear ? PathArc.Clockwise
                                       : PathArc.Counterclockwise
        }

        PathLine { x: trazo.p6.x; y: trazo.p6.y }

        // Inverted corner at the end of the edge.
        PathArc {
            x: trazo.p7.x; y: trazo.p7.y
            radiusX: trazo.g; radiusY: trazo.g
            direction: silueta.voltear ? PathArc.Counterclockwise
                                       : PathArc.Clockwise
        }

        PathLine { x: trazo.p0.x; y: trazo.p0.y }
    }
}
