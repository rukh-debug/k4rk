//  Una pantalla de mentira que enseña cómo va a quedar.
//
//  Las tres opciones de arriba —dónde vive, cómo se alinea y cómo ocupa el
//  sitio— se explican mal con palabras. «Reservar sitio» y «Encima» suenan
//  parecido y hacen cosas muy distintas con tus ventanas, y la única forma de
//  saber cuál querías era aplicarlo, mirar el escritorio y deshacerlo.
//
//  Aquí se ve antes: la barra donde va a estar, con su alineación, y una
//  ventana de mentira que se aparta o no según lo que elijas. Se actualiza al
//  tocar cualquiera de las tres.
//
//  Dibuja también el dock si lo tienes puesto, porque comparte la pantalla con
//  la barra y una previsualización que lo omitiera estaría mintiendo por
//  omisión. Sus opciones no están aquí —viven en Plugins, dentro de «Modo
//  dual»— y por eso lo dice abajo.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: previo

    spacing: 8

    //  Lo que se está mirando. Sin valor guardado se usa lo mismo que usa la
    //  barra de fábrica, o la previsualización mentiría en un arranque limpio.
    readonly property string donde: {
        const v = Settings.valor("barPosition")
        return v === "bottom" ? "bottom" : "top"
    }

    readonly property int alineacion: {
        const v = parseInt(Settings.valor("barAlignment"), 10)
        return isNaN(v) ? 50 : v
    }

    readonly property string sitio: {
        const v = Settings.valor("islandSpace")
        return typeof v === "string" && v.length > 0 ? v : "reserve"
    }

    //  ¿Aparta las ventanas? «Reserva» siempre; «completa» sí salvo cuando algo
    //  está a pantalla completa, y eso en un dibujo quieto no se distingue, así
    //  que se dibuja como que sí y se cuenta debajo.
    readonly property bool aparta: previo.sitio === "reserve"
                                   || previo.sitio === "auto"
    readonly property bool escondida: previo.sitio === "hidden"

    //  El dock, si está. Sus ajustes son del plugin `dual`, así que se leen por
    //  su id con prefijo: los de fuera viven en otro cajón.
    //  El alto del monitor donde estás, para que la escala del croquis sea la
    //  tuya y no una inventada.
    readonly property real altoPantalla: Island.altoPantalla

    // ── tu fondo de escritorio, de verdad ─────────────────────────
    //
    //  El croquis con un gris inventado enseña la forma pero no cómo QUEDA.
    //  Con el fondo real deja de ser un diagrama.
    //
    //  Lo sabe `Fondos`, el servicio: cuál está puesto, dónde vive su fotograma
    //  si es un vídeo, y cuántos huecos tiene Hyprland. Antes esto era una orden
    //  de shell con `md5sum` porque esa información vivía dentro del plugin del
    //  tema y no había forma de preguntársela. Ahora es una property: cero
    //  procesos, y se entera sola cuando cambias de fondo.
    readonly property string poster: {
        const r = Fondos.actualDe("")
        if (r.length === 0)
            return ""
        return "file://" + (Fondos.esQuieto(r) ? r : Fondos.posterDe(r))
    }

    //  Los huecos de Hyprland. La ventana de mentira los respeta, y no es un
    //  adorno: tu escritorio tiene huecos, así que una ventana que llegara a los
    //  bordes estaría enseñando algo que no pasa — y de paso taparía el fondo
    //  entero, que es justo lo que se ha venido a ver.
    readonly property int huecos: Fondos.huecos

    // ── la pantalla ───────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(width * 9 / 16)
        Layout.maximumHeight: 360
        radius: 10
        color: "#0d1117"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
        clip: true

        //  Un escritorio de mentira, y CLARO a propósito.
        //
        //  La island es negra —`Theme.islandBg` es #000000 con el tinte del
        //  tema— así que sobre un fondo oscuro no se vería: en tu pantalla se
        //  ve porque está encima del fondo de escritorio. Un croquis en el que
        //  la barra es invisible no enseña nada, así que aquí el suelo es un
        //  gris azulado que hace de fondo de pantalla.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#4a5a6e" }
                GradientStop { position: 0.55; color: "#33404f" }
                GradientStop { position: 1; color: "#232c37" }
            }
        }

        //  Y encima, tu fondo, si se ha podido resolver. El degradado de arriba
        //  se queda debajo como red: si el fichero no está —fondo recién
        //  cambiado, caché aún sin hacer— esto no carga y no se ve un hueco
        //  negro, se ve el degradado.
        Image {
            anchors.fill: parent
            visible: status === Image.Ready
            source: previo.poster
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            //  Se pinta pequeño; pedirle a Qt que lo baje al vuelo ahorra
            //  tener una textura de 1920 de ancho para ocupar 700.
            sourceSize.width: 900
        }

        //  La ventana de mentira. Es la que enseña de verdad la diferencia
        //  entre reservar sitio y ponerse encima: aquí se aparta o no.
        Rectangle {
            id: ventanita

            //  Lo que la barra le quita, a la misma escala que todo: si
            //  reserva, son sus 34 px de verdad llevados al croquis.
            readonly property int hueco: previo.aparta && !previo.escondida
                ? Math.round(Theme.baseHeight * barrita.escala) : 0

            readonly property real margen: Math.max(1, previo.huecos * barrita.escala)

            x: margen
            width: parent.width - margen * 2
            y: (previo.donde === "top" ? hueco : 0) + margen
            height: parent.height - hueco - margen * 2
            radius: Math.max(2, 8 * barrita.escala)
            color: Qt.rgba(0.09, 0.11, 0.14, 0.88)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            IslandLabel {
                anchors.centerIn: parent
                text: "a window"
                color: Qt.rgba(1, 1, 1, 0.30)
                font.pixelSize: 10
            }
        }

        //  La barra. Y es LA barra: la misma `SiluetaIsla` que dibuja la de
        //  verdad, con su ala y su radio, no un rectángulo redondeado que se
        //  le parezca. Lo único que cambia es la escala.
        //
        //  Escondida se dibuja como el filo que asoma, que es exactamente lo
        //  que se ve en esa opción hasta que acercas el ratón al borde.
        Item {
            id: barrita

            //  A escala de verdad: lo que mide la island ahora mismo, llevado
            //  a lo que mide este croquis respecto a la pantalla. Así la
            //  proporción no es una estimación, es la de tu monitor.
            readonly property real escala: parent.height / previo.altoPantalla
            readonly property real anchoReal: Math.max(160, Island.rect.ancho || 380)

            width: Math.max(24, anchoReal * escala)
            height: previo.escondida ? 3 : Math.max(4, Theme.baseHeight * escala)

            x: Math.round((parent.width - width) * previo.alineacion / 100)
            y: previo.donde === "top"
                ? 0 : parent.height - height

            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200 } }

            SiluetaIsla {
                anchors.fill: parent
                visible: !previo.escondida
                //  El ala y el radio, a la misma escala que todo lo demás: si
                //  se dejaran en su tamaño de siempre, a este tamaño el
                //  trazado se cruza y sale un champiñón.
                ala: Math.max(1, Theme.wing * barrita.escala)
                cuerpoRadio: Math.max(1, 20 * barrita.escala)
                relleno: Theme.islandBg
                lado: previo.donde === "bottom" ? "bottom" : "top"
            }

            //  El filo, para la opción escondida.
            Rectangle {
                anchors.fill: parent
                visible: previo.escondida
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.30)
            }
        }
    }

    // ── lo que el dibujo no puede decir ───────────────────────────
    IslandLabel {
        Layout.fillWidth: true
        text: {
            if (previo.sitio === "reserve")
                return "Windows start where the bar ends."
            if (previo.sitio === "auto")
                return "Pushes windows aside, except when one is fullscreen: then it gets out of the way."
            if (previo.sitio === "onTop")
                return "Windows take the whole screen and the bar floats over them."
            return "Not visible until you take the pointer to the edge."
        }
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }
}
