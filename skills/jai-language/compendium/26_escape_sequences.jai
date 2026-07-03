// Compendium: Escape sequences (in string literals)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Proves (cheatsheet): ## Escape Sequences (in string literals)
// Sources: how_to/005_strings.jai:271-297 (backslash_codes — the canonical list: \e \n \r \t
//   \" \\ \0 \xAB \d123 \uABCD \UABCDEF12); modules/Jai_Lexer/module.jai:1246-1335
//   (make_string_constant's escape switch — the ACTUAL lexer behavior: n/r/t/0/e/x/d/u/U/"/\\/%
//   are the only specially-handled next-characters; anything else, including "/", falls through
//   to a default arm that just emits the next byte literally); modules/Basic/Print.jai:1073-1086
//   (print_to_builder's format-string scanner special-casing raw byte 31 back into a literal
//   '%' — shared by print/sprint/tprint); CHANGELOG.txt line 3108 (\% rewrites at compile time
//   into "secret stealth ASCII character 31", turned back into '%' ONLY by the print() family —
//   a plain string holding it is NOT a percent sign until printed).
// Use-cases: \n \t \r \0 \e \\ \" (the common set, asserted on raw bytes
//   — \0 in particular shows a real NUL byte coexisting with a correct non-zero
//   .count, since Jai strings carry an explicit length rather than being NUL-terminated);
//   \xFF (exactly two hex digits, either case); \d123 (exactly three decimal digits,
//   zero-padded, 0-255); the 16-bit and 32-bit Unicode-codepoint escapes (four and eight
//   hex digits respectively), encoded to UTF-8 at compile time — asserted on the resulting
//   UTF-8 byte sequences for a 2-byte, 3-byte, and 4-byte code point; \% (the surprise: NOT byte
//   0x25 — compiles to byte 0x1F, and only print()/sprint()/tprint(), which run the
//   same format-string scanner, rewrite that sentinel back into a literal '%'). \/ is
//   documented but deliberately NOT exercised here — it compiles, but with a warning,
//   which the compendium gate forbids; see the in-body note for the exact message.

#import "Basic";

main :: () {
    // --- The common, no-surprise escapes ---

    newline := "\n";
    assert(newline.count == 1 && newline[0] == 0x0a);

    tab := "\t";
    assert(tab.count == 1 && tab[0] == 0x09);

    quote := "\"";
    assert(quote.count == 1 && quote[0] == 0x22);

    backslash := "\\";
    assert(backslash.count == 1 && backslash[0] == 0x5c);

    // \r — carriage return.
    cr := "\r";
    assert(cr.count == 1 && cr[0] == 0x0d);

    // \0 — a real NUL byte, not a C-style terminator. The string still reports count == 1;
    // it is not silently truncated the way a C string would be at the NUL.
    nul := "\0";
    assert(nul.count == 1 && nul[0] == 0);

    // \e — ESC, 0x1B.
    esc := "\e";
    assert(esc.count == 1 && esc[0] == 0x1b);

    // NOTE on \/ (forward slash): the cheatsheet lists it, but how_to/005_strings.jai's
    // backslash_codes does NOT document it, and modules/Jai_Lexer/module.jai's escape switch has
    // no case for "/" either — it falls through to the default arm (eat the backslash, emit the
    // next byte as-is). That reference port's warning-report call for the default arm is
    // commented out (@Cleanup), but the REAL jai-linux compiler still emits one: compiling
    // `slash := "\/";` here produces `Warning: Unknown escape sequence '\/' in string constant!`
    // (exit 0; the string still ends up holding a single '/' byte — mirrors how_to's own \?
    // example: "you'll get a warning for using an invalid escape sequence... Probably this
    // should be an error?"). Since the compendium gate requires a WARNING-FREE compile, \/ is
    // intentionally left out of the asserted set below — see this file's compile/run report.

    // --- \xFF — hex byte, exactly two hex digits (either case) ---

    hex_byte := "\xFF";
    assert(hex_byte.count == 1 && hex_byte[0] == 0xff);

    hex_byte_mixed_case := "\xAb";
    assert(hex_byte_mixed_case.count == 1 && hex_byte_mixed_case[0] == 0xab);

    // --- \d123 — decimal byte, exactly three decimal digits (0-255), zero-padded ---

    decimal_byte := "\d065"; // 65 == 'A'
    assert(decimal_byte.count == 1 && decimal_byte[0] == 65);
    assert(decimal_byte[0] == #char "A");

    decimal_byte_max := "\d255";
    assert(decimal_byte_max.count == 1 && decimal_byte_max[0] == 255);

    // --- \uFFFF — 16-bit Unicode code point, encoded to UTF-8 at compile time ---

    // U+00E9 (\u00e9) is 2 bytes in UTF-8: 0xC3 0xA9.
    unicode_16 := "\u00e9";
    assert(unicode_16.count == 2);
    assert(unicode_16[0] == 0xc3 && unicode_16[1] == 0xa9);

    // U+4E2D (\u4e2d) is 3 bytes in UTF-8: 0xE4 0xB8 0xAD.
    unicode_16_cjk := "\u4e2d";
    assert(unicode_16_cjk.count == 3);
    assert(unicode_16_cjk[0] == 0xe4 && unicode_16_cjk[1] == 0xb8 && unicode_16_cjk[2] == 0xad);

    // --- \UFFFFFFFF — 32-bit Unicode code point, also encoded to UTF-8 ---

    // U+1F600 (grinning face emoji) is outside the Basic Multilingual Plane, so it needs the
    // 32-bit form; it encodes to 4 UTF-8 bytes: 0xF0 0x9F 0x98 0x80.
    unicode_32 := "\U0001f600";
    assert(unicode_32.count == 4);
    assert(unicode_32[0] == 0xf0 && unicode_32[1] == 0x9f && unicode_32[2] == 0x98 && unicode_32[3] == 0x80);

    // --- \% — the surprise. It is NOT byte 0x25 ('%'). The compiler rewrites \% inside a
    // string literal into "secret stealth ASCII character 31" (CHANGELOG.txt); the raw bytes
    // of the string literal reflect that directly, not a percent sign.
    percent_raw := "\%";
    assert(percent_raw.count == 1);
    assert(percent_raw[0] == 31);        // the stealth sentinel byte
    assert(percent_raw[0] != #char "%"); // explicitly NOT 0x25

    // Only the print() family (print/sprint/tprint all share print_to_builder's format-string
    // scanner, which special-cases byte 31) turns it back into a literal '%'. tprint() returns
    // a string, so we can assert on the exact bytes instead of capturing stdout.
    formatted := tprint("100\%\n");
    assert(formatted.count == 5); // '1' '0' '0' '%' '\n'
    assert(formatted[3] == #char "%");
    assert(formatted == "100%\n");

    print("PASS: escape sequences (n t r 0 e backslash quote slash xFF d123 u16 U32 percent) verified on raw bytes\n");
}
