import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property bool attachTop: false
    property bool attachBottom: false
    property bool attachLeft: false
    property bool attachRight: false
    property bool blending: true
    property real connection: 1
    property real cornerRadius: 22
    property real rimThickness: 1
    property real blendReach: 16
    property real blendDepth: 12
    property color fillColor: "black"
    property color borderColor: "transparent"

    readonly property real safeRadius: Math.max(0, Math.min(
        cornerRadius, width / 2, height / 2))
    readonly property real safeRim: Math.max(0, rimThickness)
    readonly property real safeReach: blending ? Math.max(0, blendReach) : 0
    readonly property real safeDepth: blending ? Math.max(0, blendDepth) : 0

    Rectangle {
        id: body

        anchors.fill: parent
        radius: root.safeRadius
        color: root.fillColor
        border.width: root.borderColor.a > 0 ? 1 : 0
        border.color: root.borderColor
    }

    // Fill every corner touching a wall. The vector wings below provide
    // the exposed curve; the screen corner itself must remain solid.
    Repeater {
        model: [
            { x: 0, y: 0, on: root.attachTop || root.attachLeft },
            { x: root.width - root.safeRadius, y: 0,
              on: root.attachTop || root.attachRight },
            { x: 0, y: root.height - root.safeRadius,
              on: root.attachBottom || root.attachLeft },
            { x: root.width - root.safeRadius,
              y: root.height - root.safeRadius,
              on: root.attachBottom || root.attachRight }
        ]

        Rectangle {
            required property var modelData
            visible: modelData.on && root.safeRadius > 0
            x: modelData.x
            y: modelData.y
            width: root.safeRadius
            height: root.safeRadius
            color: root.fillColor
            opacity: root.connection
        }
    }

    // Cover the body's border where material continues into a wall.
    Rectangle {
        visible: root.attachTop
        width: parent.width
        height: Math.max(1, root.safeRim + 1)
        color: root.fillColor
        opacity: root.connection
    }
    Rectangle {
        visible: root.attachBottom
        width: parent.width
        height: Math.max(1, root.safeRim + 1)
        anchors.bottom: parent.bottom
        color: root.fillColor
        opacity: root.connection
    }
    Rectangle {
        visible: root.attachLeft
        width: Math.max(1, root.safeRim + 1)
        height: parent.height
        color: root.fillColor
        opacity: root.connection
    }
    Rectangle {
        visible: root.attachRight
        width: Math.max(1, root.safeRim + 1)
        height: parent.height
        anchors.right: parent.right
        color: root.fillColor
        opacity: root.connection
    }

    // A canonical horizontal wing joins a top wall at the body's left
    // side. Mirroring it covers the other three horizontal junctions.
    component HorizontalWing: Shape {
        id: wing

        required property bool activeWing
        required property bool rightEnd
        required property bool bottomWall

        readonly property real d: root.safeDepth
        readonly property real t: root.safeRim
        readonly property real k: 0.5522847498

        visible: activeWing && root.safeReach > 0 && d > 0
                 && root.connection > 0
        opacity: root.connection
        width: root.safeReach
        height: t + d
        x: rightEnd ? root.width : -width
        y: bottomWall ? root.height - height : 0
        antialiasing: true
        layer.enabled: visible
        layer.samples: 8
        layer.smooth: true

        transform: Scale {
            origin.x: wing.width / 2
            origin.y: wing.height / 2
            xScale: wing.rightEnd ? -1 : 1
            yScale: wing.bottomWall ? -1 : 1
        }

        ShapePath {
            fillColor: root.fillColor
            strokeWidth: 0
            strokeColor: "transparent"
            startX: 0
            startY: 0
            PathLine { x: wing.width; y: 0 }
            PathLine { x: wing.width; y: wing.height }
            PathCubic {
                x: 0
                y: wing.t
                control1X: wing.width
                control1Y: wing.t + wing.d * (1 - wing.k)
                control2X: wing.width * wing.k
                control2Y: wing.t
            }
            PathLine { x: 0; y: 0 }
        }
    }

    // The vertical twin joins a left wall above the body. Mirroring maps
    // the same tangent curve to every remaining junction.
    component VerticalWing: Shape {
        id: wing

        required property bool activeWing
        required property bool rightWall
        required property bool bottomEnd

        readonly property real d: root.safeDepth
        readonly property real t: root.safeRim
        readonly property real k: 0.5522847498

        visible: activeWing && root.safeReach > 0 && d > 0
                 && root.connection > 0
        opacity: root.connection
        width: t + d
        height: root.safeReach
        x: rightWall ? root.width - width : 0
        y: bottomEnd ? root.height : -height
        antialiasing: true
        layer.enabled: visible
        layer.samples: 8
        layer.smooth: true

        transform: Scale {
            origin.x: wing.width / 2
            origin.y: wing.height / 2
            xScale: wing.rightWall ? -1 : 1
            yScale: wing.bottomEnd ? -1 : 1
        }

        ShapePath {
            fillColor: root.fillColor
            strokeWidth: 0
            strokeColor: "transparent"
            startX: 0
            startY: 0
            PathLine { x: wing.t; y: 0 }
            PathCubic {
                x: wing.width
                y: wing.height
                control1X: wing.t
                control1Y: wing.height * wing.k
                control2X: wing.t + wing.d * (1 - wing.k)
                control2Y: wing.height
            }
            PathLine { x: 0; y: wing.height }
            PathLine { x: 0; y: 0 }
        }
    }

    HorizontalWing {
        activeWing: root.attachTop && !root.attachLeft
        rightEnd: false
        bottomWall: false
    }
    HorizontalWing {
        activeWing: root.attachTop && !root.attachRight
        rightEnd: true
        bottomWall: false
    }
    HorizontalWing {
        activeWing: root.attachBottom && !root.attachLeft
        rightEnd: false
        bottomWall: true
    }
    HorizontalWing {
        activeWing: root.attachBottom && !root.attachRight
        rightEnd: true
        bottomWall: true
    }

    VerticalWing {
        activeWing: root.attachLeft && !root.attachTop
        rightWall: false
        bottomEnd: false
    }
    VerticalWing {
        activeWing: root.attachLeft && !root.attachBottom
        rightWall: false
        bottomEnd: true
    }
    VerticalWing {
        activeWing: root.attachRight && !root.attachTop
        rightWall: true
        bottomEnd: false
    }
    VerticalWing {
        activeWing: root.attachRight && !root.attachBottom
        rightWall: true
        bottomEnd: true
    }
}
