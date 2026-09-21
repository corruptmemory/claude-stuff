// Proves (cheatsheet): ### Module Parameters: Two Groups + Program-Wide Type Injection
// Compendium: Module parameters — two groups (per-import value + program-wide Type injection)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/380_module_parameters/ (first.jai + local_modules/Rendering.jai)
// Compile (param_module must resolve as a local module):
//   ~/jai/jai/bin/jai-linux driver.jai -import_dir <this directory>
//
// Use-case: a single #module_parameters directive can declare TWO argument lists with
// different scoping. This driver imports the neighboring `param_module` supplying BOTH:
//   group 1  SCALE=3    — a PER-IMPORT value  (overrides the module default 2)
//   group 2  Elem=float — a PROGRAM-WIDE TYPE (overrides the module default int)
// The empty-looking machinery matters: the FIRST () reaches group 2, so a two-group import
// is `"name"(group1...)(group2...)`. This file COMPILES (proves the two-group form + the
// Type injection type-checks) and RUNS (asserts the behavior reflects both groups).

#import "Basic";

// Supply BOTH parameter groups. As the MAIN program, driver.jai is allowed to set the
// group-2 program parameter (Elem); a library #import may NOT — it would inherit the default.
#import "param_module"(SCALE=3)(Elem=float);

// ── THE SAME MODULE, TWICE IN ONE SCOPE ────────────────────────────────────────────
// `Name :: #import "M"(args)` is an ordinary constant declaration whose value is a
// module INSTANCE, so nothing stops you binding two of them. Each distinct group-1
// argument list is a separate copy of the module. Group 2 cannot vary this way — it is
// program-wide, set once (above), and these inherit it without asking.
Two   :: #import "param_module"(SCALE=2);
Three :: #import "param_module"(SCALE=3);

main :: () {
    // --- Group 1 proof (per-import VALUE) -----------------------------------------------
    // get_scale() returns SCALE. We passed SCALE=3; the module default is 2. Seeing 3 proves
    // our per-import argument (not the default) reached this instance of the module.
    assert(get_scale() == 3);

    // --- Group 2 proof (program-wide TYPE injection) ------------------------------------
    // Elem was injected as `float`, so scale_value's parameter/return type IS float here.
    r := scale_value(1.5);          // 1.5 * 3 = 4.5

    // The return TYPE literally reflects the injected group-2 Type parameter.
    assert(type_of(r) == float);

    // The VALUE reflects BOTH groups at once: SCALE=3 (group 1) AND float math preserving the
    // 0.5 fraction (group 2). Had Elem defaulted to int, 1.5 could not even be passed and 4.5
    // could not be represented; had SCALE defaulted to 2, this would be 3.0, not 4.5.
    assert(r == 4.5);

    // --- Two more instances of the SAME module, alongside the anonymous one ------------
    // Group 1 varies per import: three instances coexist in this scope, each with its own
    // SCALE. This is the ML-functor shape — a parameterized module is instantiable, and an
    // instantiation is a value you can bind.
    assert(Two.get_scale()   == 2);
    assert(Three.get_scale() == 3);

    // Group 2 does NOT vary: Elem was injected program-wide as `float` by the anonymous
    // import above, and these named imports inherit it without mentioning it at all.
    assert(type_of(Two.scale_value(1.5)) == float);
    assert(Two.scale_value(1.5) == 3.0);          // 1.5 * SCALE(2), vs 4.5 for SCALE(3)

    // --- AND THEIR TYPES DO NOT UNIFY -------------------------------------------------
    // A separate copy of the module means separate TYPES. This is the runnable half:
    assert(Two.Box != Three.Box, "two instantiations produce two distinct Box types");

    // The half that cannot compile, so it is quoted instead — and the error is the reason
    // this entry exists, because it names NEITHER cause and looks like a compiler bug:
    //     a: Two.Box;  b: Three.Box;  b = a;
    //  -> Error: Type mismatch: incompatible structs
    //       (wanted "Box" [param_module/module.jai:33], given "Box" [param_module/module.jai:33]).
    //     ... in binary operator = (left type: Box; right type: Box).
    // Same NAME, same SOURCE LOCATION, incompatible. Nothing on screen distinguishes the
    // two types, because what distinguishes them is which INSTANTIATION they came from.
    // (Jai's other route to this same surprise: a module imported by two different literal
    // path strings is two instances, so `../modules/X` and `../../modules/X` also produce
    // non-unifying types. Import a shared module by ONE spelling everywhere.)

    print("PASS: group-1 SCALE=% (per-import value), group-2 Elem=% (program-wide type) -> scale_value(1.5)=%\n",
          get_scale(), type_of(r), r);
    print("  and two more instances in the same scope: Two=% Three=%, Two.Box != Three.Box = %\n",
          Two.get_scale(), Three.get_scale(), Two.Box != Three.Box);
}
