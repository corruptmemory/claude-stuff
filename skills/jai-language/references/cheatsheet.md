# Jai Language Cheat Sheet

> **Jai Version**: beta 0.2.029
> **Platform**: Linux x86-64
> **All entries verified against**: `~/jai/jai/` distribution (how_to/, modules/, examples/)
> **Last updated**: 2026-04-30

## Ecosystem Context

Jai is a general-purpose systems-level language being developed primarily in the context of building a first-class multi-platform game engine. As a result, the standard library is oriented toward game development needs (graphics, audio, math, threading, file I/O) and intentionally omits many "batteries included" features common in languages like Go, Python, or Rust. Notable gaps include: HTTP servers/clients (there is a `Curl` module wrapping libcurl), JSON serialization/deserialization, broad cryptography support, template engines, and package management. There is no package manager by design — external code is vendored directly into the project's `modules/` directory. When building non-game applications (web servers, data pipelines, CLI tools), expect to implement or vendor these capabilities yourself.

## Declarations
<!-- verified: beta 0.2.028 -->

```jai
x := 5;                        // variable, type inferred
x : int = 5;                   // variable, explicit type
PI :: 3.14159;                 // constant
MAX : int : 100;               // typed constant
x : int;                       // default-initialized
x : int = ---;                 // uninitialized (explicit)
x, y, z : float;              // compound declaration
x, y, z := get_triple();      // compound with inference
_ := get_value();             // discard with _
#no_reset x := 0;             // preserve compile-time value at runtime

// Multi-return destructuring at call site
// Source: examples/find_symbol.jai, modules/Android/Toolchain/adb.jai
a, b := get_two_values();                           // all declared (positional)
success=, output, error := adb(..params);            // success= assigns to existing, rest declared
renderer:, ok = make_renderer(inst, surface);        // renderer: declares new, ok assigns to existing
_:, remainder = split_from_left(r, " ");            // _: declares+discards, remainder assigns

// Mixed declaration/assignment modifiers (`:` and `=`) in comma-separated capture:
// Source: CHANGELOG.txt (beta 0.1.x), modules/Subtitles.jai, modules/Basic/tests.jai,
//         modules/Android/Toolchain/*.jai, examples/VR/modules/Vulkan_Render/module.jai
// Each comma-separated variable can have `:` or `=` modifier to OVERRIDE the default:
//   In `:=` context (default = declare): `name=,` overrides to ASSIGN to existing var
//   In `=` context (default = assign): `name:,` overrides to DECLARE new var
// Capture is ALWAYS POSITIONAL. The `:` and `=` modifiers do NOT target named returns.
// The variable name is chosen freely by the caller, not matched to return parameter names.
//
// Examples in `:=` context (all names are declared UNLESS marked with `=`):
a, b=, c := 1, 2, 3;                               // a,c declared; b= assigns to existing b
success=, tbds := parse_tbd(content);                // success= assigns existing; tbds declared
success, tbdv3, complete=, lexer= := parse_yaml(l, T); // complete=, lexer= assign to existing
//
// CONSTRAINT: `:=` declares the left-hand side — you cannot "declare" a struct field member.
// Same semantics as Go's := vs =. Struct fields are assignment targets, not declarations.
//   obj.field, count := get_data();      // ERROR: obj.field is not a declarable name
//   count: u32;                          // FIX: pre-declare, then use plain =
//   obj.field, count = get_data();       // OK: both sides are assignment targets
//
// Examples in `=` context (all names assign to existing UNLESS marked with `:`):
success:, module_index = table_find(*indices, key);  // success: declares new; module_index assigns
found, file_line:, remainder = split_from_left(s);   // file_line: declares new; found,remainder assign
a, d:, c = 4, 5, 6;                                 // d: declares new; a,c assign to existing
// ~17 files use name=, pattern, ~20 files use name:, pattern
```

## Procedures
<!-- verified: beta 0.2.028 -->

```jai
// Basic
name :: (a: int, b: int) -> int { return a + b; }
name :: () { }                                     // void return

// Default values
name :: (a: int, b: int = 0) -> int { }
name :: (a := 0, b := 0) { }                      // inferred-type defaults

// Variadic
name :: (args: .. Any) { }

// Using parameter (fields promoted to scope)
name :: (using ctx: *Context) { }
name :: (using #as ctx: *Context) { }           // using with auto-cast
name :: (using,except(x,y,z) q: Quaternion) { } // using with filter
name :: (#discard result: int) { }              // discard (caller ignores)

// Multiple returns
name :: () -> int, bool { return 42, true; }

// Named returns
name :: () -> result: int, ok: bool { result = 42; ok = true; }
name :: () -> result: *Entity = null, status := SUCCESS { }  // mixed with :=
name :: () -> string, success: bool { }           // mixed named/unnamed
name :: () -> (result: int, ok: bool) { }         // parenthesized

// NOTE: #must does NOT exist in beta 0.2.028

// Polymorphism
name :: (x: $T) -> T { }                          // polymorphic ($T)
name :: (x: $T/Entity) { }                        // type restriction (requires #as using)
name :: (x: $T/interface Matchable) { }            // interface restriction
name :: (x: $T/.[s64, s32, s16, s8]) -> T { }    // type restriction with type list (array literal)
// Source: modules/Math/module.jai, modules/String/module.jai
name :: ($$x: int) { }                            // auto-bake parameter

// Modifiers (after params or after body)
name :: inline (x: int) -> int { }                // forced inline
name :: (x: int) #expand { }                      // macro (caller scope)
name :: () #c_call { }                            // C calling convention
name :: (a: T, b: T) #symmetric { }              // reversed args accepted
name :: () #no_context { }                        // no implicit context
name :: () #no_debug { }                          // no debug info
name :: () #no_abc { }                            // no array bounds check
name :: () #deprecated { }                        // deprecated warning
name :: () #deprecated "use new()" #foreign lib;  // deprecated with message
name :: () #compiler { }                          // compiler plugin
name :: () #compile_time { }                      // compile-time only
name :: () #no_aoc { }                            // no automatic output capture
name :: () #cpp_method #foreign lib;              // C++ calling convention
name :: () #cpp_return_type_is_non_pod #foreign l; // C++ non-POD return
name :: () #no_alias { }                          // no pointer aliasing
name :: () #intrinsic;                            // compiler intrinsic (no linkname)
name :: () #intrinsic "llvm.debugtrap";           // compiler intrinsic with LLVM linkname
// Source: modules/Runtime_Support.jai:474, modules/Preload.jai:369-373
name :: () #dump { }                              // dump generated code (debugging)

// #modify block (returns true to accept, false+"msg" to reject)
sum :: (a: [] $T) -> T #modify { if T == float64  T = float; return true; } { }

// Foreign
GetLastError :: () -> u32 #foreign kernel32;
other_fn :: () #foreign;                              // foreign without library
c_malloc :: (size: u64) -> *void #foreign crt "malloc"; // with custom link name (string)
walloc_malloc :: (size: s64) -> *void #foreign "malloc"; // foreign with string name only (WASM)
// Source: modules/Default_Allocator/module.jai, examples/wasm/modules/Walloc.jai

// Internal-only modifiers (used by compiler/runtime, not user code)
// #entry_point — marks program entry point (1 use: modules/Runtime_Support.jai:441)
//   __program_main :: () #entry_point;  // declares the program's main entry point
// #no_call — no-call convention (modules/Program_Print/module.jai, codegen only)
// TREE-SITTER NOTE: #entry_point is NOT in the grammar (only 1 use, internal)

// Lambda expressions
f := x => x * x;                                  // single param
f := (a, b) => a + b;                             // multi param
f := x => { if x > 0 return x; return 0; };      // block body
f := (x: int) -> int { return x * x; };           // full procedure literal

// Inline/no_inline call modifier
result := inline add(1, 2);
result := no_inline expensive();
```

## Operator Overloading
<!-- verified: beta 0.2.028 -->

```jai
operator + :: (a: Vec2, b: Vec2) -> Vec2 { }
operator == :: (a: Vec2, b: Vec2) -> bool { }
operator [] :: (arr: *MyArray, index: int) -> *T { }
operator []= :: (arr: *MyArray, index: int, value: T) { }
operator *[] :: (arr: *MyArray, index: int) -> *T { }  // pointer-index
operator ! :: (a: S128) -> bool { }     // logical NOT overload
// Also: -, *, /, %, !=, <, <=, >, >=, &&, ||, !, +=, -=, *=, /=, &&=, ||=, etc.

// Operator as value reference (re-exporting from named import)
// Needed because named imports don't propagate operators into scope.
// See "Named vs Anonymous Import Semantics" under Directives > Imports.
// Source: modules/Thread/module.jai
Basic :: #import "Basic";
operator- :: Basic.operator-;          // import operator from another module
```

