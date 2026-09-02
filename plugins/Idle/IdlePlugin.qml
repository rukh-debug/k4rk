//  Píldora plegada: carátula · espacios de trabajo · hora · visualizador, más
//  los iconos de la bandeja si hay alguno.
//  Siempre activo con prioridad 0, así que es el fondo de armario: se ve
//  cuando ningún otro módulo quiere la island.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "idle"
    title: "Pill"
    priority: 0
    active: habilitado

    // el módulo de bandeja, que se abre al pulsar los iconos; lo inyecta el host
    property var tray: null

    // cuántos iconos caben sin que la píldora se desmadre; el resto se resume
    readonly property int trayShown: Math.min(Tray.count, 4)
    readonly property int trayWidth: Tray.count === 0 || !Settings.trayInPill
        ? 0 : trayShown * 18 + (Tray.count > trayShown ? 18 : 0) + 6

    // Cada flanco ocupa lo suyo y la hora se queda quieta por el ancla que se
    // publica abajo, no por reservar lo mismo a los dos lados. La simetría
    // hacía que cada píxel de indicador costase dos, y con dos o tres agentes
    // la island se iba de ancho hasta dejar de parecerse a una island.
    // La carátula y las barras van juntas a la izquierda, así que el hueco de
    // las barras se reserva ahí y no enfrente.
    //  Las extensiones de flanco (K4.Capsule → services/Extensions.qml):
    //  lo que la cápsula gana a cada lado mientras un plugin tiene algo
    //  que decir ahí. La píldora solo le hace sitio en el flanco que
    //  toque — el anclaje para que el cuerpo no se mueva lo hace el
    //  host con estos mismos números.
    readonly property int ladoIzq: (Media.isPlaying ? 53 : 0)
        + Extensions.leftWidth
    // Lo mismo para las cápsulas de lo que has dejado a medias: cada una puede
    // llegar a 116 px con su icono y su detalle recortado.
    readonly property int minimizadosWidth: Modulos.count * 116

    readonly property int ladoDer: trayWidth
        + minimizadosWidth + Indicadores.anchoAproximado
        + Extensions.rightWidth

    //  La medida REAL de cada fila, publicada por la vista. Las sumas de arriba
    //  se quedan como arranque y red de seguridad: en cuanto la vista existe,
    //  manda lo medido — y añadir un indicador nuevo deja de exigir acordarse
    //  de sumar su hueco aquí, que es como se pisó dos veces la hora.
    //
    //  Ahora también el flanco izquierdo: con la island creciendo hacia un solo
    //  lado, lo que mida la carátula corre el borde izquierdo, y una cuenta a
    //  ojo ahí se ve tanto como una a la derecha.
    property int ladoDerMedido: 0
    property int ladoIzqMedido: 0

    readonly property int derAncho: ladoDerMedido > 0 ? ladoDerMedido : ladoDer
    readonly property int izqAncho: ladoIzqMedido > 0 ? ladoIzqMedido : ladoIzq

    //  The centre is the clock's 46 — and while the desks parade, as
    //  wide as the row they wear: the view hands the number over on
    //  every show and takes it back on every hide, so the pill lends
    //  the parade its room for the moment instead of reserving it all
    //  day. (A fixed reservation for ten desks was the old disease:
    //  the centre ate half the bar to honor a flash.)
    property int centroAncho: 46

    //  Los cuatro huecos de 11 que separan las tres zonas entre sí y de los
    //  bordes. La vista reparte con estos mismos números, así que si cambian,
    //  cambian a la vez en los dos sitios o la cuenta deja de cuadrar.
    readonly property int holgura: 44

    //  Cada flanco ocupa lo suyo y nada más, en vez de reservar los dos el del
    //  más ancho. Eso hacía que cada píxel de indicador costase dos y que con
    //  tres agentes la island ocupase media pantalla, con la mitad vacía.
    //
    //  El precio es que la hora se corre un poco al aparecer o irse un
    //  indicador: la island va centrada, así que crece la mitad por cada lado.
    //  Se probó a clavarla con un ancla y sale peor de lo que arregla —la
    //  island deja de abrirse por igual hacia los dos lados, que es lo que se
    //  mira cada vez que pasas el ratón—. Antes esto se pagaba con el doble de
    //  ancho SIEMPRE, para que no se notara en un caso que pasa de vez en
    //  cuando.
    islandWidth: izqAncho + holgura + centroAncho + derAncho
    islandHeight: Theme.baseHeight

    view: Component {
        IdleView { plugin: self; tray: self.tray; shown: self.trayShown }
    }
}
