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

    // ── captura y grabación ───────────────────────────────────────
    // services/Captura.qml los lee. Estaban a fuego ahí, con un comentario que
    // decía «en la fase 6 los lee de Settings»: esta es la fase 6.
    property string capturaDestino: "ambos"     // fichero · portapapeles · ambos
    property bool capturaCursor: false          // ¿sale el puntero en la foto?
    property string grabarAudio: "ambos"        // ninguno · sistema · micro · ambos
    //  Qué micrófono y qué salida se graban. «auto» sigue al del sistema, que
    //  es lo de siempre; un nombre concreto lo fija aunque cambie el defecto.
    property string grabarMicro: "auto"
    property string grabarSalida: "auto"
    property string grabarCodec: "h264"         // h264 · hevc
    property int grabarFps: 60
    //  ¿Grabar también la cámara, en un fichero aparte?
    //
    //  Aparte y no incrustada: así en el editor se coloca, se escala y se quita
    //  cuando quieras, en vez de quedar pegada al vídeo para siempre.
    property bool grabarCamara: false
    //  Qué cámara. Vacío es «la primera que haya», que es lo que quiere
    //  cualquiera con una sola. Se rellena solo al detectarlas.
    property string camaraDispositivo: ""

    // ── editor ────────────────────────────────────────────────────
    // services/Editor.qml los lee.
    property bool zoomAuto: true                // ¿propone momentos al grabar?
    property real zoomNivel: 2.5                // cuánto amplía como máximo
    property string editorCodec: "h264"         // con qué se renderiza
    //  Normalizar la sonoridad al renderizar: −14 LUFS, lo que espera
    //  YouTube. Apagado de fábrica: tocar el volumen de nadie sin permiso no.
    property bool editorSonoridad: false

    // ── barra ─────────────────────────────────────────────────────
    //  En qué borde vive la barra. shell.qml ancla la ventana, voltea la
    //  silueta y orienta los gestos con esto; los plugins lo leen por
    //  K4.Isla.posicion para adaptar lo que pinten fuera.
    property string posicionBarra: "arriba"     // arriba · abajo
    //  En qué punto del borde se centra la island, en tanto por ciento del
    //  ancho libre: 50 es el centro de siempre. Un plugin puede desplazarla
    //  TEMPORALMENTE con K4.Isla.colocar; esto es la base a la que vuelve.
    property int alineacionBarra: 50            // 15 · 50 · 85
    //  Qué hace la barra con el sitio del escritorio.
    //
    //  «reserva» es lo de siempre: la franja plegada se le quita al escritorio
    //  y ninguna ventana se mete debajo. «encima» no le quita nada —la píldora
    //  flota sobre las ventanas— y «escondida» además la retira por el borde
    //  hasta que hay algo que enseñar. Y «completa» no es un cuarto estado
    //  sino una regla: reserva como siempre, y se esconde SOLO mientras una
    //  ventana llena la pantalla. shell.qml es quien las obedece.
    property string reservaIsla: "reserva"   // reserva · completa · encima · escondida
    //  Click outside the bar closes whatever view is deployed, like Escape.
    //  shell.qml grows its surface to the whole screen while a view is open
    //  and spends the outside tap on closing it. Off is the old behavior:
    //  the click passes through to the desktop and the view stays.
    property bool cerrarConClicFuera: true
    // widgets/TrayRow.qml: iconos de bandeja en la píldora
    // Apagada de fábrica: en la píldora los iconos de bandeja son ruido casi
    // siempre, y al acercar el ratón la island ya se abre y ahí sí se ven —y
    // encima se pueden pulsar, que en la píldora no—.
    property bool bandejaEnPildora: false
    // widgets/NotifStrip.qml: notificaciones recientes al pasar el ratón
    property bool notificacionesAlPasar: true
    // services/Notifs.qml: descartar las de una aplicación al ir a su ventana
    property bool notificacionesAlEnfocar: true

    // ── accesos directos ──────────────────────────────────────────
    //  Qué aplicaciones salen en la franja del centro de control, por id de
    //  plugin. plugins/Panel/PanelView.qml la pinta y el centro de
    //  aplicaciones la edita con la chincheta de cada tarjeta.
    //
    //  Ids y no una copia de nombres e iconos: así al renombrar un plugin o
    //  cambiarle el icono el acceso directo se entera solo, y uno que apunte a
    //  un plugin desinstalado simplemente no se pinta.
    property var accesosDirectos: ["game", "settings", "system", "clipboard"]

    function esAccesoDirecto(id) {
        return (accesosDirectos || []).indexOf(id) >= 0
    }

    function alternarAcceso(id) {
        const l = (accesosDirectos || []).slice()
        const i = l.indexOf(id)
        if (i >= 0)
            l.splice(i, 1)
        else
            l.push(id)
        accesosDirectos = l
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
            grupo: "Capture",
            glifo: 0xF0100,
            desc: "What goes into the shot, and what happens to it afterwards.",
            opciones: [
                { id: "capturaDestino", tipo: "eleccion", de: "destinos",
                  nombre: "What to do with the shot",
                  desc: "What happens when you capture without saying more",
                  glifo: 0xF0E51 },
                { id: "capturaCursor", nombre: "Include the pointer",
                  desc: "The pointer shows wherever it was on capture",
                  glifo: 0xF037D }
            ]
        },
        {
            grupo: "Recording",
            glifo: 0xF044A,
            desc: "Audio, camera and quality of what you record.",
            opciones: [
                { id: "grabarAudio", tipo: "eleccion", de: "audios",
                  nombre: "Which sound gets recorded",
                  desc: "On separate tracks, to balance them later",
                  glifo: 0xF057E },
                { id: "grabarMicro", tipo: "eleccion", de: "microfonos",
                  nombre: "Microphone",
                  desc: "Automatic follows the system",
                  glifo: 0xF036C },
                { id: "grabarSalida", tipo: "eleccion", de: "salidas",
                  nombre: "Output that gets recorded",
                  desc: "Where the system sound comes from",
                  glifo: 0xF04C3 },
                { id: "grabarFps", tipo: "eleccion", de: "fps",
                  nombre: "Frames per second",
                  desc: "60 is smoother and twice the size",
                  glifo: 0xF0567 },
                { id: "grabarCodec", tipo: "eleccion", de: "codecs",
                  nombre: "Recording codec",
                  desc: "HEVC is smaller and slower to open",
                  glifo: 0xF0381 },
                //  Solo si hay cámara: ofrecer un interruptor que no puede
                //  hacer nada es peor que no ofrecerlo.
                { id: "grabarCamara", nombre: "Also record the camera",
                  desc: "In a separate file, to place it in the editor",
                  glifo: 0xF0567, si: "camara" }
            ]
        },
        {
            grupo: "Editor",
            glifo: 0xF03EB,
            desc: "The editor that opens when you finish capturing.",
            opciones: [
                { id: "zoomAuto", nombre: "Propose zoom while recording",
                  desc: "From the cursor trail and the clicks",
                  glifo: 0xF1276 },
                { requiere: "zoomAuto", id: "zoomNivel", tipo: "eleccion",
                  de: "niveles",
                  nombre: "How much it zooms",
                  desc: "The ceiling for the moments it proposes",
                  glifo: 0xF034B },
                { id: "editorCodec", tipo: "eleccion", de: "codecs",
                  nombre: "Render codec",
                  desc: "The one for videos leaving the editor",
                  glifo: 0xF0381 },
                { id: "editorSonoridad",
                  nombre: "YouTube loudness",
                  desc: "Normalizes to −14 LUFS when rendering",
                  glifo: 0xF147D }
            ]
        },
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
                { id: "posicionBarra", tipo: "eleccion", de: "posiciones",
                  nombre: "Where the bar lives",
                  desc: "The island and its wings flip on their own",
                  glifo: 0xF10A9 },
                { id: "alineacionBarra", tipo: "eleccion", de: "alineaciones",
                  nombre: "Island alignment",
                  desc: "Where along the edge it sits",
                  glifo: 0xF11C3 },
                { id: "reservaIsla", tipo: "eleccion", de: "reservas",
                  nombre: "How it takes up space",
                  desc: "Pushes windows aside, floats over them, or hides",
                  glifo: 0xF003E },   // md-arrange_bring_to_front
                { id: "cerrarConClicFuera", nombre: "Click outside closes what's open",
                  desc: "Same as Escape: a deployed view closes when you click outside the bar",
                  glifo: 0xF037D },   // md-cursor-default
                { id: "bandejaEnPildora", nombre: "Tray in the pill",
                  desc: "Icons of background apps", glifo: 0xF0FB0 },
                { id: "notificacionesAlPasar", nombre: "Notifications on hover",
                  desc: "Recent ones, under the clock and player", glifo: 0xF009A },
                { id: "notificacionesAlEnfocar", nombre: "Dismiss when you switch to the app",
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
        //  «Anotar» dejó de ser un destino: el anotador se abre desde la
        //  tarjeta cuando se pide, no solo en cada captura. Un valor viejo
        //  guardado sigue valiendo como «Guardar».
        if (de === "destinos")
            return [{ codigo: "fichero",      nombre: "Save" },
                    { codigo: "portapapeles", nombre: "Copy" },
                    { codigo: "ambos",        nombre: "Both" }]
        if (de === "audios")
            return [{ codigo: "ninguno", nombre: "None" },
                    { codigo: "sistema", nombre: "System" },
                    { codigo: "micro",   nombre: "Mic" },
                    { codigo: "ambos",   nombre: "Both" }]
        //  Los dispositivos de verdad, con su etiqueta legible. Los lista
        //  Captura vía pactl; aquí solo se les pone «Automático» delante.
        //  «Automático» dice a QUIÉN sigue: «Automático (G733)». Sin eso,
        //  elegirlo es elegir a ciegas, y el día que el defecto del sistema no
        //  es el micro que tienes delante, la grabación sale muda y no hay
        //  dónde verlo antes de grabar.
        if (de === "microfonos")
            return [{ codigo: "auto",
                      nombre: Captura.etiquetaMicroDefecto
                          ? "Automatic" + " (" + Captura.etiquetaMicroDefecto + ")"
                          : "Automatic" }]
                .concat(Captura.microfonos.map(function (m) {
                    return { codigo: m.nombre, nombre: m.etiqueta }
                }))
        if (de === "salidas")
            return [{ codigo: "auto",
                      nombre: Captura.etiquetaSalidaDefecto
                          ? "Automatic" + " (" + Captura.etiquetaSalidaDefecto + ")"
                          : "Automatic" }]
                .concat(Captura.salidasAudio.map(function (s) {
                    return { codigo: s.nombre, nombre: s.etiqueta }
                }))
        if (de === "codecs")
            return [{ codigo: "h264", nombre: "H.264" },
                    { codigo: "hevc", nombre: "HEVC" }]
        if (de === "fps")
            return [{ codigo: 30, nombre: "30" },
                    { codigo: 60, nombre: "60" }]
        if (de === "posiciones")
            return [{ codigo: "arriba", nombre: "Top" },
                    { codigo: "abajo",  nombre: "Bottom" }]
        //  De menos a más, que es como se lee una escala: quitar sitio
        //  siempre, quitarlo salvo cuando estorba, no quitarlo, y no estar.
        if (de === "reservas")
            return [{ codigo: "reserva",   nombre: "Reserve space" },
                    { codigo: "completa",  nombre: "Away when fullscreen" },
                    { codigo: "encima",    nombre: "On top" },
                    { codigo: "escondida", nombre: "Hidden" }]
        if (de === "alineaciones")
            return [{ codigo: 15, nombre: "Left" },
                    { codigo: 50, nombre: "Centre" },
                    { codigo: 85, nombre: "Right" }]
        if (de === "niveles")
            //  Etiquetas y no números: «2,5» no le dice nada a nadie, y lo que se
            //  quiere elegir es cuánto se nota.
            return [{ codigo: 1.8, nombre: "Soft" },
                    { codigo: 2.5, nombre: "Medium" },
                    { codigo: 3.2, nombre: "Strong" }]
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
        "capturaDestino", "capturaCursor",
        "grabarAudio", "grabarMicro", "grabarSalida", "grabarCodec", "grabarFps",
        "grabarCamara", "camaraDispositivo",
        "zoomAuto", "zoomNivel", "editorCodec", "editorSonoridad",
        "posicionBarra", "alineacionBarra", "reservaIsla", "cerrarConClicFuera",
        "bandejaEnPildora", "notificacionesAlPasar", "notificacionesAlEnfocar",
        "accesosDirectos"
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

    function cargar() {
        const bruto = vista.text()

        if (bruto.length > 0) {
            try {
                const s = JSON.parse(bruto)
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
