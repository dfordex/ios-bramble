/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_NATIVE_UPLOAD_H
#define A5_MALI_NATIVE_UPLOAD_H
#include "A5MaliNative.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Caller already owns the device transport lock. Upload actual immutable
 * commit bytes to a real kernel allocation, up to8MiB, in bounded bulk calls.
 * Does not map addresses, create descriptors or submit GPU work.
 *
 * On success *handle owns a live allocation. Release ONLY after every ordered
 * pass reached its terminal fence. On failure cleanup is attempted; a nonzero
 * *handle means kernel release failed and ownership remains with the caller.
 * Never drop/pretend-freed that handle while DMA completion is ambiguous. */
kern_return_t A5MaliCreateNativeBuffer(A5MaliClient *client,
    uint32_t bytes, const void *source, uint32_t length, uint64_t *handle);
kern_return_t A5MaliReleaseNativeBuffer(A5MaliClient *client, uint64_t handle);
#ifdef __cplusplus
}
#endif
#endif
