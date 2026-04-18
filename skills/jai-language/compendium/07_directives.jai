// Compendium: Directives
// Jai Version: beta 0.2.028
// Platform: Linux x86-64
// Sources: how_to/095_static_if.jai, how_to/600_insert.jai
// Use-cases: #if, #run, #assert, #string, #char, #code, #insert,
//   #scope_file, #filepath, #line, #this, #caller_location

#import "Basic";

// #scope_file makes this only visible in this file
#scope_file
file_only_var := 42;

#scope_export

// #string (here-string)
GREETING :: #string END
Hello from a
multi-line here-string!
END

// Compile-time constant
PLATFORM :: "linux";

// #this in struct (self-referential pointer)
Node :: struct {
    value: int;
    next: *Node;  // #this not needed when struct name is known
}

// Procedure with #caller_location default
report :: (msg: string, loc := #caller_location) {
    print("[%:%] %\n", loc.fully_pathed_filename, loc.line_number, msg);
}

main :: () {
    // #if (static conditional)
    #if PLATFORM == "linux" {
        print("Running on Linux\n");
    } else {
        print("Running elsewhere\n");
    }

    // #if bare form
    DEBUG :: true;
    #if DEBUG  print("Debug mode on\n");

    // #assert (bare form and with message — NO comma between expr and message)
    #assert(size_of(int) == 8);
    #assert size_of(int) == 8 "Expected 64-bit int";

    // #string
    print(GREETING);

    // #char (character literal -> u8)
    ch :: #char "A";
    print("char A = %\n", ch);

    // #run (compile-time execution, result used at runtime)
    computed :: #run compute_value();
    print("computed = %\n", computed);

    // #code (code literal)
    code_block :: #code { print("from code literal\n"); };
    #insert code_block;

    // #filepath and #line
    print("file: %\n", #filepath);
    print("line: %\n", #line);

    // #caller_location
    report("something happened");

    // #this in procedure (recursive anonymous lambda)
    // factorial via #this
    fact := (n: int) -> int {
        if n <= 1 return 1;
        return n * #this(n - 1);
    };
    print("fact(5) = %\n", fact(5));

    // Using file_only_var (visible because we're in same file)
    print("file_only_var = %\n", file_only_var);
}

// Used by #run
compute_value :: () -> int {
    result := 0;
    for 1..10  result += it;
    return result;
}
