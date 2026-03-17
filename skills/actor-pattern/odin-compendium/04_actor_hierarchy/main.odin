// Example 04: Actor Hierarchy -- Coordinator with Sub-Actors
//
// A coordinator (Application) manages sub-actors representing distinct
// operational modes. Demonstrates:
//   - Stoppable interface via procedure pointers in a vtable struct
//   - State_Builder function type for deferred actor construction
//   - Coordinator that owns one sub-actor at a time
//   - Fire-and-forget Set_State (avoids the deadlock trap)
//   - Recoverable_Error for graceful fallback chains
//   - Error_App as terminal state
//   - Sub-actor triggering its own replacement
//   - Type tag on sub-actor to decide behavior in the demo
//
// Build & run:
//   odin run 04_actor_hierarchy
//   odin build 04_actor_hierarchy -out:build/04 && ./build/04

package main

import "core:fmt"
import "core:sync/chan"
import "core:thread"
import "core:time"

// ============================================================================
// Core Abstractions
// ============================================================================

// Sub-actors implement this interface via a vtable.
Sub_Actor :: struct {
	data:     rawptr,
	stop:     proc(data: rawptr),
	wait:     proc(data: rawptr),
	type_tag: Sub_Actor_Type,
}

Sub_Actor_Type :: enum {
	None,
	Setup,
	Running,
	Error,
}

sub_actor_stop :: proc(s: ^Sub_Actor) {
	if s != nil && s.stop != nil { s.stop(s.data) }
}

sub_actor_wait :: proc(s: ^Sub_Actor) {
	if s != nil && s.wait != nil { s.wait(s.data) }
}

// State_Builder defers actor construction until the coordinator calls it.
State_Builder :: proc(app: ^Application) -> (Sub_Actor, bool)

// Recoverable_Error: if a builder fails, it can provide a fallback builder.
Recoverable_Error :: struct {
	message:      string,
	next_builder: State_Builder,
}

// build_state tries the builder, then one level of recovery, then Error_App.
build_state :: proc(app: ^Application, builder: State_Builder) -> Sub_Actor {
	state, ok := builder(app)
	if ok { return state }

	// The builder can stash a recoverable error on the app for us to read.
	if app.last_recovery.next_builder != nil {
		recovery := app.last_recovery
		app.last_recovery = {}
		state2, ok2 := recovery.next_builder(app)
		if ok2 { return state2 }
	}

	return new_error_app(app.last_error)
}

// ============================================================================
// Error_App -- Terminal State
// ============================================================================

Error_App :: struct {
	message: string,
}

new_error_app :: proc(message: string) -> Sub_Actor {
	e := new(Error_App)
	e.message = message
	return Sub_Actor{
		data     = e,
		stop     = proc(data: rawptr) {},
		wait     = proc(data: rawptr) {},
		type_tag = .Error,
	}
}

error_app_get_error :: proc(s: ^Sub_Actor) -> string {
	e := cast(^Error_App)s.data
	return e.message
}

// ============================================================================
// Coordinator (Application)
// ============================================================================

App_Command_Tag :: enum {
	Get_State,
	Set_State,
}

App_Command :: struct {
	tag:     App_Command_Tag,
	builder: State_Builder,
	reply:   chan.Chan(Sub_Actor), // only used for Get_State
}

Application :: struct {
	commands:      chan.Chan(App_Command),
	last_error:    string,
	last_recovery: Recoverable_Error,
}

app_init :: proc(app: ^Application) {
	app.commands = chan.create(chan.Chan(App_Command), 64, context.allocator) or_else panic("cmd chan")
}

app_destroy :: proc(app: ^Application) {
	chan.destroy(app.commands)
}

// Dispatch thread.
app_run :: proc(app: ^Application) {
	// We need the initial builder. We'll read it as the first command.
	// Actually, let's use a simpler approach: the initial state is built
	// before starting the thread and passed via a startup command.
	current: Sub_Actor

	for {
		cmd, ok := chan.recv(app.commands)
		if !ok { break }

		switch cmd.tag {
		case .Get_State:
			chan.send(cmd.reply, current)

		case .Set_State:
			// Fire-and-forget: no reply channel.
			sub_actor_stop(&current)
			sub_actor_wait(&current)
			current = build_state(app, cmd.builder)
		}
	}

	// Clean up current state on shutdown.
	sub_actor_stop(&current)
	sub_actor_wait(&current)
}

