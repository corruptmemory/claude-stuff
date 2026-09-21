// Compendium: #no_aoc = no ARITHMETIC OVERFLOW CHECK (not "output capture"),
//   and the check fires on UNSIGNED wraparound too
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: empirically established against the beta 0.2.030 compiler (2026-09-20),
//   after a textbook u32 LCG (`seed = seed*1664525 + 1013904223`) panicked a build
//   that had set arithmetic_overflow_check = .FATAL. The cheatsheet glossed #no_aoc
//   as "no automatic output capture" in two places, which sent the search the wrong
//   way entirely. Cross-checked against modules/Compiler/Compiler.jai:124 (the
//   Build_Options field and its default) and modules/Hash.jai / modules/Basic/Int128.jai
//   (the distribution's own uses, all of them wrapping hash/bignum arithmetic).
// Proves (cheatsheet): Procedure Directives (#no_aoc), Loop-Body Directives,
//   Standalone #no_aoc / #no_abc Block Statements
// Compile + run (the metaprogram is REQUIRED — see below):
//   ~/jai/jai/bin/jai-linux build.jai
//   ./no_aoc_proof
//
// THE RULE, in three parts:
//
// 1. `#no_aoc` means "no arithmetic overflow check". Nothing to do with output
//    capture. It comes in three forms, all exercised below: a PROCEDURE directive,
//    a for-loop modifier between the iterable and the body, and a STANDALONE block.
//
// 2. The check it suppresses is OFF BY DEFAULT. `Build_Options.arithmetic_overflow_check`
//    is an `enum u8 { OFF; NONFATAL; FATAL; } = .OFF` (Compiler.jai:124), and
//    set_optimization never turns it on (Compiler.jai:1755 has the .VERY_DEBUG line
//    COMMENTED OUT and 1760 forces .OFF). So `jai program.jai` wraps silently, and
//    nothing here fails — which is exactly why this entry needs its own build.jai:
//    without one it would "pass" while proving nothing.
//
// 3. When it IS on, it fires on UNSIGNED wraparound as well as signed. This is the
//    part that surprises anyone arriving from C, where unsigned wraparound is
//    defined behaviour and idiomatic. The panic, verbatim (beta 0.2.030, the
//    u32 multiply below with #no_aoc removed):
//
//        Arithmetic overflow. We tried to compute:
//            305419896 * 1664525
//        The operand type is u32, but the result does not fit into this type.
//        Panic.
//        Breakpoint hit. Stack trace:
//        ...(__arithmetic_overflow_...)...
//
//    Exit code 1. It cannot be demonstrated in code that must run clean, so it is
//    quoted rather than executed; everything else here is asserted.
//
// The asserts below are the live half: this file is built with .FATAL, so if
// #no_aoc ever stopped suppressing the check, the RUN panics instead of passing.

#import "Basic";

// ── Form 1: the PROCEDURE directive ──────────────────────────────────────────
// A textbook 32-bit LCG. Every step of it overflows u32 on purpose; that IS the
// algorithm. Without #no_aoc this proc panics under .FATAL.
lcg_next :: (seed: u32) -> u32 #no_aoc {
    return seed * 1664525 + 1013904223;
}

// The same arithmetic done the long way round, in u64 with a fold that keeps the
// product inside the type. No directive needed — and this is the escape hatch
// when you would rather not suppress the check at all.
lcg_next_no_overflow :: (seed: u64) -> u64 {
    return (seed * 1103515245 + 12345) % 0x8000_0000;
}

main :: () {
    // --- Form 1 -------------------------------------------------------------
    // 305419896 * 1664525 + 1013904223, truncated to 32 bits. The expected value
    // is computed here the way the machine does it, in u64, so the assert states
    // the wrapped answer rather than a magic constant.
    SEED :: 0x1234_5678;
    expected := cast(u32) (((cast(u64) SEED) * 1664525 + 1013904223) & 0xFFFF_FFFF);
    assert(lcg_next(SEED) == expected, "#no_aoc proc returned %, want %", lcg_next(SEED), expected);
    assert(expected == 1967335287, "the wrapped value is %, want 1967335287", expected);

    // --- Form 2: the STANDALONE block ---------------------------------------
    // #no_aoc wraps an arbitrary block, not only a loop. This is how
    // modules/Basic/Int128.jai does its limb arithmetic.
    b: u32 = SEED;
    #no_aoc {
        b = b * 1664525;
    }
    assert(b == 953431064, "#no_aoc block produced %, want 953431064", b);

    // --- Form 3: the for-loop modifier --------------------------------------
    // Between the iterable and the body, stacking with #no_abc, exactly as
    // modules/Hash.jai writes it. The hash below overflows on nearly every byte.
    data := u8.[ 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE ];
    h: u32 = 5381;
    for 0..data.count - 1 #no_abc #no_aoc {
        h = (h << 5) + h + data[it];          // djb2; wraps constantly
    }
    // Recomputed in u64 with an explicit mask — same answer, no suppression, so
    // the assert is a cross-check rather than a restatement of the same code.
    h64: u64 = 5381;
    for data  h64 = ((h64 << 5) + h64 + it) & 0xFFFF_FFFF;
    assert(cast(u64) h == h64, "the #no_aoc loop hashed to %, the checked recomputation to %", h, h64);

    // --- The escape hatch ---------------------------------------------------
    // No directive, no wraparound, same kind of generator. Prefer this in code
    // that is not performance-critical: #no_aoc turns the check off for
    // EVERYTHING in its scope, including the mistakes you did not intend.
    s := lcg_next_no_overflow(SEED);
    assert(s < 0x8000_0000, "the folded LCG left the range: %", s);

    // --- What is NOT suppressed ---------------------------------------------
    // #no_aoc covers arithmetic. A CHECKED CAST is a separate mechanism with its
    // own opt-out (`cast,no_check` / `cast,trunc`), and `cast(u8) 300` still
    // traps inside a #no_aoc block. Shown as the WORKING spelling, since the
    // trapping one cannot be in code that must run clean:
    big: s64 = 300;
    #no_aoc {
        truncated := cast,trunc(u8) big;
        assert(truncated == 44, "cast,trunc(u8) 300 gave %, want 44", truncated);
    }

    print("38_arithmetic_overflow_check: all assertions passed (built with arithmetic_overflow_check = .FATAL).\n");
}
