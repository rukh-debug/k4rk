//  Commands arriving from outside, usually through a keyboard shortcut.
//
//  Deliberately reexports rather than wraps IpcHandler: callers declare
//  functions inside the object, so they cannot be forwarded individually.
//  This hides the underlying platform, which is the purpose of this API.
//
//  IpcHandler does NOT support an attached `Component.onDestruction`:
//  it reports "Non-existent attached object", and the compiled cache can
//  hide that error until a fresh compilation. The plugin manager unregisters
//  targets by disabling `enabled` before destroying the plugin.
//
//      K4.Ipc {
//          target: "k4.mymodule"
//          function open(): void { ... }
//      }

import Quickshell.Io

IpcHandler {}
