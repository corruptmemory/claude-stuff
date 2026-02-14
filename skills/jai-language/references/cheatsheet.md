# Jai Language Cheat Sheet

> **Jai Version**: beta 0.2.025 (19 January 2026)
> **Platform**: Linux x86-64
> **All entries verified against**: `~/jai/jai/` distribution (how_to/, modules/, examples/)
> **Last updated**: 2026-02-13

## Declarations
<!-- verified: beta 0.2.025 -->

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
```

## Procedures
<!-- verified: beta 0.2.025 -->

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

// NOTE: #must does NOT exist in beta 0.2.025

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
name :: () #intrinsic;                            // compiler intrinsic

// #modify block (returns true to accept, false+"msg" to reject)
sum :: (a: [] $T) -> T #modify { if T == float64  T = float; return true; } { }

// Foreign
GetLastError :: () -> u32 #foreign kernel32;
other_fn :: () #foreign;                              // foreign without library

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
<!-- verified: beta 0.2.025 -->

```jai
operator + :: (a: Vec2, b: Vec2) -> Vec2 { }
operator == :: (a: Vec2, b: Vec2) -> bool { }
operator [] :: (arr: *MyArray, index: int) -> *T { }
operator []= :: (arr: *MyArray, index: int, value: T) { }
operator *[] :: (arr: *MyArray, index: int) -> *T { }  // pointer-index
operator ! :: (a: S128) -> bool { }     // logical NOT overload
// Also: -, *, /, %, !=, <, <=, >, >=, &&, ||, !, +=, -=, *=, /=, &&=, ||=, etc.

// Operator as value reference (importing from module)
// Source: modules/Thread/module.jai
Basic :: #import "Basic";
operator- :: Basic.operator-;          // import operator from another module
```

## Types
<!-- verified: beta 0.2.025 -->

### Primitives
- `int` (s64), `u8` `u16` `u32` `u64`, `s8` `s16` `s32` `s64`
- `float` (float32), `float32`, `float64`
- `bool`, `string`, `void`, `#Context`

### Compound Types
```jai
*Type                          // pointer (dereference: ptr.*)
[N] Type                       // fixed array
[..] Type                      // dynamic array
[] Type                        // slice/array view
#type (params) -> ReturnType   // explicit procedure type
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

## Structs
<!-- verified: beta 0.2.025 -->

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

// Memory layout
Layout :: struct {
    #place x;                       // explicit field placement
    x: float;
    y: float;
}

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
// Source: modules/File_Async/module.jai, modules/Pool.jai
Options :: struct {
    code: enum { NONE; SUCCESS; };           // anonymous enum
    flags: enum_flags u32 {                  // anonymous enum_flags with :: values
        READ   :: 0x1;
        WRITE  :: 0x2;
    };
    inner: struct { x: int; y: int; };       // anonymous struct
    value: union { as_int: int; as_f: float64; };  // anonymous union
}

// Field override (in extended struct)
Extended :: struct {
    using base: Base;
    base.flavor = .CHOCOLATE;       // override base field default
}
```

## Struct/Array Literals
<!-- verified: beta 0.2.025 -->

```jai
Type.{field = value, field2 = value2}    // named fields
.{field = value}                          // type-inferred
Type.{val1, val2, val3}                  // positional
Type.{field[0] = val, field[1] = val2}   // indexed field initializer
.[1, 2, 3]                               // array literal (type-inferred)
Type.[1, 2, 3]                           // typed array literal
```

## Enums
<!-- verified: beta 0.2.025 -->

```jai
Direction :: enum { NORTH; SOUTH; EAST; WEST; }
Color :: enum u8 { RED; GREEN :: 5; BLUE; }       // backing type + explicit values
Flags :: enum_flags u32 { READ; WRITE; EXEC; }    // bitflag enum
Strict :: enum #specified { A :: 1; B :: 2; }      // all values must be explicit
Exhaustive :: enum #complete { A; B; C; }          // switches must be exhaustive

// Using enum (anonymous, promotes values to scope)
using enum u16 { NONE; SOME :: 5; ALL; }
```

## Control Flow
<!-- verified: beta 0.2.025 -->

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
remove it;                              // remove during iteration
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
<!-- verified: beta 0.2.025 -->
```jai
// #no_abc and #no_aoc can appear BETWEEN iterable and body in for loops
// Source: modules/Hash.jai
for 0..size-1 #no_abc #no_aoc {        // no array bounds check, no auto output capture
    h = (h << 5) + h + data[it];
}
```

