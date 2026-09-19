pragma Singleton

//  System audio: reading is unrestricted; changing it requires permission.
//
//  Reading has no side effects: a visualizer or indicator only needs to know
//  the current volume, so no permission is required. Raising or muting it is
//  noticeable, which is why `ponerVolumen` and `alternarSilencio` require the
//  `audio` permission in the manifest.
//
//      K4.Etiqueta { text: K4.Audio.volumen + "%" }

import QtQuick

QtObject {
    readonly property var _a: Puente.audio

    //  From 0 to 100.
    readonly property int volumen: _a ? _a.volume : 0
    readonly property bool silenciado: _a ? _a.muted : false
    readonly property bool listo: _a ? _a.initialized : false

    //  ── require the `audio` permission ────────────────────────────
    function ponerVolumen(porciento) {
        if (_a)
            _a.setVolume(porciento)
    }

    function alternarSilencio() {
        if (_a)
            _a.toggleMute()
    }
}
