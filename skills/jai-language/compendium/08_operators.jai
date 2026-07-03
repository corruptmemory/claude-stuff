// Compendium: Operators & Casts
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Proves (cheatsheet): ## Operator Overloading, ## Operators
// Sources: how_to/093_operator_overloading.jai, how_to/094_array_operators.jai,
//   how_to/010_calling_procedures.jai
// Use-cases: binary + unary operator overloading, index operators ([] []= *[]),
//   named-import operator re-export, cast modifiers (trunc/no_check), autocast (xx),
//   precedence, prefix dereference, and the built-in operator set + compound assignment.

#import "Basic";
Math :: #import "Math";   // qualified import — its operators are NOT in local scope until re-exported

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

// Unary operator overload: operator ! makes a struct testable for "emptiness".
Flag :: struct { level: int; }
operator ! :: (f: Flag) -> bool {
    return f.level == 0;    // a zero-level Flag is "false"
}

// Index get / set overloads. operator [] returns a value (read path);
// operator []= writes (a *pointer* first arg, so it can mutate). Both wrap the
// index, so an arbitrarily large subscript is legal. NOTE: in beta 0.2.030 the
// compound forms (r[i] += x) route through []= ONLY (they do not read via [] here),
// so we exercise []/[]= as plain get/set and show compound assignment via *[] below.
Ring :: struct { data: [4] int; }
operator []  :: (r: Ring, index: int) -> int          { return r.data[index % 4]; }
operator []= :: (r: *Ring, index: int, value: int)    { r.data[index % 4] = value; }

// Pointer-index overload: operator *[] returns the ADDRESS of an element. This one
// operator enables reads, the address-of-subscript form (*s[i]), AND compound
// assignment — the how_to/094-recommended path when a real element pointer exists.
Slots :: struct { values: [4] int; }
operator *[] :: (s: *Slots, index: int) -> *int       { return *s.values[index % 4]; }

// Named-import re-export: pull an operator out of a qualified-imported module by
// value, into local scope, so overload resolution can find it. Math's operator - is
// an overload set (Vector2/Vector3/matrices/...); re-exporting brings the whole set.
operator - :: Math.operator-;

