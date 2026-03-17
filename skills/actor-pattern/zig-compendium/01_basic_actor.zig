// Example 01: Basic Actor — Counter
//
// The simplest possible actor: a counter that multiple threads can safely
// increment and read without locks. Demonstrates:
//   - Commands as a tagged union (Zig's union(enum))
//   - Each command variant carries a *Channel(Reply) for the response
//   - A dispatch thread owns all mutable state
//   - Shutdown via closing the command channel; dispatch checks for null
//   - std.Thread.spawn for worker threads, .join() to wait
//
// Build & run:
//   cd zig-compendium && zig build-exe 01_basic_actor.zig && ./01_basic_actor

const std = @import("std");
const Channel = @import("channel.zig").Channel;

// --- Command definition ---

const CounterCmd = union(enum) {
    increment: *Channel(void),
    get: *Channel(i64),
};

// --- Actor: dispatch thread ---

fn counterActor(cmds: *Channel(CounterCmd)) void {
    var count: i64 = 0;

    while (cmds.recv()) |cmd| {
        switch (cmd) {
            .increment => |reply| {
                count += 1;
                reply.send({});
            },
            .get => |reply| {
                reply.send(count);
            },
        }
    }
}

// --- Helper: send a command and wait for the reply ---

fn increment(cmds: *Channel(CounterCmd)) void {
    var reply = Channel(void).init(std.heap.page_allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .increment = &reply });
    _ = reply.recv();
}

fn get(cmds: *Channel(CounterCmd)) i64 {
    var reply = Channel(i64).init(std.heap.page_allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .get = &reply });
    return reply.recv() orelse 0;
}

// --- Demo ---

pub fn main() !void {
    var cmds = Channel(CounterCmd).init(std.heap.page_allocator, 64);
    defer cmds.deinit();

    // Start the actor thread.
    const actor = try std.Thread.spawn(.{}, counterActor, .{&cmds});

    // Spawn 10 threads that each increment 100 times.
    var workers: [10]std.Thread = undefined;
    for (&workers) |*w| {
        w.* = try std.Thread.spawn(.{}, struct {
            fn run(c: *Channel(CounterCmd)) void {
                for (0..100) |_| {
                    increment(c);
                }
            }
        }.run, .{&cmds});
    }

    // Wait for all workers to finish.
    for (&workers) |*w| {
        w.join();
    }

    // Read the final count.
    const val = get(&cmds);
    std.debug.print("Final count: {} (expected 1000)\n", .{val});

    // Shut down the actor.
    cmds.close();
    actor.join();
}
