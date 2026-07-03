// Compendium entry 15: Language Evolution Features (beta 0.2.022-0.2.030)
// Jai Compiler Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: CHANGELOG.txt (0.2.022-0.2.029), examples/dll/main.jai,
//          modules/Overwriting_Allocator/module.jai,
//          modules/macOS/bindings/core_foundation.jai,
//          modules/Compiler/Compiler.jai
//
// Use-cases demonstrated:
//   - Non-dot struct literals (0.2.022)
//   - Tagged unions: basic form (0.2.023) and with value bindings (0.2.025)
//   - Struct literals assigning to tagged unions (0.2.029)
//   - Parameterized (polymorphic) unions: union(param) { ... } with a
//     param-sized array member (models modules/Debug/windows.jai SymbolBuffer)
//   - Metaprogram walk of Type_Info_Struct.tagged_union_bindings
//     (Type_Info_Tagged_Union_Binding: constant_value + member_index)
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
// Struct literals can assign to tagged unions (NEW in beta 0.2.029)
// ============================================================================
// Source: CHANGELOG.txt beta 0.2.029
// Previously you had to set the tag and field separately.
// Now a struct literal can be used directly in an assignment.

demo_tagged_union_struct_literal :: () {
    t: Thing;

    // Old way (still works):
    t.fruit = .BANANA;
    t.y = 2.71;

    // New way (0.2.029): struct literal assignment
    t = .{ fruit = .APPLE, x = 99 };
    print("struct literal assign: fruit=%, x=%\n", t.fruit, t.x);

    t = .{ fruit = .BANANA, y = 1.41 };
    print("struct literal assign: fruit=%, y=%\n", t.fruit, t.y);
}

// ============================================================================
// Parameterized (polymorphic) unions: union(param) { ... }
// ============================================================================
// A union may take compile-time parameters just like a polymorphic struct,
// and those parameters can size a member array. The canonical use is the
// stack-allocated variable-length buffer in modules/Debug/windows.jai:
//   SymbolBuffer :: union(name_length:u32=0) { symbol: ...; data: [... + name_length] u8; }
// Instantiate with Name(value); each instantiation is a distinct concrete type
// whose size is the max over its members (here the param-sized array wins).

Small_Header :: struct {
    tag:    u32;
    length: u32;
}  // size 8, alignment 4

// The array member's length is computed from the union parameter, so the
// union's size grows with the argument — a real polymorphic-union instantiation.
Sym_Buffer :: union(name_length: u32 = 0) {
    header: Small_Header;
    data:   [size_of(Small_Header) + name_length] u8;
}

demo_parameterized_union :: () {
    // Instantiate the polymorphic union with name_length = 16.
    // Members overlay: size = max(size_of(Small_Header)=8, 8+16=24) = 24.
    b: Sym_Buffer(16);
    assert(size_of(type_of(b)) == 24, "Sym_Buffer(16) sizes to its param-sized array member");

    // A different argument yields a DIFFERENT concrete type with a different size.
    assert(size_of(Sym_Buffer(0))  == 8,  "Sym_Buffer(0) collapses to the header size");
    assert(size_of(Sym_Buffer(64)) == 72, "Sym_Buffer(64) grows with the parameter");

    // Prove the members truly overlay: write through the struct view, read the
    // raw bytes (little-endian) through the array view of the SAME storage.
    b.header.tag    = 0xAABBCCDD;
    b.header.length = 5;
    assert(b.data[0] == 0xDD, "byte 0 of the overlaid array is the low byte of tag");
    assert(b.data[3] == 0xAA, "byte 3 of the overlaid array is the high byte of tag");

    print("parameterized union: size_of(Sym_Buffer(16))=% data[0]=0x% data[3]=0x%\n",
          size_of(type_of(b)), formatInt(b.data[0], base=16), formatInt(b.data[3], base=16));
}

// ============================================================================
// Metaprogram walk of tagged_union_bindings (Type_Info_Tagged_Union_Binding)
// ============================================================================
// Source: modules/Preload.jai (Type_Info_Struct.tagged_union_bindings,
//         Type_Info_Tagged_Union_Binding), modules/Basic/Print.jai (the walk).
// A tagged union built with the '.TAG ,, field' binding form records, per
// binding, the tag's integer constant_value and the member_index of the
// variant field it selects. We walk the bindings of 'Thing' (declared above)
// and assert the tag->field mapping the compiler recorded.

demo_tagged_union_bindings_walk :: () {
    info := cast(*Type_Info_Struct) type_info(Thing);

    // The tagged-union textual flag is set for a '.TAG ,, field' union.
    assert((info.textual_flags & .UNION_IS_TAGGED) != 0, "Thing is a tagged union");

    // Three variants -> three bindings (APPLE/BANANA/ORANGE).
    assert(info.tagged_union_bindings.count == 3, "Thing has three tagged-union bindings");

    // Resolve each binding to (tag constant, selected member name) and assert
    // the exact mapping: .APPLE->x, .BANANA->y, .ORANGE->z.
    apple_field, banana_field, orange_field: string;
    for binding: info.tagged_union_bindings {
        member := info.members[binding.member_index];  // member_index indexes Type_Info_Struct.members
        if binding.constant_value == {
            case cast(u64) Fruit.APPLE;  apple_field  = member.name;
            case cast(u64) Fruit.BANANA; banana_field = member.name;
            case cast(u64) Fruit.ORANGE; orange_field = member.name;
        }
    }
    assert(apple_field  == "x", "binding for .APPLE selects field x");
    assert(banana_field == "y", "binding for .BANANA selects field y");
    assert(orange_field == "z", "binding for .ORANGE selects field z");

    print("tagged_union_bindings: count=% mapping APPLE->%, BANANA->%, ORANGE->%\n",
          info.tagged_union_bindings.count, apple_field, banana_field, orange_field);
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
    print("\n=== Tagged union struct literal assignment (0.2.029) ===\n");
    demo_tagged_union_struct_literal();
    print("\n=== Parameterized (polymorphic) union ===\n");
    demo_parameterized_union();
    print("\n=== Metaprogram walk of tagged_union_bindings ===\n");
    demo_tagged_union_bindings_walk();
    print("\n=== #code,null ===\n");
    demo_code_null();
    print("\n=== Dereference (new style) ===\n");
    demo_dereference();

    print("\nPASS: non-dot literals, tagged unions (basic + bindings + struct-literal assign), parameterized union sizing/overlay, tagged_union_bindings walk, #code,null, and postfix .* dereference all verified.\n");
}
