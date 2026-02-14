---
name: tree-sitter-grammar
description: "Comprehensive tree-sitter grammar development guide covering the JavaScript DSL, precedence systems, conflict resolution, external scanners, state explosion mitigation, and best practices distilled from studying 17 reference grammars and the official documentation. Use when building or modifying tree-sitter grammars, debugging parse errors, optimizing parser generation, or understanding tree-sitter internals. Trigger: user mentions 'tree-sitter', 'grammar.js', 'parser generation', 'tree-sitter conflicts', 'external scanner', 'state explosion', or asks about tree-sitter grammar development."
---

# Tree-Sitter Grammar Development Guide

Complete reference for building tree-sitter parsers, distilled from the official tree-sitter documentation (v0.26.x), 17 reference grammars, and practical experience.

Reference grammars cloned at `~/projects/tree-sitter-jai/reference-grammars/` for direct study:
- `tree-sitter/` — Official documentation and source
- `tree-sitter-go/` — Clean baseline (983 lines, 6 prec levels, no scanner)
- `tree-sitter-rust/` — Well-structured (1600+ lines, 15 prec levels, scanner for raw strings)
- `tree-sitter-odin/` — Closest to Jai (960 lines, 11 prec levels, no scanner)
- `tree-sitter-d/` — Feature-rich (2580 lines, scanner for heredocs/delimited strings)
- `tree-sitter-zig/` — Comptime system (named prec levels, 6 conflicts)
- `tree-sitter-c/`, `tree-sitter-cpp/` — C family patterns
- Plus: java, javascript, typescript, python, ruby, elixir, haskell, nickel, swift

See [references/cheatsheet.md](references/cheatsheet.md) for the full development cheatsheet.
