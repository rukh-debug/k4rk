//  What is drawn while the session is locked.
//
//  The compositor creates one per monitor. Reexports WlSessionLockSurface,
//  which only makes sense inside a K4.BloqueoSesion.

import Quickshell.Wayland

WlSessionLockSurface {}
