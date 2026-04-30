// Compendium: Memory Management
// Jai Version: beta 0.2.029
// Platform: Linux x86-64
// Sources: how_to/200_memory_management.jai, how_to/012_temporary_storage.jai
// Use-cases: New, alloc, free, temporary_storage, push_allocator,
//   context allocator, dynamic arrays, resizable,
//   array_find/add_if_unique/unordered_remove_by_value with optional compare() (0.2.029)

#import "Basic";

Thing :: struct {
    x: int;
    name: string;
}

main :: () {
    // New: typed heap allocation (returns pointer)
    t := New(Thing);
    t.x = 42;
    t.name = "heap";
    print("New: x=% name=%\n", t.x, t.name);
    free(t);

    // alloc: untyped allocation (returns *void, need cast)
    raw := alloc(size_of(int));
    int_ptr := cast(*int) raw;
    int_ptr.* = 100;
    print("alloc: %\n", int_ptr.*);
    free(raw);

    // Dynamic array with default allocator
    arr: [..] int;
    array_add(*arr, 1);
    array_add(*arr, 2);
    array_add(*arr, 3);
    print("dynamic arr: %\n", arr);
    array_free(arr);

    // Temporary storage (auto-freed, no manual free needed)
    // Use tprint / talloc for temp allocations
    temp_str := tprint("temp value: %", 42);
    print("tprint: %\n", temp_str);

    // Temporary allocator via push_allocator
    // NOTE: temporary_storage is reset between frames, not leaked
    {
        push_allocator(temp);
        temp_arr: [..] int;
        array_add(*temp_arr, 10);
        array_add(*temp_arr, 20);
        print("temp arr: %\n", temp_arr);
        // No need to free — temp storage handles it
    }

    // Context allocator inspection
    print("allocator: %\n", context.allocator.proc);

    // Array operations
    data: [..] int;
    defer array_free(data);

    array_add(*data, 100);
    array_add(*data, 200);
    array_add(*data, 300);

    // array_ordered_remove preserves order
    array_ordered_remove_by_index(*data, 0);
    print("after remove [0]: %\n", data);

    // array_unordered_remove is O(1) but changes order
    array_add(*data, 400);
    print("before unordered remove: %\n", data);

    // -------------------------------------------------------------------------
    // array_find / array_add_if_unique / array_unordered_remove_by_value
    // with optional $compare argument (NEW in beta 0.2.029)
    // -------------------------------------------------------------------------
    // The $compare parameter is compile-time baked ($ prefix = baked constant).
    // When null (the default), == is used. Supply a procedure to override.
    // The motivating use case: structs where equality is on one field only.

    // Without compare: uses operator == (works for int, string, etc.)
    numbers: [..] int;
    defer array_free(numbers);
    array_add(*numbers, 10);
    array_add(*numbers, 20);
    array_add(*numbers, 30);

    found2, idx := array_find(numbers, 20);
    print("array_find 20: found=%, index=%\n", found2, idx);

    // array_add_if_unique: only adds if not already present
    added, idx2 := array_add_if_unique(*numbers, 20);   // already there
    print("add_if_unique 20: added=%, index=%\n", added, idx2);
    added, idx2  = array_add_if_unique(*numbers, 99);   // new
    print("add_if_unique 99: added=%, index=%\n", added, idx2);

    // With custom compare: find a struct by a single field
    Record :: struct { id: int; name: string; }

    records: [..] Record;
    defer array_free(records);
    array_add(*records, .{ id = 1, name = "alice" });
    array_add(*records, .{ id = 2, name = "bob"   });
    array_add(*records, .{ id = 3, name = "carol"  });

    // Match on id only — name field is irrelevant for equality here
    same_id :: (a: Record, b: Record) -> bool { return a.id == b.id; }

    found3, pos := array_find(records, .{ id = 2, name = "" }, same_id);
    print("find by id=2: found=%, index=%\n", found3, pos);

    // array_add_if_unique with custom compare: deduplicate by id
    added2, _ := array_add_if_unique(*records, .{ id = 2, name = "different" }, same_id);
    print("add_if_unique id=2 (dup): added=%\n", added2);   // false

    // array_unordered_remove_by_value with custom compare
    removed := array_unordered_remove_by_value(*records, .{ id = 1, name = "" }, stop_after_first = true, same_id);
    print("removed %  record(s) with id=1\n", removed);
    print("records after remove: count=%\n", records.count);
}
