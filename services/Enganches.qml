pragma Singleton

//  Registry for plugins that appear in host-owned surfaces: their Settings
//  options, pages, Control Centre cards and launcher results.
//
//  This is a registry rather than a list of cross-imports because Settings
//  cannot know a plugin that does not exist yet, especially one installed in
//  ~/.config/k4/plugins. Each contribution registers at birth and leaves at
//  destruction.
//
//  Destruction matters: disabling, hot-reloading and uninstalling really
//  destroy plugins. An orphan contribution would invoke a dead object, so
//  both the contribution and PluginManager clean registrations up.

import QtQuick
import Quickshell

Singleton {
    id: registro

    // ── contributed settings ─────────────────────────────────────
    //
    //  Each entry: { plugin, grupo, opciones: [...], fuente }.
    //  `fuente` is the K4.Ajustes object that owns the values.
    property var ajustes: []

    //  The prefix tells Settings which owner to ask. Including the plugin id
    //  lets two plugins use the same option name without collisions.
    function idExterno(plugin, opcion) {
        return "ext_" + plugin + "_" + opcion
    }

    function _partes(id) {
        //  "ext_<plugin>_<opcion>": plugin ids contain no underscores because
        //  RE_ID forbids them, so the first separator is unambiguous.
        const resto = String(id).substring(4)
        const corte = resto.indexOf("_")
        if (corte < 0)
            return null
        return { plugin: resto.substring(0, corte),
                 opcion: resto.substring(corte + 1) }
    }

    function _fuente(plugin) {
        for (let i = 0; i < ajustes.length; ++i)
            if (ajustes[i].plugin === plugin)
                return ajustes[i].fuente
        return null
    }

    //  Replace only this settings entry. `quitarDe` means the whole plugin
    //  died and also removes launcher, page and card contributions.
    function registrarAjustes(fuente) {
        if (!fuente || !fuente.plugin)
            return
        ajustes = ajustes.filter(function (x) {
            return x.plugin !== fuente.plugin
        }).concat([{ plugin: fuente.plugin,
                     grupo: fuente.grupo,
                     opciones: fuente.opciones || [],
                     fuente: fuente }])
    }

    // This one sweeps all four: it is for when the plugin leaves.
    function quitarDe(plugin) {
        const quedan = ajustes.filter(function (x) { return x.plugin !== plugin })
        if (quedan.length !== ajustes.length)
            ajustes = quedan
        const quedanL = lanzador.filter(function (x) { return x.plugin !== plugin })
        if (quedanL.length !== lanzador.length)
            lanzador = quedanL
        const quedanP = paginas.filter(function (x) { return x.plugin !== plugin })
        if (quedanP.length !== paginas.length)
            paginas = quedanP
        const quedanT = cards.filter(function (x) { return x.plugin !== plugin })
        if (quedanT.length !== cards.length)
            cards = quedanT
    }

    //  What Settings appends to its group list.
    readonly property var gruposAjustes: {
        const salida = []
        for (let i = 0; i < ajustes.length; ++i) {
            const a = ajustes[i]
            if (!a.opciones || a.opciones.length === 0)
                continue
            salida.push({
                grupo: a.grupo || a.plugin,
                //  Metadata for the Settings sidebar. A missing icon falls
                //  back to the plugin manifest's familiar application icon.
                glifo: a.fuente && a.fuente.glifo ? a.fuente.glifo : 0,
                desc: a.fuente && a.fuente.desc ? a.fuente.desc : "",
                dePlugin: a.plugin,
                //  These live inside their plugin row, beside its enable
                //  switch, rather than becoming a separate sidebar section.
                //
                //  They remain in `Settings.definicion`, so search still finds
                //  every contributed option.
                enLateral: false,
                opciones: a.opciones.map(function (o) {
                    return Object.assign({}, o, {
                        id: registro.idExterno(a.plugin, o.id)
                    })
                })
            })
        }
        return salida
    }

    function valorAjuste(id) {
        const p = _partes(id)
        if (!p)
            return false
        const f = _fuente(p.plugin)
        return f ? (f.valores ? f.valores[p.opcion] : false) : false
    }

    function alternarAjuste(id) {
        const p = _partes(id)
        if (!p)
            return
        const f = _fuente(p.plugin)
        if (f)
            f.cambiado(p.opcion, !valorAjuste(id))
    }

    function ponerAjuste(id, valor) {
        const p = _partes(id)
        if (!p)
            return
        const f = _fuente(p.plugin)
        if (f)
            f.cambiado(p.opcion, valor)
    }

    // ── pages contributed to Settings ─────────────────────────────
    //
    //  A WHOLE page, not a row of options: shipped by the plugin that
    //  knows the work, rendered by Settings with its sidebar, its search
    //  and its scroll like any native page. Each entry:
    //  { plugin, name, fuente } — the fuente is the K4.Pagina, the one
    //  holding the Component.
    property var paginas: []

    function registrarPagina(fuente) {
        if (!fuente || !fuente.plugin || !fuente.name
                || !fuente.componente)
            return
        paginas = paginas.filter(function (x) {
            return !(x.plugin === fuente.plugin
                     && x.name === fuente.name)
        }).concat([{ plugin: fuente.plugin, name: fuente.name,
                     fuente: fuente }])
    }

    //  The Component is asked to the registry BY NAME, never through
    //  modelData: a Repeater hands its delegates a COPY of the model
    //  object, and a Component that travelled inside a copy does not
    //  instantiate.
    function componenteDe(plugin, name) {
        for (let i = 0; i < paginas.length; ++i)
            if (paginas[i].plugin === plugin && paginas[i].name === name)
                return paginas[i].fuente.componente
        return null
    }

    //  What the pages add to Settings' sidebar: groups shaped like the
    //  native ones, carrying `pagina` instead of `vista` — the key the
    //  view reads to know this section is painted by asking the registry
    //  for a Component.
    readonly property var gruposPaginas: {
        const salida = []
        for (let i = 0; i < paginas.length; ++i) {
            const f = paginas[i].fuente
            salida.push({
                grupo: f.titulo || f.name,
                padre: f.padre || "",
                glifo: f.glifo || 0,
                desc: f.desc || "",
                claves: f.claves || [],
                pagina: { plugin: f.plugin, name: paginas[i].name },
                opciones: []
            })
        }
        return salida
    }

    // ── cards contributed to the Control Centre ───────────────────
    //
    //  A BLOCK of the centre, shipped by the plugin that does the
    //  work: rendered among the native toggles/media/shortcuts,
    //  wherever the stored order says, sized by the height the card
    //  declares. Each entry: { plugin, name, fuente } — the fuente is
    //  the K4.Card, the one holding the Component.
    property var cards: []

    function registrarCard(fuente) {
        if (!fuente || !fuente.plugin || !fuente.name
                || !fuente.component)
            return
        cards = cards.filter(function (x) {
            return !(x.plugin === fuente.plugin
                     && x.name === fuente.name)
        }).concat([{ plugin: fuente.plugin, name: fuente.name,
                     fuente: fuente }])
    }

    //  Same rule as the pages: the Component is asked to the registry
    //  BY NAME, never through modelData — a Component that travelled
    //  inside a copy does not instantiate.
    function componenteDeCard(plugin, name) {
        for (let i = 0; i < cards.length; ++i)
            if (cards[i].plugin === plugin && cards[i].name === name)
                return cards[i].fuente.component
        return null
    }

    function cardDetail(id) {
        for (let i = 0; i < cards.length; ++i)
            if (cards[i].plugin + "." + cards[i].name === id)
                return cards[i].fuente.detail
        return null
    }

    function cardDetailTitle(id) {
        for (let i = 0; i < cards.length; ++i)
            if (cards[i].plugin + "." + cards[i].name === id)
                return cards[i].fuente.detailTitle || cards[i].fuente.titulo || cards[i].name
        return ""
    }

    signal cardDetailRequested(string id)

    function openCardDetail(id) {
        if (cardDetail(id))
            cardDetailRequested(id)
    }

    //  The ids the cards add to the centre's block universe:
    //  "<plugin>.<name>", the form `panelOrder` stores them in. The
    //  dotted shape is what tells a card from a native block, so a
    //  plugin id with a dot would break the promise — RE_ID already
    //  forbids dots in plugin ids, which is why the form is safe.
    readonly property var idsCards: cards.map(function (x) {
        return x.plugin + "." + x.name
    })

    //  A card's declared height, by "<plugin>.<name>" id. Zero when
    //  unknown — the caller decides what that means (the centre draws
    //  nothing at zero height).
    function altoDeCard(id) {
        for (let i = 0; i < cards.length; ++i)
            if (cards[i].plugin + "." + cards[i].name === id)
                return cards[i].fuente.alto
        return 0
    }

    // ── results in the launcher ───────────────────────────────────
    //
    //  Each entry: { plugin, fuente }. The launcher asks every source and each
    //  answers when ready, so one slow plugin blocks nobody.
    property var lanzador: []

    signal buscando(string texto)

    function registrarLanzador(fuente) {
        if (!fuente || !fuente.plugin)
            return
        lanzador = lanzador.filter(function (x) {
            return x.plugin !== fuente.plugin
        }).concat([{ plugin: fuente.plugin, fuente: fuente }])
    }

    function buscar(texto) {
        buscando(texto)
    }

    //  What should be rendered now from every source that has answered.
    readonly property var resultados: {
        const salida = []
        for (let i = 0; i < lanzador.length; ++i) {
            const f = lanzador[i].fuente
            const rs = (f && f.resultados) || []
            for (let j = 0; j < rs.length; ++j)
                salida.push(Object.assign({}, rs[j],
                                          { _plugin: lanzador[i].plugin }))
        }
        return salida
    }

    function elegir(resultado) {
        if (!resultado || !resultado._plugin)
            return
        for (let i = 0; i < lanzador.length; ++i)
            if (lanzador[i].plugin === resultado._plugin)
                lanzador[i].fuente.elegido(resultado.id)
    }
}
