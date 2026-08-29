pragma Singleton

//  Preferencias de la barra.
//
//  Solo vive aquí lo que de verdad cambia algo: un interruptor que no está
//  conectado a nada es peor que no tenerlo. Cada opción dice qué módulo la
//  lee, para que no queden huérfanas al refactorizar.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: ajustes

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/ajustes.json"

    // ── barra ─────────────────────────────────────────────────────
    //  En qué borde vive la barra. shell.qml ancla la ventana, voltea la
    //  silueta y orienta los gestos con esto; los plugins lo leen por
    //  K4.Isla.posicion para adaptar lo que pinten fuera.
    property string barPosition: "arriba"     // arriba · abajo
    //  En qué punto del borde se centra la island, en tanto por ciento del
    //  ancho libre: 50 es el centro de siempre. Un plugin puede desplazarla
    //  TEMPORALMENTE con K4.Isla.colocar; esto es la base a la que vuelve.
    property int barAlignment: 50            // 15 · 50 · 85
    //  Qué hace la barra con el sitio del escritorio.
    //
    //  «reserva» es lo de siempre: la franja plegada se le quita al escritorio
    //  y ninguna ventana se mete debajo. «encima» no le quita nada —la píldora
    //  flota sobre las ventanas— y «escondida» además la retira por el borde
    //  hasta que hay algo que enseñar. Y «completa» no es un cuarto estado
    //  sino una regla: reserva como siempre, y se esconde SOLO mientras una
    //  ventana llena la pantalla. shell.qml es quien las obedece.
    property string islandSpace: "reserva"   // reserva · completa · encima · escondida
    //  Click outside the bar closes whatever view is deployed, like Escape.
    //  shell.qml grows its surface to the whole screen while a view is open
    //  and spends the outside tap on closing it. Off is the old behavior:
    //  the click passes through to the desktop and the view stays.
    property bool cerrarConClicFuera: true
    // widgets/TrayRow.qml: iconos de bandeja en la píldora
    // Apagada de fábrica: en la píldora los iconos de bandeja son ruido casi
    // siempre, y al acercar el ratón la island ya se abre y ahí sí se ven —y
    // encima se pueden pulsar, que en la píldora no—.
    property bool trayInPill: false
    // widgets/NotifStrip.qml: notificaciones recientes al pasar el ratón
    property bool notificationsOnHover: true
    // services/Notifs.qml: descartar las de una aplicación al ir a su ventana
    property bool notificationsOnFocus: true

    // ── accesos directos ──────────────────────────────────────────
    //  Qué aplicaciones salen en la franja del centro de control, por id de
    //  plugin. plugins/Panel/PanelView.qml la pinta y el centro de
    //  aplicaciones la edita con la chincheta de cada tarjeta.
    //
    //  Ids y no una copia de nombres e iconos: así al renombrar un plugin o
    //  cambiarle el icono el acceso directo se entera solo, y uno que apunte a
    //  un plugin desinstalado simplemente no se pinta.
    property var quickAccess: ["game", "settings", "system", "clipboard"]

    function esAccesoDirecto(id) {
        return (quickAccess || []).indexOf(id) >= 0
    }

    function alternarAcceso(id) {
        const l = (quickAccess || []).slice()
        const i = l.indexOf(id)
        if (i >= 0)
            l.splice(i, 1)
        else
            l.push(id)
        quickAccess = l
        guardar()
    }

    // Cambia el valor de una opción que no es un interruptor.
    function poner(id, valor) {
        if (String(id).indexOf("ext_") === 0) {
            Enganches.ponerAjuste(id, valor)
            return
        }
        ajustes[id] = valor
        guardar()
    }

    readonly property var definicion: [,,
        {
            grupo: "Island",
            glifo: 0xF1513,
            desc: "How much room the bar keeps, and when it gets out of the way.",
            //  Dónde vive, cómo se alinea y cómo ocupa el sitio se explican mal
            //  con palabras: «Reservar sitio» y «Encima» suenan parecido y
            //  hacen cosas muy distintas con tus ventanas. Encima de las
            //  opciones va un croquis que lo enseña.
            vista: "island",
            opciones: [
                { id: "barPosition", tipo: "eleccion", de: "posiciones",
                  nombre: "Where the bar lives",
                  desc: "The island and its wings flip on their own",
                  glifo: 0xF10A9 },
                { id: "barAlignment", tipo: "eleccion", de: "alineaciones",
                  nombre: "Island alignment",
                  desc: "Where along the edge it sits",
                  glifo: 0xF11C3 },
                { id: "islandSpace", tipo: "eleccion", de: "reservas",
                  nombre: "How it takes up space",
                  desc: "Pushes windows aside, floats over them, or hides",
                  glifo: 0xF003E },   // md-arrange_bring_to_front
                { id: "cerrarConClicFuera", nombre: "Click outside closes what's open",
                  desc: "Same as Escape: a deployed view closes when you click outside the bar",
                  glifo: 0xF037D },   // md-cursor-default
                { id: "trayInPill", nombre: "Tray in the pill",
                  desc: "Icons of background apps", glifo: 0xF0FB0 },
                { id: "notificationsOnHover", nombre: "Notifications on hover",
                  desc: "Recent ones, under the clock and player", glifo: 0xF009A },
                { id: "notificationsOnFocus", nombre: "Dismiss when you switch to the app",
                  desc: "Switching to its window already counts as having attended to them", glifo: 0xF039F }
            ]
        },
        {
            grupo: "Appearance",
            //  Palabras por las que el buscador debe encontrar esta sección.
            //  Hacen falta porque sus controles viven dentro de un widget y no
            //  como `opciones`: sin esto, escribir «blur» no daba NADA aunque
            //  el interruptor esté ahí dentro.
            //
            //  Never shown, only searched: typing «gaps» deserves to find
            //  this section even though the switch lives inside a widget.
            claves: ["fondo", "fondos", "wallpaper", "escritorio", "desktop", "imagen", "video", "monitor", "pantalla"],
            glifo: 0xF03D8,
            desc: "The desktop wallpaper, and where the bar's colours come from.",
            //  El fondo y el color, juntos y en este orden: el color SALE del
            //  fondo mientras no lo toques a mano, así que separarlos en dos
            //  cajones obligaba a cruzar la ventana para entender una cosa.
            //  Ninguna opción declarada: lo que se elige aquí es una imagen y
            //  un color, y eso no cabe en una fila con un interruptor.
            vista: "fondos",
            opciones: []
        },
        {
            grupo: "Colour",
            //  Palabras por las que el buscador debe encontrar esta sección.
            //  Hacen falta porque sus controles viven dentro de un widget y no
            //  como `opciones`: sin esto, escribir «blur» no daba NADA aunque
            //  el interruptor esté ahí dentro.
            //
            //  Never shown, only searched: typing «gaps» deserves to find
            //  this section even though the switch lives inside a widget.
            claves: ["color", "colour", "colores", "preset", "acento", "accent", "paleta", "palette", "tema", "theme", "degradado"],
            glifo: 0xF03D9,
            desc: "Where the colours come from: the wallpaper, or a preset you pick.",
            //  Sección aparte y no debajo de los fondos, aunque estén
            //  emparentados: la rejilla se desplaza por dentro, así que lo que
            //  fuera detrás quedaba inalcanzable con la rueda. Un scroll dentro
            //  de otro scroll siempre acaba así.
            vista: "color",
            opciones: []
        },
        {
            grupo: "Windows",
            //  Palabras por las que el buscador debe encontrar esta sección.
            //  Hacen falta porque sus controles viven dentro de un widget y no
            //  como `opciones`: sin esto, escribir «blur» no daba NADA aunque
            //  el interruptor esté ahí dentro.
            //
            //  Never shown, only searched: typing «gaps» deserves to find
            //  this section even though the switch lives inside a widget.
            claves: ["ventanas", "windows", "borde", "border", "hueco", "huecos", "gap", "gaps", "redondeo", "rounding", "esquina", "esquinas"],
            glifo: 0xF10AC,
            desc: "Borders, gaps and corners of Hyprland's windows.",
            vista: "ventanas",
            opciones: []
        },
        {
            grupo: "Effects",
            //  Palabras por las que el buscador debe encontrar esta sección.
            //  Hacen falta porque sus controles viven dentro de un widget y no
            //  como `opciones`: sin esto, escribir «blur» no daba NADA aunque
            //  el interruptor esté ahí dentro.
            //
            //  Never shown, only searched: typing «gaps» deserves to find
            //  this section even though the switch lives inside a widget.
            claves: ["efectos", "effects", "blur", "desenfoque", "opacidad", "opacity", "sombra", "sombras", "shadow", "animacion", "animaciones", "animation"],
            glifo: 0xF00B5,
            desc: "Blur, opacity, shadows and animations.",
            vista: "efectos",
            opciones: []
        },
        {
            grupo: "Plugins",
            glifo: 0xF0431,
            desc: "What you have installed: on, off, and where it came from.",
            //  Esta sección no se pinta como una pila de interruptores: son
            //  casi cuarenta, y el ajuste de cada plugin estaba en OTRA
            //  sección. Se despliega cada uno con lo suyo dentro. La vista lo
            //  mira por este nombre; cualquier otro grupo se pinta como
            //  siempre.
            vista: "plugins",
            opciones: PluginManager.opcionesAjustes
        }
    //  Y al final, lo que aporten los plugins con K4.Ajustes. Van los
    //  últimos a propósito: lo de la barra primero, y lo instalado después,
    //  que es el orden en que la gente busca.
    ].concat(Enganches.gruposAjustes)

    //  Las alternativas de cada opción de varias respuestas.
    //
    //  Here and not in the view: each multi-choice option lists its
    //  alternatives here, so adding a choice never means touching the view.
    function opcionesDe(de) {
        if (de === "posiciones")
            return [{ codigo: "top",    nombre: "Top" },
                    { codigo: "bottom", nombre: "Bottom" }]
        //  De menos a más, que es como se lee una escala: quitar sitio
        //  siempre, quitarlo salvo cuando estorba, no quitarlo, y no estar.
        if (de === "reservas")
            return [{ codigo: "reserve", nombre: "Reserve space" },
                    { codigo: "auto",    nombre: "Away when fullscreen" },
                    { codigo: "onTop",   nombre: "On top" },
                    { codigo: "hidden",  nombre: "Hidden" }]
        if (de === "alineaciones")
            return [{ codigo: 15, nombre: "Left" },
                    { codigo: 50, nombre: "Centre" },
                    { codigo: 85, nombre: "Right" }]
        return []
    }

    function alternar(id) {
        if (String(id).indexOf("plugin_") === 0) {
            PluginManager.alternarAjuste(id)
            return
        }
        //  Los de un plugin no se guardan aquí: los guarda él. Nosotros solo
        //  le decimos que el usuario ha tocado, y él contesta con el valor
        //  nuevo en su `valores` — así lo que se ve es siempre lo guardado.
        if (String(id).indexOf("ext_") === 0) {
            Enganches.alternarAjuste(id)
            return
        }
        ajustes[id] = !ajustes[id]
        guardar()
    }

    //  Una acción con red: la pantalla la arma y la confirma, y aquí se hace.
    //  Va en el servicio y no en la vista porque es donde se declara la
    //  opción — la pantalla solo sabe pintar filas.
    function ejecutar(id) {
        if (String(id).indexOf("ext_") === 0)
            Enganches.alternarAjuste(id)
    }

    function valor(id) {
        if (String(id).indexOf("plugin_") === 0)
            return PluginManager.valorAjuste(id)
        if (String(id).indexOf("ext_") === 0)
            return Enganches.valorAjuste(id)
        return ajustes[id]
    }

    // ── persistencia ──────────────────────────────────────────────
    //
    //  Las claves, en una lista. Antes eran una línea por clave al guardar y otra
    //  al cargar, y con quince preferencias eso son treinta sitios donde
    //  olvidarse de una. Y una lista y no un recorrido del objeto entero porque
    //  un singleton tiene decenas de propiedades internas que no son ajustes.
    readonly property var claves: [
        "barPosition", "barAlignment", "islandSpace", "cerrarConClicFuera",
        "trayInPill", "notificationsOnHover", "notificationsOnFocus",
        "quickAccess"
    ]

    function guardar() {
        if (!cargado)
            return
        const d = {}
        for (let i = 0; i < claves.length; ++i)
            d[claves[i]] = ajustes[claves[i]]
        vista.setText(JSON.stringify(d, null, 1))
    }

    property bool cargado: false

    FileView { id: vista; path: ajustes.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: ajustes.cargar()
    }

    //  One-shot migration from the Spanish-era settings file: old key
    //  names, old stored values and old plugin ids become their English
    //  equivalents on load, so nobody loses their bar by updating.
    readonly property var clavesViejas: ({
        posicionBarra: "barPosition",
        alineacionBarra: "barAlignment",
        reservaIsla: "islandSpace",
        bandejaEnPildora: "trayInPill",
        notificacionesAlPasar: "notificationsOnHover",
        notificacionesAlEnfocar: "notificationsOnFocus",
        accesosDirectos: "quickAccess"
    })
    readonly property var valoresViejos: ({
        barPosition: { "arriba": "top", "abajo": "bottom" },
        islandSpace: { "reserva": "reserve", "completa": "auto",
                       "encima": "onTop", "escondida": "hidden" }
    })
    readonly property var idsViejos: ({
        sonido: "sound", pantallas: "displays", agentes: "agents"
    })

    function cargar() {
        const bruto = vista.text()

        if (bruto.length > 0) {
            try {
                let s = JSON.parse(bruto)
                for (const vieja in clavesViejas)
                    if (s[vieja] !== undefined && s[clavesViejas[vieja]] === undefined)
                        s[clavesViejas[vieja]] = s[vieja]
                for (const clave in valoresViejos)
                    if (typeof s[clave] === "string"
                        && valoresViejos[clave][s[clave]] !== undefined)
                        s[clave] = valoresViejos[clave][s[clave]]
                if (Array.isArray(s.quickAccess))
                    s.quickAccess = s.quickAccess.map(function (id) {
                        return idsViejos[id] !== undefined ? idsViejos[id] : id
                    })
                for (let i = 0; i < claves.length; ++i)
                    if (s[claves[i]] !== undefined)
                        ajustes[claves[i]] = s[claves[i]]
            } catch (e) {
                // preferencias ilegibles: se quedan las de fábrica
            }
        }

        cargado = true
    }
}
