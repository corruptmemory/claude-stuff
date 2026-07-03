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
See [compendium/](compendium/) for compilable code samples demonstrating every language feature (24 files).
See [references/build-variables-recipe.md](references/build-variables-recipe.md) for the canonical
metaprogram recipe for custom compile-time build variables (`#placeholder` knobs module +
`Message_Import`-scoped `add_build_string`) — including the beta 0.2.029 gated-`#load` bug the
naive per-file injection hits. Use this recipe whenever a metaprogram needs to feed constants
into target code.

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

**Deferred (the syntax-gap backlog, tracked as of beta 0.2.030):** the remaining
`inspection-only` sections — Declarations, Procedures, Types, Structs, Enums, Control Flow,
Operators, Special Syntax, Directives, Context, and the smaller Operator Overloading /
Struct-Array Literals / Unions / Escape Sequences / Comments — need per-section coverage
audits linking them to their compendium proof before promotion. Most have a strong candidate
file already (`compendium/01..23`); the audit is confirming coverage, not writing from scratch.
