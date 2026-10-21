/* SPDX-License-Identifier: MIT
 * GPU resource operations. Addresses describe one authorized linear mip level,
 * never a physical address or an allocation inferred from a label.
 */
#ifndef A5_RUNTIME_RESOURCE_OPS_H
#define A5_RUNTIME_RESOURCE_OPS_H
#include "runtime_encode.h"
#ifdef __cplusplus
extern "C" {
#endif
enum { A5ResourceCopy=0, A5ResourceGenerateMip=1,
       A5ResourceTexture1D=0, A5ResourceTexture2D=2,
       A5ResourceCopyProfile=500, A5ResourceMipProfile=501 };
typedef struct {
    uint64_t descriptorGPUVA;
    unsigned operation;
    /* gpuVA is the actual level base (allocation GPUVA + validated offset).
     * bytes is this level's rowBytes*height window, not the entire allocation.
     * Copy is bit-preserving, with identical source/destination Metal formats.
     * Mipmap generation uses actual center-scaled bilinear BGRA8 filtering on the GPU. */
    A5RuntimeImage source, destination;
    unsigned sourceType, destinationType;
    unsigned sourceX, sourceY, destinationX, destinationY, width, height;
} A5RuntimeResourceOp;
/* Emits genuine open-source VS -> TILER and FRAGMENT jobs at 0/0x100/0x200.
 * Partial copy first preloads the destination via a real textured TILER job
 * at 0x1800. The ordinary native topology and terminal fences remain in force.
 * Supported format IDs: 10 R8,30 RG8,80 BGRA8,43 BGR5A1,23 R16Uint,25 R16Float,
 * 55 R32Float,105 RG32Float,115 RGBA16Float (copy only except 80).
 * 1D levels require height=1. No CPU pixel rendering or synthetic completion.
 * Output is zeroed on any validation/encoding failure. */
int A5MaliEncodeRuntimeResourceOp(const A5RuntimeResourceOp *op,
                                void *descriptorBytes,size_t descriptorSize);
#ifdef __cplusplus
}
#endif
#endif
