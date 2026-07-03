// Compendium: Advanced Operators & Special Syntax
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: modules/md5.jai, modules/xxHash/module.jai, modules/Bindings_Generator/restart.jai,
//          modules/Thread/module.jai, modules/Hash.jai, how_to/730_for_expansions.jai
// Use-cases: rotate operators (<<<, >>>), postfix dereference (.*),
//   operator as value reference, loop-body directives (#no_abc, #no_aoc),
//   combined for-loop modifiers in reverse-then-pointer order (`for < *` / `for <*`)
// Compiled: yes (jai-linux, 2026-07-03)

#import "Basic";

// === Rotate operators <<< and >>> ===
// Binary operators at shift precedence level. Rotate bits left/right.
// Source: modules/md5.jai line 119, modules/xxHash/module.jai line 98
rotate_demo :: () {
    x : u32 = 0x8000_0001;
    left := x <<< 1;    // rotate left by 1 → 0x00000003
    right := x >>> 1;   // rotate right by 1 → 0xC0000000
    print("<<< = 0x%, >>> = 0x%\n", formatInt(left, base=16), formatInt(right, base=16));
}

// === Postfix dereference .* ===
// .* as postfix operator dereferences a pointer; use (.*) in prefix position
// Note: << prefix dereference was deprecated in 0.2.022
// Source: modules/Bindings_Generator/restart.jai line 43
prefix_deref_demo :: () {
    x := 42;
    ptr := *x;
    pptr := *ptr;
    val := pptr.*;   // postfix dereference (double pointer → value)
    print("pptr.* = %\n", val);
}

// === Loop-body directives #no_abc #no_aoc ===
// These directives can appear between the iterable expression and the body block
// in for loops. They suppress array bounds checking and automatic output capture.
// Source: modules/Hash.jai line 38
hash_demo :: () {
    data := u8.[1, 2, 3, 4, 5];
    h : u32 = 5381;
    for 0..data.count-1 #no_abc #no_aoc {
        h = (h << 5) + h + data[it];
    }
    print("hash = %\n", h);
}

// === Combined for-loop modifiers: reverse-then-pointer order ===
// The cheatsheet claims modifier order is flexible: `for < *` and `for <*` (the
// reverse-then-pointer order) are both valid, alongside the pointer-then-reverse
// order (`for * <`) already exercised in compendium/03_control_flow.jai. Verified
// against how_to/730_for_expansions.jai line 315 (`for < * dummy {}`) and line 415
// (`for <* my {}`) — both are the SAME `<` (reverse) before `*` (pointer) order,
// merely differing in whitespace.
reverse_pointer_demo :: () {
    // Spaced form: `for < *`
    values := int.[10, 20, 30, 40];
    visited_order: [4] int;
    vi := 0;
    for < * values {
        visited_order[vi] = it_index;   // record traversal order
        vi += 1;
        it.* = it.* + 1;                // mutate through the pointer
    }
    // Reverse order: it_index must visit 3, 2, 1, 0
    assert(visited_order[0] == 3);
    assert(visited_order[1] == 2);
    assert(visited_order[2] == 1);
    assert(visited_order[3] == 0);
    // Pointer mutation applied to every element
    assert(values[0] == 11);
    assert(values[1] == 21);
    assert(values[2] == 31);
    assert(values[3] == 41);
    print("for < * (reverse+pointer): visited_order=%, values=%\n", visited_order, values);

    // No-space form: `for <*` — same semantics, proving spacing is cosmetic
    letters := int.[100, 200, 300];
    no_space_order: [3] int;
    ni := 0;
    for <* letters {
        no_space_order[ni] = it_index;
        ni += 1;
        it.* = it.* * 2;
    }
    assert(no_space_order[0] == 2);
    assert(no_space_order[1] == 1);
    assert(no_space_order[2] == 0);
    assert(letters[0] == 200);
    assert(letters[1] == 400);
    assert(letters[2] == 600);
    print("for <* (reverse+pointer, no space): visited_order=%, values=%\n", no_space_order, letters);
}

main :: () {
    rotate_demo();
    prefix_deref_demo();
    hash_demo();
    reverse_pointer_demo();
    print("PASS: rotate operators (<<<, >>>), postfix dereference (.*), loop-body directives (#no_abc/#no_aoc), and combined for-loop modifiers in reverse-then-pointer order (`for < *` / `for <*`) all verified against beta 0.2.030.\n");
}
