// Example 04: Actor Hierarchy — Coordinator with Sub-Actors
//
// A coordinator (Application) manages sub-actors representing distinct
// operational modes. Demonstrates:
//   - Coordinator that owns one sub-actor at a time
//   - Sub-actors as tagged unions (SetupMode, RunningMode, ErrorMode)
//   - Fire-and-forget SetState (avoids deadlock)
//   - Sub-actor triggering its own replacement
//   - Transition through setup -> running -> error states
//
// Build & run:
//   cd zig-compendium && zig build-exe 04_actor_hierarchy.zig && ./04_actor_hierarchy

const std = @import("std");
const Channel = @import("channel.zig").Channel;
const print = std.debug.print;

const allocator = std.heap.page_allocator;

// ============================================================================
// Sub-Actor interfaces via tagged union
// ============================================================================

const SubActor = union(enum) {
    setup: *SetupMode,
    running: *RunningMode,
    err: ErrorMode,
};

// ============================================================================
// ErrorMode — Terminal state (no thread, just stores the error message)
// ============================================================================

const ErrorMode = struct {
    message: []const u8,
};

// ============================================================================
// SetupMode — Simulates a setup wizard
// ============================================================================

const SetupCmd = union(enum) {
    get_step: *Channel(i32),
    advance: *Channel(bool), // true = ok, false = already done
};

const SetupMode = struct {
    cmds: Channel(SetupCmd),
    thread: std.Thread,
    app: *Application,

    fn start(app: *Application) *SetupMode {
        const self = allocator.create(SetupMode) catch @panic("alloc");
        self.* = .{
            .cmds = Channel(SetupCmd).init(allocator, 64),
            .thread = undefined,
            .app = app,
        };
        self.thread = std.Thread.spawn(.{}, SetupMode.run, .{self}) catch @panic("spawn");
        return self;
    }

    fn run(self: *SetupMode) void {
        var step: i32 = 1;
        const total_steps: i32 = 3;

        while (self.cmds.recv()) |cmd| {
            switch (cmd) {
                .get_step => |reply| {
                    reply.send(step);
                },
                .advance => |reply| {
                    if (step < total_steps) {
                        step += 1;
                        reply.send(true);
                    } else {
                        reply.send(true);
                        // Fire-and-forget: tell coordinator to transition.
                        self.app.setState(.{ .running = RunningMode.start(self.app, "config-from-step-3") });
                    }
                },
            }
        }
    }

    fn getStep(self: *SetupMode) i32 {
        var reply = Channel(i32).init(allocator, 1);
        defer reply.deinit();
        self.cmds.send(.{ .get_step = &reply });
        return reply.recv() orelse 0;
    }

    fn advance(self: *SetupMode) void {
        var reply = Channel(bool).init(allocator, 1);
        defer reply.deinit();
        self.cmds.send(.{ .advance = &reply });
        _ = reply.recv();
    }

    fn stop(self: *SetupMode) void {
        self.cmds.close();
        self.thread.join();
        self.cmds.deinit();
        allocator.destroy(self);
    }
};

// ============================================================================
// RunningMode — Normal operation
// ============================================================================

const RunningCmd = union(enum) {
    get_status: *Channel(Status),
};

const Status = struct {
    config: []const u8,
    uptime_ms: i64,
};

const RunningMode = struct {
    cmds: Channel(RunningCmd),
    thread: std.Thread,
    config: []const u8,

    fn start(app: *Application, config: []const u8) *RunningMode {
        _ = app;
        const self = allocator.create(RunningMode) catch @panic("alloc");
        self.* = .{
            .cmds = Channel(RunningCmd).init(allocator, 64),
            .thread = undefined,
            .config = config,
        };
        self.thread = std.Thread.spawn(.{}, RunningMode.run, .{self}) catch @panic("spawn");
        return self;
    }

    fn run(self: *RunningMode) void {
        const start_ns = std.time.nanoTimestamp();

        while (self.cmds.recv()) |cmd| {
            switch (cmd) {
                .get_status => |reply| {
                    const elapsed_ns = std.time.nanoTimestamp() - start_ns;
                    const elapsed_ms: i64 = @intCast(@divFloor(elapsed_ns, 1_000_000));
                    reply.send(.{
                        .config = self.config,
                        .uptime_ms = elapsed_ms,
                    });
                },
            }
        }
    }

    fn getStatus(self: *RunningMode) Status {
        var reply = Channel(Status).init(allocator, 1);
        defer reply.deinit();
        self.cmds.send(.{ .get_status = &reply });
        return reply.recv() orelse .{ .config = "unknown", .uptime_ms = 0 };
    }

    fn stop(self: *RunningMode) void {
        self.cmds.close();
        self.thread.join();
        self.cmds.deinit();
        allocator.destroy(self);
    }
};

