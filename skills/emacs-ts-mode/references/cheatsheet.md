# Emacs Tree-Sitter Mode Cheatsheet

## Mode Skeleton

Every tree-sitter mode follows this structure:

```elisp
;;; my-ts-mode.el --- Major mode for MyLang using tree-sitter -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))

;;; Code:

(require 'treesit)
(eval-when-compile (require 'rx))

;; Suppress byte-compiler warnings for C-level functions
(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-text "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")

(defgroup my-ts nil
  "Major mode for MyLang using tree-sitter."
  :group 'languages)

(defcustom my-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `my-ts-mode'."
  :type 'integer
  :safe 'integerp
  :group 'my-ts)

(defvar my-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    ;; Operators as punctuation
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?* ". 23" table)    ;; also block comment middle/end
    (modify-syntax-entry ?/ ". 124b" table)  ;; also comment starter
    (modify-syntax-entry ?\n "> b" table)    ;; line-comment ender
    table)
  "Syntax table for `my-ts-mode'.")

;; ... font-lock, indent, imenu definitions ...

;;;###autoload
(define-derived-mode my-ts-mode prog-mode "MyLang"
  "Major mode for MyLang, powered by tree-sitter."
  :syntax-table my-ts-mode--syntax-table
  :group 'my-ts

  (when (treesit-ready-p 'mylang)
    (treesit-parser-create 'mylang)

    ;; Comments (for C-style // and /* */)
    (c-ts-common-comment-setup)
    ;; OR manual:
    ;; (setq-local comment-start "// ")
    ;; (setq-local comment-end "")
    ;; (setq-local comment-start-skip (rx "//" (* (syntax whitespace))))

    ;; Font-lock
    (setq-local treesit-font-lock-settings (my-ts-mode--font-lock-settings))
    (setq-local treesit-font-lock-feature-list
                '((comment definition)
                  (keyword string type)
                  (constant escape-sequence number)
                  (bracket delimiter operator function property variable)))

    ;; Indentation
    (setq-local treesit-simple-indent-rules my-ts-mode--indent-rules)

    ;; Navigation
    (setq-local treesit-defun-type-regexp
                (regexp-opt '("function_definition" "struct_definition")))
    (setq-local treesit-defun-name-function #'my-ts-mode--defun-name)

    ;; Things (sexp, list, sentence navigation)
    (setq-local treesit-thing-settings
                `((mylang
                   (sexp ,(regexp-opt '("identifier" "expression" "literal") 'symbols))
                   (sentence ,(regexp-opt '("declaration" "statement") 'symbols)))))

    ;; Imenu
    (setq-local treesit-simple-imenu-settings
                '(("Function" "\\`function_definition\\'" nil nil)
                  ("Struct"   "\\`struct_definition\\'"   nil nil)))

    ;; Electric indent
    (setq-local electric-indent-chars
                (append "{}():;," electric-indent-chars))

    ;; MUST be the final call
    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.mylang\\'" . my-ts-mode))

(provide 'my-ts-mode)
;;; my-ts-mode.el ends here
```

## `treesit-major-mode-setup` — What It Does

This is the **final call** in the mode body. It wires up everything you've set via `setq-local`:

1. **Font-lock**: Copies settings, sets `font-lock-defaults`, calls `treesit-font-lock-recompute-features`
2. **Indentation**: Optimizes rules, sets `indent-line-function` to `treesit-indent`, `indent-region-function` to `treesit-indent-region`
3. **Defun navigation**: Remaps `beginning-of-defun`/`end-of-defun` if `treesit-defun-type-regexp` is set
4. **Sexp/list/sentence**: Sets `forward-sexp-function`, `forward-list-function`, `up-list-function`, `down-list-function`, `show-paren-data-function` based on `treesit-thing-settings`
5. **Imenu**: Sets `imenu-create-index-function` to `treesit-simple-imenu`
6. **Outline**: Sets `outline-search-function` from `treesit-outline-predicate` or imenu settings

---

## Font-Lock Rules

### `treesit-font-lock-rules` DSL

```elisp
(treesit-font-lock-rules
 :language 'mylang         ;; REQUIRED: tree-sitter language symbol
 :feature 'keyword         ;; REQUIRED: feature name for level control
 :override OVERRIDE        ;; optional, default nil
 'QUERY                    ;; tree-sitter query in sexp form
 ...)
```

**Keywords** (precede each query block):

| Keyword | Values | Description |
|---------|--------|-------------|
| `:language` | symbol | Tree-sitter language for this query |
| `:feature` | symbol | Feature name for level-based enable/disable |
| `:override` | `nil`, `t`, `'append`, `'prepend`, `'keep` | How to handle face conflicts (see below) |
| `:default-language` | symbol | Sets default language for all subsequent queries |

**Override values:**
- `nil` — don't override existing face (default)
- `t` — always apply this face, replacing any existing
- `'append` — add after existing face
- `'prepend` — add before existing face
- `'keep` — apply only to regions without an existing face

**Query capture names** must be either:
- A face name: `@font-lock-keyword-face`
- A function name: `@my-ts-mode--fontify-something` (called with `(NODE OVERRIDE START END)`)

If a name is both a face and a function, the face takes priority.

### Feature Levels

```elisp
(setq-local treesit-font-lock-feature-list
  '((comment definition)              ;; Level 1 — minimum (always on)
    (keyword string type)             ;; Level 2 — basic
    (constant escape-sequence number) ;; Level 3 — default (treesit-font-lock-level = 3)
    (bracket delimiter operator       ;; Level 4 — maximum
     function property variable)))
```

`treesit-font-lock-level` (default 3) controls how many levels are active. Level N enables all features in sublists 1 through N. Users customize with `treesit-font-lock-recompute-features`.

### Common Feature Names

`definition`, `type`, `assignment`, `builtin`, `constant`, `keyword`, `comment`, `doc`, `string`, `escape-sequence`, `number`, `operator`, `property`, `bracket`, `delimiter`, `variable`, `function`, `error`, `preprocessor`/`directive`, `label`

### Font-Lock Patterns

**Basic keyword highlighting:**
```elisp
:feature 'keyword
'(["if" "else" "for" "while" "return"] @font-lock-keyword-face)
```

**Using a keyword list variable:**
```elisp
(defvar my-ts-mode--keywords '("if" "else" "for" "while" "return"))

:feature 'keyword
`([,@my-ts-mode--keywords] @font-lock-keyword-face)
```

**Field-based discrimination:**
```elisp
;; Highlight the name in function declarations
:feature 'definition
'((function_declaration name: (identifier) @font-lock-function-name-face))
```

**Value-based discrimination (sibling node type matching):**
```elisp
;; Highlight name as type when value is a struct definition
:feature 'definition
:override t
'((declaration names: (identifier) @font-lock-type-face
               value: (struct_definition)))
```

**Regex predicate (`:match`):**
```elisp
;; Only highlight identifiers matching builtin names
:feature 'builtin
`((call_expression
   function: (identifier) @font-lock-builtin-face
   (:match ,(rx-to-string `(seq bos (or ,@builtin-names) eos))
           @font-lock-builtin-face)))
```

**`:pred` predicate:**
```elisp
;; Custom predicate function
:feature 'definition
`((function_declarator) @my-fontify-fn
  (:pred my-top-level-p @my-fontify-fn))
```

**Escape sequences (always override strings):**
```elisp
:feature 'escape-sequence
:override t
'((escape_sequence) @font-lock-escape-face)
```

**Error nodes:**
```elisp
:feature 'error
:override t
'((ERROR) @font-lock-warning-face)
```

### Custom Fontification Functions

When queries alone can't express the highlighting logic, capture to a function name:

```elisp
:feature 'definition
'((declaration declarator: (_) @my-ts-mode--fontify-declarator))

(defun my-ts-mode--fontify-declarator (node override start end &rest _)
  "Fontify declarator NODE with context-dependent face."
  (let* ((name-node (treesit-node-child-by-field-name node "name"))
         (parent (treesit-node-parent node))
         (face (pcase (treesit-node-type parent)
                 ("field_declaration" 'font-lock-property-name-face)
                 ("function_declarator" 'font-lock-function-name-face)
                 (_ 'font-lock-variable-name-face))))
    (when name-node
      (treesit-fontify-with-override
       (treesit-node-start name-node)
       (treesit-node-end name-node)
       face override start end))))
```

### Priority Chain Example

For a language where declarations can be variables, constants, functions, or types depending on context, structure font-lock rules from generic to specific with appropriate overrides:

```elisp
;; Level 4: generic fallback (no override — everything else wins)
:feature 'variable
'((identifier) @font-lock-variable-use-face)

;; Level 2: type annotations override variable
:feature 'type
:override t
'((declaration type: (identifier) @font-lock-type-face))

;; Level 1: definitions override everything
:feature 'definition
:override t
'((declaration names: (identifier) @font-lock-constant-face "::"))
'((declaration names: (identifier) @font-lock-function-name-face
               value: (procedure_definition)))
'((declaration names: (identifier) @font-lock-type-face
               value: (struct_definition)))
```

### Standard Emacs Faces (29+)

| Face | Use for |
|------|---------|
| `font-lock-keyword-face` | Language keywords |
| `font-lock-comment-face` | Comments |
| `font-lock-doc-face` | Doc comments/strings |
| `font-lock-string-face` | String literals |
| `font-lock-number-face` | Numeric literals |
| `font-lock-constant-face` | Constants, enum values, booleans, null |
| `font-lock-type-face` | Type names and type definitions |
| `font-lock-function-name-face` | Function/method definitions |
| `font-lock-function-call-face` | Function/method calls |
| `font-lock-variable-name-face` | Variable definitions, parameters |
| `font-lock-variable-use-face` | Variable references |
| `font-lock-property-name-face` | Property/field definitions |
| `font-lock-property-use-face` | Property/field access |
| `font-lock-builtin-face` | Built-in functions/macros |
| `font-lock-preprocessor-face` | Preprocessor directives, annotations |
| `font-lock-operator-face` | Operators |
| `font-lock-bracket-face` | Brackets: `()`, `[]`, `{}` |
| `font-lock-delimiter-face` | Delimiters: `,`, `;`, `:` |
| `font-lock-escape-face` | Escape sequences in strings |
| `font-lock-warning-face` | Error nodes, warnings |

---

## Indentation Rules

### `treesit-simple-indent-rules` Format

```elisp
(setq-local treesit-simple-indent-rules
  `((LANGUAGE
     (MATCHER ANCHOR OFFSET)
     (MATCHER ANCHOR OFFSET)
     ...)))
