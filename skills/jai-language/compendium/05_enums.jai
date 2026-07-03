// Compendium: Enums
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/013_enums.jai, how_to/014_enum_unary_dot.jai, how_to/042_using.jai
// Use-cases: basic enum, backing type, explicit values, enum_flags,
//   #specified, #complete, using enum, unary dot, enum introspection

#import "Basic";

// Basic enum
Direction :: enum { NORTH; SOUTH; EAST; WEST; }

// Enum with backing type + explicit values
Color :: enum u8 { RED; GREEN :: 5; BLUE; }

// Enum with flags (bitwise)
Flags :: enum_flags u32 { READ; WRITE; EXEC; }

// #specified: all values must be explicit (prevents accidental renumbering)
Protocol :: enum #specified { HTTP :: 1; HTTPS :: 2; FTP :: 3; }

// #complete: switches must be exhaustive (compile error if case missing)
Shape :: enum #complete { CIRCLE; SQUARE; TRIANGLE; }

// Using enum (anonymous, promotes values to enclosing scope)
Mode :: enum u16 { NONE; SOME :: 5; ALL; }

main :: () {
    // Basic usage
    d := Direction.NORTH;
    print("direction = %\n", d);

    // Unary dot (type-inferred)
    c : Color = .RED;
    print("color = %\n", c);

    // Enum flags: combine with |, test with &
    perms := Flags.READ | .WRITE;
    print("perms = %\n", perms);
    if perms & .READ  print("  readable\n");

    // #complete forces exhaustive switch
    s := Shape.CIRCLE;
    if #complete s == {
        case .CIRCLE;   print("circle\n");
        case .SQUARE;   print("square\n");
        case .TRIANGLE; print("triangle\n");
    }

    // #specified: actually USE Protocol (not just declare it). #specified means
    // every value must be given explicitly (how_to/013_enums.jai's serialization
    // argument: an author who marks an enum #specified is promising the integer
    // values stay stable across time, so they can be safely serialized as-is).
    // Prove it isn't a no-op comment two ways: (1) the value round-trips to the
    // integer the author wrote, and (2) the compiler really set the SPECIFIED
    // bit in the enum's Type_Info -- the same flag how_to/013_enums.jai's
    // is_enum_specified() reads.
    proto := Protocol.HTTPS;
    print("protocol = % (%)\n", proto, cast(int) proto);
    assert(proto == .HTTPS);
    assert(cast(int) proto == 2);

    proto_info := type_info(Protocol);  // type_info() downcasts to *Type_Info_Enum for a known enum type.
    assert((proto_info.enum_type_flags & .SPECIFIED) != 0);

    // using enum: promotes an enum's member names into the enclosing scope, so
    // they can be referred to unqualified (no 'Mode.' prefix needed). Scoped to
    // a block so the promoted names (NONE/SOME/ALL) don't leak past this demo.
    {
        using Mode;

        m := SOME;  // Unqualified -- only resolves because of 'using Mode' above.
        assert(m == Mode.SOME);
        assert(cast(u16) m == 5);

        m = ALL;
        assert(cast(u16) m == 6);
        print("mode (using-promoted) = %\n", m);
    }

    // Enum introspection
    print("\nColor values:\n");
    for enum_values_as_s64(Color) {
        print("  %: %\n", it, cast(Color) it);
    }

    low, high := enum_range(Color);
    print("Color range: % to %\n", low, high);

    names := enum_names(Color);
    print("Color names: %\n", names);

    print("PASS: enums (#specified proven live via Protocol + Type_Info_Enum.enum_type_flags; using-enum scope promotion proven live via Mode)\n");
}
