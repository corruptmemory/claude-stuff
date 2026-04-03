// Compendium entry 19: Pass 9 Novel Constructs
// Jai Compiler Version: beta 0.2.026 (21 February 2026)
// Platform: Linux x86-64
// Sources:
//   modules/Windows.jai (bare anonymous struct/union members)
//   modules/Bucket_Array.jai (for *=EXPR modifier)
//   modules/Runtime_Support.jai (#entry_point modifier)
//   how_to/730_for_expansions.jai (for <=EXPR *=EXPR combined)
//   examples/codex_view/src/draw_live_allocations.jai (_, var = discard-assign)
//   modules/Basic/Apollo_Time.jai (backslash whitespace continuation)
//
// Use-cases demonstrated:
//   1. Bare anonymous struct member in union (no field name, for C binding compat)
//   2. for *=EXPR loop modifier (pointer iteration)
//   3. #entry_point procedure modifier (internal, runtime support)
//   4. _, var = multi-assign with discard
//   5. Backslash identifier with whitespace continuation
//
// Compiled: partially (items 1,4 can compile; items 2,3,5 are syntax-only or runtime-internal)

#import "Basic";

// ============================================================================
// 1. Bare Anonymous Struct/Union Members (no field name)
// ============================================================================
// Source: modules/Windows.jai lines 63-78
// When a struct or union contains `struct { ... }` or `union { ... }` WITHOUT
// a field name, the inner fields are "inlined" into the parent type.
// This is the same as C anonymous struct/union members.
//
// Syntax: just `struct { fields }` or `union { fields }` as a struct member
// Note: NO trailing semicolon after the closing brace
// Note: NO field name before `struct`/`union`
//
// This is distinct from NAMED anonymous types: `field: struct { ... };`
// which DO have a field name and a trailing semicolon.
//
// Usage: ~196 occurrences across 65+ files, primarily in C binding modules
//
// Full example from Windows.jai:
//   LARGE_INTEGER :: union {
//       struct {
//           LowPart : u32;
//           HighPart : s32;
//       }
//       QuadPart : s64;
//   }
//
// The bare `struct { LowPart: u32; HighPart: s32; }` has no name --
// LowPart and HighPart are accessed directly on LARGE_INTEGER instances.

// Compilable demonstration:
Point3D :: struct {
    union {
        struct {
            x: float;
            y: float;
            z: float;
        }
        components: [3] float;
    }
}

// ============================================================================
// 2. for *=EXPR Loop Modifier (Pointer Iteration)
// ============================================================================
// Source: modules/Bucket_Array.jai line 135, how_to/730_for_expansions.jai
// The `*=EXPR` form in a for loop controls whether iteration yields
// pointers to elements (*it) instead of copies.
// EXPR is a compile-time boolean expression.
//
// Syntax: for *=EXPR iterable { body }
//         for <=REVERSE *=DO_POINTER iterable { body }
//
// Can combine with <=EXPR (reverse iteration):
//   for <=REVERSE *=DO_POINTER `it, i: bucket.data { ... }
//
// The *=EXPR form is ONLY used in for-expansion contexts where
// the pointer behavior needs to be parameterized at compile time.
// Only 2 uses found in the entire distribution.
//
// NOT compilable in isolation -- requires for_expansion context

// ============================================================================
// 3. #entry_point Procedure Modifier
// ============================================================================
// Source: modules/Runtime_Support.jai line 441
// Used to mark a procedure as the program entry point.
// This is an INTERNAL modifier used by the runtime support system.
//
// Syntax: proc :: () #entry_point;
//
// Only 1 use in entire distribution:
//   __program_main :: () #entry_point;
//
// NOT compilable -- internal to runtime

// ============================================================================
// 4. _, var = Multi-Assign with Discard
// ============================================================================
// Source: examples/codex_view/src/draw_live_allocations.jai line 795
// The underscore `_` can appear on the left side of a multi-assignment
// to discard a return value at that position.
//
// Syntax: _, var = func_returning_two_values();
//         var, _ = func_returning_two_values();
//
// This is distinct from `_ := expr;` (discard single value).
// Here `_` appears in a COMMA-SEPARATED assignment target list.

get_pair :: () -> int, int { return 10, 20; }

// ============================================================================
// 5. Backslash Identifier with Whitespace Continuation
// ============================================================================
// Source: modules/Basic/Apollo_Time.jai line 260
// The backslash in identifiers can be followed by WHITESPACE (spaces/tabs)
// before the identifier continues. The compiler strips the backslash AND
// the whitespace.
//
// Form 1 (no whitespace): name\_continuation
// Form 2 (with whitespace): name\      _continuation
//
// Form 2 is used for ALIGNMENT purposes in column-formatted code:
//   month\      _starting_at_0 : u8;
//   day\        _starting_at_1 : u8;
//
// The backslash + whitespace is stripped, so these become:
//   month_starting_at_0 : u8;
//   day_starting_at_1 : u8;
//
// 136 uses across 33 files. Form 2 (with whitespace) found in:
//   modules/Basic/Apollo_Time.jai
//   modules/GetRect/system/active_widgets.jai
//
// NOT compilable in standalone test -- requires identifier token support

main :: () {
    // 1. Bare anonymous struct demo
    p: Point3D;
    p.x = 1.0;
    p.y = 2.0;
    p.z = 3.0;
    print("Point3D: x=%, y=%, z=%\n", p.x, p.y, p.z);
    print("components: %, %, %\n", p.components[0], p.components[1], p.components[2]);

    // 4. Discard-assign demo
    _, val := get_pair();
    print("Discarded first, got second: %\n", val);
}
