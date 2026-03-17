// Example 02: Request-Response Actor -- Key-Value Store
//
// A more realistic actor: an in-memory key-value store with Set, Get, Delete,
// and Keys operations. Demonstrates:
//   - Multiple payload fields on the command struct
//   - Returning copies of data (not references to actor-owned state)
//   - Error handling within the actor (key not found)
//   - Reply channel carrying a tagged union for type-safe results
//
// Build & run:
//   odin run 02_request_response
//   odin build 02_request_response -out:build/02 && ./build/02

package main

import "core:fmt"
import "core:sync/chan"
import "core:thread"

// ---------------------------------------------------------------------------
// Result types -- the reply channel carries a tagged union
// ---------------------------------------------------------------------------

KV_Error :: enum {
	None,
	Key_Not_Found,
}

KV_Result :: union {
	string,              // for Get
	[dynamic]string,     // for Keys
	KV_Error,            // for Set, Delete (ack or error)
}

// ---------------------------------------------------------------------------
// Command tags and command struct
// ---------------------------------------------------------------------------

Command_Tag :: enum {
	Set,
	Get,
	Delete,
	Keys,
}

Command :: struct {
	tag:   Command_Tag,
	key:   string,
	value: string,
	reply: chan.Chan(KV_Result),
}

// ---------------------------------------------------------------------------
// KV Store actor
// ---------------------------------------------------------------------------

KV_Store :: struct {
	commands: chan.Chan(Command),
}

kv_init :: proc(s: ^KV_Store, buffer_size: int = 64) {
	s.commands = chan.create(chan.Chan(Command), buffer_size, context.allocator) or_else panic("failed to create command channel")
}

kv_destroy :: proc(s: ^KV_Store) {
	chan.destroy(s.commands)
}

// Dispatch thread -- owns all mutable state as local variables.
kv_run :: proc(s: ^KV_Store) {
	data: map[string]string
	defer delete(data)

	for {
		cmd, ok := chan.recv(s.commands)
		if !ok { break }

		switch cmd.tag {
		case .Set:
			data[cmd.key] = cmd.value
			chan.send(cmd.reply, KV_Result(KV_Error.None))

		case .Get:
			v, found := data[cmd.key]
			if found {
				chan.send(cmd.reply, KV_Result(v))
			} else {
				chan.send(cmd.reply, KV_Result(KV_Error.Key_Not_Found))
			}

		case .Delete:
			delete_key(&data, cmd.key)
			chan.send(cmd.reply, KV_Result(KV_Error.None))

		case .Keys:
			keys := make([dynamic]string, 0, len(data))
			for k in data {
				append(&keys, k)
			}
			chan.send(cmd.reply, KV_Result(keys))
		}
	}
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

kv_set :: proc(s: ^KV_Store, key, value: string) -> KV_Error {
	reply := chan.create(chan.Chan(KV_Result), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Command{tag = .Set, key = key, value = value, reply = reply})
	result, _ := chan.recv(reply)
	return result.(KV_Error)
}

kv_get :: proc(s: ^KV_Store, key: string) -> (string, KV_Error) {
	reply := chan.create(chan.Chan(KV_Result), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Command{tag = .Get, key = key, reply = reply})
	result, _ := chan.recv(reply)
	switch r in result {
	case string:
		return r, .None
	case KV_Error:
		return "", r
	case [dynamic]string:
		return "", .None // unreachable
	}
	return "", .None
}

kv_delete :: proc(s: ^KV_Store, key: string) -> KV_Error {
	reply := chan.create(chan.Chan(KV_Result), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Command{tag = .Delete, key = key, reply = reply})
	result, _ := chan.recv(reply)
	return result.(KV_Error)
}

kv_keys :: proc(s: ^KV_Store) -> [dynamic]string {
	reply := chan.create(chan.Chan(KV_Result), 1, context.allocator) or_else panic("reply chan")
	defer chan.destroy(reply)

	chan.send(s.commands, Command{tag = .Keys, reply = reply})
	result, _ := chan.recv(reply)
	return result.([dynamic]string)
}

kv_stop :: proc(s: ^KV_Store) {
	chan.close(s.commands)
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

main :: proc() {
	store: KV_Store
	kv_init(&store, 32)
	defer kv_destroy(&store)

	// Start the dispatch thread.
	dispatch := thread.create_and_start_with_poly_data(&store, kv_run)

	// Set some values from multiple threads.
	Pair :: struct { k, v: string }
	pairs := [?]Pair{
		{"name", "Alice"},
		{"city", "Portland"},
		{"lang", "Odin"},
		{"editor", "Emacs"},
	}

	set_threads: [len(pairs)]^thread.Thread
	pair_ptrs: [len(pairs)]^Pair
	for &p, i in pairs {
		pair_ptrs[i] = &p
	}

	Set_Ctx :: struct {
		store: ^KV_Store,
		pair:  ^Pair,
	}
	set_ctxs: [len(pairs)]Set_Ctx
	for i in 0 ..< len(pairs) {
		set_ctxs[i] = Set_Ctx{store = &store, pair = pair_ptrs[i]}
		set_threads[i] = thread.create_and_start_with_poly_data(&set_ctxs[i], proc(ctx: ^Set_Ctx) {
			err := kv_set(ctx.store, ctx.pair.k, ctx.pair.v)
			if err != .None {
				fmt.printf("set error: %v\n", err)
			}
		})
	}
	for i in 0 ..< len(pairs) {
		thread.join(set_threads[i])
		thread.destroy(set_threads[i])
	}

	// Read them back.
	for p in pairs {
		v, err := kv_get(&store, p.k)
		if err != .None {
			fmt.printf("get %q: error: %v\n", p.k, err)
		} else {
			fmt.printf("%s = %s\n", p.k, v)
		}
	}

	// Try a missing key.
	_, err := kv_get(&store, "nonexistent")
	fmt.printf("missing key error: %v\n", err)

	// Delete and verify.
	kv_delete(&store, "city")
	keys := kv_keys(&store)
	defer delete(keys)
	fmt.printf("keys after delete: %v\n", keys[:])

	// Shut down.
	kv_stop(&store)
	thread.join(dispatch)
	thread.destroy(dispatch)
}
