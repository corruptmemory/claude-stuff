# Goroutine Actor Pattern — Complete Reference

## Architecture

```
Caller (HTTP handler, etc.)
  → public method on interface
    → SendReceive/SendReceiveError sends command via channel
      → run() goroutine receives command
        → processes using owned state (no locks needed)
        → sends result back via result channel
    → caller receives result
```

Key invariant: **all mutable state lives inside `run()`**. No external goroutine ever touches it directly.

## 1. Channel Helpers (`internal/chanutil/chanutil.go`)

```go
package chanutil

import "io"

type WithResult[T any] interface {
	WithResult(c chan any) T
}

// SendReceive sends a command and waits for a typed result.
// Returns io.EOF if the commands channel is closed.
func SendReceive[C WithResult[C], K any](commands chan C, msg C) (result K, err error) {
	defer func() {
		if recover() != nil {
			err = io.EOF
		}
	}()
	re := make(chan any, 1)
	commands <- msg.WithResult(re)
	value := <-re
	switch v := value.(type) {
	case error:
		err = v
	case K:
		result = v
	}
	return
}

// SendReceiveError sends a command and waits for an error-only result.
func SendReceiveError[C WithResult[C]](commands chan C, msg C) (err error) {
	defer func() {
		if recover() != nil {
			err = io.EOF
		}
	}()
	re := make(chan any, 1)
	commands <- msg.WithResult(re)
	value := <-re
	if value == nil {
		return nil
	}
	if e, ok := value.(error); ok {
		return e
	}
	return nil
}
```

The `recover()` catches panics from sending on a closed channel (which happens when the goroutine has been stopped). Returning `io.EOF` signals "service shut down."

## 2. Public Interface

Define what callers can do. Keep it clean — no channels, no implementation details.

```go
type MyService interface {
	DoSomething(input InputType) error
	GetState() (*StateType, error)
	Query(params QueryParams) ([]ResultType, error)
	Stop()
	Wait()
}
```

`Stop()` closes a `done` channel. `Wait()` blocks until `run()` exits.

## 3. Command Tags

Integer enum of operations:

```go
type commandTag int

const (
	cmdDoSomething commandTag = iota
	cmdGetState
	cmdQuery
)
```

## 4. Command Struct

Single struct carries all possible payloads. Implement `WithResult` for the channel helpers.

```go
type myCommand struct {
	tag    commandTag
	input  InputType
	params QueryParams
	result chan any
}

func (c myCommand) WithResult(ch chan any) myCommand {
	c.result = ch
	return c
}
```

Use value receiver on `WithResult` — it copies the struct so the caller's original is unmodified.

## 5. Unexported Implementation Struct

Keep the struct minimal — only fields that must be shared between public methods and `run()`. Lifecycle machinery (pollers, background goroutines, their shutdown channels) belongs inside `run()` as locals, not on the struct.

```go
type myService struct {
	commands chan myCommand
	done     chan struct{}   // closed by Stop to signal shutdown
	wg       sync.WaitGroup
	opts     *serviceOptions
	// dependencies passed at construction
	store    *SomeStore
}
```

## 6. Constructor

The constructor's job is **resource acquisition with early error surfacing**. Validate options, open resources (fail loudly if they can't be opened), build the struct, hand off to `run()`. Don't wire up runtime behavior here — that belongs in `run()`.

```go
func NewMyService(store *SomeStore, opts ...Option) (MyService, error) {
	options := defaultOptions()
	for _, o := range opts {
		if err := o(options); err != nil {
			return nil, err
		}
	}
	s := &myService{
		commands: make(chan myCommand, options.commandBuffer),
		done:     make(chan struct{}),
		store:    store,
		opts:     options,
	}
	s.wg.Add(1)
	go s.run()
	return s, nil
}
```

The command buffer size should be configurable via an option with a sensible default (e.g. 64).

## 7. The `run()` Goroutine

This is the heart. It owns all mutable state as local variables. Setup and cleanup are co-located via `defer` — any `return` triggers correct shutdown. No `goto`, no labels.

