// Compendium: Number literals (every lexical form)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Proves (cheatsheet): ## Types -> ### Number Literals
// Sources: how_to/002_number_types.jai (0x/0b/0h/underscores), how_to/003_booleans.jai (0h
//          64-bit form), modules/Basic/tests.jai (0h reinterpret-as-bits pattern)

#import "Basic";

main :: () {
    // Decimal integer (default type is s64 / int).
    decimal := 42;
    assert(decimal == 42);

    // Hexadecimal (0x prefix).
    hex := 0xff;
    assert(hex == 255);

    // Binary (0b prefix).
    binary := 0b1010;
    assert(binary == 10);

    // Hex float bit pattern (0h prefix): the digits are the RAW IEEE-754 bits, not a
    // decimal value. Eight hex digits (32 bits) reinterpret as a float32; the bit
    // pattern 0x3f800000 is exactly 1.0 in IEEE-754 single precision.
    hex_float_32 : float32 = 0h3f80_0000;
    assert(hex_float_32 == 1.0);

    // Sixteen hex digits (64 bits) reinterpret as a float64; 0x3ff0000000000000 is
    // exactly 1.0 in IEEE-754 double precision (mirrors modules/Basic/float_to_string.jai's
    // `bot` table, whose first entry is this same constant).
    hex_float_64 : float64 = 0h3ff0_0000_0000_0000;
    assert(hex_float_64 == 1.0);

    // Underscores for readability (any position, decimal or hex).
    million := 1_000_000;
    assert(million == 1000000);

    hex_underscored := 0xff_ff;
    assert(hex_underscored == 65535);

    // Plain float literal.
    pi := 3.14;
    assert(pi > 3.139 && pi < 3.141);

    // Scientific notation.
    big := 1.0e10;
    assert(big == 10000000000.0);

    small := 1.5e-3;
    assert(small > 0.0014999 && small < 0.0015001);

    // Trailing-dot float: no digits are required after the decimal point.
    zero_float := 0.;
    assert(zero_float == 0.0);

    trailing := 2340.;
    assert(trailing == 2340.0);

    print("PASS: number literals (decimal, hex, binary, hex-float bits, underscores, scientific, trailing-dot)\n");
}
