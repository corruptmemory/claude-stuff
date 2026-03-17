// Example 02: Request-Response Actor — Key-Value Store
//
// A more realistic actor: an in-memory key-value store with Set, Get, Delete,
// and Keys operations. Demonstrates:
//   - Multiple payload fields on the command struct
//   - Returning copies of data (not references to actor-owned state)
//   - Error handling within the actor (key not found)
//   - Constructor with functional options
//
// Run: go run ./02_request_response
package main

import (
	"fmt"
	"sync"

	"actor-examples/chanutil"
)

// --- Public interface ---

type KVStore interface {
	Set(key, value string) error
	Get(key string) (string, error)
	Delete(key string) error
	Keys() ([]string, error)
	Stop()
	Wait()
}

// --- Options ---

type options struct {
	commandBuffer int
}

type Option func(*options) error

func WithCommandBuffer(n int) Option {
	return func(o *options) error {
		if n <= 0 {
			return fmt.Errorf("command buffer must be positive, got %d", n)
		}
		o.commandBuffer = n
		return nil
	}
}

// --- Command tags ---

type commandTag int

const (
	cmdSet commandTag = iota
	cmdGet
	cmdDelete
	cmdKeys
)

// --- Command struct ---

type kvCommand struct {
	tag    commandTag
	key    string
	value  string
	result chan any
}

func (c kvCommand) WithResult(ch chan any) kvCommand {
	c.result = ch
	return c
}

// --- Unexported implementation ---

type kvStore struct {
	commands chan kvCommand
	done     chan struct{}
	wg       sync.WaitGroup
}

func NewKVStore(opts ...Option) (KVStore, error) {
	o := &options{commandBuffer: 64}
	for _, opt := range opts {
		if err := opt(o); err != nil {
			return nil, err
		}
	}

	s := &kvStore{
		commands: make(chan kvCommand, o.commandBuffer),
		done:     make(chan struct{}),
	}
	s.wg.Add(1)
	go s.run()
	return s, nil
}

func (s *kvStore) run() {
	// --- All mutable state lives here ---
	data := make(map[string]string)

	defer s.wg.Done()

	// --- Handler closures ---

	handleSet := func(msg kvCommand) {
		data[msg.key] = msg.value
		msg.result <- error(nil)
	}

	handleGet := func(msg kvCommand) {
		v, ok := data[msg.key]
		if !ok {
			msg.result <- fmt.Errorf("key not found: %q", msg.key)
		} else {
			msg.result <- v
		}
	}

	handleDelete := func(msg kvCommand) {
		delete(data, msg.key)
		msg.result <- error(nil)
	}

	handleKeys := func(msg kvCommand) {
		// Return a copy — caller must not see mutations.
		keys := make([]string, 0, len(data))
		for k := range data {
			keys = append(keys, k)
		}
		msg.result <- keys
	}

	// --- Dispatch loop ---

	for {
		var msg kvCommand
		select {
		case <-s.done:
			return
		case msg = <-s.commands:
		}

		switch msg.tag {
		case cmdSet:
			handleSet(msg)
		case cmdGet:
			handleGet(msg)
		case cmdDelete:
			handleDelete(msg)
		case cmdKeys:
			handleKeys(msg)
		}
		close(msg.result)
	}
}

// --- Public methods ---

func (s *kvStore) Set(key, value string) error {
	return chanutil.SendReceiveError[kvCommand](s.commands, kvCommand{
		tag:   cmdSet,
		key:   key,
		value: value,
	})
}

func (s *kvStore) Get(key string) (string, error) {
	return chanutil.SendReceive[kvCommand, string](s.commands, kvCommand{
		tag: cmdGet,
		key: key,
	})
}

func (s *kvStore) Delete(key string) error {
	return chanutil.SendReceiveError[kvCommand](s.commands, kvCommand{
		tag: cmdDelete,
		key: key,
	})
}

func (s *kvStore) Keys() ([]string, error) {
	return chanutil.SendReceive[kvCommand, []string](s.commands, kvCommand{
		tag: cmdKeys,
	})
}

func (s *kvStore) Stop() {
	defer func() { recover() }()
	close(s.done)
}

func (s *kvStore) Wait() {
	s.wg.Wait()
}

// --- Demo ---

func main() {
	store, err := NewKVStore(WithCommandBuffer(32))
	if err != nil {
		fmt.Printf("init error: %v\n", err)
		return
	}
	defer func() { store.Stop(); store.Wait() }()

	// Set some values from multiple goroutines.
	var wg sync.WaitGroup
	pairs := []struct{ k, v string }{
		{"name", "Alice"},
		{"city", "Portland"},
		{"lang", "Go"},
		{"editor", "Emacs"},
	}
	for _, p := range pairs {
		wg.Add(1)
		go func(k, v string) {
			defer wg.Done()
			if err := store.Set(k, v); err != nil {
				fmt.Printf("set error: %v\n", err)
			}
		}(p.k, p.v)
	}
	wg.Wait()

	// Read them back.
	for _, p := range pairs {
		v, err := store.Get(p.k)
		if err != nil {
			fmt.Printf("get %q: error: %v\n", p.k, err)
		} else {
			fmt.Printf("%s = %s\n", p.k, v)
		}
	}

	// Try a missing key.
	_, err = store.Get("nonexistent")
	fmt.Printf("missing key error: %v\n", err)

	// Delete and verify.
	_ = store.Delete("city")
	keys, _ := store.Keys()
	fmt.Printf("keys after delete: %v\n", keys)
}
