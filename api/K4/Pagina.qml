//  A whole page of Settings, contributed by the plugin that does the work.
//
//  `K4.Ajustes` contributes a ROW of options; this contributes the screen
//  itself. The plugin that knows the work ships the page for it: the theme
//  engine ships the Display family's working pages, a date tool could ship
//  its own top-level section. The page renders inside the Settings window
//  with the same sidebar, the same search and the same scroll as every
//  native page — the user never learns a second place.
//
//      K4.Pagina {
//          plugin: "hola"
//          name: "gretings"        // unique within YOUR plugin
//          titulo: "Greetings"
//          padre: "Display"        // optional: nest under a family
//          glifo: 0xF02FC
//          desc: "How this plugin greets the desktop"
//          claves: ["hello", "salute"]
//          componente: Component { MiPagina {} }
//      }
//
//  `padre` is the section title to nest under — a native family («Display»)
//  or another contributed page's `titulo`. Empty means a top-level section
//  of your own. Titles are the sidebar's ids: choose a `titulo` no other
//  section uses, or the tree will believe you are it.
//
//  `claves` are search keys, read exactly like a native group's. The page
//  disappears from the sidebar AND from search the moment your plugin is
//  off or unloaded — nobody renders a page whose author is gone.
//
//  `componente` is instantiated only while its page is on screen, in your
//  plugin's own context: your ids, your imports, your sibling types. Root
//  it in a layout that reports `implicitHeight`, the way the native pages
//  do, and the Settings window will size and scroll it for you.

import QtQuick

QtObject {
    id: aporte

    //  Your id, the same one as the manifest.
    required property string plugin

    //  The page's key, unique within your plugin. Two pages of yours with
    //  the same name are the same page: the last one to register wins.
    required property string name

    //  The section title in the sidebar. Defaults to `name`.
    property string titulo: ""

    //  A Nerd Font codex for the sidebar row — find it with
    //  `tools/glifos.py`. Zero means the plugin's manifest icon.
    property int glifo: 0

    //  One line under the title, for the sidebar and the search results.
    property string desc: ""

    //  The family to nest under, by its title. Empty: a section of your
    //  own at the top level.
    property string padre: ""

    //  Words the search should find this page by.
    property var claves: []

    //  The page itself. Declared here, instantiated by the host — the
    //  same arrangement as `K4.Plugin.view`.
    property Component componente: null

    function _registrar() {
        if (Puente.enganches)
            Puente.enganches.registrarPagina(aporte)
    }

    Component.onCompleted: _registrar()

    //  And again on every change, like `K4.Ajustes`: the registry keeps a
    //  PHOTO, and a page whose place in the tree is decided later — after
    //  a probe, after a setting — would be born in the wrong drawer
    //  otherwise.
    onNameChanged: _registrar()
    onTituloChanged: _registrar()
    onGlifoChanged: _registrar()
    onDescChanged: _registrar()
    onPadreChanged: _registrar()
    onClavesChanged: _registrar()
    onComponenteChanged: _registrar()

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
