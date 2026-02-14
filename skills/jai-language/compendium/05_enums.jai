// Compendium: Enums
// Jai Version: beta 0.2.025
// Platform: Linux x86-64
// Sources: how_to/013_enums.jai, how_to/014_enum_unary_dot.jai
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

    // Enum introspection
    print("\nColor values:\n");
    for enum_values_as_s64(Color) {
        print("  %: %\n", it, cast(Color) it);
    }

    low, high := enum_range(Color);
    print("Color range: % to %\n", low, high);

    names := enum_names(Color);
    print("Color names: %\n", names);
}
