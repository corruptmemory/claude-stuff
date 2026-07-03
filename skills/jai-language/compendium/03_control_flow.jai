// Compendium: Control Flow
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/040_control_flow.jai, how_to/050_for_loops.jai,
//   how_to/019_looping.jai, how_to/027_if_case.jai, how_to/095_static_if.jai,
//   how_to/730_for_expansions.jai
// Use-cases: if/else, if-case, for loops, while, defer, break/continue,
//   backtick bindings, range iteration, reverse/pointer, ifx, push_context,
//   conditional for-modifiers (for <=cond / for *=cond), named for-expansion
//   (for :name), labeled continue, #through fallthrough, #ifx (compile-time
//   ifx), braced defer, backtick `defer inside #expand macros

#import "Basic";

// --- Support declarations for the extended control-flow demonstrations ---

COND_NUMS :: int.[1, 2, 3, 4];

// `for <=cond`: compile-time-conditional REVERSE. The <= sigil takes a
// compile-time bool; when true the iteration runs in reverse. Baking it into a
// $-parameter makes it known at compile time (how_to/730_for_expansions.jai).
first_and_total :: ($reverse: bool) -> (first: int, total: int) {
    first := -1;
    total := 0;
    seen  := 0;
    for <=reverse COND_NUMS {
        if seen == 0  first = it;   // capture the first-visited element
        seen  += 1;
        total += it;
    }
    return first, total;
}

// `for *=cond`: compile-time-conditional BY-POINTER. When by_ptr is true, `it`
// is a pointer (mutate via it.*); when false it is a read-only value.
double_if :: ($by_ptr: bool, arr: [] int) {
    for *=by_ptr arr {
        #if by_ptr  it.* *= 2;
    }
}

// Named for-expansion: define a for_expansion (the default) plus a named
// alternative, and select the alternative with `for :name` (how_to/730).
demo_named_expansion :: () {
    Bag :: struct { items: [4] int; }

    for_expansion :: (bag: Bag, body: Code, flags: For_Flags) #expand {
        for i: 0..bag.items.count-1 {
            `it_index := i;
            `it       := bag.items[i];
            #insert body;
        }
    }
    evens_only :: (bag: Bag, body: Code, flags: For_Flags) #expand {
        for i: 0..bag.items.count-1 {
            v := bag.items[i];
            if v & 1  continue;             // skip odd values
            `it_index := i;
            `it       := v;
            #insert body;
        }
    }

    bag: Bag;
    bag.items = .[10, 11, 12, 13];

    all := 0;
    for bag  all += it;                     // default expansion visits all
    assert(all == 46);

    evens := 0;
    for :evens_only bag  evens += it;        // named expansion visits 10 + 12
    assert(evens == 22);
}

