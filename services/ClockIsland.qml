pragma Singleton

// Native clock hover view. Active on hover when nothing playing covers it;
// the player outranks it at priority 55. Carries the clickable tray,
// minimized items and plugin indicators that the folded pill cannot offer.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: self

    readonly property string name: "clock"
    readonly property string title: "Clock"
    readonly property int priority: 50
    readonly property bool habilitado: true
    readonly property bool nativo: true
    readonly property bool active: Island.hovered

    property bool viewLoaded: true
    readonly property bool colocable: false
    readonly property string summonCommand: ""
    readonly property bool transitorio: false

    property int anchoIzqMedido: 0
    property int anchoCentroMedido: 0
    property int anchoDerechoMedido: 0

    readonly property int ladoEstimado: {
        const trayShown = Settings.pillTrayMax > 0
            ? Math.min(Tray.count, Settings.pillTrayMax) : Tray.count
        const minisShown = Settings.pillMinimizedMax > 0
            ? Math.min(Modulos.count, Settings.pillMinimizedMax) : Modulos.count
        return (Tray.count > 0 ? trayShown * 24 + 8 : 0) + 48
            + minisShown * 180
            + Indicadores.anchoAproximado
    }

    readonly property int izqAncho: anchoIzqMedido > 0 ? anchoIzqMedido : 96
    readonly property int centroAncho: anchoCentroMedido > 0
        ? anchoCentroMedido : 92
    readonly property int derMedido: anchoDerechoMedido > 0
        ? anchoDerechoMedido : ladoEstimado
    readonly property int derAncho: Math.min(derMedido, 480)
    readonly property int hueco: 24

    readonly property int islandWidth: 44 + izqAncho + hueco + centroAncho + hueco + derAncho
    readonly property int alturaTira: Settings.notificationsOnHover
        ? Notifs.stripHeight(3) : 0
    readonly property int islandHeight: 68 + (alturaTira > 0 ? alturaTira + 18 : 0)

    property bool closeOnClickOutside: false
    property bool grabKeyboard: false
    property bool tecladoOpcional: false
    property bool tecladoAlPasar: false
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 0
    property bool handlesBackgroundTap: false

    property var barraApartada
    property var reservaBarra

    property Component view: Component {
        ClockIslandView { plugin: self }
    }

    function close() {}
}
