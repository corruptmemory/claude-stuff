// Compendium: Argument mutability
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: empirically established against the beta 0.2.030 compiler (2026-09-20);
//   the distribution's how_to/ files do not state the rule.
// Proves (cheatsheet): Procedures > Argument mutability
// Use-cases: which parameters can be assigned to, the exact compiler errors for the
//   ones that cannot, the rename idiom for getting a mutable copy of a struct
//   parameter, and which mutations the CALLER can observe.
//
// THE RULE, in one line: scalar parameters are mutable, aggregate parameters are not.
//
//   MUTABLE (assignment compiles; the change is local, the caller never sees it):
//       int, float, bool, enum, and pointers (reseating the pointer itself)
//
//   IMMUTABLE ("Error: Can't assign to an immutable argument."):
//       structs -- INCLUDING string, which is a struct {count, data}
//       fixed arrays [N]T
//       a slice's header fields (a.count, a.data)
//
//   MUTABLE THROUGH AN INDIRECTION (and the caller DOES see these):
//       p.* for a pointer parameter, and a[i] for a slice parameter -- the pointed-to
//       storage is not the argument, so immutability does not apply to it.
//
// Two traps worth knowing:
//
//   1. `x := x` DOES NOT WORK to get a mutable copy. Unlike Odin, Jai rejects it with
//      "Error: Attempt to use a value inside its own declaration."  The mutable copy
//      needs a DIFFERENT name -- see mutable_copy_of_struct below.
//
//   2. `using` a struct parameter and assigning to a promoted field gives a different
//      error: "Error: Attempt to modify a constant declaration by 'using' of its
//      members."  Same underlying cause, different message, so don't grep for the
//      first one alone.
//
// The failing forms are recorded as comments rather than code on purpose: this corpus
// must compile clean, so it cannot contain the errors it documents.

#import "Basic";

Point :: struct { x := 1; y := 2; }

// ── Scalars are mutable, and the mutation is purely local ────────────────────────
scalar_is_mutable :: (n: int, f: float, b: bool, p: *int) -> int {
    n  = 99;        // fine
    n += 1;         // compound assignment is fine too
    f  = 2.0;
    b  = true;
    p  = null;      // reseating the POINTER is fine ...
    return n;
}

// ... but writing THROUGH a pointer reaches the caller's storage.
write_through_pointer :: (p: *int) { p.* = 99; }

// ── Structs are immutable; take a renamed local copy ─────────────────────────────
// This is the idiom for "take a config/theme by value, tweak it, use it".
mutable_copy_of_struct :: (base: Point) -> Point {
    p := base;      // the LOCAL is mutable; `base` is not, and `base := base` is illegal
    p.x = 99;
    return p;
}

// WILL NOT COMPILE -- "Can't assign to an immutable argument."
//   struct_field  :: (p: Point)    { p.x = 99; }
//   whole_struct  :: (p: Point)    { q: Point; p = q; }
//   string_param  :: (s: string)   { s = "changed"; }      // string IS a struct
//   fixed_array   :: (a: [3] int)  { a[0] = 99; }
//   slice_header  :: (a: [] int)   { a.count = 0; }
//
// WILL NOT COMPILE -- "Attempt to use a value inside its own declaration."
//   self_shadow   :: (p: Point)    { p := p; }
//
// WILL NOT COMPILE -- "Attempt to modify a constant declaration by 'using' of its members."
//   using_field   :: (using p: Point) { x = 99; }

// ── A slice's ELEMENTS are mutable, and the caller sees the change ───────────────
write_slice_element :: (a: [] int) { a[0] = 99; }

main :: () {
    // Scalars: mutable inside, invisible outside.
    caller_n := 1;
    returned := scalar_is_mutable(caller_n, 1.0, false, *caller_n);
    assert(returned == 100,  "scalar param was assignable (99 then += 1)");
    assert(caller_n == 1,    "scalar mutation is local -- the caller is untouched");

    // Pointer: reseating is local, writing through is not.
    write_through_pointer(*caller_n);
    assert(caller_n == 99,   "writing through a pointer parameter DOES reach the caller");

    // Structs: the renamed-local idiom.
    original: Point;
    tweaked := mutable_copy_of_struct(original);
    assert(tweaked.x  == 99, "the local copy was modified");
    assert(original.x == 1,  "pass-by-value -- the caller's struct is untouched");
    assert(tweaked.y  == 2,  "fields the copy did not touch survive from the base");

    // Slices: the header is immutable, the elements are not, and the caller sees it.
    backing := int.[1, 2, 3];
    view: [] int = backing;
    write_slice_element(view);
    assert(backing[0] == 99, "a slice parameter's elements reach the caller's storage");
    assert(view.count == 3,  "the slice header itself is unchanged");

    print("PASS: argument mutability (scalars/enums/pointers assignable and local;\n");
    print("  structs, string, [N]T and slice headers immutable; `x := x` illegal, so a\n");
    print("  renamed local is the copy idiom; pointer pointees and slice elements are\n");
    print("  mutable and visible to the caller)\n");
}
