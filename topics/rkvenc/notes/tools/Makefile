# Cross-build the test client against the uapi headers of the rkvenc-7.3 tree.
CC ?= aarch64-linux-gnu-gcc
UAPI ?= $(HOME)/orangepi5/build/wt-rkvenc-7.3/uapi-hdr/include
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter

rkvenc-enc: rkvenc-enc.c
	$(CC) $(CFLAGS) -I$(UAPI) -o $@ $<

clean:
	rm -f rkvenc-enc
