---
name: actor-pattern
description: "Apply the Go goroutine actor pattern for thread-safe state management. A single goroutine owns all mutable state, communicating via typed command channels with generic SendReceive/SendReceiveError helpers. Eliminates mutexes and atomic pointers. Use when: (1) multiple HTTP handlers need shared mutable state, (2) replacing mutex-locked structs or atomic.Pointer patterns, (3) building a service layer that owns in-memory state plus persistence, (4) the user mentions 'actor pattern', 'collector pattern', 'goroutine event loop', or 'channel-based state management'."
---

# Go Goroutine Actor Pattern

Replace locks and atomic pointers with a single goroutine that owns all mutable state, accessed via channel-based request/response.

## When to Apply

- Multiple goroutines (HTTP handlers, background jobs) need to read/write shared state
- Current code uses `sync.Mutex` or `atomic.Pointer` to protect state
- You need a service that combines in-memory caching with persistent storage

## Pattern Overview

See [references/pattern.md](references/pattern.md) for the complete implementation reference with code templates.

## Implementation Steps

1. Create `internal/chanutil/chanutil.go` with generic channel helpers
2. Define the public **interface** (what callers see)
3. Define **command tags** (enum of operations)
4. Define the **command struct** with a `result chan any` and `WithResult` method
5. Implement the **unexported struct** with `commands chan`, `sync.WaitGroup`
6. Write the **`run()` goroutine** — single `for msg := range commands` loop owning all state
7. Write **public methods** that use `SendReceive` / `SendReceiveError` to talk to the goroutine
8. Wire **`Stop()` / `Wait()`** for clean shutdown
9. Update callers (HTTP handlers, main.go) to use the new interface
