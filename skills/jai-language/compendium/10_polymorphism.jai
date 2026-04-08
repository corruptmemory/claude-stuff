// Compendium: Polymorphism & Generics
// Jai Version: beta 0.2.027
// Platform: Linux x86-64
// Sources: how_to/100_polymorphic_procedures.jai, how_to/120_polymorphic_structs.jai,
//          how_to/170_modify.jai, how_to/160_type_restrictions.jai
// Use-cases: $T, $T/constraint, $$, #modify, polymorphic structs,
//   #bake_arguments, #bake_constants, type_of, is_constant

#import "Basic";

// Basic polymorphic procedure
identity :: (x: $T) -> T { return x; }

// Multiple type params
pair_print :: (a: $A, b: $B) {
    print("pair: (%, %)\n", a, b);
}

// Type restriction: $T/Base constrains T to subtype of Base
// NOTE: requires #as using (not just using) for subtype matching
Base :: struct { id: int; }
Child :: struct { #as using base: Base; name: string; }

greet_entity :: (e: $T/Base) {
    print("entity id: %\n", e.id);
}

// Auto-bake parameter ($$): auto-specializes when called with constants
fast_mul :: (x: int, $$y: int) -> int {
    return x * y;
}

// #modify block on procedure
coerce :: (val: $T) -> T
#modify {
    // Coerce float64 -> float32
    if T == float64 { T = float; return true; }
    return true;
}
{
    return val;
}

// Polymorphic struct
Stack :: struct (T: Type) {
    data: [..] T;
    count: int;
}

// Polymorphic struct with default parameter
Buffer :: struct (T: Type, N: int = 64) {
    storage: [N] T;
    len: int;
}

// Polymorphic struct with #modify
Wrapper :: struct (T: Type)
#modify {
    if T == void { T = int; return true; }
    return true;
}
{
    value: T;
}

stack_push :: (s: *Stack($T), val: T) {
    array_add(*s.data, val);
    s.count += 1;
}

stack_peek :: (s: *Stack($T)) -> T {
    assert(s.count > 0);
    return s.data[s.count - 1];
}

main :: () {
    // Basic polymorphism
    print("identity(42) = %\n", identity(42));
    print("identity(\"hi\") = %\n", identity("hi"));

    // Multiple type params
    pair_print(42, "hello");

    // Type restriction
    c := Child.{base = .{id = 1}, name = "Test"};
    greet_entity(c);

    // Auto-bake
    print("fast_mul(7, 6) = %\n", fast_mul(7, 6));

    // Polymorphic struct
    s: Stack(int);
    stack_push(*s, 10);
    stack_push(*s, 20);
    print("stack top = %\n", stack_peek(*s));

    // With defaults
    buf: Buffer(float);  // N defaults to 64
    buf.storage[0] = 3.14;
    buf.len = 1;
    print("buf[0] = %\n", buf.storage[0]);

    // type_of
    x := 42;
    print("type_of(x) = %\n", type_of(x));

    // is_constant
    CONST_VAL :: 10;
    #if is_constant(CONST_VAL) {
        print("CONST_VAL is constant\n");
    }
}
