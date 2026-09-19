import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import K4 as K4
import "../services"

// The same plugin view, hosted independently instead of extracting the pill.
K4.Ventana {
    id: window
    required property var owner
    property var preferredPlacement: Settings.placementDe(owner.name)
    readonly property bool hovered: hover.hovered
    readonly property var allocated: PopupLayout.placements[owner.name] || null
    readonly property var placementRequest: ({
        id: owner.name, screen: pantalla,
        width: card.width, height: card.height,
        screenWidth: width, screenHeight: height,
        placement: preferredPlacement
    })

    nombre: "k4-independent-" + owner.name
    reserva: -1
    // PanelWindow.screen may only resolve after mapping. Reading it from
    // visible creates a map/unmap feedback loop; use the screen list instead.
    visible: !Island.apartada && Quickshell.screens.some(function (output) {
        return output.name === window.pantalla
    })
    focusable: true

    Component.onCompleted: PopupLayout.registerWindow(window)
    Component.onDestruction: PopupLayout.unregisterWindow(window)
    onPlacementRequestChanged: PopupLayout.schedule()
    onVisibleChanged: PopupLayout.schedule()

    function close() {
        if (typeof owner.close === "function")
            owner.close()
    }

    // Monitor ownership is fixed at opening. Native notifications are transient
    // and retain their own lifetime; summoned views close on monitor departure.
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            if (window.owner.colocable && !window.owner.transitorio
                    && Hyprland.focusedMonitor
                    && Hyprland.focusedMonitor.name !== window.pantalla)
                window.close()
        }
    }

    readonly property bool catchOutside: visible && owner.viewLoaded
        && PopupLayout.outsideOwner(pantalla) === owner
    readonly property var mainRect: Island.rects[pantalla] || ({ x: 0, y: 0, ancho: 0, alto: 0 })

    WlrLayershell.keyboardFocus: {
        if (!visible || !owner.viewLoaded)
            return WlrKeyboardFocus.None
        if (PopupLayout.keyboardOwner === owner)
            return WlrKeyboardFocus.Exclusive
        if (!PopupLayout.keyboardOwner && owner.tecladoOpcional)
            return WlrKeyboardFocus.OnDemand
        return WlrKeyboardFocus.None
    }

    mask: Region {
        item: window.visible && window.allocated ? card : null
        Region {
            item: window.catchOutside ? outside : null
            Region {
                x: window.mainRect.x
                y: window.mainRect.y
                width: window.mainRect.ancho
                height: window.mainRect.alto
                intersection: Intersection.Subtract
            }
            PopupExclusionRegion { screenName: window.pantalla; exceptId: window.owner.name }
        }
    }

    Item {
        id: outside
        anchors.fill: parent
        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: window.close()
        }
    }

    Item {
        id: card
        x: window.allocated ? window.allocated.x : 0
        y: window.allocated ? window.allocated.y : 0
        width: Math.max(0, Math.min(Settings.popupSizeFor(window.owner, "width"), window.width))
        height: Math.max(0, Math.min(Settings.popupSizeFor(window.owner, "height"), window.height))
        visible: !!window.allocated
        focus: true
        Keys.onEscapePressed: function (event) { window.close(); event.accepted = true }
        readonly property string side: window.allocated ? window.allocated.side : "top"
        readonly property real bodyRadius: Math.min(32, height / 2)

        SiluetaIsla {
            anchors.fill: parent
            ala: Theme.wing
            cuerpoRadio: card.bodyRadius
            relleno: Theme.islandBg
            lado: card.side
        }
        EdgeAttachedShape {
            anchors.fill: parent
            attachTop: card.y <= 0.5
            attachBottom: card.y + card.height >= window.height - 0.5
            attachLeft: card.x <= 0.5
            attachRight: card.x + card.width >= window.width - 0.5
            cornerRadius: card.bodyRadius
            rimThickness: Settings.edgeZoneEnabled ? Settings.edgeZoneSize : 0
            blendReach: Theme.wing * 2
            blendDepth: Theme.wing
            fillColor: Theme.islandBg
        }

        property real reveal: 0
        Component.onCompleted: reveal = 1
        opacity: window.owner.viewLoaded ? reveal : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered)
                    hoverExit.stop()
                else if (window.owner.closeOnHoverExit)
                    hoverExit.restart()
            }
        }
        Timer {
            id: hoverExit
            interval: window.owner.hoverExitDelay
            onTriggered: if (window.owner.closeOnHoverExit)
                window.owner.hoverTimedOut()
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (window.owner.handlesBackgroundTap)
                    window.owner.backgroundTapped()
            }
        }

        Loader {
            objectName: "independentContent"
            anchors.fill: parent
            anchors.leftMargin: Theme.wing
            anchors.rightMargin: Theme.wing
            clip: true
            active: window.owner.viewLoaded
            sourceComponent: window.owner.view
            onStatusChanged: {
                if (status === Loader.Error)
                    console.warn("Independent island view failed:", window.owner.name)
            }
        }
    }
}
