//  One wallpaper layer: what gets painted from ONE file.
//
//  It comes out of the canvas because transitions need TWO at once —
//  the leaving one and the arriving one— and having the whole drawing
//  kit duplicated by hand in the same file was asking for them to
//  fall out of step.
//
//  It knows nothing of transitions or screens: it is given a path, a
//  type and whether it must move, and it paints. Who is in front and
//  how much is visible the canvas decides, being the one holding
//  both.

import QtQuick
import QtMultimedia
import K4 as K4

Item {
    id: capa

    property string ruta: ""
    property string tipo: "nada"

    //  Is it its turn to move? This is the occlusion pause, which
    //  the canvas decides. A layer that cannot be seen decompresses
    //  not one frame.
    property bool animando: true

    //  So the photo is requested at the screen's size and not the
    //  file's.
    property int anchoPantalla: 1920
    property int altoPantalla: 1080

    //  Whoever knows whether there is a copy of the video cut to
    //  this screen. The canvas sets it; without it the original
    //  plays and that is that, since this layer must keep working
    //  loose.
    property var plugin: null

    //  And the path that PLAYS, not always the one asked for: for
    //  a video bigger than the screen, its cached copy. Same idea as
    //  the photo's `sourceSize` below, and for the same reasons —see
    //  `videoAMedida` in HyprThemePlugin.qml, with the measured
    //  numbers—.
    readonly property string rutaVideo: capa.tipo !== "video" ? ""
        : (capa.plugin ? capa.plugin.videoAMedida(capa.ruta, capa.anchoPantalla)
                       : capa.ruta)

    //  Asking DOES have an effect, so it is done from handlers and
    //  never from a binding.
    function pedirAMedida() {
        if (capa.plugin && capa.tipo === "video" && capa.ruta.length > 0)
            capa.plugin.pedirEscalado(capa.ruta, capa.anchoPantalla)
    }

    onAnchoPantallaChanged: capa.pedirAMedida()
    Component.onCompleted: capa.pedirAMedida()

    //  Black underneath: if the image does not fill —a portrait
    //  photo on a landscape monitor— what peeks out is this and not
    //  the desktop behind.
    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: capa.tipo !== "nada"
    }

    Image {
        anchors.fill: parent
        visible: capa.tipo === "quieto"
        source: capa.tipo === "quieto" ? "file://" + capa.ruta : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        //  At the screen's resolution and not the file's: a 6000 px
        //  photo on a 1920 monitor is 140 MB of texture to show
        //  exactly the same.
        sourceSize.width: capa.anchoPantalla
        sourceSize.height: capa.altoPantalla
    }

    AnimatedImage {
        anchors.fill: parent
        visible: capa.tipo === "animado"
        source: capa.tipo === "animado" ? "file://" + capa.ruta : ""
        fillMode: Image.PreserveAspectCrop
        //  An AnimatedImage keeps decompressing frames even with
        //  its Item invisible, so the pause must be told to it.
        playing: visible && capa.animando
        //  No cache: a wallpaper GIF is megabytes that will not be
        //  reused and would sit in the whole engine's image cache.
        cache: false
    }

    VideoOutput {
        id: salida
        anchors.fill: parent
        visible: capa.tipo === "video"
        fillMode: VideoOutput.PreserveAspectCrop
    }

    MediaPlayer {
        id: reproductor
        videoOutput: salida
        loops: MediaPlayer.Infinite
        //  The copy if already there, else the original. When the
        //  copy finishes this changes and the player restarts: one
        //  jump, once, in a wallpaper. Cheap against what it saves
        //  from then on.
        source: capa.rutaVideo.length > 0 ? "file://" + capa.rutaVideo : ""
        //  No AudioOutput on purpose, and not an oversight: a
        //  wallpaper makes no sound. Without audio output the
        //  decoder does not even open the track.
        onSourceChanged: if (source != "") capa.acompasar()
    }

    //  `pause` and not `stop`: stopping rewinds, so on uncovering
    //  the window the wallpaper would start over from the beginning
    //  instead of continuing where it was.
    function acompasar() {
        if (capa.tipo !== "video" || capa.ruta.length === 0)
            return
        if (capa.animando)
            reproductor.play()
        else
            reproductor.pause()
    }

    onAnimandoChanged: capa.acompasar()

    //  Both, and in one handler: QML cannot declare `onTipoChanged`
    //  twice.
    onTipoChanged: {
        capa.acompasar()
        capa.pedirAMedida()
    }

    onRutaChanged: capa.pedirAMedida()

    readonly property bool reproduciendo:
        reproductor.playbackState === MediaPlayer.PlayingState
    readonly property string fallo: String(reproductor.errorString || "")

    //  Is there anything to show yet? The canvas asks before
    //  starting a transition: fading toward a video that has not
    //  decoded its first frame is fading toward black and then
    //  jumping.
    readonly property bool listo: capa.tipo === "nada" ? true
        : capa.tipo === "video" ? reproductor.hasVideo
        : true
}
