/* SPDX-License-Identifier: MIT */
#import "A5MaliResourceDependencies.h"
#include <limits.h>

enum { A5MaliMaxStorageSpans=64,A5MaliMaxPendingCommands=256,A5MaliMaxUses=4096 };
static void invalid(NSString *reason)
{ [NSException raise:NSInvalidArgumentException format:@"%@",reason]; }
static BOOL validKind(A5MaliStorageKind kind)
{ return kind>=A5MaliStorageUnknown&&kind<=A5MaliStorageAllocation; }
A5MaliStorageSpan A5MaliMakeWholeStorageSpan(A5MaliStorageKind kind,uint64_t identity)
{
    if(!validKind(kind))kind=A5MaliStorageUnknown;
    if((kind==A5MaliStorageIOSurface||kind==A5MaliStorageAllocation)&&!identity)
        kind=A5MaliStorageUnknown;
    return (A5MaliStorageSpan){kind,kind==A5MaliStorageHostRange?0:identity,0,UINT64_MAX,YES};
}
A5MaliStorageSpan A5MaliMakeStorageSpan(A5MaliStorageKind kind,uint64_t identity,
    uint64_t offset,uint64_t length)
{
    if(!validKind(kind)||kind==A5MaliStorageUnknown||
       ((kind==A5MaliStorageIOSurface||kind==A5MaliStorageAllocation)&&!identity))
        return A5MaliMakeWholeStorageSpan(A5MaliStorageUnknown,0);
    if(length>UINT64_MAX-offset)return A5MaliMakeWholeStorageSpan(kind,identity);
    return (A5MaliStorageSpan){kind,kind==A5MaliStorageHostRange?0:identity,offset,length,NO};
}
BOOL A5MaliStorageSpansAlias(A5MaliStorageSpan a,A5MaliStorageSpan b)
{
    if(!validKind(a.kind)||!validKind(b.kind)||a.kind==A5MaliStorageUnknown||b.kind==A5MaliStorageUnknown)
        return YES;
    if(a.kind!=b.kind)return NO;
    if(a.kind!=A5MaliStorageHostRange&&a.identity!=b.identity)return NO;
    /* Accept externally constructed spans conservatively on malformed range. */
    if(a.whole||b.whole||a.length>UINT64_MAX-a.offset||b.length>UINT64_MAX-b.offset)return YES;
    if(!a.length||!b.length)return NO;
    return a.offset<b.offset+b.length&&b.offset<a.offset+a.length;
}
@interface A5MaliStorageIdentity () {
@public
    A5MaliStorageSpan _spans[A5MaliMaxStorageSpans];
    NSUInteger _count;
    id _owner;
}
@end
@implementation A5MaliStorageIdentity
- (instancetype)initWithOwner:(id)owner spans:(const A5MaliStorageSpan *)spans count:(NSUInteger)count
{
    if(!owner||!count||count>A5MaliMaxStorageSpans||!spans){invalid(@"invalid storage identity set");return nil;}
    if((self=[super init])){
        _owner=owner;_count=count;
        for(NSUInteger i=0;i<count;i++){
            A5MaliStorageSpan s=spans[i];
            _spans[i]=s.whole?A5MaliMakeWholeStorageSpan(s.kind,s.identity):
                A5MaliMakeStorageSpan(s.kind,s.identity,s.offset,s.length);
        }
    }
    return self;
}
@end
BOOL A5MaliResourceStoragesAlias(A5MaliStorageIdentity *a,A5MaliStorageIdentity *b)
{
    if(![a isKindOfClass:A5MaliStorageIdentity.class]||![b isKindOfClass:A5MaliStorageIdentity.class])
        return YES;
    for(NSUInteger i=0;i<a->_count;i++)for(NSUInteger j=0;j<b->_count;j++)
        if(A5MaliStorageSpansAlias(a->_spans[i],b->_spans[j]))return YES;
    return NO;
}
@implementation A5MaliResourceUse
- (instancetype)initWithStorage:(A5MaliStorageIdentity *)storage access:(A5MaliResourceAccess)access
{
    if(![storage isKindOfClass:A5MaliStorageIdentity.class]||!access||(access&~(NSUInteger)3)){
        invalid(@"invalid resource access");return nil;
    }
    if((self=[super init])){_storage=storage;_access=access;}
    return self;
}
@end
@interface A5MaliDependencyTicket ()
@property(nonatomic,readwrite) uint64_t sequence;
@property(nonatomic,strong,nullable) id command;
@property(nonatomic,copy) NSArray<A5MaliResourceUse *> *uses;
@property(nonatomic,copy) NSArray<A5MaliDependencyTicket *> *earlier;
@property(nonatomic,weak) A5MaliResourceDependencies *registry;
@property(nonatomic,strong,nullable) NSThread *executingThread;
@property(nonatomic) BOOL terminal;
@property(nonatomic) BOOL failed;
@end
@implementation A5MaliDependencyTicket
@end
static BOOL accessConflict(A5MaliResourceAccess a,A5MaliResourceAccess b)
{ return !!((a|b)&A5MaliResourceAccessWrite); }
static BOOL usesConflict(NSArray<A5MaliResourceUse *> *a,NSArray<A5MaliResourceUse *> *b)
{
    for(A5MaliResourceUse *x in a)for(A5MaliResourceUse *y in b)
        if(accessConflict(x.access,y.access)&&A5MaliResourceStoragesAlias(x.storage,y.storage))return YES;
    return NO;
}
@implementation A5MaliResourceDependencies {
    NSCondition *_condition;
    NSMutableArray<A5MaliDependencyTicket *> *_pending;
    NSMutableArray<A5MaliDependencyTicket *> *_failed;
    uint64_t _nextSequence;
}
- (instancetype)init
{
    if((self=[super init])){_condition=[NSCondition new];_pending=[NSMutableArray array];_failed=[NSMutableArray array];_nextSequence=1;}
    return self;
}
- (A5MaliDependencyTicket *)beginCommand:(id)command uses:(NSArray<A5MaliResourceUse *> *)uses
{
    if(!command||!uses||uses.count>A5MaliMaxUses){invalid(@"invalid command storage uses");return nil;}
    NSArray *snapshot=[uses copy];
    for(id use in snapshot)if(![use isKindOfClass:A5MaliResourceUse.class]){
        invalid(@"invalid command storage use");return nil;
    }
    [_condition lock];
    @try{
        [self rejectQuarantinedUses:snapshot];
        if(_pending.count+_failed.count>=A5MaliMaxPendingCommands||_nextSequence==UINT64_MAX)
            [NSException raise:NSInternalInconsistencyException format:@"resource dependency capacity exhausted"];
        A5MaliDependencyTicket *ticket=[A5MaliDependencyTicket new];
        ticket.sequence=_nextSequence++;ticket.command=command;ticket.uses=snapshot;ticket.registry=self;
        NSMutableArray *earlier=[NSMutableArray array];
        for(A5MaliDependencyTicket *pending in _pending)
            if(usesConflict(snapshot,pending.uses))[earlier addObject:pending];
        ticket.earlier=earlier;[_pending addObject:ticket];return ticket;
    }@finally{[_condition unlock];}
}
/* Called only with the registry condition held. A failed context may still
 * touch even an input-only allocation; all aliases remain quarantined. */
