//  The application centre: everything the bar knows how to open,
//  in a grid.
//
//  The bar has eleven things that are applications —the dungeon,
//  the editor, the clipboard, the shortcuts...— and until now the
//  only way to reach them was knowing the shortcut or the command's
//  name. That is fine for whoever configured it and invisible to
//  everybody else, and above all it leaves installed plugins out:
//  a game you download has no shortcut until you give it one.
//
//  It is the phone's app drawer, on purpose: grid, search box on
//  top, you type and it filters, Enter opens. Nobody has to learn
//  anything.
//
//  What shows here is said by the catalog (`application: true`),
//  not the code: this way an outside plugin walks in just by
//  declaring it in its manifest.

import QtQuick
import K4 as K4
import "../../services"

K4.Plugin {
    id: self

    name: "apps"
    title: "Applications"
    priority: 72
    colocable: true
    active: abierto
    grabKeyboard: abierto
    islandWidth: 700
    islandHeight: 520

    property bool abierto: false
    property string busqueda: ""
    property int seleccion: 0
    //  With this set, the grid steps aside and the pending-updates
    //  list comes out, each with its switch.
    property bool modoActualizaciones: false

    //  The packages plugin, injected by catalog id. It owns updates now;
    //  when it is not there — off, or no backend on this machine — the
    //  facade below turns its absence into honest zeros, so the updates
    //  view reads one shape either way and hides on its own.
    property var packages: null
    readonly property var paq: ({
        pendientes: packages ? packages.pendientes : 0,
        pendientesRepo: packages ? packages.pendientesRepo : 0,
        pendientesAur: packages ? packages.pendientesAur : 0,
        marcadas: packages ? packages.marcadas : 0,
        comprobando: packages ? packages.comprobando : false,
        detalles: packages ? packages.detalles : [],
        excluidos: packages ? packages.excluidos : ({}),
        nombresPendientes: packages ? packages.nombresPendientes : [],
        refresh: function (forzar) {
            if (packages) packages.refresh(forzar)
        },
        alternarExcluida: function (nombre) {
            if (packages) packages.alternarExcluida(nombre)
        },
        updateSelected: function () {
            if (packages) packages.updateSelected()
        },
        updateAll: function () {
            if (packages) packages.updateAll()
        }
    })

    //  Las de la barra, filtradas por lo que se escribe. Una apagada NO
    //  desaparece: sale en gris. Que algo se esfume al apagarlo obliga a
    //  guess where it went; in gray one sees it is there and why it
    //  does not open.
    readonly property var lista: {
        const todas = PluginManager.aplicaciones
        const q = busqueda.trim().toLowerCase()
        if (q.length === 0)
            return todas
        return todas.filter(function (a) {
            return a.nombre.toLowerCase().indexOf(q) >= 0
        })
    }

    readonly property int columnas: 5

    view: Component { AppsView { plugin: self } }

    function abrirse() {
        busqueda = ""
        seleccion = 0
        modoActualizaciones = false
        abierto = true
        if (packages)
            packages.refresh(false)
    }

    //  Straight into choosing what to update: the launcher uses it.
    function abrirActualizaciones() {
        abrirse()
        modoActualizaciones = true
    }

    //  The contract verb for it: the launcher says `openTab("updates")`
    //  like it does to the panel's tabs, instead of reaching for a
    //  method only this plugin knows.
    function openTab(tab) {
        if (tab === "updates")
            abrirActualizaciones()
    }

    function toggle() {
        if (abierto)
            cerrar()
        else
            abrirse()
    }

    function cerrar() { abierto = false }
    function close() { cerrar() }

    //  Opening the chosen one: it closes FIRST, otherwise both ask
    //  for the island at once and the higher priority wins —this
    //  one— and it looks like nothing happened.
    function lanzar(id) {
        cerrar()
        PluginManager.abrirAplicacion(id)
    }

    function lanzarSeleccion() {
        if (seleccion >= 0 && seleccion < lista.length)
            lanzar(lista[seleccion].id)
    }

    function mover(dx, dy) {
        if (lista.length === 0)
            return
        let n = seleccion + dx + dy * columnas
        //  At the edges it stays, it does not wrap: jumping from the
        //  last to the first with one arrow disorients more than it
        //  helps.
        seleccion = Math.max(0, Math.min(lista.length - 1, n))
    }

    //  And announcing itself in the desktop's application launcher.
    //
    //  The two drawers stay separate on purpose —they are different
    //  questions: «open a program on my machine» is hundreds of
    //  entries, «open a part of the bar» is eleven, and mixing them
    //  buries the eleven—. But separating them leaves a hole:
    //  typing «clipboard» into SUPER+Space and getting NOTHING is
    //  exactly the feeling that something is broken, even one
    //  shortcut away.
    //
    //  So they announce themselves: two drawers, one search that
    //  finds everything. And this module does it and not each
    //  plugin, because the one knowing what a «bar application» is
    //  is this one.
    property var enElLanzador: K4.Lanzador {
        plugin: "apps"

        onBuscando: function (texto) {
            const q = texto.trim().toLowerCase()
            //  With one letter half the world comes out; from two on
            //  it is an intention.
            if (q.length < 2) {
                resultados = []
                return
            }
            resultados = PluginManager.aplicaciones
                .filter(function (a) {
                    return a.habilitado
                        && a.nombre.toLowerCase().indexOf(q) >= 0
                })
                .map(function (a) {
                    //  Each with ITS OWN icon, in the two fields the
                    //  launcher understands. It used to go in
                    //  `icono`, which is a desktop icon's name, and
                    //  no bar application has one: they all came out
                    //  iconless.
                    return { id: a.id, titulo: a.nombre,
                             desc: "Bar application",
                             imagen: a.imagen, glifo: a.glifo }
                })
        }

        onElegido: function (id) { PluginManager.abrirAplicacion(id) }
    }

    K4.Ipc {
        target: "k4.apps"
        function toggle(): void { self.toggle() }
        function open(): void { self.abrirse() }
        function close(): void { self.cerrar() }
    }
}
