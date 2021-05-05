/*
This is a C program supports Deflate/Zlib compression and decompression.
This code is modified from zpipe.c from the source code repository of
the Zlib project. This program is used to test the correctness of LibDeflate.
*/

/* zpipe.c: example of proper use of zlib's inflate() and deflate()
   Not copyrighted -- provided to the public domain
   Version 1.4  11 December 2005  Mark Adler */

/* Version history:
   1.0  30 Oct 2004  First version
   1.1   8 Nov 2004  Add void casting for unused return values
                     Use switch statement for inflate() return values
   1.2   9 Nov 2004  Add assertions to document zlib guarantees
   1.3   6 Apr 2005  Remove incorrect assertion in inf()
   1.4  11 Dec 2005  Add hack to avoid MSDOS end-of-line conversions
                     Avoid some compiler warnings for input and output buffers
 */

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zlib.h"

#if defined(MSDOS) || defined(OS2) || defined(WIN32) || defined(__CYGWIN__) || defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#define SET_BINARY_MODE(file) setmode(fileno(file), O_BINARY)
#else
#define SET_BINARY_MODE(file)
#endif

#define CHUNK 16384
#define EXTRA_BYTE_AFTER_STREAM_ERROR -100

/* Compress from file source to file dest until EOF on source.
   def() returns Z_OK on success, Z_MEM_ERROR if memory could not be
   allocated for processing, Z_STREAM_ERROR if an invalid compression
   level is supplied, Z_VERSION_ERROR if the version of zlib.h and the
   version of the library linked do not match, or Z_ERRNO if there is
   an error reading or writing the files. */
static int def(FILE* source, FILE* dest, int level, int strategy, int isZlib, unsigned char* dictionary, int dictSize) {
  int ret = 0;
  int flush = 0;
  unsigned have = 0;
  z_stream strm = {0};
  unsigned char in[CHUNK] = {0};
  unsigned char out[CHUNK] = {0};

  /* allocate deflate state */
  strm.zalloc = Z_NULL;
  strm.zfree = Z_NULL;
  strm.opaque = Z_NULL;
  ret = deflateInit2(&strm, level, Z_DEFLATED, isZlib ? 15 : -15, 8, strategy);
  if (ret != Z_OK) return ret;
  if (dictionary) deflateSetDictionary(&strm, dictionary, dictSize);

  /* compress until end of file */
  do {
    strm.avail_in = fread(in, 1, CHUNK, source);
    if (ferror(source)) {
      (void)deflateEnd(&strm);
      return Z_ERRNO;
    }
    flush = feof(source) ? Z_FINISH : Z_NO_FLUSH;
    strm.next_in = in;

    /* run deflate() on input until output buffer not full, finish
       compression if all of source has been read in */
    do {
      strm.avail_out = CHUNK;
      strm.next_out = out;
      ret = deflate(&strm, flush);   /* no bad return value */
      assert(ret != Z_STREAM_ERROR); /* state not clobbered */
      have = CHUNK - strm.avail_out;
      if (fwrite(out, 1, have, dest) != have || ferror(dest)) {
        (void)deflateEnd(&strm);
        return Z_ERRNO;
      }
    } while (strm.avail_out == 0);
    assert(strm.avail_in == 0); /* all input will be used */

    /* done when last data in file processed */
  } while (flush != Z_FINISH);
  assert(ret == Z_STREAM_END); /* stream will be complete */

  /* clean up and return */
  (void)deflateEnd(&strm);
  return Z_OK;
}

/* Decompress from file source to file dest until stream ends or EOF.
   inf() returns Z_OK on success, Z_MEM_ERROR if memory could not be
   allocated for processing, Z_DATA_ERROR if the deflate data is
   invalid or incomplete, Z_VERSION_ERROR if the version of zlib.h and
   the version of the library linked do not match, or Z_ERRNO if there
   is an error reading or writing the files. */
static int inf(FILE* source, FILE* dest, int isZlib, unsigned char* dictionary, int dictSize) {
  int ret = 0;
  unsigned have = 0;
  z_stream strm = {0};
  unsigned char in[CHUNK] = {0};
  unsigned char out[CHUNK] = {0};

  /* allocate inflate state */
  strm.zalloc = Z_NULL;
  strm.zfree = Z_NULL;
  strm.opaque = Z_NULL;
  strm.avail_in = 0;
  strm.next_in = Z_NULL;
  ret = inflateInit2(&strm, isZlib ? 15 : -15);
  if (ret != Z_OK) return ret;
  if (dictionary && !isZlib) inflateSetDictionary(&strm, dictionary, dictSize);

  /* decompress until deflate stream ends or end of file */
  do {
    strm.avail_in = fread(in, 1, CHUNK, source);
    if (ferror(source)) {
      (void)inflateEnd(&strm);
      return Z_ERRNO;
    }
    if (strm.avail_in == 0) break;
    strm.next_in = in;

    int set_dictionary_zlib = 0;
    /* run inflate() on input until output buffer not full */
    do {
      set_dictionary_zlib = 0;
      strm.avail_out = CHUNK;
      strm.next_out = out;
      ret = inflate(&strm, Z_NO_FLUSH);
      assert(ret != Z_STREAM_ERROR); /* state not clobbered */
      switch (ret) {
        case Z_NEED_DICT:
          if (!dictionary)
            ret = Z_DATA_ERROR; /* and fall through */
          else {
            ret = inflateSetDictionary(&strm, dictionary, dictSize);
            if (ret == Z_OK) {
              set_dictionary_zlib = 1;
              break;
            }  // LibDeflate: Bad problem practice
          }
        case Z_DATA_ERROR:
        case Z_MEM_ERROR:
          (void)inflateEnd(&strm);
          return ret;
      }
      if (!set_dictionary_zlib) {
        have = CHUNK - strm.avail_out;
        if (fwrite(out, 1, have, dest) != have || ferror(dest)) {
          (void)inflateEnd(&strm);
          return Z_ERRNO;
        }
      }
    } while (strm.avail_out == 0 || set_dictionary_zlib);

    /* done when inflate() says it's done */
  } while (ret != Z_STREAM_END);

  /* clean up and return */
  (void)inflateEnd(&strm);
  if (ret == Z_STREAM_END) {
    int fPos = ftell(source);
    fseek(source, 0, SEEK_END);
    int unprocessed = ftell(source) - fPos + strm.avail_in;
    if (unprocessed > 0) {
      fprintf(stderr, "%d", unprocessed);
    }
    return Z_OK;
  } else
    return Z_DATA_ERROR;
}

