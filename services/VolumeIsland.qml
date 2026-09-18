pragma Singleton

// Native volume HUD: the transient default-sink indicator.
//
// Shows only while Audio.overlayOpen (external keys, mixer, or the control
// centre slider) and leaves on its own. Never intercepts clicks: it appears
// uninvited while the pointer is busy elsewhere.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: self

    readonly property string name: "volume"
    readonly property string title: "Volume"
    readonly property int priority: 40
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: Audio.overlayOpen

    property bool viewLoaded: true
    readonly property bool colocable: false
    readonly property string summonCommand: ""
    readonly property bool transitorio: false

    readonly property int islandWidth: 240
    readonly property int islandHeight: 40

    property bool closeOnClickOutside: false
    property bool grabKeyboard: false
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 0
    property bool handlesBackgroundTap: false

    property var barraApartada
    property var reservaBarra

    property Component view: Component { VolumeIslandView {} }

    function close() {}
}
