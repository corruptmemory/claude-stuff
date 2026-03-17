// Example 03: Polling Actor -- Timer-Based Background Work
//
// An actor that combines request-response commands with a background poller.
// The poller uses nanosleep with reset-after-work semantics to avoid the
// cron-stampede problem. Demonstrates:
//   - Poller as a plain function (not a struct)
//   - Poller lifecycle owned by the dispatch thread
//   - Poller sending commands on the actor's command channel
//   - Shutdown: close command channel, poller detects send failure and exits
//
// Build: gcc -O2 -Wall -o 03 03_polling.c channel.c -lpthread
// Run:   ./03

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include "channel.h"

// --- Command tags ---

enum cmd_tag {
    CMD_NEW_READING,
    CMD_LATEST,
    CMD_HISTORY,
};

// --- Command struct ---

typedef struct {
    enum cmd_tag tag;
    double reading;    // payload for CMD_NEW_READING
    channel_t *reply;
} sensor_cmd_t;

// --- Reply for history ---

typedef struct {
    double *values;
    int count;
} history_reply_t;

// --- Poller thread ---

typedef struct {
    channel_t *commands;      // actor's command channel
    double (*read_sensor)(void);
    int interval_ms;
    volatile int *stop_flag;  // set by actor on shutdown
} poller_arg_t;

static void *poller_run(void *arg) {
    poller_arg_t *p = arg;
    struct timespec ts = {
        .tv_sec  = p->interval_ms / 1000,
        .tv_nsec = (p->interval_ms % 1000) * 1000000L,
    };

    while (!*p->stop_flag) {
        double val = p->read_sensor();

        // Build a command on the stack. We need a reply channel so the
        // actor can signal it has processed the reading before we loop.
        channel_t reply;
        channel_init(&reply, 1);

        sensor_cmd_t cmd = {
            .tag = CMD_NEW_READING,
            .reading = val,
            .reply = &reply,
        };

        if (channel_send(p->commands, &cmd) != 0) {
            channel_destroy(&reply);
            break; // command channel closed
        }

        void *unused;
        channel_recv(&reply, &unused);
        channel_destroy(&reply);

        // Sleep AFTER work completes (adaptive interval).
        nanosleep(&ts, NULL);
    }
    return NULL;
}

// --- Actor state ---

typedef struct {
    channel_t commands;
    pthread_t thread;
} sensor_service_t;

// --- Dispatch thread ---

typedef struct {
    sensor_service_t *svc;
    double (*read_sensor)(void);
    int interval_ms;
} run_arg_t;

static void *sensor_run(void *arg) {
    run_arg_t *ra = arg;
    sensor_service_t *s = ra->svc;

    // All mutable state lives here.
    double latest = 0.0;
    double *history = NULL;
    int hist_count = 0;
    int hist_cap = 0;

    // Start the poller. Its lifecycle is owned by this thread.
    volatile int poller_stop = 0;
    poller_arg_t parg = {
        .commands = &s->commands,
        .read_sensor = ra->read_sensor,
        .interval_ms = ra->interval_ms,
        .stop_flag = &poller_stop,
    };
    pthread_t poller_thread;
    pthread_create(&poller_thread, NULL, poller_run, &parg);

    free(ra); // allocated by caller

    void *raw;
    while (channel_recv(&s->commands, &raw) == 0) {
        sensor_cmd_t *cmd = raw;
        switch (cmd->tag) {

        case CMD_NEW_READING:
            latest = cmd->reading;
            if (hist_count == hist_cap) {
                hist_cap = hist_cap ? hist_cap * 2 : 16;
                history = realloc(history, sizeof(double) * hist_cap);
            }
            history[hist_count++] = cmd->reading;
            channel_send(cmd->reply, NULL); // ack
            break;

        case CMD_LATEST: {
            // Pack double into a heap allocation.
            double *val = malloc(sizeof(double));
            *val = latest;
            channel_send(cmd->reply, val);
            break;
        }

        case CMD_HISTORY: {
            history_reply_t *r = malloc(sizeof(history_reply_t));
            r->count = hist_count;
            r->values = malloc(sizeof(double) * hist_count);
            memcpy(r->values, history, sizeof(double) * hist_count);
            channel_send(cmd->reply, r);
            break;
        }
        }
    }

    // Shut down poller.
    poller_stop = 1;
    pthread_join(poller_thread, NULL);

    free(history);
    return NULL;
}

// --- Lifecycle ---

void sensor_init(sensor_service_t *s, double (*read_sensor)(void), int interval_ms) {
    channel_init(&s->commands, 64);
    run_arg_t *ra = malloc(sizeof(run_arg_t));
    ra->svc = s;
    ra->read_sensor = read_sensor;
    ra->interval_ms = interval_ms;
    pthread_create(&s->thread, NULL, sensor_run, ra);
}

void sensor_stop(sensor_service_t *s) {
    channel_close(&s->commands);
    pthread_join(s->thread, NULL);
    channel_destroy(&s->commands);
}

// --- Public methods ---

double sensor_latest(sensor_service_t *s) {
    channel_t reply;
    channel_init(&reply, 1);

    sensor_cmd_t cmd = { .tag = CMD_LATEST, .reply = &reply };
    channel_send(&s->commands, &cmd);

    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);

    double val = *(double *)raw;
    free(raw);
    return val;
}

// Returns heap-allocated array. Caller must free values and the reply struct.
void sensor_history(sensor_service_t *s, double **out_values, int *out_count) {
    channel_t reply;
    channel_init(&reply, 1);

    sensor_cmd_t cmd = { .tag = CMD_HISTORY, .reply = &reply };
    channel_send(&s->commands, &cmd);

    void *raw;
    channel_recv(&reply, &raw);
    channel_destroy(&reply);

    history_reply_t *r = raw;
    *out_values = r->values;
    *out_count = r->count;
    free(r);
}

// --- Demo ---

static double fake_sensor(void) {
    return 20.0 + (double)(rand() % 1000) / 100.0;
}

int main(void) {
    srand(time(NULL));

    sensor_service_t svc;
    sensor_init(&svc, fake_sensor, 200); // poll every 200ms

    // Let the poller collect some readings.
    struct timespec one_sec = { .tv_sec = 1 };
    nanosleep(&one_sec, NULL);

    double latest = sensor_latest(&svc);
    printf("Latest reading: %.2f C\n", latest);

    double *values;
    int count;
    sensor_history(&svc, &values, &count);
    printf("Collected %d readings:\n", count);
    for (int i = 0; i < count; i++) {
        printf("  [%d] %.2f C\n", i, values[i]);
    }
    free(values);

    sensor_stop(&svc);
    return 0;
}
