// Compendium: Foreign bindings + inline assembly + raw bytes
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Proves (cheatsheet): ## Directives (#library,system, #foreign, #asm, #bytes);
//                      ## Procedures (#foreign)
// Sources: how_to/095_static_if.jai (`libc :: #library,system "libc"` + `#foreign`),
//          how_to/900_inline_assembly.jai (#asm blocks, register mapping),
//          modules/Runtime_Support.jai (#bytes raw machine-code emission),
//          cheatsheet.md ## Directives (#library / #library,system / #foreign / #asm / #bytes)
// Use-cases: bind a PURE libc function via `#library,system` + `#foreign` and CALL it
//   (result asserted, so a broken binding/signature fails at runtime); an inline `#asm`
//   block that computes into a high-level variable (add + bitwise-or, results asserted);
//   and `#bytes` raw machine-code emission (a single x86-64 NOP — proves the directive
//   compiles and the emitted byte executes harmlessly). This file links libc at runtime
//   (so does Basic) — ldd-cleanliness is a concern for the GAME, never for this language
//   corpus, which is free to exercise the real dynamic loader.

#import "Basic";

// ── #library,system + #foreign ─────────────────────────────────────────────────
// `#library,system` names a library the SYSTEM already provides (resolved by the
// dynamic loader at link/runtime — no path, no vendored .so). libc is the canonical one.
libc :: #library,system "libc";

// A #foreign procedure declaration: normal Jai signature + `#foreign <library>`.
// C's `int toupper(int c)` / `int tolower(int c)` are PURE (ASCII, locale "C") and
// trivially assertable. C `int` is 32-bit on this ABI, so s32 in and s32 out.
toupper :: (c: s32) -> s32 #foreign libc;
tolower :: (c: s32) -> s32 #foreign libc;

main :: () {
    // ── Call the foreign functions; assert exact results ───────────────────────
    // #char "a" is the integer code point 97; toupper maps it to 65 == #char "A".
    assert(toupper(#char "a") == #char "A");
    assert(toupper(#char "z") == #char "Z");
    assert(tolower(#char "Q") == #char "q");
    // Non-letters pass through unchanged (the C contract), which we also pin.
    assert(toupper(#char "5") == #char "5");
    print("foreign libc: toupper('a')=% tolower('Q')=%\n", toupper(#char "a"), tolower(#char "Q"));

    // ── #asm block — add ───────────────────────────────────────────────────────
    // The high-level variable is mapped into a gpr for us; `add a, b` does a += b.
    a := 20;
    b := 22;
    #asm {
        add a, b;   // a = a + b  (register-mapped by the compiler)
    }
    // Copy to a fresh local before the assert: printing/&-taking `a` would force it
    // to memory (the how_to/900 gotcha); the copy keeps `a` register-eligible.
    sum := a;
    assert(sum == 42);

    // ── #asm block — bitwise OR with an immediate ──────────────────────────────
    flags := 0b1100;
    #asm {
        or flags, 0b0011;   // flags |= 3  ->  0b1111
    }
    or_result := flags;
    assert(or_result == 0b1111);
    print("asm: 20+22=% ; 0b1100|0b0011=0b%\n", sum, formatInt(or_result, base = 2));

    // ── #bytes — raw machine-code emission ─────────────────────────────────────
    // Emits opaque bytes straight into the instruction stream. 0x90 is the x86-64
    // NOP — a valid, side-effect-free instruction, so control flows right past it.
    // The reachable code AFTER it proves the emitted byte both compiled and ran.
    reached_after_bytes := false;
    #bytes .[0x90];   // NOP
    reached_after_bytes = true;
    assert(reached_after_bytes);

    print("PASS: #library,system + #foreign (libc toupper/tolower), #asm (add/or), #bytes (NOP)\n");
}
