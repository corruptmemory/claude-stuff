// Example 04: Actor Hierarchy — Coordinator with Sub-Actors
//
// A coordinator (Application) manages sub-actors representing distinct
// operational modes. Demonstrates:
//   - Stoppable interface and StateBuilder function type
//   - Coordinator that owns one sub-actor at a time
//   - Fire-and-forget SetState (avoids the deadlock trap)
//   - RecoverableError for graceful fallback chains
//   - ErrorApp as terminal state
//   - Sub-actor triggering its own replacement
//   - Type-switching on sub-actor to decide behavior
//
// Run: go run ./04_actor_hierarchy
package main

import (
	"errors"
	"fmt"
	"sync"
	"time"

	"actor-examples/chanutil"
)

// ============================================================================
// Core Abstractions
// ============================================================================

// Stoppable is the common interface for all managed sub-actors.
type Stoppable interface {
	Stop()
	Wait()
}

// StateBuilder defers actor construction until the coordinator calls it.
type StateBuilder func(a *Application) (Stoppable, error)

// RecoverableError wraps an error with a fallback builder.
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

// buildState tries the builder, then one level of recovery, then ErrorApp.
func buildState(a *Application, builder StateBuilder) (Stoppable, error) {
	state, err := builder(a)
	if err == nil {
		return state, nil
	}
	if next, ok := IsRecoverable(err); ok {
		state, err = next(a)
		if err == nil {
			return state, nil
		}
	}
	return NewErrorApp(err), nil
}

// ============================================================================
// ErrorApp — Terminal State
// ============================================================================

type ErrorApp struct {
	err error
}

func NewErrorApp(err error) *ErrorApp { return &ErrorApp{err: err} }
func (e *ErrorApp) GetError() error   { return e.err }
func (e *ErrorApp) Stop()             {}
func (e *ErrorApp) Wait()             {}

// ============================================================================
// Coordinator (Application)
// ============================================================================

type appCommandTag int

const (
	appGetState appCommandTag = iota
	appSetState
)

