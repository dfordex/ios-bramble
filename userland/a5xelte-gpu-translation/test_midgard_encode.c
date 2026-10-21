/* SPDX-License-Identifier: MIT */
#include "midgard_encode.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint32_t word(const uint8_t *bytes, size_t offset)
{
    uint32_t value;
    memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

static uint64_t address(const uint8_t *bytes, size_t offset)
{
    uint64_t value;
    memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

static float coordinate(const uint8_t *bytes, size_t offset)
{
    float value;
    memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

static void check_fragment_tiles(const uint8_t *bytes,
    const struct a5_midgard_rect *r)
{
    /* Independent decode of the upstream v4 12-bit X/Y fields. Pixel
     * bounds in the SFBD must not be mistaken for this dispatch range. */
    const uint32_t minimum = word(bytes, 0x20);
    const uint32_t maximum = word(bytes, 0x24);
    assert((minimum & 0xfffu) == r->x / 16);
    assert(((minimum >> 16) & 0xfffu) == r->y / 16);
    assert((maximum & 0xfffu) == (r->x + r->width - 1) / 16);
    assert(((maximum >> 16) & 0xfffu) == (r->y + r->height - 1) / 16);
    assert(!(minimum & 0xf000f000u) && !(maximum & 0xf000f000u));
}

int main(void)
{
    uint8_t descriptor[A5_MIDGARD_DESCRIPTOR_BYTES + 8];
    const struct a5_midgard_image source = {
        0x04000000, 4352ULL * 1920, 1080, 1920, 4352,
    };
    const struct a5_midgard_image destination = {
        0x05000000, 4320ULL * 1920, 1080, 1920, 4320,
    };
    const struct a5_midgard_rect source_rect = {10, 20, 320, 480};
    const struct a5_midgard_rect destination_rect = {30, 40, 320, 480};
    memset(descriptor, 0x5a, sizeof(descriptor));
    assert(a5_midgard_encode_copy(descriptor, A5_MIDGARD_DESCRIPTOR_BYTES,
        0x02000000, &source, &source_rect, &destination, &destination_rect) ==
        A5_MIDGARD_OK);
    for (unsigned i = A5_MIDGARD_DESCRIPTOR_BYTES;
        i < sizeof(descriptor); ++i)
        assert(descriptor[i] == 0x5a);
    assert(word(descriptor, 0x310) == 0x0001100f);
    assert(word(descriptor, 0x500) == 0xc87a9835); /* compiled T720 shader */
    assert(address(descriptor, 0x350) == 0x02000880);
    assert(address(descriptor, 0x820) == 0x020008c1);
    assert(address(descriptor, 0x720) == source.gpu_va);
    assert(word(descriptor, 0x728) == source.row_bytes);
    assert(address(descriptor, 0x150) == destination.gpu_va);
    assert(address(descriptor, 0x180) == destination.gpu_va);
    assert(word(descriptor, 0x120) & (1u << 30)); /* destination preload */
    assert(word(descriptor, 0x128) == (40u << 16 | 30u));
    assert(word(descriptor, 0x12c) == (519u << 16 | 349u));
    assert(coordinate(descriptor, 0x880) == 30.0f);
    assert(coordinate(descriptor, 0x884) == 40.0f);
    assert(coordinate(descriptor, 0x8c0) == 10.0f);
    assert(coordinate(descriptor, 0x8c4) == 20.0f);
    assert(address(descriptor, 0x28) == 0x02000100);
    check_fragment_tiles(descriptor, &destination_rect);
    assert(address(descriptor, 0x1d8) == 0x02002000);
    assert(address(descriptor, 0x1e0) == 0x02003000);
    for (unsigned i = A5_MIDGARD_HEAP_OFFSET;
         i < A5_MIDGARD_HEAP_OFFSET + A5_MIDGARD_HEAP_BYTES; ++i)
        assert(descriptor[i] == 0);

    const struct a5_midgard_rect whole = {0, 0, 1080, 1920};
    assert(a5_midgard_encode_clear(descriptor,
        A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &destination, &whole,
        0x44332211) == A5_MIDGARD_OK);
    assert(word(descriptor, 0x10) == 0x00010013);
    assert(!(word(descriptor, 0x120) & (1u << 30)));
    assert(word(descriptor, 0x180) == 0x44332211);
    assert(word(descriptor, 0x18c) == 0x44332211);
    assert(word(descriptor, 0x128) == 0);
    assert(word(descriptor, 0x12c) == (1919u << 16 | 1079u));
    assert(word(descriptor, 0x1200) == 0xa0000000);
    check_fragment_tiles(descriptor, &whole);
    assert(word(descriptor, 0x24) == (119u << 16 | 67u));
    /* Empty heap is allowed only for the disabled-tiler clear path. */
    assert(address(descriptor, 0x1d8) == address(descriptor, 0x1e0));

    const struct a5_midgard_image small = {
        0x06000000, 64ULL * 16, 16, 16, 64,
    };
    const struct a5_midgard_rect corner = {4, 5, 8, 7};
    assert(a5_midgard_encode_clear(descriptor,
        A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &small, &corner,
        0x11223344) == A5_MIDGARD_OK);
    assert(word(descriptor, 0x128) == (5u << 16 | 4u));
    assert(word(descriptor, 0x12c) == (11u << 16 | 11u));
    assert(word(descriptor, 0x1c0) == 0x204);
    assert(word(descriptor, 0x1c4) == 0xfff);
    check_fragment_tiles(descriptor, &corner);

    const struct a5_midgard_image small_source = {
        0x07000000, 64ULL * 16, 16, 16, 64,
    };
    const struct a5_midgard_rect small_whole = {0, 0, 16, 16};
    assert(a5_midgard_encode_copy(descriptor,
        A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &small_source,
        &small_whole, &small, &small_whole) == A5_MIDGARD_OK);
    assert(word(descriptor, 0x700) == 0x000f000f);
    assert(word(descriptor, 0x728) == 64);
    assert(word(descriptor, 0x72c) == 1024);
    assert(word(descriptor, 0x91c) == 0x000f000f);
    assert(word(descriptor, 0x1c0) == 0x400);
    assert(word(descriptor, 0x1c4) == 0x1c7);
    check_fragment_tiles(descriptor, &small_whole);

    /* Cross both tile boundaries from a nonzero origin, including a
     * two-pixel rectangle spanning tile0/tile1. Neither endpoint may use
     * width/height directly as a tile coordinate. */
    const struct a5_midgard_rect crossings[] = {
        {15, 15, 2, 2}, {16, 31, 17, 2}, {31, 32, 33, 17},
        {1079, 1919, 1, 1},
    };
    for (unsigned i = 0; i < sizeof(crossings) / sizeof(crossings[0]); ++i) {
        assert(a5_midgard_encode_copy(descriptor,
            A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &source,
            &crossings[i], &destination, &crossings[i]) == A5_MIDGARD_OK);
        check_fragment_tiles(descriptor, &crossings[i]);
        assert(a5_midgard_encode_clear(descriptor,
            A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &destination,
            &crossings[i], 0x12345678) == A5_MIDGARD_OK);
        check_fragment_tiles(descriptor, &crossings[i]);
    }
    assert(a5_midgard_encode_copy(descriptor, 0x2000, 0x02000000,
        &source, &source_rect, &destination, &destination_rect) == A5_MIDGARD_INVALID);

    struct a5_midgard_image bad = source;
    bad.row_bytes = 4000;
    assert(a5_midgard_encode_copy(descriptor,
        A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &bad, &source_rect,
        &destination, &destination_rect) == A5_MIDGARD_INVALID);
    bad = source;
    bad.gpu_va = destination.gpu_va;
    assert(a5_midgard_encode_copy(descriptor,
        A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &bad, &source_rect,
        &destination, &destination_rect) == A5_MIDGARD_UNSUPPORTED);
    const struct a5_midgard_rect out_of_bounds = {1079, 0, 2, 1};
    assert(a5_midgard_encode_copy(descriptor,
        A5_MIDGARD_DESCRIPTOR_BYTES, 0x02000000, &source, &out_of_bounds,
        &destination, &destination_rect) == A5_MIDGARD_INVALID);
    puts("typed Midgard descriptor encoding: PASS");
    return 0;
}
