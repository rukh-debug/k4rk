pragma Singleton

//  Notifications received by the shell.
//
//  Reading is unrestricted for logs, counters and observational filters.
//  Dismissing requires the `notificaciones` permission: deleting an unread
//  notice can lose information the user has not yet seen.
//
//      Connections {
//          target: K4.Notificaciones
//          function onLlego() { console.log(K4.Notificaciones.ultima.summary) }
//      }

import QtQuick

QtObject {
    id: api

    readonly property var _n: Puente.notificaciones

    readonly property int cuantas: _n ? _n.count : 0
    readonly property var ultima: _n ? _n.latest : null
    //  Recent notifications, already limited by the shell.
    readonly property var recientes: _n ? _n.recent : []

    signal llego()

    //  ── requires the `notificaciones` permission ──────────────────
    function limpiar() { if (_n) _n.clear() }

    property Connections _puente: Connections {
        target: api._n
        function onNotified() { api.llego() }
    }
}
