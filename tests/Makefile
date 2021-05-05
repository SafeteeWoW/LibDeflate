# This Makefile builds puff and zdeflate in Unix-like systems
# You need to specify the location of zlib compiled library in
# the environment variable "ZLIB_PATH"

SHELL=/bin/bash

ifneq ($(ZLIB_PATH), $(wildcard $(ZLIB_PATH)))
$(message $(ZLIB_PATH))
endif

CC=gcc
CFLAGS=-O2

all: puff zdeflate

puff: puff.c puff.h pufftest.c
	$(CC) $(CFLAGS) puff.c pufftest.c -o puff

zdeflate: zdeflate.c
	if [[ "$$(uname -s)" == "Darwin" ]]; then                                                            \
		$(CC) $(CFLAGS) zdeflate.c -I $$ZLIB_PATH $$ZLIB_PATH/libz.a -o zdeflate;                        \
	else                                                                                                 \
		$(CC) $(CFLAGS) zdeflate.c -I $$ZLIB_PATH -L $$ZLIB_PATH -Wl,-Bstatic,-lz,-Bdynamic -o zdeflate; \
	fi

clean:
	rm -rf puff puff.o pufftest.o zdeflate.o zdeflate