## Types
<!-- verified: beta 0.2.028 -->

### Primitives
- `int` (s64), `u8` `u16` `u32` `u64`, `s8` `s16` `s32` `s64`
- `float` (float32), `float32`, `float64`
- `bool`, `string`, `void`
- **`void` is the zero `Type`** (since 0.2.029): A `Type` variable declared without initialization holds `void` (not undefined). `void` evaluates as `false` in if-statements; all other types evaluate as `true`. `void` is always index 0 in both compile-time and runtime type tables; `Type` is always index 1. Previously a zero-initialized `Type` was undefined behavior at compile time.
- `#Context` — the type of the implicit context parameter
  - Used as a type: `ctx: #Context;`, `cast(*#Context) ptr`
  - Used as a namespace: `#Context.default_allocator` (static member access)
  - `type_info(#Context)` — get runtime type info for the context struct
  - `push_context { }` — pushes a default `#Context` (no expression needed)
  - Source: modules/Remap_Context.jai, modules/Debug/windows.jai, modules/Thread/primitives.jai
  - Source: modules/Android/Toolchain/adb.jai (#Context.default_allocator)
  - ~30+ files use #Context as a type across the distribution

### Compound Types
```jai
*Type                          // pointer (dereference: ptr.*)
[N] Type                       // fixed array
[..] Type                      // dynamic array
[] Type                        // slice/array view
#type (params) -> ReturnType   // explicit procedure type (see Type System for full details)
(params) -> ReturnType         // bare procedure type (in type positions)
(params)                       // bare void procedure type
#type,distinct Type            // distinct type variant
#type,isa Type                 // subtype variant
Table(string, int)             // parameterized type
$T                             // polymorphic type
$T/Constraint                  // restricted polymorphic
$T/interface I                 // interface-restricted polymorphic
```

### Type Introspection
```jai
type_of(expr)                  // get type of expression
size_of(Type)                  // byte size
type_info(Type)                // runtime type info struct
is_constant(expr)              // compile-time check
initializer_of(Type)           // default initializer procedure
```

### Number Literals
<!-- verified: beta 0.2.028 -->
```jai
42                             // decimal integer
0xff                           // hexadecimal (0x prefix)
0b1010                         // binary (0b prefix)
0h3f80_0000                    // hex float bit pattern (0h prefix, reinterprets as float)
1_000_000                      // underscores for readability (any position)
0xff_ff                        // underscores in hex
3.14                           // float literal
1.0e10                         // scientific notation
1.5e-3                         // scientific with negative exponent
0.                             // trailing dot float (no digits after decimal)
2340.                          // trailing dot float (integer-like appearance)
// NOTE: trailing dot floats are valid Jai but tree-sitter grammar cannot support them
// because `0.` would break `0..10` range expressions (lexer greedy match)
// Source: how_to/010_basics.jai, modules/Math/module.jai
```

## Structs
<!-- verified: beta 0.2.028 -->

```jai
Vector3 :: struct {
    x: float;
    y: float;
    z: float;
}

// Default values
Thing :: struct {
    name: string;
    count := 0;                     // field with default (:= syntax)
    data: int = ---;                // uninitialized
}

// Using modifiers in struct fields
Filtered :: struct {
    using,except(a, b) inner: Inner;          // exclude specific fields
    using,only(x, y) pos: Position;           // include only specific fields
    using,except EXCLUSION_LIST f: Foo;       // identifier reference
    using,map(prefix_with_gl) procs: Procs;   // name remapping
}

// Embedding/inheritance
Player :: struct {
    using base: Entity;             // fields of Entity promoted to Player
    using #as base2: OtherBase;     // auto-cast to base type
    name: string;
}

// Polymorphic struct
Holder :: struct (T: Type, N: int = 4) {
    data: [N] T;
}

// With #modify
Container :: struct (T: Type) #modify { if T == void then T = int; } {
    value: T;
}

// Modifiers
// NOTE: #packed does NOT exist. Use #no_padding AFTER closing brace:
// Thing :: struct { x: u8; y: u32; } #no_padding
Reduced :: struct #type_info_none { data: int; }
Reduced2 :: struct #type_info_procedures_are_void_pointers { cb: #type () -> void; }
NoSize :: struct #type_info_no_size_complaint { data: int; }
// Multiple struct modifiers can be combined on a single struct:
GL_Procedures :: struct #type_info_procedures_are_void_pointers #type_info_no_size_complaint {
    glActiveTexture: #type () -> void;
}
// Source: modules/GL/glad_core.jai, modules/GL/glad_all.jai
// Struct modifiers go BETWEEN 'struct' keyword and opening '{':
//   #type_info_none — strip all type info at runtime (empty struct)
//   #type_info_procedures_are_void_pointers — simplify proc field info
//   #type_info_no_size_complaint — suppress size warnings
// Source: how_to/935_type_info_reduction.jai
// These are extensively used in COM/VTable bindings (modules/dxgi/, modules/d3d11/, etc.)
// ~297 uses of #type_info_none, ~15 of #type_info_procedures_are_void_pointers,
// ~6 of #type_info_no_size_complaint across the distribution

// Memory layout
// NOTE: #place was REMOVED in beta 0.2.027 (won't compile). Use #overlay instead.
// Layout :: struct { #place x; x: float; y: float; }  // NO LONGER VALID

// #overlay — alias a field over an existing field's memory
// Source: modules/Float16.jai
Matrix3_Float16 :: struct {
    _11, _12, _13: Float16;
    _21, _22, _23: Float16;
    _31, _32, _33: Float16;
    #overlay (_11) floats: [9] Float16;  // overlays _11's memory
}

// #align — field alignment directive (suffix on field declaration)
// Source: modules/Runtime_Support.jai, modules/Android/native_app.jai
AlignedData :: struct {
    x: u8;
    data: [16] u8 #align 16;        // field aligned to 16 bytes
    ctx: CONTEXT #align 32;          // aligned to 32 bytes
    crc: u32 #align 1;              // pack tightly (1-byte alignment)
}

// Anonymous struct/enum/union as field types
// Source: modules/Pool.jai
Options :: struct {
    code: enum { NONE; SUCCESS; };           // anonymous enum
    flags: enum_flags u32 {                  // anonymous enum_flags with :: values
        READ   :: 0x1;
        WRITE  :: 0x2;
    };
    inner: struct { x: int; y: int; };       // anonymous struct
    value: union { as_int: int; as_f: float64; };  // anonymous union
}

// BARE anonymous struct/union members (no field name) — (Pass 9 discovery)
// Source: modules/Windows.jai:63, modules/POSIX/bindings/linux/base.jai,
//         modules/Bindings_Generator/tests/*.jai, modules/executable_formats/*.jai
// 196 uses across the distribution, primarily in C/C++ bindings
LARGE_INTEGER :: union {
    struct {                                 // bare anonymous struct (no field name!)
        LowPart : u32;
        HighPart : s32;
    }                                        // NOTE: no semicolon after closing }
    QuadPart : s64;
}
// The fields of the bare anonymous struct/union are promoted to the parent scope
// This matches C's anonymous struct/union behavior
// Can also appear in struct bodies:
curl_fileinfo :: struct {
    filename: *u8;
    strings: struct {                        // named field with anonymous struct type
        time: *u8;
        perm: *u8;
    };
    union {                                  // bare anonymous union (no field name, no semicolon)
        data_ptr: *void;
        data_int: s64;
    }
}
// Key syntactic difference: bare form has NO field name and NO trailing semicolon
// Named form: `field_name: struct { ... };` (with semicolon)
// Bare form:  `struct { ... }` (no semicolon, no field name)

// Field override (in extended struct)
Extended :: struct {
    using base: Base;
    base.flavor = .CHOCOLATE;       // override base field default
}
```

## Struct/Array Literals
<!-- verified: beta 0.2.028 -->

```jai
Type.{field = value, field2 = value2}    // named fields
.{field = value}                          // type-inferred
Type.{val1, val2, val3}                  // positional
Type.{field[0] = val, field[1] = val2}   // indexed field initializer
Type.{name = "Ginger", values[1] = 7}   // mixed named + indexed initializer
// Source: how_to/007_struct_literals.jai:136
.{ns.index = xx URI, name.index = xx N}  // dotted subfield initializer
// Source: modules/Android/Toolchain/manifest.jai (~40 uses of field.subfield = val)
// Dotted field names (field.subfield) in struct literals allow setting nested struct members
.[1, 2, 3]                               // array literal (type-inferred)
Type.[1, 2, 3]                           // typed array literal

// Non-dot struct literals (NEW in beta 0.2.022)
// Source: CHANGELOG.txt beta 0.2.022, modules/Overwriting_Allocator/module.jai
{3, 4}                                    // struct literal without leading dot
return {};                                // empty struct literal (vs return .{})
return { proc, u };                       // struct literal in return
a = .[{3, "Yes"}, {2, "No"}]            // non-dot struct literals inside array literal
// Special case: 'if x == {}' does NOT parse as a switch (compiler 0.2.023+ special case)
```

## Enums
<!-- verified: beta 0.2.028 -->

```jai
Direction :: enum { NORTH; SOUTH; EAST; WEST; }
Color :: enum u8 { RED; GREEN :: 5; BLUE; }       // backing type + explicit values
Flags :: enum_flags u32 { READ; WRITE; EXEC; }    // bitflag enum
Strict :: enum #specified { A :: 1; B :: 2; }      // all values must be explicit
Exhaustive :: enum #complete { A; B; C; }          // switches must be exhaustive

// Using enum (anonymous, promotes values to scope)
using enum u16 { NONE; SOME :: 5; ALL; }
```

## Unions
<!-- verified: beta 0.2.028 -->

```jai
// Basic union
Value :: union {
    as_int: int;
    as_float: float64;
}

// Tagged union (NEW in beta 0.2.023)
// Source: CHANGELOG.txt beta 0.2.023, beta 0.2.025
Value_Kind :: enum u8 { SCALAR :: 0; VECTOR :: 1; STRING :: 2; }
Value :: union kind: Value_Kind {
    scalar: float64;
    vector: Vector4;
    _string: string;
}
// Tag must be integer or Type. Becomes first struct member.
// Each field after {} is re-packed after tag per alignment rules.

// Tagged union with value bindings (NEW in beta 0.2.025)
// Source: CHANGELOG.txt beta 0.2.025
Fruit :: enum u8 { APPLE :: 0; BANANA :: 1; ORANGE :: 2; }
Thing :: union fruit: Fruit {
    .APPLE  ,, x: int;                  // bind tag value to field
    .BANANA ,, y: float;
    .ORANGE ,, z := "text";
}
// NOTE: ,, syntax for bindings is experimental and may change (case keyword considered)
// Struct literals can now be used to ASSIGN to tagged unions (0.2.029):
//   t = .{ .BANANA, y = 3.14 };    // assign-via-literal syntax
// Source: CHANGELOG.txt beta 0.2.029
// IMPORTANT: Each variant supports exactly ONE field binding. Multi-field variants
// require a wrapper struct. Source: jai-wayland code generator (2026-04-03).
// Example workaround for multi-field event data:
//   Motion_Args :: struct { time: u32; x: Fixed; y: Fixed; }
//   Event :: union kind: Kind { .MOTION ,, motion: Motion_Args; }
// Type_Info_Tagged_Union_Binding available in modules/Preload for metaprogramming
// Walking tagged union bindings at compile time:
//   si := cast(*Type_Info_Struct) ti;
//   tag_member := si.members[0];                   // first member is the tag field
//   tag_type := cast(*Type_Info_Struct) tag_member.type;  // the enum type
//   for binding: si.tagged_union_bindings {
//       variant := si.members[binding.member_index]; // the variant's field
//       variant_type := cast(*Type_Info_Struct) variant.type;  // the variant's arg struct
//       // binding.constant_value is the tag enum value (u64)
//       // variant.name is the field name (e.g., "mode")
//       // Use to generate dispatch code: if tag == N { handle variant }
//   }

// Parameterized (polymorphic) union
// Source: modules/Debug/windows.jai
SymbolBuffer :: union(name_length: u32 = 0) {
    symbol: IMAGEHLP_SYMBOL64;
    data: [size_of(IMAGEHLP_SYMBOL64) + name_length] u8;
}
buffer: SymbolBuffer(MAX_NAME_LEN);  // instantiation with parameter
// Same syntax as polymorphic structs but for unions
```

## Control Flow
<!-- verified: beta 0.2.028 -->

### If Statement
```jai
if cond { ... } else { ... }
if cond then stmt;                      // bare body with 'then'
if cond  stmt;                          // bare body ('then' optional)
if cond then stmt; else other;          // bare body with else
```

### If-Case (Switch)
```jai
if value == {
    case .A;
        handle_a();
    case .B;
        handle_b();
        #through;                       // fall through to next case
    case;
        handle_default();
}
if #complete value == { ... }           // exhaustiveness check
```

### For Loop
```jai
for array { print(it); }               // implicit it, it_index
for elem: array { }                     // named element
for elem, idx: array { }               // named element + index
for `it, `it_index: array { }         // backticked iterator bindings
for 0..10 { }                          // range (inclusive both ends)
for < array { }                         // reverse iteration (unconditional)
for * array { }                         // by-pointer iteration (unconditional)
for <=reversed array { }               // conditional reverse (baked bool)
for <=cast(bool)(flags & .REVERSE)  array { }  // conditional with cast expression
for <=REVERSE bucket, bi: array { }   // conditional with named iterators
for * < array { }                      // pointer + reverse (unconditional)
for *=expr, <=expr  array { }         // both conditional (comma-separated)
for <=REVERSE *=DO_POINTER `it, i: bucket.data { }  // conditional both + backtick
for :custom_iterator container { }     // named for-expansion
for array  stmt;                        // bare statement body

// for_expansion definition (custom iterator protocol)
for_expansion :: (container: *$T, body: Code, flags: For_Flags) #expand {
    // `it, `it_index exported to caller via backtick
    // #insert (break=..., remove=...) body;
}

