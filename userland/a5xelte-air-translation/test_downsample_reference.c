/* SPDX-License-Identifier: MIT */
#include "downsample_reference.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static float from_bits(uint32_t bits)
{ float result; memcpy(&result, &bits, sizeof(result)); return result; }
static float from_half_bits(uint16_t bits)
{ _Float16 result; memcpy(&result, &bits, sizeof(result)); return (float)result; }

/* Independent float-coordinate nearest sample and half-FMA evaluation of the
 * audited AIR. This verifies the integer oracle against shader arithmetic,
 * including the asymmetric weights, RGB-only EDR, odd stripes and UNORM ties. */
static uint32_t arithmetic_reference(uint32_t x, uint32_t y)
{
    const float offsets[4][2] = {
        {-0.5f/64, -0.5f/64}, {0.5f/64, -0.5f/64},
        {-0.5f/64, 0.5f/64}, {0.5f/64, 0.5f/64},
    };
    const _Float16 weights[4] = {0.125f, 0.125f, 0.25f, 0.5f};
    _Float16 accumulator[4] = {0};
    for (unsigned tap = 0; tap < 4; ++tap) {
        const float u = ((float)x + 0.5f)/32 + offsets[tap][0];
        const float v = ((float)y + 0.5f)/32 + offsets[tap][1];
        int sx = (int)floorf(u * 64), sy = (int)floorf(v * 64);
        if (sx < 0) sx = 0; else if (sx > 63) sx = 63;
        if (sy < 0) sy = 0; else if (sy > 63) sy = 63;
        unsigned channels[4] = {
            (unsigned)(sx / 7) & 1u, (unsigned)(sy / 7) & 1u,
            ((unsigned)(sx / 7) ^ (unsigned)(sy / 7)) & 1u, 1,
        };
        for (unsigned channel = 0; channel < 4; ++channel)
            accumulator[channel] = (_Float16)fmaf((float)channels[channel],
                (float)weights[tap], (float)accumulator[channel]);
    }
    uint32_t result = 0;
    for (unsigned channel = 0; channel < 4; ++channel) {
        _Float16 value = accumulator[channel];
        if (channel < 3) value = (_Float16)(value * (_Float16)0.5f);
        uint32_t unorm = (uint32_t)lrintf((float)value * 255);
        result |= unorm << (channel*8);
    }
    return result;
}
int main(void)
{
    assert(from_bits(A5DownsampleTapPositiveFloat) == 0.5f/64);
    assert(from_bits(A5DownsampleTapNegativeFloat) == -0.5f/64);
    assert(from_bits(A5DownsampleTexmatScaleFloat) == 1.0f/64);
    assert(from_half_bits(A5DownsampleWeight0Half) == 0.125f);
    assert(from_half_bits(A5DownsampleWeight1Half) == 0.125f);
    assert(from_half_bits(A5DownsampleWeight2Half) == 0.25f);
    assert(from_half_bits(A5DownsampleWeight3Half) == 0.5f);
    assert(from_half_bits(A5DownsampleEDRHalf) == 0.5f);
    assert(a5_downsample_source_pixel(0, 0) == 0xff000000u);
    assert(a5_downsample_source_pixel(7, 0) == 0xffff00ffu);
    assert(a5_downsample_source_pixel(0, 7) == 0xffffff00u);
    assert(a5_downsample_source_pixel(7, 7) == 0xff00ffffu);
    const struct { uint32_t x, y, pixel; } probes[] = {
        {0, 0, 0xff000000u}, {3, 0, 0xff500050u},
        {0, 3, 0xff606000u}, {3, 3, 0xff306050u},
        {4, 4, 0xff008080u}, {31, 31, 0xff306050u},
    };
    for (unsigned i = 0; i < sizeof(probes)/sizeof(probes[0]); ++i)
        assert(a5_downsample_expected_pixel(probes[i].x, probes[i].y) == probes[i].pixel);
    uint32_t colors[1024], color_count = 0;
    for (uint32_t y = 0; y < 32; ++y)
        for (uint32_t x = 0; x < 32; ++x) {
            const uint32_t expected = a5_downsample_expected_pixel(x, y);
            assert(expected == arithmetic_reference(x, y));
            assert(a5_downsample_pixel_matches(expected, expected));
            unsigned found = 0;
            while (found < color_count && colors[found] != expected) ++found;
            if (found == color_count) colors[color_count++] = expected;
        }
    assert(color_count == 9);
    assert(a5_downsample_pixel_matches(0xff306051u, 0xff306050u));
    assert(!a5_downsample_pixel_matches(0xff306052u, 0xff306050u));
    assert(!a5_downsample_pixel_matches(0xfe306050u, 0xff306050u));
    puts("downsample reference: 1024 half-FMA/normalized-nearest pixels match; 9 output colors");
    return 0;
}
