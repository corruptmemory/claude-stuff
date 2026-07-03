// Compendium: Special Syntax
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/014_enum_unary_dot.jai, how_to/019_looping.jai,
//   how_to/042_using.jai, how_to/044_using_advanced/main.jai,
//   modules/Basic/String_Builder.jai (,, allocator override)
// Use-cases: unary dot, spread, comma-comma (,,) allocator override, notes
//   (incl. @selector parenthesized form), using modifiers
//   (except(name) / except NAMES / only / map), defer, push_context, ifx

#import "Basic";

Color :: enum { RED; GREEN; BLUE; }

// Typed variadic (spread requires matching types, no implicit element conversion)
printer :: (args: .. int) {
    for args  print("  arg: %\n", it);
}

// Notes (annotations) — go BEFORE declaration or AFTER procedure body
// Position 1: before the declaration
@deprecated
deprecated_func :: () {
    print("old function\n");
}

// Position 2: after closing brace of procedure body
tagged_func :: () {
    print("tagged\n");
} @"important: review this"

// Helpers for the 'using' modifier demonstrations (below):
Quaternion :: struct { x, y, z, w: float; w = 1; }

// Referenced by `using,except SKIP_XYZ` — an identifier-reference exclusion list
// (a named string.[...] constant), NOT the parenthesized inline single-name form.
SKIP_XYZ :: string.["x", "y", "z"];

Procs :: struct { Clear: int; PushMatrix: int; }

// Compile-time name-mapper for `using,map` — prepends "gl" to each promoted name.
prefix_with_gl :: (names: [] string) {
    for * names  it.* = tprint("gl%", it.*);
}

// A struct member carrying a parenthesized @selector(...) note — parses with NO
// Objective-C context; the whole text just becomes the note string (read via type_info).
Widget :: struct {
    handler: int;  @selector(windowWillClose:)
    plain:   int;
}

main :: () {
    // Unary dot (type-inferred enum value)
    c : Color = .RED;
    print("color = %\n", c);
    assert(c == Color.RED);

    // Spread (unpack array into variadic)
    values := int.[1, 2, 3];
    printer(..values);

    // Comma-comma (,,): pass an EXTRA trailing argument (an allocator) after the
    // regular arguments. `,,` separates the normal args from the allocator arg, so
    // the call allocates from `temp` instead of context.allocator.
    // (modules/Basic/String_Builder.jai, modules/Command_Line.jai)
    sb: String_Builder;
    append(*sb, "hello");
    joined := builder_to_string(*sb,, allocator = temp);   // build the string into temp
    print("comma-comma builder_to_string = %\n", joined);
    assert(joined == "hello");

    scratch := NewArray(3, int,, temp);                    // allocate the array in temp
    scratch[2] = 7;
    print("comma-comma NewArray = %\n", scratch);
    assert(scratch.count == 3 && scratch[2] == 7);

    // Ifx expression
    x := 10;
    result := ifx x > 5 then "big" else "small";
    print("ifx: %\n", result);
    assert(result == "big");

    // Ifx without 'then'
    result2 := ifx x > 5  "big";
    print("ifx no-then: %\n", result2);
    assert(result2 == "big");

    // Defer
    {
        defer print("  deferred (last)\n");
        print("  before defer\n");
    }

    // Push_context
    new_ctx := context;
    push_context new_ctx {
        print("inside push_context\n");
    }

    // === using modifiers ===

    // using,except(name): parenthesized inline exclusion of a single name.
    Inner :: struct { a: int; b: int; c: int; }
    Outer :: struct {
        using,except(c) inner: Inner;    // exclude c from promotion
    }
    o := Outer.{inner = .{a = 1, b = 2, c = 3}};
    print("outer.a = %, outer.b = %\n", o.a, o.b);
    assert(o.a == 1 && o.b == 2);
    // o.c would be an error — excluded by using,except(c)

    // using,except NAMES: identifier-reference exclusion list (SKIP_XYZ, a named
    // string.[...] constant declared at top level) — not the parenthesized form above.
    Only_W :: struct { using,except SKIP_XYZ q: Quaternion; }   // links only w
    ow: Only_W;
    ow.w = 9;
    print("using,except NAMES -> w = %\n", ow.w);
    assert(ow.w == 9);
    // ow.x/y/z are NOT promoted (excluded via SKIP_XYZ) — reach them through ow.q.x

    // using,only(a, b): promote ONLY the listed names, ignore all the rest.
    Only_WY :: struct { using,only(w, y) q: Quaternion; }
    wy: Only_WY;
    wy.w = 2;
    wy.y = 3;
    print("using,only(w, y) -> w = %, y = %\n", wy.w, wy.y);
    assert(wy.w == 2 && wy.y == 3);
    // wy.x / wy.z are NOT promoted (not in the only-list)

    // using,map(fn): a compile-time procedure renames each promoted name.
    // prefix_with_gl prepends "gl", so Clear -> glClear, PushMatrix -> glPushMatrix.
    using,map(prefix_with_gl) procs: Procs;
    glClear      = 11;
    glPushMatrix = 22;
    print("using,map -> glClear = %, glPushMatrix = %\n", glClear, glPushMatrix);
    assert(procs.Clear == 11 && procs.PushMatrix == 22);

    // @selector(...) note form: read back the parenthesized note off a struct member
    // via type_info — proves it is captured as an ordinary note string.
    winfo := type_info(Widget);
    sel_note := "";
    for winfo.members  if it.name == "handler"  sel_note = it.notes[0];
    print("@selector note = '%'\n", sel_note);
    assert(sel_note == "selector(windowWillClose:)");

    // Notes used on procedures (annotations for metaprogramming)
    deprecated_func();
    tagged_func();

    print("PASS: unary dot, spread, comma-comma (,,) allocator override, ifx, defer, push_context, using,except(name)/except NAMES/only(...)/map(fn), @selector note\n");
}
