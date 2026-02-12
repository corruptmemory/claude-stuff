---
name: config-extraction
description: "Extract subsystem-specific config structs from a monolithic/global configuration using the strangler fig pattern. Each subsystem gets a focused config struct and a pure conversion function, breaking the dependency on the global config package. Use when: (1) multiple packages import a central config struct and cherry-pick fields, (2) you want to decouple a subsystem so it no longer imports the config package, (3) config has cross-referencing lookups (e.g. account name → key) that should be pre-resolved, (4) the user mentions 'extract config', 'decouple config', 'config refactor', or 'strangler fig config'."
---

# Config Extraction — Strangler Fig Pattern

Incrementally replace a monolithic global config struct with focused, subsystem-specific config structs. Each subsystem gets exactly the fields it needs, pre-resolved and ready to use.

## When to Apply

- Multiple packages import a central `config.Configuration` and cherry-pick deeply nested fields
- You want a subsystem to be testable without constructing the entire global config
- Config contains cross-referencing lookups (e.g. storage account name → key) that get repeated across subsystems
- You're preparing to split a monolith into separate services

## Pattern Overview

See [references/pattern.md](references/pattern.md) for the complete implementation reference with code templates and a worked example.

## Implementation Steps

### Per-subsystem extraction (repeat for each subsystem, one at a time):

1. **Catalog field references** — read every file in the subsystem package and list every `conf.X.Y.Z` access. This is your work list.
2. **Define the focused config struct** in the subsystem package — inline fields, don't embed original sub-structs.
3. **Write `ConfigToXxxConfig(conf config.Configuration) (XxxConfig, error)`** — a pure conversion function that maps and pre-resolves all values.
4. **Change the subsystem's stored config type** from global to focused (struct field, constructor parameter).
5. **Follow the compiler errors** — mechanically update every `conf.X.Y.Z` → `conf.Z` reference.
6. **Update call sites** (`cmd/`, `main()`) to call the conversion function and pass the result.
7. **Update test helpers** to construct global config and pass through the conversion function.
8. **Build all binaries and compile all tests** to verify.
9. **Commit** — one self-contained commit per subsystem.

### Ordering heuristic:

- Start with **leaf subsystems** (fewer dependents, simpler config surface).
- Work toward **central subsystems** (more call sites, cross-cutting concerns) last.
- This builds confidence and establishes the pattern before hitting complexity.
