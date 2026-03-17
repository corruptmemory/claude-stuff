// Example 04: Actor Hierarchy -- Coordinator with Sub-Actors
//
// A coordinator (application_t) manages sub-actors representing distinct
// operational modes. Demonstrates:
//   - Stoppable interface via function pointers (vtable)
//   - Coordinator that owns one sub-actor at a time
//   - Fire-and-forget set_state (avoids the deadlock trap)
//   - Sub-actor triggering its own replacement
//   - Error state as terminal sub-actor
//   - Type tag on sub-actors for type-switching in main
//
// Build: gcc -O2 -Wall -o 04 04_actor_hierarchy.c channel.c -lpthread
// Run:   ./04

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <time.h>
#include "channel.h"

// ============================================================================
// Stoppable interface (vtable pattern)
// ============================================================================

typedef enum {
    STATE_SETUP,
    STATE_RUNNING,
    STATE_ERROR,
} state_type_t;

typedef struct stoppable {
    state_type_t type;
    void (*stop)(struct stoppable *self);
    void (*wait)(struct stoppable *self);
} stoppable_t;

// Forward declarations.
typedef struct application application_t;
typedef stoppable_t *(*state_builder_t)(application_t *app);

// ============================================================================
// ErrorState -- Terminal State
// ============================================================================

typedef struct {
    stoppable_t base;
    char message[256];
} error_state_t;

static void error_stop(stoppable_t *self) { (void)self; }
static void error_wait(stoppable_t *self) { (void)self; }

static stoppable_t *new_error_state(const char *msg) {
    error_state_t *e = calloc(1, sizeof(error_state_t));
    e->base.type = STATE_ERROR;
    e->base.stop = error_stop;
    e->base.wait = error_wait;
    strncpy(e->message, msg, sizeof(e->message) - 1);
    return &e->base;
}

// ============================================================================
// Coordinator (application_t)
// ============================================================================

enum app_cmd_tag {
    APP_GET_STATE,
    APP_SET_STATE,  // fire-and-forget: no reply channel
};

typedef struct {
    enum app_cmd_tag tag;
    state_builder_t builder;  // for APP_SET_STATE
    channel_t *reply;         // for APP_GET_STATE only
} app_cmd_t;

struct application {
    channel_t commands;
    pthread_t thread;
};

// Forward declarations.
void app_set_state(application_t *a, state_builder_t builder);

static void *app_run(void *arg) {
    application_t *a = arg;
    stoppable_t *current = NULL;

    void *raw;
    while (channel_recv(&a->commands, &raw) == 0) {
        app_cmd_t *cmd = raw;
        switch (cmd->tag) {
        case APP_GET_STATE:
            channel_send(cmd->reply, current);
            break;
        case APP_SET_STATE:
            // Fire-and-forget: stop old, build new.
            if (current) {
                current->stop(current);
                current->wait(current);
            }
            current = cmd->builder(a);
            free(cmd); // was heap-allocated by app_set_state
            break;
        }
    }

    if (current) {
        current->stop(current);
        current->wait(current);
    }
    return NULL;
}

void app_init(application_t *a, state_builder_t initial) {
    channel_init(&a->commands, 64);
    pthread_create(&a->thread, NULL, app_run, a);

    // Send initial builder as a heap-allocated fire-and-forget command.
    app_set_state(a, initial);
}

stoppable_t *app_get_state(application_t *a) {
    channel_t reply;
    channel_init(&reply, 1);

    app_cmd_t cmd = { .tag = APP_GET_STATE, .reply = &reply };
    channel_send(&a->commands, &cmd);

    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);
    return raw;
}

// Fire-and-forget: heap-allocate the command so the caller can return.
void app_set_state(application_t *a, state_builder_t builder) {
    app_cmd_t *cmd = malloc(sizeof(app_cmd_t));
    cmd->tag = APP_SET_STATE;
    cmd->builder = builder;
    cmd->reply = NULL;
    channel_send(&a->commands, cmd);
}

void app_stop(application_t *a) {
    channel_close(&a->commands);
    pthread_join(a->thread, NULL);
    channel_destroy(&a->commands);
}

