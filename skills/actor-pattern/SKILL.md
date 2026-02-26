---
name: actor-pattern
description: "Apply the Go goroutine actor pattern for thread-safe state management. Use when: (1) multiple HTTP handlers need shared mutable state, (2) replacing mutex-locked structs or atomic.Pointer patterns, (3) building a service layer that owns in-memory state plus persistence, (4) application has distinct operational modes (setup, running, error) requiring a coordinator that manages sub-actors, (5) the user mentions 'actor pattern', 'goroutine event loop', 'channel-based state management', or 'actors managing actors'."
---

# Go Goroutine Actor Pattern

Replace locks and atomic pointers with a single goroutine that owns all mutable state, accessed via channel-based request/response.

## When to Apply

**Single actor:**
- Multiple goroutines (HTTP handlers, background jobs) need to read/write shared state
- Current code uses `sync.Mutex` or `atomic.Pointer` to protect state
- You need a service that combines in-memory caching with persistent storage

**Actor hierarchy (coordinator + sub-actors):**
- Application has distinct operational modes (setup wizard, running, error recovery)
- Sub-actors need to trigger their own replacement (e.g., setup → running)
- You need graceful error recovery with fallback chains

## Pattern Overview

See [references/pattern.md](references/pattern.md) for the complete implementation reference with code templates. Covers both single actors and actor hierarchies.

## Implementation Steps — Single Actor

1. Create `internal/chanutil/chanutil.go` with generic channel helpers
2. Define the public **interface** (what callers see)
3. Define **command tags** (enum of operations)
4. Define the **command struct** with a `result chan any` and `WithResult` method
5. Implement the **unexported struct** with `commands chan`, `sync.WaitGroup`
6. Write the **`run()` goroutine** — single `for msg := range commands` loop owning all state
7. Write **public methods** that use `SendReceive` / `SendReceiveError` to talk to the goroutine
8. Wire **`Stop()` / `Wait()`** for clean shutdown
9. Update callers (HTTP handlers, main.go) to use the new interface

## Implementation Steps — Actor Hierarchy

1. Define **`Stoppable`** interface (`Stop()` + `Wait()`) and **`StateBuilder`** function type
2. Build the **coordinator actor** (Application) that owns one sub-actor at a time
3. Make **`SetState` fire-and-forget** — never synchronous, or you get deadlocks
4. Define **`RecoverableError`** for fallback chains; **`buildState`** tries builder → recovery → ErrorApp
5. Build each **sub-actor** (SetupApp, RunningApp, ErrorApp) implementing Stoppable
6. Sub-actors receive coordinator pointer; call `app.SetState(nextBuilder)` to trigger transitions
7. HTTP handlers **type-switch** on the current sub-actor to decide what to render
