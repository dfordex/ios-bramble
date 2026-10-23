/* SPDX-License-Identifier: MIT
 * Storage identities and committed-work dependencies. No GPU handles, addresses
 * from a command wire, resource getters, or device lock are used here.
 */
#import <Foundation/Foundation.h>
#include <stdint.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint32_t, A5MaliStorageKind) {
    A5MaliStorageUnknown=0,
    A5MaliStorageHostRange=1,
    A5MaliStorageIOSurface=2,
    A5MaliStorageAllocation=3,
};
typedef struct {
    A5MaliStorageKind kind;
    uint64_t identity,offset,length;
    BOOL whole;
} A5MaliStorageSpan;
/* Host ranges use absolute process addresses and identity=0. IOSurface spans
 * use the underlying surface ID and byte offsets across its entire allocation,
 * including plane offsets. Allocation spans use the retained root allocation
 * object's identity. A texture view uses its root allocation/buffer identities,
 * not the view object. Multiple projections catch e.g. IOSurface/host aliases.
 * If complete identity/range extraction is impossible, supply Unknown. */
A5MaliStorageSpan A5MaliMakeStorageSpan(A5MaliStorageKind kind,uint64_t identity,
    uint64_t offset,uint64_t length);
A5MaliStorageSpan A5MaliMakeWholeStorageSpan(A5MaliStorageKind kind,uint64_t identity);
BOOL A5MaliStorageSpansAlias(A5MaliStorageSpan a,A5MaliStorageSpan b);

@interface A5MaliStorageIdentity : NSObject
- (instancetype)initWithOwner:(id)owner spans:(const A5MaliStorageSpan *)spans
    count:(NSUInteger)count;
@end
BOOL A5MaliResourceStoragesAlias(A5MaliStorageIdentity *a,A5MaliStorageIdentity *b);

typedef NS_OPTIONS(NSUInteger,A5MaliResourceAccess) {
    A5MaliResourceAccessRead=1,
    A5MaliResourceAccessWrite=2,
};
@interface A5MaliResourceUse : NSObject
@property(nonatomic,readonly) A5MaliStorageIdentity *storage;
@property(nonatomic,readonly) A5MaliResourceAccess access;
- (instancetype)initWithStorage:(A5MaliStorageIdentity *)storage
    access:(A5MaliResourceAccess)access;
@end

@interface A5MaliDependencyTicket : NSObject
@property(nonatomic,readonly) uint64_t sequence;
@end
@interface A5MaliResourceDependencies : NSObject
/* Publish at commit, before worker dispatch. The strong command reference and
 * storage owners stay alive until finishTicket. Uncommitted encoders are absent.
 * The returned ticket waits only earlier conflicting read/write usages; reads
 * do not depend on other reads. Bounded limits fail closed with an exception. */
- (A5MaliDependencyTicket *)beginCommand:(id)command
    uses:(NSArray<A5MaliResourceUse *> *)uses;
/* Call BEFORE taking the device/transport lock. Does not hold the condition
 * while waiting. Marks the actual worker thread to detect recursive self-waits. */
- (void)waitForDependenciesAndMarkExecuting:(A5MaliDependencyTicket *)ticket;
/* Call on success/error after the terminal fence, before completion callbacks.
 * An exception before dispatch must also finish its published ticket. */
- (void)finishTicket:(A5MaliDependencyTicket *)ticket;
/* Failed GPU submissions may leave kernel-pinned pages visible to the GPU.
 * Quarantine their storage until registry teardown; never report it complete.
 * Releases the command reference but retains all storage owners. Subsequent
 * aliasing commands/waits fail closed, including already-published workers. */
- (void)failTicket:(A5MaliDependencyTicket *)ticket;
/* Resource completion means no overlapping committed access remains. CPU reads
 * wait earlier writes; CPU writes/purge wait reads and writes. Snapshot semantics
 * exclude subsequently committed work. Call outside device and resource locks;
 * CPU access must share the caller's normal resource/commit exclusion protocol.
 * A wait from its own active conflicting worker throws, never pretends done. */
- (BOOL)isCompleteForStorage:(A5MaliStorageIdentity *)storage;
- (void)waitForStorage:(A5MaliStorageIdentity *)storage
    access:(A5MaliResourceAccess)access;
@end
NS_ASSUME_NONNULL_END
