// Example 04: Actor Hierarchy — Coordinator with Sub-Actors
//
// A coordinator (Application) manages sub-actors representing distinct
// operational modes. Demonstrates:
//   - Stoppable interface via function pointers
//   - Coordinator that owns one sub-actor at a time
//   - Fire-and-forget set_state (avoids the deadlock trap)
//   - Sub-actor triggering its own replacement
//   - Type-switching on sub-actor to decide behavior
//
// Build & run:  ~/jai/jai/bin/jai-linux first.jai - 04

// ============================================================================
// Core Abstractions
// ============================================================================

// Stoppable — common interface for all managed sub-actors.
// In Jai we use a struct with function pointers instead of an interface.
Stoppable :: struct {
    stop: (data: *void);
    data: *void;
    kind: Sub_Actor_Kind;
}

Sub_Actor_Kind :: enum {
    SETUP;
    RUNNING;
    ERROR;
}

// State_Builder — defers actor construction until the coordinator calls it.
State_Builder :: #type (app: *Application) -> Stoppable;

// ============================================================================
// Coordinator (Application)
// ============================================================================

App_Command_Tag :: enum {
    GET_STATE;
    SET_STATE;
}

App_Command :: struct {
    tag:            App_Command_Tag;
    builder:        State_Builder;      // only for SET_STATE
    result_state:   *Stoppable;         // only for GET_STATE
    done:           *Channel(bool);     // only for GET_STATE (SET_STATE is fire-and-forget)
}

Application :: struct {
    commands: Channel(App_Command);
    thread:   Thread;
    initial:  State_Builder;
}

init_application :: (app: *Application, initial: State_Builder) {
    init(*app.commands, 64);
    app.initial = initial;
    thread_init(*app.thread, app_run);
    app.thread.data = app;
    thread_start(*app.thread);
}

destroy_application :: (app: *Application) {
    close(*app.commands);
    thread_is_done(*app.thread, -1);
    thread_deinit(*app.thread);
    destroy(*app.commands);
}

app_run :: (thread: *Thread) -> s64 {
    app := cast(*Application) thread.data;

    // Build the initial sub-actor.
    current := app.initial(app);

    while true {
        cmd, ok := receive(*app.commands);
        if !ok break;

        if cmd.tag == {
            case .GET_STATE;
                cmd.result_state.* = current;
                send(cmd.done, true);

            case .SET_STATE;
                // Fire-and-forget — no done channel, no blocking.
                // This is critical: if SET_STATE were synchronous, a sub-actor
                // calling set_state from within its own dispatch loop would
                // deadlock (sub-actor waits for coordinator, coordinator waits
                // for sub-actor.stop()).
                if current.stop != null {
                    current.stop(current.data);
                }
                current = cmd.builder(app);
        }
    }

    // Shutdown: stop the final sub-actor.
    if current.stop != null {
        current.stop(current.data);
    }
    return 0;
}

// --- Public API ---

app_get_state :: (app: *Application) -> Stoppable {
    result: Stoppable;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*app.commands, App_Command.{tag = .GET_STATE, result_state = *result, done = *done});
    receive(*done);
    return result;
}

// Fire-and-forget — no result, no blocking.
app_set_state :: (app: *Application, builder: State_Builder) {
    send(*app.commands, App_Command.{tag = .SET_STATE, builder = builder});
}

// ============================================================================
// Sub-Actor: Setup Mode
// ============================================================================

Setup_Command_Tag :: enum {
    GET_STEP;
    ADVANCE;
}

Setup_Command :: struct {
    tag:        Setup_Command_Tag;
    result_int: *int;
    done:       *Channel(bool);
}

Setup_State :: struct {
    app:      *Application;
    commands: Channel(Setup_Command);
    thread:   Thread;
}

build_setup :: (app: *Application) -> Stoppable {
    state := New(Setup_State);
    state.app = app;
    init(*state.commands, 64);
    thread_init(*state.thread, setup_run);
    state.thread.data = state;
    thread_start(*state.thread);

    return Stoppable.{stop = setup_stop, data = state, kind = .SETUP};
}

setup_stop :: (data: *void) {
    state := cast(*Setup_State) data;
    close(*state.commands);
    thread_is_done(*state.thread, -1);
    thread_deinit(*state.thread);
    destroy(*state.commands);
    free(state);
}

