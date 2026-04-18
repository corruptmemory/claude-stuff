// Compendium: Operators & Casts
// Jai Version: beta 0.2.028
// Platform: Linux x86-64
// Sources: how_to/010_calling_procedures.jai
// Use-cases: operator overloading, cast modifiers, autocast (xx),
//   precedence, prefix dereference

#import "Basic";

Vec2 :: struct {
    x: float;
    y: float;
}

// Operator overloading
operator + :: (a: Vec2, b: Vec2) -> Vec2 {
    return .{a.x + b.x, a.y + b.y};
}

operator == :: (a: Vec2, b: Vec2) -> bool {
    return a.x == b.x && a.y == b.y;
}

// Operator with #symmetric (only need one definition for both orderings)
operator * :: (v: Vec2, s: float) -> Vec2 #symmetric {
    return .{v.x * s, v.y * s};
}

main :: () {
    a := Vec2.{1.0, 2.0};
    b := Vec2.{3.0, 4.0};

    // Overloaded operators
    c := a + b;
    print("a + b = (%, %)\n", c.x, c.y);

    eq := a == b;
    print("a == b: %\n", eq);

    // #symmetric: both orderings work
    d := a * 2.0;
    e := 3.0 * a;
    print("a * 2 = (%, %)\n", d.x, d.y);
    print("3 * a = (%, %)\n", e.x, e.y);

    // Cast modifiers
    big : int = 300;
    small := cast(u8) big;              // basic cast (may warn on overflow)
    no_chk := cast,no_check(u8) big;    // no overflow check
    trunc  := cast,trunc(u8) big;       // truncating cast
    print("cast(u8) 300 = %, no_check = %, trunc = %\n", small, no_chk, trunc);

    // Autocast (xx)
    val : u8 = 42;
    widened : int = xx val;
    print("xx u8 = %\n", widened);

    // Pointer operations
    x := 10;
    ptr := *x;           // address-of
    deref := ptr.*;      // dereference
    print("*x = %, ptr.* = %\n", ptr, deref);

    // Prefix dereference: (.*) is a standalone prefix operator
    // Syntax: (.*) expr — dereferences pointer expression
    // NOTE: (.*) must be written as a standalone token before the expression
    //   (.*) cast(*Vec2) ptr_expr   — typical use in cast contexts
    // This is handled by our grammar but is rare in practice
}
