//  Lock the session through the compositor.
//
//  Reexports WlSessionLock, which uses the `ext-session-lock` protocol. The
//  compositor draws the lock surface above everything and grants it exclusive
//  keyboard access: no window can draw over it or hear what you type. That
//  distinguishes a session lock from a window merely covering the screen.
//
//  Two important operational details:
//
//  1. Set `locked` to lock or unlock. The documented `unlock()` exists in C++
//     but is not exposed to QML.
//  2. If the process dies while locked, the compositor retains an orphaned
//     lock. A subsequent lock attempt causes a protocol error that terminates
//     the new client's connection. Recovery requires ending the session.

import Quickshell.Wayland

WlSessionLock {}
