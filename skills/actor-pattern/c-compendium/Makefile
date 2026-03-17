CC      = gcc
CFLAGS  = -O2 -Wall
LDFLAGS = -lpthread

EXAMPLES = 01 02 03 04

all: $(EXAMPLES)

01: 01_basic_actor.c channel.c channel.h
	$(CC) $(CFLAGS) -o $@ 01_basic_actor.c channel.c $(LDFLAGS)

02: 02_request_response.c channel.c channel.h
	$(CC) $(CFLAGS) -o $@ 02_request_response.c channel.c $(LDFLAGS)

03: 03_polling.c channel.c channel.h
	$(CC) $(CFLAGS) -o $@ 03_polling.c channel.c $(LDFLAGS)

04: 04_actor_hierarchy.c channel.c channel.h
	$(CC) $(CFLAGS) -o $@ 04_actor_hierarchy.c channel.c $(LDFLAGS)

clean:
	rm -f $(EXAMPLES)

.PHONY: all clean
