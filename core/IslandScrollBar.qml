//  The in-house scrollbar, for host views.
//
//  Only a wrapper around K4.Desplazador: the single implementation lives in
//  the API because external plugins need it too. Otherwise their lists used
//  Qt's default scrollbar and looked inconsistent. This supplies only the
//  core component name.

import K4 as K4

K4.Desplazador {}
