// Compendium: Advanced Operators & Special Syntax
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: modules/md5.jai, modules/xxHash/module.jai, modules/Bindings_Generator/restart.jai,
//          modules/Thread/module.jai, modules/Hash.jai
// Use-cases: rotate operators (<<<, >>>), postfix dereference (.*),
//   operator as value reference, loop-body directives (#no_abc, #no_aoc)
// Compiled: yes (jai-linux, 2026-02-21)

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

main :: () {
    rotate_demo();
    prefix_deref_demo();
    hash_demo();
}
