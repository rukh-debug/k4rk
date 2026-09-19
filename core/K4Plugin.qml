//  Compatibility wrapper: the contract lives in the public API so external
//  plugins can use it.
//
//  The actual type is `K4.Plugin` (api/K4/Plugin.qml). External plugins cannot
//  reach core/ by relative path, so the shared contract belongs in the K4
//  module. This preserves the old `K4Plugin {}` spelling for host-side
//  callers; plugins import K4 and use `K4.Plugin {}`. Native host features
//  use core/NativeFeature instead.

import K4 as K4

K4.Plugin {}
