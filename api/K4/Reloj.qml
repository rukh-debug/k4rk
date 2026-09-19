pragma Singleton

//  Time from the clock shared throughout the shell.
//
//  Share one source instead of having five SystemClock instances polling
//  independently. Updates once per minute, enough for a bar clock; plugins
//  needing second-level updates should use their own Timer.

import QtQuick

QtObject {
    readonly property var _r: Puente.reloj

    readonly property date ahora: _r ? _r.date : new Date()
}
