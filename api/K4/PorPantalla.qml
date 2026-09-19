//  One instance per screen.
//
//  Multi-monitor surfaces often need one instance per display: a fullscreen
//  surface can cover both monitors, with each instance knowing its screen.
//  Reexports `Variants` with the screen model already assigned for that use.
//
//      K4.PorPantalla {
//          delegate: K4.Ventana { required property var modelData; screen: modelData }
//      }

import Quickshell

Variants {
    model: Quickshell.screens
}
