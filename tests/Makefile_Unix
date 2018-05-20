# This Makefile builds puff and zdeflate in Unix-like systems
# You need to specify the location of zlib compiled library in
# the environment variable "ZLIB_PATH"

ifneq ($(ZLIB_PATH), $(wildcard $(ZLIB_PATH)))
$(message $(ZLIB_PATH))
endif

CC=gcc

all: puff zdeflate

puff: puff.c puff.h pufftest.c
	$(CC) -O2 puff.c pufftest.c -o puff

zdeflate: zdeflate.c
	$(CC) -O2 zdeflate.c -I $$ZLIB_PATH -L $$ZLIB_PATH -lz -o zdeflate

clean:
	rm -rf puff puff.o pufftest.o zdeflate.o zdeflate