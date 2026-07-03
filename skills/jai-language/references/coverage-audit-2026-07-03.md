# Cheatsheet ↔ compendium coverage audit — beta 0.2.030 (2026-07-03)

> **RESOLVED (2026-07-03).** This audit drove the "close everything first" closure (see
> `coverage-closure-plan-2026-07-03.md`): all PARTIAL/NO-PROOF sections below were closed with new
> or extended compendium proofs and promoted to `compile-verified`. Kept as the historical record
> of what the audit found (including the dead-code / decoy quality bugs, now fixed).

Per-section audit of whether a compendium file actually **compile-proves** each cheatsheet
section, to justify promoting its banner from `inspection-only` to `compile-verified`.
Rule applied: a construct is "covered" only if exercised in real, non-comment CODE in a
compendium file that compiles clean; comment-only / declared-but-unexercised does NOT count.

## Verdict summary (26 banners)

| Verdict | Count | Banners |
|---|---|---|
| PROMOTE (clean) | 2 | Rotate Operators; Prefix Dereference (deprecated) |
| PARTIAL (core proven, advanced/rare tail unproven) | 19 | Declarations, Procedures, Operator Overloading, Types, Structs, Struct/Array Literals, Enums, Unions, Control Flow, Loop-Body Directives, Standalone #no_aoc, Directives (##), Type Variants, Code Literals, Module Parameters, Operators (##), Special Syntax, Escape Sequences, Context System |
| NO-PROOF (needs new code) | 5 | Number Literals, #elsewhere, AST Rewriting, Metaprogramming Directives (#poke_name), Comments |

## Clean promotions (apply now)

- **### Rotate Operators** → `compendium/13` — both `<<<`/`>>>` exercised (13:16-19). Complete.
- **### Prefix Dereference (DEPRECATED)** → `compendium/08, 13` — modern `.*` amply proven
  (08:61, 13:30, +06/11/20/01); deprecated `<<ptr` form intentionally not exercised.

## NO-PROOF — cheap to close (quick wins → new/extended proof)

- **### Number Literals** — only bare decimal int/float exercised anywhere. Missing: hex `0x`,
  binary `0b`, hex-float `0h`, underscores `1_000_000`, scientific `1e10`, trailing-dot `2340.`.
  (hex exists in 13/16 but not as a literals demo.) → tiny new demo file.
- **## Escape Sequences** — 4/12 proven in 17 (`\n \t \" \d`). Missing: `\r \0 \e \\ \/ \% \x \u \U`.
- **## Comments** — only trivial `//`. Missing: block `/* */`, nested `/* /* */ */`, `//` inside a
  string literal (the Tree-Sitter note). → tiny new demo file.
- **## Operators (##)** — cheap adds to 08: modulo `%`, bitwise `& ^ ~`, logical `|| !`, plain `>>`,
  compound-assign family (`-= /= %= &= |= ^= <<= >>=`).

## PARTIAL — core proven, notable gaps (candidate file[s] → gap)

- **## Declarations** → 01 (+16,18): `#no_reset`; `name=,` assign-override; 3-position mixed capture; `_:,` in `=` context.
- **## Procedures** → 02,10 (+16): modifier zoo (`#c_call #symmetric #no_debug #deprecated #compiler #compile_time #cpp_* #no_alias #intrinsic #dump`), all `#foreign` forms, `using`-params, `#discard`, `..Any` variadic, `$T/interface`, `$T/.[list]`, `=>` lambda, call-site inline.
- **## Operator Overloading** → 08 (+13): `operator []`, `operator []=`, unary `!`, compound-assign operators, named-import re-export (`operator- :: Basic.operator-`).
- **## Types** → 06 (+10,20,23): `u16..u64`/`s8..s64`, `#type,isa`, `$T/interface`, `initializer_of`. (Several "gaps" — `$T`, `is_constant`, `Table`, `Type_Info_Struct.alignment` — ARE proven, in non-candidate files 10/20/23 → multi-file linkage.)
- **## Structs** → 04,14,23: `using,only`/`,map`/`,except NAMES`, `#as using` (in-candidate), all three `#type_info_*`, `#modify`-on-struct exercised, struct-field `= ---`, in-body field override.
- **## Struct/Array Literals** → 04 (+03,06,17): indexed/mixed field init, non-dot `return {}`, nested non-dot, `if x == {}`.
- **## Enums** → 05: `enum #specified` is DEAD CODE (declared, never used); `using enum` scope-promotion absent.
- **## Unions** → 15 (+19): polymorphic `union(params){}`, `tagged_union_bindings` reflection walk, multi-field wrapper workaround.
- **## Control Flow** → 03,16 (+12,17,20): conditional for-modifiers, named `for :iter`, labeled `continue`, `#through`, `#ifx`, braced `defer {}`, most backtick-macro keyword remaps.
- **### Loop-Body Directives** → 13: order-flexibility (`for < *` vs `for <*`) unproven.
- **### Standalone #no_aoc** → 16,13: `} else #no_aoc {}` variant unproven.
- **## Directives (##)** → 07,12,13,16,22: ~18 of ~45 directives proven; large families unproven (`#load`, `#foreign`, `#library`, `#asm`, `#bytes`, `#module_parameters`, `#add_context`, `#placeholder`, most Introspection directives).
- **### Type Variants** → 06: only bare `#type,distinct` decl; `#type,isa` entirely unproven; no distinct-type introspection/cast/math tests.
- **### Code Literals** → 12: basic `#code` block/expr/`,null` proven; `#code,typed`, `Code.type`, `#code x = expr` unproven.
- **### Module Parameters** → 22: structural-acceptance idiom proven; the `#module_parameters (a)(b)` directive itself never compiled anywhere.
- **## Special Syntax** → 09,13,18: `,,` allocator override is a DECOY (09:38-42 claims it, doesn't use `,,`); backtick break; backslash identifiers; `@selector`; 5 of 6 `using,except`/`only`/`map` variants.
- **## Context System** → 16,21: core + handoff solid; `#add_context`, `context.stack_trace` unproven.

## NO-PROOF — hard / large (deferred backlog)

- **### Compile-Time AST Rewriting** — the whole `compiler_get_nodes → walk/mutate → #insert`
  mechanism is undemonstrated. High value, non-trivial to author a minimal compiling demo.
- **### Metaprogramming Directives** — `#poke_name` unproven (+ a removal note that documents an absence).
- **### External Declarations (#elsewhere)** — all 4 forms comment-only; the compendium author's
  own header states it "cannot be demonstrated in a self-contained compilable example."

## Compendium QUALITY bugs found (fix regardless of promotion policy)

1. **`,,` decoy** — `09_special_syntax.jai:38-42` comments that it shows the comma-comma allocator
   override, then does `arr.allocator = context.allocator;` instead. The claimed demo doesn't use `,,`.
2. **Dead-code declarations** (declared, never exercised → prove nothing): `Protocol :: enum #specified`
   (05_enums.jai:20); `Wrapper` `#modify`-on-struct (10_polymorphism.jai:57-64, never instantiated);
   `PackedData` `#no_padding` is non-generic so at least fully typechecked, borderline.

## Structural lessons

- **Linkage must be multi-file.** A section's proof is frequently spread across several compendium
  files; the `compile-verified` banner should be able to cite `compendium/NN, MM`.
- **The compendium proves each section's common CORE, not its full breadth.** Under a strict
  "prove ~everything" rule only 2/26 promote. The tail is mostly advanced/rare/deprecated/exotic.