Extract command handlers into named closures for a tight dispatch loop:

```go
func (s *myService) run() {
	// --- All mutable state lives here ---
	var items []Item
	var latest *Item

	// Load initial state from persistence
	items, _ = s.store.LoadToday()
	if len(items) > 0 {
		last := items[len(items)-1]
		latest = &last
	}

	// Cleanup runs on any return path.
	defer func() {
		s.store.Close()
		s.wg.Done()
	}()

	// --- handler closures (each sends exactly one value on msg.result) ---

	handleDoSomething := func(msg myCommand) {
		if err := s.store.Write(msg.input); err != nil {
			msg.result <- err
		} else {
			items = append(items, msg.input)
			latest = &msg.input
			msg.result <- error(nil)
		}
	}

	handleGetState := func(msg myCommand) {
		msg.result <- latest
	}

	handleQuery := func(msg myCommand) {
		msg.result <- doQuery(items, msg.params)
	}

	// --- dispatch loop ---

	for {
		var msg myCommand
		select {
		case <-s.done:
			return // defer handles cleanup
		case msg = <-s.commands:
		}

		switch msg.tag {
		case cmdDoSomething:
			handleDoSomething(msg)
		case cmdGetState:
			handleGetState(msg)
		case cmdQuery:
			handleQuery(msg)
		}
		close(msg.result)
	}
}
```

Critical details:
- Select on `s.done` for shutdown — `return` triggers `defer` cleanup
- Handler closures close over actor-local state — no parameters needed
- `close(msg.result)` after the switch — uniform invariant, one per command
- For error-returning commands, send `error(nil)` explicitly for success (typed nil)
- Return copies of slices if callers shouldn't see mutations
- **No `goto` shutdown labels** — `defer` works with any exit path, including ones added by future contributors who reflexively type `return`

## 8. Public Methods

Each method creates a command and uses the channel helpers:

```go
func (s *myService) DoSomething(input InputType) error {
	return chanutil.SendReceiveError[myCommand](s.commands, myCommand{
		tag:   cmdDoSomething,
		input: input,
	})
}

func (s *myService) GetState() (*StateType, error) {
	return chanutil.SendReceive[myCommand, *StateType](s.commands, myCommand{
		tag: cmdGetState,
	})
}

func (s *myService) Query(params QueryParams) ([]ResultType, error) {
	return chanutil.SendReceive[myCommand, []ResultType](s.commands, myCommand{
		tag:    cmdQuery,
		params: params,
	})
}
```

## 9. Stop and Wait

`Stop()` closes the `done` channel. Use `recover()` so double-close is safe — libraries must never panic.

```go
func (s *myService) Stop() {
	defer func() { recover() }()
	close(s.done)
}

func (s *myService) Wait() {
	s.wg.Wait()
}
```

Callers should `defer func() { svc.Stop(); svc.Wait() }()` after construction.

## HTTP Handler Integration

Handlers accept the interface, not the implementation:

```go
func MyHandler(svc MyService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		data, err := svc.GetState()
		if err != nil {
			log.Printf("error: %v", err)
		}
		// render response
	}
}
```

## Testing

Test through the public interface. The goroutine starts automatically in the constructor.

```go
func TestMyService(t *testing.T) {
	svc, err := NewMyService(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { svc.Stop(); svc.Wait() }()

	if err := svc.DoSomething(input); err != nil {
		t.Fatal(err)
	}
	state, err := svc.GetState()
	// assert...
}
```

## Polling with Timer (Not Ticker)

When an actor needs a background poller (e.g., checking a remote for changes), use `time.NewTimer` with reset-after-work, **not** `time.NewTicker`. A ticker fires on a fixed cadence regardless of how long the work takes — if a poll cycle is slow (network call, actor round-trip), ticks queue up and fire back-to-back. This is the cron-stampede problem.

A timer reset after work guarantees at least `interval` of idle between cycles. The timer approach is **adaptive** — it naturally backs off when work is slow and polls at the configured rate when things are fast, rather than making a brittle assumption that work always completes within the interval.

