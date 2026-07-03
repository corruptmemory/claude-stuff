// Compendium: Declarations
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/010_calling_procedures.jai, how_to/020_declarations.jai,
//   how_to/560_no_reset.jai + how_to/170_modify.jai (#no_reset),
//   modules/Basic/tests.jai:390 (`n=, digit := ...`),
//   modules/executable_formats/tbd/tbd.jai:21 (`success=, tbds := parse_tbd(...)`),
//   modules/Android/Toolchain/android_helper.jai:1560
//     (`found, _:, remainder = split_from_left(...)`), modules/String/module.jai
// Use-cases: variable declaration, type inference, constants, typed constants,
//   default init, uninitialized, compound declarations, discard, pointers,
//   #no_reset (a global surviving compile-time -> runtime), `name=,`
//   assign-override in a `:=`-context multi-return capture, a 3-position
//   capture combining BOTH `:,` (declare-override) AND `=,` (assign-override)
//   in one list, and `_:,` discard-declare inside an `=`-context (assign)
//   multi-return capture.

#import "Basic";
#import "String";

// ============================================================================
// #no_reset -- a global whose compile-time-computed value SURVIVES into the
// runtime executable. An ordinary global is always reset to its default
// (zero) value when the compiler writes out the executable, even if a #run
// block changed it at compile time. Source: how_to/560_no_reset.jai,
// how_to/170_modify.jai.
// ============================================================================

normal_global:   int;
#no_reset no_reset_global: int;

#run {
    normal_global   = 777;
    no_reset_global = 777;
}

demo_no_reset :: () {
    // normal_global was set to 777 at COMPILE TIME inside the #run above, but
    // ordinary globals reset to their default value in the emitted executable
    // -- so at runtime it is back to 0.
    print("normal_global (reset) = %\n", normal_global);
    assert(normal_global == 0, "expected normal_global reset to 0 at runtime, got %", normal_global);

    // no_reset_global is #no_reset, so whatever value it held at the end of
    // compile-time is exactly what it holds at runtime: 777.
    print("no_reset_global (#no_reset, retained) = %\n", no_reset_global);
    assert(no_reset_global == 777, "expected #no_reset global to retain its compile-time value 777, got %", no_reset_global);
}

// ============================================================================
// `name=,` -- ASSIGN-OVERRIDE in a `:=`-context multi-return capture. The
// list's trailing `:=` means bare names DECLARE a fresh variable at their
// position; `name=,` punches through that default and ASSIGNS an EXISTING
// variable instead. Modeled on modules/Basic/tests.jai:390
// (`n=, digit := signed_divide_with_remainder(n, .{10, 0});`) and
// modules/executable_formats/tbd/tbd.jai:21 (`success=, tbds := parse_tbd(content);`).
// ============================================================================

divmod10 :: (n: int) -> quotient: int, remainder: int {
    return n / 10, n % 10;
}

demo_assign_override_in_declare_context :: () {
    n := 12345;
    digits: [..] int;
    while n > 0 {
        // `n=,` ASSIGNS the quotient back into the OUTER `n` (so the while
        // condition actually progresses -- if this shadowed instead, the loop
        // would never terminate); `digit` is freshly DECLARED each iteration,
        // which is the list's default since it trails with `:=`.
        n=, digit := divmod10(n);
        array_add(*digits, digit);
    }
    print("digits (least-significant first) = %\n", digits);
    assert(digits.count == 5, "expected 5 digits extracted, got %", digits.count);
    assert(digits[0] == 5 && digits[1] == 4 && digits[2] == 3 && digits[3] == 2 && digits[4] == 1,
           "expected digits 5,4,3,2,1 in that order, got %", digits);
    assert(n == 0, "expected n consumed to 0 via the n=, assign-override (proves assignment, not shadowing), got %", n);
}

// ============================================================================
// A 3-position capture combining BOTH `:,` (declare-override) AND `=,`
// (assign-override) in ONE capture list, under an overall `:=` (declare)
// trailing operator. `result_a:,` is a redundant-but-legal declare (the
// list's default under `:=` anyway); `result_b=,` punches through to ASSIGN
// an existing variable; `result_c` is a bare fresh declare (the default).
// ============================================================================

compute_triplet :: () -> a: int, b: int, c: int {
    return 10, 20, 30;
}

demo_mixed_declare_and_assign_capture :: () {
    result_b := 999; // pre-existing; will be ASSIGNED via `=,`

    result_a:, result_b=, result_c := compute_triplet();

    print("result_a=% result_b=% result_c=%\n", result_a, result_b, result_c);
    assert(result_a == 10, "expected result_a declared via `:,` as 10, got %", result_a);
    assert(result_b == 20, "expected result_b assigned via `=,` as 20, got %", result_b);
    assert(result_c == 30, "expected result_c bare-declared as 30, got %", result_c);
}

// ============================================================================
// `_:,` -- discard-and-declare, used specifically inside an `=`-context
// (assign) multi-return capture. Modeled on
// modules/Android/Toolchain/android_helper.jai:1560
// (`found, _:, remainder = split_from_left(remainder, " ");`).
// ============================================================================

demo_discard_declare_in_assign_context :: () {
    found := false;
    remainder := "";

    // `found` and `remainder` ASSIGN into the pre-existing vars above (the
    // list trails with a bare `=`); `_:,` DECLARES-and-discards the middle
    // return value (the "left" half of the split) at its position.
    found, _:, remainder = split_from_left("alpha beta gamma", " ");

    print("found=% remainder=\"%\"\n", found, remainder);
    assert(found == true, "expected a space to be found");
    assert(remainder == "beta gamma", "expected remainder 'beta gamma', got '%'", remainder);
}

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

    // #no_reset global vs. an ordinary global reset at runtime
    demo_no_reset();

    // `name=,` assign-override in a `:=`-context multi-return capture
    demo_assign_override_in_declare_context();

    // 3-position capture combining `:,` (declare-override) AND `=,`
    // (assign-override) in one list
    demo_mixed_declare_and_assign_capture();

    // `_:,` discard-declare inside an `=`-context (assign) capture
    demo_discard_declare_in_assign_context();

    print("PASS: declarations (inference, constants, typed constants, default/uninitialized init, compound decls, discard, pointers), #no_reset globals, name=, assign-override, mixed :,/=, 3-position capture, and _:, discard-declare in an =-context capture all verified against beta 0.2.030.\n");
}