// `defer is one of the backtickable keywords: inside an #expand macro it
// installs the deferred statement into the CALLER's scope, so it fires when the
// caller's enclosing block exits (not when the macro returns).
with_cleanup :: (log: *[..] int) #expand {
    array_add(log, 100);
    `defer array_add(log, 200);
}

demo_backtick_defer :: () {
    log: [..] int;
    {
        with_cleanup(*log);      // appends 100 now; schedules 200 at block exit
        array_add(*log, 150);
    }                            // block exits -> the backtick defer fires (200)
    assert(log.count == 3);
    assert(log[0] == 100 && log[1] == 150 && log[2] == 200);
}

// Compile-time constant driving the #ifx demonstrations below.
BUILD_IS_DEBUG :: true;

main :: () {
    // If/else
    x := 42;
    if x > 0 {
        print("positive\n");
    } else {
        print("non-positive\n");
    }

    // If with bare body (no braces)
    if x > 0  print("still positive\n");

    // If with 'then' keyword
    if x > 0 then print("then form\n");

    // If-case (switch)
    direction := 1;
    if direction == {
        case 0;
            print("north\n");
        case 1;
            print("south\n");
        case;
            print("unknown\n");
    }

    // For loop with implicit it/it_index
    array := int.[10, 20, 30];
    for array  print("  it=% idx=%\n", it, it_index);

    // For with named bindings
    for elem, idx: array  print("  elem=% idx=%\n", elem, idx);

    // For with range
    for 0..4  print("  range: %\n", it);

    // For reverse
    for < array  print("  rev: %\n", it);

    // For by-pointer
    mut_array : [3] int = .[1, 2, 3];
    for * mut_array  it.* *= 2;
    for mut_array  print("  doubled: %\n", it);

    // For reverse + pointer
    for * < mut_array  print("  rev ptr: %\n", it.*);

    // NOTE: backtick bindings (e.g. `val, `idx) only valid inside #expand macros
    // Cannot demonstrate in regular procedures

    // While loop
    i := 0;
    while i < 3 {
        print("  while i=%\n", i);
        i += 1;
    }

    // Break and continue
    for 0..10 {
        if it == 3  continue;
        if it == 7  break;
        print("  bc: %\n", it);
    }

    // Labeled break
    for outer: 0..2 {
        for 0..2 {
            if it == 1  break outer;
            print("  labeled: outer=% inner=%\n", outer, it);
        }
    }

    // Defer
    {
        defer print("  deferred (runs last)\n");
        print("  before defer\n");
    }

    // Ifx expression
    val := 10;
    result := ifx val > 5 then "big" else "small";
    print("ifx result: %\n", result);

    // Ifx without then
    result2 := ifx val > 5  "big";
    print("ifx no-then: %\n", result2);

    // --- Extended constructs (each asserted) ---

    // Conditional for-modifier: for <=cond (compile-time-conditional reverse).
    f_fwd, t_fwd := first_and_total(false);
    f_rev, t_rev := first_and_total(true);
    print("for <=cond: fwd first=% total=% ; rev first=% total=%\n",
        f_fwd, t_fwd, f_rev, t_rev);
    assert(f_fwd == 1 && t_fwd == 10);   // forward: first visited is 1
    assert(f_rev == 4 && t_rev == 10);   // reversed: first visited is 4

    // Conditional for-modifier: for *=cond (compile-time-conditional by-pointer).
    nums := int.[1, 2, 3];
    double_if(true, nums);               // by pointer -> mutates in place
    assert(nums[0] == 2 && nums[1] == 4 && nums[2] == 6);
    novum := int.[5, 6, 7];
    double_if(false, novum);             // by value -> no mutation
    assert(novum[0] == 5 && novum[1] == 6 && novum[2] == 7);
    print("for *=cond: doubled=% untouched=%\n", nums, novum);

    // Named for-expansion invocation: for :name container.
    demo_named_expansion();

    // Labeled continue: continue an OUTER named loop from inside an inner loop.
    labeled_hits := 0;
    for outer_c: 0..2 {
        for inner_c: 0..2 {
            if inner_c == 1  continue outer_c;  // advance the outer loop
            labeled_hits += 1;
        }
    }
    print("labeled continue: hits=%\n", labeled_hits);
    assert(labeled_hits == 3);           // one inner hit per outer iteration

    // #through: C-like fallthrough from one if-case case into the next.
    grade := 2;
    msg_count := 0;
    if grade == {
        case 1; msg_count += 1;   #through;
        case 2; msg_count += 1;   #through;
        case 3; msg_count += 1;
        case;   msg_count += 100;
    }
    print("#through: msg_count=%\n", msg_count);
    assert(msg_count == 2);              // case 2 (+1) falls through to case 3 (+1)

    // #ifx: compile-time ifx expression (then form and block form).
    mode := #ifx BUILD_IS_DEBUG then "debug" else "release";
    assert(mode == "debug");
    computed := #ifx BUILD_IS_DEBUG {
        k := 6;
        k * 7;                           // block value is its last expression
    } else {
        0;
    };
    print("#ifx: mode=% computed=%\n", mode, computed);
    assert(computed == 42);

    // Braced defer: multiple statements deferred to scope exit.
    defer_log: [..] int;
    {
        defer {
            array_add(*defer_log, 1);
            array_add(*defer_log, 2);
        }
        array_add(*defer_log, 0);        // runs first; the braced defer runs last
    }
    print("braced defer: %\n", defer_log);
    assert(defer_log.count == 3 && defer_log[0] == 0 && defer_log[1] == 1 && defer_log[2] == 2);

    // Backtick `defer inside an #expand macro (fires in the caller's scope).
    demo_backtick_defer();

    print("PASS: control flow (extended: for <=cond / *=cond, for :name, labeled continue, #through, #ifx, braced defer, backtick `defer)\n");
}
