/* SPDX-License-Identifier: MIT */
#ifndef A5_MALI_NATIVE_H
#define A5_MALI_NATIVE_H
#include "A5MaliBridge.h"
#include "../a5xelte-gpu-translation/native_abi.h"
/* Release only terminal, idle pooled upload BOs. Call with the device lock.
 * No active session/current unsubmitted snapshot may be evicted. */
#ifdef __cplusplus
extern "C" {
#endif
kern_return_t A5MaliEvictIdleNativeUpload(A5MaliClient *client);
void A5MaliDiscardNativeUploads(A5MaliClient *client);
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
typedef struct {
    const void *bytes;
    uint32_t length;
} A5MaliNativeUploadPart;
/* Internal immutable draw snapshots. Returns real retained kernel handles and
 * disjoint byte offsets. Bulk writes precede GPU START at the next flush.
 * Unsupported means no batch session: caller uses the legacy upload path. */
kern_return_t A5MaliStageNativeUploads(A5MaliClient *,unsigned count,
    const A5MaliNativeUploadPart *,uint64_t *handles,uint32_t *offsets);
int A5MaliNativeSubmissionMayBeActive(void);
#ifdef __cplusplus
}
#endif
#endif
