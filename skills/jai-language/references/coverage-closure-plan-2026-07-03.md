# Coverage-closure plan — "close everything first" (beta 0.2.030, 2026-07-03)

> **STATUS: COMPLETE (2026-07-03).** All 21 implementation tasks landed; every substantive
> cheatsheet section is `compile-verified` (27 banners); the full 33-entry corpus compiles AND
> runs clean. Residual (structurally multi-artifact) exceptions documented at their banners and in
> SKILL.md: `#placeholder`, `#cpp_method`, `#load`, `#elsewhere` forms 2–4. `#poke_name` and
> `#elsewhere` (form 1) turned out to be self-containable after all (the prior "impossible" claim
> was wrong).

Goal: extend/add compendium files so every cheatsheet section's constructs are exercised in
real, compiling, running code — then promote all banners to `compile-verified`. Gate per task:
the file COMPILES AND RUNS clean (`jai-linux <file>.jai` → run binary, rc 0). Source of gaps:
`coverage-audit-2026-07-03.md`.

One task per TARGET FILE (so tasks never collide on a file → parallel-safe). Each new/extended
file must add a `// Proves (cheatsheet): <section(s)>` header line.

## NEW files
- [x] N1 `25_number_literals.jai` — hex `0x`, binary `0b`, hex-float `0h`, underscores, scientific, trailing-dot; assert each value. → Number Literals
- [x] N2 `26_escape_sequences.jai` — `\r \0 \e \\ \/ \% \x \u \U` (+ \n \t \" \d); assert byte values / decoded lengths. → Escape Sequences
- [x] N3 `27_comments.jai` — block `/* */`, nested `/* /* */ */`, `//` inside a string literal, wrapped around real asserted code. → Comments
- [x] N4 `28_foreign_and_asm.jai` — `#library,system "libc"` + `#foreign` a libc fn (e.g. `getpid`) called+asserted; inline `#asm` block computing a value + assert; `#bytes` if feasible. → Directives(#foreign/#library/#asm/#bytes), Procedures(#foreign)
- [x] N5 `29_metaprogramming.jai` — `#import "Compiler"`; `compiler_get_nodes` walk of a `#code` + inspect root; `#code,typed`, `Code.type`/`get_root_type`; `#add_context` field + push + read; `#poke_name` if feasible. → AST Rewriting, Code Literals(gaps), Context System(#add_context), Metaprogramming Directives
- [x] N6 `30_module_parameters/` (subdir: `driver.jai` + `param_module/module.jai`) — two-group `#module_parameters (a)(b)`, program-Type injection via `#add_context`, per-import values; verify with `-import_dir`. → Module Parameters
- [x] N7 `31_directives_extra.jai` — single-file-demonstrable `##Directives` residuals: `#run,host`, `#run,stallable`, `#scope_module`, `#exists`, `#location`, `#caller_code`, `#procedure_name`, `#string,cr`, `#bake_constants`, `#type,isa` cross-ref, etc. Sweep as many as compile. → Directives (##)
- [x] N8? `#elsewhere` — INVESTIGATE self-containment (companion link unit?). If impossible, leave inspection-only with a documented permanent-exception reason. → External Declarations

## EXTENSIONS (one task per existing file)
- [x] E01 `01_declarations.jai` — `#no_reset`; `name=,` assign-override; 3-position mixed capture; `_:,` in `=` context.
- [x] E02 `02_procedures.jai` — proc-modifier set (`#c_call #symmetric #no_debug #no_alias #deprecated #compile_time #dump #no_context` — the demonstrable ones); `using`-params (plain/`#as`/`,except`); `#discard`; `..Any` variadic; `$T/interface`; `$T/.[list]`; `=>` lambda; call-site `inline`/`no_inline`.
- [x] E03 `03_control_flow.jai` — conditional for-modifiers; named `for :iter`; labeled `continue`; `#through`; `#ifx`; braced `defer {}`; backtick `break`/`continue`/`defer`/`remove` inside `#expand`.
- [x] E04 `04_structs.jai` — `using,only`/`,map`/`,except NAMES`; `#as using` in-file; `#type_info_none`/`_procedures_are_void_pointers`/`_no_size_complaint`; `#modify`-on-struct instantiated; struct field `= ---`; in-body base-field override.
- [x] E05 `05_enums.jai` — `using enum` scope-promotion; make `Protocol` (`#specified`) live; make `Mode` (`using enum`) live. (fixes dead-code bug)
- [x] E06 `06_types.jai` — `u16/u32/u64/s8/s16/s32/s64`; `#type,isa` subtype + downcast; `$T/interface`; distinct-type introspection (cast/`xx`/math/type_info variant). → Types, Type Variants
- [x] E08 `08_operators.jai` — `operator []`/`[]=`/`*[]`/ unary `!` overloads; named-import re-export; modulo `%`, bitwise `& ^ ~`, logical `||`, plain `>>`, compound-assign family. → Operator Overloading, Operators
- [x] E09 `09_special_syntax.jai` — FIX the `,,` decoy → a REAL comma-comma allocator override; backtick `break`; `using,except NAMES`/`.[list]`/`#run`; `using,only`; `using,map`; `@selector` variants if demonstrable. (fixes decoy bug)
- [x] E13 `13_advanced_operators.jai` — loop-body directive order flexibility (`for < *` and `for <*`).
- [x] E15 `15_language_evolution.jai` — polymorphic `union(params){}` + instantiation; `tagged_union_bindings` reflection for-loop with dispatch.
- [x] E16 `16_return_capture_and_blocks.jai` — `} else #no_aoc {}` variant.

## After all tasks
- [x] Fix any remaining quality bugs; re-audit spot-check that new demos EXERCISE (not just mention) their constructs.
- [x] Promote every now-covered banner to `compile-verified: beta 0.2.030 | compendium/NN[,MM]` (multi-file where needed). Any residual (e.g. #elsewhere, ##Directives long tail) stays inspection-only with a one-line documented reason.
- [x] Full corpus compile+run; clean artifacts; bump SKILL.md compendium count; update the audit doc statuses.
- [x] Commit + push.

## Residual-risk notes
- `## Directives` is a ~45-item grab-bag; some (`#load`, `#program_export`, `#placeholder`) need companions/metaprograms — full clean promotion may leave a small documented tail.
- `#elsewhere` may be permanently inspection-only (cross-link-unit by nature).
