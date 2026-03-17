// Example 02: Request-Response Actor -- Key-Value Store
//
// An in-memory key-value store with Set, Get, Delete, and Keys operations.
// Demonstrates:
//   - Multiple payload fields on the command struct
//   - Returning copies of data (not references to actor-owned state)
//   - Error handling within the actor (key not found)
//   - Simple array-based storage (no hash table needed)
//
// Build: gcc -O2 -Wall -o 02 02_request_response.c channel.c -lpthread
// Run:   ./02

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "channel.h"

// --- Command tags ---

enum cmd_tag {
    CMD_SET,
    CMD_GET,
    CMD_DELETE,
    CMD_KEYS,
};

// --- Reply struct for Get (carries value + error flag) ---

typedef struct {
    char *value;   // heap-allocated copy, caller must free; NULL on error
    int   found;
} get_reply_t;

// --- Reply struct for Keys ---

typedef struct {
    char **keys;   // heap-allocated array of heap-allocated strings; caller frees
    int    count;
} keys_reply_t;

// --- Command struct ---

typedef struct {
    enum cmd_tag tag;
    char key[64];
    char value[64];
    channel_t *reply;
} kv_cmd_t;

// --- KV pair for internal storage ---

typedef struct {
    char key[64];
    char value[64];
} kv_pair_t;

// --- Actor state ---

typedef struct {
    channel_t commands;
    pthread_t thread;
} kvstore_t;

// --- Dispatch thread ---

static void *kvstore_run(void *arg) {
    kvstore_t *s = arg;

    // All mutable state lives here.
    kv_pair_t *pairs = NULL;
    int count = 0;
    int capacity = 0;

    void *raw;
    while (channel_recv(&s->commands, &raw) == 0) {
        kv_cmd_t *cmd = raw;
        switch (cmd->tag) {

        case CMD_SET: {
            // Update existing or append.
            int found = 0;
            for (int i = 0; i < count; i++) {
                if (strcmp(pairs[i].key, cmd->key) == 0) {
                    strncpy(pairs[i].value, cmd->value, sizeof(pairs[i].value) - 1);
                    pairs[i].value[sizeof(pairs[i].value) - 1] = '\0';
                    found = 1;
                    break;
                }
            }
            if (!found) {
                if (count == capacity) {
                    capacity = capacity ? capacity * 2 : 8;
                    pairs = realloc(pairs, sizeof(kv_pair_t) * capacity);
                }
                strncpy(pairs[count].key, cmd->key, sizeof(pairs[count].key) - 1);
                pairs[count].key[sizeof(pairs[count].key) - 1] = '\0';
                strncpy(pairs[count].value, cmd->value, sizeof(pairs[count].value) - 1);
                pairs[count].value[sizeof(pairs[count].value) - 1] = '\0';
                count++;
            }
            channel_send(cmd->reply, NULL); // ack
            break;
        }

        case CMD_GET: {
            get_reply_t *r = malloc(sizeof(get_reply_t));
            r->value = NULL;
            r->found = 0;
            for (int i = 0; i < count; i++) {
                if (strcmp(pairs[i].key, cmd->key) == 0) {
                    r->value = strdup(pairs[i].value);
                    r->found = 1;
                    break;
                }
            }
            channel_send(cmd->reply, r);
            break;
        }

        case CMD_DELETE: {
            for (int i = 0; i < count; i++) {
                if (strcmp(pairs[i].key, cmd->key) == 0) {
                    pairs[i] = pairs[count - 1]; // swap-remove
                    count--;
                    break;
                }
            }
            channel_send(cmd->reply, NULL); // ack
            break;
        }

        case CMD_KEYS: {
            keys_reply_t *r = malloc(sizeof(keys_reply_t));
            r->count = count;
            r->keys = malloc(sizeof(char *) * count);
            for (int i = 0; i < count; i++) {
                r->keys[i] = strdup(pairs[i].key);
            }
            channel_send(cmd->reply, r);
            break;
        }
        }
    }

    free(pairs);
    return NULL;
}

// --- Lifecycle ---

void kvstore_init(kvstore_t *s) {
    channel_init(&s->commands, 64);
    pthread_create(&s->thread, NULL, kvstore_run, s);
}

void kvstore_stop(kvstore_t *s) {
    channel_close(&s->commands);
    pthread_join(s->thread, NULL);
    channel_destroy(&s->commands);
}

