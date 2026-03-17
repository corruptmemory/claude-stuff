// Example 01: Basic Actor -- Counter
//
// The simplest actor: a counter that multiple threads can safely increment
// and read without locks. Demonstrates:
//   - Command tags (enum of operations)
//   - Command struct with tag, payload, and reply channel pointer
//   - The dispatch thread owning all mutable state as local variables
//   - Public functions: create reply channel on stack, send command, recv reply
//   - Shutdown via channel_close on the command channel
//
// Build: gcc -O2 -Wall -o 01 01_basic_actor.c channel.c -lpthread
// Run:   ./01

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include "channel.h"

// --- Command tags ---

enum cmd_tag {
    CMD_INCREMENT,
    CMD_GET,
};

// --- Command struct ---

typedef struct {
    enum cmd_tag tag;
    channel_t *reply;  // caller-allocated, for returning results
} counter_cmd_t;

// --- Actor state (opaque to callers) ---

typedef struct {
    channel_t commands;
    pthread_t thread;
} counter_t;

// --- Dispatch thread ---

static void *counter_run(void *arg) {
    counter_t *c = arg;

    // All mutable state lives here.
    int count = 0;

    void *raw;
    while (channel_recv(&c->commands, &raw) == 0) {
        counter_cmd_t *cmd = raw;
        switch (cmd->tag) {
        case CMD_INCREMENT:
            count++;
            channel_send(cmd->reply, NULL); // ack
            break;
        case CMD_GET: {
            // Send back the count as a void* (intptr_t cast).
            intptr_t val = count;
            channel_send(cmd->reply, (void *)val);
            break;
        }
        }
    }
    return NULL;
}

// --- Lifecycle ---

void counter_init(counter_t *c) {
    channel_init(&c->commands, 64);
    pthread_create(&c->thread, NULL, counter_run, c);
}

void counter_stop(counter_t *c) {
    channel_close(&c->commands);
    pthread_join(c->thread, NULL);
    channel_destroy(&c->commands);
}

// --- Public methods ---

void counter_increment(counter_t *c) {
    channel_t reply;
    channel_init(&reply, 1);

    counter_cmd_t cmd = { .tag = CMD_INCREMENT, .reply = &reply };
    channel_send(&c->commands, &cmd);

    void *unused;
    channel_recv(&reply, &unused);
    channel_destroy(&reply);
}

int counter_get(counter_t *c) {
    channel_t reply;
    channel_init(&reply, 1);

    counter_cmd_t cmd = { .tag = CMD_GET, .reply = &reply };
    channel_send(&c->commands, &cmd);

    void *val;
    channel_recv(&reply, &val);
    channel_destroy(&reply);
    return (int)(intptr_t)val;
}

// --- Worker thread for concurrent increments ---

typedef struct {
    counter_t *ctr;
    int n;
} worker_arg_t;

static void *worker(void *arg) {
    worker_arg_t *w = arg;
    for (int i = 0; i < w->n; i++) {
        counter_increment(w->ctr);
    }
    return NULL;
}

// --- Demo ---

int main(void) {
    counter_t ctr;
    counter_init(&ctr);

    // Spawn 10 threads that each increment 100 times.
    enum { NUM_THREADS = 10, INCREMENTS = 100 };
    pthread_t threads[NUM_THREADS];
    worker_arg_t args[NUM_THREADS];

    for (int i = 0; i < NUM_THREADS; i++) {
        args[i] = (worker_arg_t){ .ctr = &ctr, .n = INCREMENTS };
        pthread_create(&threads[i], NULL, worker, &args[i]);
    }
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    int val = counter_get(&ctr);
    printf("Final count: %d (expected %d)\n", val, NUM_THREADS * INCREMENTS);

    counter_stop(&ctr);
    return 0;
}
