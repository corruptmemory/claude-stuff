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

`Stop()` closes the command channel. `Wait()` blocks until `run()` exits.

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

```go
type myService struct {
	commands chan myCommand
	wg       sync.WaitGroup
	// dependencies passed at construction
	store    *SomeStore
}
```

## 6. Constructor

Create the struct, load initial state, start the goroutine.

```go
func NewMyService(deps ...) (MyService, error) {
	s := &myService{
		commands: make(chan myCommand, 64),
		store:    store,
	}
	s.wg.Add(1)
	go s.run()
	return s, nil
}
```

Buffer size 64 is a reasonable default — prevents callers from blocking when the goroutine is processing.

## 7. The `run()` Goroutine

This is the heart. It owns all mutable state as local variables.

```go
func (s *myService) run() {
	defer s.wg.Done()
	defer s.store.Close()  // cleanup resources

	// --- All mutable state lives here ---
	var items []Item
	var latest *Item

	// Load initial state from persistence
	items, _ = s.store.LoadToday()
	if len(items) > 0 {
		last := items[len(items)-1]
		latest = &last
	}

	for msg := range s.commands {
		switch msg.tag {
		case cmdDoSomething:
			// Mutate state, persist, return error or nil
			if err := s.store.Write(msg.input); err != nil {
				msg.result <- err
			} else {
				items = append(items, msg.input)
				latest = &msg.input
				msg.result <- error(nil)
			}

		case cmdGetState:
			// Return data (copy if needed)
			msg.result <- latest

		case cmdQuery:
			// Compute and return
			result := doQuery(items, msg.params)
			msg.result <- result
		}
		close(msg.result)
	}
}
```

Critical details:
- `for msg := range s.commands` — exits when channel is closed (Stop)
- `close(msg.result)` after every case — unblocks the SendReceive caller
- For error-returning commands, send `error(nil)` explicitly for success (typed nil)
- Return copies of slices if callers shouldn't see mutations

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

```go
func (s *myService) Stop() {
	close(s.commands)
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