// --- Public methods ---

void kvstore_set(kvstore_t *s, const char *key, const char *value) {
    channel_t reply;
    channel_init(&reply, 1);

    kv_cmd_t cmd = { .tag = CMD_SET, .reply = &reply };
    strncpy(cmd.key, key, sizeof(cmd.key) - 1);
    cmd.key[sizeof(cmd.key) - 1] = '\0';
    strncpy(cmd.value, value, sizeof(cmd.value) - 1);
    cmd.value[sizeof(cmd.value) - 1] = '\0';

    channel_send(&s->commands, &cmd);
    void *unused;
    channel_recv(&reply, &unused);
    channel_destroy(&reply);
}

// Returns heap-allocated value (caller must free), or NULL if not found.
char *kvstore_get(kvstore_t *s, const char *key) {
    channel_t reply;
    channel_init(&reply, 1);

    kv_cmd_t cmd = { .tag = CMD_GET, .reply = &reply };
    strncpy(cmd.key, key, sizeof(cmd.key) - 1);
    cmd.key[sizeof(cmd.key) - 1] = '\0';

    channel_send(&s->commands, &cmd);
    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);

    get_reply_t *r = raw;
    char *val = r->value; // may be NULL
    free(r);
    return val;
}

void kvstore_delete(kvstore_t *s, const char *key) {
    channel_t reply;
    channel_init(&reply, 1);

    kv_cmd_t cmd = { .tag = CMD_DELETE, .reply = &reply };
    strncpy(cmd.key, key, sizeof(cmd.key) - 1);
    cmd.key[sizeof(cmd.key) - 1] = '\0';

    channel_send(&s->commands, &cmd);
    void *unused;
    channel_recv(&reply, &unused);
    channel_destroy(&reply);
}

// Returns array of heap-allocated strings. Caller must free each string and the array.
// *out_count is set to the number of keys.
char **kvstore_keys(kvstore_t *s, int *out_count) {
    channel_t reply;
    channel_init(&reply, 1);

    kv_cmd_t cmd = { .tag = CMD_KEYS, .reply = &reply };
    channel_send(&s->commands, &cmd);

    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);

    keys_reply_t *r = raw;
    char **keys = r->keys;
    *out_count = r->count;
    free(r);
    return keys;
}

// --- Worker for concurrent sets ---

typedef struct {
    kvstore_t *store;
    const char *key;
    const char *value;
} set_arg_t;

static void *set_worker(void *arg) {
    set_arg_t *a = arg;
    kvstore_set(a->store, a->key, a->value);
    return NULL;
}

// --- Demo ---

int main(void) {
    kvstore_t store;
    kvstore_init(&store);

    // Set some values from multiple threads.
    struct { const char *k, *v; } pairs[] = {
        {"name",   "Alice"},
        {"city",   "Portland"},
        {"lang",   "C"},
        {"editor", "Emacs"},
    };
    enum { N = sizeof(pairs) / sizeof(pairs[0]) };

    pthread_t threads[N];
    set_arg_t args[N];
    for (int i = 0; i < N; i++) {
        args[i] = (set_arg_t){ .store = &store, .key = pairs[i].k, .value = pairs[i].v };
        pthread_create(&threads[i], NULL, set_worker, &args[i]);
    }
    for (int i = 0; i < N; i++) {
        pthread_join(threads[i], NULL);
    }

    // Read them back.
    for (int i = 0; i < N; i++) {
        char *v = kvstore_get(&store, pairs[i].k);
        if (v) {
            printf("%s = %s\n", pairs[i].k, v);
            free(v);
        } else {
            printf("%s: not found\n", pairs[i].k);
        }
    }

    // Try a missing key.
    char *v = kvstore_get(&store, "nonexistent");
    printf("missing key: %s\n", v ? v : "(not found)");
    free(v); // free(NULL) is safe

    // Delete and verify.
    kvstore_delete(&store, "city");
    int nkeys;
    char **keys = kvstore_keys(&store, &nkeys);
    printf("keys after delete (%d):", nkeys);
    for (int i = 0; i < nkeys; i++) {
        printf(" %s", keys[i]);
        free(keys[i]);
    }
    printf("\n");
    free(keys);

    kvstore_stop(&store);
    return 0;
}
