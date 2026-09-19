//  A separate window outside the island.
//
//  For modules that need more room than the bar provides: a fullscreen
//  picker, an editor or a view deserving half the screen.
//
//  Implemented as a `wlr-layer-shell` surface so it can appear above other
//  content without becoming a normal window that the compositor places,
//  moves and includes in Alt+Tab. A future Windows or Mac host could replace
//  this implementation without requiring plugin changes.
//
//  Fullscreen and transparent by default, the usual case for drawing custom
//  content over the existing desktop.
//
//      K4.Ventana {
//          nombre: "mi-selector"
//          conTeclado: true
//          Item { anchors.fill: parent; ... }
//      }

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: ventana

    // Appears in `hyprctl layers` and can be targeted by compositor rules.
    property string nombre: "k4"

    //  Monitor name, as reported by `hyprctl monitors`. Empty lets the
    //  compositor choose. Pair with `K4.Isla.rectEn(pantalla)` to anchor
    //  content to the island on THAT display.
    property string pantalla: ""

    screen: {
        if (pantalla.length === 0)
            return null
        const lista = Quickshell.screens
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].name === pantalla)
                return lista[i]
        return null
    }

    //  Whether to take exclusive keyboard focus. Use only when the visible
    //  surface needs it: no other window receives keys while the grab lasts.
    //
    //  On multi-monitor setups, an exclusive grab is NOT per screen. Wayland
    //  keyboard focus is shared across the session, and Hyprland treats an
    //  exclusive layer as a modal grab, stopping keyboard AND pointer events
    //  elsewhere. Testing a window on the second monitor prevented the first
    //  monitor's island from opening on hover and redirected typing even
    //  with another window focused. `tecladoAlPasar` addresses that case.
    property bool conTeclado: false

    //  Grab the keyboard ONLY while the pointer is over this window.
    //
    //  While interacting here, this window owns focus; moving to another
    //  screen releases it so the rest of the desktop works again. Takes
    //  precedence over `conTeclado` when both are enabled.
    //
    //  Release to OnDemand rather than None deliberately: OnDemand continues
    //  receiving pointer input, allowing the pointer to re-enter.
    property bool tecladoAlPasar: false

    //  Is the pointer inside? The CONTENT OWNER reports this, not the window.
    //
    //  The window does not know its contents, and only the topmost item sees
    //  hover reliably. A listener placed here is covered by the caller's
    //  children, which are created afterward. The view owner controls that
    //  stack and can bind this to its background, card or both with an OR.
    //
    //  Both automatic approaches were tested and failed: an Item containing
    //  a HoverHandler behind everything is covered, while a bare HoverHandler
    //  inside PanelWindow attaches to no item and reports `hovered` as
    //  undefined. Explicitly assigning its parent with
    //  `HoverHandler { parent: ventana.contentItem }` did not raise a QML
    //  error: it CRASHED Quickshell during window construction, subsequently
    //  reproduced in the test bench.
    property bool ratonDentro: false


    // Above everything, including the island.
    property bool encima: true

    //  Layer selection. Three choices, with the middle one as the usual layer:
    //
    //   · "fondo" — BELOW windows, for desktop content. It does not cover the
    //     island or any application, and a maximized window hides it.
    //
    //     Uses `Bottom`, not `Background`, despite the setting's name.
    //     Wallpaper daemons such as swaybg and swww use `Background`, where
    //     creation order determines stacking. Changing wallpaper restarts
    //     swaybg, placing its new surface ABOVE an older drawing surface and
    //     silently hiding it. Observed in `hyprctl layers`: `0. k4-fondo`
    //     followed by `1. wallpaper`, with the canvas rendering underneath.
    //     `Bottom` remains below application windows but above wallpaper,
    //     which is the required arrangement for desktop drawing.
    //   · "normal" — above windows and below the island.
    //   · "encima" — above everything, including the island.
    //
    //  The existing `encima` shortcut still selects the two original layers,
    //  so `capa` starts bound to it. Assigning `capa` breaks that binding and
    //  lets the more specific choice win. Callers that never assign it keep
    //  their previous behavior.
    //
    //  In "fondo" mode, set `zonaActiva`: without it, the mask stays null and
    //  the surface captures ALL desktop clicks. On the bottom layer that
    //  makes the desktop stop responding. A background should not catch
    //  clicks; supply a 0×0 Item.
    property string capa: ventana.encima ? "encima" : "normal"

    //  Background content does not reserve desktop space: content underneath
    //  cannot push windows above it, so `reserva` is not meaningful there.

    //  The part of the surface that captures clicks.
    //
    //  Without this, a fullscreen window captures ALL pointer input even if
    //  it only draws a central panel. Point this at the panel to leave the
    //  surrounding desktop usable while the window is shown.
    property Item zonaActiva: null

    //  Anchored edges. All four, the default, produce a fullscreen overlay.
    //  Release one edge to make a strip anchored to the opposite edge, the
    //  shape needed by a surface that reserves desktop space.
    property bool pegadaArriba: true
    property bool pegadaAbajo: true
    property bool pegadaIzquierda: true
    property bool pegadaDerecha: true

    anchors.top: pegadaArriba
    anchors.left: pegadaIzquierda
    anchors.right: pegadaDerecha
    anchors.bottom: pegadaAbajo

    color: "transparent"

    //  Desktop space reserved at the edge, in pixels. The default 0 reserves
    //  none: this window floats over the desktop without rearranging windows
    //  underneath.
    //
    //  Reserve space for persistent content such as a dock or permanent strip.
    //  Transient animations, notices and decorations should keep this at 0,
    //  or the desktop would rearrange whenever they appear.
    //
    //  Only meaningful for an edge strip: with all four edges anchored there
    //  is no single edge to reserve from, so the compositor ignores it.
    property int reserva: 0

    //  A value of -1 reserves nothing AND ignores other surfaces' reservations,
    //  allowing edge-to-edge drawing through their reserved areas.
    //
    //  Use this when drawing OVER the bar's strip. Otherwise a fullscreen
    //  window may start below the bar and place its content 34 px lower than
    //  its coordinates suggest.
    exclusionMode: reserva > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: reserva

    mask: ventana.zonaActiva ? recorteZona : null

    property Region recorteZona: Region { item: ventana.zonaActiva }

    WlrLayershell.namespace: ventana.nombre
    WlrLayershell.layer: ventana.capa === "fondo" ? WlrLayer.Bottom
        : (ventana.capa === "encima" ? WlrLayer.Overlay : WlrLayer.Top)
    WlrLayershell.keyboardFocus: {
        if (ventana.tecladoAlPasar)
            return ventana.ratonDentro ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.OnDemand
        return ventana.conTeclado ? WlrKeyboardFocus.Exclusive
                                  : WlrKeyboardFocus.None
    }
}