// Exporting additional state beyond it/it_index:
// Any backtick variable declared in the for_expansion is visible in the loop body.
// Source: how_to/730_for_expansions.jai (extra_info example)
for_expansion :: (holder: *Holder, body: Code, flags: For_Flags) #expand {
    _internal: InternalState;        // underscore prefix avoids shadowing
    `state := *_internal;            // expose pointer to loop body
    `visited_index := 0;
    for ok, slot_index: holder.occupied {
        if !ok continue;
        `it := holder.values[slot_index];
        `it_index := slot_index;
        defer `visited_index += 1;   // defer so continue still increments
        #insert(break=break) body;
    }
}
// Usage: loop body can reference `state` and `visited_index` by name
for holder { print("%, state=%\n", it, state.*); }

// CRITICAL: #insert only remaps keywords you specify. If you remap break
// but not continue, a `continue` in the body targets the innermost loop
// in the for_expansion — which may skip post-body cleanup code.
// Solution: use `defer` for any post-body logic that must always run.
// Source: how_to/730_for_expansions.jai line 133
for_expansion :: (q: *Queue, body: Code, flags: For_Flags) #expand {
    while msg := q.peek() {
        defer q.consume(msg);        // runs on normal exit, continue, AND break
        `it := msg;
        `it_index := 0;
        #insert(break=break) body;   // continue in body skips to defer, not past it
    }
}
```

### While Loop
```jai
while cond { }
while name := get_char() { }           // named loop variable
while cond  stmt;                       // bare body
```

### Loop Control
```jai
break;
continue;
break label;                           // labeled break
continue label;                        // labeled continue
remove it;                              // remove during iteration (explicit target)
remove;                                 // bare remove — removes current iterator element (implicit `it`)
// Source: modules/Input/windows.jai:85 (bare form)
// Source: examples/codex_view/src/draw_live_allocations.jai:152-154 (bare form in braceless if)
// Common pattern: `for items.* if condition remove;` — braceless for+if+bare remove
// ~1 file uses bare `remove;`, ~20+ files use `remove <expr>;`
```

### Backtick Prefix (from #expand macros)
```jai
my_macro :: () #expand {
    `x := 1;                           // export x to caller scope
    `defer free(ptr);                   // defer in caller scope
    `break;                             // break caller's loop
    `continue;                          // continue caller's loop
    `remove it;                         // remove in caller's loop
}
```

### Loop-Body Directives
<!-- verified: beta 0.2.028 -->
```jai
// #no_abc and #no_aoc can appear BETWEEN iterable and body in for loops
// Source: modules/Hash.jai
for 0..size-1 #no_abc #no_aoc {        // no array bounds check, no auto output capture
    h = (h << 5) + h + data[it];
}
// For-loop modifier order is flexible: `for < *` and `for <*` are both valid
// The `<` (reverse) and `*` (pointer) modifiers can appear in any order with optional space
```

### Standalone #no_aoc / #no_abc Block Statements
<!-- verified: beta 0.2.028 -->
```jai
// #no_aoc can wrap an arbitrary block of statements (NOT just for-loops)
// This disables arithmetic overflow checking for the enclosed operations
// Source: modules/Basic/Int128.jai, modules/Basic/float_to_string.jai
#no_aoc {
    c.low = a.low + b.low;      // overflow check suppressed
}

