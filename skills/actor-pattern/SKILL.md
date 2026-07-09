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
7. Wire **shutdown** — keep `stop` (a `recover`-guarded, idempotent trigger) and `wait` (blocks until exit; a `WaitGroup`, so N callers) as **separate** operations, and pick drain-then-exit vs exit-at-earliest deliberately. See "Lifecycle" below.

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

`stop` and `wait` play the roles a `WaitGroup` splits on purpose — and the
mechanism *is* a `WaitGroup`:

- **`stop`** — "wind down and exit as soon as logically appropriate." A one-way
  trigger; it does not block on the actor actually being gone.
- **`wait`** — "block until the actor has exited." `WaitGroup.Wait()` admits
  **one OR MORE** callers, each returning once the actor's goroutine finishes.

Keep them separate by default. Welding them into a single blocking `stop()`
forecloses the patterns the split buys: a supervisor stopping N sub-actors and
*then* waiting on all of them; ordered teardown; a test asserting clean exit;
any observer that wants to know "it's done" without being the one who stopped
it. Bundling is sometimes fine — but make it a named, deliberate choice
(`stopAndWait`), not a default baked into `stop`.

**`wait` is a `WaitGroup`.** `Add(1)` before launching, `Done` on the way out,
and `Wait()` serves N callers for free — no bespoke `done`/`exited` channel:

```go
func (a *actor) start() {
    a.wg.Add(1)
    go func() {
        defer a.wg.Done()
        // ... dispatch loop (see drain vs exit below) ...
    }()
}
func (a *actor) wait()        { a.wg.Wait() }
func (a *actor) stopAndWait() { a.stop(); a.wait() }
```

**`stop` should `recover`, not carry a `sync.Once`.** Stopping is not a drag
race — let a second or concurrent `close` panic and catch it. But do not
*swallow* the recovered value: a recovered double-stop is a correct no-op and
*also* evidence that a stray `stop()` caller is loose. Silently discarding it
is the very silent-failure trap the `recover` was meant to make safe. Check the
value, log it with an identity so you know *which* actor double-stopped, and
add `debug.Stack()` when you need to hunt the wayward caller:

```go
func (a *actor) stop() {
    defer func() {
        if r := recover(); r != nil { // re-close of a closed channel panics
            log.Printf("actor %s: recovered panic in stop (double stop?): %v", a.id, r)
            // when hunting the stray caller: log.Printf("%s", debug.Stack())
        }
    }()
    close(a.cmds) // or close(a.quit) — see drain vs exit
}
```

Idempotent, zero extra fields — and a stray stop now surfaces instead of hiding.

### Drain-then-exit vs exit-at-earliest — there is a season

How the dispatch loop *ends* is a real choice, not a detail:

- **Drain then exit** — finish every command already accepted, *then* stop.
  Close the **command** channel and `range` it:
  ```go
  for fn := range a.cmds { fn() }   // stop() closes a.cmds
  ```
  Choose this when exiting mid-flight would leave a data store, file, or
  network protocol in an invalid or costly-to-recover state and you *can*
  finish cleanly. "The process could be killed or the machine could die
  anyway" is true — but that is no reason to *emulate* a crash when a tidy
  shutdown is right there. Cost: closing `cmds` panics a producer that sends
  after `stop` (often the *desired* loud signal), so producers must quiesce
  first.

- **Exit at the earliest opportunity** — abandon anything still queued. Use a
  dedicated `quit` channel and `select`:
  ```go
  for {
      select {
      case <-a.quit:            // stop() closes a.quit
          return
      case fn := <-a.cmds:
          fn()
      }
  }
  ```
  Choose this when queued work is discardable and prompt shutdown matters.
  `cmds` is never closed, so a late producer blocks or is dropped rather than
  panicking — quieter, but it won't catch a producer that outlived shutdown.

Both variants share the same `wait` (a `WaitGroup`) and the same
recover-guarded `stop`; only the loop body and which channel `stop` closes
differ. The Go compendium's `01_basic_actor` is the exit-early form —
recover-guarded `Stop()` closing a `done` channel, `Wait()` on a `WaitGroup`.

**Name the bundled convenience `stopAndWait()`** so the blocking wait is
visible at the call site. Never bury a blocking wait inside a method named
`stop` — a reader wiring `stop()` into a shutdown hook has no way to know it
blocks.

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