The poller should be a plain function, not a struct — it has no meaningful state beyond lifecycle coordination, and `run()` already owns that via a WaitGroup and done channel:

```go
// startPoller launches inside run(). The actor controls its lifecycle
// via done channel and waits for exit via wg.
func startPoller(wg *sync.WaitGroup, resolve func() (string, error), commands chan<- myCommand, done <-chan struct{}, interval time.Duration) {
	wg.Add(1)
	go func() {
		defer wg.Done()

		timer := time.NewTimer(0) // fire immediately for seed
		defer timer.Stop()

		lastKnown := ""
		if v, err := resolve(); err == nil {
			lastKnown = v
		}

		for {
			select {
			case <-done:
				return
			case <-timer.C:
			}

			v, err := resolve()
			if err == nil && v != lastKnown {
				lastKnown = v
				re := make(chan any, 1)
				select {
				case commands <- myCommand{tag: cmdNewValue, result: re}:
					<-re
				case <-done:
					return
				}
			}

			timer.Reset(interval) // interval measured from END of work
		}
	}()
}
```

Usage inside `run()`:

```go
var pollerWg sync.WaitGroup
pollerDone := make(chan struct{})
startPoller(&pollerWg, resolveHEAD, s.commands, pollerDone, s.opts.pollInterval)

defer func() {
	close(pollerDone)
	pollerWg.Wait()
	// ... other cleanup ...
	s.wg.Done()
}()
```

Key details:
- The poller sends commands directly on the actor's channel — no intermediate "bridge" goroutine needed
- It gets its own `done` channel so `run()` controls its lifecycle explicitly
- `timer.Reset(interval)` after all work ensures slow polls don't cause stampeding
- You don't get metronomic heartbeats, but you don't get heart attacks either
- If a struct's only fields are shutdown coordination, the caller already has that coordination — the struct is overhead

## When State Needs Date Rollover

If state is partitioned by date (e.g., daily log files), handle rollover in the write path:

```go
case cmdRecord:
	date := msg.obs.Timestamp.Format("2006-01-02")
	if date != todayStr {
		todayStr = date
		todayItems = []Item{}  // reset in-memory buffer
	}
	// persist and append to todayItems
```

## When Querying Historical Data

Combine in-memory (today) with on-disk (past days):

```go
func (s *myService) loadRange(start, end time.Time, todayStr string, todayItems []Item) []Item {
	var all []Item
	for d := start.Truncate(24*time.Hour); !d.After(end); d = d.Add(24*time.Hour) {
		dateStr := d.Format("2006-01-02")
		if dateStr == todayStr {
			dayItems = todayItems  // use in-memory
		} else {
			dayItems, _ = s.store.ReadDay(dateStr)  // read from disk
		}
		// filter by start/end, append to all
	}
	return all
}
```

---

## Actor Hierarchy — Actors Managing Actors

When your application has distinct operational modes — setup wizard, running, error recovery — a single actor isn't enough. You need a **coordinator actor** that owns and transitions between **sub-actors**.

### Core Abstractions

```go
// Stoppable is the common interface for all managed sub-actors.
type Stoppable interface {
	Stop()
	Wait()
}

// StateBuilder defers actor construction until the coordinator calls it.
// It receives the coordinator so sub-actors can trigger transitions.
type StateBuilder func(a *Application) (Stoppable, error)
```

`StateBuilder` is a function, not a struct — the coordinator calls it to create the next sub-actor. Sub-actors receive a pointer to the coordinator so they can call `SetState` to trigger their own replacement.

### Coordinator Actor

The coordinator (Application) owns exactly one sub-actor at a time:

