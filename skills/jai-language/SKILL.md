---
name: jai-language
description: "Comprehensive Jai programming language reference and cheat sheet. Use when working with Jai code, tree-sitter-jai grammar development, or answering questions about Jai syntax and semantics. Covers declarations, types, control flow, directives, metaprogramming, and all language features. Trigger: user mentions 'Jai', 'Jai language', 'tree-sitter-jai', or asks about Jai syntax."
---

# Jai Language Reference

Complete reference for the Jai programming language by Jonathan Blow.

The Jai compiler distribution at `~/jai/jai/` contains the authoritative source:
- **how_to/** — 84 `.jai` files across subdirectories covering all features
- **examples/** — Real-world programs
- **modules/** — Standard library

See [references/cheatsheet.md](references/cheatsheet.md) for the full language cheat sheet.
See [compendium/](compendium/) for compilable code samples demonstrating every language feature
(38 entries: 36 single `.jai` files + two subdirectory entries, `30_module_parameters/` and
`38_arithmetic_overflow_check/`).
See [references/build-variables-recipe.md](references/build-variables-recipe.md) for the canonical
metaprogram recipe for custom compile-time build variables (`#placeholder` knobs module +
`Message_Import`-scoped `add_build_string`) — including the beta 0.2.029 gated-`#load` bug the
naive per-file injection hits. Use this recipe whenever a metaprogram needs to feed constants
into target code.

## STANDING RULE: document surprises as you hit them

**Any Jai behaviour that surprises you relative to what this skill already says must be
written down here, in the same pass that discovered it.** Jai is under heavy development
and sparsely documented elsewhere; a surprise you do not record is one the next session
pays for again. Two sessions in a row have lost time to behaviour this skill did not
mention.

What qualifies: anything you had to establish by experiment because the cheatsheet was
silent or wrong, anything whose compiler error names the wrong cause, and anything that
differs from the obvious analogue in Go/C/Odin/Zig.

How to record it:

1. **Tag it with the Jai version you observed it on.** The language changes; an untagged
   claim rots silently and there is no way to tell later whether it was ever true.
2. **Prove it in the compendium** — a new entry, or an addition to a fitting one — that
   both COMPILES and RUNS clean, with asserts that would fail if the behaviour changed.
   Behaviour that cannot be shown in compiling code (a compiler ERROR, say) goes in
   comments with the exact message quoted, since the corpus must compile.
3. **Add it to the cheatsheet** where someone would look for it, not only where it was
   found, and extend that section's banner to name the proving entry.
4. **Prefer strengthening an existing section** over a new one when the topic already
   has a home; a surprise usually means a section was incomplete, not missing.

Recorded this way so far, all beta 0.2.030: `compendium/34` (argument mutability —
scalars are assignable, aggregates are not, and `x := x` is rejected), `compendium/35`
(defer ordering and scope), `compendium/36` (scopes — a bare `{ }` is a real scope;
`#if` and struct-literal braces are not, **including for imports**, which a bare block
DOES scope while a `#if` splices them into the enclosing scope), and `compendium/37`
(array-to-slice conversion — a `*[..]T` satisfies a `*[]T` parameter, a `*[N]T` does not), and
`compendium/38_arithmetic_overflow_check/` (`#no_aoc` = no ARITHMETIC OVERFLOW CHECK — this
cheatsheet had glossed it "no automatic output capture" in two places; the check is `.OFF` by
default in `Build_Options` and fires on UNSIGNED wraparound once turned on). A
sixth went into an EXISTING entry rather than a new one, which the rule prefers:
`compendium/30_module_parameters/` now also proves that the same module can be imported
**twice in one scope** with different group-1 arguments, and that the two instantiations'
types **do not unify** — reported as `incompatible structs (wanted "Box" [module.jai:33],
given "Box" [module.jai:33])`, an error naming neither cause.

**A worked example of why step 2 says "and RUNS":** `compendium/36`'s first draft
compiled clean and failed an assert at runtime, because a hand-counted string length was
wrong. Compiling proves the signatures; only running proves the claim.

## Compendium verification requirement

Every compendium `.jai` file **must compile without errors or warnings** against the current Jai compiler. When updating the skill for a new Jai release:

1. Bump version headers in the cheatsheet and all compendium files.
2. Reconcile changelog changes with skill content (removed features, new syntax, etc.).
3. **Compile every compendium file** with `~/jai/jai/bin/jai-linux <file>.jai` and confirm zero errors.
   Where a file has runtime asserts, **run it too** — compiling proves signatures, running
   proves behavior (both matter: the beta 0.2.030 pass found `Type_Info_Struct.alignment`
   only *runs* wrong, and a formatInt soft-deprecation only by *reading* the module).
4. Clean up build artifacts (`rm -rf .build` in the compendium directory; remove the built
   binaries — they are gitignored but should not linger).

**Subdirectory entries** (two; every other entry is a single `[0-9]*.jai` file compiled directly):
- `30_module_parameters/` — compile its driver with an import dir:
  `~/jai/jai/bin/jai-linux compendium/30_module_parameters/driver.jai -import_dir compendium/30_module_parameters`.
- `38_arithmetic_overflow_check/` — carries its own metaprogram, because what it proves is
  INVISIBLE under the default build (`Build_Options.arithmetic_overflow_check` defaults to
  `.OFF`, and there is no command-line flag for it). Build with
  `~/jai/jai/bin/jai-linux compendium/38_arithmetic_overflow_check/build.jai`, then run the
  `no_aoc_proof` binary it drops beside `build.jai`. Do NOT compile `program.jai` directly:
  it would pass while proving nothing.

Do not mark a version as verified until compilation is confirmed. The compendium is a "known good" corpus — if it doesn't compile, the version stamp is a lie.

## Cheatsheet verification banners (two tiers) + compendium linkage

The cheatsheet's reliability rests on a **robust correspondence** between each section and a
compendium file that *proves it compiles*. Every cheatsheet section carries one banner:

- `<!-- compile-verified: beta X | compendium/NN.jai -->` — the section's constructs are
  exercised by that compendium file, which compiles (and, where it asserts, runs) clean at
  version X. This is the tier we trust for first-pass codegen.
- `<!-- inspection-only: beta X -->` — checked by reading the distribution at version X, not
  compile-proven. The backlog: these await a compendium proof.

**Linkage is bidirectional.** A `compile-verified` banner names its proving `compendium/NN.jai`,
and that file's header carries a `// Proves (cheatsheet): <section(s)>` line. A section may be
promoted to `compile-verified` **only** when a compendium file actually exercises its
constructs (not merely a topically-related file) — a small compendium file cannot compile-verify
a large section it only partially covers; that is overclaiming, the same "stamp is a lie" trap.

**Priority — standard-module quick-refs first.** Module signatures drift independently of
language syntax (beta 0.2.030 alone changed Thread/NewArray/File), so module quick-refs are the
highest-value `compile-verified` targets and must be proven by *calling* the real APIs.

**Coverage status (beta 0.2.030, 2026-07-03): the per-section audit + closure is COMPLETE.**
Every substantive cheatsheet section is now `compile-verified` (27 banners) against a compendium
entry; the audit that drove this lives in `references/coverage-audit-2026-07-03.md` and the closure
worklist in `references/coverage-closure-plan-2026-07-03.md`. The only `inspection-only` banner left
is **Tree-Sitter Grammar Issues** — parser-development notes, not a claim about compiling Jai, so it
has no compendium proof by design.

**Multi-artifact constructs — proven by a DISTRIBUTION EXAMPLE (the third proof source).** A few
constructs can't be demonstrated in our single-file corpus (they need a metaprogram / companion /
external link unit), but the Jai distribution ships multi-artifact examples that DO demonstrate them.
Citing such an example is a legitimate, lighter proof — provided we CONFIRM it still compiles against
the current version (verified for beta 0.2.030, in scratch copies so the distribution is untouched):
- `#placeholder` → `how_to/460_code_browsing_and_generation/` (build via `first.jai`) +
  `examples/add_build_string_into_specific_scope/` (`build.jai`); recipe in `build-variables-recipe.md`.
- `#load` → `how_to/040_import_and_load/main.jai`.
- `#elsewhere` forms 2–4 → `examples/dll/` (`build.jai`, builds a real `.so`).

Do NOT assume a shipped example compiles — `examples/module_info.jai` compiles with a **deprecation
warning** at 0.2.030. So the cited examples are part of the release checklist too: re-compile each on
every version bump (scratch copies; compile-only is enough — they need no run for signature proof).

**A fourth proof source — LIVE-VERIFIED against a real program.** A few claims are about
what the TOOLCHAIN does, not what the language accepts, so no compendium entry can assert
them: the corpus proves behaviour with runtime asserts, and "gdb can break here" is not a
runtime assert. These carry `verified live: beta X | <date>` in the cheatsheet and need a
re-verification RECIPE instead of a compile, or they rot silently. Recorded so far:

- **Generated code is readable and debuggable** (beta 0.2.030, 2026-09-20). Re-verify:
  1. Build any project that uses `#insert` with multi-statement expansions, then read
     `<build-dir>/.added_strings_w<N>.jai` — every expansion and `add_build_string`, each
     headed with its origin file and line.
  2. `readelf --debug-dump=rawline <bin> | grep added_strings` — the generated file must
     appear in the DWARF file table. **A small expansion will NOT appear** (it folds into
     the `#insert` call site), so use a real one; a toy test reports the wrong answer.
  3. `gdb -batch -q -ex "directory <build-dir>" -ex "break .added_strings_w<N>.jai:<line>"
     -ex run --args <bin>` — the breakpoint must resolve AND hit, and `bt` must show a
     backtrace mixing generated and hand-written frames.
- **`modules/Check` is a default-on plugin** (beta 0.2.030, 2026-09-20). Re-verify:
  compile `print("% and %\n", 1);` — it must be a COMPILE error naming the arity; the
  same file with `-no_check` must compile and fail at runtime instead.
- **`for_expansion` macros need `-debug_for` to be steppable** (beta 0.2.030, 2026-09-20).
  Re-verify: break on a `for` over a type with a `for_expansion`, `step`, and confirm it
  skips the macro body by default and enters it when built with `-debug_for`.

**Still unverified here** (no self-contained example ships): `#cpp_method` /
`#cpp_return_type_is_non_pod` — only used inside platform module bindings (`modules/d3d11`,
`modules/Windows`, `modules/Check`), which don't build standalone on this box. Genuinely open.
All of the above are noted at their cheatsheet banners.

**When the audit found errors** (this is the payoff — the proofs are a bug-finder): the beta 0.2.030
closure corrected three cheatsheet mistakes (`\/` is not a valid escape; `` `break ``/`` `continue ``/
`` `remove `` are not backtickable — only `defer`/`return`/`push_context`/operators are; a `,,`
allocator-override "demo" that didn't use `,,`) and recorded two real 0.2.030 behaviors (compound
assignment through `[]`/`[]=` calls only the SET overload; `Type_Info_Struct.alignment` is only
partially populated). Re-run the corpus each release and expect it to keep finding drift.
