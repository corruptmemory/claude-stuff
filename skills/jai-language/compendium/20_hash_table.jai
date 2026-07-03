// Compendium: Hash_Table module
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: modules/Hash_Table.jai, examples/hash_table_test.jai
// Use-cases: basic CRUD, iteration, reset/resize, custom hash/compare,
//            find_or_add pattern, stable-pointer guarantees
//
// Key 0.2.029 changes documented here:
//   - init() is deprecated; Table is usable immediately after declaration
//   - table_reset() now FREES memory (like array_reset) — breaking behavior change
//   - table_reset_keeping_memory() is the old table_reset behavior
//   - table_resize() added for explicit pre-allocation

#import "Basic";
#import "Hash_Table";

// ============================================================================
// Basic CRUD
// ============================================================================
// Table(Key_Type, Value_Type) — both type parameters are required.
// No init() call needed; the allocator is captured lazily on first use.

demo_basic :: () {
    t: Table(string, int);

    // table_add: insert a key-value pair, returns *Value (pointer to stored value)
    table_add(*t, "alpha", 1);
    table_add(*t, "beta",  2);
    table_add(*t, "gamma", 3);

    // table_find: returns (success: bool, value: Value_Type) — value is a copy
    found, val := table_find(*t, "beta");
    print("find beta: found=%, val=%\n", found, val);

    _, missing := table_find(*t, "delta");   // found=false, val is uninitialized
    print("find delta: found=false (val garbage, don't use it)\n");

    // table_find_pointer: returns *Value or null — for in-place mutation
    ptr := table_find_pointer(*t, "alpha");
    if ptr {
        ptr.* = 100;
        print("mutated alpha in place: %\n", ptr.*);
    }

    // table_set: add if absent, replace if present (combine add + update)
    table_set(*t, "beta", 99);
    table_set(*t, "new",  42);

    // table_contains: set-membership check (no value copy)
    print("contains gamma: %\n", table_contains(*t, "gamma"));
    print("contains delta: %\n", table_contains(*t, "delta"));

    // table_remove: removes and returns the value
    removed, old := table_remove(*t, "gamma");
    print("removed gamma: success=%, old_val=%\n", removed, old);
    print("table count after remove: %\n", t.count);

    deinit(*t);
}

// ============================================================================
// Iteration
// ============================================================================
// for_expansion: it = value, it_index = key (note reversed from array convention)
// Iteration order is NOT insertion order — it follows internal slot layout.
// Iteration with * gives *Value_Type, allowing in-place modification.
// Use 'remove' to delete the current entry while iterating.

demo_iteration :: () {
    t: Table(string, float);
    table_add(*t, "x", 1.0);
    table_add(*t, "y", 2.0);
    table_add(*t, "z", 3.0);

    // Read-only iteration
    print("table entries:\n");
    for t {
        key   := it_index;   // string
        value := it;         // float (copy)
        print("  %: %\n", key, value);
    }

    // By-pointer iteration (for in-place mutation)
    for * t  it.* *= 10.0;

    // Iteration with removal (remove entries matching a condition)
    for * t {
        if it_index == "x"  remove it;   // removes "x" from the table
    }
    print("count after remove-during-iteration: %\n", t.count);

    deinit(*t);
}

// ============================================================================
// find_or_add: get-or-create pattern
// ============================================================================
// Returns a *Value and a 'newly_added' bool.
// Use when the value is expensive to construct or when you need a stable pointer.

demo_find_or_add :: () {
    t: Table(string, [..] int);

    // Append to a per-key list, creating it if absent
    add_to_list :: (t: *Table(string, [..] int), key: string, v: int) {
        list, _ := find_or_add(t, key);
        array_add(list, v);
    }

    add_to_list(*t, "evens", 2);
    add_to_list(*t, "evens", 4);
    add_to_list(*t, "odds",  1);
    add_to_list(*t, "evens", 6);

    for t  print("%: %\n", it_index, it);

    // Clean up the inner arrays first, then the table itself
    for * t  array_free(it.*);
    deinit(*t);
}