```go
type appCommandTag int

const (
	appGetState appCommandTag = iota
	appSetState
)

type appCommand struct {
	tag     appCommandTag
	builder StateBuilder  // only for appSetState
	result  chan any
}

func (c appCommand) WithResult(ch chan any) appCommand {
	c.result = ch
	return c
}

type Application struct {
	commands chan appCommand
	wg       sync.WaitGroup
}

func NewApplication(initial StateBuilder) (*Application, error) {
	a := &Application{commands: make(chan appCommand, 64)}
	a.wg.Add(1)
	go a.run(initial)
	return a, nil
}
```

The `run()` loop builds the initial sub-actor, then processes commands:

```go
func (a *Application) run(initial StateBuilder) {
	defer a.wg.Done()

	current, _ := buildState(a, initial)

	for msg := range a.commands {
		switch msg.tag {
		case appGetState:
			msg.result <- current
			close(msg.result)

		case appSetState:
			if current != nil {
				current.Stop()
				current.Wait()
			}
			current, _ = buildState(a, msg.builder)
		}
	}

	// Shutdown: stop the final sub-actor.
	if current != nil {
		current.Stop()
		current.Wait()
	}
}
```

`GetState` is synchronous (request/response). `appSetState` has **no result channel** — this is critical (see deadlock section below).

### The Deadlock Trap — Fire-and-Forget SetState

**This is the most important lesson in hierarchical actors.**

When a sub-actor triggers its own replacement, a synchronous `SetState` creates a circular wait:

```
Sub-actor.run()  →  calls app.SetState(nextBuilder)       ← BLOCKS waiting for response
  → Coordinator.run()  receives appSetState
    → calls current.Stop()                                  ← closes sub-actor's command channel
    → calls current.Wait()                                  ← BLOCKS waiting for sub-actor.run() to exit
      → sub-actor.run() is blocked on SetState response     ← DEADLOCK
```

**Solution: Make SetState fire-and-forget.** Send the command, don't wait for a response.

```go
func (a *Application) SetState(builder StateBuilder) {
	defer func() { recover() }()  // safe if coordinator already shut down
	a.commands <- appCommand{tag: appSetState, builder: builder}
}
```

Key properties:
- No result channel — the sub-actor sends and moves on
- `recover()` catches panics from sending on a closed channel (coordinator already stopped)
- The sub-actor's `run()` loop naturally exits via `for msg := range` when `Stop()` closes its channel
- The coordinator processes the transition after the current `range` iteration completes

### RecoverableError — Graceful Fallback Chains

When a state transition fails, you often want to fall back rather than crash:

```go
type RecoverableError struct {
	Err         error
	NextBuilder StateBuilder
}

func (e *RecoverableError) Error() string { return e.Err.Error() }
func (e *RecoverableError) Unwrap() error { return e.Err }

func IsRecoverable(err error) (StateBuilder, bool) {
	var re *RecoverableError
	if errors.As(err, &re) {
		return re.NextBuilder, true
	}
	return nil, false
}
```

The coordinator uses this in `buildState`:

```go
func buildState(a *Application, builder StateBuilder) (Stoppable, error) {
	state, err := builder(a)
	if err == nil {
		return state, nil
	}
	// Try one level of recovery.
	if next, ok := IsRecoverable(err); ok {
		state, err = next(a)
		if err == nil {
			return state, nil
		}
	}
	// Terminal failure — park in error state.
	return NewErrorApp(err), nil
}
```

**Recovery is single-level only.** If the recovery builder also fails, go to `ErrorApp`. This prevents livelock. Note: `buildState` ignores any `RecoverableError` returned by the recovery builder itself — don't bother wrapping recovery failures in `RecoverableError`, it won't be followed.

### ErrorApp — Terminal State

A minimal actor that holds an error and does nothing else:

```go
type ErrorApp struct {
	err error
}

func NewErrorApp(err error) *ErrorApp { return &ErrorApp{err: err} }
func (e *ErrorApp) GetError() error   { return e.err }
func (e *ErrorApp) Stop()             {}
func (e *ErrorApp) Wait()             {}
```

**Gotcha:** If you make ErrorApp a full channel-based actor and use `SendReceive` for `GetError()`, remember that `SendReceive` interprets `error` values as failures, not results. You need a custom helper that returns the error as the *payload*, not the error return. Watch the return value ordering — `appErr, _ :=` not `_, err :=`.

