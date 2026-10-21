/* SPDX-License-Identifier: MIT
 * Privileged experimental T720 native queue. Addresses are selected by the
 * kernel and name only this client's AS1 mappings, never physical memory.
 */
#ifndef A5_MALI_NATIVE_ABI_H
#define A5_MALI_NATIVE_ABI_H
#include <stdint.h>
enum { A5NativeQuerySelector=17, A5NativeSubmitSelector=18,
       A5NativeCapability=32, A5NativeSlots=4, A5NativeJobBytes=0x40000,
       A5NativeJobVA=0x12000000, A5NativeBulkWriteSelector=19,
       A5NativeBulkWriteMax=0x100000, A5NativeBufferMax=0x800000 };
typedef struct { uint32_t version,size,reserved0,reserved1; } A5NativeHeader;
typedef struct {
    A5NativeHeader header;
    uint64_t surfaces[A5NativeSlots], buffers[A5NativeSlots];
} A5NativeQueryRequest;
typedef struct {
    uint64_t token, gpuVA;
    uint32_t bytes,width,height,rowBytes,pixelFormat,usage;
} A5NativeSpan;
typedef struct {
    A5NativeHeader header;
    uint64_t jobVA;
    uint32_t jobBytes, flags; /* flags is the nonzero AS1 mapping epoch */
    A5NativeSpan surfaces[A5NativeSlots], buffers[A5NativeSlots];
} A5NativeQueryResult;
typedef struct {
    A5NativeHeader header;
    uint32_t jobBytes,vertexOffset,tilerOffset,fragmentOffset;
    uint32_t readSurfaces,writeSurfaces,readBuffers,reserved;
    uint32_t profileID,mappingEpoch;
    uint64_t surfaces[A5NativeSlots], buffers[A5NativeSlots];
    /* Exactly jobBytes encoded bytes follow this fixed structure. */
} A5NativeSubmitRequest;
typedef struct {
    A5NativeHeader header; /* size is fixed header + actual chunk length */
    uint64_t handle;
    uint32_t offset,length;
} A5NativeBulkWriteRequest;
typedef struct {
    A5NativeHeader header;
    uint32_t status,reserved;
    uint64_t tilerFence,fragmentFence;
} A5NativeSubmitResult;
#endif
