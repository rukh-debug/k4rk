//  A text file that can be read and written.
//
//  Reexports Quickshell's FileView. Its API already has the needed shape:
//  `path`, `text()`, `setText()`, `blockLoading`, `onLoaded`. Forwarding those
//  members manually would only introduce more opportunities for mistakes.
//
//  `blockLoading` deserves a note: it reads synchronously on creation. Use it
//  for small data needed immediately, such as settings or state, not for
//  anything potentially slow: it blocks the rendering thread.

import Quickshell.Io

FileView {}
