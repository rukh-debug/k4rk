//  La forma de la island: el cuerpo redondeado y las dos esquinas invertidas
//  que lo funden con el borde de la pantalla.
//
//  Vivía suelta dentro de `shell.qml`. Sale a su propio fichero porque ahora la
//  dibujan DOS sitios: la barra de verdad y la previsualización de Ajustes, que
//  no sería una previsualización si dibujara otra cosa — un rectángulo azul
//  redondeado no es esta forma, y lo que se quiere enseñar es precisamente cómo
//  queda.
//
//  Ojo con los tamaños pequeños: hace falta `2·(ala + radio)` de ancho para que
//  el trazado se cierre. Con menos, la curva derecha empieza antes de que acabe
//  la izquierda, el recorrido se cruza y sale un rectángulo; y si `ala + radio`
//  llega justo a la mitad, las dos curvas de abajo se juntan en punta y sale un
//  champiñón. Por eso los radios se acotan por el ANCHO y no solo por el alto.
//
//  El trazado se define en coordenadas DE BORDE —(u, v): u a lo largo del
//  borde, v la distancia a él— y `punto()` las traduce al item. Así los cuatro
//  lados son el mismo dibujo con otro mapa, y no cuatro formas que irse
//  desincronizando. Las esquinas invertidas quedan SIEMPRE en el lado que toca
//  el borde de la pantalla, que es el punto de fundirse con él; las redondeadas,
//  enfrente.

import QtQuick
import QtQuick.Shapes

Shape {
    id: silueta

    //  Cuánto muerde cada esquina invertida hacia dentro.
    property real ala: Theme.wing

    //  El redondeo de las dos esquinas contrarias al borde.
    property real cuerpoRadio: 20

    property color relleno: Theme.islandBg

    //  De qué borde cuelga la island: "top" · "bottom" · "left" · "right".
    //  «bottom» fue un `reflejada` que daba la vuelta al dibujo; con vistas
    //  que pueden abrirse en cualquier borde, la generalización es el mapa.
    property string lado: "top"

    // CurveRenderer suaviza mejor, pero descarta las esquinas invertidas (las
    // alas), así que se antialiasa con MSAA.
    antialiasing: true
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    //  «bottom» y «left» reflejan el dibujo, y una reflexión invierte el
    //  sentido de cada arco: sin esto el relleno saldría del revés — la forma
    //  bien, el agujero dentro.
    readonly property bool voltear: lado === "bottom" || lado === "left"

    //  A lo largo del borde, y de grosor: según el lado, uno es el ancho del
    //  item y el otro su alto.
    readonly property real largo:
        (lado === "left" || lado === "right") ? height : width
    readonly property real grueso:
        (lado === "left" || lado === "right") ? width : height

    function punto(u, v) {
        if (lado === "bottom")
            return Qt.point(u, height - v)
        if (lado === "left")
            return Qt.point(v, u)
        if (lado === "right")
            return Qt.point(width - v, u)
        return Qt.point(u, v)
    }

    ShapePath {
        id: trazo

        fillColor: silueta.relleno
        strokeWidth: 0
        strokeColor: "transparent"

        readonly property real largo: silueta.largo
        readonly property real grueso: silueta.grueso
        //  Acotados por el ancho además de por el alto: ver la nota de arriba.
        readonly property real g: Math.max(0, Math.min(silueta.ala,
                                                       grueso / 2,
                                                       largo / 6))
        readonly property real r: Math.max(0, Math.min(silueta.cuerpoRadio,
                                                       grueso / 2,
                                                       largo / 3 - trazo.g))

        //  Cada nodo del trazado, ya mapeado al item.
        readonly property var p0: silueta.punto(0, 0)
        readonly property var p1: silueta.punto(trazo.g, trazo.g)
        readonly property var p2: silueta.punto(trazo.g, grueso - trazo.r)
        readonly property var p3: silueta.punto(trazo.g + trazo.r, grueso)
        readonly property var p4: silueta.punto(largo - trazo.g - trazo.r, grueso)
        readonly property var p5: silueta.punto(largo - trazo.g, grueso - trazo.r)
        readonly property var p6: silueta.punto(largo - trazo.g, trazo.g)
        readonly property var p7: silueta.punto(largo, 0)

        startX: trazo.p0.x
        startY: trazo.p0.y

        // esquina invertida del principio del borde
        PathArc {
            x: trazo.p1.x; y: trazo.p1.y
            radiusX: trazo.g; radiusY: trazo.g
            direction: silueta.voltear ? PathArc.Counterclockwise
                                       : PathArc.Clockwise
        }

        PathLine { x: trazo.p2.x; y: trazo.p2.y }

        // redonda del lado interior, principio
        PathArc {
            x: trazo.p3.x; y: trazo.p3.y
            radiusX: trazo.r; radiusY: trazo.r
            direction: silueta.voltear ? PathArc.Clockwise
                                       : PathArc.Counterclockwise
        }

        PathLine { x: trazo.p4.x; y: trazo.p4.y }

        // redonda del lado interior, final
        PathArc {
            x: trazo.p5.x; y: trazo.p5.y
            radiusX: trazo.r; radiusY: trazo.r
            direction: silueta.voltear ? PathArc.Clockwise
                                       : PathArc.Counterclockwise
        }

        PathLine { x: trazo.p6.x; y: trazo.p6.y }

        // esquina invertida del final del borde
        PathArc {
            x: trazo.p7.x; y: trazo.p7.y
            radiusX: trazo.g; radiusY: trazo.g
            direction: silueta.voltear ? PathArc.Counterclockwise
                                       : PathArc.Clockwise
        }

        PathLine { x: trazo.p0.x; y: trazo.p0.y }
    }
}
