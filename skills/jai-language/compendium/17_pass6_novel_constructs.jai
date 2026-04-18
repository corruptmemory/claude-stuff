// Compendium entry 17: Pass 6 Novel Constructs
// Jai Compiler Version: beta 0.2.028 (9 April 2026)
// Platform: Linux x86-64
// Sources: CHANGELOG.txt (0.2.005 "Caststravaganza", 0.2.006 vote result),
//          modules/Android/examples/camera.jai (function-call cast),
//          modules/Android/Toolchain/manifest.jai (dotted field names in struct literals),
//          modules/Runtime_Support.jai (standalone #bytes directive),
//          modules/Input/windows.jai (bare remove;),
//          examples/codex_view/src/draw_live_allocations.jai (bare remove;),
//          examples/beta_key_mailer/email_keys.jai (\d escape sequences),
//          how_to/005_strings.jai (\d escape documentation)
//
// Use-cases demonstrated:
//   - Function-call style cast: cast(Type, expr) — the community-chosen preferred form
//   - Bare `remove;` statement (implicit current iterator element)
//   - Dotted field names in struct literal initializers
//   - \d decimal escape sequences in strings
//   - #bytes as standalone statement for raw machine code emission
//   - #intrinsic with LLVM linkname string

#import "Basic";
#import "String";

// ============================================================================
// Function-call style cast: cast(Type, expr)
// ============================================================================
// Introduced in beta 0.2.005 ("Caststravaganza") as Option 2
// Chosen by community vote (75%) in beta 0.2.006
// Both prefix cast(T) expr and function-call cast(T, expr) coexist
// Source: CHANGELOG.txt beta 0.2.005, 0.2.006

Point :: struct { x: float; y: float; }

demo_function_call_cast :: () {
    // Standard prefix cast (still works)
    a : s64 = 42;
    b := cast(float) a;
    print("Prefix cast: %\n", b);

    // Function-call style cast (newer, preferred direction)
    c := cast(float, a);     // expression inside parens after comma
    print("Function-call cast: %\n", c);

    // Advantage: explicit precedence with complex expressions
    ptr := *a;
    // Prefix: cast(*u8) ptr + 1   — ambiguous: cast ptr, then add 1? or cast (ptr+1)?
    // Function-call: clear precedence
    // d := cast(*u8, ptr);  // clearly casts just ptr

    // Common pattern in Android modules:
    width : s32 = 1920;
    aspect := cast(float, width) / 1080.0;
    print("Aspect ratio: %\n", aspect);

    // Cast with boolean in for-loop conditional modifier:
    flags : u32 = 0x1;
    arr := int.[10, 20, 30];
    // for <=cast(bool, flags & 0x1) arr { print("%\n", it); }
    // The above would iterate in reverse if flags & 0x1 is true
}

// ============================================================================
// Bare `remove;` statement (no expression argument)
// ============================================================================
// Standard: `remove it;` or `remove element;` (explicit target)
// Bare form: `remove;` — removes current iterator element (implicit `it`)
// Source: modules/Input/windows.jai:85,
//         examples/codex_view/src/draw_live_allocations.jai:152-154

demo_bare_remove :: () {
    items : [..] int;
    array_add(*items, 1);
    array_add(*items, 2);
    array_add(*items, 3);
    array_add(*items, 4);
    array_add(*items, 5);

    // Standard form with explicit target
    for items  if it > 3  remove it;
    print("After remove it (>3): %\n", items);

    // Re-populate
    array_reset(*items);
    array_add(*items, 1);
    array_add(*items, 2);
    array_add(*items, 3);

    // Bare form — equivalent to `remove it;`
    // Removes current element without explicit naming
    for items  if it == 2  remove;
    print("After bare remove (==2): %\n", items);
}

// ============================================================================
// \d decimal escape sequences in strings
// ============================================================================
// \dNNN — decimal byte value (1-3 digits, max 255)
// Source: how_to/005_strings.jai:297,
//         examples/beta_key_mailer/email_keys.jai:44,
//         examples/codex_view/src/main.jai:309

demo_decimal_escape :: () {
    // \d010 = LF (line feed, decimal 10)
    // \d013 = CR (carriage return, decimal 13)
    // \d032 = space (decimal 32)
    TRIM :: "\d010\d013\n \t";  // same chars: LF, CR, newline, space, tab
    s := "  hello  \d010\d013";
    trimmed := trim(s, TRIM);
    print("Trimmed: '%'\n", trimmed);

    // Comparison: \d vs \x
    // \d010 = \x0a (both represent byte value 10, LF)
    // \d013 = \x0d (both represent byte value 13, CR)
    // \d032 = \x20 (both represent byte value 32, space)
    // \d is the decimal form, \x is the hex form
}

// ============================================================================
// Dotted field names in struct literal initializers
// ============================================================================
// Inside .{...}, field initializers can use dotted access for subfields
// Source: modules/Android/Toolchain/manifest.jai (~40 uses)
//         how_to/007_struct_literals.jai:136 (indexed: values[1] = 7)

Inner :: struct { index: u32; value: u32; }
Outer :: struct { ns: Inner; name: Inner; data: u32; }

demo_dotted_struct_literal :: () {
    // Standard struct literal
    o1 := Outer.{ns = Inner.{index = 1, value = 2}, name = Inner.{index = 3, value = 4}, data = 5};

    // Dotted field initializer — set subfields directly
    o2 := Outer.{ns.index = 1, ns.value = 2, name.index = 3, name.value = 4, data = 5};
    // Both produce identical results

    print("o1: ns.index=%, name.index=%, data=%\n", o1.ns.index, o1.name.index, o1.data);
    print("o2: ns.index=%, name.index=%, data=%\n", o2.ns.index, o2.name.index, o2.data);
}

// ============================================================================
// #intrinsic with LLVM linkname string
// ============================================================================
// #intrinsic can optionally take a string argument for the LLVM intrinsic name
// Source: modules/Runtime_Support.jai:474
// Without string: compiler provides built-in implementation (memcpy, memcmp, etc.)
// With string: maps to specific LLVM intrinsic function

// Example (cannot run outside compiler context):
// llvm_trap :: () #intrinsic "llvm.debugtrap";
// memcpy :: (dest: *void, source: *void, count: s64) #intrinsic;  // no linkname

// ============================================================================
// #bytes as standalone statement (NOT limited to #asm blocks)
// ============================================================================
// Emits raw machine code bytes directly into the instruction stream
// Takes an array literal of byte values (hex, decimal, or binary)
// Source: modules/Runtime_Support.jai:465,469,507,662,
//         modules/rpmalloc/rpmalloc.jai:688
// Typically guarded by `#if CPU == .ARM64` static conditionals

// Example (this is ARM64-specific, won't compile on x86):
// #if CPU == .ARM64 {
//     #bytes .[0x3F, 0x20, 0x03, 0xD5]; // YIELD instruction
//     #bytes .[0x20, 0x00, 0b001_0_0000, 0b1101_0100]; // BRK 0x01
// }
// Note: Array can mix hex (0xFF), decimal, and binary (0b...) literals

// ============================================================================
// Main
// ============================================================================

main :: () {
    print("=== Function-call Cast ===\n");
    demo_function_call_cast();
    print("\n=== Bare Remove ===\n");
    demo_bare_remove();
    print("\n=== Decimal Escape ===\n");
    demo_decimal_escape();
    print("\n=== Dotted Struct Literal ===\n");
    demo_dotted_struct_literal();
}
