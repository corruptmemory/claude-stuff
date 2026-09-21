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
// THE OWNERSHIP HALF, added 2026-09-22 after it caused a real bug: the difference
// between the two types is not only the count/capacity, it is WHO OWNS THE MEMORY.
//
//   [] T   -> Array_View_64   { count, data }                         a VIEW: owns nothing
//   [..] T -> Resizable_Array { count, data, allocated, ALLOCATOR }   OWNS: remembers where
//
// The standard library draws the same line a second time, in two overloads:
//
//   array_free :: inline (array: [] $T)  { free(array.data); }                   <- view
//   array_free :: (array: [..] $T)       { free(array.data,, array.allocator); } <- owner
//
// So a struct field that is OWNED and FREED, and whose struct can cross scopes, must be
// `[..]`. Declaring it `[]` is a TYPE-LEVEL LIE the compiler cannot catch — both types
// index and iterate identically — and it silently routes the free into the view overload,
// which uses whatever `context.allocator` is current AT THE FREE SITE rather than the one
// that allocated. That forecloses `,,` on the whole path: allocate with `,, temp`, free
// under the default context, and a temp pointer goes to the heap allocator.
//
// The general rule: anything that COULD be built in one scope and freed in another has to
// carry the allocator that built it. A construct whose every lifetime is syntactically
// scoped can keep the cleanup in the scope instead; generalize when you need to. `[..]` is
// ubiquitous and escapes constantly, so it pays that freight for everyone.
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

// A counting allocator: the only way to observe WHICH allocator a free went to.
Alloc_Counts :: struct { acquires: int; frees: int; }

counting_allocator_proc :: (mode: Allocator_Mode, requested_size: s64, old_size: s64,
                            old_memory: *void, allocator_data: *void) -> *void {
    d := cast(*Alloc_Counts) allocator_data;
    if #complete mode == {
      case .ALLOCATE;  d.acquires += 1;  return alloc(requested_size ,, context.default_allocator);
      case .RESIZE;
        // array_resize on a [..] grows through RESIZE, not ALLOCATE -- a counter that
        // watched only ALLOCATE would read zero and look like the allocator never ran.
        d.acquires += 1;
        return realloc(old_memory, requested_size, old_size ,, context.default_allocator);
      case .FREE;      d.frees += 1;  free(old_memory ,, context.default_allocator);  return null;
      case .STARTUP;      #through;
      case .SHUTDOWN;     #through;
      case .THREAD_START; #through;
      case .THREAD_STOP;  #through;
      case .CREATE_HEAP;  #through;
      case .DESTROY_HEAP; #through;
      case .IS_THIS_YOURS; #through;
      case .CAPS;
        return null;
    }
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

    // ── OWNERSHIP: a [..] REMEMBERS its allocator; a [] cannot ──────────────────
    // Proven with a counting allocator, because the claim is about WHICH allocator runs,
    // and that is invisible from the outside otherwise.
    counts: Alloc_Counts;
    counting := Allocator.{ counting_allocator_proc, *counts };

    owned: [..] u8;
    {
        c := context;
        c.allocator = counting;
        push_context c {
            array_resize(*owned, 64);   // grows via RESIZE, not ALLOCATE
        }
    }
    assert(counts.acquires == 1,                              "the counting allocator produced it");
    assert(owned.allocator.proc == counting_allocator_proc,   "the [..] RECORDS its allocator");

    // Freed from the ORDINARY context: the ambient allocator is not the counting one.
    assert(counts.frees == 0);
    array_free(owned);                                        // picks the [..] overload
    assert(counts.frees == 1, "array_free used the ARRAY's allocator, not the context's");

    // And the lie: assigning the [..] to a [] drops the allocator on the floor. A []
    // has nowhere to keep it, which is exactly why an owned buffer must not be one.
    keeper: [..] u8;
    array_resize(*keeper, 8);
    lost: [] u8 = keeper;
    assert(lost.count == keeper.count && lost.data == keeper.data, "the view sees the bytes");
    assert(size_of(type_of(lost)) < size_of(type_of(keeper)),
           "a [] is SMALLER than a [..] -- the missing bytes are allocated+allocator");
    array_free(keeper);

    print("PASS: array-to-slice ([N]T and [..]T convert by value; *[..]T converts by\n");
    print("  OWNERSHIP: a [..] records its allocator and array_free uses it; a [] cannot,\n");
    print("  so an owned buffer typed [] frees through the ambient allocator instead.\n");
    print("  pointer so slice-taking mutators like pop() accept a dynamic array; *[N]T\n");
    print("  does not, because a fixed array has no count field to point at)\n");
}