// ============================================================================
// Sub-Actor: RunningMode
// ============================================================================

enum running_cmd_tag {
    RUNNING_GET_STATUS,
};

typedef struct {
    enum running_cmd_tag tag;
    channel_t *reply;
} running_cmd_t;

typedef struct {
    stoppable_t base;
    channel_t commands;
    pthread_t thread;
    char config[128];
    struct timespec started;
} running_mode_t;

static void *running_run(void *arg) {
    running_mode_t *r = arg;

    void *raw;
    while (channel_recv(&r->commands, &raw) == 0) {
        running_cmd_t *cmd = raw;
        switch (cmd->tag) {
        case RUNNING_GET_STATUS: {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            long ms = (now.tv_sec - r->started.tv_sec) * 1000
                     + (now.tv_nsec - r->started.tv_nsec) / 1000000;
            char *status = malloc(256);
            snprintf(status, 256, "running (config=%s, uptime=%ldms)", r->config, ms);
            channel_send(cmd->reply, status);
            break;
        }
        }
    }
    return NULL;
}

static void running_stop(stoppable_t *self) {
    running_mode_t *r = (running_mode_t *)self;
    channel_close(&r->commands);
}

static void running_wait(stoppable_t *self) {
    running_mode_t *r = (running_mode_t *)self;
    pthread_join(r->thread, NULL);
    channel_destroy(&r->commands);
    // Don't free r here -- caller may still reference it until they're done.
}

static stoppable_t *new_running_mode(application_t *app, const char *config) {
    (void)app;
    running_mode_t *r = calloc(1, sizeof(running_mode_t));
    r->base.type = STATE_RUNNING;
    r->base.stop = running_stop;
    r->base.wait = running_wait;
    strncpy(r->config, config, sizeof(r->config) - 1);
    clock_gettime(CLOCK_MONOTONIC, &r->started);
    channel_init(&r->commands, 64);
    pthread_create(&r->thread, NULL, running_run, r);
    return &r->base;
}

char *running_get_status(running_mode_t *r) {
    channel_t reply;
    channel_init(&reply, 1);

    running_cmd_t cmd = { .tag = RUNNING_GET_STATUS, .reply = &reply };
    channel_send(&r->commands, &cmd);

    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);
    return raw; // caller must free
}

const char *running_config(running_mode_t *r) {
    return r->config; // immutable after construction
}

// ============================================================================
// Sub-Actor: SetupMode
// ============================================================================

enum setup_cmd_tag {
    SETUP_GET_STEP,
    SETUP_ADVANCE,
};

typedef struct {
    enum setup_cmd_tag tag;
    channel_t *reply;
} setup_cmd_t;

typedef struct {
    stoppable_t base;
    application_t *app;
    channel_t commands;
    pthread_t thread;
} setup_mode_t;

// Builder for transition from setup -> running.
// We need a wrapper because state_builder_t takes only (application_t*).
static stoppable_t *build_running_from_setup(application_t *app) {
    return new_running_mode(app, "config-from-step-3");
}

static void *setup_run(void *arg) {
    setup_mode_t *s = arg;

    int step = 1;
    int total_steps = 3;

    void *raw;
    while (channel_recv(&s->commands, &raw) == 0) {
        setup_cmd_t *cmd = raw;
        switch (cmd->tag) {
        case SETUP_GET_STEP: {
            intptr_t val = step;
            channel_send(cmd->reply, (void *)val);
            break;
        }
        case SETUP_ADVANCE:
            if (step < total_steps) {
                step++;
            } else {
                // Trigger transition -- fire-and-forget.
                app_set_state(s->app, build_running_from_setup);
            }
            channel_send(cmd->reply, NULL); // ack
            break;
        }
    }
    return NULL;
}

static void setup_stop(stoppable_t *self) {
    setup_mode_t *s = (setup_mode_t *)self;
    channel_close(&s->commands);
}

static void setup_wait(stoppable_t *self) {
    setup_mode_t *s = (setup_mode_t *)self;
    pthread_join(s->thread, NULL);
    channel_destroy(&s->commands);
}