```

Rules are tried **in order**; first match wins. Each rule is `(MATCHER ANCHOR OFFSET)`:
- **MATCHER**: Returns non-nil if this rule applies. Receives `(NODE PARENT BOL)`.
- **ANCHOR**: Returns a buffer position. Receives `(NODE PARENT BOL)`.
- **OFFSET**: Integer literal or variable symbol whose value is an integer.

**BOL** = position of first non-whitespace on current line.
**NODE** = largest node starting at BOL (may be nil for empty lines).
**PARENT** = parent of NODE.

A rule can also be a **single function** `(NODE PARENT BOL) -> (cons ANCHOR-POS OFFSET)` or nil. This is the "function-as-rule" pattern for complex cases.

### Preset Matchers

| Matcher | Description |
|---------|-------------|
| `(node-is TYPE)` | NODE's type matches TYPE (regexp) |
| `(parent-is TYPE)` | PARENT's type matches TYPE (regexp) |
| `(field-is NAME)` | NODE's field name in PARENT matches NAME (regexp) |
| `(n-p-gp NODE PARENT GP)` | Checks node, parent, and grandparent types (all regexps, nil = skip) |
| `(match NODE-TYPE PARENT-TYPE FIELD INDEX-MIN INDEX-MAX)` | Multi-condition (all optional, nil = skip) |
| `(query PATTERN)` | Queries PARENT with tree-sitter PATTERN, checks if NODE is captured |
| `(prev-line-is TYPE)` | Previous line's largest node matches TYPE |
| `no-node` | NODE is nil (empty line / outside any node) |
| `comment-end` | Text after point matches `comment-end-skip` |
| `catch-all` | Always matches |

### Preset Anchors

| Anchor | Description |
|--------|-------------|
| `parent-bol` | Beginning of indentation on PARENT's line (most common anchor) |
| `parent` | Start of PARENT node |
| `grand-parent` | Start of PARENT's parent |
| `great-grand-parent` | Start of PARENT's parent's parent |
| `first-sibling` | Start of PARENT's first child |
| `(nth-sibling N &optional NAMED)` | Start of PARENT's Nth child |
| `prev-sibling` | Start of NODE's previous named sibling |
| `standalone-parent` | First ancestor that starts on its own line |
| `column-0` | Beginning of current line (column 0) |
| `no-indent` | Current BOL position (don't change indentation) |
| `prev-line` | First non-whitespace on previous line |
| `comment-start` | Position after comment-start-skip match |
| `prev-adaptive-prefix` | End of adaptive-fill-regexp match on previous line (block comments) |

### Combinators

| Combinator | Description |
|------------|-------------|
| `(and FN...)` | Returns result of last FN if all return non-nil |
| `(or FN...)` | Returns first non-nil result |
| `(not FN)` | Negates the result |

### Common Indent Rule Patterns

**Top-level at column 0:**
```elisp
((parent-is "source_file") column-0 0)
```

**Closing delimiters align with parent:**
```elisp
((node-is ")") parent-bol 0)
((node-is "]") parent-bol 0)
((node-is "}") parent-bol 0)
```

**Block contents indented:**
```elisp
((parent-is "block") parent-bol my-ts-mode-indent-offset)
((parent-is "struct_definition") parent-bol my-ts-mode-indent-offset)
((parent-is "enum_definition") parent-bol my-ts-mode-indent-offset)
```

**Function parameters/arguments:**
```elisp
((parent-is "parameter_list") parent-bol my-ts-mode-indent-offset)
((parent-is "argument_list") parent-bol my-ts-mode-indent-offset)
```

**Block comment alignment (use with `c-ts-common`):**
```elisp
((and (parent-is "comment") c-ts-common-looking-at-star)
 c-ts-common-comment-start-after-first-star -1)
