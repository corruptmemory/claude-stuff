// param_module — a module that declares BOTH #module_parameters groups.
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
//
// The two groups scope differently (see references/cheatsheet.md
// "Module Parameters: Two Groups + Program-Wide Type Injection"):
//   group 1 — SCALE — a PER-IMPORT value  (each distinct #import arg list = a separate copy)
//   group 2 — Elem  — a PROGRAM-WIDE Type  (set once, by the main program, before any import)
#module_parameters (SCALE := 2)(Elem: Type = int);

// Both parameters become ordinary compile-time constants inside the module.
#assert(is_constant(SCALE));
#assert(is_constant(Elem));

// This proc USES BOTH parameters at once: it scales an `Elem`-typed value (group 2, the
// injected TYPE) by SCALE (group 1, the per-import value). `cast(Elem)` makes the constant
// int SCALE fold to whatever Elem is (int -> 3, float -> 3.0), so the proc is type-correct
// for either injected element type.
scale_value :: (x: Elem) -> Elem {
    return x * cast(Elem) SCALE;
}

// Module/program parameters are NOT exported to the importer by name, so a consumer that
// wants to observe the group-1 value needs the module to hand it back through a proc.
get_scale :: () -> int {
    return SCALE;
}

#scope_module
#import "Basic";
