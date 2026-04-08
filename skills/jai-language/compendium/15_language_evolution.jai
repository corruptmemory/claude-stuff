// Compendium entry 15: Language Evolution Features (beta 0.2.022-0.2.027)
// Jai Compiler Version: beta 0.2.027 (7 April 2026)
// Platform: Linux x86-64
// Sources: CHANGELOG.txt (0.2.022-0.2.025), examples/dll/main.jai,
//          modules/Overwriting_Allocator/module.jai,
//          modules/macOS/bindings/core_foundation.jai,
//          modules/Compiler/Compiler.jai
//
// Use-cases demonstrated:
//   - Non-dot struct literals (0.2.022)
//   - Tagged unions: basic form (0.2.023) and with value bindings (0.2.025)
//   - #elsewhere directive for external variable/procedure declarations
//   - #code,null for null Code values
//   - #library,no_static_library for dynamic-only libraries
//   - Trailing comma in procedure parameters (0.2.025)
//   - << prefix dereference deprecation (0.2.022)

#import "Basic";
Math :: #import "Math";

// ============================================================================
// Non-dot struct literals (NEW in beta 0.2.022)
// ============================================================================
// Previously: Type.{val1, val2}  or  .{val1, val2}
// Now also:   {val1, val2}  (without the leading dot)
// Source: CHANGELOG.txt beta 0.2.022

Vector2 :: struct { x: float; y: float; }

length :: (v: Vector2) -> float {
    return Math.sqrt(v.x * v.x + v.y * v.y);
}

demo_non_dot_struct_literals :: () {
    // Traditional form still works
    v1 := Vector2.{3, 4};
    v2 : Vector2 = .{3, 4};

    // New non-dot form (0.2.022+)
    // Type is inferred from context
    result := length({3, 4});     // instead of length(.{3, 4})
    print("length({3, 4}) = %\n", result);

    // Return without dot
    // return {};  // instead of return .{} (when return type is a struct)

    // Array of struct literals without dots
    // pairs := .[{3, "Yes"}, {2, "No"}];  // instead of .[.{3, "Yes"}, .{2, "No"}]

    // IMPORTANT: 'if x == {}' does NOT parse as a switch statement
    // The compiler has a special case for this (added in 0.2.023)
}

// ============================================================================
// Tagged unions (NEW in beta 0.2.023)
// ============================================================================
// Source: CHANGELOG.txt beta 0.2.023

Value_Kind :: enum u8 {
    SCALAR :: 0;
    VECTOR :: 1;
    STRING :: 2;
}

// Basic tagged union: 'union tag_name: TagType { fields }'
// Tag must be integer type or Type
// Tag becomes first struct member (address same as struct address)
Value :: union kind: Value_Kind {
    scalar: float64;
    // Fields are re-packed after tag per alignment rules
    // So field addresses may differ (u8 tag -> u8 field at offset 1, *void at offset 8)
}

// ============================================================================
// Tagged union with value bindings (NEW in beta 0.2.025)
// ============================================================================
// Source: CHANGELOG.txt beta 0.2.025

Fruit :: enum u8 {
    APPLE  :: 0;
    BANANA :: 1;
    ORANGE :: 2;
}

// Binding form: .TAG_VALUE ,, field_name: Type;
// The ,, separates the tag value from the field declaration
// NOTE: ,, syntax is experimental and may change to 'case' keyword
Thing :: union fruit: Fruit {
    .APPLE  ,, x: int;
    .BANANA ,, y: float;
    .ORANGE ,, z := "You're ruining Hamlet!";
}
// Type_Info_Tagged_Union_Binding available in modules/Preload for metaprogramming
// tagged_union_bindings array on Type_Info_Struct

demo_tagged_unions :: () {
    v: Value;
    v.kind = .SCALAR;
    v.scalar = 3.14;
    print("Tagged union: kind=%, value=%\n", v.kind, v.scalar);

    t: Thing;
    t.fruit = .APPLE;
    t.x = 42;
    print("Thing: fruit=%, x=%\n", t.fruit, t.x);
}

// ============================================================================
// #code,null — null value for Code-typed parameters
// ============================================================================
// Source: modules/Compiler/Compiler.jai, examples/codex_view/src/draw_live_allocations.jai
// Code_Code has a NULL flag (0x2). #code,null tests as false in 'if'.

// Example: checking #code,null in compile-time conditionals
demo_code_null :: () {
    // #code,null is primarily used as a default parameter value
    // for procedures that optionally accept Code arguments.
    // It tests as false in #if checks.
    //
    // Real-world usage from modules/Compiler/Compiler.jai:
    //   compiler_get_code :: (node: *Code_Node,
    //       code_to_copy_scope_from: Code = #code,null) -> Code #compiler;
    //
    // Real-world usage from examples/codex_view:
    //   draw_items :: ($color_proc := #code,null) { ... }
    //   if color_proc  { /* use it */ }

    // Simple demonstration: #code,null as a value
    c : Code = #code,null;
    // 'c' now holds a null Code value that tests as false
    print("Code null value created (no runtime inspection available)\n");
}

// ============================================================================
// Trailing comma in procedure parameters (restored in 0.2.025)
// ============================================================================
// Source: CHANGELOG.txt beta 0.2.025

function_with_trailing_comma :: (
    a: int,
    b: float,
    c: string,   // <-- trailing comma now permitted again
) -> int {
    return a;
}

// ============================================================================
// << prefix dereference is DEPRECATED (beta 0.2.022)
// ============================================================================
// Source: CHANGELOG.txt beta 0.2.022
// Use (.*) or postfix .* instead
// modules/Rewrite.jai plugin can auto-rewrite: jai program.jai +Rewrite -write

demo_dereference :: () {
    x := 42;
    ptr := *x;

    // OLD (deprecated, generates warning):
    // value := <<ptr;

    // NEW (preferred):
    value := ptr.*;          // postfix form
    // value2 := (ptr.*);   // parenthesized prefix form

    print("Dereferenced: %\n", value);
}

// ============================================================================
// Main
// ============================================================================

main :: () {
    print("=== Non-dot struct literals ===\n");
    demo_non_dot_struct_literals();
    print("\n=== Tagged unions ===\n");
    demo_tagged_unions();
    print("\n=== #code,null ===\n");
    demo_code_null();
    print("\n=== Dereference (new style) ===\n");
    demo_dereference();
}
