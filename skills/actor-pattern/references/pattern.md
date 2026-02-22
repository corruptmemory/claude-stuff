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
