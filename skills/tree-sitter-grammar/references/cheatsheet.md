# Tree-Sitter Grammar Development Cheatsheet

> **tree-sitter version**: 0.26.5 (cargo install)
> **ABI**: 15 (default with `tree-sitter.json`)
> **Sources**: Official docs, 17 reference grammars
> **Last updated**: 2026-02-15 (Pass 9 — per-rule state profiling, anonymous struct/union in type position research, action budget verification, expression hierarchy feasibility confirmed via cross-grammar comparison)

## Grammar Design Philosophy

These principles are hard-won from 9+ passes of iterative grammar development. They should guide every design decision.

1. **Accepting over Precise** -- Tree-sitter grammars exist for editor highlighting and code navigation, NOT for validation. An "accepting" grammar that assigns approximate highlights to unusual constructs is better than a "precise" grammar that produces ERROR nodes (losing ALL highlighting in the affected region). When in doubt, parse it loosely. The compiler validates; the editor illuminates.

2. **Highlight-Driven Design** -- Every named node must justify its existence by enabling a visually distinct highlight group. If two node types get the same highlight color in practice, they should be one node (see `compile_time_constant`, `intrinsic_call` consolidation patterns). Most editor themes render all keyword sub-groups identically. Separate AST nodes that map to the same `@keyword.directive` are wasted state budget.

3. **Coverage is the Primary Metric** -- File parse success rate matters more than AST accuracy. A grammar that parses 95% of files with approximate trees beats one that parses 80% with perfect trees. ERROR nodes are catastrophic -- they destroy all highlighting in the affected region and propagate unpredictably. Measure success by `tree-sitter parse --quiet` across real codebases, not by AST elegance.

4. **State Budget is Real** -- Every expression alternative costs thousands of parse states. The relationship is highly nonlinear (49 alts = 36K states, 27 alts = 14K states). The 65,535 action entry limit is a hard ABI constraint (`uint16_t`) that cannot be raised. Measure before adding any rule to `_expression` or `_type`. Every named rule that appears there must earn its place with real file-count impact data.

5. **Build Bottom-Up, Not Top-Down** -- When restructuring a grammar, start from a minimal skeleton and build up rather than trying to simplify a complex grammar. Bottom-up gives fast iteration (seconds vs minutes per generate cycle) and lets you discover exactly what each rule costs. A 50-line test grammar can disprove a structural hypothesis in 5 minutes that would take 2 hours to disprove in the full grammar.

6. **Reference Grammar Calibration** -- C++ (a genuinely complex language) has 11,551 states. If your grammar for a simpler language has 3-4x that, the grammar is over-fitted, not the language is over-complex. Study how reference grammars (Go: 1,035 states, Zig: 1,836, Odin: 3,758, D: 8,061) achieve coverage with fewer states. The answer is almost always: fewer expression alternatives, expression hierarchy, and aggressive use of `token(choice(...))`.

## Grammar DSL Core Functions

```javascript
seq(rule1, rule2, ...)           // Sequential (concatenation)
choice(rule1, rule2, ...)        // Alternatives (|)
repeat(rule)                     // Zero-or-more (*)
repeat1(rule)                    // One-or-more (+)
optional(rule)                   // Zero-or-one (?)
field('name', rule)              // Named child for queries
alias(rule, $.new_name)          // Rename rule in tree
token(rule)                      // Combine into single token
token.immediate(rule)            // No whitespace before token
```

## Precedence System

### Parse Precedence (outside `token()`)
```javascript
prec(N, rule)                    // Higher N = tighter binding
prec.left(N, rule)               // Left-associative: a+b+c = (a+b)+c
prec.right(N, rule)              // Right-associative: a=b=c = a=(b=c)
prec.dynamic(N, rule)            // Runtime precedence (with GLR conflicts)
```

### Lexical Precedence (inside `token()`)
```javascript
token(prec(N, /regex/))          // Higher N = preferred token match
```

### Precedence Design (typical range)
| Level | Category | Example |
|-------|----------|---------|
| 17 | Field access | `.field` |
| 16 | Call | `f(args)` |
| 15 | Postfix | `a[i]`, `p.*` |
| 14 | Cast | `cast(T)` |
| 13 | Unary | `-x`, `!x`, `*x` |
| 12 | Multiplicative | `*`, `/`, `%` |
| 11 | Additive | `+`, `-` |
| 10 | Shift | `<<`, `>>` |
| 8-9 | Comparison/Equality | `<`, `==` |
| 5-7 | Bitwise AND/XOR/OR | `&`, `^`, `\|` |
| 3-4 | Logical AND/OR | `&&`, `\|\|` |
| 2 | Range | `..` |
| 1 | Assignment | `=`, `+=` |

Reference ranges: Go uses 6 levels, Rust 15, Odin 11, Zig 11, D 15+.

## Grammar Configuration Fields

```javascript
export default grammar({
  name: 'lang',

  extras: $ => [/\s/, $.comment],        // Tokens allowed anywhere (whitespace, comments)
  word: $ => $.identifier,               // Keyword extraction optimization
  inline: $ => [$._intermediate_rule],   // Collapse intermediate nodes
  supertypes: $ => [$._expression],      // Abstract category nodes for queries

  conflicts: $ => [                      // Intentional GLR ambiguities
    [$.rule_a, $.rule_b],
  ],

  externals: $ => [                      // External scanner tokens
    $.block_comment,
    $._custom_token,
  ],

  rules: {
    source_file: $ => repeat($._item),
    // ...
  },
});
```

## Rule Naming Conventions

| Pattern | Meaning |
|---------|---------|
| `_expression` | Private rule (no visible node, children bubble up) |
| `source_file` | Root node |
| `block` | Scoped content |
| `identifier` | Terminal/leaf node |
| `$.rule_name` | Reference to another rule |

Private rules (`_` prefix) reduce tree depth. Use for intermediate categories.

## Conflict Resolution

### When to declare conflicts
- Two rules can match the same prefix and context doesn't disambiguate
- Expression vs type overlap (e.g., `[]int` as type or expression)
- Pattern vs expression (e.g., JS array pattern vs literal)

### Dynamic precedence with conflicts
```javascript
conflicts: $ => [[$.rule_a, $.rule_b]],

// In rules:
choice(
  prec.dynamic(1, $.rule_a),     // Preferred parse
  prec.dynamic(0, $.rule_b),     // Fallback
)
```

### Braceless body pattern (Jai, etc.)
```javascript
for_statement: $ => prec.dynamic(1, seq(
  'for', field('iterable', $._expression),
  field('body', choice(
    $.block,                           // { ... } is unambiguous
    prec.dynamic(-1, $._statement),    // braceless: ambiguous
  )),
)),

// Must declare conflicts for every possible continuation:
conflicts: $ => [
  [$.for_statement, $.unary_expression, $.call_expression],
  [$.for_statement, $.unary_expression, $.field_expression],
  [$._statement, $.for_statement],
],
```

## External Scanner (scanner.c)

### When to use
- Nested block comments (`/* /* */ */`)
- Context-dependent tokens (Python indent/dedent)
- Configurable delimiters (Rust raw strings, Jai here-strings)
- Opaque blocks (inline assembly)

### 5 Required Functions
```c
void *tree_sitter_LANG_external_scanner_create();
void tree_sitter_LANG_external_scanner_destroy(void *payload);
unsigned tree_sitter_LANG_external_scanner_serialize(void *payload, char *buffer);
void tree_sitter_LANG_external_scanner_deserialize(void *payload, const char *buffer, unsigned length);
bool tree_sitter_LANG_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols);
```

### Scanner Patterns
```c
// Lexer API
lexer->lookahead                       // Current char (Unicode codepoint)
lexer->advance(lexer, false)           // Consume char (skip=true for whitespace)
lexer->mark_end(lexer)                 // Set token boundary
lexer->eof(lexer)                      // Check EOF
lexer->result_symbol = TOKEN_TYPE      // Set token type before return true

// Pattern: nested block comments
int depth = 1;
while (depth > 0 && !lexer->eof(lexer)) {
  if (lexer->lookahead == '/' && peek_next == '*') depth++;
  if (lexer->lookahead == '*' && peek_next == '/') depth--;
  advance(lexer);
}

// Pattern: delimiter matching (here-strings)
// 1. Extract delimiter from input
// 2. Scan until delimiter at start of line
// 3. Use mark_end() before lookahead
```

### Scanner Rules
- External tokens have HIGHEST lexer priority
- Always check `valid_symbols[TOKEN]` before scanning
- Never return zero-width tokens (infinite loop)
- Cannot backtrack after `advance()`
- State serialization max: `TREE_SITTER_SERIALIZATION_BUFFER_SIZE` bytes
- Use `ts_malloc`/`ts_free` (not `malloc`/`free`)

## State Explosion: Causes & Mitigation

### Known Causes
1. **Too many `_expression` alternatives** — THE primary driver. 49 alternatives → 6 min generation. 27 → 58 sec. Highly nonlinear.
2. **struct/enum in `_expression` or `_type`** — Each expression context multiplies states
3. **Overly broad `choice()` with overlapping patterns** — No clear precedence
4. **20+ precedence levels** — Creates exponential state combinations
5. **Too many distinct parser-level tokens** — Each token adds a column to every "large state" parse table row
6. **Large inline expansions** — When inlined rules are themselves large

### Mitigation Strategies
1. **Keep type/expression separate** — Don't put struct_definition in `_type`
2. **Flatten expression hierarchy** — Use precedence table, not nested rules
3. **Limit precedence levels** — 12-15 is healthy, 20+ risks explosion
4. **Use `token(choice(...))` to consolidate keyword-like alternatives** — See Strategy 5 below
5. **Profile generation** — If `tree-sitter generate` takes >10 min, investigate
6. **Test incrementally** — Add one feature at a time, check generation time
7. **Use GLR sparingly** — Declare only conflicts that truly exist

### What Does NOT Help (experimentally proven)
- **Private sub-rules (grouping)**: Moving alternatives behind a `_private_rule` has ZERO impact on states or generation time. The parser generator expands all alternatives transitively. **EXCEPTION**: If the sub-rule genuinely separates conflict domains (no shared conflicts with parent), it CAN help — this is the Zig pattern below.
- **Inlining intermediate rules**: Inlining `_expression_or_list` INCREASED generation time by 33% (8 min vs 6 min). Inlining adds alternatives at every use site.
- **Consolidation without `token()`**: Merging 9 node types into 3 without using `token()` INCREASED time by 29% (7:45 vs 6:00). Parser generator heuristics break down.
- **Reducing conflict count alone**: Removing 8 braceless-body conflicts had <2% impact on generation time. Conflicts affect parser SIZE but not generation TIME.

### Advanced Strategy: Hierarchical Expression Delegation (Zig Pattern)

**The most promising structural optimization** discovered from the benchmark study.

Zig organizes expressions in a 3-level hierarchy:
```
expression (19 direct alts) → type_expression (6 alts) → primary_type_expression (33 alts)
```

Despite having **109 total reachable** expression alternatives (including `struct_declaration`, `enum_declaration`, `union_declaration`), Zig generates only **1,836 states** in 9.9 seconds. The key is that the parser generator processes each hierarchy level within its own conflict domain.

**Application to Jai**: Currently `_expression` is flat with 38 alternatives. Potential hierarchy:
```javascript
_expression: $ => choice(
    // ~20 core alternatives (identifiers, binary, unary, call, field, index, etc.)
    $._directive_expression,   // 8-10 directive alternatives
    $._type_like_expression,   // 5 type-like alternatives
),
```

**CRITICAL CAVEAT**: This only works if the sub-rules have **genuinely different sets of conflicts**. If `_directive_expression` participates in the same conflicts as `_expression` (e.g., braceless body conflicts), the parser generator still expands everything transitively and the benefit is zero. This is why simple "private sub-rule grouping" failed in Phase 3. The hierarchy must genuinely separate conflict domains.

**WHY hierarchy works in Zig/D but private sub-rules don't (Pass 3 finding, REFINED in Pass 4)**:
The critical difference is NOT just "where rules are placed" but "what rules REFERENCE."

