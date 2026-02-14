// Compendium: Macros & Metaprogramming
// Jai Version: beta 0.2.025
// Platform: Linux x86-64
// Sources: how_to/600_insert.jai, how_to/730_for_expansions.jai
// Use-cases: #expand, backtick export, #code, #insert, #run,
//   compile-time code generation, #bake_arguments

#import "Basic";

// #expand macro — runs in caller's scope
// Backtick (`) exports names to caller scope
set_to_zero :: () #expand {
    `result := 0;
}

// Macro with body parameter (Code argument)
do_twice :: (body: Code) #expand {
    #insert body;
    #insert body;
}

// Macro with backtick break/continue
find_first :: (arr: [] $T, pred: Code) -> s64 #expand {
    for arr {
        if #insert pred  `return it_index;
    }
    `return -1;
}

// #bake_arguments: create specialized procedure
adder :: (x: int, y: int) -> int { return x + y; }
add_42 :: #bake_arguments adder(y = 42);

// #run for compile-time computation
COMPUTED :: #run compute_table();

compute_table :: () -> [5] int {
    result: [5] int;
    for 0..4  result[it] = it * it;
    return result;
}

main :: () {
    // #expand macro
    set_to_zero();
    print("result = %\n", result);  // result exported to this scope

    // do_twice with #code
    x := 0;
    do_twice(#code { x += 1; });
    print("x after do_twice = %\n", x);

    // #bake_arguments
    print("add_42(8) = %\n", add_42(8));

    // #run result used at runtime
    print("COMPUTED = %\n", COMPUTED);

    // #insert with code literal
    #insert #code { print("inserted code\n"); };

    // #code and #insert for expression-level
    val := 10;
    code_expr :: #code val + 5;
    computed := #insert code_expr;
    print("insert expr = %\n", computed);
}