- (void)rejectQuarantinedUses:(NSArray<A5MaliResourceUse *> *)uses
{
    for(A5MaliDependencyTicket *failed in _failed)
        for(A5MaliResourceUse *a in failed.uses)
            for(A5MaliResourceUse *b in uses)
                if(A5MaliResourceStoragesAlias(a.storage,b.storage))
                    [NSException raise:NSInternalInconsistencyException format:@"storage quarantined after failed GPU work"];
}
- (void)checkTicket:(A5MaliDependencyTicket *)ticket
{
    if(![ticket isKindOfClass:A5MaliDependencyTicket.class]||ticket.registry!=self)
        invalid(@"foreign resource dependency ticket");
}
- (void)waitForDependenciesAndMarkExecuting:(A5MaliDependencyTicket *)ticket
{
    [_condition lock];
    @try{
        [self checkTicket:ticket];
        [self rejectQuarantinedUses:ticket.uses];
        if(ticket.terminal||ticket.executingThread)
            [NSException raise:NSInternalInconsistencyException format:@"dependency ticket cannot execute twice"];
        for(A5MaliDependencyTicket *active in _pending)
            if(active.executingThread==NSThread.currentThread)
                [NSException raise:NSInternalInconsistencyException format:@"nested command execution cannot wait on queued work"];
        for(A5MaliDependencyTicket *earlier in ticket.earlier){
            while(!earlier.terminal){
                if(earlier.executingThread==NSThread.currentThread)
                    [NSException raise:NSInternalInconsistencyException format:@"resource dependency self-wait"];
                [_condition wait];
                [self rejectQuarantinedUses:ticket.uses];
            }
            if(earlier.failed)
                [NSException raise:NSInternalInconsistencyException format:@"earlier GPU dependency failed"];
        }
        [self rejectQuarantinedUses:ticket.uses];
        ticket.earlier=@[];ticket.executingThread=NSThread.currentThread;
    }@finally{[_condition unlock];}
}
- (void)finishTicket:(A5MaliDependencyTicket *)ticket
{
    /* A last owner release may run an IOSurface/no-copy deallocator that uses
     * other locks or queries completion. Keep those releases outside our lock. */
    __attribute__((objc_precise_lifetime)) id retiredCommand=nil;
    __attribute__((objc_precise_lifetime)) NSArray *retiredUses=nil,*retiredEarlier=nil;
    [_condition lock];
    @try{
        [self checkTicket:ticket];if(ticket.terminal)return;
        retiredCommand=ticket.command;retiredUses=ticket.uses;retiredEarlier=ticket.earlier;
        ticket.terminal=YES;ticket.executingThread=nil;ticket.command=nil;
        ticket.uses=@[];ticket.earlier=@[];[_pending removeObjectIdenticalTo:ticket];
        [_condition broadcast];
    }@finally{[_condition unlock];}
}
- (void)failTicket:(A5MaliDependencyTicket *)ticket
{
    __attribute__((objc_precise_lifetime)) id retiredCommand=nil;
    __attribute__((objc_precise_lifetime)) NSArray *retiredEarlier=nil;
    [_condition lock];
    @try{
        [self checkTicket:ticket];if(ticket.failed)return;
        if(ticket.terminal)
            [NSException raise:NSInternalInconsistencyException format:@"completed GPU work cannot become quarantined"];
        retiredCommand=ticket.command;retiredEarlier=ticket.earlier;
        ticket.failed=YES;ticket.terminal=YES;ticket.executingThread=nil;
        ticket.command=nil;ticket.earlier=@[];
        /* Keep ticket.uses: the kernel may still hold the actual GPU pages.
         * Its retained storage owners cannot run no-copy deallocators yet. */
        [_failed addObject:ticket];[_pending removeObjectIdenticalTo:ticket];
        [_condition broadcast];
    }@finally{[_condition unlock];}
}
- (BOOL)isCompleteForStorage:(A5MaliStorageIdentity *)storage
{
    if(!storage){invalid(@"missing resource storage");return NO;}
    [_condition lock];
    @try{
        for(A5MaliDependencyTicket *ticket in _failed)
            for(A5MaliResourceUse *use in ticket.uses)
                if(A5MaliResourceStoragesAlias(storage,use.storage))return NO;
        for(A5MaliDependencyTicket *ticket in _pending)
            for(A5MaliResourceUse *use in ticket.uses)
                if(A5MaliResourceStoragesAlias(storage,use.storage))return NO;
        return YES;
    }@finally{[_condition unlock];}
}
- (void)waitForStorage:(A5MaliStorageIdentity *)storage access:(A5MaliResourceAccess)access
{
    A5MaliResourceUse *requested=[[A5MaliResourceUse alloc]initWithStorage:storage access:access];
    [_condition lock];
    @try{
        [self rejectQuarantinedUses:@[requested]];
        NSMutableArray *snapshot=[NSMutableArray array];
        for(A5MaliDependencyTicket *ticket in _pending)
            if(usesConflict(@[requested],ticket.uses))[snapshot addObject:ticket];
        /* A later ticket can depend transitively on this worker even if its
         * particular requested storage differs. Reject reentrant waits on later
         * work as well as direct self-waits instead of hiding a dependency. */
        for(A5MaliDependencyTicket *active in _pending)
            if(active.executingThread==NSThread.currentThread)
                for(A5MaliDependencyTicket *waited in snapshot)
                    if(!waited.terminal&&waited.sequence>=active.sequence)
                        [NSException raise:NSInternalInconsistencyException format:@"active command cannot wait on itself or later storage work"];
        for(A5MaliDependencyTicket *ticket in snapshot)while(!ticket.terminal){
            if(ticket.executingThread==NSThread.currentThread)
                [NSException raise:NSInternalInconsistencyException format:@"active command cannot wait on its own storage"];
            [_condition wait];
            [self rejectQuarantinedUses:@[requested]];
        }
        [self rejectQuarantinedUses:@[requested]];
    }@finally{[_condition unlock];}
}
@end
