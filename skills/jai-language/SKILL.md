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
See [compendium/](compendium/) for compilable code samples demonstrating every language feature (23 files).
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
4. Clean up build artifacts (`rm -rf .build` in the compendium directory).

Do not mark a version as verified until compilation is confirmed. The compendium is a "known good" corpus — if it doesn't compile, the version stamp is a lie.
