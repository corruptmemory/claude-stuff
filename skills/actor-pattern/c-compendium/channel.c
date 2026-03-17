// channel.c -- Implementation of bounded blocking channel.

#include "channel.h"
#include <stdlib.h>
#include <assert.h>

void channel_init(channel_t *ch, int capacity) {
    assert(capacity > 0);
    ch->buf = malloc(sizeof(void *) * capacity);
    ch->capacity = capacity;
    ch->head = 0;
    ch->tail = 0;
    ch->count = 0;
    ch->closed = 0;
    pthread_mutex_init(&ch->mtx, NULL);
    pthread_cond_init(&ch->not_empty, NULL);
    pthread_cond_init(&ch->not_full, NULL);
}

int channel_send(channel_t *ch, void *item) {
    pthread_mutex_lock(&ch->mtx);
    while (!ch->closed && ch->count == ch->capacity) {
        pthread_cond_wait(&ch->not_full, &ch->mtx);
    }
    if (ch->closed) {
        pthread_mutex_unlock(&ch->mtx);
        return -1;
    }
    ch->buf[ch->tail] = item;
    ch->tail = (ch->tail + 1) % ch->capacity;
    ch->count++;
    pthread_cond_signal(&ch->not_empty);
    pthread_mutex_unlock(&ch->mtx);
    return 0;
}

int channel_recv(channel_t *ch, void **item) {
    pthread_mutex_lock(&ch->mtx);
    while (ch->count == 0 && !ch->closed) {
        pthread_cond_wait(&ch->not_empty, &ch->mtx);
    }
    if (ch->count == 0) {
        // closed and empty
        pthread_mutex_unlock(&ch->mtx);
        return -1;
    }
    *item = ch->buf[ch->head];
    ch->head = (ch->head + 1) % ch->capacity;
    ch->count--;
    pthread_cond_signal(&ch->not_full);
    pthread_mutex_unlock(&ch->mtx);
    return 0;
}

void channel_close(channel_t *ch) {
    pthread_mutex_lock(&ch->mtx);
    ch->closed = 1;
    pthread_cond_broadcast(&ch->not_empty);
    pthread_cond_broadcast(&ch->not_full);
    pthread_mutex_unlock(&ch->mtx);
}

void channel_destroy(channel_t *ch) {
    free(ch->buf);
    ch->buf = NULL;
    pthread_mutex_destroy(&ch->mtx);
    pthread_cond_destroy(&ch->not_empty);
    pthread_cond_destroy(&ch->not_full);
}