HTTP handlers type-switch on the sub-actor to decide what to render:

```go
state, _ := app.GetState()
switch s := state.(type) {
case *SetupApp:
	renderSetupWizard(s)
case *RunningApp:
	renderDashboard(s)
case *ErrorApp:
	renderErrorPage(s.GetError())
}
```

### Sub-Actor Example: Setup Wizard

A sub-actor that owns wizard state and eventually transitions the coordinator to a different sub-actor:

```go
type SetupApp struct {
	app      *Application  // coordinator — for calling SetState
	commands chan setupCommand
	wg       sync.WaitGroup
}

func NewSetupApp(a *Application, cfg Settings, ...) *SetupApp {
	sa := &SetupApp{
		app:      a,
		commands: make(chan setupCommand, 64),
	}
	sa.wg.Add(1)
	go sa.run(cfg)
	return sa
}
```

When the wizard completes, it triggers its own replacement:

```go
// Inside SetupApp.run(), after successful confirmation:
sa.app.SetState(makeRunningBuilder(finalSettings))
// Don't break or return — let the range loop drain naturally.
// The coordinator will Stop() this actor, closing sa.commands,
// which causes `for msg := range sa.commands` to exit.
```

### Multi-Client Serialization and Stale Submissions

When an actor backs an HTTP-driven state machine (wizard, approval chain, multi-step form), the `for cmd := range` loop serializes all mutations. Multiple browsers hitting the same wizard see one authoritative state — this is a feature, not a bug.

**The stale browser problem:** Browser A and B both see Step 3. A submits, advancing to Step 4. B submits against what it thinks is Step 3, but the actor is now on Step 4. B's submission may produce a confusing (but non-destructive) result.

**Defense escalation ladder:**

| Level | Technique | Guards Against |
|-------|-----------|---------------|
| **0** | Trust the form | Nothing — stale submissions silently operate on wrong state |
| **1** | Hidden `step` field; server rejects if it doesn't match current state | Stale browsers; returns "refresh" instead of wrong result |
| **2** | `HMAC(step + nonce, secret)` in hidden field; server verifies | Level 1 + forged step values from crafted requests |
| **3** | Signed token with one-time nonce; server tracks consumed nonces | Level 2 + replay attacks |

Level 1 covers 99% of real-world confusion for near-zero cost. Levels 2–3 for scenarios where the state machine controls something security-sensitive.

### Two Representations, One Truth

When the actor tracks a value internally (e.g., `selectedKind` local variable) and the config derives the same value differently (e.g., `Kind()` checks which sub-struct has data), they **will diverge** in intermediate states — the user selected a type but hasn't filled in details yet.

**Fix:** Include the actor's authoritative value in the state snapshot sent to templates. Never derive state from partially-populated config when the actor already knows the answer.

### Immutable Resources Skip the Command Channel

Not everything on an actor struct needs serialization. Immutable or stateless resources — configured once at construction, never modified — can be exposed via simple getters without going through the command channel.

```go
type RunningApp struct {
	commands chan runCommand
	wg       sync.WaitGroup
	workflow GitWorkflow  // immutable after construction, nil if unavailable
}

// Workflow returns the GitWorkflow. Safe for concurrent reads — no command needed.
func (ra *RunningApp) Workflow() GitWorkflow { return ra.workflow }
```

Rule of thumb: if the field is set in the constructor and never modified by `run()`, it's safe to read directly. If `run()` ever writes to it, it must go through the command channel.

### Move Post-Actor I/O to the Caller

When the actor's contribution to an operation is complete, remaining blocking I/O (network calls, external APIs) should run in the caller's goroutine, not the actor's.

```go
// Handler — NOT inside the cart actor:
info, err := cart.Commit()  // actor does its work (git commit + push)
if err != nil { ... }

// MR creation is a network call. The actor's job is done — run it here.
mrResult, mrErr := workflow.OpenMergeRequest(info.BranchName, ...)
```

