/* SPDX-License-Identifier: MIT
 * Actual concurrent waiter tests over the production storage dependency helper.
 * No device, IOKit transport, GPU tokens, or resource getter is substituted.
 */
#import "A5MaliResourceDependencies.h"
#import <dispatch/dispatch.h>
#include <assert.h>
#include <stdio.h>
@interface ReentrantStorageOwner : NSObject
@property(nonatomic,copy) void (^onDeallocation)(void);
@end
@implementation ReentrantStorageOwner
- (void)dealloc { if(_onDeallocation)_onDeallocation(); }
@end
static A5MaliStorageIdentity *storage(id owner,A5MaliStorageKind kind,uint64_t identity,uint64_t offset,uint64_t length)
{
    A5MaliStorageSpan span=A5MaliMakeStorageSpan(kind,identity,offset,length);
    return [[A5MaliStorageIdentity alloc]initWithOwner:owner spans:&span count:1];
}
static A5MaliResourceUse *use(A5MaliStorageIdentity *storage,A5MaliResourceAccess access)
{ return [[A5MaliResourceUse alloc]initWithStorage:storage access:access]; }
static void mustThrow(void (^block)(void))
{ BOOL threw=NO;@try{block();}@catch(NSException*e){(void)e;threw=YES;}assert(threw); }
static void completed(dispatch_semaphore_t done)
{ assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))); }
static void stillWaiting(dispatch_semaphore_t done)
{ assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC))); }
int main(void)
{
 @autoreleasepool {
    NSObject *owner=[NSObject new],*other=[NSObject new];
    A5MaliStorageIdentity *host=storage(owner,A5MaliStorageHostRange,0,0x1000,256);
    A5MaliStorageIdentity *hostAlias=storage(other,A5MaliStorageHostRange,0,0x1080,256);
    A5MaliStorageIdentity *hostAdjacent=storage(other,A5MaliStorageHostRange,0,0x1100,256);
    assert(A5MaliResourceStoragesAlias(host,hostAlias));
    assert(!A5MaliResourceStoragesAlias(host,hostAdjacent));
    A5MaliStorageIdentity *plane0=storage(owner,A5MaliStorageIOSurface,77,0,256);
    A5MaliStorageIdentity *plane1=storage(other,A5MaliStorageIOSurface,77,256,256);
    A5MaliStorageIdentity *view=storage(other,A5MaliStorageIOSurface,77,128,256);
    assert(!A5MaliResourceStoragesAlias(plane0,plane1));
    assert(A5MaliResourceStoragesAlias(plane0,view)&&A5MaliResourceStoragesAlias(plane1,view));
    assert(!A5MaliResourceStoragesAlias(plane0,storage(other,A5MaliStorageIOSurface,78,0,512)));
    A5MaliStorageSpan projections[]={A5MaliMakeStorageSpan(A5MaliStorageIOSurface,77,0,256),
        A5MaliMakeStorageSpan(A5MaliStorageHostRange,0,0x1000,256)};
    A5MaliStorageIdentity *surfaceWithHost=[[A5MaliStorageIdentity alloc]initWithOwner:owner spans:projections count:2];
    assert(A5MaliResourceStoragesAlias(surfaceWithHost,hostAlias));
    A5MaliStorageIdentity *root=storage(owner,A5MaliStorageAllocation,123,0,1024);
    A5MaliStorageIdentity *rootView=storage(other,A5MaliStorageAllocation,123,512,128);
    assert(A5MaliResourceStoragesAlias(root,rootView));
    assert(!A5MaliResourceStoragesAlias(root,storage(other,A5MaliStorageAllocation,124,0,1024)));
    assert(A5MaliResourceStoragesAlias(root,storage(other,A5MaliStorageAllocation,123,UINT64_MAX-8,32)));
    assert(A5MaliResourceStoragesAlias(host,storage(other,A5MaliStorageHostRange,0,UINT64_MAX-8,32)));
    assert(A5MaliResourceStoragesAlias(root,storage(other,A5MaliStorageUnknown,0,0,0)));
    assert(!A5MaliResourceStoragesAlias(root,storage(other,A5MaliStorageAllocation,123,4,0)));
    A5MaliResourceDependencies *registry=[A5MaliResourceDependencies new];
    assert([registry isCompleteForStorage:host]);
    A5MaliDependencyTicket *read=[registry beginCommand:owner uses:@[use(host,A5MaliResourceAccessRead)]];
    assert(![registry isCompleteForStorage:hostAlias]&&[registry isCompleteForStorage:hostAdjacent]);
    /* CPU read does not wait on a GPU read. */
    [registry waitForStorage:hostAlias access:A5MaliResourceAccessRead];
    A5MaliDependencyTicket *read2=[registry beginCommand:other uses:@[use(hostAlias,A5MaliResourceAccessRead)]];
    [registry waitForDependenciesAndMarkExecuting:read2];
    mustThrow(^{[registry waitForStorage:host access:A5MaliResourceAccessWrite];});
    [registry finishTicket:read2];
    dispatch_semaphore_t entered=dispatch_semaphore_create(0),done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{
        dispatch_semaphore_signal(entered);[registry waitForStorage:hostAlias access:A5MaliResourceAccessWrite];
        dispatch_semaphore_signal(done);
    }});
    completed(entered);stillWaiting(done);[registry finishTicket:read];completed(done);
    assert([registry isCompleteForStorage:host]);
    /* A GPU write depends on an earlier aliasing read, across queue threads. */
    A5MaliDependencyTicket *earlier=[registry beginCommand:owner uses:@[use(host,A5MaliResourceAccessRead)]];
    A5MaliDependencyTicket *later=[registry beginCommand:other uses:@[use(hostAlias,A5MaliResourceAccessWrite)]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{
        dispatch_semaphore_signal(entered);[registry waitForDependenciesAndMarkExecuting:later];
        dispatch_semaphore_signal(done);
    }});
    completed(entered);stillWaiting(done);[registry finishTicket:earlier];completed(done);
    assert(![registry isCompleteForStorage:host]);[registry finishTicket:later];
    /* A terminal ticket publishes completion and releases command/storage owners. */
    __weak id weakCommand,weakOwner;A5MaliDependencyTicket *retained=nil;
    @autoreleasepool {
        NSObject *command=[NSObject new],*allocation=[NSObject new];weakCommand=command;weakOwner=allocation;
        retained=[registry beginCommand:command uses:@[use(storage(allocation,A5MaliStorageAllocation,99,0,16),A5MaliResourceAccessWrite)]];
    }
    assert(weakCommand&&weakOwner);[registry finishTicket:retained];
    assert(!weakCommand&&!weakOwner);[registry finishTicket:retained];
    __block BOOL deallocatorQueried=NO;
    @autoreleasepool {
        ReentrantStorageOwner *allocation=[ReentrantStorageOwner new];
        allocation.onDeallocation=^{deallocatorQueried=[registry isCompleteForStorage:host];};
        retained=[registry beginCommand:[NSObject new] uses:@[use(storage(allocation,A5MaliStorageAllocation,100,0,16),A5MaliResourceAccessWrite)]];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{
        [registry finishTicket:retained];dispatch_semaphore_signal(done);
    }});
    completed(done);assert(deallocatorQueried);
    /* An executing worker cannot deadlock itself through a later transitive use. */
    A5MaliStorageIdentity *second=storage(other,A5MaliStorageAllocation,9,0,16);
    A5MaliDependencyTicket *active=[registry beginCommand:owner uses:@[use(host,A5MaliResourceAccessWrite)]];
    [registry waitForDependenciesAndMarkExecuting:active];
    A5MaliDependencyTicket *indirect=[registry beginCommand:other uses:@[use(host,A5MaliResourceAccessRead),use(second,A5MaliResourceAccessWrite)]];
    mustThrow(^{[registry waitForStorage:second access:A5MaliResourceAccessRead];});
    mustThrow(^{[registry waitForDependenciesAndMarkExecuting:indirect];});
    [registry finishTicket:active];[registry waitForDependenciesAndMarkExecuting:indirect];[registry finishTicket:indirect];
    A5MaliResourceDependencies *foreign=[A5MaliResourceDependencies new];
    mustThrow(^{[foreign finishTicket:active];});
    mustThrow(^{(void)use(host,(A5MaliResourceAccess)(UINT64_C(1)<<40));});
    mustThrow(^{[registry waitForDependenciesAndMarkExecuting:active];});
    assert([registry isCompleteForStorage:host]);
    /* A fault/timeout can leave pages pinned and GPU-visible until reboot.
     * Neither terminal notification nor command release means storage complete. */
    A5MaliResourceDependencies *quarantine=[A5MaliResourceDependencies new];
    A5MaliDependencyTicket *failed=[quarantine beginCommand:owner uses:@[use(host,A5MaliResourceAccessWrite)]];
    A5MaliDependencyTicket *dependent=[quarantine beginCommand:other uses:@[use(hostAlias,A5MaliResourceAccessRead)]];
    __block BOOL dependencyThrew=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{
        dispatch_semaphore_signal(entered);
        @try{[quarantine waitForDependenciesAndMarkExecuting:dependent];}
        @catch(NSException *e){(void)e;dependencyThrew=YES;}
        dispatch_semaphore_signal(done);
    }});
    completed(entered);stillWaiting(done);[quarantine failTicket:failed];completed(done);
    assert(dependencyThrew&&![quarantine isCompleteForStorage:hostAlias]);
    mustThrow(^{[quarantine waitForStorage:hostAlias access:A5MaliResourceAccessRead];});
    mustThrow(^{(void)[quarantine beginCommand:other uses:@[use(hostAlias,A5MaliResourceAccessRead)]];});
    [quarantine finishTicket:failed];[quarantine failTicket:failed];
    assert(![quarantine isCompleteForStorage:host]);
    [quarantine finishTicket:dependent];
    A5MaliDependencyTicket *unrelated=[quarantine beginCommand:other uses:@[use(hostAdjacent,A5MaliResourceAccessWrite)]];
    [quarantine waitForDependenciesAndMarkExecuting:unrelated];[quarantine finishTicket:unrelated];
    assert([quarantine isCompleteForStorage:hostAdjacent]);
    mustThrow(^{[quarantine failTicket:unrelated];});
    __weak id failedCommand,failedOwner;
    @autoreleasepool {
        A5MaliResourceDependencies *lifetimeRegistry=[A5MaliResourceDependencies new];
        A5MaliDependencyTicket *pinned=nil;
        @autoreleasepool {
            NSObject *command=[NSObject new],*allocation=[NSObject new];failedCommand=command;failedOwner=allocation;
            pinned=[lifetimeRegistry beginCommand:command uses:@[use(storage(allocation,A5MaliStorageAllocation,501,0,32),A5MaliResourceAccessRead)]];
        }
        [lifetimeRegistry failTicket:pinned];assert(!failedCommand&&failedOwner);
        [lifetimeRegistry finishTicket:pinned];assert(failedOwner);
        pinned=nil;lifetimeRegistry=nil;
    }
    assert(!failedOwner);
    puts("storage aliases, committed/CPU dependencies, failure quarantine, retention, and self-deadlock tests passed");
 }
 return 0;
}