**In D** (confirmed Pass 4):
- `_expr` has 5 alternatives: assignment, ternary, binary, _unary_expr
- `call_expression` references `$._unary_expr` (mid level), NOT `$._expr`
- `property_expression` references `$._unary_expr` (mid level), NOT `$._expr`
- `cast_expression` references `$._unary_expr` (mid level), NOT `$._expr`
- Result: postfix/call states only need transitions for 11 unary alternatives, not all 33+ reachable expressions

**In Zig** (confirmed Pass 4, SURPRISING):
- `expression` (19 alts) → `type_expression` (6 alts) → `primary_type_expression` (33 alts)
- `call_expression` IS inside `primary_type_expression` BUT references `$.expression` (TOP level)
- `field_expression`, `index_expression` also reference `$.expression` (TOP level)
- **Despite this**, Zig gets only 1,836 states. Why?
- **Hypothesis**: The hierarchy works because `type_expression` rules (pointer_type, slice_type, array_type) reference `$.type_expression` (MID level), not `$.expression`. This creates a genuine split: type-construction expressions only need type-level continuations, while value expressions get full expression continuations. The parser can merge states that differ only in which hierarchy level they're tracking.

**The key takeaway**: You don't need ALL postfix operations to reference the mid level. Even if SOME reference the top level, having the type-construction rules reference a mid level creates enough state sharing to dramatically reduce the total count. The benefit is proportional to how many rules reference the mid level vs the top level.

Simply moving alternatives behind a private sub-rule keeps all the same `$._expression` references within those rules. The parser generator expands `_sub_expression` back to its alternatives, and since every leaf still references `$._expression`, the combinatorial explosion is identical.

**For Jai specifically**: Applying this pattern is difficult but the D pattern offers a more targeted approach:
- **Step 1**: Create `_postfix_expression` containing call, field, index, dereference, struct_literal, array_literal (6 rules)
- **Step 2**: Have `call_expression.function` reference `$._postfix_expression` instead of `$._expression`
- **Step 3**: `_postfix_expression` includes `$.parenthesized_expression` so `(a + b)(args)` still works (the parens "elevate" the inner expression to postfix level)
- **Risk**: MEDIUM — must verify `parenthesized_expression` inclusion handles all edge cases
- **Effort**: 4-8 hours for the restructuring, plus 4+ hours testing

**Estimated impact**: Based on D achieving 8,061 states with 42 conflicts (same as Jai), this restructuring could plausibly reduce Jai from 38,899 to 10,000-15,000 states, cutting generation time from ~4.5 min to ~1-2 min and parser.c from 113MB to 30-40MB.

### Advanced Strategy: External Scanner Offloading (Swift Pattern)

Swift's external scanner handles **33 token types** (vs Jai's 4) including operators (`->`, `.`, `&&`, `||`), keywords (`throws`, `default`, `where`), and implicit semicolons. Despite 36 GLR conflicts, Swift generates only 9,028 states in 4.1 seconds.

**Key insight**: By having the external scanner handle context-sensitive tokenization, the grammar becomes simpler. The scanner can make decisions that would require exponential states in the parser.

**Application to Jai — `<<` prefix dereference via scanner**:
```c
// Add PREFIX_DEREF to externals in grammar.js
// In scanner.c:
if (valid_symbols[PREFIX_DEREF] && lexer->lookahead == '<') {
    advance(lexer);
    if (lexer->lookahead == '<') {
        advance(lexer);
        lexer->mark_end(lexer);
        lexer->result_symbol = PREFIX_DEREF;
        return true;
    }
}
```
The grammar references `PREFIX_DEREF` as a unary operator only in positions where it's valid. When `valid_symbols[PREFIX_DEREF]` is false, the scanner returns false and lets the grammar handle `<<` as binary shift. **Zero additional parser states** — disambiguation happens entirely in the scanner.

### Advanced Strategy: Backslash Identifiers via External Scanner (Pass 3 finding)

The highest-impact fixable pattern (~30 module files). Jai allows `\` within identifiers as a visual separator: `month\_starting_at_0`, `left\_margin`. The pattern is always `\` followed by `_` or a letter.

**Approach**: Add `BACKSLASH_IDENTIFIER` external token. Keep `identifier` as the `word` token (pure regex). Add `backslash_identifier` as a separate named node alongside `identifier` in all identifier-accepting positions.

```c
// scanner.c
enum TokenType { BLOCK_COMMENT, HERE_STRING_BODY, ASM_BODY, BACKSLASH_IDENTIFIER, ERROR_SENTINEL };

static bool scan_backslash_identifier(TSLexer *lexer) {
    if (!is_ident_start(lexer->lookahead)) return false;
    bool has_backslash = false;
    while (is_ident_char(lexer->lookahead)) advance(lexer);
    while (lexer->lookahead == '\\') {
        lexer->mark_end(lexer);
        advance(lexer);
        if (lexer->lookahead == '_' || is_ident_start(lexer->lookahead)) {
            has_backslash = true;
            advance(lexer);
            while (is_ident_char(lexer->lookahead)) advance(lexer);
        } else { return has_backslash; }
    }
    if (has_backslash) { lexer->mark_end(lexer); lexer->result_symbol = BACKSLASH_IDENTIFIER; return true; }
    return false;
}
```

```javascript
// grammar.js — every rule accepting identifier also accepts backslash_identifier
externals: $ => [..., $.backslash_identifier, ...],
```

**Risk**: LOW. External tokens resolved before grammar, `valid_symbols` controls placement. Must update ~20-30 rules that accept `identifier`. State count impact minimal (similar to adding a literal type).

**Key constraint**: Cannot change the `word` token regex (adding `\` would break keyword boundary detection). Must use external scanner for the backslash-containing variant.

### Advanced Strategy: Inline Rule Candidates

Jai has only **3 inline rules** vs 6-14 in comparable grammars. Current: `_top_level_item`, `_declaration_value`, `_literal`.

Safe candidates for NEW inlining:
- `_return_type_item` — pure choice, 3 alternatives, used only in `_return_type_list`. LOW risk.
- `_return_type_list` — used only in `return_type`. LOW risk.

**DO NOT inline**: `_statement` (27 alts, 8+ usages — catastrophic), `_type` (12 alts, 20+ usages — very dangerous), `_expression` (39 alts, 50+ usages — would destroy parse table). These rules are referenced too many times; inlining copies alternatives into every usage site.

Impact of safe candidates: negligible state count reduction. Focus effort on expression restructuring and external scanner instead.

### `reserved` Keyword Feature (v0.26+, ABI 15)

Define named word sets and use `reserved('setname', rule)` to allow keywords in specific contexts. JavaScript grammar demonstrates at lines 33-72 of `reference-grammars/tree-sitter-javascript/grammar.js`.

For Jai, limited benefit since directives start with `#` (no collision with `word` token). Potential use for `using`, `cast`, `struct`, `enum` if they appear as identifiers in some contexts.

### Tree-sitter Version Notes

**v0.26.5** (installed via cargo, current): ABI 15, `u16::MAX` action limit, `reserved` keyword feature.

**v0.27.0** (cloned at `reference-grammars/tree-sitter/`): Same ABI 15, same `u16::MAX` action limit. No changes to the parser generator that affect state count or action overflow. `OptLevel::MergeStates` is still the only optimization (enabled by default). The `SMALL_STATE_THRESHOLD` remains 64. No planned increase to the action limit -- it would require changing the C API (uint16_t type in parse table) which is an ABI break.

### The 65,535 Action Entry Limit (Corrected Understanding)
The limit is NOT on state count (40,044 states is fine). It's on `next_parse_action_list_index` — a cumulative index into a flat array of unique `ParseTableEntry` objects in `render.rs` (line 1458). Each unique entry consumes `1 + action_count` slots. The index is stored as `uint16_t`, hence the 65,535 maximum.

- **Source**: `reference-grammars/tree-sitter/crates/generate/src/render.rs` line 1458
- **What overflows**: Total unique parse action entries across the entire grammar
- **Current Jai**: 38,899 states, 42 conflicts — still under the limit
- **Overflow examples**: Adding `<<` as unary → 78,534 entries; `#overlay` → 67,759; `#align` suffix → 78,465
- **Cannot be raised**: Hard-coded as `u16::MAX` in renderer. Would require tree-sitter ABI change.
- **Confirmed still in tree-sitter 0.27.0**: The cloned repo at `reference-grammars/tree-sitter/` is version 0.27.0. Same `u16::MAX` limit, same ABI 15. No planned change.
- **`_expression` alternative count drives state count superlinearly** — but the *action entry limit* is what blocks specific features

### Action Overflow Workarounds (Pass 4 analysis)

**Strategy A: External Scanner Token Disambiguation** (proven in Swift, Rust)
Move the ambiguous token to the external scanner. When `valid_symbols[TOKEN]` is true (context where the token is valid), the scanner produces it. When false, the scanner returns false and the internal lexer handles the characters as something else.

**Detailed example: `<<` prefix dereference**
```c
// scanner.c — new token PREFIX_DEREF
if (valid_symbols[PREFIX_DEREF] && lexer->lookahead == '<') {
    advance(lexer);
    if (lexer->lookahead == '<') {
        advance(lexer);
        lexer->mark_end(lexer);
        lexer->result_symbol = PREFIX_DEREF;
        return true;
    }
}
// Falls through to internal lexer which handles << as binary shift
```

```javascript
// grammar.js
externals: $ => [..., $.prefix_deref, ...],

// In unary_expression or dereference_expression:
prec(PREC.UNARY, seq($.prefix_deref, field('operand', $._expression))),
```

**Why this works**: The parser only marks `PREFIX_DEREF` as valid at positions where a unary expression can START (after `=`, after `(`, at statement start, etc.). At positions where `<<` should be binary shift (after an expression), `PREFIX_DEREF` is NOT valid, so the scanner returns false and the internal lexer matches `<<` as shift. Zero additional parser states because the disambiguation happens entirely in the scanner.

