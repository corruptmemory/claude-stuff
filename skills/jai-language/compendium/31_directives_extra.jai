// Proves (cheatsheet): ## Directives (residual single-file-demonstrable set)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/050_this.jai, how_to/497_caller_code.jai, how_to/100_polymorphic_procedures.jai,
//   how_to/115_auto_bakes.jai, how_to/170_modify.jai, how_to/180_type_variants.jai,
//   how_to/005_strings.jai, how_to/018_print_functions.jai, how_to/551_things_that_are_constant.jai,
//   how_to/400_workspaces.jai, how_to/630_compiler_get_nodes.jai,
//   how_to/950_cross-compiling/do_things_at_compile_time_for_real.jai
// Use-cases: #run,host  #run,stallable  #scope_module  #scope_export  #exists  #location
//   #caller_code  #procedure_name  #procedure_of_call  #string,cr  #string,\%  #bake_constants
//   #compile_time  #filepath  #file  #this  #type,isa  #type,distinct  #insert,scope()  #program_export

#import "Basic";
#import "String";    // ends_with (for the #file suffix check).
#import "Compiler";  // For #caller_code -> compiler_get_nodes / Code_Node.

// ---------------------------------------------------------------------------
// #scope_module / #scope_export : file-scope visibility control.
// You may use #scope_module even in a main program (how_to/151). A symbol under
// #scope_module is still visible within the same file, so we can assert on it.
// ---------------------------------------------------------------------------
#scope_module
module_scoped_value := 99;

#scope_export

// ---------------------------------------------------------------------------
// #exists : compile-time test of whether a symbol is declared/visible.
// Works on undeclared identifiers (that is the whole point) without an error.
// ---------------------------------------------------------------------------
#assert #exists(module_scoped_value);
#assert !#exists(never_declared_symbol_zzz);

// ---------------------------------------------------------------------------
// #run,host : run a procedure in the HOST (metaprogram) context at compile time.
// In a normal, non-cross-compiling build it just runs like any other #run.
// ---------------------------------------------------------------------------
HOST_VALUE :: #run,host -> int { return 42; };

// ---------------------------------------------------------------------------
// #run,stallable : a compile-time #run that is allowed to stall on compiler
// messages. As an expression it still yields a constant.
// ---------------------------------------------------------------------------
STALLABLE_VALUE :: #run,stallable -> int { return 7; };

// ---------------------------------------------------------------------------
// #compile_time : marks a procedure that may only run at compile time.
// ---------------------------------------------------------------------------
triple_ct :: (x: int) -> int #compile_time { return x * 3; }
TRIPLED :: #run triple_ct(14);
#assert TRIPLED == 42;

// ---------------------------------------------------------------------------
// #type,isa / #type,distinct : type variants.
//   #type,isa   implicitly converts to its base type.
//   #type,distinct does NOT implicitly convert (needs an explicit cast).
// ---------------------------------------------------------------------------
My_Length :: #type,isa int;
Handle    :: #type,distinct u32;

takes_int :: (x: int) -> int { return x + 1; }

// ---------------------------------------------------------------------------
// #bake_constants : produce a concrete procedure by fixing polymorphic const args.
// ---------------------------------------------------------------------------
add_typed :: (a: $T, b: T) -> T { return a + b; }
add_ints  :: #bake_constants add_typed(T = int);

// ---------------------------------------------------------------------------
// #procedure_of_call : the exact (possibly polymorphic) procedure a call resolves to.
// ---------------------------------------------------------------------------
square_poly :: (x: $T) -> T { return x * x; }
square_f64  :: #procedure_of_call square_poly(5.0);  // The float64 instantiation.

// ---------------------------------------------------------------------------
// #procedure_name : name of the enclosing procedure as a string.
// ---------------------------------------------------------------------------
whoami :: () -> string {
    return #procedure_name();
}

// ---------------------------------------------------------------------------
// #this : the enclosing procedure/struct as a compile-time constant.
// Here it makes a named procedure self-referential (recursion without the name).
// ---------------------------------------------------------------------------
count_down :: (n: int) -> int {
    self :: #this;
    if n <= 0  return 0;
    return 1 + self(n - 1);
}

