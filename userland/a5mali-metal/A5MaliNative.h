/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_NATIVE_H
#define A5_MALI_NATIVE_H
#include "A5MaliBridge.h"
#include "../a5xelte-gpu-translation/native_abi.h"
#ifdef __cplusplus
extern "C" {
#endif
kern_return_t A5MaliQueryNative(A5MaliClient *,
    const A5NativeQueryRequest *,A5NativeQueryResult *);
kern_return_t A5MaliSubmitNative(A5MaliClient *,
    const A5NativeSubmitRequest *,const void *encodedJobs,A5MaliFence *);
/* Internal worker outcome: validation/query failures did not launch GPU work.
 * After Submit18 begins, only a valid terminal-fence reply proves retirement.
 * Reset once before a command buffer starts on its actual worker thread. */
void A5MaliBeginNativeSubmissionTracking(void);
/* Internal command-buffer preparation: zero fence means queued, never complete.
 * End flushes actual hardware and restores the original transport. */
kern_return_t A5MaliBeginNativeBatch(A5MaliClient *);
kern_return_t A5MaliEndNativeBatch(A5MaliClient *,int commit,A5MaliFence *);
int A5MaliNativeBatchAccepted(A5MaliClient *);
int A5MaliNativeSubmissionMayBeActive(void);
#ifdef __cplusplus
}
#endif
#endif
