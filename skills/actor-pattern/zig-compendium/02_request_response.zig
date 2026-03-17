// Example 02: Request-Response Actor — Key-Value Store
//
// A more realistic actor: an in-memory key-value store with set, get, delete,
// and keys operations. Demonstrates:
//   - Multiple payload fields on the command union
//   - Returning copies of data (not references to actor-owned state)
//   - Error handling within the actor (key not found)
//   - Tagged union variants with different reply channel types
//
// Build & run:
//   cd zig-compendium && zig build-exe 02_request_response.zig && ./02_request_response

const std = @import("std");
const Channel = @import("channel.zig").Channel;
const print = std.debug.print;

const allocator = std.heap.page_allocator;

// --- Reply types ---

const GetReply = struct {
    value: ?[]const u8, // null means not found
};

const KeysReply = struct {
    keys: [][]const u8, // caller must free
};

// --- Command definition ---

const KVCmd = union(enum) {
    set: struct {
        key: []const u8,
        value: []const u8,
        reply: *Channel(void),
    },
    get: struct {
        key: []const u8,
        reply: *Channel(GetReply),
    },
    delete: struct {
        key: []const u8,
        reply: *Channel(void),
    },
    keys: struct {
        reply: *Channel(KeysReply),
    },
};

// --- Actor: dispatch thread ---

fn kvActor(cmds: *Channel(KVCmd)) void {
    var data = std.StringHashMap([]const u8).init(allocator);
    defer data.deinit();

    while (cmds.recv()) |cmd| {
        switch (cmd) {
            .set => |c| {
                data.put(c.key, c.value) catch {};
                c.reply.send({});
            },
            .get => |c| {
                const val = data.get(c.key);
                c.reply.send(.{ .value = val });
            },
            .delete => |c| {
                _ = data.remove(c.key);
                c.reply.send({});
            },
            .keys => |c| {
                var key_list = std.ArrayList([]const u8).initCapacity(allocator, data.count()) catch unreachable;
                var it = data.keyIterator();
                while (it.next()) |k| {
                    key_list.append(allocator, k.*) catch {};
                }
                c.reply.send(.{ .keys = key_list.toOwnedSlice(allocator) catch &.{} });
            },
        }
    }
}

// --- Convenience functions ---

fn kvSet(cmds: *Channel(KVCmd), key: []const u8, value: []const u8) void {
    var reply = Channel(void).init(allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .set = .{ .key = key, .value = value, .reply = &reply } });
    _ = reply.recv();
}

fn kvGet(cmds: *Channel(KVCmd), key: []const u8) ?[]const u8 {
    var reply = Channel(GetReply).init(allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .get = .{ .key = key, .reply = &reply } });
    const r = reply.recv() orelse return null;
    return r.value;
}

fn kvDelete(cmds: *Channel(KVCmd), key: []const u8) void {
    var reply = Channel(void).init(allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .delete = .{ .key = key, .reply = &reply } });
    _ = reply.recv();
}

fn kvKeys(cmds: *Channel(KVCmd)) [][]const u8 {
    var reply = Channel(KeysReply).init(allocator, 1);
    defer reply.deinit();
    cmds.send(.{ .keys = .{ .reply = &reply } });
    const r = reply.recv() orelse return &.{};
    return r.keys;
}

// --- Demo ---

pub fn main() !void {
    var cmds = Channel(KVCmd).init(allocator, 64);
    defer cmds.deinit();

    const actor = try std.Thread.spawn(.{}, kvActor, .{&cmds});

    // Set values from multiple threads.
    const pairs = [_]struct { k: []const u8, v: []const u8 }{
        .{ .k = "name", .v = "Alice" },
        .{ .k = "city", .v = "Portland" },
        .{ .k = "lang", .v = "Zig" },
        .{ .k = "editor", .v = "Emacs" },
    };

    var workers: [pairs.len]std.Thread = undefined;
    for (&pairs, 0..) |p, i| {
        workers[i] = try std.Thread.spawn(.{}, struct {
            fn run(c: *Channel(KVCmd), key: []const u8, val: []const u8) void {
                kvSet(c, key, val);
            }
        }.run, .{ &cmds, p.k, p.v });
    }
    for (&workers) |*w| w.join();

    // Read them back.
    for (&pairs) |p| {
        if (kvGet(&cmds, p.k)) |v| {
            print("{s} = {s}\n", .{ p.k, v });
        } else {
            print("{s} = (not found)\n", .{p.k});
        }
    }

    // Try a missing key.
    if (kvGet(&cmds, "nonexistent")) |_| {
        print("nonexistent = (unexpected)\n", .{});
    } else {
        print("missing key: \"nonexistent\" not found\n", .{});
    }

    // Delete and list keys.
    kvDelete(&cmds, "city");
    const keys = kvKeys(&cmds);
    defer allocator.free(keys);

    print("keys after delete:", .{});
    for (keys) |k| {
        print(" {s}", .{k});
    }
    print("\n", .{});

    // Shut down.
    cmds.close();
    actor.join();
}
