/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_RUNTIME_CLEAR_H
#define A5_MALI_RUNTIME_CLEAR_H
#include "runtime_encode.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    uint64_t descriptorGPUVA;
    A5RuntimeImage destination;
    double color[4]; /* actual Metal clear RGBA, not prepacked byte pixels */
} A5RuntimeClear;
/* Genuine whole-target fragment-only clear. NativeSubmit profile0 uses
 * vertexOffset=tilerOffset=UINT32_MAX, fragmentOffset=0, terminalfragmentfence.
 * No shader, vertex job or CPU pixel filling is involved. */
int A5MaliEncodeRuntimeClear(const A5RuntimeClear *, void *, size_t);
#ifdef __cplusplus
}
#endif
#endif
