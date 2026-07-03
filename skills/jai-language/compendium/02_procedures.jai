// Compendium: Procedures
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/010_calling_procedures.jai, how_to/030_procedures.jai,
//   how_to/042_using.jai, how_to/060_polymorphism.jai,
//   how_to/110_polymorphic_arguments.jai, how_to/160_type_restrictions.jai
// Use-cases: basic procedures, default params, variadic (typed ..int / ..Any),
//   multiple returns, named returns, inline, using-param, #discard param,
//   polymorph $T, $T/interface, $T/.[..] type-set, => lambda,
//   call-site inline/no_inline, #symmetric/#no_alias/#no_debug/#compile_time,
//   #expand, #modify, procedure types

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

// --- Audit extension: further procedure constructs (all proven below) ---

// 'using' parameter: the struct's fields are usable unqualified in the body
Counter :: struct { value: int; }
boost :: (using c: *Counter, amount: int) { value += amount; }  // 'value' is c.value

// #discard on a parameter: deliberately-unused parameter
discard_answer :: (#discard ignored: int) -> int { return 42; }

// ..Any variadic: mixed-type variable arguments (element type is Any)
count_any :: (args: ..Any) -> int { return args.count; }

// Typed variadic ..int: every argument must be an int
sum_ints :: (nums: ..int) -> int { total := 0; for nums total += it; return total; }

// $T/interface I: interface-constrained polymorph (structural / duck typing)
Named :: struct { name: string; id: int; }
describe_id :: (x: $T/interface Named) -> int { return x.id; }
Widget :: struct { id: int; extra: float; name: string; }  // has name+id -> matches Named

// $T/.[T1, T2]: type-set restriction (T must be one of the listed types)
inc_restricted :: (x: $T/.[s32, s64]) -> T { return x + 1; }

// => short-arrow lambda: a polymorphic "quick procedure", single expression
triple :: x => x * 3;

// Ordinary proc wrapped by call-site inline / no_inline keywords in main
plain_add :: (a: int, b: int) -> int { return a + b; }

// #symmetric: a plain 2-arg proc callable with its arguments in either order
combine :: (a: int, b: float) -> float #symmetric { return a + b; }

// #no_alias: pointer parameters are asserted not to alias (optimization hint)
add_through :: (a: *int, b: *int) -> int #no_alias { return a.* + b.*; }

// #no_debug: MACRO-ONLY modifier (compiler rejects it on non-macros); the
// expansion carries no debug line info.
bump :: () #expand #no_debug { `counter += 1; }

// #compile_time: proc callable ONLY at compile time (here through #run)
ct_square :: (n: int) -> int #compile_time { return n * n; }
CT_SQUARE_6 :: #run ct_square(6);

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

    // --- Audit extension exercises (real executed code, verified by assert) ---

    // 'using' parameter: body mutated ctr.value via the unqualified name
    ctr: Counter;
    boost(*ctr, 5);
    assert(ctr.value == 5);

    // #discard parameter
    assert(discard_answer(999) == 42);

    // ..Any variadic — count mixed-type args
    assert(count_any(1, "two", 3.0, true) == 4);

    // typed ..int variadic
    assert(sum_ints(1, 2, 3, 4) == 10);

    // $T/interface — Widget matches the Named interface by structure
    w: Widget;
    w.id   = 7;
    w.name = "gizmo";
    assert(describe_id(w) == 7);

    // $T/.[...] type-set restriction — only s32/s64 accepted
    assert(inc_restricted(cast(s32) 41) == 42);
    assert(inc_restricted(cast(s64) 99) == 100);

    // => short-arrow lambda (polymorphed by the int call)
    assert(triple(14) == 42);

    // call-site inline / no_inline keywords
    ia := inline    plain_add(1, 2);
    ib := no_inline plain_add(3, 4);
    assert(ia == 3);
    assert(ib == 7);

    // #symmetric — same result with arguments in either order
    assert(combine(2, 3.0) == 5.0);
    assert(combine(3.0, 2) == 5.0);

    // #no_alias pointer params
    na1 := 10;
    na2 := 20;
    assert(add_through(*na1, *na2) == 30);

    // #no_debug macro (backtick side effect proves it ran)
    counter := 0;
    bump();
    assert(counter == 1);

    // #compile_time proc, evaluated by #run at build time
    assert(CT_SQUARE_6 == 36);

    print("PASS: procedures (basics, defaults, typed ..int/..Any variadic, multiple/named\n");
    print("  returns, poly $T + $$ auto-bake, $T/interface, $T/.[..] type-set, using-param,\n");
    print("  #discard, => lambda, inline/no_inline call-site, #symmetric/#no_alias/#no_debug/\n");
    print("  #compile_time, #modify, #expand, procedure types)\n");
}
