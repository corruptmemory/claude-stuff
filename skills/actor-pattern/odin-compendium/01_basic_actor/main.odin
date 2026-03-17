// Example 01: Basic Actor -- Counter
//
// The simplest possible actor: a counter that multiple threads can safely
// increment and read without locks. Demonstrates:
//   - Command tags (enum of operations)
//   - Command struct with a reply channel pointer for result exchange
//   - A dispatch thread owning all mutable state as local variables
//   - Public procedures that create a reply channel, send command, block on reply
//   - Shutdown via closing the command channel
//
// Build & run:
//   odin run 01_basic_actor
//   odin build 01_basic_actor -out:build/01 && ./build/01

package main

import "core:fmt"
import "core:sync/chan"
import "core:thread"

// ---------------------------------------------------------------------------
// Command tags and command struct
// ---------------------------------------------------------------------------

Command_Tag :: enum {
	Increment,
	Get,
}

Command :: struct {
	tag:   Command_Tag,
	reply: chan.Chan(int), // caller-owned reply channel
}

// ---------------------------------------------------------------------------
// Counter actor
// ---------------------------------------------------------------------------

Counter :: struct {
	commands: chan.Chan(Command),
}

counter_init :: proc(c: ^Counter) {
	c.commands = chan.create(chan.Chan(Command), 64, context.allocator) or_else panic("failed to create command channel")
}

counter_destroy :: proc(c: ^Counter) {
	chan.destroy(c.commands)
}

// Dispatch thread -- owns all mutable state as local variables.
counter_run :: proc(c: ^Counter) {
	count := 0

	for {
		cmd, ok := chan.recv(c.commands)
		if !ok { break } // channel closed -- shutdown

		switch cmd.tag {
		case .Increment:
			count += 1
			chan.send(cmd.reply, 0) // ack
		case .Get:
			chan.send(cmd.reply, count)
		}
	}
}

// ---------------------------------------------------------------------------
// Public API -- each creates a reply channel, sends command, blocks for result
// ---------------------------------------------------------------------------

counter_increment :: proc(c: ^Counter) {
	reply := chan.create(chan.Chan(int), 1, context.allocator) or_else panic("failed to create reply channel")
	defer chan.destroy(reply)

	chan.send(c.commands, Command{tag = .Increment, reply = reply})
	_, _ = chan.recv(reply)
}

counter_get :: proc(c: ^Counter) -> int {
	reply := chan.create(chan.Chan(int), 1, context.allocator) or_else panic("failed to create reply channel")
	defer chan.destroy(reply)

	chan.send(c.commands, Command{tag = .Get, reply = reply})
	result, _ := chan.recv(reply)
	return result
}

counter_stop :: proc(c: ^Counter) {
	chan.close(c.commands)
}

// ---------------------------------------------------------------------------
// Worker thread context
// ---------------------------------------------------------------------------

Worker_Ctx :: struct {
	counter:    ^Counter,
	iterations: int,
}

worker_proc :: proc(ctx: ^Worker_Ctx) {
	for _ in 0 ..< ctx.iterations {
		counter_increment(ctx.counter)
	}
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

main :: proc() {
	ctr: Counter
	counter_init(&ctr)
	defer counter_destroy(&ctr)

	// Start the dispatch thread.
	dispatch_thread := thread.create_and_start_with_poly_data(&ctr, counter_run)

	// Spawn 10 threads that each increment 100 times.
	THREADS :: 10
	ITERS   :: 100

	ctxs: [THREADS]Worker_Ctx
	threads: [THREADS]^thread.Thread

	for i in 0 ..< THREADS {
		ctxs[i] = Worker_Ctx{counter = &ctr, iterations = ITERS}
		threads[i] = thread.create_and_start_with_poly_data(&ctxs[i], worker_proc)
	}

	// Wait for all worker threads.
	for i in 0 ..< THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	// Read the final count.
	val := counter_get(&ctr)
	fmt.printf("Final count: %d (expected %d)\n", val, THREADS * ITERS)
	assert(val == THREADS * ITERS)

	// Shut down the actor.
	counter_stop(&ctr)
	thread.join(dispatch_thread)
	thread.destroy(dispatch_thread)
}
