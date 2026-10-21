/* SPDX-License-Identifier: MIT */
#ifndef A5XELTE_METALLIB_H
#define A5XELTE_METALLIB_H

#include <stddef.h>
#include <stdint.h>

/* Views borrow the caller's bytes. This parses the library and locates AIR;
 * it does not translate AIR into NIR, Midgard, or a Metal pipeline. */
typedef struct {
    const uint8_t *bytes;
    size_t size;
    size_t records_offset;
    size_t records_end;
    size_t air_offset;
    size_t air_size;
    uint32_t function_count;
} a5_metallib;

typedef struct {
    const char *name;             /* NUL terminated inside input bytes */
    size_t name_length;           /* excludes NUL */
    uint8_t type;                 /* 0 vertex, 1 fragment, 2 kernel; 3-5 opaque */
    const uint8_t *bitcode;       /* LLVM AIR bitcode starts BC C0 DE */
    size_t bitcode_size;
    size_t blob_offset;           /* absolute offset in metallib */
    size_t blob_size;             /* wrapped blob size */
} a5_air_function;

typedef enum {
    A5_AIR_OK = 0,
    A5_AIR_BAD_ARGUMENT,
    A5_AIR_BAD_LIBRARY,
    A5_AIR_BAD_FUNCTION,
    A5_AIR_OUT_OF_RANGE,
} a5_air_status;

a5_air_status a5_metallib_open(const void *bytes, size_t size,
                              a5_metallib *out);
a5_air_status a5_metallib_function(const a5_metallib *library,
                                  uint32_t index, a5_air_function *out);

#endif
