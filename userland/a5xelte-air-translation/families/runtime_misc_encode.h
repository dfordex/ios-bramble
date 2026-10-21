/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_RUNTIME_MISC_ENCODE_H
#define A5_MALI_RUNTIME_MISC_ENCODE_H
#include "runtime_encode.h"
#ifdef __cplusplus
extern "C" {
#endif
/* One native pass for an original, authenticated misc pipeline. The caller
 * submits EVERY profile->passes entry in encoded order, retaining every
 * source/destination through its terminal fence. Configured but AIR-unwritten
 * attachment2 is not fabricated, cleared, or silently treated as an output.
 * The caller must independently implement the renderpass load/store actions. */
typedef struct {
    A5RuntimeDraw draw;
    uint32_t passIndex;
    A5RuntimeImage colorAttachments[8];
    A5RuntimeImage fragmentTextures[31];
} A5RuntimeMiscDraw;
/* Large CPU-backed SSBOs must first be uploaded into a real mapped GPU buffer.
 * Copies of actual snapshots are bounded by the64KiB descriptor-owned arena;
 * insufficient space returns A5RuntimeBounds, never truncated/zeroed inputs.
 * Home's two constexpr samplers are the actual translated linear-clamp states;
 * this does not accept arbitrary application sampler specialization. */
int A5MaliEncodeRuntimeMiscPass(const A5RuntimeMiscDraw *, void *, size_t);
#ifdef __cplusplus
}
#endif
#endif
