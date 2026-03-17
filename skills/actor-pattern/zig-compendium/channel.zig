// channel.zig — Generic bounded channel using mutex + condition variables
//
// Mirrors the design of the Jai channel module: a ring buffer with head/tail
// indices, mutex for synchronization, and two condition variables (one for
// readers, one for writers). Supports close semantics: send is a no-op after
// close, recv returns null when closed and empty.
//
// This file is imported by the example files via @import("channel.zig").

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        head: usize,
        tail: usize,
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        closed: bool,
        allocator: Allocator,

        pub fn init(allocator: Allocator, capacity: usize) Self {
            const items = allocator.alloc(T, capacity) catch @panic("channel: allocation failed");
            return Self{
                .items = items,
                .head = 0,
                .tail = 0,
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .closed = false,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn send(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            defer self.not_empty.signal();

            if (self.closed) return;
            while (!self.closed and (self.tail - self.head == self.items.len)) {
                self.not_full.wait(&self.mutex);
            }
            if (self.closed) return;
            self.items[self.tail % self.items.len] = item;
            self.tail += 1;
        }

        pub fn recv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            defer self.not_full.signal();

            while (self.head == self.tail) {
                if (self.closed) return null;
                self.not_empty.wait(&self.mutex);
            }
            const item = self.items[self.head % self.items.len];
            self.head += 1;
            return item;
        }

        pub fn close(self: *Self) void {
            self.mutex.lock();
            self.closed = true;
            self.mutex.unlock();
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }
    };
}