This keeps the actor's `run()` loop responsive. Other callers can still send commands while the handler waits for the network response. Applies whenever:
- The actor produces a result that a subsequent I/O call needs (e.g., branch name → MR creation)
- The I/O call doesn't need to mutate actor state
- Blocking the actor would freeze unrelated operations (dashboard, SSE, other sessions)

### Two Deadly Sins of Actor Systems

| Sin | Symptom | Prevention |
|-----|---------|------------|
| **Deadlock** | Actor A synchronously waits for Actor B, while B waits for A to finish | Fire-and-forget for transitions; never synchronously call your own coordinator |
| **Livelock** | Actors endlessly trigger transitions without making progress | Single-level recovery; terminal ErrorApp as backstop; never retry the same builder |

## Design Principles

These principles apply broadly to Go library design but are especially important for actor-based systems:

**Scope lifecycle to the owner.** If `run()` creates a resource, `run()` should clean it up. Don't put poller fields, bridge goroutines, or shutdown channels on the struct if they only exist for `run()`'s benefit. Local variables and `defer` handle this naturally.

**Fail early, fail loudly.** Configuration errors (bad SSH key, duplicate auth, invalid buffer size) must surface at construction time via returned errors. Libraries must never call `panic` or leak panics — only the application writer may decide to panic.

**`Option` returns `error`.** Functional options should be `func(*options) error`, not `func(*options)`. This lets options validate and reject conflicts (e.g., duplicate auth methods) at the call site. The constructor loop stops at the first error.

**`defer` over `goto`.** Use `defer` for cleanup, not `goto shutdown` labels. `defer` works with any exit path — including the `return` that a future contributor will reflexively type. Aligning with Go idioms means the path of least resistance is also the safe path.

**Handles should not know the protocol.** Types returned to callers (handles, contexts) should call unexported methods on the actor struct, not use `chanutil.SendReceive` directly. This keeps protocol details (command tags, channel types) confined to the actor implementation.

**Timer over Ticker for pollers.** `time.NewTicker` makes a brittle assumption: work always completes within the interval. `time.NewTimer` with reset-after-work is adaptive — it naturally backs off when work is slow. Resilience over rigidity.

**Don't abstract inside unexported code.** A `notify chan string` between two private types is an abstraction boundary that costs a goroutine and complex shutdown sequencing, with no external benefit. Private types can speak the same protocol directly.

**Three command patterns.** Not every command needs a result channel:
- *Request-response*: caller creates result channel, sends command, waits for typed result. Use `SendReceive`/`SendReceiveError`.
- *Done-signal*: result channel exists for synchronization but no value is sent on success — `close(msg.result)` at the end of the dispatch loop signals completion. Errors are still sent explicitly.
- *Fire-and-forget*: no result channel at all. The caller sends and moves on. Guard with `recover()` for sends on a closed channel. To synchronize with a fire-and-forget in tests, do a round-trip request-response (e.g., `Status()`) — sequential processing guarantees the fire-and-forget has been handled.

**Recovery via reclone.** When an actor manages a local cache of a remote resource (e.g., a bare git repo), the cache can become irrecoverably corrupt. Don't try to repair — nuke and reclone. Clone to a temp sibling path, swap directories atomically, reopen handles. Since closures in `run()` capture variables (not values), reassigning the resource variable makes all closures pick up the new instance automatically. Distinguish "cache corrupt" from "remote unreachable" by probing the remote before triggering recovery.

**Cached vs. side-effecting queries.** Some commands just return state the actor already holds (cheap, no I/O). Others trigger work — API calls, reconciliation, recomputation — before returning fresh state. Expose both via separate public methods. The cached path serves frequent/automatic callers (SSE-triggered refreshes, initial page loads), while the side-effecting path serves explicit user actions (a "Refresh" button). Same return type, different command tags. Example: `GetMRData()` returns stashed MR lists instantly; `RefreshMRs()` calls the upstream API, updates internal state, then returns.

