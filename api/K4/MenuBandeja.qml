//  The menu offered by a tray icon.
//
//  Reexports QsMenuOpener. Tray menus use a desktop protocol: each application
//  publishes its own over D-Bus. This turns that menu into a model that can
//  render inside the island instead of asking the application to open its
//  own popup window.

import Quickshell

QsMenuOpener {}
