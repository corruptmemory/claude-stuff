// Example 03: Polling Actor — Timer-Based Background Work
//
// An actor that combines request-response commands with a background poller.
// The poller uses sleep (simulating timer-reset-after-work) to avoid the
// cron-stampede problem. Demonstrates:
//   - Poller as a plain thread function
//   - Poller sending commands on the actor's channel
//   - Adaptive interval (sleep after work completes)
//   - Coordinated shutdown via channel close + shutdown flag
//
// Build & run:  ~/jai/jai/bin/jai-linux first.jai - 03

// ---------------------------------------------------------------------------
// Command protocol
// ---------------------------------------------------------------------------

Command_Tag :: enum {
    NEW_READING;
    LATEST;
    HISTORY;
}

Command :: struct {
    tag:            Command_Tag;
    reading:        float64;            // payload for NEW_READING
    result_float:   *float64;           // result for LATEST
    result_history: *[..] float64;      // result for HISTORY
    done:           *Channel(bool);     // synchronization
}

// ---------------------------------------------------------------------------
// Actor
// ---------------------------------------------------------------------------

Sensor_Service :: struct {
    commands:       Channel(Command);
    dispatch_thread: Thread;
    poller_thread:   Thread;
    poll_interval:   int;                 // milliseconds
    shutdown:        bool;                // shared flag for poller
}

init_sensor :: (svc: *Sensor_Service, poll_interval_ms: int) {
    init(*svc.commands, 64);
    svc.poll_interval = poll_interval_ms;

    // Start dispatch thread.
    thread_init(*svc.dispatch_thread, sensor_run);
    svc.dispatch_thread.data = svc;
    thread_start(*svc.dispatch_thread);

    // Start poller thread.
    thread_init(*svc.poller_thread, poller_run);
    svc.poller_thread.data = svc;
    thread_start(*svc.poller_thread);
}

destroy_sensor :: (svc: *Sensor_Service) {
    svc.shutdown = true;
    close(*svc.commands);
    thread_is_done(*svc.poller_thread, -1);
    thread_deinit(*svc.poller_thread);
    thread_is_done(*svc.dispatch_thread, -1);
    thread_deinit(*svc.dispatch_thread);
    destroy(*svc.commands);
}

// ---------------------------------------------------------------------------
// Poller thread — sends NEW_READING commands on the actor's channel.
// Sleep after work completes (adaptive interval, not metronomic).
// ---------------------------------------------------------------------------

poller_run :: (thread: *Thread) -> s64 {
    svc := cast(*Sensor_Service) thread.data;

    while !svc.shutdown {
        // Simulate sensor read — simple pseudo-random temperature.
        reading := 20.0 + cast(float64)(rdtsc() % 1000) / 100.0;

        done: Channel(bool);
        init(*done, 1);

        if svc.shutdown { destroy(*done); break; }
        send(*svc.commands, Command.{tag = .NEW_READING, reading = reading, done = *done});
        receive(*done);
        destroy(*done);

        // Sleep AFTER work — interval measured from END of work.
        sleep_milliseconds(cast(s32) svc.poll_interval);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Dispatch thread
// ---------------------------------------------------------------------------

sensor_run :: (thread: *Thread) -> s64 {
    svc := cast(*Sensor_Service) thread.data;

    // --- All mutable state lives here ---
    readings: [..] float64;
    latest: float64 = 0.0;

    while true {
        cmd, ok := receive(*svc.commands);
        if !ok break;

        if cmd.tag == {
            case .NEW_READING;
                latest = cmd.reading;
                array_add(*readings, cmd.reading);

            case .LATEST;
                cmd.result_float.* = latest;

            case .HISTORY;
                // Return a copy.
                for readings array_add(cmd.result_history, it);
        }

        send(cmd.done, true);
    }

    array_free(readings);
    return 0;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

sensor_latest :: (svc: *Sensor_Service) -> float64 {
    result: float64;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*svc.commands, Command.{tag = .LATEST, result_float = *result, done = *done});
    receive(*done);
    return result;
}

sensor_history :: (svc: *Sensor_Service) -> [..] float64 {
    history: [..] float64;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*svc.commands, Command.{tag = .HISTORY, result_history = *history, done = *done});
    receive(*done);
    return history;
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

main :: () {
    svc: Sensor_Service;
    init_sensor(*svc, 200);
    defer destroy_sensor(*svc);

    // Let the poller collect some readings.
    sleep_milliseconds(1100);

    latest := sensor_latest(*svc);
    print("Latest reading: %°C\n", formatFloat(latest, trailing_width=2));

    history := sensor_history(*svc);
    defer array_free(history);
    print("Collected % readings:\n", history.count);
    for history {
        print("  [%] %°C\n", it_index, formatFloat(it, trailing_width=2));
    }
}

#import "Basic";
#import "Thread";
#import "Machine_X64";
#import "channel";