((parent-is "comment") prev-adaptive-prefix 0)
```

**Raw strings / here-strings (don't indent contents):**
```elisp
((parent-is "here_string") no-indent 0)
```

**Handling ERROR nodes (critical for editing experience):**
```elisp
((parent-is "ERROR") prev-line 0)
```

**Empty line fallback:**
```elisp
(no-node parent-bol 0)
```

**General catch-all:**
```elisp
(catch-all parent-bol 0)
```

### Using `c-ts-common-baseline-indent-rule`

For C-like languages, use the baseline as a universal fallback after your language-specific rules:

```elisp
(require 'c-ts-common)

(setq-local c-ts-common-indent-offset 'my-ts-mode-indent-offset)

(setq-local treesit-simple-indent-rules
  `((mylang
     ;; Language-specific rules first
     ((parent-is "source_file") column-0 0)
     ;; ... more rules ...

     ;; Baseline fallback handles:
     ;; - Closing brace alignment
     ;; - Sibling alignment
     ;; - List/paren alignment
     ;; - Default parent+offset
     ,@c-ts-common-baseline-indent-rule)))
```

### Function-as-Rule Pattern

For complex indentation that can't be expressed as `(MATCHER ANCHOR OFFSET)`:

```elisp
(defun my-ts-mode--for-loop-indent (node parent bol)
  "Custom indent rule for for-loop parts."
  (when (string-match-p "for_statement" (treesit-node-type parent))
    (let ((field (treesit-node-field-name node)))
      (pcase field
        ("body" (cons (treesit-node-start parent) my-ts-mode-indent-offset))
        ("condition" (cons (treesit-node-start parent) (* 2 my-ts-mode-indent-offset)))
        (_ nil)))))  ;; nil means "this rule doesn't apply, try next"
```

Insert into rules list as a bare symbol:
```elisp
`((mylang
   my-ts-mode--for-loop-indent   ;; function-as-rule
   ((parent-is "block") parent-bol my-ts-mode-indent-offset)
   ...))
```

### Override Rules

`treesit-simple-indent-override-rules` has the same format but is checked BEFORE `treesit-simple-indent-rules`. This lets users inject rules without modifying the mode's rules:

```elisp
;; In user config:
(setq-local treesit-simple-indent-override-rules
  '((mylang
     ((parent-is "switch_body") parent-bol 0))))  ;; different switch style
```

---

## Imenu

### `treesit-simple-imenu-settings`

```elisp
(setq-local treesit-simple-imenu-settings
  '(("Function" "\\`function_definition\\'" nil nil)
    ("Method"   "\\`method_declaration\\'"   nil nil)
    ("Struct"   "\\`type_declaration\\'"     my-struct-p nil)
    (nil        "\\`variable\\'"             nil nil)))  ;; ungrouped