// Can also appear as an else clause:
#if CPU == .X64 {
    #asm { ... }
} else #no_aoc {                  // else with #no_aoc block
    c.high = a.high - b.high;
    c.low  = a.low  - b.low;
}

// Note: only #no_aoc { } standalone blocks observed in distribution
// No standalone #no_abc { } blocks found (only as procedure/loop modifier)
// Source: modules/Basic/Int128.jai (~5 occurrences), modules/Basic/float_to_string.jai (~1)
```

### Other
```jai
defer stmt;                             // deferred execution
defer { block; }                        // deferred block
push_context new_ctx { ... }           // context switch scope with expression
push_context { ... }                   // push DEFAULT #Context (no expression)
// Source: how_to/011_context.jai, modules/Input/macos.jai, modules/Thread/primitives.jai
push_context,defer_pop ctx;            // push_context with comma modifier (in #expand macros)
// Source: modules/Remap_Context.jai
```

### Ifx Expression (Conditional)
```jai
result := ifx cond then a else b;
result := ifx cond  a;                         // without 'then' keyword
result := ifx cond then { compute(); } else { other(); };
result := #ifx cond then a else b;     // compile-time ifx
```

## Directives
<!-- verified: beta 0.2.028 -->

### Imports
```jai
#import "Basic";
#import "Module"(PARAM=value);          // with module parameters
#import,file "path";                    // file import
#import,dir "path";                     // directory import
#import,string "code";                  // string import (inline code)
#import,string #string END              // string import with here-string
code here
END
#load "file.jai";                       // file inclusion

// using with #import — promotes all module exports into current scope
using Basic :: #import "Basic";                      // all exports visible without Basic. prefix
using Random :: #import "Random";                    // direct access to random(), seed(), etc.
using,except(Node) Trees :: #import,file "trees.jai"; // import with exclusions
using,except(Cowabunga) Basic :: #import "Basic";    // exclude specific names
using Sound :: #import "Sound_Player"(VERBOSE = false); // using + import with params
// Source: how_to/042_using.jai, how_to/044_using_advanced/main.jai
// Source: modules/Window_Creation/android.jai, modules/Sound_Player/examples/

// NOTE: #foreign_import does NOT exist. Use #library for foreign libraries.
```

#### Named vs Anonymous Import Semantics

**Named import** (`Name :: #import "Module"`) namespaces everything under `Name.`:
- Bare names like `assert`, `free`, `NewArray` won't compile — must use `Name.assert`, etc.
- **Operator overloads don't propagate through namespaces.** If a module defines operators for its types (e.g., `Basic` defines `+`, `-`, `==` for `Apollo_Time` via `S128`), a named import won't make those operators available. This means `time_a - time_b` fails at compile time even though the module provides the operator.
- Use when: you want to avoid polluting the namespace, or only call a few qualified functions.

**Anonymous import** (`#import "Module"`) brings all exports directly into scope:
- Bare `assert`, `free`, `NewArray`, etc. work without qualification.
- Operator overloads propagate into scope — arithmetic on types like `Apollo_Time` works.
- Use when: the module is used broadly (many functions called) or you need its operator overloads.

**Re-exporting operators from named imports** (when you need named import but also need operators):
```jai
// In module scope — re-export specific operators
Basic :: #import "Basic";
operator- :: Basic.operator-;    // make subtraction work for Basic's types
```
Source: `modules/Thread/module.jai`

**Common pitfall:** A module that uses `Name :: #import "Basic"` but calls bare `assert()` or `free()` in its source files will compile fine if never independently instantiated (e.g., no test suite imports it). The error only surfaces when the module is first compiled as a dependency. Always verify modules compile by adding them to the test build.

### Compile-Time Execution
```jai
#run expr;                              // compile-time execution
#run { block; }
#run -> Type { ... }                    // #run with return type (inline compile-time block)
// Source: modules/Android/Toolchain/crypto.jai, how_to/044_using_advanced/main.jai
// Also: #run -> string { ... }, #run -> bool { ... }, #run -> [] string { ... }
#run,stallable expr;                    // run with modifier (avoids stalling)
#run,stallable -> Type { ... }         // stallable with return type
// Source: examples/VR/modules/Vulkan_Paths.jai, modules/Default_Metaprogram.jai
// a, b := #run -> Type1, Type2 { ... }  // multi-return form
#if cond { ... } else { ... }          // static conditional
#if cond  stmt;                         // static if with bare body
#if cond  #load "a.jai"; else  #load "b.jai";  // braceless static if/else
#if cond then stmt;                     // single-line static if with 'then' keyword
// Source: modules/ (discovered Pass 3 testing)
#if value == {                          // static if case form
    case .A;  handle_a();
    case .B;  handle_b();
} else #if other_val == { ... }        // else chain
#assert(cond);                          // parenthesized form
#assert cond;                           // bare form
#assert cond "message";                 // with message (NO comma, space-separated)
#insert expr;                           // code insertion (string: resolves in textual scope)
#insert,scope() expr;                  // with scope (Code: inherits caller scope; string: still textual scope)
#insert(break=break outer) expr;       // with break parameter mapping
#insert(continue=continue outer) expr; // with continue parameter mapping
#insert(remove=#assert(false)) expr;   // with remove parameter
#insert(break=break slot, remove={stmt; stmt;}) expr;  // combined break + remove
#insert(break=break outer, continue=continue inner) expr;  // combined break + continue
#insert(remove={inline remove_fn(arr, `it_index); `it_index -= 1;}) body;  // remove with compound body
#insert -> Code { return #code x = 1; }  // short form (arrow + block)
#code { block; }                        // code literal (type: Code)
#code expr;
#code,typed expr;                      // code with modifier
#code x = expr;                        // code assignment literal
#bake_arguments func(param = value);   // partial application
#bake_constants func(param = value);
```

### Strings & Characters
```jai
#string END
multi-line
content here
END
#string,cr DELIM                        // normalize line endings to \r\n
content with CRLF endings
DELIM
#string,\% DELIM                       // enable \% escape processing
100\% accurate                         // \% becomes literal % (prevents format expansion)
DELIM
// Source: how_to/005_strings.jai (#string,cr), how_to/018_print_functions.jai (#string,\%)
#char "x"                              // character literal → u8
```

### Scope Control
```jai
#scope_file                            // visible only in this file
#scope_module                          // visible in module
#scope_export                          // exported from module
```

### Type System
```jai
#type (params) -> ReturnType           // explicit procedure type
#type (x: int) -> result: int, ok: bool  // with named returns
// Source: modules/Bindings_Generator/module.jai, modules/Android/module.jai
#type (a0: *u8, *void) -> s32 #c_call  // with calling convention modifier
#type (this: *IDxcBlob) -> *void #cpp_method  // with #cpp_method
// Source: modules/X11/sofd/module.jai, modules/dxc_compiler/dxc_compiler_bindings.jai
#type () -> *u8 #foreign               // with #foreign (no library, used in casts)
// Source: modules/POSIX/generate_glibc_bindings.jai: cast(#type () -> *u8 #foreign)
(params) -> ReturnType                 // bare procedure type (in type positions)
(*void) #no_context                    // bare void proc type with modifier (struct fields)
// Source: modules/Preload.jai: initializer: (*void) #no_context;
#type,distinct Type                    // distinct type variant
#type,isa Type                         // subtype variant
```

### Type Variants (`#type,distinct` and `#type,isa`)
<!-- verified: beta 0.2.028, from how_to/180_type_variants.jai -->
```jai
// #type,distinct — newtype: same layout, NO implicit cast to/from base type.
// Use for type safety when you want the same representation but distinct identity.
// Source: how_to/180_type_variants.jai
Handle :: #type,distinct u32;          // u32 under the hood, but won't mix with u32
Grid3i :: #type,distinct [3] s32;      // works with arrays too
Fd     :: #type,distinct s32;          // e.g. tag file descriptors distinctly from s32

a: Handle = 5;                         // literals implicitly cast (as with any numeric type)
b: u32 = 42;
// a = b;                              // ERROR: no implicit cast from u32 to Handle
a = cast(Handle) b;                    // explicit cast OK
a = xx (b + 1);                        // auto-cast OK
a + a;                                 // built-in math operators work between same distinct type
3 * a + 2;                             // math with literals works too

// Introspection: type_info(Handle).type == .VARIANT
// cast(*Type_Info_Variant) type_info(Handle) gives .variant_of pointing to u32's type_info
// This lets compile-time code generators distinguish Handle from u32 via type_info.

// #type,isa — subtype: same layout, IMPLICIT downcast to base type (one-way).
// Forms a subtype chain: Fully_Pathed → Filename → string
Filename     :: #type,isa string;      // can pass anywhere a string is accepted
Fully_Pathed :: #type,isa Filename;    // can pass as Filename or string

// Operator return type promotion: when a #type,isa value is implicitly downcast
// to its base type for a procedure call, and the return type equals the base type,
// the result is automatically promoted back to the variant type.
// Source: how_to/180_type_variants.jai lines 84-99
pa: Position3;  pb: Position3;         // Position3 :: #type,isa Vector3
p := pa + pb;                          // calls Vector3 + Vector3, result promoted to Position3
assert(type_of(p) == Position3);       // true

// Compile-time use: distinct types are powerful for compile-time code generation.
// A struct-walking macro can match on type_info to emit different code per field:
//   member.type == type_info(Fd)  → emit fd-passing code (out-of-band)
//   member.type == type_info(s32) → emit regular s32 serialization
// Same runtime representation, different compile-time behavior. Zero overhead.
```

