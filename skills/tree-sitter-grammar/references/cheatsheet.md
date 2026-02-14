# Tree-Sitter Grammar Development Cheatsheet

> **tree-sitter version**: 0.26.5 (cargo install)
> **ABI**: 15 (default with `tree-sitter.json`)
> **Sources**: Official docs, 17 reference grammars
> **Last updated**: 2026-02-14

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
- **Private sub-rules (grouping)**: Moving alternatives behind a `_private_rule` has ZERO impact on states or generation time. The parser generator expands all alternatives transitively.
- **Inlining intermediate rules**: Inlining `_expression_or_list` INCREASED generation time by 33% (8 min vs 6 min). Inlining adds alternatives at every use site.
- **Consolidation without `token()`**: Merging 9 node types into 3 without using `token()` INCREASED time by 29% (7:45 vs 6:00). Parser generator heuristics break down.
- **Reducing conflict count alone**: Removing 8 braceless-body conflicts had <2% impact on generation time. Conflicts affect parser SIZE but not generation TIME.

### The 65,535 State Limit
- Parser state IDs are 16-bit: max 65,535 states
- Current Jai grammar: 40,044 states with 42 GLR conflicts (108MB parser.c, 294 tests passing)
- Adding constructs to `_expression` risks exceeding this
- **`_expression` alternative count drives state count superlinearly**

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

## Reference Grammar Comparison

| Grammar | Lines | Prec Levels | Conflicts | Scanner | Generation Time |
|---------|-------|-------------|-----------|---------|----------------|
| Go | 983 | 6 | 8 | None | ~2s |
| Odin | 960 | 11 | Many | None | ~3s |
| Rust | 1600+ | 15 | 10 | 233 lines | ~10s |
| Zig | 1200+ | 11 | 6 | None | ~5s |
| D | 2580 | 15+ | Many | 300 lines | ~15s |
| **Jai** | **1340+** | **17** | **42** | **220 lines** | **~6 min** |

### Key Observations
- Jai's generation time is driven by `_expression` having 39 alternatives (was 49 before consolidation). Other grammars have 15-25.
- 17 precedence levels is high but within safe range
- 43 GLR conflicts is high — reduced from 52 via strategic conflict elimination (12% parser size reduction)
- 220-line scanner is moderate (comparable to Rust)
- Grammar is closest to Odin in design but with Rust-level scanner complexity
- **`_expression` alternative count is the primary driver** of generation time. Conflict count affects parser SIZE but not generation TIME. The `token(choice(...))` technique for consolidating keyword-like alternatives gives the best cost/benefit ratio.

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

### Issue: Parse table action overflow (>65,535 actions)
**Problem**: Adding new alternatives to rules that interact with `_expression` or `_struct_member` can cause per-state action counts to exceed the 65,535 hard limit. This is distinct from the state count limit — you can have few states but still overflow actions within a single state.
**Observed cases** (from Jai grammar):
- `<<` as unary prefix operator: 78,534 actions — the `<<` token already serves as binary shift, and adding it as unary creates massive ambiguity across all expression states.
- `#overlay` in `_struct_member`: 67,759 actions — struct body alternatives multiply with expression alternatives.
- `#align N` as struct_field suffix: 78,465 actions — the expression argument creates unresolvable conflict between declaration and struct_field rules.
**Diagnostic**: `tree-sitter generate` error: "ENOBUFS: no buffer space available" with message showing action count.
**Mitigation**: No workaround exists short of fundamentally restructuring the grammar to reduce the number of expression alternatives. These features must be documented as known limitations.
