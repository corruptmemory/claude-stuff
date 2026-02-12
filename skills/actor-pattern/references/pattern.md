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
