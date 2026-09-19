//  The in-house glyph component, now a thin wrapper around K4.Glifo.
//
//  The implementation lives in the API so external plugins can use it. This
//  wrapper retains the English name used by host views. One implementation
//  keeps separate copies of the same control from drifting apart.

import K4 as K4

K4.Glifo {}
