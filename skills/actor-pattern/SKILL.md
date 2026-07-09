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
7. Wire **shutdown** — signal via a dedicated `quit`/`done` channel (not by closing `cmds`, which races with producers), and keep `stop` (the idempotent trigger) and `wait` (blocks until exit, admits N callers) as **separate** operations. See "Lifecycle" below.

## Implementation Steps — Actor Hierarchy

1. Define **Stoppable** interface and **StateBuilder** function type
2. Build the **coordinator** that owns one sub-actor at a time
3. Make **SetState fire-and-forget** — never synchronous, or you get deadlocks
4. Define **RecoverableError** for fallback chains; terminal ErrorApp as backstop
5. Build each **sub-actor** implementing Stoppable
6. Sub-actors receive coordinator pointer; call `SetState(nextBuilder)` to trigger transitions
7. Callers **type-switch** on the current sub-actor to decide behavior

## Command shape: tagged structs, not interface.apply()

The naive "command pattern" approach is one interface type per
command with an `apply()` method:

```go
type cacheCmd interface{ apply(*cacheState) }
type getAllCmd  struct{ result chan []Release }
func (c *getAllCmd) apply(s *cacheState) { /* ... */ }
```

This spreads the state-mutation logic across types. Prefer a tagged
struct with all logic co-located in `run()` as local closures that
capture state variables:

```go
type cmdTag int
const (cmdGetAll cmdTag = iota; cmdInvalidate; cmdStats)

type cacheCmd struct {
    tag    cmdTag
    result chan cacheResult
}

func (c *Cache) run(ctx context.Context) {
    var (warm bool; releases []Release; fetchedAt time.Time; lastErr error)

    doFetch   := func() (int, time.Duration, error) { /* ... */ }
    doGetAll  := func(cmd cacheCmd) { /* ... */ }

    for {
        select {
        case cmd := <-c.cmds:
            switch cmd.tag {
            case cmdGetAll:  doGetAll(cmd)
            }
        // ...
        }
    }
}
```

One function, top-to-bottom readable, state and behavior adjacent.

## Lifecycle: `stop` and `wait` are two operations

`stop` and `wait` play the roles a `WaitGroup` splits on purpose:

- **`stop`** — "wind down and exit as soon as logically possible." A one-way
  trigger. Nothing about it blocks on the actor actually being gone.
- **`wait`** — "block until the actor has exited." Like `WaitGroup.Wait()`,
  **one OR MORE** callers may wait, and each returns only once the actor's
  goroutine has finished.

Keep them separate by default. Welding them into a single `stop()` that also
blocks forecloses every synchronization pattern the split enables: a
supervisor stopping N sub-actors and *then* waiting on all of them; ordered
teardown (stop the producer, drain, then stop the consumer); a test asserting
the actor exited cleanly; any observer that wants to know "it's done" without
being the one who asked it to stop. Bundling is a decision to throw those away
— sometimes fine for one app, but make it a deliberate, named choice, not a
default baked into `stop`.

Two invariants make the split safe:

- **`stop` must be idempotent and safe from any goroutine.** Guard the signal
  so a second or concurrent call can't double-close/panic — `sync.Once`, or a
  recover-guarded close.
- **`wait` must serve N callers.** A closed channel broadcasts to every
  receiver, and `WaitGroup.Wait()` admits any number of waiters — both give
  fan-out for free. Signalling shutdown by *closing a dedicated `quit` channel*
  (never by closing the command channel, which races with producers and panics
  on send-after-close) is what makes an idempotent `stop` possible at all.

```go
func (a *actor) start() {
    go func() {
        defer close(a.exited)          // broadcast "exited" to every waiter
        for {
            select {
            case <-a.quit:             // the stop signal
                return
            case fn := <-a.cmds:
                fn()
            }
        }
    }()
}

func (a *actor) stop() { a.stopOnce.Do(func() { close(a.quit) }) } // idempotent trigger
func (a *actor) wait() { <-a.exited }                              // any number of callers
```

**If you want the common "stop then block" convenience, name it what it does**
— `stopAndWait()` — so the blocking wait is visible at the call site. Never
bury a blocking `wait` inside a method named `stop`; a reader wiring `stop()`
into a shutdown hook has no way to know it blocks.

```go
func (a *actor) stopAndWait() { a.stop(); a.wait() }
```

The Go compendium's `01_basic_actor` already ships this: `Stop()` signals
(recover-guarded `close`), `Wait()` blocks on a `WaitGroup`. That is the
reference — prefer it over any bundled `stop()`.

**Producer discipline (unchanged by the split):** call `stop` only after the
goroutines that send commands have quiesced. Both a closed `quit` and a closed
`cmds` leave an in-flight `do()`/send with nowhere to go — the split makes the
*lifecycle* composable, it does not remove the need for producers to stop
sending first.

## Testing the actor with deterministic time

When the actor uses periodic refresh or timers, introduce a narrow
`Ticker` interface rather than using `time.Ticker` directly:

```go
type Ticker interface {
    GetTick() <-chan time.Time
    Reset(d time.Duration)
    Stop()
}
```

Production uses a realTicker wrapping `time.Ticker`. Tests use a
`ManualTicker` whose `Reset()` method is **unbuffered** — calling it
blocks the actor until the test receives. This creates a
rendezvous-style sync barrier:

```go
type ManualTicker struct {
    ch          chan time.Time
    resetCalled chan time.Duration  // unbuffered
}

func (m *ManualTicker) Reset(d time.Duration)    { m.resetCalled <- d }
func (m *ManualTicker) AwaitReset() time.Duration { return <-m.resetCalled }
```

Tests then run deterministically without `time.Sleep`:

```go
ticker.Fire()             // push a tick
ticker.AwaitReset()       // blocks until actor has finished the refresh
assert state is updated   // provably post-tick
```

No polling, no races, no arbitrary timeouts. Example: `releases.Cache`
in `idpair-inbound`.
