// Compendium entry 16: Named Return Capture, Standalone #no_aoc Blocks, #Context Type
// Jai Compiler Version: beta 0.2.029 (9 April 2026)
// Platform: Linux x86-64
// Sources: modules/Basic/tests.jai (name=,), modules/Subtitles.jai (name:,),
//          modules/executable_formats/tbd/tbd.jai (multiple name=,),
//          modules/Basic/Int128.jai (#no_aoc standalone block),
//          modules/Basic/float_to_string.jai (#no_aoc standalone block),
//          modules/Remap_Context.jai (#Context type),
//          modules/Android/Toolchain/adb.jai (#Context.default_allocator),
//          how_to/011_context.jai (push_context {} default form),
//          modules/Input/macos.jai (@selector annotation)
//
// Use-cases demonstrated:
//   - name:, in multi-return capture (declare new variable at that position)
//   - Mixed declaration/assignment in `=` context multi-return capture
//   - _:, discard pattern (positional)
//   - Standalone #no_aoc { } block statement
//   - else #no_aoc { } clause
//   - #Context as a type name
//   - #Context.member static member access
//   - push_context { } without expression (default context)
//   - @selector annotation in Objective-C bindings

#import "Basic";

// ============================================================================
// Mixed Declaration/Assignment in Multi-Return Capture
// ============================================================================
// When capturing multiple return values, each position can independently
// be a declaration or an assignment. Capture is ALWAYS POSITIONAL:
//   `name:,` declares a NEW variable at that position (the `:` means "declare")
//   bare `name,` in `:=` context declares, in `=` context assigns to existing
//   `_:,` declares and discards the return at that position
//
// IMPORTANT: `name:` does NOT target returns by name -- the caller chooses
// whatever name they want. The `:` is purely a declaration operator.

// A function with multiple named returns
get_result :: () -> value: int, success: bool, message: string {
    return 42, true, "ok";
}

// Another function for demonstrating capture patterns
split_at_3 :: (input: string) -> result: string, remainder: string {
    if input.count > 3 {
        r: string;
        r.data = input.data;
        r.count = 3;
        rem: string;
        rem.data = input.data + 3;
        rem.count = input.count - 3;
        return r, rem;
    }
    return input, "";
}

demo_named_return_capture :: () {
    // Standard positional capture (all declared with :=)
    val, ok, msg := get_result();
    print("Positional: val=%, ok=%, msg=%\n", val, ok, msg);

    // In `:=` context, `name:,` still declares -- redundant but legal
    // name:, is useful in `=` context to declare at a specific position
    result:, rest := split_at_3("hello world");
    print("name:, capture: result=%, rest=%\n", result, rest);

    // Mixed capture in `=` context:
    // `my_result:,` DECLARES new var (pos 1), `existing_rem` ASSIGNS (pos 2)
    existing_rem := "";
    my_result:, existing_rem = split_at_3("testing123");
    print("Mixed: my_result=%, existing_rem=%\n", my_result, existing_rem);

    // Discard with _:, (declares and discards at that position)
    _:, remainder2 := split_at_3("testing");
    print("Discard: remainder=%\n", remainder2);
}

// ============================================================================
// Standalone #no_aoc { } Block Statement
// ============================================================================
// #no_aoc can wrap arbitrary statements, not just for-loop bodies
// Disables arithmetic overflow checking for enclosed operations
// Source: modules/Basic/Int128.jai, modules/Basic/float_to_string.jai

demo_no_aoc_block :: () {
    a : u64 = 0xFFFF_FFFF_FFFF_FFFE;
    b : u64 = 5;

    // Standalone #no_aoc block — suppresses overflow for this block
    result: u64;
    #no_aoc {
        result = a + b;  // Would overflow, but check is suppressed
    }
    print("Overflow result (no check): %\n", result);

    // Can also appear in else clauses:
    // } else #no_aoc {
    //     c.low = a.low + b.low;
    // }
    // Source: modules/Basic/Int128.jai lines 85, 121, 145, 660
}

// ============================================================================
// #Context as a Type
// ============================================================================
// #Context is the type of the implicit context parameter
// Can be used as a type, namespace, and with type_info()

demo_context_type :: () {
    // #Context as a type
    ctx: #Context;                 // declare a variable of type #Context
    ctx = context;                 // copy current context

    // #Context with type_info
    info := type_info(#Context);
    print("#Context type info: name=%, size=%\n", info.name, info.runtime_size);

    // push_context with default #Context (no expression)
    push_context {
        // Inside here we have a fresh default context
        print("Inside default push_context\n");
    }
}

// ============================================================================
// Main
// ============================================================================

main :: () {
    print("=== Named Return Capture ===\n");
    demo_named_return_capture();
    print("\n=== Standalone #no_aoc Block ===\n");
    demo_no_aoc_block();
    print("\n=== #Context Type ===\n");
    demo_context_type();
}