static stoppable_t *new_setup_mode(application_t *app) {
    setup_mode_t *s = calloc(1, sizeof(setup_mode_t));
    s->base.type = STATE_SETUP;
    s->base.stop = setup_stop;
    s->base.wait = setup_wait;
    s->app = app;
    channel_init(&s->commands, 64);
    pthread_create(&s->thread, NULL, setup_run, s);
    return &s->base;
}

int setup_get_step(setup_mode_t *s) {
    channel_t reply;
    channel_init(&reply, 1);

    setup_cmd_t cmd = { .tag = SETUP_GET_STEP, .reply = &reply };
    channel_send(&s->commands, &cmd);

    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);
    return (int)(intptr_t)raw;
}

void setup_advance(setup_mode_t *s) {
    channel_t reply;
    channel_init(&reply, 1);

    setup_cmd_t cmd = { .tag = SETUP_ADVANCE, .reply = &reply };
    channel_send(&s->commands, &cmd);

    void *unused;
    channel_recv(&reply, &unused);
    channel_destroy(&reply);
}

// ============================================================================
// Demo
// ============================================================================

// Builder for read-only fallback mode.
static stoppable_t *build_readonly_fallback(application_t *app) {
    printf("[Recovery] Falling back to read-only mode\n");
    return new_running_mode(app, "read-only-fallback");
}

// Builder that fails with recovery.
static stoppable_t *build_recoverable_failure(application_t *app) {
    (void)app;
    // Simulate failure: return error state but with a recoverable hint.
    // Since C doesn't have exceptions, we encode recovery as:
    // return NULL to signal failure, then the coordinator tries the fallback.
    // But our coordinator is simpler: state_builder_t always returns a stoppable.
    // So we implement recovery by having the builder itself try the fallback.
    printf("[Builder] Primary database unavailable, trying fallback...\n");
    return build_readonly_fallback(app);
}

// Builder that fails unrecoverably.
static stoppable_t *build_unrecoverable_failure(application_t *app) {
    (void)app;
    printf("[Builder] Everything is on fire, trying recovery...\n");
    printf("[Builder] Recovery also failed\n");
    return new_error_state("recovery also failed");
}

static void msleep(int ms) {
    struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

int main(void) {
    application_t app;
    app_init(&app, new_setup_mode);

    // Walk through the setup wizard.
    for (int i = 0; i < 4; i++) {
        stoppable_t *state = app_get_state(&app);
        switch (state->type) {
        case STATE_SETUP: {
            setup_mode_t *s = (setup_mode_t *)state;
            int step = setup_get_step(s);
            printf("[Setup] On step %d\n", step);
            setup_advance(s);
            // Give the coordinator time to process the fire-and-forget SetState.
            msleep(50);
            break;
        }
        case STATE_RUNNING: {
            running_mode_t *r = (running_mode_t *)state;
            char *status = running_get_status(r);
            printf("[Running] %s\n", status);
            free(status);
            printf("[Running] Config (direct getter): %s\n", running_config(r));
            break;
        }
        case STATE_ERROR: {
            error_state_t *e = (error_state_t *)state;
            printf("[Error] %s\n", e->message);
            break;
        }
        }
    }

    // Demonstrate recoverable error.
    printf("\n--- Triggering recoverable error ---\n");
    app_set_state(&app, build_recoverable_failure);
    msleep(50);

    stoppable_t *state = app_get_state(&app);
    if (state->type == STATE_RUNNING) {
        running_mode_t *r = (running_mode_t *)state;
        char *status = running_get_status(r);
        printf("[After Recovery] %s\n", status);
        free(status);
    }

    // Demonstrate unrecoverable error.
    printf("\n--- Triggering unrecoverable error ---\n");
    app_set_state(&app, build_unrecoverable_failure);
    msleep(50);

    state = app_get_state(&app);
    if (state->type == STATE_ERROR) {
        error_state_t *e = (error_state_t *)state;
        printf("[ErrorApp] Parked with: %s\n", e->message);
    }

    app_stop(&app);
    return 0;
}
