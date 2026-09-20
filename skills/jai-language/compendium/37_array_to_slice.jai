// Compendium: fixed / dynamic / slice — which converts to which
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: empirically established against the beta 0.2.030 compiler (2026-09-20),
//   after a real misreading: a proc signature said `*[] $T` and was taken to mean
//   "this cannot accept a dynamic array". It can.
// Proves (cheatsheet): Compound Types > array-to-slice conversion
// Use-cases: passing an array to a proc that takes a slice, and the one shape that
//   does NOT work.
//
// THE RULE: a slice `[] T` is a (count, data) view, and Jai will build one for you
// implicitly — BY VALUE from either array kind, and BY POINTER only from a dynamic
// array. The asymmetry is the surprise:
//
//   [N] T   -> [] T     by value    YES
//   [..] T  -> [] T     by value    YES
//   *[..] T -> *[] T    by pointer  YES   <- so slice-taking MUTATORS accept a [..]
//   *[N] T  -> *[] T    by pointer  NO    "Error: Type mismatch. Type wanted: *[] s64;
//                                          type given: *[3] s64."
//
// Why `*[..] T -> *[] T` works and `*[N] T -> *[] T` does not: a dynamic array BEGINS
// with the same (count, data) pair a slice has — it just carries an allocator and a
// capacity after them — so a pointer to it is already a valid pointer to a slice. A
// fixed array is bare storage with no count field at all, so there is nothing for a
// *[] T to point AT; the count exists only in the type.
//
// THE PRACTICAL CONSEQUENCE, which is what made this worth recording: reading
//     pop :: (array: *[] $T) -> T           (modules/Basic/Array.jai:232)
// and concluding "pop does not work on a [..]" is WRONG. It does. `pop(*my_dynamic)`
// compiles and removes the last element. Do not hand-roll a pop to work around a
// constraint that is not there. (There are good reasons to hand-roll one — e.g. freeing
// memory each element owns at the point of removal — but the signature is not one.)

#import "Basic";

sum_slice :: (s: [] int) -> int {
    total := 0;
    for s  total += it;
    return total;
}

main :: () {
    // A FIXED array converts to a slice by value.
    fixed := int.[1, 2, 3, 4];
    assert(sum_slice(fixed) == 10, "[N]T passes to a []T parameter by value");

    named_slice: [] int = fixed;
    assert(named_slice.count == 4, "and binds to a []T variable");

    // A DYNAMIC array converts by value too.
    dyn: [..] int;
    defer array_free(dyn);
    array_add(*dyn, 5);
    array_add(*dyn, 6);
    array_add(*dyn, 7);
    assert(sum_slice(dyn) == 18, "[..]T passes to a []T parameter by value");

    // And BY POINTER -- which is the half that gets misread. Basic's `pop` takes
    // `*[] $T`, and this is a dynamic array, and it works.
    last := pop(*dyn);
    assert(last == 7,      "pop(*dynamic_array) returns the last element ...");
    assert(dyn.count == 2, "... and shortens the array");

    // WILL NOT COMPILE -- a fixed array has no count field to point at:
    //     pop(*fixed);
    //  -> Error: Type mismatch. Type wanted: *[] s64; type given: *[3] s64.

    // A slice of a slice is still just a view; nothing is copied.
    view: [] int = dyn;
    assert(view.count == 2 && view.data == dyn.data, "a []T view shares the storage");

    print("PASS: array-to-slice ([N]T and [..]T convert by value; *[..]T converts by\n");
    print("  pointer so slice-taking mutators like pop() accept a dynamic array; *[N]T\n");
    print("  does not, because a fixed array has no count field to point at)\n");
}