main :: () {
    a := Vec2.{1.0, 2.0};
    b := Vec2.{3.0, 4.0};

    // Overloaded operators
    c := a + b;
    print("a + b = (%, %)\n", c.x, c.y);
    assert(c.x == 4.0 && c.y == 6.0);

    eq := a == b;
    print("a == b: %\n", eq);
    assert(eq == false);
    assert((a == Vec2.{1.0, 2.0}) == true);

    // #symmetric: both orderings work
    d := a * 2.0;
    e := 3.0 * a;
    print("a * 2 = (%, %)\n", d.x, d.y);
    print("3 * a = (%, %)\n", e.x, e.y);
    assert(d.x == 2.0 && d.y == 4.0);
    assert(e.x == 3.0 && e.y == 6.0);

    // Unary operator overload (operator !)
    assert(!Flag.{0} == true);      // level 0 -> "false" -> ! is true
    assert(!Flag.{5} == false);
    print("!Flag.{0} = %, !Flag.{5} = %\n", !Flag.{0}, !Flag.{5});

    // Index get/set overloads ([] and []=)
    r: Ring;
    for 0..3  r[it] = it * 10;       // operator []= (auto-addresses r)
    assert(r[0] == 0 && r[3] == 30); // operator [] reads
    assert(r[6] == 20);              // read wraps: 6 % 4 == 2
    r[9] = 99;                       // write wraps: 9 % 4 == 1
    assert(r[1] == 99);
    print("r[0]=%, r[3]=%, r[6]=%, r[1]=%\n", r[0], r[3], r[6], r[1]);

    // Pointer-index overload (*[]) — read, address-of-subscript, and compound assign
    s: Slots;
    for 0..3  s.values[it] = it * 2; // 0, 2, 4, 6
    assert(s[1] == 2);               // operator *[] read (auto-dereferences)
    p := *s[2];                      // *[] enables address-of a subscript -> *int
    p.* = 40;
    assert(s.values[2] == 40);
    s[2] *= 3;                       // *[] enables compound assignment (real pointer)
    assert(s.values[2] == 120);
    print("s[1]=%, s[2]=%\n", s[1], s[2]);

    // Named-import re-export: Math.operator- resolved into local scope by value
    diff := Math.Vector2.{5, 7} - Math.Vector2.{2, 3};
    assert(diff.x == 3 && diff.y == 4);
    print("re-exported (-): diff = (%, %)\n", diff.x, diff.y);

    // Cast modifiers
    in_range : int = 200;
    checked := cast(u8) in_range;       // plain CHECKED cast, in range -> 200 (no trap)
    assert(checked == 200);

    big : int = 300;
    // A plain `cast(u8) big` here WOULD TRAP at runtime (300 > u8 max 255): a checked
    // cast aborts on overflow, so it cannot appear in a file that must run clean.
    trunc  := cast,trunc(u8)    big;    // truncating cast: low 8 bits -> 300 & 0xff
    no_chk := cast,no_check(u8) big;    // no overflow check: same low 8 bits here
    assert(trunc  == 44);               // 300 & 0xff == 44
    assert(no_chk == 44);
    print("cast(u8) 200 = %, trunc(300) = %, no_check(300) = %\n", checked, trunc, no_chk);

    // Autocast (xx)
    val : u8 = 42;
    widened : int = xx val;
    print("xx u8 = %\n", widened);
    assert(widened == 42);

    // Pointer operations
    x := 10;
    ptr := *x;           // address-of
    deref := ptr.*;      // dereference
    print("*x = %, ptr.* = %\n", ptr, deref);
    assert(deref == 10);
    ptr.* = 25;          // write through the pointer
    assert(x == 25);

    // Prefix dereference: (.*) is a standalone prefix operator
    // Syntax: (.*) expr — dereferences pointer expression
    // NOTE: (.*) must be written as a standalone token before the expression
    //   (.*) cast(*Vec2) ptr_expr   — typical use in cast contexts
    // This is handled by our grammar but is rare in practice

    // ---- Built-in operators (the plain, non-overloaded set) ----

    // Arithmetic / modulo
    assert(17 % 5 == 2);                        // modulo

    // Bitwise: AND, OR, XOR, complement, shifts
    assert((0b1100 & 0b1010) == 0b1000);        // bitwise AND
    assert((0b1100 | 0b1010) == 0b1110);        // bitwise OR
    assert((0b1100 ^ 0b1010) == 0b0110);        // bitwise XOR
    mask : u8 = 0b0000_1111;
    assert(~mask == 0b1111_0000);               // bitwise complement (~)
    assert((1 << 4) == 16);                     // left shift
    assert((256 >> 2) == 64);                   // right shift

    // Logical: AND, OR, NOT (short-circuiting on bool)
    assert((true && false) == false);           // logical AND
    assert((false || true) == true);            // logical OR
    assert(!false == true);                     // logical NOT

    // Compound-assignment family (op-and-store)
    n := 20;
    n -= 5;   assert(n == 15);                  // -=
    n /= 3;   assert(n == 5);                   // /=
    n %= 3;   assert(n == 2);                   // %=
    n *= 6;   assert(n == 12);                  // *=
    n += 4;   assert(n == 16);                  // +=

    bits := 0b1111;
    bits &= 0b1010; assert(bits == 0b1010);     // &=
    bits |= 0b0100; assert(bits == 0b1110);     // |=
    bits ^= 0b0011; assert(bits == 0b1101);     // ^=

    sh := 1;
    sh <<= 5; assert(sh == 32);                 // <<=
    sh >>= 2; assert(sh == 8);                  // >>=

    print("PASS: 08_operators — overloads (+ == * ! [] []= *[], - re-export), casts (trunc/no_check/xx), pointers, and built-in operators (mod & | ^ ~ << >> && || ! and the compound-assign family) all verified.\n");
}