```

Format: list of `(CATEGORY NODE-TYPE-REGEXP PREDICATE NAME-FN)`
- **CATEGORY**: String for grouping (e.g., `"Function"`) or nil for flat entries
- **NODE-TYPE-REGEXP**: Regexp matching tree-sitter node types
- **PREDICATE**: nil or `(node) -> bool` for additional filtering
- **NAME-FN**: nil (defaults to `treesit-defun-name`) or `(node) -> string`

**With predicate** (when multiple constructs share a node type):
```elisp
(defun my-ts-mode--struct-p (node)
  "Check if NODE is a struct declaration."
  (treesit-node-child-by-field-name
   (treesit-search-subtree node "struct_type") "name"))

(setq-local treesit-simple-imenu-settings
  '(("Struct" "\\`type_declaration\\'" my-ts-mode--struct-p nil)))
```

---

## Navigation

### Defun Navigation

```elisp
;; Simple regexp
(setq-local treesit-defun-type-regexp
            (regexp-opt '("function_definition" "struct_definition")))

;; With predicate (dotted pair)
(setq-local treesit-defun-type-regexp
            (cons (regexp-opt '("call" "declaration"))
                  #'my-ts-mode--defun-p))
```

### Defun Name

```elisp
(setq-local treesit-defun-name-function #'my-ts-mode--defun-name)

(defun my-ts-mode--defun-name (node)
  "Return the name of NODE."
  (pcase (treesit-node-type node)
    ("function_definition"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("struct_definition"
     ;; Walk up to the declaration to find the name
     (let ((parent (treesit-node-parent node)))
       (when (equal (treesit-node-type parent) "declaration")
         (treesit-node-text
          (treesit-node-child-by-field-name parent "names") t))))
    (_ nil)))
```

### Thing Settings (Emacs 30+)

Controls `forward-sexp`, `forward-list`, `forward-sentence`, and related movement commands:

```elisp
(setq-local treesit-thing-settings
  `((mylang
     (sexp (not (or (and named ,(rx bos (or "source_file" "comment") eos))
                    (and anonymous ,(rx (or "{" "}" "[" "]" "(" ")" ","))))))
     (list ,(regexp-opt '("block" "parameter_list" "argument_list"
                          "struct_definition" "enum_definition") 'symbols))
     (sentence ,(regexp-opt '("declaration" "expression_statement"
                              "if_statement" "for_statement" "while_statement"
                              "return_statement") 'symbols))
     (text ,(regexp-opt '("comment" "string_literal" "here_string") 'symbols)))))
```

**PRED** can be:
- A regexp matching node type
- A function `(node) -> bool`
- A cons `(REGEXP . FN)` — both must match
- Combinators: `(or PRED...)`, `(and PRED...)`, `(not PRED)`
- Atoms: `named` (named nodes), `anonymous` (anonymous nodes)

### Outline Integration

```elisp
;; Simple: reuse defun regexp
(setq-local treesit-outline-predicate
  (rx bos (or "function_definition" "struct_definition" "enum_definition") eos))

;; Or use a function
(setq-local treesit-outline-predicate #'my-ts-mode--defun-p)
```

If not set, `treesit-major-mode-setup` derives it from `treesit-simple-imenu-settings`.

---

## Comment Setup

### Using `c-ts-common` (recommended for C-style comments)

```elisp
(require 'c-ts-common)
(c-ts-common-comment-setup)
```

This single call sets up: `comment-start`, `comment-end`, `comment-start-skip`, `comment-end-skip`, `adaptive-fill-mode`, `adaptive-fill-function`, `paragraph-start`, `paragraph-separate`, `fill-paragraph-function`, `comment-line-break-function`, `comment-multi-line`.

### Manual (if not C-style)

```elisp
(setq-local comment-start "// ")
(setq-local comment-end "")
(setq-local comment-start-skip (rx "//" (* (syntax whitespace))))
```

### Comment Indentation Rules (for `/* * */` alignment)

Add to indent rules for block comment continuation alignment:

```elisp
;; From c-ts-common:
((and (parent-is "comment") c-ts-common-looking-at-star)
 c-ts-common-comment-start-after-first-star -1)
((parent-is "comment") prev-adaptive-prefix 0)
```

---

## Syntax Table

Even with tree-sitter handling font-lock, a syntax table is still needed for:
- Electric pair mode
- `forward-sexp` fallback
- `comment-dwim` and other comment commands
- `show-paren-mode`

### Standard C-like Syntax Table

```elisp
(defvar my-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    ;; Operators as punctuation
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?% "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?^ "." table)
    (modify-syntax-entry ?! "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?~ "." table)
    ;; String delimiter
    (modify-syntax-entry ?\" "\"" table)
    ;; Escape character
    (modify-syntax-entry ?\\ "\\" table)
    ;; Comment syntax: // and /* */
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23" table)
    (modify-syntax-entry ?\n "> b" table)
    table)
  "Syntax table for `my-ts-mode'.")
```

### Comment Syntax Entry Codes

The `". 124b"` and `". 23"` codes encode C comment syntax:
- `/` is punctuation (`.`) + starts `//` (1st char of 2-char comment-start, flag `1`) + starts `/*` (1st char, flag `1`) + ends `*/` (2nd char of 2-char comment-end, flag `4`) + b-style (flag `b` for `//`)
- `*` is punctuation (`.`) + 2nd char of `/*` start (flag `2`) + 1st char of `*/` end (flag `3`)
- `\n` ends b-style comments (`> b`)

### `syntax-propertize-function`

For characters with context-dependent syntax (e.g., `'` used both as char delimiter and lifetime marker, or `#` used both as directive prefix and operator), use tree-sitter node types to resolve ambiguity at runtime:

```elisp
(defun my-ts-mode--syntax-propertize (start end)
  "Apply syntax properties from START to END."
  (let ((parser (treesit-parser-list)))
    (dolist (node (treesit-query-capture
                   (car parser)
                   '((char_literal "'" @char-start) ...)
                   start end))
      (pcase (car node)
        ('char-start
         (put-text-property (cdr node) (1+ (cdr node))
                            'syntax-table (string-to-syntax "\"")))))))
```

---

## Grammar Installation

### Grammar Source Registration

```elisp
(defcustom my-ts-mode-grammar-source
  "https://github.com/example/tree-sitter-mylang.git"
  "URL for the tree-sitter-mylang grammar."
  :type 'string
  :group 'my-ts)
```

### Auto-Install Pattern (from templ-ts-mode)

```elisp
(defcustom my-ts-mode-grammar-install 'prompt
  "How to handle missing grammar."
  :type '(choice (const :tag "Auto-install" auto)
                 (const :tag "Prompt" prompt)
                 (const :tag "Don't install" nil))
  :group 'my-ts)

(defun my-ts-mode--ensure-grammar ()
  "Install the grammar if missing."
  (setq-local treesit-language-source-alist
              `((mylang . (,my-ts-mode-grammar-source))))
  (when (and (not (treesit-language-available-p 'mylang))
             (pcase my-ts-mode-grammar-install
               ('auto t)
               ('prompt (y-or-n-p "Install tree-sitter-mylang grammar?"))
               (_ nil)))
    (treesit-install-language-grammar 'mylang)))
```

### Interactive Install Helper (from elixir-ts-mode)

```elisp
(defun my-ts-mode-install-grammar ()
  "Install the tree-sitter grammar for MyLang."
  (interactive)
  (let ((treesit-language-source-alist
         (append `((mylang . (,my-ts-mode-grammar-source)))
                 treesit-language-source-alist)))
    (treesit-install-language-grammar 'mylang)))
```

---

## Multi-Language Embedding

For languages that embed other languages (e.g., HTML+JS, Elixir+HEEx):

### Range Rules

```elisp
(setq-local treesit-range-settings
  (treesit-range-rules
   :embed 'javascript
   :host 'html
   :offset '(1 . -1)   ;; trim delimiters from range
   '((script_element (raw_text) @javascript))))
```

Keywords: `:embed` (embedded lang), `:host` (host lang), `:offset` (cons `(START . END)`), `:local` (t for dedicated local parser)

### Language-at-Point

```elisp
(setq-local treesit-language-at-point-function
            #'my-ts-mode--language-at-point)

(defun my-ts-mode--language-at-point (point)
  "Return the language at POINT."
  (let ((node (treesit-node-at point 'host-lang)))
    (if (equal (treesit-node-type node) "embedded_content")
        'embedded-lang
      'host-lang)))
```

### Parser Creation Order

Create embedded parsers FIRST, then the host parser:

```elisp
(when (treesit-ready-p 'embedded)
  (treesit-parser-create 'embedded))
(treesit-parser-create 'host)  ;; host parser last
```

### Merging Font-Lock Features

```elisp
(setq-local treesit-font-lock-feature-list
  (treesit-merge-font-lock-feature-list
   my-host-features
   my-embedded-features))
```

---

## Useful Node Traversal Functions

| Function | Signature | Returns |
|----------|-----------|---------|
| `treesit-node-at` | `(pos &optional parser-or-lang named)` | Leaf node at position |
| `treesit-node-on` | `(beg end &optional parser-or-lang named)` | Smallest node covering range |
| `treesit-node-type` | `(node)` | Node type string |
| `treesit-node-text` | `(node &optional no-property)` | Buffer text of node |
| `treesit-node-start` | `(node)` | Start position |
| `treesit-node-end` | `(node)` | End position |
| `treesit-node-parent` | `(node)` | Parent node |
| `treesit-node-child` | `(node n &optional named)` | Nth child |
| `treesit-node-children` | `(node &optional named)` | All children as list |
| `treesit-node-child-by-field-name` | `(node field)` | Child with given field name |
| `treesit-node-field-name` | `(node)` | Field name of node in parent |
| `treesit-node-next-sibling` | `(node &optional named)` | Next sibling |
| `treesit-node-prev-sibling` | `(node &optional named)` | Previous sibling |
| `treesit-node-index` | `(node &optional named)` | Index among siblings |
| `treesit-parent-until` | `(node pred &optional include)` | Walk up until pred matches |
| `treesit-parent-while` | `(node pred)` | Walk up while pred matches |
| `treesit-node-top-level` | `(node &optional pred include)` | Highest ancestor matching |
| `treesit-search-subtree` | `(node pred &optional backward all depth)` | Search within subtree |
| `treesit-search-forward` | `(node pred &optional backward all)` | Search forward in tree |
| `treesit-filter-child` | `(node pred &optional named)` | Filter children by predicate |
| `treesit-query-capture` | `(node query &optional beg end node-only)` | Run query, get captures |
| `treesit-fontify-with-override` | `(start end face override ...)` | Apply face with override |
| `treesit-defun-at-point` | `()` | Defun node at point |

---

## Testing

### ERT Indentation Tests (`.erts` format)

The `.erts` (Emacs Resource Test Suite) format is the standard way to test indentation:

```
Code:
  (lambda ()
    (my-ts-mode)
    (indent-region (point-min) (point-max)))

Name: Basic block indentation

=-=
if cond {
stmt1;
stmt2;
}
=-=
if cond {
    stmt1;
    stmt2;
}
=-=-=

Name: Nested blocks

=-=
fn foo() {
if cond {
bar();
}
}
=-=
fn foo() {
    if cond {
        bar();
    }
}
=-=-=
```

The `=-=` markers delimit before/after states. `=-=-=` separates test cases.

### ERT Font-Lock Tests

```elisp
(ert-deftest my-ts-mode-font-lock-keywords ()
  (with-temp-buffer
    (my-ts-mode)
    (insert "if x { return y; }")
    (font-lock-ensure)
    (goto-char (point-min))
    (should (eq (get-text-property (point) 'face) 'font-lock-keyword-face))
    (search-forward "return")
    (should (eq (get-text-property (match-beginning 0) 'face)
                'font-lock-keyword-face))))
```

### Byte-Compile Check

```bash
emacs -Q --batch -f batch-byte-compile my-ts-mode.el
```

### Interactive Testing

```bash
emacs -Q -L . --eval "(require 'my-ts-mode)" path/to/test-file
```

### Mangle-and-Reindent Pattern (from ada-ts-mode)

Tests that code reindents to the original after mangling:

```elisp
(ert-deftest my-ts-mode-indent-roundtrip ()
  (with-temp-buffer
    (insert-file-contents "test/sample.mylang")
    (my-ts-mode)
    (let ((original (buffer-string)))
      ;; Strip all indentation
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]+" nil t)
        (replace-match ""))
      ;; Re-indent
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) original)))))
```

---

## Best Practices

### Performance
- Pre-compile queries as `defconst` where possible — runtime compilation is expensive
- Use `:default-language` to avoid repeating the language for every query block
- Put the `variable` catch-all at level 4 (not always active)

### Correctness
- Always call `treesit-major-mode-setup` as the very last thing in the mode body
- Guard with `(when (treesit-ready-p 'mylang) ...)` before any tree-sitter calls
- Handle `ERROR` nodes in indent rules — code is frequently in an error state while editing
- Include `(no-node parent-bol 0)` or `(catch-all parent-bol 0)` as indent fallback

### Convention
- Derive from `prog-mode` for programming languages
- Use `(derived-mode-add-parents 'my-ts-mode '(my-mode))` if replacing an existing non-ts mode
- Prefix feature names with `mylang-` if embedding other languages (avoids collision)
- Name custom faces `my-ts-mode-CONCEPT-face` (following Emacs convention)
- Use `regexp-opt` with `'symbols` for `treesit-defun-type-regexp` and thing settings

### Code Organization
- Keyword lists as `defvar` variables, composed into queries via splatting
- Font-lock rules as a function returning `(treesit-font-lock-rules ...)` (allows parameterization)
- Indent rules as a `defvar` (or function if style variants are needed)
- If indentation is complex (>100 rules), consider a separate `-indentation.el` file

### User Experience
- Provide grammar auto-install or at minimum an interactive install command
- Support `electric-indent-chars` for `{}():;,` at minimum
- Set `treesit-outline-predicate` for outline-minor-mode integration
- Set `treesit-defun-name-function` for which-function-mode and add-log

---

## Quick Reference: What to Set in `define-derived-mode`

| Variable | Purpose | Required? |
|----------|---------|-----------|
| `treesit-font-lock-settings` | Font-lock rules | Yes |
| `treesit-font-lock-feature-list` | Feature levels | Yes |
| `treesit-simple-indent-rules` | Indentation rules | Yes |
| `treesit-defun-type-regexp` | Defun navigation | Recommended |
| `treesit-defun-name-function` | Defun name extraction | Recommended |
| `treesit-simple-imenu-settings` | Imenu entries | Recommended |
| `treesit-thing-settings` | Sexp/list/sentence nav | Recommended (Emacs 30+) |
| `treesit-outline-predicate` | Outline headings | Optional (auto-derived from imenu) |
| `electric-indent-chars` | Auto-indent triggers | Recommended |
| `comment-start` / `comment-end` | Comment commands | Yes (or use c-ts-common) |
| `treesit-language-at-point-function` | Multi-language | Only if embedding |
| `treesit-range-settings` | Multi-language ranges | Only if embedding |
