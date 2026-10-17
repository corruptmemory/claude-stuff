// 41 — Init regions: temp by default, a Preserved_Values struct for what must survive
// Jai beta 0.2.030
//
// Proves (cheatsheet): Context System > Init regions: temp by default, a Preserved_Values
//   struct for what must survive
//
// Sources: established against the beta 0.2.030 compiler (2026-10-17) while reviewing the
//   Vulkan lessons in understanding-graphics-apis, where every enumerate call follows the
//   same protocol -- get a count, allocate that many, get the data, keep a little, drop
//   the rest. Basic/module.jai:347 (`temp`), Basic/Temporary_Storage_Paged_Alloc.jai (the
//   arena), how_to/011_context.jai (#add_context).
// Use-cases: Vulkan / D3D / any C-API setup with the count-then-fill protocol; any init
//   that makes many short-lived allocations and keeps a few values.
//
// The C/C++ habit is one `defer free(buf.data)` per enumeration buffer. Jai makes a better
// shape cheap: give INIT its own memory region with the temp allocator as the default, and
// copy the few values that must outlive init through ONE dedicated allocator carried by a
// Preserved_Values struct that the context points at. Then:
//
//   1. nothing inside init names an allocator or frees anything -- every NewArray lands
//      in the region, and the region dies all at once;
//   2. helpers like save_device_name take NO "where does this go" parameter, because
//      context.preserved_values says where;
//   3. the allocator that owns the preserved values is a FIELD of the struct that holds
//      them, so whoever frees the struct knows how.
//
// What the asserts pin, with three distinguishable allocators:
//   - the ambient (outer) allocator is NEVER called during init;
//   - the preserved allocator is called exactly once per preserved value;
//   - the scratch really went to the init arena, and the caller's own temp arena is
//     untouched, so the region can be dropped without a frame's temp data going with it;
//   - the preserved values survive the arena being reset and scribbled over.

#import "Basic";
#import "String";

// ---- the part that would be the C API --------------------------------------------------
// A stand-in for vkEnumerateInstanceLayerProperties: with a null `out` it reports the count,
// otherwise it fills up to *count entries. Only the names are worth keeping.
Layer_Properties :: struct {
    layer_name:   [64] u8;        // C-style fixed buffer, NUL-terminated
    spec_version: u32;
}

FAKE_LAYERS :: string.["VK_LAYER_MESA_overlay", "VK_LAYER_KHRONOS_validation", "VK_LAYER_MESA_device_select"];

enumerate_layers :: (count: *u32, out: *Layer_Properties) -> bool {
    if !out { count.* = cast(u32) FAKE_LAYERS.count; return true; }
    n := min(cast(s64) count.*, FAKE_LAYERS.count);
    for i: 0..n-1 {
        src := FAKE_LAYERS[i];
        memcpy(out[i].layer_name.data, src.data, src.count);
        out[i].layer_name[src.count] = 0;
        out[i].spec_version = cast(u32) (100 + i);
    }
    count.* = cast(u32) n;
    return true;
}

DEVICE_NAME :: "AMD Radeon RX 7900 XTX (RADV NAVI31)";

get_device_name :: (buffer: *u8, capacity: s64) -> s64 {   // like vkGetPhysicalDeviceProperties
    n := min(DEVICE_NAME.count, capacity - 1);
    memcpy(buffer, DEVICE_NAME.data, n);
    buffer[n] = 0;
    return n;
}

// ---- what survives init -------------------------------------------------------------------
Preserved_Values :: struct {
    allocator:        Allocator;   // owns every heap field below; whoever frees knows how
    device_name:      string;
    validation_layer: string;      // empty if the layer is absent
}

#add_context preserved_values: *Preserved_Values;   // null until vulkan_init pushes one

// Dedicated savers: no destination parameter, the context says where.
save_device_name :: (name: *u8, length: s64) {
    pv := context.preserved_values;
    pv.device_name = copy_string(to_string(name, length),, allocator = pv.allocator);
}

save_validation_layer :: (name: string) {
    pv := context.preserved_values;
    pv.validation_layer = copy_string(name,, pv.allocator);   // `,, x` == `,, allocator = x`
}

// ---- the init region ----------------------------------------------------------------------
init_arena_backing: [1 << 16] u8;
init_arena:         Temporary_Storage_Paged_Alloc;   // the DERIVED type (see compendium/40)
init_scratch_peak:  s64;

