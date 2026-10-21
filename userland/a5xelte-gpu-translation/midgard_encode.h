/* SPDX-License-Identifier: MIT */
#ifndef A5XELTE_MIDGARD_ENCODE_H
#define A5XELTE_MIDGARD_ENCODE_H

#include <stddef.h>
#include <stdint.h>

/* Kernel-owned, pinned and already mapped in the submitting GPU address space.
 * These fields must never be populated directly from an IOUserClient request.
 */
struct a5_midgard_image {
    uint64_t gpu_va;
    uint64_t mapped_bytes;
    uint32_t width;
    uint32_t height;
    uint32_t row_bytes;
};

struct a5_midgard_rect {
    uint32_t x;
    uint32_t y;
    uint32_t width;
    uint32_t height;
};

enum a5_midgard_status {
    A5_MIDGARD_OK = 0,
    A5_MIDGARD_INVALID = 1,
    A5_MIDGARD_UNSUPPORTED = 2,
};

enum {
    A5_MIDGARD_DESCRIPTOR_BYTES = 0x2000,
    A5_MIDGARD_TILER_OFFSET = 0x300,
    A5_MIDGARD_FRAGMENT_OFFSET = 0,
};

/* A complete copy uses the Mesa-generated T720 sample shader, then submits
 * JS1 tiler and JS0 fragment in order. The caller owns cache and fence work.
 * The destination is a separate, bounded BGRA8 resource. */
enum a5_midgard_status a5_midgard_encode_copy(
    void *descriptor_cpu, size_t descriptor_bytes, uint64_t descriptor_va,
    const struct a5_midgard_image *source,
    const struct a5_midgard_rect *source_rect,
    const struct a5_midgard_image *destination,
    const struct a5_midgard_rect *destination_rect);

/* One bounded BGRA8 clear. Submit JS0 fragment only. */
enum a5_midgard_status a5_midgard_encode_clear(
    void *descriptor_cpu, size_t descriptor_bytes, uint64_t descriptor_va,
    const struct a5_midgard_image *destination,
    const struct a5_midgard_rect *destination_rect, uint32_t bgra8_word);

#endif