### Introspection
```jai
#caller_location                       // Source_Code_Location of caller
#caller_code                           // Code of caller
#location(expr)                        // source location
#filepath                              // current file path
#file                                  // current file path (alias)
#line                                  // current source line number
#compile_time                          // boolean: true if running at compile time
#exists(context.foo)                   // check if a symbol/expression exists
#this                                  // current struct/scope
#procedure_of_call(call_expr)          // get procedure from polymorphic call
#procedure_name()                      // name of current procedure as string
```

### Inline Assembly
```jai
#asm { ... }                           // inline assembly (opaque body)
#asm AVX, AVX2 { ... }                // with ISA feature flags

// #asm as bare statement (used with #if and else):
#if BITS == 8 #asm {                   // #if condition followed directly by #asm block
    movzxbw two_bytes:, value;
    popcnt.16 result, two_bytes;
} else #asm {                          // else clause with #asm block
    popcnt?BITS result, value;
}
// Source: how_to/900_inline_assembly.jai, modules/Bit_Operations.jai

// #bytes — raw machine code byte emission (standalone statement, NOT limited to #asm blocks)
// Used for platform-specific instructions that #asm doesn't support (e.g., ARM64 on non-ARM hosts)
// Source: modules/Runtime_Support.jai (lines 465, 469, 507, 662),
//         modules/rpmalloc/rpmalloc.jai (line 688)
// Syntax: #bytes <array_literal>;
#bytes .[0x3F, 0x20, 0x03, 0xD5];     // ARM64 YIELD instruction
#bytes .[0x02, 0x80, 0x00, 0x00];     // ARM64 UDF 0x8002 (breakpoint)
#bytes .[0x20, 0x00, 0b001_0_0000, 0b1101_0100]; // ARM64 BRK 0x01
// Array literal can contain hex (0xFF), decimal, and binary (0b...) byte values
// Typically guarded by #if CPU == .ARM64 or similar static conditionals
// ~6 total uses in distribution, all ARM64-specific

// Inside #asm blocks, register declarations use `name:` and `name:,`:
//   mov temp:, [*ptr + 0];          // declare output register 'temp'
//   cpuid a, b:, c, d:;            // b and d are output registers (name:,)
//   xor.d a: gpr === a, a;         // declare with register class constraint
//   movd source:, byte;             // declare and initialize from variable
// Source: modules/Machine_X64.jai, modules/Bit_Operations.jai, modules/String/module.jai
```

### External Declarations (`#elsewhere`)
<!-- verified: beta 0.2.028 -->
```jai
// #elsewhere declares variables/procedures whose bodies live in external libraries
// Source: examples/dll/main.jai, modules/macOS/bindings/core_foundation.jai, modules/macOS/bindings/mach.jai

// External library declaration
Helper :: #library,no_static_library "helper";

// Procedure with #elsewhere (body in external library)
do_something :: () #no_context #elsewhere Helper;
get_value    :: () -> string   #elsewhere Helper;

// Global variable with #elsewhere (value in external library)
NDR_record: NDR_record_t #elsewhere libc;
kCFNull: CFNullRef #elsewhere corefoundation;
kCFAllocatorDefault: CFAllocatorRef #elsewhere corefoundation;
// Syntax: name: Type #elsewhere library_identifier;
// #elsewhere goes AFTER procedure modifiers (#no_context etc.) and return type

// #elsewhere with custom link name (C++ mangled names, ObjC symbols, etc.)
// Source: modules/POSIX/bindings/macos/x64/stdio.jai, modules/Bindings_Generator/tests/windows.jai
stdin: *FILE #elsewhere libc "__stdinp";                        // custom link name string
DefaultOutside: ConstStuff #elsewhere cpp_library "?DefaultOutside@@3UConstStuff@@A";  // C++ mangled
__view_class_object: *void #elsewhere library "OBJC_CLASS_$_LightweightOpenGLView";    // ObjC class symbol
// Source: modules/Objective_C/LightweightRenderingView/module.jai

// #elsewhere without library (compiler-provided or same binary)
// Source: modules/Compiler/Compiler.jai, modules/Objective_C/GameController.jai
__runtime_info: Runtime_Info #elsewhere;                        // no library specified
GCControllerDidConnectNotification: *NSString #elsewhere;       // bare #elsewhere
NSApp: *NSApplication #elsewhere;                               // from AppKit
// Used when the symbol is provided by the binary itself (no external library needed)

// GRAMMAR NOTE: #elsewhere has 4 forms:
//   name: Type #elsewhere;                          -- bare (no library)
//   name: Type #elsewhere lib;                      -- with library identifier
//   name: Type #elsewhere lib "link_name";           -- with library + custom link name
//   proc :: () -> T #modifier #elsewhere lib;        -- after procedure signature + modifiers
// ~30 files in the distribution use #elsewhere, primarily:
//   - POSIX bindings (stdin/stdout/stderr, timezone vars, signal lists)
//   - macOS CoreFoundation/AppKit constants
//   - Android media format keys
//   - C++ binding tests (mangled names)
//   - Compiler internals (__runtime_info)
```

### Code Literals
<!-- verified: beta 0.2.028 -->
```jai
#code { block; }                        // code literal (type: Code)
#code expr;                             // expression as code
#code,typed expr;                       // typed code (resolved/typechecked in local scope)
#code x = expr;                         // code assignment literal

// #code,null — null value for Code-typed parameters
// Source: modules/Compiler/Compiler.jai, examples/codex_view/src/draw_live_allocations.jai
draw_items :: ($color_proc_code := #code,null) { }  // default param
compiler_get_code :: (code_to_copy_scope_from: Code = #code,null) -> Code #compiler;
// #code,null tests as false in 'if'. The Code_Code node has a NULL flag (0x2).

// Code.type — get the root expression type from a constant Code
// Source: examples/code_type.jai
f :: ($c: Code) -> u32 {
    T :: c.type;    // T is the type of the root expression in the Code
    return 42;
}
// For non-constant Code, use get_root_type(c) from modules/Compiler
// #code,typed ensures the code is resolved locally so get_root_type works
// Source: examples/code_type.jai (detailed example)
```

### Compile-Time AST Rewriting (#code + compiler_get_nodes + #insert)
<!-- verified: beta 0.2.028, from how_to/630_compiler_get_nodes.jai -->
```jai
// Pattern: Walk/modify AST captured with #code, then #insert the result.
// Requires: #import "Compiler";
//
// compiler_get_nodes returns a FRESH COPY of the AST (safe to mutate).
// 'expressions' is a flat list of ALL sub-nodes in the tree.
// Source: how_to/630_compiler_get_nodes.jai

// --- AST modification pattern (modify nodes in-place, re-emit as Code) ---
my_macro :: (c: Code) #expand {
    transform :: (code: Code) -> Code {
        root, expressions := compiler_get_nodes(code);
        for expressions {
            if it.kind != .LITERAL continue;
            literal := cast(*Code_Literal) it;
            if literal.value_type != .STRING continue;
            literal._string = modify_string(literal._string);  // mutate in-place
        }
        return compiler_get_code(root);  // convert modified AST back to Code
    }
    modified :: #run transform(c);
    #insert,scope() modified;  // ,scope() inherits caller's scope
}

// --- String generation pattern (walk AST, generate new code as string) ---
// More flexible than AST modification: can inject new identifiers, rewrite
// call signatures, add validation. The generated string is compiled when inserted.
//
// CROSS-MODULE SCOPING: When an #expand macro lives in a module, #insert of a
// generated string resolves identifiers in the MODULE's scope — both #insert and
// #insert,scope() behave this way for strings. To reference caller-defined names
// (types, functions), use backtick-prefixed identifiers (`Name) in the generated
// string. Backtick identifiers resolve in the caller's scope, same mechanism as
// `it, `it_index, `break in for-expansion macros.
//
// Module-defined names (exported types, internal functions) don't need backticks.
//
// Example: generated string for cross-module override validation:
//   _overrides := Override.[
//       make_internal(`CallerStruct, "field", `caller_write_fn),  // backtick = caller scope
//   ];
//
// DEBUGGING: The compiler writes all #insert-ed strings to .build/.added_strings_wN.jai
// (hidden file, dot-prefixed). Inspect this to see exactly what was generated and inserted.
// The file shows each insert with its source location and the full generated text.
//
my_macro2 :: (row: *$T, override_code: Code = #code .[]) #expand {
    generate :: (code: Code, struct_ti: *Type_Info) -> string {
        si := cast(*Type_Info_Struct) struct_ti;
        root, expressions := compiler_get_nodes(code);
        sb: String_Builder;
        for expressions {
            if it.kind != .PROCEDURE_CALL continue;
            call := cast(*Code_Procedure_Call) it;
            if call.procedure_expression.kind != .IDENT continue;
            ident := cast(*Code_Ident) call.procedure_expression;
            if ident.name != "target_fn" continue;
            // Extract args, validate, generate new code string...
            args := call.arguments_unsorted;  // [] Code_Argument
            arg_expr := args[0].expression;   // *Code_Node
            // Backtick caller-scope names, no backtick for module-scope names:
            // print_to_builder(*sb, "rewritten_fn(`%, \"%\", `%),\n",
            //     si.name, field_name, fn_ident.name);
        }
        return builder_to_string(*sb);
    }
    _gen :: #run generate(override_code, type_info(T));
    #insert,scope() _gen;  // variables declared here are available below
}

