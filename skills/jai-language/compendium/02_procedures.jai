// Compendium: Procedures
// Jai Version: beta 0.2.025
// Platform: Linux x86-64
// Sources: how_to/030_procedures.jai, how_to/060_polymorphism.jai
// Use-cases: basic procedures, default params, variadic, multiple returns,
//   named returns, inline, #expand, #modify, lambda, procedure types

#import "Basic";

// Basic procedure
add :: (a: int, b: int) -> int { return a + b; }

// Void return
greet :: () { print("hello\n"); }

// Default values
increment :: (x: int, by: int = 1) -> int { return x + by; }

// Inferred-type defaults
with_defaults :: (a := 0, b := 0) -> int { return a + b; }

// Multiple returns
divide :: (a: int, b: int) -> int, bool {
    if b == 0  return 0, false;
    return a / b, true;
}

// Named returns (must explicitly return values, no implicit return of named vars)
safe_divide :: (a: int, b: int) -> result: int, ok: bool {
    if b == 0  return 0, false;
    return a / b, true;
}

// Mixed named/unnamed returns
decode :: () -> string, success: bool {
    return "data", success = true;
}

// NOTE: #must does NOT exist in Jai beta 0.2.025
// Return value usage is not enforced by the compiler

// Polymorphic ($T)
identity :: (x: $T) -> T { return x; }

// Auto-bake ($$)
auto_baked :: ($$x: int) -> int { return x * 2; }

// Inline
inline_add :: inline (a: int, b: int) -> int { return a + b; }

// #expand (macro)
my_macro :: () #expand {
    `result := 42;
}

// #modify block (returns true to accept, or false+"message" to reject)
flexible :: (a: $T) -> T
#modify { if T == float64  T = float; return true; }
{ return a; }

// Lambda expressions
main :: () {
    greet();

    print("add(3,4) = %\n", add(3, 4));
    print("increment(5) = %\n", increment(5));
    print("increment(5, 3) = %\n", increment(5, 3));
    print("with_defaults(a=1) = %\n", with_defaults(a = 1));

    q, ok := divide(10, 3);
    print("divide(10,3) = %, ok=%\n", q, ok);

    r, ok2 := safe_divide(10, 0);
    print("safe_divide(10,0) = %, ok=%\n", r, ok2);

    s, suc := decode();
    print("decode() = %, success=%\n", s, suc);


    print("identity(42) = %\n", identity(42));
    print("identity(\"hello\") = %\n", identity("hello"));

    print("auto_baked(5) = %\n", auto_baked(5));

    // Lambda expressions
    square := (x: int) -> int { return x * x; };
    print("square(7) = %\n", square(7));

    // NOTE: bare lambda `x => x * 2` requires polymorphic context or typed params
    // Use full procedure literal for typed lambdas instead

    // Lambda with block body (use full procedure literal, not => with block)
    abs_val := (x: int) -> int { if x < 0 return -x; return x; };
    print("abs_val(-3) = %\n", abs_val(-3));

    // Inline call
    print("inline add = %\n", inline_add(1, 2));

    // Macro call
    my_macro();
    print("macro result = %\n", result);

    // Procedure type
    op : (int, int) -> int = add;
    print("op(10,20) = %\n", op(10, 20));
}