vulkan_init :: (pv: *Preserved_Values) -> bool {
    init_arena.data = init_arena_backing.data;
    init_arena.size = init_arena_backing.count;

    ctx := context;
    ctx.allocator         = temp;               // the region's DEFAULT allocator...
    ctx.temporary_storage = *init_arena.base;   // ...and `temp` resolves to THIS arena
    ctx.preserved_values  = pv;
    ok := false;
    push_context ctx {
        ok = init_body();
        // Measure BEFORE the reset: reset_temporary_storage zeroes high_water_mark, and
        // total_bytes_occupied goes back to 0 (compendium/40).
        init_scratch_peak = context.temporary_storage.total_bytes_occupied;
        reset_temporary_storage();              // the region dies here, all at once
    }
    return ok;
}

in_range :: (p: *void, lo: *u8, hi: *u8) -> bool {
    b := cast(*u8) p;
    return b >= lo && b < hi;
}

// Inside the region: the count-then-fill protocol, with no defer and no free anywhere.
init_body :: () -> bool {
    layer_count: u32;
    if !enumerate_layers(*layer_count, null)  return false;
    layer_props := NewArray(layer_count, Layer_Properties);     // scratch, in the init arena
    if !enumerate_layers(*layer_count, layer_props.data)  return false;
    assert(in_range(layer_props.data, init_arena.data, init_arena.data + init_arena.size),
           "the scratch array is in the init arena");

    for * layer_props {
        name := to_string(it.layer_name.data);                  // a VIEW into scratch
        if name == "VK_LAYER_KHRONOS_validation"  save_validation_layer(name);
    }

    name_buf := NewArray(256, u8);                               // also scratch
    n := get_device_name(name_buf.data, name_buf.count);
    save_device_name(name_buf.data, n);
    return true;
}

// ---- the proof ----------------------------------------------------------------------------
// A counting allocator: the only way to observe WHICH allocator an allocation went to.
Alloc_Counts :: struct { acquires: int; frees: int; }

counting_allocator_proc :: (mode: Allocator_Mode, requested_size: s64, old_size: s64,
                            old_memory: *void, allocator_data: *void) -> *void {
    d := cast(*Alloc_Counts) allocator_data;
    if #complete mode == {
      case .ALLOCATE;  d.acquires += 1;  return alloc(requested_size ,, context.default_allocator);
      case .RESIZE;    d.acquires += 1;  return realloc(old_memory, requested_size, old_size ,, context.default_allocator);
      case .FREE;      d.frees += 1;     free(old_memory ,, context.default_allocator);  return null;
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
    outer_counts:     Alloc_Counts;
    preserved_counts: Alloc_Counts;
    outer     := Allocator.{ counting_allocator_proc, *outer_counts };
    preserved := Allocator.{ counting_allocator_proc, *preserved_counts };

    pv: Preserved_Values;
    pv.allocator = preserved;

    // Something in the CALLER's temp arena that must survive init untouched.
    frame_ts     := context.temporary_storage;
    frame_marker := tprint("frame data that must survive init");
    frame_before := frame_ts.total_bytes_occupied;

    ok := false;
    {
        push_allocator(outer);                  // the AMBIENT allocator while init runs
        ok = vulkan_init(*pv);
        assert(context.preserved_values == null, "the pointer lived only inside the region");
        assert(context.allocator.proc == counting_allocator_proc, "push_context restored the ambient allocator");
    }
    assert(ok);

    // Three allocators, three lifetimes.
    assert(outer_counts.acquires == 0,     "init never touched the ambient allocator");
    assert(preserved_counts.acquires == 2, "exactly one allocation per preserved value");
    assert(init_scratch_peak > 0,          "the scratch really went to the init arena");
    assert(init_arena.total_bytes_occupied == 0, "the region was dropped");
    assert(frame_ts.total_bytes_occupied == frame_before, "the caller's temp arena is untouched");
    assert(frame_marker == "frame data that must survive init");

    // Scribble over the whole init arena: anything that secretly lived there is now garbage.
    memset(init_arena_backing.data, 0xAA, init_arena_backing.count);
    assert(pv.device_name      == DEVICE_NAME,                   "preserved: the device name");
    assert(pv.validation_layer == "VK_LAYER_KHRONOS_validation", "preserved: the chosen layer");
    assert(!in_range(pv.device_name.data, init_arena_backing.data, init_arena_backing.data + init_arena_backing.count),
           "...and it is NOT in the arena");

    // Teardown mirrors the struct: the allocator the struct carries frees its fields.
    free(pv.device_name      ,, pv.allocator);
    free(pv.validation_layer ,, pv.allocator);
    assert(preserved_counts.frees == 2, "freed through the allocator the struct carries");

    print("41_init_region_and_preserved_values: all assertions passed\n");
}
