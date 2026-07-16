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

## Reaching for a Mutex? Actor first

If you find yourself reaching for a Mutex, FIRST consider an actor-based
solution. Choosing a Mutex should be resisted strongly *most of the time*.

The primary exceptions center around **potential performance costs** — and
those performance benefits MUST be *significant* to offset the increased
complexity relative to an actor. In that situation, do not just pick the
mutex — **propose a spike** comparing the two options (mutex vs actor) along
at least two axes: **latency** and **throughput**. These are statistical
problems by nature, so the spike must report `min`, `mean`, `median`,
`stdev`, and the long-tail percentiles — not single numbers. (A language with
no channel construct is the other honest exception: there you build the
channel from first principles per the tier table above, then apply the
pattern anyway.)

Two observations backing the "most of the time":

- **Non-performance justifications usually dissolve into the pattern's own
  vocabulary.** The common one: "I need this call to be synchronous" (e.g. so
  tests are deterministic) — but command-with-ack / block-for-reply IS the
  actor's synchrony; a mutex buys nothing the reply channel doesn't. Field
  case (personal-site's RC debouncer, 2026-07): a pipeline stage was built
  mutex-shaped precisely for synchronous state updates, and every review of it
  required multi-goroutine interleaving proofs — one real starvation bug hid
  in those interleavings. Reshaped as an actor (state as `run()` locals, acked
  offer command), the identical tests passed unchanged off one serial history.
  If you're writing "deterministic in both interleavings" about your own
  component, it has one goroutine too many.
- **Ordering.** All mutex logic centers on *serialized access*, and that
  serialization has to happen somewhere: with kernel-backed mutexes it shows
  up as parked threads, and on unlock the wake-up order is a lottery — whoever
  happens to grab the lock next wins, which reopens the "sensible order of
  access" question. Channels are FIFO: access to the shared resource is
  strictly ordered, and the only thing the scheme can't guarantee — fairness
  among senders when the channel is full — is pushed *upstream* to the channel
  implementation, out of the actor entirely. The actor simply responds.
  K.I.S.S. in action.

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

## The `chan func()` trap — ship data, not behavior

The most common way to get this wrong is a command channel of type
`chan func()` fed closures that mutate the owned state:

```go
// WRONG: an executor, not an actor.
type actor struct { cmds chan func() }
func (a *actor) run() { for fn := range a.cmds { fn() } }
func (a *actor) do(fn func()) {                  // ships behavior, blocks for it
    done := make(chan struct{})
    a.cmds <- func() { fn(); close(done) }
    <-done
}
func (a *actor) setStatus(k, s string) {
    a.do(func() { a.tasks[k].Status = s })       // closure captures the receiver + args
}
```

This is not an actor — it is `java.util.concurrent.Executor` + `Runnable`: a
single-thread executor of zero-arg thunks. The closure is a literal GoF
Command object — its capture list is the command's fields, the captured
receiver is the command's receiver, calling it is `execute()`. And `do()` is
a `sync.Mutex` reinvented out of a goroutine, a channel, and a per-call
handshake; when every call is synchronous (as they usually are) there isn't
even an async path to justify the machinery.

**The discriminator is what moves.** A command/executor ships *behavior* to
where the state lives (the closure knows how to mutate). An actor ships
*data* to where the behavior lives — the behavior stays put in `run()`.
`chan func()` moves behavior → you built a work queue. A typed command
channel moves data → you built an actor.

**Litmus:** if the value on the channel could be `fmt.Println` — if its type
names no operation in your domain — it's an executor, not an actor. `func()`
is a signature that says *nothing*: nothing typed goes in, nothing comes out.

**Why it drifts here even when you know the rule.** Three forces pull the
same way in Go: (1) *training mass* — executor / `Runnable` / Command is
ubiquitous, while actors are thin and scattered across Erlang, Pony, and Akka
(whose good ergonomics are really Scala's sealed traits + exhaustive `match`,
not the pattern's); (2) *Go collapses the distinction* — with no sum types,
no exhaustive matching, and no `receive` primitive, "typed message handled by
an actor loop" and "command dispatched by a central invoker" become the same
`switch cmd.op`, so the more-trained-on framing wins by default; (3) a real
*terseness gradient* — an inline closure is fewer lines than a command struct
plus a `run()` case. This section is the counter-force: pay the small
verbosity tax, put a typed message on the wire, keep the behavior in `run()`.
The idiomatic-Go actor was never the weird part; carrying `Runnable`s instead
of data was.

**The one principled exception — an update-fn.** Shipping a function *is* fine
when its type names a contract: a `func(State) State` update-fn (Clojure's
`agent`, or `swap!` on an `atom`) takes the current value and returns the next.
It passes the litmus — `fmt.Println` does not have that signature — because the
type names a domain operation (state transformation), so the caller ships a
*typed transform*, not opaque behavior. Two conditions keep it honest: (1)
**value semantics** — the owner does `s = f(s)` and `f` receives the value, never
a pointer it mutates in place (the instant it takes `*State`, you are back in the
trap); (2) it earns its place only when transitions are genuinely open-ended. For
a small fixed op set, the tagged-command enum still wins — all transitions stay
visible in `run()`; the update-fn trades that closed, readable set for open
extensibility. So the full rule is not "never a function on a channel," it is:
the channel's element type must name a contract — an op enum, or a
`State → State` transform, never a bare `func()`.

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
