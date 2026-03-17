// Example 01: Basic Actor — Counter
//
// The simplest possible actor: a counter that multiple threads can safely
// increment and read without locks. Demonstrates:
//   - Command tags (enum of operations)
//   - Command struct with result pointer + done channel
//   - A dispatch thread owning all mutable state
//   - Public procedures using send_receive helper
//   - Shutdown via closing the command channel
//
// Build & run:  ~/jai/jai/bin/jai-linux first.jai - 01

// ---------------------------------------------------------------------------
// Result exchange: caller creates these on its stack, sends pointers in the
// command, blocks on the done channel until the actor signals.
// ---------------------------------------------------------------------------

Command_Tag :: enum {
    INCREMENT;
    GET;
}

Command :: struct {
    tag:        Command_Tag;
    result_int: *int;              // pointer to caller's stack variable
    done:       *Channel(bool);    // pointer to caller's stack channel
}

// ---------------------------------------------------------------------------
// Actor struct — holds the command channel and dispatch thread.
// All mutable state lives inside the dispatch thread as local variables.
// ---------------------------------------------------------------------------

Counter :: struct {
    commands: Channel(Command);
    thread:   Thread;
}

init_counter :: (c: *Counter) {
    init(*c.commands, 64);
    thread_init(*c.thread, counter_run);
    c.thread.data = c;
    thread_start(*c.thread);
}

destroy_counter :: (c: *Counter) {
    close(*c.commands);
    thread_is_done(*c.thread, -1);   // join — wait for dispatch thread to exit
    thread_deinit(*c.thread);
    destroy(*c.commands);
}

// ---------------------------------------------------------------------------
// Dispatch thread — owns all mutable state as locals.
// ---------------------------------------------------------------------------

counter_run :: (thread: *Thread) -> s64 {
    c := cast(*Counter) thread.data;

    // --- All mutable state lives here ---
    count := 0;

    while true {
        cmd, ok := receive(*c.commands);
        if !ok break;  // channel closed — shutdown

        if cmd.tag == {
            case .INCREMENT;
                count += 1;

            case .GET;
                cmd.result_int.* = count;
        }

        send(cmd.done, true);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Public API — each creates a command on the stack, sends it, blocks for
// the result.
// ---------------------------------------------------------------------------

counter_increment :: (c: *Counter) {
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*c.commands, Command.{tag = .INCREMENT, done = *done});
    receive(*done);
}

counter_get :: (c: *Counter) -> int {
    result: int;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*c.commands, Command.{tag = .GET, result_int = *result, done = *done});
    receive(*done);
    return result;
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

main :: () {
    ctr: Counter;
    init_counter(*ctr);
    defer destroy_counter(*ctr);

    // Spawn 10 threads that each increment 100 times.
    THREADS :: 10;
    ITERS   :: 100;

    threads: [THREADS] Thread;
    ctxs:    [THREADS] Worker_Ctx;

    for i: 0..THREADS-1 {
        ctxs[i].counter = *ctr;
        ctxs[i].iterations = ITERS;
        thread_init(*threads[i], worker_proc);
        threads[i].data = *ctxs[i];
        thread_start(*threads[i]);
    }
    for i: 0..THREADS-1 {
        thread_is_done(*threads[i], -1);
        thread_deinit(*threads[i]);
    }

    val := counter_get(*ctr);
    print("Final count: % (expected %)\n", val, THREADS * ITERS);
    assert(val == THREADS * ITERS);
}

Worker_Ctx :: struct {
    counter:    *Counter;
    iterations: int;
}

worker_proc :: (thread: *Thread) -> s64 {
    ctx := cast(*Worker_Ctx) thread.data;
    for 0..ctx.iterations-1 {
        counter_increment(ctx.counter);
    }
    return 0;
}

#import "Basic";
#import "Thread";
#import "channel";
