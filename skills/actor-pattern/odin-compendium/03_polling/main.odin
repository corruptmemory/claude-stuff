// Example 03: Polling Actor -- Timer-Based Background Work
//
// An actor that combines request-response commands with a background poller.
// The poller sleeps between iterations (measuring interval from END of work
// to avoid the cron-stampede problem). Demonstrates:
//   - Poller as a plain thread (not an actor)
//   - Poller lifecycle owned by the dispatch thread via a stop channel
//   - Poller sending commands on the actor's command channel
//   - Adaptive interval (sleep after work completes)
//
// Build & run:
//   odin run 03_polling
//   odin build 03_polling -out:build/03 && ./build/03

package main

import "core:fmt"
import "core:math/rand"
import "core:sync/chan"
import "core:thread"
import "core:time"

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

Sensor_Result :: union {
	f64,
	[]f64,
	Sensor_Ack,
}

Sensor_Ack :: struct {}

// ---------------------------------------------------------------------------
// Command tags and command struct
// ---------------------------------------------------------------------------

Command_Tag :: enum {
	New_Reading,
	Latest,
	History,
}

Command :: struct {
	tag:     Command_Tag,
	reading: f64,
	reply:   chan.Chan(Sensor_Result),
}

// ---------------------------------------------------------------------------
// Sensor Service actor
// ---------------------------------------------------------------------------

Sensor_Service :: struct {
	commands:  chan.Chan(Command),
	stop_chan: chan.Chan(bool), // signal poller + dispatch to stop
}

sensor_init :: proc(s: ^Sensor_Service) {
	s.commands = chan.create(chan.Chan(Command), 64, context.allocator) or_else panic("cmd chan")
	s.stop_chan = chan.create(chan.Chan(bool), 1, context.allocator) or_else panic("stop chan")
}

sensor_destroy :: proc(s: ^Sensor_Service) {
	chan.destroy(s.commands)
	chan.destroy(s.stop_chan)
}

// Dispatch thread -- owns all mutable state as local variables.
sensor_run :: proc(s: ^Sensor_Service) {
	readings: [dynamic]f64
	defer delete(readings)
	latest: f64 = 0.0

	for {
		cmd, ok := chan.recv(s.commands)
		if !ok { break } // channel closed

		switch cmd.tag {
		case .New_Reading:
			latest = cmd.reading
			append(&readings, cmd.reading)
			chan.send(cmd.reply, Sensor_Result(Sensor_Ack{}))

		case .Latest:
			chan.send(cmd.reply, Sensor_Result(latest))

		case .History:
			// Return a copy.
			cp := make([]f64, len(readings))
			copy(cp, readings[:])
			chan.send(cmd.reply, Sensor_Result(cp))
		}
	}
}

// ---------------------------------------------------------------------------
// Poller -- a plain thread that periodically sends readings to the actor
// ---------------------------------------------------------------------------

Poller_Ctx :: struct {
	service:     ^Sensor_Service,
	interval_ms: int,
}

poller_run :: proc(ctx: ^Poller_Ctx) {
	// Fire immediately for the first reading, then sleep after each.
	first := true

	for {
		if !first {
			time.sleep(time.Duration(ctx.interval_ms) * time.Millisecond)
		}
		first = false

		// Check if we should stop (non-blocking).
		_, stopped := chan.try_recv(ctx.service.stop_chan)
		if stopped { return }

		// Generate a reading.
		reading := 20.0 + rand.float64() * 10.0

		// Send to actor via command channel.
		reply := chan.create(chan.Chan(Sensor_Result), 1, context.allocator) or_else panic("reply chan")

		ok := chan.send(ctx.service.commands, Command{
			tag     = .New_Reading,
			reading = reading,
			reply   = reply,
		})
		if !ok {
			chan.destroy(reply)
			return // command channel closed
		}
		_, _ = chan.recv(reply)
		chan.destroy(reply)
	}
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

sensor_latest :: proc(s: ^Sensor_Service) -> f64 {
	reply := chan.create(chan.Chan(Sensor_Result), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Command{tag = .Latest, reply = reply})
	result, _ := chan.recv(reply)
	return result.(f64)
}

sensor_history :: proc(s: ^Sensor_Service) -> []f64 {
	reply := chan.create(chan.Chan(Sensor_Result), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Command{tag = .History, reply = reply})
	result, _ := chan.recv(reply)
	return result.([]f64)
}

sensor_stop :: proc(s: ^Sensor_Service) {
	// Signal the poller to stop.
	chan.send(s.stop_chan, true)
	// Close the command channel to stop the dispatch thread.
	chan.close(s.commands)
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

main :: proc() {
	svc: Sensor_Service
	sensor_init(&svc)
	defer sensor_destroy(&svc)

	// Start the dispatch thread.
	dispatch := thread.create_and_start_with_poly_data(&svc, sensor_run)

	// Start the poller thread.
	poller_ctx := Poller_Ctx{service = &svc, interval_ms = 200}
	poller := thread.create_and_start_with_poly_data(&poller_ctx, poller_run)

	// Let the poller collect some readings.
	time.sleep(1 * time.Second)

	latest := sensor_latest(&svc)
	fmt.printf("Latest reading: %.2f C\n", latest)

	history := sensor_history(&svc)
	defer delete(history)
	fmt.printf("Collected %d readings:\n", len(history))
	for r, i in history {
		fmt.printf("  [%d] %.2f C\n", i, r)
	}

	// Shut down.
	sensor_stop(&svc)
	thread.join(poller)
	thread.destroy(poller)
	thread.join(dispatch)
	thread.destroy(dispatch)
}
