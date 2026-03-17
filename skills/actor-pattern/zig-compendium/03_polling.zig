// Example 03: Polling Actor — Timer-Based Background Work
//
// An actor that combines request-response commands with a background poller.
// The poller sleeps between readings (interval measured from end of work,
// avoiding cron-stampede). Demonstrates:
//   - Poller as a plain function (not a struct)
//   - Poller lifecycle owned by run() via an atomic stop flag
//   - Poller sending commands on the actor's channel
//   - std.Thread.sleep for intervals (no timer primitive needed)
//
// Build & run:
//   cd zig-compendium && zig build-exe 03_polling.zig && ./03_polling

const std = @import("std");
const Channel = @import("channel.zig").Channel;
const print = std.debug.print;

const allocator = std.heap.page_allocator;

// --- Command definition ---

const SensorCmd = union(enum) {
    new_reading: struct {
        value: f64,
        reply: *Channel(void),
    },
    latest: struct {
        reply: *Channel(f64),
    },
    history: struct {
        reply: *Channel(HistoryReply),
    },
};

const HistoryReply = struct {
    readings: []const f64,
};

// --- Poller: a plain function, not a struct ---

fn startPoller(
    cmds: *Channel(SensorCmd),
    stop: *std.atomic.Value(bool),
    interval_ns: u64,
) !std.Thread {
    return try std.Thread.spawn(.{}, struct {
        fn run(c: *Channel(SensorCmd), s: *std.atomic.Value(bool), interval: u64) void {
            var rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp() & 0xFFFFFFFF));
            const random = rng.random();

            while (!s.load(.acquire)) {
                // Simulate reading a sensor: random temperature 20-30.
                const reading: f64 = 20.0 + @as(f64, @floatFromInt(random.intRangeAtMost(u32, 0, 1000))) / 100.0;

                var reply = Channel(void).init(allocator, 1);
                defer reply.deinit();
                c.send(.{ .new_reading = .{ .value = reading, .reply = &reply } });
                _ = reply.recv();

                // Sleep after work completes (adaptive interval).
                std.Thread.sleep(interval);
            }
        }
    }.run, .{ cmds, stop, interval_ns });
}

// --- Actor: dispatch thread ---

fn sensorActor(cmds: *Channel(SensorCmd)) void {
    var latest: f64 = 0.0;
    var readings = std.ArrayList(f64).initCapacity(allocator, 64) catch unreachable;

    while (cmds.recv()) |cmd| {
        switch (cmd) {
            .new_reading => |c| {
                latest = c.value;
                readings.append(allocator, c.value) catch {};
                c.reply.send({});
            },
            .latest => |c| {
                c.reply.send(latest);
            },
            .history => |c| {
                // Return a copy so the caller can't see mutations.
                const copy = allocator.dupe(f64, readings.items) catch &.{};
                c.reply.send(.{ .readings = copy });
            },
        }
    }
}

// --- Convenience functions ---

fn getLatest(cmds: *Channel(SensorCmd)) f64 {
    var reply = Channel(f64).init(allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .latest = .{ .reply = &reply } });
    return reply.recv() orelse 0.0;
}

fn getHistory(cmds: *Channel(SensorCmd)) []const f64 {
    var reply = Channel(HistoryReply).init(allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .history = .{ .reply = &reply } });
    const r = reply.recv() orelse return &.{};
    return r.readings;
}

// --- Demo ---

pub fn main() !void {
    var cmds = Channel(SensorCmd).init(allocator, 64);
    defer cmds.deinit();

    const actor = try std.Thread.spawn(.{}, sensorActor, .{&cmds});

    // Start the poller: read every 200ms.
    var stop_flag = std.atomic.Value(bool).init(false);
    const poller = try startPoller(&cmds, &stop_flag, 200_000_000);

    // Let the poller collect some readings.
    std.Thread.sleep(1_000_000_000); // 1 second

    const latest = getLatest(&cmds);
    print("Latest reading: {d:.2} C\n", .{latest});

    const history = getHistory(&cmds);
    defer allocator.free(history);
    print("Collected {d} readings:\n", .{history.len});
    for (history, 0..) |r, i| {
        print("  [{d}] {d:.2} C\n", .{ i, r });
    }

    // Shut down: stop the poller, then close the command channel.
    stop_flag.store(true, .release);
    poller.join();
    cmds.close();
    actor.join();
}
