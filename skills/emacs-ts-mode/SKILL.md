---
name: emacs-ts-mode
description: "Comprehensive guide for building Emacs tree-sitter major modes. Covers the full treesit.el API, font-lock rules, indentation, navigation, imenu, and best practices distilled from studying 17+ production modes. Use when creating or modifying an Emacs tree-sitter mode (*-ts-mode), working with treesit-font-lock-rules, treesit-simple-indent-rules, or any Emacs tree-sitter integration. Trigger: user mentions 'ts-mode', 'tree-sitter mode', 'treesit', 'font-lock-rules', 'indent-rules', or asks about Emacs tree-sitter major mode development."
---

# Emacs Tree-Sitter Mode Development Guide

Complete reference for building Emacs 29+ tree-sitter major modes, distilled from the Emacs core treesit.el API and 17+ production modes (built-in: go, rust, c/c++, elixir, python, ruby, typescript; third-party: clojure, ada, haskell, scala, templ, swift, zig, and others).

Reference modes are cloned at `~/projects/jai-ts-mode/reference-modes/` for direct study.

Key built-in files to consult:
- `reference-modes/emacs/lisp/treesit.el` — core infrastructure (5835 lines)
- `reference-modes/emacs/lisp/progmodes/go-ts-mode.el` — clean standalone mode
- `reference-modes/emacs/lisp/progmodes/rust-ts-mode.el` — advanced font-lock patterns
- `reference-modes/emacs/lisp/progmodes/c-ts-mode.el` — complex dual-language, preprocessor handling
- `reference-modes/emacs/lisp/progmodes/c-ts-common.el` — reusable C-family utilities

Key third-party modes:
- `reference-modes/clojure-ts-mode/` — best-documented, has doc/design.md
- `reference-modes/ada-ts-mode/` — most feature-complete single-language mode
- `reference-modes/elixir-ts-mode/` — upstreamed to Emacs core, multi-language embedding

See [references/cheatsheet.md](references/cheatsheet.md) for the full API cheatsheet.
