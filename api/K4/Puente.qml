pragma Singleton

// Host-injected services. API files must not import the host by relative path:
// doing so can instantiate a second singleton graph and duplicate IPC targets.
import QtQuick

QtObject {
    property var config: null
    property var credentials: null
    // Shared theme and pill indicators.
    property var tema: null
    property var indicadores: null

    // Explicit service references keep each platform dependency visible.
    property var audio: null
    property var feedback: null
    property var medios: null
    property var notificaciones: null
    property var wifi: null
    property var bluetooth: null
    property var escritorios: null
    property var portapapeles: null
    property var reloj: null
    property var systemMonitor: null

    // Contributions, surface state and host integration.
    property var enganches: null
    property var isla: null
    property var extensiones: null
    property var submaps: null
    property var consola: null
}
