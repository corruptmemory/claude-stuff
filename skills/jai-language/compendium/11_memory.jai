// Compendium: Memory Management
// Jai Version: beta 0.2.028
// Platform: Linux x86-64
// Sources: how_to/200_memory_management.jai, how_to/012_temporary_storage.jai
// Use-cases: New, alloc, free, temporary_storage, push_allocator,
//   context allocator, dynamic arrays, resizable

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
}