**Key validation**: In position `a << b`, after `a` the parser expects binary continuation operators. `PREFIX_DEREF` is NOT among the valid tokens (it's a unary prefix). In position `x = << ptr`, after `=` the parser expects an expression start. `PREFIX_DEREF` IS valid. The context-awareness of tree-sitter's lexer makes this work.

**Strategy B: Reduce action count via expression consolidation**
The action overflow is `next_parse_action_list_index >= u16::MAX`. Each UNIQUE `ParseTableEntry` consumes `1 + N` slots where N is the number of actions. Reducing the number of unique entries (by reducing distinct token types or conflicts) shrinks the cumulative index.

The `token(choice(...))` technique directly reduces the number of parser-level tokens, which reduces the number of distinct entries. If consolidating tokens brings the overflow case from 78,534 to under 65,535, the feature becomes implementable.

**Strategy C: Structural avoidance**
For `#overlay` and `#align` which overflow when added to `_struct_member`: instead of adding them as full alternatives, use a "catch-all directive" pattern:
```javascript
_struct_member: $ => choice(
    $.struct_field,
    $.declaration,
    // ... existing members
    $.struct_directive,  // NEW: catch-all for directives in struct bodies
),

struct_directive: $ => seq(
    field('name', token(choice('#overlay', '#align', '#elsewhere'))),
    optional(field('argument', $._expression)),
    ';',
),
```
This adds ONE alternative instead of three, and uses `token(choice(...))` to make it a single parser token. If one alternative is within budget but three are not, this is the path.

### Conflict Reduction: Proven Strategies (from Jai grammar optimization)

Reducing GLR conflicts from 52→43 cut parser.c from 117MB→103MB (12% reduction). This freed enough budget to add a previously-blocked feature (`#foreign` + procedure modifiers, was only 557 over limit).

**Strategy 1: Remove optional syntax variants that create expression ambiguity**
Making a comma optional between `*=expr` and `<=expr` in for-loop modifiers created 5 new conflicts (`[$.for_statement, $.binary_expression, ...]`). The `<=` token is ambiguous: is it comparison (extending expression) or the reverse flag? Requiring the comma eliminated all 5 conflicts.
- **Cost**: Lose comma-less syntax (affected 1 module file)
- **Savings**: 5 conflicts

**Strategy 2: Restrict rule alternatives that overlap with `_expression`**
`using_filter_args` accepted `identifier`, `array_literal`, `run_expression` — all members of `_expression`. This created 4 conflicts because the parser couldn't tell if a token after `using,except` was a filter arg or the start of an expression/type. Restricting to only the parenthesized form `(id, id)` eliminated all 4 conflicts.
- **Cost**: Lose `using,except NAMES`, `using,except .["a","b"]`, `using,except #run fn()` forms
- **Savings**: 4 conflicts

**Key principle**: When a sub-rule's alternatives overlap with `_expression` or `_type`, every such overlap creates conflicts with every other rule that also overlaps with `_expression`/`_type`. The cost is multiplicative, not additive. Restricting sub-rules to non-overlapping forms (like parenthesized identifier lists) is a high-leverage optimization.

**Strategy 3: Add required terminators to resolve optional-param ambiguity**
When a rule has `optional(directive_params)` and the `(` token is ambiguous (could start params or a new expression), adding a required terminator (`;` or `choice(block, ';')`) at the end forces the parser to consume `(` as params. This is because the parser must eventually reach the terminator, and `(` doesn't match it.
- **Example**: `import_directive` with `;` terminator makes `#import "X"(PARAM=val);` parse correctly
- **Example**: `module_parameters_directive` with `choice($.block, ';')` makes `#module_parameters(A)(B);` parse correctly
- **Cost**: Zero conflicts (actually ELIMINATES unnecessary conflicts)
- **Caveat**: If the rule has alternative forms without `;` (e.g., here-string imports), split the rule into separate forms via `choice`

**Strategy 4: Use prec.right to prefer consuming optional params**
For rules used in `_declaration_value` (inlined), `prec.right` makes the parser prefer to shift `(` as directive_params rather than reducing the rule. Works well when the parent context (e.g., `declaration`) has no valid continuation starting with `(`.
- **Example**: `import_expression` with `prec.right` correctly consumes both `()` param lists in `Basic :: #import "Basic"()(DEBUG=true);`
- **Cost**: Zero new conflicts or states

**Strategy 5: Use `token(choice(...))` to consolidate keyword-like expression alternatives**
Multiple simple keyword expressions (like `#this`, `#line`, `#compile_time`) that all get the same highlight treatment can be merged into a single rule using `token(choice(...))`. This reduces the number of parser-level tokens AND parser-level alternatives.

```javascript
// Before: 6 separate alternatives in _expression (6 parser tokens)
this_expression: _ => '#this',
caller_location_expression: _ => '#caller_location',
line_expression: _ => '#line',
// ... 3 more

// After: 1 alternative in _expression (1 parser token)
compile_time_constant: _ => token(choice(
  '#this', '#caller_location', '#caller_code',
  '#filepath', '#file', '#line', '#compile_time',
)),
```

**Key insight**: `choice(...)` without `token()` creates N separate parser tokens. With `token()`, it's 1 parser token matched by the lexer. This matters because each parser token adds a column to every "large state" row in the parse table.

- **Cost**: Lose ability to distinguish these nodes by type in queries (must use `#match?` predicates on content instead)
- **Savings**: In Jai grammar, consolidating 6→1 cut generation time from 6:00 to 4:30 (25%)
- **When to use**: Only for expressions that get the same highlight group. Don't merge nodes that need different highlighting.

**Experimental proof** (from Jai grammar, 9 experiments):

| Approach | Time | Result |
|----------|------|--------|
| Baseline (49 alternatives) | 6:00 | — |
| Remove 22 alternatives (proof of concept) | 0:58 | Lower bound |
| token() for 6 constants (44 alt) | **4:30** | **25% faster** |
| token() + consolidate builtins (39 alt) | **4:27** | Marginal additional gain |
| Consolidate WITHOUT token() (40 alt) | 7:45 | WORSE |
| Group via private sub-rule (42 alt) | 7:58 | Zero impact |

## Expression Hierarchy Pattern

### Flat table (preferred over nested)
```javascript
binary_expression: $ => {
  const table = [
    [PREC.MULTIPLICATIVE, choice('*', '/', '%')],
    [PREC.ADDITIVE, choice('+', '-')],
    [PREC.COMPARATIVE, choice('<', '<=', '>', '>=')],
  ];
  return choice(...table.map(([p, op]) =>
    prec.left(p, seq($._expression, op, $._expression))
  ));
},
```

### Why flat is better
- Fewer intermediate rules = fewer states
- Easy to add operators
- Consistent precedence per level
- Same associativity per level

## Declaration System Pattern (Jai-specific)

Jai's `:`, `:=`, `::` each have different semantics:
```javascript
declaration: $ => seq(
  names,
  choice(
    seq(':=', value),           // Variable, type inferred
    seq('::', value),           // Constant
    seq(':', type, '=', value), // Variable, typed
    seq(':', type, ':', value), // Constant, typed
    seq(':', type, '=', '---'), // Uninitialized
    seq(':', type),             // Default init
  ),
),
```

## Testing

### Corpus tests (test/corpus/*.txt)
```
================================================================================
Test name
================================================================================

source code here

--------------------------------------------------------------------------------

(expected_parse_tree
  (in_s_expression_format))
```

### Highlight tests (test/highlight/*.ext)
```
code_here;
// <- highlight_group       (column 0 of previous line)
//   ^ highlight_group      (^ column position on previous line)
```

### Commands
```bash
tree-sitter generate              # Generate parser from grammar.js
tree-sitter test                  # Run all corpus + highlight tests
tree-sitter test -f "test name"   # Run specific test (substring match)
tree-sitter parse file.ext        # Parse file, show tree
tree-sitter parse file.ext -q     # Parse file, show only errors
```

## Reference Grammar Comprehensive Benchmark

Benchmarked against all 17 reference grammars (tree-sitter v0.26.5, ABI 15):

| Grammar | States | Large States | Large% | Size | Gen Time | Conflicts | Expr Alts | Inline | Tokens |
|---------|--------|-------------|--------|------|----------|-----------|-----------|--------|--------|
| Nickel | 1,268 | 9 | 0.7% | 1.3M | 0.3s | 0 | n/a | 0 | 82 |
| Go | 1,442 | 29 | 2.0% | 1.5M | 0.5s | 8 | 23 | 7 | 95 |
| Java | 1,385 | 406 | 29.3% | 2.5M | 1.1s | 13 | 10 | 4 | 138 |
| Zig | 1,836 | 933 | 50.8% | 5.6M | 9.9s | 6 | 19→109 | 1 | 154 |
| JavaScript | 1,870 | 387 | 20.7% | 2.8M | 1.3s | 18 | 11 | 14 | 134 |
| C | 2,015 | 455 | 22.6% | 3.7M | 1.3s | 17 | 24+18 | 6 | 161 |
| Python | 2,788 | 185 | 6.6% | 3.3M | 0.6s | 9 | 8 | 6 | 108 |
| Rust | 3,825 | 1,064 | 27.8% | 6.3M | 3.0s | 9 | 31 | 8 | 157 |
| Odin | 3,955 | 1,022 | 25.8% | 8.0M | 5.3s | 6 | 20 | 6 | 176 |
| TypeScript | 5,870 | 1,193 | 20.3% | 8.4M | 6.7s | 48 | 15 | 14 | 166 |
| Ruby | 5,989 | 2,168 | 36.2% | 15M | 22.8s | 0 | 14 | 2 | 157 |
| Elixir | 7,001 | 1,094 | 15.6% | 13M | 2.9s | 6 | 23 | 0 | 124 |
| D | 8,061 | 3,241 | 40.2% | 23M | 17.2s | 42 | 5→28 | 14 | 229 |
| Swift | 9,028 | 1,918 | 21.2% | 18M | 4.1s | 36 | 11 | 1 | 213 |
| C++ | 11,551 | 3,721 | 32.2% | 24M | 35.2s | 39 | 15+8 | 7 | 225 |
| Haskell | 12,862 | 2,378 | 18.5% | 19M | 5.1s | 5 | 27 | 51 | 156 |
| **Jai** | **39,630** | **23,144** | **58.4%** | **111M** | **~300s** | **42** | **40** | **3** | **334** |

> **Expr Alts**: Direct `_expression` alternatives. `19→109` means 19 direct, 109 reachable via hierarchy. `24+18` means 24 non-binary + 18 binary operator variants.

### Key Observations

- **Jai is an extreme outlier**: 3.0x more states than Haskell (next largest), 6.1x more large states than C++, 7.3x slower generation than C++
- **57.9% large-state ratio** is the highest — every large state stores an action per symbol (334 symbols x 22,516 large states = ~7.5M entries in the large state table)
- **States per expression alternative**: Jai=1,024 vs Go=63, C=84, Rust=123, Odin=198. The 5-16x multiplier comes from **interaction between alternatives and GLR conflicts**
- **Only 3 inline rules** vs 6-14 in comparable grammars — missed optimization opportunity
- **Symbol count 334** is the highest — C has 161, Rust 157, D 229, C++ 225. Combined with 57.9% large-state ratio, each symbol disproportionately inflates the table
- **`_expression` alternative count remains the primary driver** — highly nonlinear relationship with state count
- The `token(choice(...))` technique remains the best cost/benefit optimization

### Large vs Small State Internals (Pass 4 finding)

**How states are classified**: In `minimize_parse_table.rs`, states are sorted by descending entry count. The `LARGE_STATE_COUNT` is determined by the threshold `min(64, SYMBOL_COUNT/2)`. For Jai with SYMBOL_COUNT=334, threshold=64. Any state with >64 terminal+nonterminal entries is "large."

**Large state cost**: Each large state stores a uint16 action for EVERY symbol: `ts_parse_table[LARGE_STATE_COUNT][SYMBOL_COUNT]`. This is a dense 2D array. For Jai: 22,516 x 334 x 2 bytes = ~15 MB just for the large state table header. The full parser.c also includes small state table, action lists, and other metadata.

**Small state cost**: Small states use a compact sparse representation where symbols are grouped by their shared action, avoiding redundant storage. This is vastly more compact — the 16,383 small states take a fraction of the space.

**Key optimization target**: Reducing `LARGE_STATE_COUNT` has the highest leverage on parser size. A state transitions from large to small by having fewer than 64 distinct entries. Reducing the number of expression alternatives or tokens directly reduces the entry count per state.

**Comparison of large-state ratios**:
| Grammar | Large% | Large State Table Size |
|---------|--------|----------------------|
| Go | 2.0% | 29 x 95 x 2 = 5.5 KB |
| Python | 6.6% | 185 x 108 x 2 = 40 KB |
| Zig | 50.8% | 933 x 273 x 2 = 510 KB |
| Rust | 27.8% | 1,064 x 157 x 2 = 334 KB |
| Odin | 25.8% | 1,022 x 285 x 2 = 583 KB |
| D | 40.2% | 3,241 x 229 x 2 = 1.5 MB |
| C++ | 32.2% | 3,721 x 225 x 2 = 1.7 MB |
| Swift | 21.2% | 1,918 x 547 x 2 = 2.1 MB |
| **Jai** | **57.9%** | **22,516 x 334 x 2 = 15.0 MB** |

Jai's large state table is 7x bigger than its nearest competitor (Swift). This is the primary driver of the 113MB parser.c.

### Why D has 42 conflicts but only 8,061 states (vs Jai's 42 conflicts and 38,899 states)

D and Jai both have 42 GLR conflicts, but D has 4.8x fewer states. The difference is in expression hierarchy:

**D's expression hierarchy** (3 levels):
```
_expr (5 alts: assignment, ternary, binary, _unary_expr)
  → _unary_expr (11 alts: _primary_expr, unary, new, delete, assert, cast, throw, call, index, postfix, property)
    → _primary_expr (17+ alts: identifier, literals, typeof, is, function_literal, etc.)
```

**Critical pattern**: D's `call_expression` references `$._unary_expr`, NOT `$._expr`. D's `property_expression` references `$._unary_expr`, NOT `$._expr`. This means postfix operations (call, property, index) can only chain off unary/primary expressions, genuinely separating the conflict domains.

**Jai's flat structure**:
```
_expression (38 alts: everything including call, field, index, binary, unary, etc.)
```

Every postfix operation in Jai references `$._expression` for its operand, meaning every expression can be followed by `(`, `.`, `[`. This creates massive state fan-out because every state that could be inside an expression needs transitions for all 38 alternatives PLUS all postfix continuations.

## Common Patterns from Reference Grammars

### Word token for keyword extraction
```javascript
word: $ => $.identifier,  // Required for proper keyword handling
```
Ensures `ifSomething` isn't parsed as `if` + `Something`.

### Inline for tree flattening
```javascript
inline: $ => [$._simple_type, $._declaration_value],
```
Removes intermediate nodes, reducing tree depth and state count.

### Extras for whitespace/comments
```javascript
extras: $ => [/\s/, $.line_comment, $.block_comment],
```

### Token for atomic matching
```javascript
// Good: single token prevents whitespace between parts
'.{': _ => token(seq('.', '{')),
// Bad: two separate tokens, whitespace could appear
seq('.', '{'),
```

## String Literal vs Comment Priority (Critical Bug Pattern)

### The Problem
When a grammar has `//` line comments in `extras` and string literals with a bare regex for content, `//` inside strings is misinterpreted as a comment. This causes cascading parse errors.

**Root cause**: Tree-sitter's `extras` tokens are valid at EVERY position in the grammar, including between repetitions inside `string_literal`. When the lexer sees `//` inside a string, both the string content regex and the line_comment token can match. Without explicit lexical precedence, the comment wins because:
1. `token(seq('//', /.*/))` wraps a sequence starting with a string literal `'//'`
2. A bare regex `/[^"\\]+/` has default lexical precedence 0
3. Tree-sitter prefers string-specified tokens over regex-specified tokens (Match Specificity rule)

### The Fix (Universal Pattern)

**Every major reference grammar** (C, Go, Rust, Odin, Zig, D, Swift) uses the same fix:

```javascript
// WRONG — bare regex, no precedence, no immediate
string_literal: $ => seq('"', repeat(choice($.escape_sequence, /[^"\\]+/)), '"'),

// CORRECT — token.immediate with lexical precedence
string_literal: $ => seq(
  '"',
  repeat(choice(
    $.escape_sequence,
    alias(token.immediate(prec(1, /[^"\\\n]+/)), $.string_content),
  )),
  '"',
),
```

**Three essential elements**:
1. **`token.immediate`** — Prevents `extras` (whitespace, comments) from being matched BEFORE this token. Without it, the parser can insert a comment between string content segments.
2. **`prec(1, ...)`** — Gives lexical precedence of 1, higher than the comment's default 0. When both match at the same position, string content wins.
3. **`\n` in exclusion set** — `/[^"\\\n]+/` prevents the regex from consuming across line boundaries. Improves error recovery: if a closing `"` is missing, the error is contained to one line.

### Alternative: External Scanner (Rust Pattern)

For bulletproof handling, make string content an external scanner token:

```javascript
// grammar.js
externals: $ => [$.string_content, ...],
string_literal: $ => seq('"', repeat(choice($.escape_sequence, $.string_content)), '"'),
```

```c
// scanner.c — process_string
static bool process_string(TSLexer *lexer) {
    bool has_content = false;
    for (;;) {
        if (lexer->lookahead == '"' || lexer->lookahead == '\\') break;
        if (lexer->eof(lexer)) return false;
        has_content = true;
        advance(lexer);
    }
    lexer->result_symbol = STRING_CONTENT;
    lexer->mark_end(lexer);
    return has_content;
}
```

External scanner tokens have HIGHEST lexer priority, completely bypassing the internal lexer's comment matching. Rust uses this approach. Zero ambiguity possible.

**Trade-off**: The `token.immediate(prec(1, ...))` approach is simpler (1-line grammar change) and is used by C, Go, Odin, Zig, D. The external scanner approach is more robust but adds scanner complexity.

### Why `extras` tokens appear inside strings

Tree-sitter's lexer is context-aware but `extras` are ALWAYS valid. Inside `seq('"', repeat(choice(...)), '"')`, between each iteration of the `repeat`, the lexer considers: (a) the choice alternatives, (b) all extras tokens. So `//` after a string content segment could be matched as a line_comment extra UNLESS the string content has higher lexical precedence.

### Reference grammar survey (Pass 4 finding)

| Grammar | String Content | Comment Priority | Fix Pattern |
|---------|---------------|-----------------|-------------|
| C | `token.immediate(prec(1, /[^\\"\n]+/))` | Default (0) | Lexical prec |
| Go | `token.immediate(prec(1, /[^"\n\\]+/))` | Default (0) | Lexical prec |
| Odin | `token.immediate(prec(1, /[^"\n\\]+/))` | Default (0) | Lexical prec |
| Zig | `token.immediate(prec(1, /[^\\"\n]+/))` | Default (0) | Lexical prec |
| D | `token.immediate(prec(1, /[^"\\]+/))` | Default (0) | Lexical prec |
| Rust | External scanner (`STRING_CONTENT`) | N/A | Scanner |
| Swift | External scanner | N/A | Scanner |
| **Jai** | **bare `/[^"\\]+/`** | Default (0) | **BROKEN** |

## Known Issues & Workarounds

### Issue: Anonymous struct/enum in type position
**Problem**: Adding `struct_definition` or `enum_definition` to `_type` causes state explosion.
**Workaround**: Accept as known limitation. These constructs work in `_declaration_value` (`::`  position) but not in type annotation (`:`) position.

### Issue: Braceless body ambiguity
**Problem**: `for x + y` — is `+` extending expression or starting body?
**Workaround**: Use `prec.dynamic()` with explicit conflict declarations for every possible continuation operator.

### Issue: `*` as unary vs binary
**Problem**: `if x * y` — is `*` multiplication (extend condition) or dereference (start consequence)?
**Workaround**: Use `prec.right(PREC.MULTIPLICATIVE)` for unary `*` instead of `prec(PREC.UNARY)`, with explicit `[$.binary_expression, $.unary_expression]` conflict.

### Issue: Parse table action overflow (>65,535 action entries)
**Problem**: Adding new alternatives to rules that interact with `_expression` or `_struct_member` can push `next_parse_action_list_index` (a cumulative uint16 index into a flat array of unique `ParseTableEntry` objects) past 65,535. This is a hard limit in `render.rs` line 1458.
**Observed cases** (from Jai grammar):
- `<<` as unary prefix operator: 78,534 entries — solvable via external scanner (`PREFIX_DEREF` token)
- `#overlay` in `_struct_member`: 67,759 entries — may benefit from hierarchical expression restructuring
- `#align N` as struct_field suffix: 78,465 entries — unresolvable conflicts with declaration rule
**Diagnostic**: `tree-sitter generate` error: "ENOBUFS: no buffer space available" with entry count.
**Mitigation strategies** (prioritized, REVISED Pass 5):
1. **Reduce overall state count first** — Jai is at 99.9% action budget (65,479/65,535). ANY new feature requires first creating headroom by reducing states. The ONLY path forward is expression hierarchy restructuring or aggressive token consolidation.
2. **External scanner offloading** — Useful for disambiguation (eliminates the need for parser to track both interpretations) but has a HIDDEN COST: external tokens prevent state merging (see "External Token State-Merge Penalty" below).
3. **Hierarchical expression restructuring** — Reduce direct `_expression` alternatives to shrink action table.
4. **`token(choice(...))` consolidation** — Reduce parser-level token count, shrinking every large state row.
5. **Accept as limitation** — When none of the above apply.

### Action Entry Budget Analysis (Pass 5 — CRITICAL FINDING)

The Jai grammar is at **99.9% of the action entry limit**:

| Grammar | Max Action Index | Limit | Usage | Remaining |
|---------|-----------------|-------|-------|-----------|
| **Jai** | **65,479** | 65,535 | **99.9%** | **56** |
| D | 14,977 | 65,535 | 22.8% | 50,558 |
| C++ | 18,820 | 65,535 | 28.7% | 46,715 |
| Swift | 14,329 | 65,535 | 21.9% | 51,206 |
| Rust | 7,590 | 65,535 | 11.6% | 57,945 |
| Zig | 3,194 | 65,535 | 4.9% | 62,341 |

**Implication**: With only 56 entry slots remaining, ANY grammar change that creates new unique action entries will exceed the limit. There is NO room to add features without first reducing the existing entry count. This is the SINGLE MOST IMPORTANT constraint for Jai grammar development going forward.

**How entries accumulate** (from `render.rs::get_parse_action_list_id`):
- Each UNIQUE `ParseTableEntry` (action list + reusable flag) costs `1 + action_count` slots
- Most entries are single-action SHIFT(state_N) entries costing 2 slots each
- GLR conflict entries (multiple actions) cost `1 + N` where N is the number of parallel actions
- Entries are DEDUPLICATED: if 10,000 states share the same action for a token, it's 1 entry
- The total index increments by `1 + actions.len()` for each new unique entry

**Relationship between states and entries**: Fewer states = fewer unique entries. Reducing Jai from 39,630 to ~25,000 states would proportionally reduce entries from ~65,479 to ~41,000, freeing ~24,000 slots. This is the ONLY way to create headroom.

### External Token State-Merge Penalty (Pass 5 — NEW FINDING)

**Source**: `minimize_parse_table.rs` lines 356-364 (`token_conflicts` function)

When the state minimizer considers merging two compatible states, it refuses if one state has an external token that the other doesn't. The code comment says: "Do not add external tokens; they could conflict lexically with any of the state's existing lookahead tokens."

**Mechanism**: `if new_token.is_external() { return true; /* conflict, don't merge */ }`

**Impact on Jai grammar**: Adding a new external token (e.g., `PREFIX_DEREF` for `<<`) would PREVENT state merging for any pair of states where one expects `PREFIX_DEREF` and the other doesn't. This could potentially INCREASE total state count, which would increase action entries, which could push us further past the limit instead of helping.

**Key nuance**: The external scanner approach for `<<` still provides the DISAMBIGUATION benefit (the parser doesn't need to carry both unary and binary interpretations simultaneously, which is what causes the 78,534-entry overflow). But after generating, the minimizer won't merge states as aggressively. Net effect depends on which is larger: the entry savings from disambiguation vs the entry cost from reduced merging.

**Recommendation**: Before implementing external scanner `PREFIX_DEREF`, first reduce the overall state count to create substantial headroom (at least 5,000 entry slots). Then add the external token and measure. If the net effect is still over limit, the approach fails.

**Also blocked by this**: Any token that is BOTH internal (grammar rule) and external (scanner) prevents merging for all states that reference it. Lines 370-383: "Do not add tokens which are both internal and external."

### Catch-All Struct Directive Pattern (Pass 5 — Feasibility Analysis)

**Proposal**: Consolidate `#overlay`, `#align`, `#elsewhere`, `#place`, `#as` into a single `struct_directive` rule in `_struct_member`, using `token(choice(...))` for the keyword.

**Feasibility**: PARTIALLY FEASIBLE but with constraints.

The keyword consolidation via `token(choice('#overlay', '#align', '#elsewhere', '#place', '#as'))` would reduce the parser-level token count by 4 (5 tokens -> 1 token). This saves entries proportional to `4 * large_state_count_with_these_tokens`.

**Problem 1**: These directives have DIFFERENT argument structures:
- `#align` takes `_expression`
- `#place` takes `identifier` + `;`
- `#as` takes `_struct_member` (recursive!)
- `#overlay` takes `(field_ref)` + struct field

Cannot use `token(choice(...))` for the WHOLE directive rule, only for the keyword part. The argument handling must remain separate via `choice(...)` after the keyword token.

**Problem 2**: The `#as _struct_member` form is recursive. If `struct_directive` is itself in `_struct_member`, and `#as` variant takes `_struct_member`, this creates a cycle that's fine for parsing but adds complexity.

**Problem 3**: Currently `#overlay` alone causes 67,759 entries (2,224 over). Even consolidating the keyword with `token()` only reduces the entry count by the "column savings" from fewer parser tokens. With 23,144 large states each saving maybe 4 entries for the removed tokens, that's ~92,576 entry references eliminated from the large state table. But the ACTION ENTRY count (unique entries) might not decrease proportionally because the entries for `#overlay` contexts are unique regardless.

**Verdict**: The catch-all pattern alone is INSUFFICIENT to add `#overlay`. Must first reduce overall state count to create headroom. The catch-all pattern would then be a good way to add multiple directives cheaply (1 alternative instead of 3+) once headroom exists.

### Odin's Struct Directive Pattern (Pass 5 — Reference Pattern)

Odin avoids the struct member explosion by placing struct directives BEFORE the struct body (between `struct` keyword and `{`), not inside the body as members:

```javascript
struct_type: $ => seq(
    'struct',
    optional(field('parameters', $.parameter_list)),
    repeat(alias($._struct_directive, $.compiler_directive)),  // BEFORE body
    '{', list(',', $.struct_field_declaration), '}',
),
_struct_directive: $ => choice('#no_copy', '#packed', '#raw_union', seq('#align', $._expression)),
```

This works because directives in a fixed position don't interact with the `_expression` alternatives inside the body. The parser knows exactly when to expect directives (after `struct`, before `{`) vs when to expect fields (inside `{}`).

**Application to Jai**: Jai has a different syntax where directives like `#align` can appear BETWEEN fields inside the struct body, not just before it. This makes the Odin pattern inapplicable for Jai without changing the language semantics. However, for directives that DO appear before the body (like `#no_padding`, `#packed`), the Odin pattern is already used in Jai's `struct_modifier`.

### Refreshed Benchmark Comparison (Pass 5 — 2026-02-15)

| Grammar | States | Large States | Large% | Size | Gen Time | Max Action Idx | Actions% | Conflicts |
|---------|--------|-------------|--------|------|----------|----------------|----------|-----------|
| Go | 1,442 | 29 | 2.0% | 1.5M | 0.5s | ~500 | 0.8% | 8 |
| Zig | 1,836 | 933 | 50.8% | 5.6M | 9.0s | 3,194 | 4.9% | 6 |
| Odin | 3,955 | 1,022 | 25.8% | 8.0M | 4.8s | ~5,000 | ~7.6% | 6 |
| Rust | 3,825 | 1,064 | 27.8% | 6.3M | 3.0s | 7,590 | 11.6% | 9 |
| D | 8,061 | 3,241 | 40.2% | 22M | 16.5s | 14,977 | 22.8% | 42 |
| Swift | 9,028 | 1,918 | 21.2% | 17M | 4.1s | 14,329 | 21.9% | 36 |
| C++ | 11,551 | 3,721 | 32.2% | 24M | 35.2s | 18,820 | 28.7% | 39 |
| **Jai** | **39,630** | **23,144** | **58.4%** | **111M** | **~300s** | **65,479** | **99.9%** | **42** |

**Key observations**:
- Jai's action usage (99.9%) is an order of magnitude higher than the next closest (C++ at 28.7%)
- Jai has more states than all other grammars COMBINED (38,118 total for the other 7)
- The action budget is EXHAUSTED; this is the binding constraint, not generation time or file size
- Even D (same conflict count as Jai, 42) uses only 22.8% of the action budget
- The fundamental difference: D has a 3-level expression hierarchy, Jai is flat

### render.rs Action Deduplication Details (Pass 5 — Internal Mechanics)

**Source**: `render.rs` lines 1689-1703

```rust
fn get_parse_action_list_id(&self, entry: &ParseTableEntry,
    parse_table_entries: &mut HashMap<ParseTableEntry, usize>,
    next_parse_action_list_index: &mut usize,
) -> usize {
    if let Some(&index) = parse_table_entries.get(entry) {
        index  // REUSE existing entry
    } else {
        let result = *next_parse_action_list_index;
        parse_table_entries.insert(entry.clone(), result);
        *next_parse_action_list_index += 1 + entry.actions.len();  // NEW entry
        result
    }
}
```

A `ParseTableEntry` contains `{ actions: Vec<ParseAction>, reusable: bool }`. Two entries are deduplicated iff they have the SAME action vector and SAME reusable flag. Since most entries are `{ [SHIFT(state_N)], true }`, and each shift goes to a DIFFERENT state, most entries are unique (2 slots each). GLR conflict entries with multiple actions use `1 + N` slots.

**What reduces unique entries**:
1. **State merging** — When the minimizer merges 2 states into 1, all shifts that pointed to those 2 states now point to the same state. This converts previously-unique entries into duplicates. MORE merging = FEWER unique entries.
2. **Fewer expression alternatives** — Each alternative creates unique shift targets in expression-continuation states. Fewer alternatives = fewer unique shift targets = more entry sharing.
3. **`token(choice(...))` consolidation** — Reduces the number of terminal symbols, which reduces the number of entries per large state. But doesn't directly reduce unique entries unless it also enables more state merging.

### State Minimizer Internals (Pass 5 — How Merging Works)

**Source**: `minimize_parse_table.rs`

The state minimizer runs in 4 phases:
1. **`merge_compatible_states()`** — Groups states by parse item set core. Iteratively splits groups when states conflict (different actions or successors).
2. **`remove_unit_reductions()`** — Eliminates single-child reductions for hidden non-named rules.
3. **`remove_unused_states()`** — Garbage-collects unreachable states.
4. **`reorder_states_by_descending_size()`** — Sorts by descending entry count (large states first for `LARGE_STATE_COUNT` cutoff).

**State merging blockers** (things that prevent two states from being merged):
- Different action counts for the same token
- Different shift destinations (unless those destinations are in the same merge group)
- One state has an external token the other doesn't (see "External Token State-Merge Penalty")
- One state has a token that lexically conflicts with another token in the other state
- One state has a token that matches the same string as a token in the other state

**Implication for Jai**: The 42 GLR conflicts likely cause many states to have multi-action entries that differ from single-action entries in other states. This blocks merging. Reducing conflicts (e.g., by removing braceless body support) would enable MORE merging. But Pass 3 showed that removing conflicts had <2% time impact — the question is whether it significantly impacts ACTION ENTRY count, which was not measured.

### Expression Consolidation Opportunities for Jai (Pass 5 — Actionable)

Current `_expression` has 40 direct alternatives. Potential further consolidation using `token(choice(...))`:

**Tier 1 (same highlight group, no argument differences)**:
- `bake_expression` uses `#bake_arguments`/`#bake_constants` — these are `@keyword.directive`
- `procedure_of_call_expression` uses `#procedure_of_call` — also `@keyword.directive`
- `library_expression` uses `#library` — also `@keyword.directive`
Could merge all 3 into `directive_call` or a new `keyword_directive_expression` using `token(choice(...))`. Saves 2 alternatives.

**Tier 2 (type-like expressions in expression position)**:
- `pointer_type`, `array_type`, `polymorphic_type`, `type_variant` — these are in both `_expression` and `_type`
Could be grouped behind `_type_in_expression` sub-rule. But since they participate in the `[$._expression, $._type]` conflict, grouping alone won't help (the parser expands transitively). ONLY helps if the sub-rule genuinely separates conflict domains.

**Tier 3 (directive expressions with block/expression args)**:
- `run_expression` (`#run`), `code_expression` (`#code`), `insert_expression` (`#insert`) — all take block or expression
These have different structures (run takes optional identifier modifier, code takes optional identifier, insert has complex forms). Consolidation is possible but would lose the distinct node types needed for different semantic handling.

**Estimated impact**: Tier 1 consolidation (40 -> 37 alternatives) would save ~7-10% of entries if combined with `token()`. Based on Phase 3 data, going from 39 to 37 alternatives with `token()` might save ~500-1000 action entries. This is likely INSUFFICIENT to create enough headroom for blocked features (which need 2,000-13,000 entries).

**The path to unlocking blocked features requires MAJOR restructuring** — either the D-style expression hierarchy (which Pass 4 showed breaks named_argument/field_initializer conflict resolution for Jai) or a novel approach not yet attempted.

### Novel Approach: Selective Expression Restriction (Pass 5 — Theoretical)

Instead of the full D-style hierarchy (which broke `named_argument` patterns), consider restricting ONLY the type-construction rules:

```javascript
// NEW: type-constructing expressions reference _type, not _expression
pointer_type: $ => prec(PREC.UNARY, seq('*', field('type', $._type))),  // already does this!
array_type: $ => ... seq('[', field('size', $._expression), ']', field('element', $._type)),  // already does this!
```

Currently, `pointer_type` and `array_type` already reference `$._type`, NOT `$._expression` for their type operand. The issue is that they ARE alternatives in `$._expression` (so they appear in expression-level states).

**Key question**: What if we REMOVE `pointer_type`, `array_type`, `polymorphic_type`, `type_variant`, and `procedure_type` from `_expression` and ONLY keep them in `_type`? Then `_expression` drops from 40 to 35 alternatives.

**Risk**: Expressions like `*ptr` would no longer parse as `unary_expression('*', expr)` could be confused with `pointer_type`. But `unary_expression` handles the `*` prefix already. The actual risk is: can a type appear in an expression position that isn't behind a `:` (type annotation)? Answer: YES — in Jai, `Type.{field=value}` struct literals start with a type expression followed by `.{`. Currently this works because types are in `_expression`.

**Mitigation**: Keep `procedure_type` in `_expression` (needed for lambda type annotations), but remove `pointer_type`, `array_type`, `polymorphic_type` from `_expression` since they're always followed by `.{` or `.[` when used as expression-starters. The struct_literal and array_literal rules already handle these cases by having type fields. Needs careful validation.

**Estimated impact**: 40 -> 35 alternatives could yield ~15-20% state reduction based on the nonlinear relationship. If it brings entries from 65,479 to ~53,000, that frees ~12,000 slots — enough for `#overlay` (needs 2,224) and possibly `<<` prefix dereference (needs 13,055 but might be less with lower baseline).

### call_expression vs parameterized_type Ambiguity (Pass 6 — Deep Research)

**The Problem**: When `identifier(args)` appears inside parentheses — e.g., `(func(args) + 1)` — the parser misinterprets `func(args)` as `parameterized_type` instead of `call_expression`. The outer `()` is parsed as `procedure_type` (bare form) wrapping a `parameterized_type`, instead of `parenthesized_expression` wrapping a `call_expression`. This causes ERROR nodes because subsequent tokens (like `+ 1`) don't make sense after a type.

**Root cause**: The bare `procedure_type` form at grammar.js lines 1002-1009 starts with `(`, which competes with `parenthesized_expression`. When both GLR paths complete without errors, the parser picks `procedure_type(parameterized_type)` over `parenthesized_expression(call_expression)` because of tree comparison tiebreaking (both have 0 dynamic precedence).

**Affected contexts** (experimentally verified):
- `(func(args))` — parsed as `procedure_type(parameterized_type)` WRONG
- `(func(args) + 1)` — ERROR: parameterized_type followed by unexpected `+`
- `(func(args).field)` — ERROR: parameterized_type followed by unexpected `.field`
- `((func(args)))` — nested `procedure_type(procedure_type(parameterized_type))` WRONG
- `(func(a, b, c))` — parsed as `procedure_type(parameterized_type)` WRONG

**Unaffected contexts** (correctly parsed):
- `func(args);` — `call_expression` (expression statement, no outer parens)
- `func(args) + 1` — `call_expression` (binary expression, no outer parens)
- `outer(func(args))` — `call_expression` nested inside `argument_list`
- `if func(args) {}` — `call_expression` (if condition)
- `x := func(args)` — `call_expression` (direct assignment)
- `Table(int).{}` — `call_expression` (followed by `.{` which disambiguates)
- `s: Table(string, int)` — `parameterized_type` (type annotation position, correct)

**GLR Resolution Order** (from `parser.c` lines 840-878):
1. Error cost (lower wins) — if one path has errors, the error-free path wins
2. Dynamic precedence (higher total wins) — `prec.dynamic(N)` accumulates
3. If both have errors, prefer the newer parse
4. Tree comparison — deterministic tiebreaker (earlier subtree wins)

Currently both paths have 0 dynamic precedence, so the tiebreaker picks the procedure_type interpretation.

**How Go solves the same problem** (reference grammar analysis):
Go has `type_conversion_expression` (analogous to `parameterized_type` in expression position) with `prec.dynamic(-1)`. Go's `_type_identifier` inside `_simple_type` also has `prec.dynamic(-1)`. This means when the parser explores both the call and type-conversion paths, the type path accumulates -1 and the call path has 0. Call wins.

Go's critical advantage: its `function_type` starts with `func`, NOT `(`. So `(identifier(args))` can never be parsed as a function type wrapping a type argument. Jai doesn't have this luxury because bare `procedure_type` starts with `(`.

**How Rust avoids the problem entirely**: Rust uses `<>` for generic type arguments (`Vec<int>`), completely separating the syntax from function calls (`func(args)`). No ambiguity possible.

**How D avoids the problem entirely**: D uses `!` for template instantiation (`Array!(int)`), separating the syntax from function calls. No ambiguity possible.

**How Odin handles it**: Odin has `proc_call` with `prec.dynamic(op_prec.r_unary)` (high dynamic precedence), ensuring procedure calls always win over type interpretations. Odin's `generic_type` uses `/` syntax (`typeid/T`), not `()`.

**How Zig handles it**: Zig avoids the problem because type instantiation uses `{}` (struct initializer), not `()`.

#### Evaluated Strategies

**Strategy 1: `prec.dynamic(-1)` on bare `procedure_type` form [RECOMMENDED]**

Wrap the bare procedure_type form (lines 1002-1009) in `prec.dynamic(-1, ...)`:
```javascript
procedure_type: $ => choice(
  // Explicit #type prefix (unaffected)
  seq('#type', '(', commaSep(choice($.parameter, $._type)), ')',
    optional(seq('->', $._type)), repeat($.procedure_modifier)),
  // Bare form — penalize so call_expression wins in ambiguous cases
  prec.dynamic(-1, seq('(', commaSep(choice($.parameter, $._type)), ')',
    optional(seq('->', $._type)), repeat($.procedure_modifier))),
),
```

**Why it works**: When `(identifier(args))` is parsed:
- Path A: `parenthesized_expression(call_expression)` — total dynamic prec = 0
- Path B: `procedure_type(parameterized_type)` — total dynamic prec = -1 (from bare procedure_type)
- Path A wins (0 > -1)

**When the -1 doesn't matter**: In type annotation positions like `x: (int) -> void`, only the type interpretation exists (no competing `parenthesized_expression`), so the -1 is irrelevant.

**When procedure_type is the ONLY valid parse**: In `x := (int) -> void;`, the `parenthesized_expression` path would fail (can't continue `-> void` after `)` closes the parens), creating an error cost. Error cost trumps dynamic precedence, so procedure_type still wins.

- **Risk**: LOW — only affects GLR disambiguation, not which rules are valid
- **Cost**: Zero new states, zero new conflicts, zero new action entries (dynamic prec is stored on reduce actions, not in the parse table)
- **Effort**: ~1 hour to implement + regenerate + test
- **Side effects**: `(identifier)` as a bare procedure type (single param, no return type) would also lose to `parenthesized_expression(identifier)`. This is actually DESIRABLE for syntax highlighting — `(x)` should be a parenthesized expression, not a procedure type with no return type.

**Strategy 2: `prec.dynamic(-1)` on `parameterized_type` + `prec.dynamic(1)` on `call_expression`**

Apply dynamic prec to BOTH rules:
```javascript
call_expression: $ => prec.dynamic(1, prec(PREC.CALL, seq(...))),
parameterized_type: $ => prec.dynamic(-1, prec(PREC.CALL, seq(...))),
```

**Why it works**: When `(identifier(args))` is parsed:
- Path A: `parenthesized_expression(call_expression)` — accumulates +1
- Path B: `procedure_type(parameterized_type)` — accumulates -1
- Path A wins (+1 > -1)

**Risk**: MEDIUM — `prec.dynamic(-1)` on `parameterized_type` affects type annotation positions too. In `x: Table(int)`, the conflict `[$._expression, $._type]` means the parser also explores `call_expression` as an alternative. With +1 on call and -1 on parameterized_type, the call interpretation wins (+1 > -1), causing `x: Table(int)` to parse as `call_expression` instead of `parameterized_type`. This breaks type annotation highlighting.

**Mitigation**: Could boost `parameterized_type` when accessed through `_type` with `prec.dynamic(2)`, but this creates a complex web of dynamic prec values that's hard to reason about.

- **Risk**: MEDIUM-HIGH due to type annotation side effects
- **Cost**: Zero new states
- **Effort**: ~2-3 hours to implement + extensive testing of type annotations
- **Not recommended** without Strategy 1 failing first

**Strategy 3: Remove bare `procedure_type` from `_expression`**

Keep procedure_type in `_expression` only with the `#type` prefix form. Remove the bare form from `_expression` (keep it in `_type` only).

**Why it works**: Without bare procedure_type in `_expression`, `(identifier(args))` in expression position has no competing type interpretation through procedure_type.

**Risk**: HIGH — The `[$._expression, $._type]` conflict allows `_type` alternatives to be explored in expression contexts. Removing bare procedure_type from `_expression` might NOT fully prevent it from being explored (depends on whether the GLR conflict propagates the `_type` alternatives). Additionally, it reduces `_expression` alternatives by 1, which provides a small state count improvement.

The bigger risk: procedure_type appearing as a value (e.g., `callback :: (int) -> void;` in `_declaration_value` which inlines `_expression`). If bare procedure_type is removed from `_expression`, these cases would need to go through `_type` via the conflict. This SHOULD work but needs validation.

- **Risk**: HIGH — complex interaction with GLR conflicts, may not fully solve the problem
- **Cost**: Potentially reduces states (1 fewer `_expression` alternative)
- **Effort**: ~4-6 hours including regeneration and comprehensive testing
- **Not recommended** as primary strategy

**Strategy 4: Split procedure_type into separate rules for each position**

Create `procedure_type_explicit` (with `#type`) and `procedure_type_bare` (without `#type`):
- `_expression`: contains `procedure_type_explicit` only
- `_type`: contains both `procedure_type_explicit` and `procedure_type_bare`

**Why it works**: Same principle as Strategy 3 but more surgically targeted. The bare form can't compete in expression contexts.

**Risk**: MEDIUM — Same concerns as Strategy 3 about `_declaration_value` inlining `_expression`. Also doubles the number of procedure_type-related rules in the grammar, potentially adding states instead of removing them.

- **Risk**: MEDIUM
- **Cost**: May increase states due to rule duplication
- **Effort**: ~4-6 hours
- **Only consider** if Strategy 1 fails

**Strategy 5: External scanner for parenthesized_expression vs procedure_type**

Add an external scanner token `OPEN_PAREN_EXPR` that matches `(` in contexts where only expressions are valid (not types). The scanner would examine context to decide.

**Risk**: VERY HIGH — Context-dependent `(` disambiguation requires the scanner to understand the full parse state, which it can't do (scanner only sees characters, not the parse stack). The `valid_symbols` mechanism provides some context awareness, but distinguishing "expression-only `(`" from "could-be-type `(`" requires information that's not available to the scanner.

- **Not recommended** — impractical

**Strategy 6: Combine `parameterized_type` and `call_expression` into one rule**

Create a unified `call_or_parameterized` rule that handles both syntaxes. In `_expression`, use this rule. In `_type`, use `parameterized_type` (type-specific version).

**Why it might work**: By having only ONE rule for `identifier(args)` in expression contexts, there's no ambiguity to resolve. The `_type` version would be used only in type annotation positions.

**Risk**: MEDIUM — This changes the node type structure. `call_expression` and `parameterized_type` are currently separate node types used by highlight queries and navigation queries. Merging them would require updating all queries. Also, `call_expression` accepts `_expression` as its function (allowing `expr(args)`), while `parameterized_type` only accepts `identifier` or `scoped_identifier`. A unified rule would need the broader acceptance.

- **Risk**: MEDIUM
- **Cost**: May reduce conflicts (removes `[$._expression, $.parameterized_type]` conflict)
- **Effort**: ~6-8 hours including query updates
- **Consider** as alternative if Strategy 1 has unexpected issues

#### Recommended Implementation Order

1. **Try Strategy 1 first** (`prec.dynamic(-1)` on bare procedure_type) — lowest risk, lowest effort, addresses root cause directly
2. **If Strategy 1 doesn't work** (e.g., the dynamic precedence is not propagated as expected, or it causes unexpected side effects), try Strategy 2 with careful testing of type annotations
3. **If neither works**, investigate Strategy 4 (split procedure_type) or Strategy 6 (unified call rule)

#### Expected Impact

If Strategy 1 works, it fixes the parenthesized-call misparse for:
- All `(func(args) + expr)` patterns in module files
- All `(func(args).field)` patterns
- All `(func(a, b, c))` patterns

This was identified as affecting ~19 module files and ~8 example files in the initial problem description. The actual impact may be larger since the call/type ambiguity can cascade.

### "Unnecessary" Conflicts: Deep Source Code Analysis (Pass 7 — DEFINITIVE FINDING)

**Source**: `build_parse_table.rs` lines 258, 348-364, 849-857

**Mechanism**: The parse table builder tracks "unnecessary" conflicts as follows:
1. `actual_conflicts` starts as a COPY of all `expected_conflicts` (line 258)
2. When a conflict IS encountered during table building, it gets REMOVED from `actual_conflicts` (line 855: `self.actual_conflicts.remove(&actual_conflict);`)
3. After building ALL states, whatever REMAINS in `actual_conflicts` was declared but never encountered (line 348-364: logged as "unnecessary")

**Key finding**: `expected_conflicts` (parse-level GLR conflicts) have NO direct effect on the lexer or lex table construction. The `TokenConflictMap` is built entirely from the `LexicalGrammar` analysis (character-level token overlap detection in `token_conflicts.rs`). It does NOT reference `expected_conflicts` at all.

**Therefore**: An "unnecessary" conflict declaration (one that is never encountered during table building) has ZERO effect on the generated parser. The parse table is identical whether or not the conflict is declared. Removing an "unnecessary" conflict should be perfectly safe.

**BUT**: The Pass 6 observation that removing the `!= disambiguation` conflicts broke `!=` tokenization needs re-examination. If removing those 4 conflict declarations truly broke things, the cause is NOT that the declarations influence the parser. The likely explanations are:
1. The conflicts ARE actually encountered but the exact rule set reported as "unnecessary" doesn't match the declaration due to intermediate rule expansion. The parser generator compares conflicts after sorting and deduping symbols; if the actual conflict involves auxiliary symbols that get expanded, the matching could fail even though the conflict is real.
2. A secondary effect: removing the declarations may cause a different conflict to become an ERROR (because without the whitelisting, the build would fail). If `tree-sitter generate` was run with a flag that ignores errors, or if the error was masked, the resulting parser could be subtly different.
3. Coincidental: another change was made simultaneously that caused the breakage.

**Recommendation**: Re-test removing these 4 "unnecessary" conflicts one at a time, verifying each time that `tree-sitter generate` completes successfully (no unresolved conflict errors) before testing the resulting parser. If generation itself fails, the conflicts ARE needed (the "unnecessary" warning is a false positive).

### Full Build Pipeline (Pass 7 — Source Code Trace)

**Source**: `build_tables.rs` lines 40-116

The build pipeline runs in this exact order:
1. `ParseItemSetBuilder::new()` — Compute FIRST/LAST sets for all symbols
2. `get_following_tokens()` — For each terminal, compute which terminals can follow it (uses productions and extras)
3. `build_parse_table()` — Build the raw parse table (GLR states, conflict resolution). This is where `expected_conflicts` are checked.
4. `TokenConflictMap::new()` — Analyze all terminal-token-pair overlap characteristics (matching strings, prefixes, continuations). Uses `following_tokens` from step 2.
5. `CoincidentTokenIndex::new()` — Record which terminal pairs appear in the same parse state. Built FROM the parse table (step 3).
6. `identify_keywords()` — Determine which tokens can be keyword-extracted. Uses coincident index + token conflict map.
7. `populate_error_state()` — Fill in error recovery state (state 0). Uses conflict-free token analysis.
8. `populate_used_symbols()` — Mark which symbols are actually used in the table.
9. `minimize_parse_table()` — State minimization. Merges compatible states. This is where the external token penalty applies.
10. `build_lex_table()` — Build the lex tables. Uses token_conflict_map, coincident_token_index, keywords. Merges lex states that have compatible token sets.
11. `populate_external_lex_states()` — Associate external tokens with parse states.
12. `mark_fragile_tokens()` — Mark tokens that overlap with other valid tokens in the same state.
13. `render()` (in `render.rs`) — Convert tables to C code. This is where the action entry limit (u16::MAX) is checked.

**Key insight for optimization**: Steps 3 and 9 are the two places where state count is determined. Step 3 creates the raw states; step 9 reduces them. Reducing raw states (fewer expression alternatives, less GLR splitting) is the primary lever. Enabling more state merging in step 9 (fewer external tokens, fewer token conflicts) is the secondary lever.

### Zig Hierarchy Confirmation (Pass 7 — Verified from Source)

**Zig's expression hierarchy** (source: `reference-grammars/tree-sitter-zig/grammar.js`):
```
expression (19 alts) -> type_expression (6 alts) -> primary_type_expression (33 alts)
```

**Postfix operations in Zig are in primary_type_expression and reference $.expression (top level)**:
```javascript
call_expression:        prec(PREC.MEMBER, seq(field('function', $.expression), ...))
field_expression:       prec(PREC.MEMBER, seq(optional(field('object', $.expression)), '.', ...))
index_expression:       prec(PREC.MEMBER, seq(field('object', $.expression), '[', ...))
dereference_expression: prec(PREC.MEMBER, seq($.expression, '.*'))
```

**Type-constructing rules reference $.type_expression (MID level)**:
```javascript
pointer_type: prec.right(1, seq('*', repeat(modifiers), $.type_expression))
slice_type:   prec.right(1, seq('[', optional(...), ']', repeat(modifiers), $.type_expression))
array_type:   prec(1, seq('[', $.expression, optional(...), ']', $.type_expression))
nullable_type: prec(1, seq('?', choice($.type_expression, ...)))
```

**Result**: 1,836 states, 9.0s generation, 5.6MB parser.c

**WHY this works despite postfix ops referencing the top level**:
The hierarchy creates a genuine separation because type-construction states (after `*`, after `]` in array_type, etc.) only need transitions for `type_expression` alternatives (6), not all 19 `expression` alternatives. The parser generator can then merge these type-construction states more aggressively, because they share a smaller set of valid continuations.

The net effect: states inside type-construction contexts have 6 possible continuations. States inside expression contexts have 19. The 33 primary_type_expression alternatives are shared but accessed through either path. This eliminates the multiplicative state explosion that occurs when ALL alternatives are at the same level.

### D Hierarchy Deep Dive (Pass 7 — Verified from Source)

**D's expression hierarchy** (source: `reference-grammars/tree-sitter-d/grammar.js`):
```
_expr (5 alts: assignment, ternary, binary, ternary, _unary_expr)
  -> _unary_expr (11 alts: _primary_expr, unary, new, delete, assert, cast, throw, call, index, postfix, property)
    -> _primary_expr (22+ alts: identifier, typeof, typeid, array_literal, is_expr, function_literal, etc.)
```

**Critical: Postfix operations in D reference `$._unary_expr` (MID level), NOT `$._expr`**:
```javascript
call_expression:     prec.left(choice(seq($._unary_expr, $.named_arguments), ...))
index_expression:    choice(seq($._unary_expr, "[", ...))
property_expression: choice(..., prec.left(seq($._unary_expr, ".", ...)))
```

**Result**: 8,061 states, 16.5s generation, 22MB parser.c, 42 conflicts

**Comparison with Jai (same 42 conflicts)**: D gets 4.8x fewer states. The difference is entirely due to D's expression hierarchy restricting which alternatives are reachable from postfix-continuation states.

### Concrete Expression Hierarchy Plan for Jai (Pass 7 — Actionable)

Based on the Zig and D patterns, here is a concrete restructuring plan:

**Proposed 3-level hierarchy**:

```javascript
// Level 1: _expression (20 alts) — control flow, binary, unary, assignment
_expression: $ => choice(
    $.unary_expression,
    $.binary_expression,
    $.cast_expression,
    $.autocast_expression,
    $.range_expression,
    $.ifx_expression,
    $.lambda_expression,
    $.run_expression,
    $.code_expression,
    $.insert_expression,
    $.bake_expression,
    $.procedure_of_call_expression,
    $.inline_expression,
    $.library_expression,
    $.import_expression,
    $.char_expression,
    $.here_string,
    $._postfix_expression,  // NEW: mid-level
),

// Level 2: _postfix_expression (12 alts) — call, field, index, struct/array literals
_postfix_expression: $ => choice(
    $.call_expression,
    $.field_expression,
    $.index_expression,
    $.dereference_expression,
    $.struct_literal,
    $.array_literal,
    $._primary_expression,  // NEW: lowest level
),

// Level 3: _primary_expression (15 alts) — identifiers, literals, types
_primary_expression: $ => choice(
    $.identifier,
    $.backslash_identifier,
    $.scoped_identifier,
    $._literal,
    $.parenthesized_expression,
    $.unary_dot_expression,
    $.compile_time_constant,
    $.intrinsic_call,
    $.directive_call,
    $.backtick_identifier,
    $.procedure_type,
    $.pointer_type,
    $.array_type,
    $.polymorphic_type,
    $.type_variant,
    $.procedure_definition,
),
```

**Critical change**: Postfix operations reference `$._postfix_expression` instead of `$._expression`:
```javascript
call_expression: $ => prec(PREC.CALL, seq(
    field('function', $._postfix_expression),  // WAS: $._expression
    field('arguments', $.argument_list),
)),
field_expression: $ => prec(PREC.FIELD, seq(
    field('object', $._postfix_expression),  // WAS: $._expression
    '.',
    field('member', choice($.identifier, $.backslash_identifier)),
)),
index_expression: $ => prec(PREC.POSTFIX, seq(
    field('object', $._postfix_expression),  // WAS: $._expression
    '[',
    field('index', $._expression),
    ']',
)),
```

**Why `$._postfix_expression` is the right mid-level for Jai**: Unlike D, Jai allows `(a + b)(args)` (call on any expression), which means `parenthesized_expression` must be reachable from `_postfix_expression`. It IS, through `_primary_expression`. And `parenthesized_expression` wraps `$._expression`, so any expression can be called by wrapping in parens: `(a + b)(args)` parses as `call_expression(parenthesized_expression(binary_expression(...)), ...)`.

**Expected impact**:
- State count: ~39,213 -> estimated 8,000-15,000 (based on D getting 8,061 with same conflict count)
- Action entries: ~65,479 -> estimated 15,000-30,000 (proportional to state reduction)
- Generation time: ~5 min -> estimated 30-60 sec
- parser.c size: ~111MB -> estimated 20-40MB
- This would create ~35,000-50,000 slots of action entry headroom, enough to add ALL blocked features

**Risks and mitigations**:
1. **Braceless body conflicts**: The `[$.for_statement, $.unary_expression, $.call_expression]` conflicts reference `$.call_expression`. If `call_expression` is in `_postfix_expression` and `for_statement` iterates over `$._expression`, the conflict may need updating. The key is that after the iterable expression, the parser needs to decide if `(` starts a call or the body. This conflict should still work because the conflict declaration names rules, not hierarchy levels.
2. **Named argument / field initializer**: `[$.named_argument, $.assignment_expression]` and `[$._expression, $.field_initializer]` may need adjustment since field_initializer is inside struct_literal which is in `_postfix_expression`.
3. **`[$._expression, $._type]` conflict**: This must propagate through the hierarchy levels. If `_type` alternatives overlap with `_primary_expression` alternatives (which they do: pointer_type, array_type, polymorphic_type), the conflict may need to become `[$._primary_expression, $._type]` or similar.
4. **Highlight queries**: No change needed if `_postfix_expression` and `_primary_expression` are hidden (underscore prefix). The named node types (call_expression, identifier, etc.) remain the same.

**Implementation order**:
1. Create `_primary_expression` first (pure grouping, no reference changes). Verify generation completes.
2. Create `_postfix_expression` (pure grouping). Verify generation completes.
3. Change `call_expression.function` to reference `$._postfix_expression`. This is the CRITICAL change. Measure state count and action entries.
4. Change `field_expression.object` and `index_expression.object` to reference `$._postfix_expression`. Measure again.
5. If struct_literal and array_literal can reference `$._postfix_expression` for their type, change those too.
6. Update conflict declarations as needed.
7. Run full test suite.

**Time estimate**: 8-16 hours for the full restructuring, including testing and debugging.

### Build Pipeline Optimization Sequence (Pass 7 — Strategic)

Given the findings, the optimal sequence for improving the Jai grammar is:

1. **Expression hierarchy restructuring** (highest impact, highest effort)
   - Expected: 3-5x state reduction, 3-5x action entry reduction
   - Unblocks: ALL currently-blocked features
   - Time: 8-16 hours

2. **Additional `token(choice(...))` consolidation** (medium impact, low effort)
   - Consolidate remaining directive expressions: bake, procedure_of_call, library -> 1 rule
   - Expected: 5-10% additional reduction on top of hierarchy
   - Time: 2-4 hours

3. **External scanner for `<<` prefix dereference** (only needed if hierarchy doesn't create enough headroom)
   - After hierarchy, action entries should be ~15,000-30,000 (vs 65,535 limit)
   - `<<` as unary needs ~2,000-3,000 entries (reduced from 13,000 due to smaller baseline)
   - External scanner approach may not even be needed if hierarchy creates enough headroom
   - Time: 4-8 hours

4. **Catch-all struct directive** (for `#overlay`, `#align`, `#elsewhere`)
   - After hierarchy, adding these as a single `struct_directive` rule should be within budget
   - Time: 2-4 hours

5. **Backslash identifiers** (external scanner, independent)
   - Can be done at any point, independent of hierarchy
   - Time: 4-8 hours

### Per-Rule State Distribution (Pass 9 — `--report-states-for-rule -`)

**CRITICAL TOOL**: `tree-sitter generate --report-states-for-rule -` lists every rule and its state contribution. This is the primary profiling tool for grammar optimization.

**Jai grammar state distribution** (39,362 total states, 44 conflicts):

| Rule | States | % of Total | Notes |
|------|--------|------------|-------|
| binary_expression | 9,559 | 24.3% | Refs `$._expression` on both sides |
| declaration | 9,119 | 23.2% | Complex `:/:=/::` choice |
| dereference_expression | 8,774 | 22.3% | Refs `$._expression` as operand |
| struct_literal | 8,089 | 20.5% | Refs `$._expression` as type + contents |
| array_literal | 8,059 | 20.5% | Refs `$._expression` as type + contents |
| index_expression | 7,952 | 20.2% | Refs `$._expression` as object |
| range_expression | 7,934 | 20.2% | Refs `$._expression` on both sides |
| field_expression | 7,811 | 19.8% | Refs `$._expression` as object |
| call_expression | 7,794 | 19.8% | Refs `$._expression` as function |
| procedure_type | 5,170 | 13.1% | Complex param/return types |
| lambda_expression | 3,294 | 8.4% | |
| for_statement | 2,624 | 6.7% | Braceless body conflicts |
| ifx_expression | 2,195 | 5.6% | |
| _expression | 1,701 | 4.3% | |
| code_expression | 1,605 | 4.1% | |
| procedure_definition | 1,550 | 3.9% | |
| unary_expression | 1,392 | 3.5% | |
| cast_expression | 1,347 | 3.4% | |
| array_type | 1,184 | 3.0% | Refs `$._expression` for size |
| struct_definition | 120 | 0.3% | Relatively cheap! |

**Key insight**: 6 postfix operations (call, field, index, dereference, struct_literal, array_literal) each consume ~8,000 states because they reference `$._expression` for their object/operand. **This is the single largest optimization target.** If these referenced a mid-level `$._postfix_expression` instead, each would drop from ~8,000 to ~1,000-2,000 states.

**Comparison — Zig per-rule states** (1,836 total, 6 conflicts, 3-level hierarchy):

| Rule | States | Jai Equivalent | Jai States | Ratio |
|------|--------|----------------|------------|-------|
| binary_expression | 437 | binary_expression | 9,559 | 21.9x |
| call_expression | 397 | call_expression | 7,794 | 19.6x |
| field_expression | 405 | field_expression | 7,811 | 19.3x |
| index_expression | 403 | index_expression | 7,952 | 19.7x |
| struct_declaration | 43 | struct_definition | 120 | 2.8x |
| expression | 127 | _expression | 1,701 | 13.4x |

The 19-22x ratio for postfix operations confirms that the expression hierarchy is the primary driver. Zig's hierarchy restricts type-construction states to 6 alternatives and postfix states share that reduced set.

**Comparison — Odin per-rule states** (3,955 total, 6 conflicts, struct_type in _simple_type):

| Rule | States | Key Feature |
|------|--------|-------------|
| _expression | 483 | Flat, 20 alts |
| proc_call | 470 | |
| binary_expression | 459 | |
| struct_type | 252 | In `_simple_type`, not in `_expression` |
| array_type | 250 | |

Odin gets struct_type for only 252 states because struct_type is in `_type`, not `_expression`. The `_type` and `_expression` are separate hierarchies with overlap handled by conflicts.

**Comparison — C per-rule states** (2,015 total, 17 conflicts, struct_specifier in type_specifier):

| Rule | States | Key Feature |
|------|--------|-------------|
| binary_expression | 216 | |
| call_expression | 157 | |
| struct_specifier | 22 | In type_specifier, costs only 22 states! |

C achieves struct_specifier in type for only 22 states because C has far fewer expression alternatives and a simpler expression model.

### Anonymous Struct/Union in Type Position — Cross-Grammar Analysis (Pass 9)

**Research question**: How do reference grammars handle anonymous struct/union in type position?

| Grammar | struct in _type? | struct in _expression? | States | Approach |
|---------|-----------------|----------------------|--------|----------|
| **C** | YES (type_specifier) | NO | 2,015 | struct_specifier in type_specifier, [type_specifier, expression] conflict |
| **C++** | YES (type_specifier) | NO | 11,551 | Same as C |
| **Go** | YES (_simple_type) | NO | 1,442 | struct_type in _simple_type, [$._simple_type, $._expression] conflict |
| **Zig** | YES (primary_type_expression) | YES (via hierarchy) | 1,836 | 3-level hierarchy: expr -> type_expr -> primary_type_expr containing struct_declaration |
| **Odin** | YES (_simple_type) | NO (but reachable via conflict) | 3,955 | struct_type in _simple_type |
| **Rust** | NO | NO | 3,825 | struct_item is a top-level declaration only, not a type |
| **D** | NO | NO | 8,061 | struct_declaration is a declaration only, not in type or expression |
| **Jai** | NO (blocked) | NO (state explosion) | 39,362 | Would cause overflow if added to _type due to flat expression structure |

**Key finding**: ALL grammars that support anonymous struct in type position either:
1. Have a MUCH simpler expression model (C: 24+18 alts, Go: 23 alts) — OR
2. Use a hierarchical expression structure (Zig: 3 levels with 19/6/33 split)

Jai's flat 40-alternative `_expression` with 44 GLR conflicts makes adding struct_definition to `_type` infeasible WITHOUT first restructuring expressions into a hierarchy.

**After hierarchy restructuring** (estimated): Adding struct_definition/union_definition to `_type` should cost ~100-250 additional states (based on the Zig and Odin data) instead of causing overflow. This would fix ~25 module files.

### Action Budget Verification (Pass 9 — CORRECTED)

**Current state**: Max action entry index = **65,133** (not 65,479 as previously reported). Remaining: **402 slots** (65,535 - 65,133).

This provides slightly more headroom than previously believed but still means ANY grammar change that creates more than ~200 unique action entries will overflow. The expression hierarchy restructuring remains the ONLY viable path to unlock new features.

### 65,535 Limit is a HARD ABI CONSTRAINT (Pass 9 — CONFIRMED)

Investigated every possible path to increase the limit:

1. **`ts_parse_table` is `uint16_t`** — The large state table stores action indices as `uint16_t`. Cannot store values > 65,535.
2. **`ts_small_parse_table` is `uint16_t`** — Same constraint for small states.
3. **`ts_language_lookup` returns `uint16_t`** — The runtime API returns a `uint16_t` index.
4. **No LARGE_TABLE_MODE exists** — Searched the entire tree-sitter codebase (v0.27.0), no configuration or compile flag to increase the limit.
5. **No planned change** — Increasing would require a new ABI version (ABI 16+), which is an incompatible change requiring all editor integrations to update.
6. **Local patching is impossible** — Even if the generator check is removed, the generated C code would overflow `uint16_t` and wrap around, producing an incorrect parser.

**The ONLY path is reducing the number of unique action entries below 65,535.**

### `--report-states-for-rule` Flag (Pass 9 — NEW TOOL)

`tree-sitter generate --report-states-for-rule -` lists all rules sorted by descending state count. Use `-` for all rules, or a specific rule name for just that rule.

This is the PRIMARY profiling tool for grammar optimization. It directly identifies which rules are most expensive and should be the focus of optimization efforts.

Other useful flags:
- `--report-states-for-rule RULE_NAME` — Report only for a specific rule
- `--no-minimize` — Disable state merging optimization (produces raw unoptimized state count)

### Revised Expression Hierarchy Plan (Pass 9 — Data-Driven)

Based on the per-rule state profiling, the hierarchy plan from Pass 7 is CONFIRMED but with refined targets:

**Primary optimization target**: The 6 postfix operations consuming 7,800-8,800 states EACH:
- call_expression (7,794) → change `.function` from `$._expression` to `$._postfix_expression`
- field_expression (7,811) → change `.object` from `$._expression` to `$._postfix_expression`
- index_expression (7,952) → change `.object` from `$._expression` to `$._postfix_expression`
- dereference_expression (8,774) → change `.operand` from `$._expression` to `$._postfix_expression`
- struct_literal (8,089) → change `.type` from `$._expression` to `$._postfix_expression`
- array_literal (8,059) → change `.type` from `$._expression` to `$._postfix_expression`

**Secondary optimization target**: range_expression (7,934) and binary_expression (9,559) reference `$._expression` on both sides. Binary must stay at top level (D does the same). Range could potentially reference `$._postfix_expression` if ranges only operate on postfix expressions (needs Jai language validation).

**Expected impact calculation** (based on Zig ratios):
- Current: 39,362 states
- Postfix operations drop from avg 8,080 to avg 400 (20x reduction each)
- 6 operations * (8,080 - 400) = 46,080 state savings
- BUT states are shared, so actual savings ~60-70% of theoretical
- Expected final: 10,000-15,000 states
- Expected action entries: 15,000-30,000 (vs current 65,133)
- Headroom created: 35,000-50,000 action entry slots

**This is sufficient to add ALL blocked features**: `<<` prefix deref, `#overlay`, `#align`, anonymous struct/union in `_type`, backslash identifiers.

### Why This Works: The State Sharing Principle (Pass 9 — Theoretical Foundation)

When a rule like `call_expression` references `$._expression` as its function operand, the parser must create states for every possible expression that could appear before `(`. With 40 expression alternatives, each with their own continuation states, this creates a massive state fan-out.

When `call_expression` references `$._postfix_expression` instead (12 alternatives), the parser only needs states for 12 possible expression forms before `(`. The key insight: `parenthesized_expression` is one of the 12, so `(a + b)(args)` still works — the `parenthesized_expression` "elevates" any expression to postfix level.

The state savings come from THREE mechanisms:
1. **Fewer raw states generated**: Fewer alternatives = fewer possible parse paths = fewer states in the initial table
2. **More states merge**: With fewer distinct continuations, more states become compatible for merging
3. **Fewer unique action entries**: Fewer distinct shift targets = more entry deduplication

This is exactly what Zig and D achieve. D has 42 conflicts (same as Jai) but only 8,061 states because its hierarchy restricts postfix operations to `$._unary_expr` (11 alternatives) instead of `$._expr` (5 top-level alternatives that transitively expand to 33+).

### Corrected Implementation Approach (Pass 9 — Refined from Pass 7)

**The D model is SAFER than the Zig model for Jai because**:
- D has the SAME conflict count as Jai (42)
- D's postfix operations reference the MID level, not the TOP level
- D achieves 4.8x fewer states than Jai with the same conflict count
- D doesn't put struct/union/enum in type positions (same as Jai currently)

**The Zig model is MORE AMBITIOUS**:
- Only 6 conflicts (vs Jai's 44)
- Puts struct/enum/union in the bottom of the hierarchy (reachable from expression)
- Uses supertypes for clean query handling
- Achieves the lowest state count of any language with struct-in-type support

**Recommended approach for Jai**: Start with the D model (restrict postfix references to mid-level). If successful, optionally adopt aspects of the Zig model (adding struct to _type via the hierarchy).

**Specific changes needed**:
```javascript
// 1. Create mid-level rule
_postfix_expression: $ => choice(
    $.call_expression,
    $.field_expression,
    $.index_expression,
    $.dereference_expression,
    $.struct_literal,
    $.array_literal,
    $._primary_expression,
),

// 2. Create bottom-level rule
_primary_expression: $ => choice(
    $.identifier,
    $.backslash_identifier,
    $.scoped_identifier,
    $._literal,
    $.parenthesized_expression,  // CRITICAL: allows (expr)(args) pattern
    $.unary_dot_expression,
    $.compile_time_constant,
    $.intrinsic_call,
    $.directive_call,
    $.backtick_identifier,
    $.procedure_type,
    $.pointer_type,
    $.array_type,
    $.polymorphic_type,
    $.type_variant,
    $.procedure_definition,
),

// 3. Update _expression to use hierarchy
_expression: $ => choice(
    $.unary_expression,
    $.binary_expression,
    $.cast_expression,
    $.autocast_expression,
    $.range_expression,
    $.ifx_expression,
    $.lambda_expression,
    $.run_expression,
    $.code_expression,
    $.insert_expression,
    $.bake_expression,
    $.procedure_of_call_expression,
    $.inline_expression,
    $.library_expression,
    $.import_expression,
    $.char_expression,
    $.here_string,
    $._postfix_expression,  // replaces all postfix+primary alternatives
),

// 4. Change postfix operation references
call_expression: $ => prec(PREC.CALL, seq(
    field('function', $._postfix_expression),  // WAS: $._expression
    field('arguments', $.argument_list),
)),
field_expression: $ => prec(PREC.FIELD, seq(
    field('object', $._postfix_expression),    // WAS: $._expression
    '.',
    field('field', choice($.identifier, $.backslash_identifier)),
)),
// ... same for index_expression, dereference_expression, struct_literal, array_literal
```

**Critical risk area**: The `[$._expression, $._type]` conflict currently allows `_type` alternatives to be explored in expression positions. With the hierarchy, this conflict may need to become `[$._primary_expression, $._type]` since the shared alternatives (pointer_type, array_type, polymorphic_type) are now in `_primary_expression`. This needs careful testing.

**Braceless body conflict updates**: Conflicts like `[$.for_statement, $.unary_expression, $.call_expression]` should still work because conflict declarations reference NAMED rules, not hierarchy levels. `call_expression` is still a named rule regardless of where it appears in the hierarchy.