/* report a zlib or i/o error */
static void zerr(int ret) {
  fputs("zdeflate: ", stderr);
  switch (ret) {
    case Z_ERRNO:
      if (ferror(stdin)) fputs("error reading stdin\n", stderr);
      if (ferror(stdout)) fputs("error writing stdout\n", stderr);
      break;
    case Z_STREAM_ERROR:
      fputs("invalid compression level\n", stderr);
      break;
    case Z_DATA_ERROR:
      fputs("invalid or incomplete deflate data\n", stderr);
      break;
    case Z_MEM_ERROR:
      fputs("out of memory\n", stderr);
      break;
    case Z_VERSION_ERROR:
      fputs("zlib version mismatch!\n", stderr);
      break;
    case EXTRA_BYTE_AFTER_STREAM_ERROR:
      fputs("Extra bytes after deflate data\n", stderr);
      break;
    default:
      fprintf(stderr, "Unknown zlib error number: %d\n", ret);
  }
}

/* compress or decompress from stdin to stdout */
int main(int argc, char** argv) {
  int ret = 0;

  /* avoid end-of-line conversions */
  SET_BINARY_MODE(stdin);
  SET_BINARY_MODE(stdout);
  SET_BINARY_MODE(stderr);

  int level = Z_DEFAULT_COMPRESSION;
  int strategy = Z_DEFAULT_STRATEGY;
  int isDecompress = 0;
  int isZlib = 0;
  unsigned char* dictionary = 0;
  int dictSize = 0;

  int i = 0;
  for (i = 1; i < argc; ++i) {
    char* arg = argv[i];
    if (strcmp(arg, "-d") == 0)
      isDecompress = 1;
    else if (strcmp(arg, "--zlib") == 0)
      isZlib = 1;
    else if (strcmp(arg, "-0") == 0)
      level = 0;
    else if (strcmp(arg, "-1") == 0)
      level = 1;
    else if (strcmp(arg, "-2") == 0)
      level = 2;
    else if (strcmp(arg, "-3") == 0)
      level = 3;
    else if (strcmp(arg, "-4") == 0)
      level = 4;
    else if (strcmp(arg, "-5") == 0)
      level = 5;
    else if (strcmp(arg, "-6") == 0)
      level = 6;
    else if (strcmp(arg, "-7") == 0)
      level = 7;
    else if (strcmp(arg, "-8") == 0)
      level = 8;
    else if (strcmp(arg, "-9") == 0)
      level = 9;
    else if (strcmp(arg, "--filter") == 0)
      strategy = Z_FILTERED;
    else if (strcmp(arg, "--huffman") == 0)
      strategy = Z_HUFFMAN_ONLY;
    else if (strcmp(arg, "--rle") == 0)
      strategy = Z_RLE;
    else if (strcmp(arg, "--fix") == 0)
      strategy = Z_FIXED;
    else if (strcmp(arg, "--default") == 0)
      strategy = Z_DEFAULT_STRATEGY;
    else if (strcmp(arg, "--dict") == 0) {
      const int max_dict_size = 32768;
      dictionary = (unsigned char*)malloc(max_dict_size + 1);
      i++;
      char* filename = argv[i];
      FILE* file = fopen(filename, "rb");
      if (file) {
        ret = fseek(file, 0, SEEK_END);
        if (ret != 0) {
          fprintf(stderr, "fseek for file %s fails with code %d: %s", filename, ret, strerror(errno));
          ret = 100;
          break;
        }
        dictSize = ftell(file);
        if (dictSize > max_dict_size) {
          fprintf(stderr, "Dictionary file size %d is larger than the max allowed size: %d", dictSize, max_dict_size);
          ret = 101;
          break;
        }
        rewind(file);
        int actual_size = fread(dictionary, 1, dictSize, file);
        if (actual_size != dictSize) {
          fprintf(stderr,
                  "Read file error. Actual bytes read: %d, excepted bytes "
                  "read: %d: %s",
                  actual_size, dictSize, strerror(errno));
          ret = 102;
          break;
        }
        dictionary[dictSize] = 0;
        fclose(file);
      } else {
        fprintf(stderr, "Cant open dictionary file %s", filename);
        ret = 103;
        break;
      }
    } else {
      fputs(
          "zdeflate usage: zdeflate [-d] [--zlib] [-0/-1/.../-9] "
          "[--filter/--huffman/--rle/--fix/--default] "
          "< source > dest\n",
          stderr);
      ret = 104;
      break;
    }
  }
  /* do compression if no arguments */
  if (ret == 0) {
    if (!isDecompress) {
      ret = def(stdin, stdout, level, strategy, isZlib, dictionary, dictSize);
      if (ret != Z_OK) zerr(ret);
    } else {
      ret = inf(stdin, stdout, isZlib, dictionary, dictSize);
      if (ret != Z_OK) zerr(ret);
    }
  }

  free(dictionary);
  return ret;
}