// Key Compiler AST types:
// Code_Node        — base; .kind is Code_Node.Kind enum
// Code_Node.Kind   — .LITERAL, .IDENT, .PROCEDURE_CALL, .BLOCK, .DECLARATION, ...
// Code_Procedure_Call — .procedure_expression (*Code_Node), .arguments_unsorted ([] Code_Argument)
// Code_Argument    — .expression (*Code_Node), .name (*Code_Ident, null if positional)
// Code_Ident       — .name (string), .resolved_declaration (*Code_Declaration)
// Code_Literal     — .value_type (.STRING, .NUMBER, .ARRAY, .STRUCT, ...), ._string, ._s64, etc.
// Code_Array_Literal_Info — .array_members ([] *Code_Node)
//
// compiler_get_nodes :: (code: Code) -> (root: *Code_Node, expressions: [] *Code_Node) #compiler;
// compiler_get_code  :: (node: *Code_Node, ...) -> Code #compiler;
// compiler_report    :: (message: string, loc := #caller_location, mode := Report.ERROR) #compiler;
//   Report :: enum u8 { ERROR; WARNING; INFO; }  // from #import "Compiler"
//
// #code delays name resolution — identifiers don't need to exist until #insert.
// This enables "phantom function" patterns: user writes make_foo("x", fn) in #code,
// macro rewrites to make_foo_internal(StructType, "x", fn) via string generation.
// Two-phase validation: AST walk validates structure, polymorph #assert validates types.
```

### Metaprogramming Directives
<!-- verified: beta 0.2.028 -->
```jai
// #poke_name — replace a name in an inserted/injected scope
// Source: modules/Iprof/instrument.jai
#poke_name target_scope replacement_name;

// NOTE: #body_text was REMOVED from the language (replaced by #run_and_insert, also removed)
```

### Other Directives
```jai
#no_reset                              // retain compile-time value at runtime
#placeholder my_func                   // forward declaration for metaprogram
#module_parameters(T: Type)(...)       // module configuration
#module_parameters(NAME := default);   // with := defaults
#module_parameters(A: [] Type = DEF);  // with typed defaults
#module_parameters(A := 1, B := 2,);  // trailing comma OK
#module_parameters (LOAD := true)(CACHE_SIZE : s32 = 64, DEBUG := false);  // two-level params
#module_parameters () (DEBUGGER := false, IFACE: $I/interface MyInterface = DefaultImpl);  // polymorphic interface constraint in module params
#import "X"(A = 1, B = 2,);           // trailing comma in import params OK
#add_context depth: s32;               // add to implicit context
#add_context depth: s32 = 0;           // with default
#add_context read := 0;                // with type inference (:=)
#add_context :: MY_CONSTANT;           // constant binding (::)
#add_context #as using base: Context_Base;  // with #as and using
#add_context input_handler: struct {   // anonymous struct type
    window_proc := MyWindowProc;
    window_proc_allocator: Allocator;
};
// Source: modules/Input/windows.jai
#add_context generator: *struct #type_info_none {  // ptr to anonymous struct with modifier
    global_scope: Block;
    // ...
};
// Source: modules/Bindings_Generator/module.jai, modules/Bindings_Generator/restart.jai
// Source: modules/ (various), discovered Pass 3 and Pass 4 testing
#library,system "kernel32"             // system library
#library,no_dll "lib"                  // static library
#library,no_static_library "helper"   // dynamic library only (no static linking)
#library,system,no_dll "lib"           // multiple library modifiers
#library,system,no_dll "libc_stub_weak" // system + no_dll combined
#library,system,link_always "lib"      // always link this library
#library,no_dll,link_always "x64/libandroid_native_app_glue" // no_dll + link_always combined
// Source: modules/Android/Native_App/bindings.jai, modules/Android/generate.jai

