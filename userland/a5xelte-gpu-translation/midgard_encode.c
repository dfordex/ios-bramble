/* SPDX-License-Identifier: MIT
 * Fixed-pipeline Midgard v4 lowering for two typed BGRA8 operations.
 * This is suitable for a trusted kernel encoder after AS/BO ownership checks;
 * it is not a Metal shader compiler or an IOUserClient command parser.
 */
#include "midgard_encode.h"

#include <string.h>

#if !defined(__BYTE_ORDER__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "The T720 packed descriptor template is little-endian"
#endif

struct fixture_word {
    uint16_t offset;
    uint32_t value;
};

static const struct fixture_word fixture_words[] = {
#include "t720_fixture_words.inc"
};

static void put32(uint8_t *out, size_t offset, uint32_t value)
{
    memcpy(out + offset, &value, sizeof(value));
}

static void put64(uint8_t *out, size_t offset, uint64_t value)
{
    memcpy(out + offset, &value, sizeof(value));
}

static void put_float(uint8_t *out, size_t offset, float value)
{
    memcpy(out + offset, &value, sizeof(value));
}

static int valid_gpu_va(uint64_t va)
{
    /* Midgard LPAE uses 4 KiB pages in the Exynos7580 port. */
    return va && !(va & 0xfff) && va < (1ULL << 40);
}

static int valid_image(const struct a5_midgard_image *image)
{
    if (!image || !valid_gpu_va(image->gpu_va) ||
        !image->width || image->width > 2048 ||
        !image->height || image->height > 2048 ||
        image->row_bytes < image->width * 4 ||
        image->row_bytes > 8192 ||
        (image->row_bytes & 15) ||
        image->mapped_bytes < (uint64_t)image->row_bytes * image->height ||
        image->mapped_bytes > UINT32_MAX)
        return 0;
    return image->gpu_va + image->mapped_bytes <= (1ULL << 40);
}

static int valid_rect(const struct a5_midgard_rect *r,
    const struct a5_midgard_image *image)
{
    return r && image && r->width && r->height &&
        r->x < image->width && r->y < image->height &&
        r->width <= image->width - r->x &&
        r->height <= image->height - r->y;
}

static int valid_descriptors(void *cpu, size_t bytes, uint64_t va)
{
    return cpu && bytes >= A5_MIDGARD_DESCRIPTOR_BYTES && valid_gpu_va(va) &&
        va + A5_MIDGARD_DESCRIPTOR_BYTES <= (1ULL << 40);
}

static void encode_framebuffer(uint8_t *out, uint64_t desc_va,
    const struct a5_midgard_image *dst, const struct a5_midgard_rect *bounds,
    uint32_t clear_color, int preload)
{
    const size_t fb = 0x100;
    const uint32_t min_xy = (bounds->y << 16) | bounds->x;
    const uint32_t max_xy = ((bounds->y + bounds->height - 1) << 16) |
        (bounds->x + bounds->width - 1);
    put32(out, fb + 4, 31);                 /* no local workgroup storage */
    put32(out, fb + 8 * 4, 0xb84da201u | (preload ? (1u << 30) : 0));
    put32(out, fb + 9 * 4, 0x00141000u);  /* linear BGRA8 writeback */
    put32(out, fb + 10 * 4, min_xy);
    put32(out, fb + 11 * 4, max_xy);
    put64(out, fb + 20 * 4, dst->gpu_va);
    put32(out, fb + 22 * 4, dst->row_bytes);
    if (preload) {
        put64(out, fb + 32 * 4, dst->gpu_va);
        put32(out, fb + 34 * 4, dst->row_bytes);
        put32(out, fb + 35 * 4, dst->row_bytes * dst->height);
    } else {
        for (unsigned i = 0; i < 4; ++i)
            put32(out, fb + (32 + i) * 4, clear_color);
    }
    put64(out, fb + 25 * 8, desc_va + 0x1000);
    put64(out, fb + 26 * 8, desc_va + 0x1200);
    put64(out, fb + 27 * 8, desc_va +
        (preload ? A5_MIDGARD_HEAP_OFFSET : 0x1000));
    put64(out, fb + 28 * 8, desc_va +
        (preload ? A5_MIDGARD_HEAP_OFFSET + A5_MIDGARD_HEAP_BYTES : 0x1000));
    if (preload) {
        const uint32_t bins_x = (dst->width + 1023) / 1024;
        const uint32_t bins_y = (dst->height + 1023) / 1024;
        put32(out, fb + 48 * 4, 0x200 + bins_x * bins_y * 0x200);
        put32(out, fb + 49 * 4, 0x01c7); /* 1024x1024 flat tiles */
    } else {
        put32(out, fb + 48 * 4, 0x204); /* no geometry, 512+4 bytes */
        put32(out, fb + 49 * 4, 0x0fff); /* no hierarchy */
    }
    put32(out, 0x1200, 0xa0000000u);   /* empty polygon-list body */
}

static void encode_fragment_job(uint8_t *out, uint64_t desc_va,
    uint32_t job_index, const struct a5_midgard_rect *bounds)
{
    put32(out, 0x10, (job_index << 16) | 0x13u); /* 64-bit fragment job */
    /* Fragment payload uses inclusive 16x16 tile indices; the SFBD and
     * viewport separately retain exact pixel scissors. */
    put32(out, 0x20, (bounds->x >> 4) | ((bounds->y >> 4) << 16));
    put32(out, 0x24, ((bounds->x + bounds->width - 1) >> 4) |
        (((bounds->y + bounds->height - 1) >> 4) << 16));
    put64(out, 0x28, desc_va + 0x100);
}

