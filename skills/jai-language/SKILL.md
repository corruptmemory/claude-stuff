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
(37 entries: 36 single `.jai` files + the `30_module_parameters/` subdirectory entry).
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
(array-to-slice conversion — a `*[..]T` satisfies a `*[]T` parameter, a `*[N]T` does not).

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

**Subdirectory entry:** `30_module_parameters/` is not a single file — compile its driver with an
import dir:
`~/jai/jai/bin/jai-linux compendium/30_module_parameters/driver.jai -import_dir compendium/30_module_parameters`.
(Every other entry is a single `[0-9]*.jai` file compiled directly.)

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
