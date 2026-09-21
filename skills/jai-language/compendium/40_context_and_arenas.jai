// 40 — The implicit context: allocator overrides, its TYPE, and multiple temp arenas
// Jai beta 0.2.030
//
// Proves (cheatsheet): Memory Management / Allocators (the ,, override), Context
//
// Five things, four of which are not obvious from the cheatsheet:
//
//   1. `,,` sets context.allocator for the WHOLE DYNAMIC EXTENT of the call, so an
//      allocation several frames deeper inherits it. This is what lets an out-parameter
//      API hand the caller ownership of a struct's heap FIELDS, not just its array.
//   2. `,, temp` and `,, allocator = temp` are the same thing.
//   3. The context's TYPE is spelled `#Context`. There is no bare `Context` identifier.
//   4. A bare `-> #Context` return is REJECTED; it must be a NAMED return.
//   5. context.temporary_storage can be swapped, so a program can run two temp arenas
//      with different lifetimes. reset_temporary_storage() resets whichever one the
//      CURRENT context points at.
//
// Plus one measurement trap that makes a control silently useless (see high_water_mark).

#import "Basic";
#import "String";

// A struct with an OWNED string field. The field is the whole point: an out-param that
// owned only the array would be a fake fix, with an owned spine and borrowed strings.
Row :: struct { name: string; n: int; }

// Allocates TWO ways -- array_add on the caller's array, and copy_string one level
// deeper -- and names an allocator NOWHERE.
fill :: (out: *[..] Row) {
    for n: string.["alpha-long-enough-to-measure", "beta-long-enough-to-measure"] {
        r: Row;
        r.name = copy_string(n);
        r.n    = it_index;
        array_add(out, r);
    }
}

occupied :: () -> s64 { return context.temporary_storage.total_bytes_occupied; }

// (3) and (4): the type is `#Context`, and the return must be NAMED.
//     `-> Context`   => Error: Undeclared identifier 'Context'.
//     `-> #Context`  => Error: Expected a declaration after ->.
second_arena_backing: [1 << 16] u8;
second_arena:         Temporary_Storage_Paged_Alloc;

second_arena_context :: () -> c: #Context {
    if !second_arena.data {
        second_arena.data = second_arena_backing.data;
        second_arena.size = second_arena_backing.count;
    }
    ctx := context;
    ctx.temporary_storage = *second_arena.base;   // #as using base: Temporary_Storage
    return ctx;
}

// push_context restores on an EARLY RETURN out of its block, like a defer.
early_return_probe :: () -> int {
    ctx := second_arena_context();
    push_context ctx {
        for 0..3  if it == 2  return 42;
    }
    return 0;
}

main :: () {
    // ---- 1. control: no ,, means the DEFAULT allocator; temp must not move ----------
    before := occupied();
    heap_rows: [..] Row;
    fill(*heap_rows);
    assert(occupied() - before == 0, "the default-allocator path must not touch temp");

    // ---- 2. ,, allocator = temp, and ,, temp: identical -----------------------------
    before = occupied();
    named_rows: [..] Row;
    fill(*named_rows ,, allocator = temp);
    d_named := occupied() - before;
    assert(d_named > 0, "the ,, override must allocate from temporary storage");

    before = occupied();
    short_rows: [..] Row;
    fill(*short_rows ,, temp);
    assert(occupied() - before == d_named, "`,, temp` == `,, allocator = temp`");

    // ---- 3. TRANSITIVITY: the copy_string one level deeper is in temp too -----------
    in_temp :: (p: *void, lo: *u8, hi: *u8) -> bool {
        b := cast(*u8) p;
        return b >= lo && b < hi;
    }
    ts := context.temporary_storage;
    lo := ts.data;
    hi := ts.data + ts.size;
    assert(in_temp(named_rows.data,         lo, hi), "the ARRAY came from temp");
    assert(in_temp(named_rows[0].name.data, lo, hi), "the STRING came from temp too");
    assert(!in_temp(heap_rows[0].name.data, lo, hi), "control: the no-,, string did not");

    // ---- 4. TWO ARENAS: resetting one must not disturb the other --------------------
    run_ts := context.temporary_storage;
    kept: [..] Row;
    fill(*kept ,, temp);                      // lives in the OUTER arena
    kept_occupied := run_ts.total_bytes_occupied;

    inner_peak: s64 = 0;
    ctx := second_arena_context();
    push_context ctx {
        assert(context.temporary_storage == *second_arena.base);

        // `temp` IS LATE-BOUND -- it names a TIER, not an arena.
        //   temp :: Allocator.{temporary_allocator_proc, null};     (Basic/module.jai)
        // `data` is null, and the proc reads context.temporary_storage at ALLOCATION
        // time, so the SAME `temp` symbol resolves to whichever arena is current. That
        // is why a callee writing `x.allocator = temp` does NOT sever the caller's
        // chain: it fixes the tier and inherits the arena. An allocator with non-null
        // `data` is the one that carries an identity the caller did not choose.
        inner_rows: [..] Row;
        fill(*inner_rows ,, temp);
        ilo := second_arena.data;
        ihi := second_arena.data + second_arena.size;
        assert(in_temp(inner_rows.data,         ilo, ihi), "same `temp`, INNER arena");
        assert(in_temp(inner_rows[0].name.data, ilo, ihi), "...strings too");
        assert(!in_temp(kept.data, ilo, ihi), "control: the outer rows are NOT in here");

        for frame: 0..4 {
            junk := tprint("frame % scratch", frame);
            assert(junk.count > 0);
            // MEASURE BEFORE THE RESET. reset_temporary_storage zeroes high_water_mark
            // (Basic/Temporary_Storage_Paged_Alloc.jai:167), so a control that samples
            // it afterwards reads 0 and concludes -- wrongly -- that nothing happened.
            inner_peak = max(inner_peak, context.temporary_storage.total_bytes_occupied);
            reset_temporary_storage();        // resets the INNER arena only
        }
    }
    assert(inner_peak > 0, "the inner arena really did the work");
    assert(run_ts.total_bytes_occupied == kept_occupied, "outer arena untouched by inner resets");
    assert(kept.count == 2);
    assert(kept[0].name == "alpha-long-enough-to-measure", "outer data survived the resets");
    assert(kept[1].name == "beta-long-enough-to-measure",  "...including the SECOND row");

    // The second row matters: with the arenas merged, row 0 can still read correctly
    // while row 1 is garbage. A control that only checks row 0 passes a broken split.

    // ---- 5. push_context restores on an early return --------------------------------
    saved := context.temporary_storage;
    assert(early_return_probe() == 42);
    assert(context.temporary_storage == saved, "push_context restores on early return");

    print("40_context_and_arenas: all assertions passed\n");
}
