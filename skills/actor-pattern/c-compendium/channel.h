// channel.h -- Bounded, blocking, closable channel for void* items.
// Mirrors the Jai channel module: init, send, recv, close, destroy.
// Thread-safe via pthreads mutex + two condition variables.

#ifndef CHANNEL_H
#define CHANNEL_H

#include <pthread.h>

typedef struct channel {
    void **buf;
    int capacity;
    int head;
    int tail;
    int count;
    int closed;
    pthread_mutex_t mtx;
    pthread_cond_t  not_empty; // signalled when item added or channel closed
    pthread_cond_t  not_full;  // signalled when item removed or channel closed
} channel_t;

// Initialize a channel with the given capacity (must be > 0).
void channel_init(channel_t *ch, int capacity);

// Send an item. Returns 0 on success, -1 if the channel is closed.
// Blocks if the channel is full.
int channel_send(channel_t *ch, void *item);

// Receive an item. Returns 0 on success (item stored in *item),
// -1 if the channel is closed AND empty.
// Blocks if the channel is empty.
int channel_recv(channel_t *ch, void **item);

// Close the channel. Wakes all blocked senders and receivers.
void channel_close(channel_t *ch);

// Destroy the channel (free buffer, destroy mutex/conds).
void channel_destroy(channel_t *ch);

#endif
