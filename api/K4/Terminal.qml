pragma Singleton

// Terminal access for plugins. The host selects a window terminal and owns
// shared connection state; a terminal provider registers the island runner.
// Process-launching operations require the procesos permission.

import QtQuick

QtObject {
    id: api
    readonly property var _c: Puente.consola
    readonly property string cual: _c ? _c.binario : ""
    readonly property bool enLaIsla: _c ? _c.usaIsla : false
    readonly property string cierre: _c ? _c.cierre : ""

    function ejecutar(script) { if (_c && script) _c.ejecutar(String(script)) }
    function abrir(path) { if (_c) Sistema.lanzar(_c.abrir(path ? String(path) : "")) }

    // Provider operations keep service imports out of the Terminal plugin.
    readonly property bool islandAvailable: _c ? _c.hayIsla : false
    readonly property bool nativeIslandAvailable: _c ? _c.nativeIslandAvailable : false
    readonly property bool nativeWindowAvailable: _c ? _c.esNuestra : false
    readonly property string themePath: _c ? _c.themePath : ""
    readonly property string focusedPid: _c ? _c.focusedPid : ""
    readonly property string connecting: _c ? _c.conectando : ""
    readonly property double connectionStartedAt: _c ? _c.conectandoDesde : 0
    readonly property string connectionTint: _c ? _c.tinteConexion : ""

    function registerIsland(callback) { if (_c) _c.registrarIsla(callback) }
    function refreshBackends() { if (_c) _c.revisar() }
    function windowCommand(path) { return _c ? _c.abrir(path || "") : [] }
    function scriptCommand(script) { return _c ? _c.orden(script) : [] }
    function connectionFinished() { if (_c) _c.conectado() }
    function connectionEnded(destination) { if (_c) _c.salioDe(destination) }
    function markConnectionStarted() { if (_c) _c.conectandoDesde = Date.now() }
    function takeConnectionPassword() {
        if (!_c) return ""
        const password = _c.claveConexion
        _c.claveConexion = ""
        return password
    }
    function trackNotice(title, pid) { if (_c) _c.trackNotice(title, pid) }
    function clearNotice(title) { if (_c) _c.clearNotice(title) }
}
