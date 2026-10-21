/* SPDX-License-Identifier: MIT
 * CPU oracle and input contract for the actual translated QuartzCore
 * downsample_blur_vert_lph / downsample_4_frag_lph private AS0 fixture.
 * This contains mathematical test data, not downloaded shader code.
 * Portable C/C++: no floating point, allocation, libc or Foundation required.
 */
#ifndef A5_DOWNSAMPLE_REFERENCE_H
#define A5_DOWNSAMPLE_REFERENCE_H
#include <stdint.h>

enum {
    A5DownsampleSourceWidth = 64,
    A5DownsampleSourceHeight = 64,
    A5DownsampleDestinationWidth = 32,
    A5DownsampleDestinationHeight = 32,
    A5DownsampleSourceRowBytes = 256,
    A5DownsampleDestinationRowBytes = 128,
    A5DownsampleStripeWidth = 7,
    A5DownsampleStripeHeight = 7,
    /* half weights: 1/8, 1/8, 1/4, 1/2; half EDR scale: 1/2. */
    A5DownsampleWeight0Half = 0x3000,
    A5DownsampleWeight1Half = 0x3000,
    A5DownsampleWeight2Half = 0x3400,
    A5DownsampleWeight3Half = 0x3800,
    A5DownsampleEDRHalf = 0x3800,
    /* normalized offsets: +/-0.5/64 = +/-1/128 in float32. */
    A5DownsampleTapPositiveFloat = 0x3c000000,
    A5DownsampleTexmatScaleFloat = 0x3c800000, /* 1/64 */
    A5DownsampleColorWriteRule = 0x2222,
    A5DownsampleChannelTolerance = 1,
};
#define A5DownsampleTapNegativeFloat UINT32_C(0xbc000000)

/* Coordinates must be inside the fixed source/destination extents above.
 * Source is an opaque, nonconstant BGRA8 checker of odd-width stripes.
 * The odd width ensures many 2x2 tap groups cross stripe boundaries. */
static inline uint32_t
a5_downsample_source_pixel(uint32_t x, uint32_t y)
{
    const uint32_t blue = (x / A5DownsampleStripeWidth) & 1u;
    const uint32_t green = (y / A5DownsampleStripeHeight) & 1u;
    const uint32_t red = blue ^ green;
    return UINT32_C(0xff000000) | (red * 255u << 16) |
        (green * 255u << 8) | blue * 255u;
}

/* Output pixel center (x+.5,y+.5) maps to normalized texture coordinates
 * ((x+.5)/32,(y+.5)/32). Offsets in tap order are (-,-),(+,-),(-,+),(+,+)
 * with magnitude 0.5/64. Nearest normalized sampling therefore reads source
 * texels (2*x,2*y),(2*x+1,2*y),(2*x,2*y+1),(2*x+1,2*y+1).
 * The shader does half FMAs in that order, then multiplies RGB (not alpha)
 * by EDR=.5. All input channels are exactly 0 or 1 and every intermediate
 * is an exact dyadic multiple of 1/16: half rounding loses no information.
 * Alpha is exactly 1. ColorWriteRule0x2222 performs round-to-nearest-even
 * UNORM8 quantization. For numerator0..8, (n*255+8)/16 has the same result:
 * the only tie is n=8 ->127.5->128 (even). */
static inline uint32_t
a5_downsample_expected_pixel(uint32_t x, uint32_t y)
{
    const uint32_t samples[4] = {
        a5_downsample_source_pixel(2u*x, 2u*y),
        a5_downsample_source_pixel(2u*x + 1u, 2u*y),
        a5_downsample_source_pixel(2u*x, 2u*y + 1u),
        a5_downsample_source_pixel(2u*x + 1u, 2u*y + 1u),
    };
    const uint32_t weights[4] = {1, 1, 2, 4}; /* denominator8; EDR doubles it */
    uint32_t result = UINT32_C(0xff000000);
    for (uint32_t channel = 0; channel < 3; ++channel) {
        uint32_t numerator = 0;
        for (uint32_t tap = 0; tap < 4; ++tap)
            numerator += weights[tap] * ((samples[tap] >> (channel*8)) & 1u);
        result |= ((numerator * 255u + 8u) / 16u) << (channel*8);
    }
    return result;
}

static inline int
a5_downsample_pixel_matches(uint32_t actual, uint32_t expected)
{
    /* Alpha is produced exactly and must not be covered by RGB tolerance. */
    if ((actual >> 24) != (expected >> 24)) return 0;
    for (uint32_t channel = 0; channel < 3; ++channel) {
        const uint32_t a = (actual >> (channel*8)) & 255u;
        const uint32_t e = (expected >> (channel*8)) & 255u;
        const uint32_t delta = a > e ? a - e : e - a;
        if (delta > A5DownsampleChannelTolerance) return 0;
    }
    return 1;
}
#endif
