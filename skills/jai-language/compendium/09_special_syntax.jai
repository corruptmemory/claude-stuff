// Compendium: Special Syntax
// Jai Version: beta 0.2.029
// Platform: Linux x86-64
// Sources: how_to/014_enum_unary_dot.jai, how_to/019_looping.jai
// Use-cases: unary dot, spread, comma-comma, backtick, notes,
//   using modifiers, defer, push_context, ifx

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

main :: () {
    // Unary dot (type-inferred enum value)
    c : Color = .RED;
    print("color = %\n", c);

    // Spread (unpack array into variadic)
    values := int.[1, 2, 3];
    printer(..values);

    // Comma-comma (extra arguments after ,, go to allocator/context)
    // In practice used with allocator override, here just showing syntax
    arr : [..] int;
    arr.allocator = context.allocator;
    array_add(*arr, 42);
    print("arr = %\n", arr);

    // Ifx expression
    x := 10;
    result := ifx x > 5 then "big" else "small";
    print("ifx: %\n", result);

    // Ifx without 'then'
    result2 := ifx x > 5  "big";
    print("ifx no-then: %\n", result2);

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

    // Using modifier examples (shown via struct for context)
    Inner :: struct { a: int; b: int; c: int; }
    Outer :: struct {
        using,except(c) inner: Inner;    // exclude c from promotion
    }
    o := Outer.{inner = .{a = 1, b = 2, c = 3}};
    print("outer.a = %, outer.b = %\n", o.a, o.b);
    // o.c would be an error — excluded by using,except

    // Notes used on procedures (annotations for metaprogramming)
    deprecated_func();
    tagged_func();
}
