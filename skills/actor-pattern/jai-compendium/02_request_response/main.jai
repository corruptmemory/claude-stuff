// Example 02: Request-Response Actor — Key-Value Store
//
// A more realistic actor: an in-memory key-value store with set, get, delete,
// and keys operations. Demonstrates:
//   - Multiple payload fields on the command struct
//   - Returning copies of data (not references to actor-owned state)
//   - Error signaling via ok flag
//   - A generic send_receive helper
//
// Build & run:  ~/jai/jai/bin/jai-linux first.jai - 02

// ---------------------------------------------------------------------------
// Command protocol
// ---------------------------------------------------------------------------

Command_Tag :: enum {
    SET;
    GET;
    DELETE;
    KEYS;
}

Command :: struct {
    tag:   Command_Tag;

    // Payload (used depending on tag)
    key:   string;
    value: string;

    // Result exchange — pointers to caller's stack
    result_string: *string;
    result_keys:   *[..] string;
    result_ok:     *bool;
    done:          *Channel(bool);
}

// ---------------------------------------------------------------------------
// Actor
// ---------------------------------------------------------------------------

KVStore :: struct {
    commands: Channel(Command);
    thread:   Thread;
}

init_kvstore :: (store: *KVStore) {
    init(*store.commands, 64);
    thread_init(*store.thread, kvstore_run);
    store.thread.data = store;
    thread_start(*store.thread);
}

destroy_kvstore :: (store: *KVStore) {
    close(*store.commands);
    thread_is_done(*store.thread, -1);
    thread_deinit(*store.thread);
    destroy(*store.commands);
}

// ---------------------------------------------------------------------------
// Dispatch thread
// ---------------------------------------------------------------------------

kvstore_run :: (thread: *Thread) -> s64 {
    store := cast(*KVStore) thread.data;

    // --- All mutable state lives here ---
    data: Table(string, string);
    init(*data, 32);

    while true {
        cmd, ok := receive(*store.commands);
        if !ok break;

        if cmd.tag == {
            case .SET;
                table_set(*data, copy_string(cmd.key), copy_string(cmd.value));

            case .GET;
                found, val := table_find(*data, cmd.key);
                if found {
                    cmd.result_string.* = copy_string(val);
                    cmd.result_ok.* = true;
                } else {
                    cmd.result_ok.* = false;
                }

            case .DELETE;
                table_remove(*data, cmd.key);

            case .KEYS;
                for data {
                    array_add(cmd.result_keys, copy_string(it_index));
                }
        }

        send(cmd.done, true);
    }

    deinit(*data);
    return 0;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

kvstore_set :: (store: *KVStore, key: string, value: string) {
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*store.commands, Command.{tag = .SET, key = key, value = value, done = *done});
    receive(*done);
}

kvstore_get :: (store: *KVStore, key: string) -> (value: string, ok: bool) {
    result: string;
    ok: bool;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*store.commands, Command.{tag = .GET, key = key, result_string = *result, result_ok = *ok, done = *done});
    receive(*done);
    return result, ok;
}

kvstore_delete :: (store: *KVStore, key: string) {
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*store.commands, Command.{tag = .DELETE, key = key, done = *done});
    receive(*done);
}

kvstore_keys :: (store: *KVStore) -> [..] string {
    keys: [..] string;
    done: Channel(bool);
    init(*done, 1);
    defer destroy(*done);

    send(*store.commands, Command.{tag = .KEYS, result_keys = *keys, done = *done});
    receive(*done);
    return keys;
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

main :: () {
    store: KVStore;
    init_kvstore(*store);
    defer destroy_kvstore(*store);

    pairs :: Pair.[
        .{"name",   "Alice"},
        .{"city",   "Portland"},
        .{"lang",   "Jai"},
        .{"editor", "Emacs"},
    ];

    // Set values from multiple threads.
    threads: [pairs.count] Thread;
    ctxs:    [pairs.count] Set_Worker_Ctx;
    for i: 0..pairs.count-1 {
        ctxs[i].store = *store;
        ctxs[i].pair = pairs[i];
        thread_init(*threads[i], set_worker);
        threads[i].data = *ctxs[i];
        thread_start(*threads[i]);
    }
    for i: 0..pairs.count-1 {
        thread_is_done(*threads[i], -1);
        thread_deinit(*threads[i]);
    }

    // Read them back.
    for pairs {
        val, ok := kvstore_get(*store, it.k);
        if ok  print("% = %\n", it.k, val);
        else   print("%: not found\n", it.k);
    }

    // Try a missing key.
    _, ok := kvstore_get(*store, "nonexistent");
    print("missing key found: %\n", ok);

    // Delete and verify.
    kvstore_delete(*store, "city");
    keys := kvstore_keys(*store);
    print("keys after delete:");
    for keys print(" %", it);
    print("\n");
}

Pair :: struct { k: string; v: string; }

Set_Worker_Ctx :: struct {
    store: *KVStore;
    pair:  Pair;
}

set_worker :: (thread: *Thread) -> s64 {
    ctx := cast(*Set_Worker_Ctx) thread.data;
    kvstore_set(ctx.store, ctx.pair.k, ctx.pair.v);
    return 0;
}

#import "Basic";
#import "Thread";
#import "Hash_Table";
#import "channel";
