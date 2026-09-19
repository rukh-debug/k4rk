//  Persistent plugin state: a named JSON file in the plugin's own directory.
//
//  Storage for saved games, high scores and plugin settings. Each plugin
//  writes in ITS directory, ~/.local/state/k4/plugins/<id>/, rather than a
//  shared directory where identically named files would overwrite each other.
//
//      K4.Guardado {
//          id: guardado
//          plugin: "snake"                 // the manifest id
//          onCargado: function (d) { record = d.record || 0 }
//      }
//      ...
//      guardado.guardar({ record: record })
//
//  `cargado` fires once at startup, with {} if no state existed. `guardar`
//  writes the complete supplied value: this is small state, not a database,
//  and keeping the write simple avoids partially updated application state.

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: self

    required property string plugin
    //  A plugin may want several files, such as a saved game and settings.
    property string nombre: "estado"

    signal cargado(var datos)

    readonly property string _dir: Paths.estadoDe(plugin)
    readonly property string _ruta: _dir + "/" + nombre + ".json"

    function guardar(datos) {
        _fichero.setText(JSON.stringify(datos, null, 1))
    }

    //  Create the directory before reading: a missing directory is expected
    //  on first use, but attempting to write into it would fail.
    property var _mkdir: Process {
        command: ["mkdir", "-p", self._dir]
        running: true
        onExited: self._leer()
    }

    function _leer() {
        let d = {}
        try {
            const bruto = _fichero.text()
            if (bruto && bruto.length > 0)
                d = JSON.parse(bruto)
        } catch (e) {
            //  Broken state must not prevent startup: start fresh instead.
            //  Leave the damaged file on disk in case anything is recoverable.
        }
        cargado(d)
    }

    property var _fichero: FileView {
        path: self._ruta
        blockLoading: true
    }
}