### Other
```jai
defer stmt;                             // deferred execution
defer { block; }                        // deferred block
push_context new_ctx { ... }           // context switch scope
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
<!-- verified: beta 0.2.025 -->

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
#foreign_import "lib";
#foreign_import,system "kernel32";
#foreign_import,header "header.h";
```

### Compile-Time Execution
```jai
#run expr;                              // compile-time execution
#run { block; }
#run,stallable expr;                    // run with modifier
#if cond { ... } else { ... }          // static conditional
#if cond  stmt;                         // static if with bare body
#if cond  #load "a.jai"; else  #load "b.jai";  // braceless static if/else
#if value == {                          // static if case form
    case .A;  handle_a();
    case .B;  handle_b();
} else #if other_val == { ... }        // else chain
#assert(cond);                          // parenthesized form
#assert cond;                           // bare form
#assert cond "message";                 // with message (NO comma, space-separated)
#insert expr;                           // code insertion
#insert,scope() expr;                  // with scope
#insert(break=break outer) expr;       // with break parameter mapping
#insert(remove=#assert(false)) expr;   // with remove parameter
#insert(break=break slot, remove={stmt; stmt;}) expr;  // combined break + remove
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
#string,noslash DELIM                   // no escape processing
raw content
DELIM
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
#type,distinct Type                    // distinct type variant
#type,isa Type                         // subtype variant
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
```

### Inline Assembly
```jai
#asm { ... }                           // inline assembly (opaque body)
#asm AVX, AVX2 { ... }                // with ISA feature flags
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
#add_context #as using base: Context_Base;  // with #as and using
#library,system "kernel32"             // system library
#library,no_dll "lib"                  // static library
#library,system,no_dll "lib"           // multiple library modifiers
#library,system,link_always "lib"      // always link this library
#foreign lib_handle                    // foreign function from library
#program_export                        // export procedure to executable
#program_export "entry"                // export with custom name
#file                                  // current file path (alias for #filepath)
#filepath                              // current file path
```

## Operators
<!-- verified: beta 0.2.025 -->

### Precedence (high to low)

| Prec | Operators | Description |
|------|-----------|-------------|
| 17 | `.field` | Field access |
| 16 | `f(args)` | Call |
| 15 | `a[i]`, `p.*`, `(.*) expr`, `<<ptr` | Index, dereference, prefix dereference |
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
<!-- verified: beta 0.2.025 -->
```jai
x <<< n                               // rotate left (same precedence as <<)
x >>> n                                // rotate right (same precedence as >>)
// Source: modules/md5.jai, modules/xxHash/module.jai
```

### Prefix Dereference (`<<`)
<!-- verified: beta 0.2.025 -->
```jai
<<ptr                                  // prefix dereference (equivalent to ptr.*)
<<filename_pointer                     // common in pointer-heavy code
// Source: modules/Bindings_Generator/restart.jai
```

### Cast
```jai
cast(float) x                         // explicit cast
cast,no_check(u8) x                   // no overflow check
cast,trunc(u8) x                      // truncating cast
cast,force(U128) x                    // unsafe force cast (bypasses checks)
xx x                                   // autocast
xx,no_check x                         // autocast without check
```

## Special Syntax
<!-- verified: beta 0.2.025 -->

```jai
.ENUM_VALUE                            // unary dot (type-inferred enum)
..array                                // spread (unpack into varargs, types must match)
func(args,, allocator = temp)          // comma-comma (context override)
`name                                  // backtick (keyword as identifier)
`return false, .{};                    // backtick return (return from caller in #expand macro)
`break;                                // backtick break (break caller's loop)
left\_margin := 0.014;                 // backslash in identifiers (line-continuation/visual break)
// Source: examples/codex_view/src/draw_live_allocations.jai, modules/Basic/Apollo_Time.jai
@NoteName                              // note/attribute (before decl OR after body)
@"string note"                         // string note
// Notes go: (1) before declaration, or (2) after procedure body closing }
// @note name :: () { }     — BEFORE the declaration
// name :: () { } @note     — AFTER the body (e.g. } @RunWhenReady)
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
<!-- verified: beta 0.2.025 -->

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
| `\d123` | Decimal byte |
| `\uFFFF` | Unicode (16-bit) |
| `\UFFFFFFFF` | Unicode (32-bit) |

## Comments
<!-- verified: beta 0.2.025 -->

```jai
// Line comment
/* Block comment — nests arbitrarily: /* nested */ still inside */
```

## Context System
<!-- verified: beta 0.2.025 -->

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
