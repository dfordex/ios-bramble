/* SPDX-License-Identifier: MIT */
#include "metallib.h"
#include <string.h>

static uint16_t rd16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t rd32(const uint8_t *p)
{
    return (uint32_t)rd16(p) | ((uint32_t)rd16(p + 2) << 16);
}

static uint64_t rd64(const uint8_t *p)
{
    return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32);
}

static int region(size_t total, uint64_t offset, uint64_t length)
{
    return offset <= total && length <= total - offset;
}

a5_air_status a5_metallib_open(const void *bytes, size_t size,
                               a5_metallib *out)
{
    if (!bytes || !out)
        return A5_AIR_BAD_ARGUMENT;
    memset(out, 0, sizeof(*out));
    if (size < 0x5c)
        return A5_AIR_BAD_LIBRARY;
    const uint8_t *p = bytes;
    if (memcmp(p, "MTLB", 4) || rd64(p + 0x10) != size)
        return A5_AIR_BAD_LIBRARY;

    const uint64_t records = rd64(p + 0x18);
    const uint64_t records_size = rd64(p + 0x20);
    const uint64_t air = rd64(p + 0x48);
    const uint64_t air_size = rd64(p + 0x50);
    /* MTLB metadata length excludes its leading function count word. */
    if (!region(size, records, 4) ||
        !region(size, records + 4, records_size) ||
        !region(size, air, air_size) ||
        records + 4 + records_size > air ||
        records_size > 16 * 1024 * 1024 || air_size > 128 * 1024 * 1024)
        return A5_AIR_BAD_LIBRARY;
    const uint32_t count = rd32(p + records);
    if (!count || count > 4096 || records_size < (uint64_t)count * 8)
        return A5_AIR_BAD_LIBRARY;
    size_t position = (size_t)records + 4;
    const size_t end = position + (size_t)records_size;
    for (uint32_t i = 0; i < count; ++i) {
        if (!region(end, position, 8))
            return A5_AIR_BAD_LIBRARY;
        const uint32_t record_size = rd32(p + position);
        if (record_size < 8 || !region(end, position, record_size))
            return A5_AIR_BAD_LIBRARY;
        position += record_size;
    }
    if (position != end)
        return A5_AIR_BAD_LIBRARY;
    *out = (a5_metallib){p, size, (size_t)records + 4, end,
                         (size_t)air, (size_t)air_size, count};
    return A5_AIR_OK;
}

a5_air_status a5_metallib_function(const a5_metallib *lib,
                                   uint32_t index, a5_air_function *out)
{
    if (!lib || !out || !lib->bytes)
        return A5_AIR_BAD_ARGUMENT;
    memset(out, 0, sizeof(*out));
    if (index >= lib->function_count)
        return A5_AIR_OUT_OF_RANGE;
    const uint8_t *p = lib->bytes;
    size_t position = lib->records_offset;
    for (uint32_t i = 0; i < index; ++i)
        position += rd32(p + position);
    const size_t record_end = position + rd32(p + position);
    position += 4;
    const uint8_t *name = NULL;
    size_t name_size = 0;
    uint8_t type = 0xff;
    uint64_t offset = 0, blob_size = 0;
    int have_offset = 0, have_size = 0, ended = 0;
    while (position + 4 <= record_end) {
        const uint8_t *tag = p + position;
        position += 4;
        if (!memcmp(tag, "ENDT", 4)) {
            ended = 1;
            break;
        }
        if (position + 2 > record_end)
            return A5_AIR_BAD_FUNCTION;
        const uint16_t length = rd16(p + position);
        position += 2;
        if (!region(record_end, position, length))
            return A5_AIR_BAD_FUNCTION;
        const uint8_t *value = p + position;
        if (!memcmp(tag, "NAME", 4)) {
            if (name || length < 2 || value[length - 1] ||
                memchr(value, 0, length - 1))
                return A5_AIR_BAD_FUNCTION;
            name = value;
            name_size = length - 1;
        } else if (!memcmp(tag, "TYPE", 4)) {
            if (type != 0xff || length != 1 || value[0] > 5)
                return A5_AIR_BAD_FUNCTION;
            type = value[0];
        } else if (!memcmp(tag, "OFFT", 4)) {
            if (have_offset || length != 24)
                return A5_AIR_BAD_FUNCTION;
            offset = rd64(value + 16);
            have_offset = 1;
        } else if (!memcmp(tag, "MDSZ", 4)) {
            if (have_size || length != 8)
                return A5_AIR_BAD_FUNCTION;
            blob_size = rd64(value);
            have_size = 1;
        }
        position += length;
    }
    if (!ended || position != record_end || !name || type == 0xff ||
        !have_offset || !have_size || blob_size < 20 ||
        !region(lib->air_size, offset, blob_size))
        return A5_AIR_BAD_FUNCTION;
    const size_t absolute = lib->air_offset + (size_t)offset;
    const uint8_t *blob = p + absolute;
    /* LLVM bitcode wrapper: magic, version, payload offset/length, CPU type. */
    if (rd32(blob) != 0x0b17c0de ||
        !region(blob_size, rd32(blob + 8), rd32(blob + 12)) ||
        rd32(blob + 12) < 4)
        return A5_AIR_BAD_FUNCTION;
    const uint32_t payload_offset = rd32(blob + 8);
    const uint32_t payload_size = rd32(blob + 12);
    if (payload_offset < 20 ||
        memcmp(blob + payload_offset, "BC\xc0\xde", 4))
        return A5_AIR_BAD_FUNCTION;
    *out = (a5_air_function){(const char *)name, name_size, type,
                             blob + payload_offset, payload_size,
                             absolute, (size_t)blob_size};
    return A5_AIR_OK;
}
