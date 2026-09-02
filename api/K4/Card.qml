//  A block of the Control Centre, contributed by the plugin that does
//  the work.
//
//  `K4.Ajustes` contributes a row of options and `K4.Pagina` a whole
//  Settings screen; this contributes a card in the centre — the panel
//  that opens from the bar. The plugin that knows the work ships the
//  card for it: a mail watcher ships its unread row, a sync tool ships
//  its progress. The card renders among the native blocks — toggles,
//  media, shortcuts — wherever the stored order says, with the same
//  width, the same look rules and the same editor: the user reorders
//  and hides it in Settings → Control centre like any native block.
//
//      K4.Card {
//          plugin: "correo"
//          name: "unread"            // unique within YOUR plugin
//          titulo: "Mail"
//          glifo: 0xF01EE
//          alto: 64                  // px the card occupies
//          component: Component { MiFila {} }
//      }
//
//  `alto` is the height the card OCCUPIES — fixed, like the native
//  blocks' own heights. The centre sizes itself from it and hands the
//  card exactly that room; the card's root should fill what it is
//  given (`width: parent.width`, `height: parent.height`).
//
//  Visibility is the user's, not yours: the eye toggle in the centre's
//  editor hides the card, and `panelOrder` decides where it sits. The
//  card disappears from both the moment your plugin is off or
//  unloaded — nobody renders a card whose author is gone.
//
//  `componente` is instantiated only while the centre is open on its
//  controls tab, in your plugin's own context: your ids, your
//  imports, your sibling types.

import QtQuick

QtObject {
    id: aporte

    //  Your id, the same one as the manifest.
    required property string plugin

    //  The card's key, unique within your plugin. Two cards of yours
    //  with the same name are the same card: the last one to register
    //  wins. The centre knows the card as "<plugin>.<name>".
    required property string name

    //  The label the centre's editor shows for the card.
    property string titulo: ""

    //  A Nerd Font codex for the editor row — find it with
    //  `tools/glifos.py`. Zero means the plugin's manifest icon.
    property int glifo: 0

    //  One line under the label, for the editor row.
    property string desc: ""

    //  The height the card occupies, in pixels. The centre is as tall
    //  as the blocks it shows; a card of zero height is a card that
    //  never gets room.
    property int alto: 0

    //  The card itself. Declared here, instantiated by the host — the
    //  same arrangement as `K4.Plugin.view`.
    property Component component: null

    function _registrar() {
        if (Puente.enganches)
            Puente.enganches.registrarCard(aporte)
    }

    Component.onCompleted: _registrar()

    //  And again on every change, like `K4.Pagina`: the registry keeps
    //  a PHOTO, and a card whose height or component is decided later
    //  would be born with the stale one otherwise.
    onNameChanged: _registrar()
    onTituloChanged: _registrar()
    onGlifoChanged: _registrar()
    onDescChanged: _registrar()
    onAltoChanged: _registrar()
    onComponentChanged: _registrar()

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