// Get_State is synchronous -- request/response.
app_get_state :: proc(app: ^Application) -> Sub_Actor {
	reply := chan.create(chan.Chan(Sub_Actor), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(app.commands, App_Command{tag = .Get_State, reply = reply})
	result, _ := chan.recv(reply)
	return result
}

// Set_State is fire-and-forget -- no reply channel, no blocking.
// This prevents the deadlock where a sub-actor synchronously waits for
// Set_State while the coordinator waits for the sub-actor to Stop.
app_set_state :: proc(app: ^Application, builder: State_Builder) {
	chan.send(app.commands, App_Command{tag = .Set_State, builder = builder})
}

app_stop :: proc(app: ^Application) {
	chan.close(app.commands)
}

// ============================================================================
// Sub-Actor: Setup_Mode
// ============================================================================

Setup_Command_Tag :: enum {
	Get_Step,
	Advance,
}

Setup_Command :: struct {
	tag:   Setup_Command_Tag,
	reply: chan.Chan(int),
}

Setup_Mode :: struct {
	app:      ^Application,
	commands: chan.Chan(Setup_Command),
}

new_setup_mode :: proc(app: ^Application) -> (Sub_Actor, bool) {
	s := new(Setup_Mode)
	s.app = app
	s.commands = chan.create(chan.Chan(Setup_Command), 64, context.allocator) or_else panic("setup cmd chan")

	t := thread.create_and_start_with_poly_data(s, setup_run)
	_ = t // thread self-manages via channel close

	return Sub_Actor{
		data     = s,
		stop     = proc(data: rawptr) { s := cast(^Setup_Mode)data; chan.close(s.commands) },
		wait     = proc(data: rawptr) {
			// Give the dispatch thread time to drain.
			time.sleep(10 * time.Millisecond)
		},
		type_tag = .Setup,
	}, true
}

setup_run :: proc(s: ^Setup_Mode) {
	step := 1
	total_steps :: 3

	for {
		cmd, ok := chan.recv(s.commands)
		if !ok { break }

		switch cmd.tag {
		case .Get_Step:
			chan.send(cmd.reply, step)

		case .Advance:
			if step < total_steps {
				step += 1
				chan.send(cmd.reply, 0) // ack (0 = success)
			} else {
				chan.send(cmd.reply, 0) // ack

				// Trigger transition -- fire-and-forget.
				app := s.app
				app_set_state(app, proc(a: ^Application) -> (Sub_Actor, bool) {
					return new_running_mode(a, "config-from-step-3")
				})
			}
		}
	}
}

setup_get_step :: proc(s: ^Setup_Mode) -> int {
	reply := chan.create(chan.Chan(int), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Setup_Command{tag = .Get_Step, reply = reply})
	result, _ := chan.recv(reply)
	return result
}

setup_advance :: proc(s: ^Setup_Mode) {
	reply := chan.create(chan.Chan(int), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Setup_Command{tag = .Advance, reply = reply})
	_, _ = chan.recv(reply)
}

// ============================================================================
// Sub-Actor: Running_Mode
// ============================================================================

Running_Command_Tag :: enum {
	Get_Status,
}

Running_Command :: struct {
	tag:   Running_Command_Tag,
	reply: chan.Chan(string),
}

Running_Mode :: struct {
	app:      ^Application,
	commands: chan.Chan(Running_Command),
	config:   string,        // immutable after construction
	started:  time.Time,
}

new_running_mode :: proc(app: ^Application, config: string) -> (Sub_Actor, bool) {
	r := new(Running_Mode)
	r.app = app
	r.config = config
	r.started = time.now()
	r.commands = chan.create(chan.Chan(Running_Command), 64, context.allocator) or_else panic("running cmd chan")

	t := thread.create_and_start_with_poly_data(r, running_run)
	_ = t

	return Sub_Actor{
		data     = r,
		stop     = proc(data: rawptr) { r := cast(^Running_Mode)data; chan.close(r.commands) },
		wait     = proc(data: rawptr) {
			time.sleep(10 * time.Millisecond)
		},
		type_tag = .Running,
	}, true
}

running_run :: proc(r: ^Running_Mode) {
	for {
		cmd, ok := chan.recv(r.commands)
		if !ok { break }

		switch cmd.tag {
		case .Get_Status:
			elapsed := time.since(r.started)
			ms := time.duration_milliseconds(elapsed)
			status := fmt.tprintf("running (config=%s, uptime=%.0fms)", r.config, ms)
			chan.send(cmd.reply, status)
		}
	}
}

running_get_status :: proc(r: ^Running_Mode) -> string {
	reply := chan.create(chan.Chan(string), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(r.commands, Running_Command{tag = .Get_Status, reply = reply})
	result, _ := chan.recv(reply)
	return result
}

running_config :: proc(r: ^Running_Mode) -> string {
	return r.config // immutable, safe for concurrent reads
}

// ============================================================================
// Demo
// ============================================================================

main :: proc() {
	app: Application
	app_init(&app)
	defer app_destroy(&app)

	// Start the coordinator dispatch thread.
	dispatch := thread.create_and_start_with_poly_data(&app, app_run)

	// Set initial state to Setup_Mode.
	app_set_state(&app, new_setup_mode)
	time.sleep(50 * time.Millisecond)

	// Walk through the setup wizard.
	for _ in 0 ..< 4 {
		state := app_get_state(&app)

		switch state.type_tag {
		case .Setup:
			s := cast(^Setup_Mode)state.data
			step := setup_get_step(s)
			fmt.printf("[Setup] On step %d\n", step)
			setup_advance(s)
			// After advancing past the last step, give the coordinator
			// a moment to process the fire-and-forget Set_State.
			time.sleep(50 * time.Millisecond)

		case .Running:
			r := cast(^Running_Mode)state.data
			status := running_get_status(r)
			fmt.printf("[Running] %s\n", status)
			fmt.printf("[Running] Config (direct getter): %s\n", running_config(r))

		case .Error:
			msg := error_app_get_error(&state)
			fmt.printf("[Error] %s\n", msg)

		case .None:
			// Not yet initialized
		}
	}

	// Demonstrate RecoverableError: force a transition to a builder that fails
	// with recovery.
	fmt.println("\n--- Triggering recoverable error ---")
	app_set_state(&app, proc(a: ^Application) -> (Sub_Actor, bool) {
		a.last_error = "primary database unavailable"
		a.last_recovery = Recoverable_Error{
			message = "primary database unavailable",
			next_builder = proc(a: ^Application) -> (Sub_Actor, bool) {
				fmt.println("[Recovery] Falling back to read-only mode")
				return new_running_mode(a, "read-only-fallback")
			},
		}
		return {}, false
	})
	time.sleep(50 * time.Millisecond)

	state := app_get_state(&app)
	if state.type_tag == .Running {
		r := cast(^Running_Mode)state.data
		status := running_get_status(r)
		fmt.printf("[After Recovery] %s\n", status)
	}

	// Demonstrate unrecoverable error -> Error_App.
	fmt.println("\n--- Triggering unrecoverable error ---")
	app_set_state(&app, proc(a: ^Application) -> (Sub_Actor, bool) {
		a.last_error = "everything is on fire"
		a.last_recovery = Recoverable_Error{
			message = "everything is on fire",
			next_builder = proc(a: ^Application) -> (Sub_Actor, bool) {
				a.last_error = "recovery also failed"
				return {}, false
			},
		}
		return {}, false
	})
	time.sleep(50 * time.Millisecond)

	state = app_get_state(&app)
	if state.type_tag == .Error {
		msg := error_app_get_error(&state)
		fmt.printf("[ErrorApp] Parked with: %s\n", msg)
	}

	// Shut down.
	app_stop(&app)
	thread.join(dispatch)
	thread.destroy(dispatch)
}
