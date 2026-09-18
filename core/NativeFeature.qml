// Host-private specialization of the K4.Plugin surface contract.
//
// Native features are trusted bar chrome, not extensions: they are always
// loaded, declare no permissions, and may import private host services.
// They still implement the same surface properties shell.qml arbitrates
// (name, priority, active, view, colocable, keyboard, close) so native and
// plugin surfaces never drift into two contracts.

import QtQuick
import K4 as K4

K4.Plugin {
    // Native surfaces are always enabled; there is no user switch.
    habilitado: true
    // Marks the object for host health reporting, which has no catalog
    // row to hang onto. See services/SurfaceRegistry.qml.
    readonly property bool nativo: true
}
