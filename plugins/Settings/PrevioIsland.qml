//  A fake screen showing how it will look.
//
//  The three options above —where it lives, how it aligns and how it
//  takes space— explain badly in words. «Reserve space» and «On top»
//  sound alike and do very different things to your windows, and
//  the only way to know which one you wanted was to apply it, look
//  at the desktop and undo it.
//
//  Here it is seen before: the bar where it will be, with its
//  alignment, and a fake window that steps aside or not depending
//  on what you choose. It updates on touching any of the three.
//
//  The dock too, if you have it up, because it shares the screen
//  with the bar and a preview omitting it would be lying by
//  omission. Its options are not here —they live in Plugins, inside
//  «Dual mode»— and that is said below.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: previo

    spacing: 8

    //  What is being looked at. With no saved value the same the
    //  factory bar uses is taken, or the preview would lie on a
    //  clean start.
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

    //  Does it push windows aside? «Reserve» always; «auto» yes
    //  except when something is fullscreen, and that cannot be told
    //  apart in a still drawing, so it draws as if yes and is
    //  explained below.
    readonly property bool aparta: previo.sitio === "reserve"
                                   || previo.sitio === "auto"
    readonly property bool escondida: previo.sitio === "hidden"

    //  The height of the monitor you are on, so the sketch's scale
    //  is yours and not an invented one.
    readonly property real altoPantalla: Island.altoPantalla

    // ── your desktop wallpaper, the real one ─────────────────────
    //
    //  A sketch with an invented gray shows the shape but not how it
    //  LOOKS. With the real wallpaper it stops being a diagram.
    //
    //  `Fondos`, the service, knows it: which one is set, where its
    //  frame lives if it is a video, and how many gaps Hyprland has.
    //  This used to be a shell command with `md5sum` because that
    //  information lived inside the theme plugin and there was no way
    //  to ask it. Now it is a property: zero processes, and it learns
    //  on its own when you change wallpaper.
    readonly property string poster: {
        const r = Fondos.actualDe("")
        if (r.length === 0)
            return ""
        return "file://" + (Fondos.esQuieto(r) ? r : Fondos.posterDe(r))
    }

    //  Hyprland's gaps. The fake window respects them, and it is
    //  not decoration: your desktop has gaps, so a window reaching
    //  the edges would be showing something that does not happen —
    //  and would cover the whole wallpaper on the way, which is
    //  exactly what one came to see.
    readonly property int huecos: Fondos.huecos

    // ── the screen ────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(width * 9 / 16)
        Layout.maximumHeight: 360
        radius: 10
        color: "#0d1117"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
        clip: true

        //  A fake desktop, and BRIGHT on purpose.
        //
        //  The island is black —`Theme.islandBg` is #000000 with the
        //  theme's tint— so on a dark wallpaper it would not show:
        //  on your screen it shows because it sits on top of the
        //  desktop wallpaper. A sketch where the bar is invisible
        //  teaches nothing, so here the floor is a bluish gray
        //  standing in for the wallpaper.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#4a5a6e" }
                GradientStop { position: 0.55; color: "#33404f" }
                GradientStop { position: 1; color: "#232c37" }
            }
        }

        //  And on top, your wallpaper, if it could be resolved. The
        //  gradient above stays underneath as a net: if the file is
        //  not there —wallpaper just changed, cache not yet made—
        //  this does not load and no black hole shows, the gradient
        //  does.
        Image {
            anchors.fill: parent
            visible: status === Image.Ready
            source: previo.poster
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            //  It paints small; asking Qt to downscale on the fly
            //  spares a 1920-wide texture to fill 700.
            sourceSize.width: 900
        }

        //  The fake window. It is what truly shows the difference
        //  between reserving space and sitting on top: here it steps
        //  aside or not.
        Rectangle {
            id: ventanita

            //  What the bar takes from it, at the same scale as
            //  everything: if it reserves, its real 34 px carried into
            //  the sketch.
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

        //  The bar. And it IS the bar: the same `SiluetaIsla` that
        //  draws the real one, with its wing and its radius, not a
        //  rounded rectangle that looks like it. The only thing that
        //  changes is the scale.
        //
        //  Hidden it draws as the peeking edge, which is exactly
        //  what that option shows until you bring the mouse to the
        //  edge.
        Item {
            id: barrita

            //  At true scale: what the island measures right now,
            //  carried into what this sketch measures against the
            //  screen. This way the proportion is not an estimate, it
            //  is your monitor's.
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
                //  The wing and the radius, at the same scale as
                //  everything else: left at their usual size, at this
                //  size the path crosses itself and out comes a
                //  mushroom.
                ala: Math.max(1, Theme.wing * barrita.escala)
                cuerpoRadio: Math.max(1, 20 * barrita.escala)
                relleno: Theme.islandBg
                lado: previo.donde === "bottom" ? "bottom" : "top"
            }

            //  The edge, for the hidden option.
            Rectangle {
                anchors.fill: parent
                visible: previo.escondida
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.30)
            }
        }
    }

    // ── what the drawing cannot say ───────────────────────────────
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
