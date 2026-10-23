/* SPDX-License-Identifier: MIT
 * Runtime v4 descriptor encoder. All GPU addresses must first be mapped and
 * authorized by the kernel; these structures never contain physical addresses.
 */
#ifndef A5_MALI_RUNTIME_ENCODE_H
#define A5_MALI_RUNTIME_ENCODE_H
#include <stddef.h>
#include <stdint.h>
#include "../../a5mali-metal/A5MaliCompiledRegistry.h"
#ifdef __cplusplus
extern "C" {
#endif
enum { A5RuntimeJobBytes=0x40000, A5RuntimeMaxVertices=256,
       A5RuntimeMaxIndices=1536,
       A5RuntimeVertexOffset=0, A5RuntimeTilerOffset=0x100,
       A5RuntimeFragmentOffset=0x200 };
enum { A5RuntimeOK=0, A5RuntimeInvalid=1, A5RuntimeUnsupported=2,
       A5RuntimeBounds=3 };
enum { A5RuntimeTriangle=3, A5RuntimeTriangleStrip=4 };
enum { A5RuntimeBlendCopy=0, A5RuntimeBlendPremultipliedSourceOver=1 };
typedef struct {
    uint64_t gpuVA;
    uint32_t bytes, offset;
    /* Optional immutable commit-time snapshot of the same allocation. When
     * supplied, required bytes at offset are copied into a bounded job arena,
     * and matching shader bind offsets are rebased to zero. */
    const uint8_t *cpuBytes;
} A5RuntimeBuffer;
typedef struct {
    uint64_t gpuVA;
    uint32_t bytes, width, height, rowBytes, metalPixelFormat;
} A5RuntimeImage;
/* Blur sampler snapshot. Values follow Metal/A5RuntimeSampler: filter0 is
 * nearest,1 linear; address0 is clamp-to-edge. Only normalized, noncompare,
 * one-level clamp sampling is admitted by these authenticated blur profiles.
 * All-zero is the original internal fixture's nearest/clamp contract; public
 * Metal submissions must supply valid=1 with their actual descriptor. */
typedef struct {
    uint32_t valid,minFilter,magFilter,mipFilter;
    uint32_t sAddressMode,tAddressMode,rAddressMode;
    uint32_t normalizedCoordinates,maxAnisotropy,compareEnabled;
    float lodMinClamp,lodMaxClamp;
} A5RuntimeBlurSampler;
int A5MaliRuntimeBlurSamplerSupported(const A5RuntimeBlurSampler *);
typedef struct {
    const A5MaliCompiledProfile *profile;
    uint64_t descriptorGPUVA;
    A5RuntimeImage source, destination;
    A5RuntimeBlurSampler sourceSampler;
    /* Optional mapped RT1 backing for profile100's inactive BGRA8 output.
     * Its authenticated write mask is zero: it is retained/validated, never
     * emitted as an SFBD writeback or advertised as general MRT support. */
    A5RuntimeImage inactiveColor1;
    uint32_t hasInactiveColor1;
    /* The application bindings, indexed by the ORIGINAL Metal slot number.
     * offset is the actual set*Buffer:offset: value, never folded into GPUVA. */
    A5RuntimeBuffer vertexBuffers[31], fragmentBuffers[31];
    /* Indexed draws use an immutable commit-time index snapshot. offset is
     * the Metal indexBufferOffset in bytes; the encoder copies the exact span
     * into its mapped job arena and validates each referenced vertex. A GPUVA
     * alone is insufficient because it cannot establish the maximum index. */
    A5RuntimeBuffer indexBuffer;
    uint32_t indexCount, indexSize; /* 0/0 nonindexed, or 2/4 bytes per index */
    uint32_t vertexStart, vertexCount, primitive, blend;
    uint32_t scissorX, scissorY, scissorWidth, scissorHeight;
    double viewportX, viewportY, viewportWidth, viewportHeight,
           viewportNear, viewportFar;
} A5RuntimeDraw;
/* On failure clears output so a caller cannot submit a partly encoded job.
 * Supports authenticated, unspecialized blur profiles: dynamic viewport uses
 * UBO0 scale@512/offset@528; legacy fixed profiles retain their strict gate.
 * Zero base vertex remains validated because it is embedded in the code.
 * No fixtures, CPU pixel loops, clear colors or expected images are used. */
int A5MaliEncodeRuntimeDraw(const A5RuntimeDraw *draw, void *descriptorBytes,
                          size_t descriptorSize);
#ifdef __cplusplus
}
#endif
#endif