**Blocking in the actor loop is a trade-off, not a bug.** When a command handler makes a network call (API fetch, ancestry check), it blocks the entire actor for the duration. This is acceptable when: (1) the trigger is infrequent (HEAD changes, explicit user refresh), (2) no other commands need low latency during that window, and (3) the alternative — spawning a goroutine for the work — would require complex synchronization to update actor-owned state safely. But if the blocking work is frequent or user-initiated with unpredictable latency (like git commit+push), isolate it in a dedicated actor (e.g., CartActor) so the main actor stays responsive.

## Actor-to-Actor Communication via Subscriptions

When one actor needs to react to another actor's events, use the subscription pattern: `ActorA.Subscribe()` returns a `Subscription[T]` with an `Events() <-chan T` method. ActorB reads from that channel in its own `select` loop.

```go
// ActorB's run loop watches both its own commands AND ActorA's events:
func (b *ActorB) run() {
    syncEvents := b.syncSubscription.Events() // from ActorA
    for {
        select {
        case evt, ok := <-syncEvents:
            if !ok { syncEvents = nil; continue }
            // React to ActorA's events
            if evt.Type == SETDone { b.handleSyncDone() }
        case cmd, ok := <-b.cmds:
            if !ok { return }
            cmd.execute(b.db)
        }
    }
}
```

**Fan-in pattern.** A third actor (EventActor) subscribes to multiple actors and merges their event streams into a unified output. SSE clients subscribe to the fan-in actor, seeing a single ordered stream. The fan-in actor's `run()` loop is just a `select` on all input channels plus its own command channel (for subscribe/unsubscribe requests).

**No callbacks.** Callbacks cross concurrency boundaries invisibly — the caller has no idea what goroutine context the callback runs in. Channels make the boundary explicit and enforced.

## The Decompression Pattern

When an actor needs to do long-running work that itself requires sending commands back through its own channel (e.g., a reindex that calls `actor.IncrementalScan()` → sends command → waits for response), running the work synchronously in the `run()` loop deadlocks: the loop is blocked in the work function, unable to process the very commands the work function is waiting on.

**Solution:** Launch the work in a goroutine. The goroutine sends commands to the actor's channel and blocks on each response. Meanwhile, the `run()` loop keeps processing all commands — both the work function's commands and any other commands (HTTP handler queries, etc.). The long-running operation's commands interleave with regular traffic.

```go
func (a *IndexActor) doReindex() {
    a.broadcaster.Broadcast(IndexEvent{IETReindexProgress, "Rebuilding..."})
    go func() {
        // This calls a.IncrementalScan() which sends commands to a.cmds
        // and blocks for each response. The run() loop processes them
        // interleaved with any other commands.
        count, err := a.reindexFn(a.maildirRoot, a)
        // Send completion event back through the command channel
        a.cmds <- &indexEventCmd{IndexEvent{IETReindexDone, fmt.Sprintf("Indexed %d", count)}}
    }()
}
```

The goroutine is a "pressure source" — it pushes commands into the channel and yields control between each one. The actor processes them at its own pace alongside everything else. Users querying mail during a reindex see no latency because their commands slip into the gaps between scan operations.

**Key invariant:** the goroutine never touches the actor's owned state directly. It only communicates via the command channel. The actor remains the sole owner of mutable state.

## Value Safety: Returning Immutable Copies

The actor guarantees *access serialization* (only one goroutine touches state at a time) but not *value safety*. If a command handler returns a pointer to internal state, the caller can mutate it from another goroutine — the channel delivered the pointer safely, but shared mutable state leaked right back.

**Rule:** Every result sent back through a response channel must be an immutable copy. In Go, this means returning structs (value types), freshly-allocated slices, and freshly-populated maps — never pointers to internal state, never internal slices.

**Corollary for inputs:** Once you send a mutable value (slice, map) into an actor via a command, don't modify it from the caller's goroutine. In practice, this is easy because the caller typically blocks on the response channel until the command completes.
