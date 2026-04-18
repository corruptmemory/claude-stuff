// Compendium: Control Flow
// Jai Version: beta 0.2.028
// Platform: Linux x86-64
// Sources: how_to/040_control_flow.jai, how_to/050_for_loops.jai
// Use-cases: if/else, if-case, for loops, while, defer, break/continue,
//   backtick bindings, range iteration, reverse/pointer, ifx, push_context

#import "Basic";

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
}
