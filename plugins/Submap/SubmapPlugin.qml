//  Hyprland submaps, announced on the pill.
//
//  A submap is the keyboard speaking another language for a while: the
//  screenshot keys, window resizing, whatever the user set up. It is
//  invisible by design, right until you forget which language it speaks
//  and every key starts doing the wrong thing. This plugin reads the
//  active submap through K4.Submaps and declares a capsule extension
//  through K4.Capsule while one is on — and that is ALL it does to the
//  bar. No pill internals, no geometry: it is written against the
//  public API only, the same one a plugin installed in
//  ~/.config/k4/plugins gets, and could be picked up and dropped there
//  as-is.
//
//  It never claims the island (`active` stays false): the extension is
//  part of the PILL, not a view. The pill stays itself — art, clock,
//  tray — and the name rides on its flank. When a deployed view takes
//  the island, the extension folds back with the pill and returns when
//  the pill does; that rule is the capsule's, not this plugin's.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "submap"
    title: "Submap"
    priority: 10
    active: false

    // ── what Hyprland says ────────────────────────────────────
    readonly property string currentMap: K4.Submaps.current

    readonly property bool live: habilitado && showing
        && currentMap.length > 0

    //  The name as it is read: "shot-manager" and "shot_manager" both
    //  become "Shot manager". The raw id stays an id; what the pill
    //  shows is a word.
    readonly property string label: {
        if (currentMap.length === 0)
            return ""
        const s = currentMap.replace(/[-_]+/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    // ── settings ──────────────────────────────────────────────
    //
    //  Whether the extension happens at all, which way it grows, and
    //  how far it may reach — a free number, not a preset, because the
    //  longest name a person declares is not known in advance. They
    //  live in the plugin's own section of Settings and persist in its
    //  state file.
    property bool showing: true
    property string side: "right"          // "left" · "right"
    property int maxLength: 300            // px cap, 60…1200

    // ── the capsule extension ─────────────────────────────────
    //
    //  The whole integration. `extension` is a binding that builds a
    //  NEW object when the state changes, and null when there is
    //  nothing to say — that is the API's contract for enter and leave.
    //  The measuring, the caps and the growing are the bar's.
    K4.Capsule {
        plugin: "submap"
        extension: self.live ? ({
            lado: self.side,
            texto: self.label,
            glifo: 0xF030E,               // md-keyboard_caps
            color: K4.Tema.azul,
            maxLength: self.maxLength
        }) : null
    }

    // ── settings, persisted ───────────────────────────────────
    function clampMaxLength(v) {
        const n = Math.floor(Number(v))
        if (!isFinite(n))
            return 300
        return Math.max(60, Math.min(1200, n))
    }

    property var store: K4.Guardado {
        plugin: "submap"
        onCargado: function (d) {
            if (d.showing !== undefined)
                self.showing = d.showing === true
            if (d.side === "left" || d.side === "right")
                self.side = d.side
            if (d.maxLength !== undefined)
                self.maxLength = self.clampMaxLength(d.maxLength)
        }
    }

    function persist() {
        store.guardar({ showing: showing, side: side, maxLength: maxLength })
    }

    K4.Ajustes {
        plugin: "submap"
        grupo: "Submap"
        glifo: 0xF030E   // md-keyboard_caps
        desc: "The pill grows toward a screen edge with the active mode's name."

        opciones: [
            { id: "showing", nombre: "Show the active submap",
              desc: "The capsule extends while a mode is on",
              glifo: 0xF030E },
            { id: "side", nombre: "Which way it grows",
              desc: "Toward the left or the right edge of the screen",
              glifo: 0xF0E73, tipo: "eleccion",
              alternativas: [{ codigo: "left", nombre: "Left" },
                             { codigo: "right", nombre: "Right" }] },
            { id: "maxLength", tipo: "texto",
              nombre: "Max length",
              desc: "Pixels the capsule may grow to — the name elides past it",
              pista: "300", glifo: 0xF046D }
        ]
        valores: ({
            showing: self.showing,
            side: self.side,
            maxLength: String(self.maxLength)
        })
        onCambiado: function (id, valor) {
            if (id === "showing")
                self.showing = valor === true
            else if (id === "side" && (valor === "left" || valor === "right"))
                self.side = valor
            else if (id === "maxLength")
                self.maxLength = self.clampMaxLength(valor)
            else
                return
            self.persist()
        }
    }
}