setup_run :: (thread: *Thread) -> s64 {
    state := cast(*Setup_State) thread.data;

    step := 1;
    TOTAL_STEPS :: 3;

    while true {
        cmd, ok := receive(*state.commands);
        if !ok break;

        if cmd.tag == {
            case .GET_STEP;
                cmd.result_int.* = step;

            case .ADVANCE;
                if step < TOTAL_STEPS {
                    step += 1;
                } else {
                    // Trigger transition — fire-and-forget.
                    // Don't break or return; let the receive loop drain
                    // naturally when the coordinator closes our channel.
                    app_set_state(state.app, build_running);
                }
        }
        send(cmd.done, true);
    }
    return 0;
}

setup_get_step :: (state: *Setup_State) -> int {
    result: int;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);
    send(*state.commands, Setup_Command.{tag = .GET_STEP, result_int = *result, done = *done});
    receive(*done);
    return result;
}

setup_advance :: (state: *Setup_State) {
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);
    send(*state.commands, Setup_Command.{tag = .ADVANCE, done = *done});
    receive(*done);
}

// ============================================================================
// Sub-Actor: Running Mode
// ============================================================================

Running_Command_Tag :: enum {
    GET_STATUS;
}

Running_Command :: struct {
    tag:           Running_Command_Tag;
    result_string: *string;
    done:          *Channel(bool);
}

Running_State :: struct {
    app:      *Application;
    commands: Channel(Running_Command);
    thread:   Thread;
    config:   string;   // immutable after construction — safe for direct reads
}

build_running :: (app: *Application) -> Stoppable {
    state := New(Running_State);
    state.app = app;
    state.config = "config-from-setup";
    init(*state.commands, 64);
    thread_init(*state.thread, running_run);
    state.thread.data = state;
    thread_start(*state.thread);

    return Stoppable.{stop = running_stop, data = state, kind = .RUNNING};
}

running_stop :: (data: *void) {
    state := cast(*Running_State) data;
    close(*state.commands);
    thread_is_done(*state.thread, -1);
    thread_deinit(*state.thread);
    destroy(*state.commands);
    free(state);
}

running_run :: (thread: *Thread) -> s64 {
    state := cast(*Running_State) thread.data;

    while true {
        cmd, ok := receive(*state.commands);
        if !ok break;

        if cmd.tag == {
            case .GET_STATUS;
                cmd.result_string.* = tprint("running (config=%)", state.config);
        }
        send(cmd.done, true);
    }
    return 0;
}

running_get_status :: (state: *Running_State) -> string {
    result: string;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);
    send(*state.commands, Running_Command.{tag = .GET_STATUS, result_string = *result, done = *done});
    receive(*done);
    return result;
}

// ============================================================================
// Error State (not a full actor — just holds an error)
// ============================================================================

Error_State :: struct {
    message: string;
}

build_error :: (app: *Application) -> Stoppable {
    state := New(Error_State);
    state.message = "something went wrong";
    return Stoppable.{stop = error_stop, data = state, kind = .ERROR};
}

error_stop :: (data: *void) {
    state := cast(*Error_State) data;
    free(state);
}

// ============================================================================
// Demo
// ============================================================================

main :: () {
    app: Application;
    init_application(*app, build_setup);
    defer destroy_application(*app);

    // Walk through the setup wizard.
    for 0..3 {
        state := app_get_state(*app);

        if state.kind == {
            case .SETUP;
                setup := cast(*Setup_State) state.data;
                step := setup_get_step(setup);
                print("[Setup] On step %\n", step);
                setup_advance(setup);
                // Give coordinator time to process fire-and-forget set_state.
                sleep_milliseconds(50);

            case .RUNNING;
                running := cast(*Running_State) state.data;
                status := running_get_status(running);
                print("[Running] %\n", status);
                // Immutable field — safe for direct read, no command needed.
                print("[Running] Config (direct getter): %\n", running.config);

            case .ERROR;
                err := cast(*Error_State) state.data;
                print("[Error] %\n", err.message);
        }
    }

    // Force a transition to error state.
    print("\n--- Triggering error state ---\n");
    app_set_state(*app, build_error);
    sleep_milliseconds(50);

    state := app_get_state(*app);
    if state.kind == .ERROR {
        err := cast(*Error_State) state.data;
        print("[ErrorApp] Parked with: %\n", err.message);
    }
}

#import "Basic";
#import "Thread";
#import "channel";
