// Example 01: Basic Actor — Counter
//
// The simplest possible actor: a counter that multiple goroutines can
// safely increment and read without locks. Demonstrates:
//   - Command tags (enum of operations)
//   - Command struct with result channel and WithResult method
//   - The run() goroutine owning all mutable state
//   - Public methods using SendReceive / SendReceiveError
//   - Stop() / Wait() lifecycle
//
// Run: go run ./01_basic_actor
package main

import (
	"fmt"
	"sync"

	"actor-examples/chanutil"
)

// --- Public interface ---

type Counter interface {
	Increment() error
	Get() (int, error)
	Stop()
	Wait()
}

// --- Command tags ---

type commandTag int

const (
	cmdIncrement commandTag = iota
	cmdGet
)

// --- Command struct ---

type counterCommand struct {
	tag    commandTag
	result chan any
}

// Value receiver — copies the struct so the caller's original is unmodified.
func (c counterCommand) WithResult(ch chan any) counterCommand {
	c.result = ch
	return c
}

// --- Unexported implementation ---

type counter struct {
	commands chan counterCommand
	done     chan struct{}
	wg       sync.WaitGroup
}

func NewCounter() Counter {
	c := &counter{
		commands: make(chan counterCommand, 64),
		done:     make(chan struct{}),
	}
	c.wg.Add(1)
	go c.run()
	return c
}

// run owns all mutable state as local variables.
func (c *counter) run() {
	// --- All mutable state lives here ---
	count := 0

	defer c.wg.Done()

	// --- Handler closures ---

	handleIncrement := func(msg counterCommand) {
		count++
		msg.result <- error(nil) // typed nil for error-returning commands
	}

	handleGet := func(msg counterCommand) {
		msg.result <- count
	}

	// --- Dispatch loop ---

	for {
		var msg counterCommand
		select {
		case <-c.done:
			return
		case msg = <-c.commands:
		}

		switch msg.tag {
		case cmdIncrement:
			handleIncrement(msg)
		case cmdGet:
			handleGet(msg)
		}
		close(msg.result)
	}
}

// --- Public methods ---

func (c *counter) Increment() error {
	return chanutil.SendReceiveError[counterCommand](c.commands, counterCommand{
		tag: cmdIncrement,
	})
}

func (c *counter) Get() (int, error) {
	return chanutil.SendReceive[counterCommand, int](c.commands, counterCommand{
		tag: cmdGet,
	})
}

func (c *counter) Stop() {
	defer func() { recover() }()
	close(c.done)
}

func (c *counter) Wait() {
	c.wg.Wait()
}

// --- Demo ---

func main() {
	ctr := NewCounter()
	defer func() { ctr.Stop(); ctr.Wait() }()

	// Spawn 10 goroutines that each increment 100 times.
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 100; j++ {
				if err := ctr.Increment(); err != nil {
					fmt.Printf("increment error: %v\n", err)
					return
				}
			}
		}()
	}
	wg.Wait()

	val, err := ctr.Get()
	if err != nil {
		fmt.Printf("get error: %v\n", err)
		return
	}
	fmt.Printf("Final count: %d (expected 1000)\n", val)
}