type appCommand struct {
	tag     appCommandTag
	builder StateBuilder
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

func (a *Application) run(initial StateBuilder) {
	defer a.wg.Done()

	current, _ := buildState(a, initial)

	for msg := range a.commands {
		switch msg.tag {
		case appGetState:
			msg.result <- current
			close(msg.result)

		case appSetState:
			// No result channel — fire-and-forget. This is critical.
			if current != nil {
				current.Stop()
				current.Wait()
			}
			current, _ = buildState(a, msg.builder)
		}
	}

	if current != nil {
		current.Stop()
		current.Wait()
	}
}

// GetState is synchronous — request/response.
func (a *Application) GetState() (Stoppable, error) {
	return chanutil.SendReceive[appCommand, Stoppable](a.commands, appCommand{
		tag: appGetState,
	})
}

// SetState is fire-and-forget — no result channel, no blocking.
// This prevents the deadlock where a sub-actor synchronously waits for
// SetState while the coordinator waits for the sub-actor to Stop.
func (a *Application) SetState(builder StateBuilder) {
	defer func() { recover() }()
	a.commands <- appCommand{tag: appSetState, builder: builder}
}

func (a *Application) Stop() {
	defer func() { recover() }()
	close(a.commands)
}

func (a *Application) Wait() {
	a.wg.Wait()
}

// ============================================================================
// Sub-Actor: SetupMode
// ============================================================================
// Simulates a setup wizard that collects configuration, then transitions
// the coordinator to RunningMode.

type setupCommandTag int

const (
	setupGetStep setupCommandTag = iota
	setupAdvance
)

type setupCommand struct {
	tag    setupCommandTag
	result chan any
}

func (c setupCommand) WithResult(ch chan any) setupCommand {
	c.result = ch
	return c
}

type SetupMode struct {
	app      *Application
	commands chan setupCommand
	wg       sync.WaitGroup
}

func NewSetupMode(a *Application) (Stoppable, error) {
	s := &SetupMode{
		app:      a,
		commands: make(chan setupCommand, 64),
	}
	s.wg.Add(1)
	go s.run()
	return s, nil
}

func (s *SetupMode) run() {
	step := 1
	totalSteps := 3

	defer s.wg.Done()

	for msg := range s.commands {
		switch msg.tag {
		case setupGetStep:
			msg.result <- step
		case setupAdvance:
			if step < totalSteps {
				step++
				msg.result <- error(nil)
			} else {
				msg.result <- error(nil)
				// Trigger transition — fire-and-forget.
				// Don't break or return; let the range loop drain naturally.
				s.app.SetState(func(a *Application) (Stoppable, error) {
					return NewRunningMode(a, fmt.Sprintf("config-from-step-%d", totalSteps))
				})
			}
		}
		close(msg.result)
	}
}

func (s *SetupMode) GetStep() (int, error) {
	return chanutil.SendReceive[setupCommand, int](s.commands, setupCommand{
		tag: setupGetStep,
	})
}

func (s *SetupMode) Advance() error {
	return chanutil.SendReceiveError[setupCommand](s.commands, setupCommand{
		tag: setupAdvance,
	})
}

func (s *SetupMode) Stop() {
	defer func() { recover() }()
	close(s.commands)
}

func (s *SetupMode) Wait() {
	s.wg.Wait()
}

// ============================================================================
// Sub-Actor: RunningMode
// ============================================================================

type runningCommandTag int

const (
	runGetStatus runningCommandTag = iota
)

type runningCommand struct {
	tag    runningCommandTag
	result chan any
}

func (c runningCommand) WithResult(ch chan any) runningCommand {
	c.result = ch
	return c
}

type RunningMode struct {
	app      *Application
	commands chan runningCommand
	wg       sync.WaitGroup
	config   string // immutable after construction
}

func NewRunningMode(a *Application, config string) (Stoppable, error) {
	r := &RunningMode{
		app:      a,
		commands: make(chan runningCommand, 64),
		config:   config,
	}
	r.wg.Add(1)
	go r.run()
	return r, nil
}

func (r *RunningMode) run() {
	upSince := time.Now()

	defer r.wg.Done()

	for msg := range r.commands {
		switch msg.tag {
		case runGetStatus:
			msg.result <- fmt.Sprintf("running (config=%s, uptime=%s)",
				r.config, time.Since(upSince).Truncate(time.Millisecond))
		}
		close(msg.result)
	}
}

func (r *RunningMode) GetStatus() (string, error) {
	return chanutil.SendReceive[runningCommand, string](r.commands, runningCommand{
		tag: runGetStatus,
	})
}

// Config is immutable — safe for concurrent reads without going through the channel.
func (r *RunningMode) Config() string { return r.config }

func (r *RunningMode) Stop() {
	defer func() { recover() }()
	close(r.commands)
}

func (r *RunningMode) Wait() {
	r.wg.Wait()
}

// ============================================================================
// Demo
// ============================================================================

func main() {
	// Start in SetupMode.
	app, err := NewApplication(NewSetupMode)
	if err != nil {
		fmt.Printf("init error: %v\n", err)
		return
	}
	defer func() { app.Stop(); app.Wait() }()

	// Walk through the setup wizard.
	for i := 0; i < 4; i++ {
		state, _ := app.GetState()
		switch s := state.(type) {
		case *SetupMode:
			step, _ := s.GetStep()
			fmt.Printf("[Setup] On step %d\n", step)
			if err := s.Advance(); err != nil {
				fmt.Printf("[Setup] Advance error: %v\n", err)
			}
			// After advancing past the last step, give the coordinator
			// a moment to process the fire-and-forget SetState.
			time.Sleep(50 * time.Millisecond)

		case *RunningMode:
			status, _ := s.GetStatus()
			fmt.Printf("[Running] %s\n", status)
			fmt.Printf("[Running] Config (direct getter): %s\n", s.Config())

		case *ErrorApp:
			fmt.Printf("[Error] %v\n", s.GetError())
		}
	}

	// Demonstrate RecoverableError: force a transition to a builder that fails
	// with recovery.
	fmt.Println("\n--- Triggering recoverable error ---")
	app.SetState(func(a *Application) (Stoppable, error) {
		return nil, &RecoverableError{
			Err: fmt.Errorf("primary database unavailable"),
			NextBuilder: func(a *Application) (Stoppable, error) {
				fmt.Println("[Recovery] Falling back to read-only mode")
				return NewRunningMode(a, "read-only-fallback")
			},
		}
	})
	time.Sleep(50 * time.Millisecond)

	state, _ := app.GetState()
	if r, ok := state.(*RunningMode); ok {
		status, _ := r.GetStatus()
		fmt.Printf("[After Recovery] %s\n", status)
	}

	// Demonstrate unrecoverable error → ErrorApp.
	fmt.Println("\n--- Triggering unrecoverable error ---")
	app.SetState(func(a *Application) (Stoppable, error) {
		return nil, &RecoverableError{
			Err: fmt.Errorf("everything is on fire"),
			NextBuilder: func(a *Application) (Stoppable, error) {
				return nil, fmt.Errorf("recovery also failed")
			},
		}
	})
	time.Sleep(50 * time.Millisecond)

	state, _ = app.GetState()
	if e, ok := state.(*ErrorApp); ok {
		fmt.Printf("[ErrorApp] Parked with: %v\n", e.GetError())
	}
}