// ============================================================================
// Reset and resize (0.2.029 behavior)
// ============================================================================
// BREAKING CHANGE IN 0.2.029:
//   table_reset()               — now FREES memory (matches array_reset behavior)
//   table_reset_keeping_memory() — old table_reset behavior (clear count, keep memory)
//
// table_resize(t, expected_count) — pre-allocate before a big insert batch.
//   Avoids repeated internal resizes and keeps pointers stable during the batch.
//   The table will accommodate at least expected_count entries before growing.

demo_reset_resize :: () {
    t: Table(int, string);

    table_add(*t, 1, "one");
    table_add(*t, 2, "two");
    print("before reset_keeping_memory: count=%\n", t.count);

    // Clear contents, keep the allocated memory (useful for frame-scoped tables)
    table_reset_keeping_memory(*t);
    print("after reset_keeping_memory: count=%, allocated=%\n", t.count, t.allocated);

    table_add(*t, 3, "three");

    // Free memory entirely (NEW 0.2.029 behavior — was keep-memory before)
    table_reset(*t);
    print("after reset: count=%, allocated=%\n", t.count, t.allocated);

    // Pre-allocate for a known large batch (avoids mid-batch resizes)
    table_resize(*t, 1000);
    print("after resize(1000): allocated=%\n", t.allocated);

    deinit(*t);
}

// ============================================================================
// table_ensure_space: reserve space while keeping pointers stable
// ============================================================================
// table_ensure_space guarantees the table won't resize during the next N inserts.
// This makes previously returned *Value pointers remain valid for the batch.

demo_ensure_space :: () {
    t: Table(string, int);

    // Reserve room for 5 more inserts before any internal resize
    table_ensure_space(*t, 5);

    ptr_a := table_add(*t, "a", 10);   // ptr_a is stable for this batch
    ptr_b := table_add(*t, "b", 20);

    ptr_a.* = 99;   // safe: no resize happened between the adds
    print("a=%, b=%\n", ptr_a.*, ptr_b.*);

    deinit(*t);
}

// ============================================================================
// Custom hash and compare functions
// ============================================================================
// Table struct parameters: given_hash_function and given_compare_function.
// Both are compile-time constants baked into the Table type.
// Useful for case-insensitive keys, structs, integer ranges, etc.

case_insensitive_hash :: (s: string) -> u32 {
    // Simple djb2-style hash treating uppercase as lowercase
    h: u32 = 5381;
    for s  h = ((h << 5) + h) + (cast(u32)(it | 0x20));
    return h;
}

case_insensitive_eq :: (a: string, b: string) -> bool {
    if a.count != b.count  return false;
    for i: 0..a.count-1 {
        if (a[i] | 0x20) != (b[i] | 0x20)  return false;
    }
    return true;
}

demo_custom_hash :: () {
    // Type alias for readability — Table with custom hash and compare
    CI_Table :: Table(string, int,
        given_hash_function    = case_insensitive_hash,
        given_compare_function = case_insensitive_eq);

    t: CI_Table;
    table_add(*t, "Hello", 1);

    // Case-insensitive lookup
    found, val := table_find(*t, "hello");
    print("case-insensitive find 'hello': found=%, val=%\n", found, val);
    found, val  = table_find(*t, "HELLO");
    print("case-insensitive find 'HELLO': found=%, val=%\n", found, val);

    deinit(*t);
}

// ============================================================================
// Main
// ============================================================================

main :: () {
    print("=== Basic CRUD ===\n");
    demo_basic();
    print("\n=== Iteration ===\n");
    demo_iteration();
    print("\n=== find_or_add ===\n");
    demo_find_or_add();
    print("\n=== Reset and Resize (0.2.029) ===\n");
    demo_reset_resize();
    print("\n=== ensure_space ===\n");
    demo_ensure_space();
    print("\n=== Custom hash/compare ===\n");
    demo_custom_hash();
}