// ============================================================================
// Coordinator (Application)
// ============================================================================

const AppCmd = union(enum) {
    get_state: *Channel(SubActor),
    set_state: SubActor, // fire-and-forget, no reply channel
};

const Application = struct {
    cmds: Channel(AppCmd),
    thread: std.Thread,

    /// Create the coordinator, then start it with a SetupMode sub-actor.
    /// This two-phase init solves the circular dependency: SetupMode needs
    /// the Application pointer, and Application needs the initial SubActor.
    fn startWithSetup() *Application {
        const self = allocator.create(Application) catch @panic("alloc");
        self.* = .{
            .cmds = Channel(AppCmd).init(allocator, 64),
            .thread = undefined,
        };
        const setup = SetupMode.start(self);
        self.thread = std.Thread.spawn(.{}, Application.run, .{ self, SubActor{ .setup = setup } }) catch @panic("spawn");
        return self;
    }

    fn run(self: *Application, initial: SubActor) void {
        var current = initial;

        while (self.cmds.recv()) |cmd| {
            switch (cmd) {
                .get_state => |reply| {
                    reply.send(current);
                },
                .set_state => |new_state| {
                    // Stop the old sub-actor.
                    stopSubActor(current);
                    current = new_state;
                },
            }
        }

        // Cleanup on shutdown.
        stopSubActor(current);
    }

    fn getState(self: *Application) SubActor {
        var reply = Channel(SubActor).init(allocator, 1);
        defer reply.deinit();
        self.cmds.send(.{ .get_state = &reply });
        return reply.recv() orelse .{ .err = .{ .message = "coordinator gone" } };
    }

    // Fire-and-forget: no reply channel, no blocking.
    // This prevents the deadlock where a sub-actor synchronously waits for
    // SetState while the coordinator waits for the sub-actor to Stop.
    fn setState(self: *Application, new_state: SubActor) void {
        self.cmds.send(.{ .set_state = new_state });
    }

    fn stop(self: *Application) void {
        self.cmds.close();
        self.thread.join();
        self.cmds.deinit();
        allocator.destroy(self);
    }

    fn stopSubActor(sub: SubActor) void {
        switch (sub) {
            .setup => |s| s.stop(),
            .running => |r| r.stop(),
            .err => {},
        }
    }
};

// ============================================================================
// Demo
// ============================================================================

pub fn main() !void {
    // Start in SetupMode.
    const app = Application.startWithSetup();
    defer app.stop();

    // Walk through the setup wizard.
    for (0..5) |_| {
        const state = app.getState();
        switch (state) {
            .setup => |s| {
                const step = s.getStep();
                print("[Setup] On step {d}\n", .{step});
                s.advance();
                // Give the coordinator a moment to process fire-and-forget.
                std.Thread.sleep(50_000_000);
            },
            .running => |r| {
                const status = r.getStatus();
                print("[Running] config={s}, uptime={d}ms\n", .{ status.config, status.uptime_ms });
            },
            .err => |e| {
                print("[Error] {s}\n", .{e.message});
            },
        }
    }

    // Demonstrate error state.
    print("\n--- Triggering error state ---\n", .{});
    app.setState(.{ .err = .{ .message = "everything is on fire" } });
    std.Thread.sleep(50_000_000);

    const state = app.getState();
    switch (state) {
        .err => |e| {
            print("[ErrorMode] Parked with: {s}\n", .{e.message});
        },
        else => {
            print("[Unexpected] Not in error state\n", .{});
        },
    }
}
