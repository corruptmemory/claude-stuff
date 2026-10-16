// lib_module — a LIBRARY that imports param_module BARE, the way http_router imports http_server.
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
//
// Proves (with driver.jai, 2026-10-03): a library's bare import does NOT see the group-1
// arguments the main program passed. It is its own instantiation, with group-1 DEFAULTS
// (SCALE = 2 here, though driver.jai imports SCALE=3). Group 2 IS inherited (Elem = float).
#import "param_module";

lib_scale :: () -> int { return get_scale(); }

// Compiles only because this instance's Elem is float: group 2 reached the library.
lib_scale_value :: (x: float) -> float { return scale_value(x); }