// Standalone #library (no name :: binding) — used for link-only declarations
#library,system,link_always "libm";   // standalone: just links the library, no identifier
// Source: modules/stb_vorbis/module.jai, modules/stb_image/module.jai
// NOTE: #system_library is deprecated in favor of #library,system (CHANGELOG beta 0.2.019)
// Source: examples/dll/main.jai (#library,no_static_library)
// Source: modules/Default_Allocator/module.jai (#library,system,no_dll)
#foreign lib_handle                    // foreign function from library
#program_export                        // export procedure to executable
#program_export "entry"                // export with custom name
#file                                  // current file path (alias for #filepath)
#filepath                              // current file path
```

## Operators
<!-- verified: beta 0.2.028 -->

### Precedence (high to low)

| Prec | Operators | Description |
|------|-----------|-------------|
| 17 | `.field` | Field access |
| 16 | `f(args)` | Call |
| 15 | `a[i]`, `p.*`, `(.*) expr`, `<<ptr` (DEPRECATED) | Index, dereference, prefix dereference |
| 14 | `cast(T)`, `xx` | Cast, autocast |
| 13 | `-x`, `+x`, `!x`, `~x`, `*x` | Unary (negate, identity, not, complement, address-of) |
| 12 | `*`, `/`, `%` | Multiplicative |
| 11 | `+`, `-` | Additive |
| 10 | `<<`, `>>`, `<<<`, `>>>` | Shift, Rotate |
| 9 | `<`, `<=`, `>`, `>=` | Comparison |
| 8 | `==`, `!=` | Equality |
| 7 | `&` | Bitwise AND |
| 6 | `^` | Bitwise XOR |
| 5 | `\|` | Bitwise OR |
| 4 | `&&` | Logical AND |
| 3 | `\|\|` | Logical OR |
| 2 | `..` | Range |
| 1 | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `\|=`, `^=`, `<<=`, `>>=`, `&&=`, `\|\|=` | Assignment |

### Rotate Operators
<!-- verified: beta 0.2.028 -->
```jai
x <<< n                               // rotate left (same precedence as <<)
x >>> n                                // rotate right (same precedence as >>)
// Source: modules/md5.jai, modules/xxHash/module.jai
```

### Prefix Dereference (`<<`) — DEPRECATED
<!-- verified: beta 0.2.028 -->
```jai
// WARNING: Unary << is DEPRECATED as of beta 0.2.022 and will be REMOVED in a future beta.
// Use (.*) or postfix .* instead.
// Source: CHANGELOG.txt beta 0.2.022
// The compiler distribution provides modules/Rewrite.jai plugin to auto-rewrite << to .*:
//   jai program.jai +Rewrite -write
<<ptr                                  // prefix dereference (equivalent to ptr.*)
(ptr.*)                                // preferred replacement form
```

### Cast
```jai
// Prefix cast (original syntax, still supported)
cast(float) x                         // explicit cast
cast,no_check(u8) x                   // no overflow check
cast,trunc(u8) x                      // truncating cast
cast,force(U128) x                    // unsafe force cast (bypasses checks)
cast(#type () -> void #c_call) ptr    // cast with complex #type expression
// Source: modules/ (discovered Pass 3 testing)

// Function-call style cast (NEW preferred syntax, chosen by community vote 75%)
// Introduced in "Caststravaganza" beta 0.2.005, officially chosen in 0.2.006
// Source: CHANGELOG.txt beta 0.2.005 (Option 2), beta 0.2.006 (polling result)
// Both prefix and function-call forms coexist; gradual migration planned
cast(float, a.width)                  // expression inside parens after comma
cast(u32, it.required)                // clear precedence, no ambiguity
cast(*u8, p + offset)                 // equivalent to: cast(*u8) (p + offset)
cast(bool, flags & .REVERSE)          // used in for-loop conditional modifiers
// Source: modules/Android/examples/camera.jai (~15 uses),
//         modules/Android/Toolchain/manifest.jai (~10 uses),
//         modules/Android/Jni.jai (~8 uses)
// ~92 total uses across distribution (mostly Android modules)
// NOTE: Modifiers (trunc, force, no_check) placement in function-call form:
//   cast(*u8, p + offset, trunc).*   // modifier INSIDE parens (CHANGELOG example)
//   No confirmed distribution usage of modifier-inside-parens form yet

xx x                                   // autocast
xx,no_check x                         // autocast without check
xx,trunc x                            // autocast with truncation
xx,force x                            // autocast force (bypasses checks)
```

## Special Syntax
<!-- verified: beta 0.2.028 -->

```jai
.ENUM_VALUE                            // unary dot (type-inferred enum)
..array                                // spread (unpack into varargs, types must match)
func(args,, allocator = temp)          // comma-comma (context override)
ptr := New(MyStruct,, temp);           // allocate from temporary storage via ,,
`name                                  // backtick (keyword as identifier)
`return false, .{};                    // backtick return (return from caller in #expand macro)
`break;                                // backtick break (break caller's loop)
left\_margin := 0.014;                 // backslash in identifiers (visual break, ignored by compiler)
// Source: examples/codex_view/src/draw_live_allocations.jai, modules/Basic/Apollo_Time.jai
// Backslash (`\`) inside identifiers is a "visual break" — the compiler strips it
// The identifier `left\_margin` is the same as `left_margin` to the compiler
//
// TWO FORMS (Pass 9 discovery):
// Form 1: No whitespace — `name\_continuation` (visual break only)
//   left\_margin, free\_site_trace, LEFT\_SHOULDER
// Form 2: Whitespace continuation — `name\      _continuation` (visual alignment)
//   month\      _starting_at_0    — modules/Basic/Apollo_Time.jai:260
//   deactivate\         _proc     — modules/GetRect/system/active_widgets.jai:35
//   popups\  _per_frame_update    — modules/GetRect/module.jai:567
//   frame\  _color                — modules/GetRect/system/themes.jai:515
//   allocations\   _since_last    — modules/Basic/Visualize_Memory_Debugger.jai:203
// The `\` followed by spaces/tabs continues the identifier (compiler strips \ and whitespace)
// This is used for visual column alignment of struct fields and variable names
//
// 136 uses across 33 files in the distribution
// Uses found in distribution:
//   shader_sprite_left\_handed    — modules/Simp/shader.jai
//   local\_rect                  — modules/Window_Creation/windows.jai
//   move_cursor_left\_by_word    — modules/GetRect/widgets/text_input.jai
//   LEFT\_SHOULDER, LEFT\_THUMB  — modules/Gamepad/Gamepad.jai
//   left\_arrow_tip              — modules/GetRect/widgets/color_picker.jai
//   a.end\ _string               — examples/dll/main.jai
//   first_\background            — modules/GetRect/examples/example.jai
//   frees\_this_frame            — modules/Basic/Memory_Debugger.jai:1289
//   ident\ _value                — modules/Jai_Lexer/module.jai:166
// TREE-SITTER NOTE: Requires external scanner changes to handle `\` within identifier tokens
@NoteName                              // note/attribute (before decl OR after body)
@"string note"                         // string note
// Notes go: (1) before declaration, or (2) after procedure body closing }
// @note name :: () { }     — BEFORE the declaration
// name :: () { } @note     — AFTER the body (e.g. } @RunWhenReady)

// @selector — Objective-C selector annotation (special note form)
// Goes AFTER procedure body closing } in Objective-C struct method declarations
// Content can include colons as part of ObjC selector naming convention
// Source: modules/Objective_C/examples/cocoa.jai, modules/Input/macos.jai, modules/Gamepad/Gamepad.jai
} @selector(applicationWillTerminate:)    // single-colon selector
} @selector(windowDidResize:toSize:)      // multi-colon selector
} @selector(wantsPeriodicDraggingUpdates) // no-colon selector
} @selector(handleControllerDidConnectNotification:notification:)  // long multi-colon
// ~21 occurrences across modules/Input/macos.jai, modules/Objective_C/, modules/Gamepad/
using x;                               // promote fields to scope
using #as base: Entity;               // using with auto-cast (in struct fields)
#as using,except(vtable) iunknown: IUnknown;  // #as + using,except combined (struct fields)
using,except(a, b) x;                 // using with exclusions (parenthesized)
using,except NAMES x;                 // using with exclusions (identifier ref)
using,except .["a","b"] x;           // using with exclusions (array literal)
using,except #run get_names() x;     // using with exclusions (compile-time)
using,only(a, b) x;                   // using with inclusions
using,map(prefix_fn) x;              // using with name remapping function
```

## Escape Sequences (in string literals)
<!-- verified: beta 0.2.028 -->

| Escape | Meaning |
|--------|---------|
| `\n` | Newline |
| `\t` | Tab |
| `\r` | Carriage return |
| `\0` | Null byte |
| `\e` | Escape (0x1B) |
| `\\` | Backslash |
| `\"` | Double quote |
| `\/` | Forward slash |
| `\%` | Literal percent (in format strings) |
| `\xFF` | Hex byte |
| `\d123` | Decimal byte (0-255). Source: how_to/005_strings.jai:297 |
| `\uFFFF` | Unicode (16-bit) |
| `\UFFFFFFFF` | Unicode (32-bit) |

### `\d` Escape in Practice
```jai
// \d NNN — decimal byte escape (1-3 digits, max value 255)
// Source: how_to/005_strings.jai:297, examples/beta_key_mailer/email_keys.jai:44
TRIM :: "\d010\d013\n \t";    // \d010 = LF (10), \d013 = CR (13)
s := trim_right(cmd, "\d010\d013\d032");  // \d032 = space (32)
// Source: examples/codex_view/src/main.jai:309
//
// TREE-SITTER BUG: The grammar regex /\\d[0-9]{1,3}/ is broken because
// tree-sitter's regex engine interprets \d as the digit character class [0-9],
// not as literal backslash-d. The fix requires escaping: /\\\\d[0-9]{1,3}/
// or using a character class [d] instead: /\\[d][0-9]{1,3}/
```

## Comments
<!-- verified: beta 0.2.028 -->

```jai
// Line comment
/* Block comment — nests arbitrarily: /* nested */ still inside */
```

### Tree-Sitter Note: `//` in String Literals
```jai
// WARNING: Jai strings can contain "//" sequences that tree-sitter's lexer
// may incorrectly parse as line comments. This happens with URLs in strings:
tprint("smtp://%:%\0", host, port);      // "smtp://" contains //
url := "https://example.com/page";        // "//" inside string
// Also happens with format strings containing path separators:
fmt := "C://Users//file.txt";
// Source: modules/Mail.jai, modules/Curl/module.jai
// Tree-sitter's lexer operates at a level below the grammar and will match //
// as a comment token before the grammar can consume it as string content.
// This is a fundamental tree-sitter limitation, not a grammar bug.
```

## File I/O and String Formatting
<!-- verified: beta 0.2.028 -->

### File Module (`#import "File"`)
```jai
// Reading
contents, ok := read_entire_file("path/to/file.txt");     // -> string, bool

// Writing — three overloads:
write_entire_file("out.txt", "string data");               // string -> bool
write_entire_file("out.bin", data_ptr, byte_count);        // *void, int -> bool
write_entire_file("out.jai", *builder);                    // *String_Builder -> bool (resets builder)
write_entire_file("out.jai", *builder, do_reset = false);  // keep builder contents after write

// Directories
make_directory_if_it_does_not_exist("path/to/dir");

// Source: modules/File/module.jai
```

### File_Utilities Module (`#import "File_Utilities"`)
```jai
// Walk directory tree — callback receives *File_Visit_Info and userdata pointer
visit_files("dir", recursive = true, *context, (info: *File_Visit_Info, ctx: *My_Ctx) {
    if ends_with(info.full_name, ".xml") { /* process */ }
});
// Source: modules/File_Utilities/module.jai
```

### String Formatting (`#import "Basic"`)
```jai
// String_Builder for building output
sb: String_Builder;
sb.allocator = temp;                                       // use temp allocator for transient strings
print_to_builder(*sb, "% :: struct {\n", type_name);
result := builder_to_string(*sb,, allocator = temp);       // note: ,, skips do_reset param

// tprint — temp-allocated sprintf
name := tprint("%_%", prefix, suffix);

// formatInt — integer formatting with base, padding, minimum digits
// Source: modules/Basic/Print.jai
tprint("%", formatInt(255, base = 16));                    // "ff"
tprint("%", formatInt(42, minimum_digits = 5));            // "00042"
tprint("%", formatInt(1000, digits_per_comma = 3, comma_string = ","));  // "1,000"
// FormatInt struct: { base := 10; minimum_digits := 1; padding: u8 = '0';
//                     digits_per_comma: u16 = 0; comma_string := ""; }

// formatFloat — float formatting
tprint("%", formatFloat(3.14, trailing_width = 2));        // "3.14"
// FormatFloat.Mode :: enum { DECIMAL; SCIENTIFIC; SHORTEST; }
```

## Context System
<!-- verified: beta 0.2.028 -->

Every Jai procedure receives an implicit `context` parameter containing:
- Allocator (default and temporary)
- Logger
- Stack trace
- User-extensible via `#add_context`

```jai
push_context new_ctx {                 // switch context for scope
    // new_ctx is active here
}
context.allocator = my_allocator;      // modify directly
```

## Language Evolution & Deprecations
<!-- Source: CHANGELOG.txt beta 0.2.019 through 0.2.028 -->

### Removed Features
| Feature | Removed In | Replacement |
|---------|------------|-------------|
| `#place` directive | 0.2.027 | `#overlay` |
| `#must` directive | 0.2.022 | No replacement (return value checking removed) |
| `cast.*(T)` infix cast | 0.2.022 | `cast(T) expr` |
| `cast(T).*` infix cast | 0.2.022 | `cast(T) expr` |
| `%%` as literal % in print | 0.2.022 | Use `\%` instead |
| `#v2` for-loop directive | 0.2.019 | Remove (transition aid, no longer needed) |
| enum `.loose` member | 0.2.022 | Use metaprogramming |
| `Code_Directive_Place` | 0.2.027 | Removed from `modules/Compiler/Compiler.jai` |
| `__temporary_allocator` (Basic) | 0.2.029 | Use `temporary_allocator` or `temp` |

### Deprecated Features
| Feature | Deprecated In | Will Be Removed | Replacement |
|---------|---------------|-----------------|-------------|
| Unary `<<` prefix deref | 0.2.022 | Future | `(.*)`  or postfix `.*` |
| `[]` on pointer types | 0.2.022 | Future | Dereference pointer first |
| `-release` CLI flag | 0.2.026 | Future | `-o` or `-optimized` |
| `-release_debug` CLI flag | 0.2.026 | Future | `-od` or `-optimized_debug` |
| `#system_library` | 0.2.019 | Future | `#library,system` |
| `#foreign_library` | ~0.2.015 | Removed 0.2.025 | `#library` |
| `#foreign_system_library` | ~0.2.015 | Removed 0.2.025 | `#library,system` |
| `modules/File_Async` | 0.2.025 | Removed 0.2.026 | Copy from older beta if needed |
| `Hash_Table.init()` | 0.2.029 | Future | Not needed; use `table_resize()` for explicit sizing |

### New Features (by version)
| Feature | Added In | Notes |
|---------|----------|-------|
| `void` as zero `Type` value | 0.2.029 | Uninitialized `Type` holds `void`; `void` is `false` in if; index 0 in type tables |
| Struct literals assign to tagged unions | 0.2.029 | `t = .{ .TAG, field = val };` |
| `Hash_Table.table_reset_keeping_memory()` | 0.2.029 | Old `table_reset()` behavior (clear count, keep memory) |
| `Hash_Table.table_resize()` | 0.2.029 | Explicit table size pre-allocation |
| `array_find/add_if_unique/unordered_remove_by_value` optional `compare()` | 0.2.029 | Compile-time baked comparator arg |
| Non-dot struct literals `{3, 4}` | 0.2.022 | Instead of `.{3, 4}` |
| Tagged unions `union tag: T {}` | 0.2.023 | Tag must be integer or Type |
| Tagged union bindings `.VAL ,, field` | 0.2.025 | Experimental, syntax may change |
| `#overlay` directive | 0.2.020 | Replaces `#place` |
| Trailing comma in proc params | 0.2.025 | `foo(a, b, c,)` |
| `$T/.[types]` type restrictions | 0.2.014 | Array form: `$T/.[string, u8]` |
| `#no_alias` proc modifier | 0.2.025 | No pointer aliasing |
| Function-call cast `cast(T, expr)` | 0.2.005 | Community chosen (75%), coexists with prefix form |
| `#bytes` standalone directive | pre-0.2.025 | Raw machine code bytes, not limited to `#asm` |
| Bare `remove;` statement | pre-0.2.025 | Removes current iterator (implicit `it`) |
| print() tagged union display | 0.2.026 | Prints as `{TAG, value}`, cross-refs correct field |

### Breaking Changes (behavior changes without syntax change)
| Change | Version | Old Behavior | New Behavior |
|--------|---------|--------------|--------------|
| `Hash_Table.table_reset()` | 0.2.029 | Reset count, keep allocated memory | Free memory + reset (like `array_reset`) |

## Tree-Sitter Grammar Issues (tracked for parser development)
<!-- verified: beta 0.2.028 -->

### Category A: Action overflow / state explosion (cannot add without fundamental restructuring)
| Issue | Description | Impact | Actions |
|-------|-------------|--------|---------|
| Anonymous struct/union in type | `Blentity(struct {...})` — inline anonymous struct/union in type positions | 65+ files first error, ~196 uses | State explosion |
| `#overlay` struct directive | `#overlay (field) alias: Type;` — field memory aliasing | 13 files | 67,759 actions |
| `#align N` field suffix | `data: [64] u8 #align 16;` — alignment after field type | 5 files first error, 241 uses | 78,465 actions |
| `<<` prefix dereference | `<<ptr` — deprecated unary prefix deref | ~50 actual uses | 78,534 actions |

### Category B: Grammar changes needed (implementable)
| Issue | Description | Impact | Difficulty |
|-------|-------------|--------|------------|
| Bare anonymous struct/union member | `struct { ... }` or `union { ... }` without field name (C bindings) | 65+ files, 196 uses | Medium — new `_struct_member` alternative |
| Backslash identifiers | `name\_part` and `name\      _part` — `\` + optional whitespace as visual break | 33 files, 136 uses | Medium — external scanner change |
| parameterized_type ambiguity | `cast(Type) (expr)` — `(expr)` misparses as parameterized_type | 55+ files systemic | Hard — GLR `[$._expression, $._type]` conflict |
| Function-call cast | `cast(Type, expr)` and `cast,mod(Type, expr)` — comma-expr form | 144 uses total | Easy — extend cast_expression |
| `#elsewhere` forms | 4 syntax forms: bare, with lib, with lib+name, procedures | ~30 files | Already partially in grammar |
| Dotted struct literal fields | `field.subfield = val` in `.{ ... }` | ~40 uses (Android manifest) | Medium |
| `\d` escape broken | Grammar regex `/\\d[0-9]{1,3}/` — tree-sitter interprets `\d` as digit class | 4 files | Easy — regex fix |
| Bare `remove;` | Grammar requires `remove <expr>;` | 1 module + 3 example uses | Easy |
| `#bytes` directive | Not in grammar as standalone statement | 6 uses across 3 files | Easy |
| Mixed decl/assign capture | `success:, var = func();` — `name:,` and `name=,` modifiers | ~37 uses across ~37 files | Medium — declaration rule change |
| `$T/.[types]` constraint | `$T/.[s64, s32, s16, s8]` — array literal type restriction | 2 uses (Math, String) | Medium — conflicts with spread |
| `operator-` as value | `operator- :: Basic.operator-;` — operator name as expression | 1 use (Thread) | Medium — grammar restructuring |
| `Code.type` member access | `T :: c.type;` where c is constant Code parameter | examples/code_type.jai | Easy |
| `_, var = discard-assign` | `_, var = func()` — underscore in multi-assignment LHS | 2 uses | Easy — extend assignment rule |
| if-case bitwise AND | `if expr & N == { case }` — `&` lower precedence than `==` | 2 uses | Semantic (not grammar issue) |
| Non-dot struct literal | `return { expr, expr };` — struct literal without `.` prefix | 1 use | Hard — ambiguous with block |
| `#entry_point` modifier | `proc :: () #entry_point;` — internal procedure modifier | 1 use (Runtime_Support) | Easy |
| `for *=EXPR` modifier | `for *=DO_POINTER <=REVERSE array` — pointer modifier | 2 uses | Easy — extend for modifiers |
