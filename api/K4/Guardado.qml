// Existing plugin contract. Named preferences use config.json; state is local.
import QtQuick

PluginState {
    id: self
    property string nombre: "state"
    name: nombre === "estado" ? "state" : nombre === "ajustes" ? "settings" : nombre
    signal cargado(var datos)
    onLoaded: function (data) { cargado(data) }
    function guardar(datos) { return save(datos) }
}