static void set_vertices(uint8_t *out, size_t offset,
    const struct a5_midgard_rect *r)
{
    const float x0 = (float)r->x, y0 = (float)r->y;
    const float x1 = (float)(r->x + r->width);
    const float y1 = (float)(r->y + r->height);
    const float xy[8] = {x0, y0, x1, y0, x0, y1, x1, y1};
    for (unsigned vertex = 0; vertex < 4; ++vertex) {
        put_float(out, offset + vertex * 16, xy[vertex * 2]);
        put_float(out, offset + vertex * 16 + 4, xy[vertex * 2 + 1]);
        put_float(out, offset + vertex * 16 + 8, 0.0f);
        put_float(out, offset + vertex * 16 + 12, 1.0f);
    }
}

enum a5_midgard_status a5_midgard_encode_copy(
    void *descriptor_cpu, size_t descriptor_bytes, uint64_t descriptor_va,
    const struct a5_midgard_image *source,
    const struct a5_midgard_rect *source_rect,
    const struct a5_midgard_image *destination,
    const struct a5_midgard_rect *destination_rect)
{
    if (!valid_descriptors(descriptor_cpu, descriptor_bytes, descriptor_va) ||
        !valid_image(source) || !valid_image(destination) ||
        !valid_rect(source_rect, source) ||
        !valid_rect(destination_rect, destination))
        return A5_MIDGARD_INVALID;
    if (source_rect->width != destination_rect->width ||
        source_rect->height != destination_rect->height ||
        (source->gpu_va < destination->gpu_va + destination->mapped_bytes &&
        destination->gpu_va < source->gpu_va + source->mapped_bytes) ||
        (descriptor_va < source->gpu_va + source->mapped_bytes &&
        source->gpu_va < descriptor_va + A5_MIDGARD_DESCRIPTOR_BYTES) ||
        (descriptor_va < destination->gpu_va + destination->mapped_bytes &&
        destination->gpu_va < descriptor_va + A5_MIDGARD_DESCRIPTOR_BYTES))
        return A5_MIDGARD_UNSUPPORTED;

    uint8_t *out = (uint8_t *)descriptor_cpu;
    memset(out, 0, A5_MIDGARD_DESCRIPTOR_BYTES);
    for (size_t i = 0; i < sizeof(fixture_words) / sizeof(fixture_words[0]);
        ++i)
        put32(out, fixture_words[i].offset, fixture_words[i].value);

    /* Relocate the Mesa-generated T720 shader and fixed draw descriptors. */
    static const uint16_t pointer_offsets[] = {
        0x350, 0x360, 0x368, 0x378, 0x390, 0x398, 0x3a0,
        0x3b0, 0x600, 0x740,
    };
    static const uint16_t pointer_targets[] = {
        0x880, 0x740, 0x780, 0x600, 0x820, 0x800, 0x900,
        0x100, 0x505, 0x700,
    };
    for (unsigned i = 0; i < sizeof(pointer_offsets) /
        sizeof(pointer_offsets[0]); ++i)
        put64(out, pointer_offsets[i], descriptor_va + pointer_targets[i]);
    put64(out, 0x820, (descriptor_va + 0x8c0) | 1u);
    put32(out, 0x700, ((source->height - 1) << 16) | (source->width - 1));
    put64(out, 0x720, source->gpu_va);
    put32(out, 0x728, source->row_bytes);
    put32(out, 0x72c, source->row_bytes * source->height);
    set_vertices(out, 0x880, destination_rect);
    set_vertices(out, 0x8c0, source_rect);
    put32(out, 0x91c, ((destination->height - 1) << 16) |
        (destination->width - 1));
    encode_framebuffer(out, descriptor_va, destination, destination_rect,
        0, 1);
    encode_fragment_job(out, descriptor_va, 2, destination_rect);
    return A5_MIDGARD_OK;
}

enum a5_midgard_status a5_midgard_encode_clear(
    void *descriptor_cpu, size_t descriptor_bytes, uint64_t descriptor_va,
    const struct a5_midgard_image *destination,
    const struct a5_midgard_rect *destination_rect, uint32_t bgra8_word)
{
    if (!valid_descriptors(descriptor_cpu, descriptor_bytes, descriptor_va) ||
        !valid_image(destination) ||
        !valid_rect(destination_rect, destination))
        return A5_MIDGARD_INVALID;
    if (descriptor_va < destination->gpu_va + destination->mapped_bytes &&
        destination->gpu_va < descriptor_va + A5_MIDGARD_DESCRIPTOR_BYTES)
        return A5_MIDGARD_UNSUPPORTED;
    uint8_t *out = (uint8_t *)descriptor_cpu;
    memset(out, 0, A5_MIDGARD_DESCRIPTOR_BYTES);
    encode_framebuffer(out, descriptor_va, destination, destination_rect,
        bgra8_word, 0);
    encode_fragment_job(out, descriptor_va, 1, destination_rect);
    return A5_MIDGARD_OK;
}
