// Compendium: Declarations
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/010_calling_procedures.jai, how_to/020_declarations.jai
// Use-cases: variable declaration, type inference, constants, typed constants,
//   default init, uninitialized, compound declarations, discard, pointers

#import "Basic";

main :: () {
    // Variable with type inference
    x := 5;
    print("x = %\n", x);

    // Explicit type
    y : int = 10;
    print("y = %\n", y);

    // Constant (compile-time)
    PI :: 3.14159;
    print("PI = %\n", PI);

    // Typed constant
    MAX : int : 100;
    print("MAX = %\n", MAX);

    // Default-initialized (zero)
    z : int;
    print("z (default) = %\n", z);

    // Uninitialized (explicit)
    w : int = ---;
    w = 42;
    print("w (was uninitialized) = %\n", w);

    // Compound declaration
    a, b, c : float;
    a = 1.0;
    b = 2.0;
    c = 3.0;
    print("a=% b=% c=%\n", a, b, c);

    // Discard
    _ := 999;

    // Pointer
    val := 42;
    ptr := *val;
    print("ptr.* = %\n", ptr.*);
}