// ---------------------------------------------------------------------------
// #caller_code : as a macro-arg default, becomes the Code of the invoking call,
// inspectable with the Compiler module at compile time.
// ---------------------------------------------------------------------------
Inspect :: (args: .. Any, call := #caller_code) #expand {
    #run {
        nodes := compiler_get_nodes(call);
        assert(nodes.kind == .PROCEDURE_CALL);  // Build fails if the shape is wrong.
    }
}

// ---------------------------------------------------------------------------
// #insert,scope() : insert Code that is allowed to reference the current scope
// (the ,scope() breaks macro hygiene so `code` can see `scratch`).
// ---------------------------------------------------------------------------
with_scratch :: (code: Code) -> int #expand {
    scratch := 100;
    #insert,scope() code;   // `code` may read/write `scratch`.
    return scratch;
}

// ---------------------------------------------------------------------------
// #program_export : expose the symbol as a visible entry point (how_to/400).
// Harmless in an executable; still callable normally.
// ---------------------------------------------------------------------------
#program_export
exported_answer :: () -> int {
    return 42;
}

// ---------------------------------------------------------------------------
// #string,cr : here-string whose line endings are normalized to \r\n.
// Content is verbatim from column 0, so CR_TEXT == "line one\r\n".
// ---------------------------------------------------------------------------
CR_TEXT :: #string,cr END
line one
END

// ---------------------------------------------------------------------------
// #string,\% : here-string that honors the \% escape (literal percent), so the
// bare % stays a format placeholder.  Content == "%\% ready\n".
// ---------------------------------------------------------------------------
PCT_TEMPLATE :: #string,\% END
%\% ready
END

main :: () {
    // #scope_module symbol visible in-file.
    assert(module_scoped_value == 99);

    // #exists as a runtime-usable compile-time bool.
    present := #exists(module_scoped_value);
    absent  := #exists(never_declared_symbol_zzz);
    assert(present);
    assert(!absent);

    // #run,host and #run,stallable produced compile-time constants.
    assert(HOST_VALUE == 42);
    assert(STALLABLE_VALUE == 7);

    // #compile_time result folded in.
    assert(TRIPLED == 42);

    // #type,isa implicitly downcasts to int for the call; #type,distinct needs a cast.
    len: My_Length = 5;
    assert(takes_int(len) == 6);
    h: Handle = 5;
    assert(cast(u32) h == 5);

    // #bake_constants gave a concrete (int,int)->int procedure.
    assert(add_ints(3, 4) == 7);

    // #procedure_of_call resolved the float64 instantiation.
    assert(square_f64(4.0) == 16.0);

    // #procedure_name.
    assert(whoami() == "whoami");

    // #this self-recursion.
    assert(count_down(5) == 5);

    // #caller_code : the macro's compile-time #run asserted the call shape.
    Inspect(1, 2, 3);

    // #insert,scope() : inserted code mutated the macro-body local `scratch`.
    v := with_scratch(#code { scratch += 23; });
    assert(v == 123);

    // #program_export symbol is still an ordinary callable.
    assert(exported_answer() == 42);

    // #location : a compile-time Source_Code_Location struct literal.
    loc := #location();
    assert(loc.line_number > 0);
    assert(loc.fully_pathed_filename.count > 0);

    // #filepath (directory) and #file (full path) are non-empty strings.
    assert(#filepath.count > 0);
    file := #file;
    assert(ends_with(file, "31_directives_extra.jai"));

    // #string,cr : \r\n line endings ("line one" is 8 chars; index 8 is \r).
    assert(CR_TEXT.count == 10);
    assert(CR_TEXT[8] == 13);  // '\r'
    assert(CR_TEXT[9] == 10);  // '\n'

    // #string,\% : the \% became a literal percent; the bare % took the argument.
    rendered := tprint(PCT_TEMPLATE, 90);
    assert(rendered == "90% ready\n");

    print("PASS: 31_directives_extra (residual directives: #run,host  #run,stallable  #scope_module\n");
    print("      #scope_export  #exists  #compile_time  #type,isa  #type,distinct  #bake_constants\n");
    print("      #procedure_of_call  #procedure_name  #this  #caller_code  #insert,scope()\n");
    print("      #program_export  #location  #filepath  #file  #string,cr  #string,\\\%)\n");
}
