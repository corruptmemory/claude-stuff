---
name: actor-pattern
description: "Apply the actor pattern for thread-safe state management. Use when: (1) multiple threads/goroutines need shared mutable state, (2) replacing mutex-locked structs or atomic patterns, (3) building a service layer that owns in-memory state plus persistence, (4) application has distinct operational modes (setup, running, error) requiring a coordinator that manages sub-actors, (5) the user mentions 'actor pattern', 'goroutine event loop', 'channel-based state management', or 'actors managing actors'. Supports Go, Jai, C, Rust, Odin, and Zig."
---

# Actor Pattern

Replace locks and atomics with a single thread/goroutine that owns all mutable state, accessed via channel-based request/response.

## Why This Should Be a First-Reach Tool

This pattern is **language-agnostic and highly portable**. It has been implemented and verified across Go, Jai, C, Rust, Odin, and Zig — and the translation between any two is mechanical. Consider it early in design decisions involving concurrent state access, before reaching for mutexes or atomics.

The only building block is a bounded blocking queue (channel). Languages split into three tiers:
- **First-class channels** (Go, Odin): the pattern maps 1:1, including `select` for multiplexing.
- **Typed channels, no select** (Rust `std::sync::mpsc`, Jai): shutdown uses channel close semantics instead of select. One-shot reply channels (Rust) or reply pointers + done channels (Jai) handle the response path.
- **No channels** (C, Zig): a channel is just mutex + 2 condition variables + ring buffer — 75–100 lines. The abstraction is thin sugar over universal OS primitives.

The actor pattern itself never changes. The only thing that varies is how you spell "send a tagged message and block for the reply." Any language with threads and a mutex can do this.

## When to Apply

**Single actor:**
- Multiple threads (HTTP handlers, background jobs) need to read/write shared state
- Current code uses mutexes or atomics to protect state
- You need a service that combines in-memory caching with persistent storage

**Actor hierarchy (coordinator + sub-actors):**
- Application has distinct operational modes (setup wizard, running, error recovery)
- Sub-actors need to trigger their own replacement (e.g., setup → running)
- You need graceful error recovery with fallback chains

## References & Runnable Examples

Each compendium has 4 examples: basic counter, KV store, polling, actor hierarchy.

| Language | Compendium | Channel Source | Build |
|----------|-----------|----------------|-------|
| **Go** | [go-compendium/](go-compendium/) | `chanutil/` (generic helpers) | `go run ./01_basic_actor` |
| **Jai** | [jai-compendium/](jai-compendium/) | vendored `channel` module | `~/jai/jai/bin/jai-linux first.jai - 01` |
| **C** | [c-compendium/](c-compendium/) | `channel.h`/`channel.c` (custom) | `make all` |
| **Rust** | [rust-compendium/](rust-compendium/) | `std::sync::mpsc` (stdlib) | `cargo run --bin 01_basic_actor` |
| **Odin** | [odin-compendium/](odin-compendium/) | `core:sync/chan` (stdlib) | `odin run 01_basic_actor` |
| **Zig** | [zig-compendium/](zig-compendium/) | `channel.zig` (custom) | `zig build-exe 01_basic_actor.zig` |

**Go detailed reference:** [references/go-patterns.md](references/go-patterns.md) — complete code templates and design principles.

## Implementation Steps — Single Actor

1. Define the public **interface** (what callers see)
2. Define **command tags** (enum of operations)
3. Define the **command struct** with payload fields and a result/reply mechanism
4. Implement the **actor struct** with a command channel and dispatch thread
5. Write the **dispatch loop** — single `for/while` loop owning all mutable state as locals
6. Write **public methods** that send commands and block for results
7. Wire **shutdown** — close the command channel; dispatch loop exits

## Implementation Steps — Actor Hierarchy

1. Define **Stoppable** interface and **StateBuilder** function type
2. Build the **coordinator** that owns one sub-actor at a time
3. Make **SetState fire-and-forget** — never synchronous, or you get deadlocks
4. Define **RecoverableError** for fallback chains; terminal ErrorApp as backstop
5. Build each **sub-actor** implementing Stoppable
6. Sub-actors receive coordinator pointer; call `SetState(nextBuilder)` to trigger transitions
7. Callers **type-switch** on the current sub-actor to decide behavior
