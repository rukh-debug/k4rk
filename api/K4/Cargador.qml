//  Load something only while it is needed, and release it afterward.
//
//  For expensive objects that should not exist permanently: a fullscreen
//  window or a view containing video. Reexports LazyLoader.
//
//  Note its non-obvious default property, `component`: the object declared
//  inside IS the component to load, rather than a child of the loader.
//
//      K4.Cargador {
//          active: seleccionando
//          MiVentana {}
//      }

import Quickshell

LazyLoader {}
