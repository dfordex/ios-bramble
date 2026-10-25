/* SPDX-License-Identifier: MIT */
#import "A5MaliCommandBuffer.h"
#import "A5MaliNative.h"
#include <stdio.h>

static NSString *const A5MaliErrorDomain = @"com.orhunnx.a5xelte.mali";

static NSError *a5error(kern_return_t code)
{
    return [NSError errorWithDomain:A5MaliErrorDomain code:code userInfo:nil];
}

@interface A5MaliDevice () {
    A5MaliClient _client;
    NSRecursiveLock *_lock;
    NSHashTable<A5MaliSurface *> *_residentSurfaces;
    NSMutableSet<A5MaliSurface *> *_operationSurfaces;
    uint64_t _residencyClock;
    unsigned _evictions,_reimports,_blockedEvictions;
}
- (A5MaliClient *)client;
- (NSRecursiveLock *)lock;
- (void)setupResidency;
- (kern_return_t)importResourceLocked:(IOSurfaceRef)surface usage:(uint32_t)usage result:(A5MaliResource *)resource;
- (A5MaliResource)resolveResource:(A5MaliSurface *)surface;
- (BOOL)evictIdleResourceLocked;
- (void)beginResourceOperation;
- (void)endResourceOperation:(BOOL)terminal;
@end

@interface A5MaliCommandBuffer (PrivateInit)
- (instancetype)initWithDevice:(A5MaliDevice *)device;
@end

@interface A5MaliCommandQueue (PrivateInit)
- (instancetype)initWithDevice:(A5MaliDevice *)device;
@end

@interface A5MaliSurface () {
    A5MaliDevice *_device;
    IOSurfaceRef _surface;
    A5MaliResource _resource;
    uint64_t _residentUse;
    BOOL _residentQuarantined;
}
- (instancetype)initWithDevice:(A5MaliDevice *)device
                       surface:(IOSurfaceRef)surface
                      resource:(A5MaliResource)resource;
- (A5MaliResource)resource;
- (A5MaliDevice *)device;
- (A5MaliResource)residentResource;
- (uint64_t)residentUse;
- (void)setResidentUse:(uint64_t)use;
- (BOOL)residentQuarantined;
- (void)quarantineResident;
- (BOOL)evictResident:(A5MaliClient *)client;
- (BOOL)restoreResident:(A5MaliResource)resource;
@end

typedef NS_ENUM(uint32_t, A5MaliKind) {
    A5MaliKindClear = A5MaliClearBGRA,
    A5MaliKindCopy = A5MaliCopyBGRA,
    A5MaliKindTexturedQuad = A5MaliDrawTexturedQuadBGRA,
    A5MaliKindReadSurf = A5MaliReadSurfBGRA,
    A5MaliKindNative = 0x100,
};

@interface A5MaliOperation : NSObject
@property (nonatomic) A5MaliKind kind;
@property (nonatomic, strong) A5MaliSurface *destination;
@property (nonatomic, strong, nullable) A5MaliSurface *source;
@property (nonatomic) A5MaliRect sourceRect;
@property (nonatomic) A5MaliRect destinationRect;
@property (nonatomic) uint32_t color;
@property (nonatomic, copy, nullable) A5MaliNativeWork nativeWork;
@end

@implementation A5MaliOperation
@end

@implementation A5MaliDevice

- (instancetype)initWithError:(NSError * _Nullable * _Nullable)error
{
    if ((self = [super init])) {
        kern_return_t kr = A5MaliOpen(&_client);
        if (kr != KERN_SUCCESS) {
            if (error) *error = a5error(kr);
            return nil;
        }
        [self setupResidency];
    }
    return self;
}

- (instancetype)initWithService:(io_service_t)service
                          error:(NSError * _Nullable * _Nullable)error
{
    if ((self = [super init])) {
        kern_return_t kr = A5MaliOpenService(&_client, service);
        if (kr != KERN_SUCCESS) {
            if (error) *error = a5error(kr);
            return nil;
        }
        [self setupResidency];
    }
    return self;
}

- (instancetype)initWithTransport:(A5MaliTransport)transport
                          context:(void *)context
                commandCapabilities:(uint32_t)commands
               operationCapabilities:(uint32_t)operations
{
    if ((self = [super init])) {
        if (A5MaliInitTransportWithCapabilities(&_client, transport,
                context, commands) != KERN_SUCCESS)
            return nil;
        _client.supportedOperations = operations;
        [self setupResidency];
    }
    return self;
}

- (void)dealloc
{
    A5MaliClose(&_client);
}

- (A5MaliClient *)client { return &_client; }
- (NSRecursiveLock *)lock { return _lock; }

/* Logical texture ownership is independent of bounded kernel residency.
 * Weak cache entries never own a texture/backing; current synchronous GPU
 * operations hold strong leases until terminal proof. Eviction drops only an
 * idle import handle, retaining the caller's original IOSurface pixels. */
- (void)setupResidency
{
    _lock=[NSRecursiveLock new];
    _residentSurfaces=[NSHashTable weakObjectsHashTable];
}
- (BOOL)evictIdleResourceLocked
{
    @autoreleasepool {
        A5MaliSurface *victim=nil;
        for(A5MaliSurface *surface in _residentSurfaces.allObjects){
            if([_operationSurfaces containsObject:surface]||surface.residentQuarantined)continue;
            if(!victim||surface.residentUse<victim.residentUse)victim=surface;
        }
        if(!victim)return NO;
        if(![victim evictResident:&_client]){
            [victim quarantineResident];++_blockedEvictions;
            /* A failed unmap/release leaves its generation resident. Never
             * count or reuse that slot; try a different safely idle resource. */
            return [self evictIdleResourceLocked];
        }
        [_residentSurfaces removeObject:victim];++_evictions;
        if(_evictions<=8||!(_evictions%64))fprintf(stderr,
            "A5XELTE Metal residency: evicted=%u reimported=%u resident=%lu pinned=%lu blocked=%u\n",
            _evictions,_reimports,(unsigned long)_residentSurfaces.count,
            (unsigned long)_operationSurfaces.count,_blockedEvictions);
        return YES;
    }
}
- (kern_return_t)importResourceLocked:(IOSurfaceRef)surface usage:(uint32_t)usage result:(A5MaliResource *)resource
{
    mach_port_t port=IOSurfaceCreateMachPort(surface);
    if(!MACH_PORT_VALID(port))return kIOReturnBadArgument;
    /* The kernel currently publishes128 logical imports and four independent
     * physical windows. This cache never expands either bound. A smaller test
     * or future kernel quota also works through its NoResources response. */
    if(_residentSurfaces.count>=128)[self evictIdleResourceLocked];
    kern_return_t kr=A5MaliImportSurface(&_client,port,usage,resource);
    for(unsigned attempt=0;kr==kIOReturnNoResources&&attempt<128;++attempt){
        if(![self evictIdleResourceLocked])break;
        kr=A5MaliImportSurface(&_client,port,usage,resource);
    }
    mach_port_deallocate(mach_task_self(),port);return kr;
}
- (A5MaliSurface *)importSurface:(IOSurfaceRef)surface usage:(uint32_t)usage
    error:(NSError * _Nullable * _Nullable)error
{
    if(!surface){if(error)*error=a5error(kIOReturnBadArgument);return nil;}
    [_lock lock];
    @try{
        A5MaliResource resource={0};
        kern_return_t kr=[self importResourceLocked:surface usage:usage result:&resource];
        if(kr){if(error)*error=a5error(kr);return nil;}
        A5MaliSurface *result=[[A5MaliSurface alloc]initWithDevice:self surface:surface resource:resource];
        [result setResidentUse:++_residencyClock];[_residentSurfaces addObject:result];
        if(_operationSurfaces)[_operationSurfaces addObject:result];
        return result;
    }@finally{[_lock unlock];}
}
- (A5MaliResource)resolveResource:(A5MaliSurface *)surface
{
    [_lock lock];
    @try{
        A5MaliResource resource=surface.residentResource;
        if(surface.residentQuarantined){resource.token=0;return resource;}
        if(!resource.token&&surface.iosurface){
            A5MaliResource restored={0};
            kern_return_t kr=[self importResourceLocked:surface.iosurface usage:resource.usage result:&restored];
            if(kr)return resource;
            if(![surface restoreResident:restored]){
                A5MaliReleaseSurface(&_client,&restored);[surface quarantineResident];return resource;
            }
            [_residentSurfaces addObject:surface];++_reimports;resource=restored;
            if(_reimports<=8||!(_reimports%64))fprintf(stderr,
                "A5XELTE Metal residency: reimported=%u evicted=%u resident=%lu pinned=%lu blocked=%u\n",
                _reimports,_evictions,(unsigned long)_residentSurfaces.count,
                (unsigned long)_operationSurfaces.count,_blockedEvictions);
        }
        if(surface.iosurface){
            [surface setResidentUse:++_residencyClock];
            if(_operationSurfaces)[_operationSurfaces addObject:surface];
        }
        return resource;
    }@finally{[_lock unlock];}
}
- (void)beginResourceOperation
{
    if(_operationSurfaces)[NSException raise:NSInternalInconsistencyException format:@"nested resource residency operation"];
    _operationSurfaces=[NSMutableSet new];
}
- (void)endResourceOperation:(BOOL)terminal
{
    if(!terminal)for(A5MaliSurface *surface in _operationSurfaces)[surface quarantineResident];
    _operationSurfaces=nil;
}

- (A5MaliCommandBuffer *)newCommandBuffer
{
    return [[A5MaliCommandBuffer alloc] initWithDevice:self];
}

- (A5MaliCommandQueue *)newCommandQueue
{
    return [[A5MaliCommandQueue alloc] initWithDevice:self];
}

- (BOOL)supportsPrivateReadSurf
{
    return (_client.gpuCommandsSupported & (1U << 4)) != 0;
}
- (BOOL)supportsNativePrograms
{
    const uint32_t required = (1U << 16) | (1U << 17);
    return (_client.gpuCommandsSupported & 32U) &&
        (_client.supportedOperations & required) == required;
}

#ifdef A5_MALI_HOST_TEST
- (A5MaliSurface *)hostTestSurfaceWithResource:(A5MaliResource)resource
{
    return [[A5MaliSurface alloc] initWithDevice:self surface:NULL
                                         resource:resource];
}
#endif

@end

@implementation A5MaliCommandQueue {
    A5MaliDevice *_device;
}

- (instancetype)initWithDevice:(A5MaliDevice *)device
{
    if ((self = [super init]))
        _device = device;
    return self;
}

- (A5MaliCommandBuffer *)newCommandBuffer
{
    return [_device newCommandBuffer];
}

@end

@implementation A5MaliSurface

- (instancetype)initWithDevice:(A5MaliDevice *)device
                       surface:(IOSurfaceRef)surface
                      resource:(A5MaliResource)resource
{
    if ((self = [super init])) {
        _device = device;
        _surface = surface ? (IOSurfaceRef)CFRetain(surface) : NULL;
        _resource = resource;
    }
    return self;
}

- (void)dealloc
{
    if (_resource.token) {
        [[_device lock] lock];
        /* The kernel keeps GPU-visible pages pinned if teardown is unsafe. */
        A5MaliReleaseSurface([_device client], &_resource);
        [[_device lock] unlock];
    }
    if (_surface) CFRelease(_surface);
}

- (A5MaliResource)resource { return [_device resolveResource:self]; }
- (A5MaliResource)residentResource { return _resource; }
- (uint64_t)residentUse { return _residentUse; }
- (void)setResidentUse:(uint64_t)use { _residentUse=use; }
- (BOOL)residentQuarantined { return _residentQuarantined; }
- (void)quarantineResident { _residentQuarantined=YES; }
- (BOOL)evictResident:(A5MaliClient *)client
{
    if(!_surface||!_resource.token||_residentQuarantined)return NO;
    A5MaliResource old=_resource,retired=_resource;
    if(A5MaliReleaseSurface(client,&retired)!=KERN_SUCCESS)return NO;
    _resource=old;_resource.token=0;return YES;
}
- (BOOL)restoreResident:(A5MaliResource)resource
{
    if(_resource.token||_residentQuarantined||!resource.token||resource.width!=_resource.width||
       resource.height!=_resource.height||resource.rowBytes!=_resource.rowBytes||resource.usage!=_resource.usage)return NO;
    _resource=resource;return YES;
}
- (A5MaliDevice *)device { return _device; }
- (uint32_t)width { return _resource.width; }
- (uint32_t)height { return _resource.height; }
- (uint32_t)rowBytes { return _resource.rowBytes; }
- (IOSurfaceRef)iosurface { return _surface; }

@end

@interface A5MaliCommandBuffer () {
    A5MaliDevice *_device;
    NSMutableArray<A5MaliOperation *> *_operations;
    BOOL _committed;
    A5MaliFence _completedFence;
}
- (instancetype)initWithDevice:(A5MaliDevice *)device;
@end

@implementation A5MaliCommandBuffer

- (instancetype)initWithDevice:(A5MaliDevice *)device
{
    if ((self = [super init])) {
        _device = device;
        _operations = [NSMutableArray new];
    }
    return self;
}

- (BOOL)encodeClear:(A5MaliSurface *)destination
               rect:(A5MaliRect)rect
               bgra:(uint32_t)bgra
{
    if (_committed || _operations.count >= A5MaliCommandOperationLimit ||
        destination.device != _device) return NO;
    A5MaliOperation *operation = [A5MaliOperation new];
    operation.kind = A5MaliKindClear;
    operation.destination = destination;
    operation.destinationRect = rect;
    operation.color = bgra;
    [_operations addObject:operation];
    return YES;
}

- (BOOL)encodeCopy:(A5MaliSurface *)source
       sourceRect:(A5MaliRect)sourceRect
               to:(A5MaliSurface *)destination
  destinationRect:(A5MaliRect)destinationRect
{
    if (_committed || _operations.count >= A5MaliCommandOperationLimit || source.device != _device ||
        destination.device != _device) return NO;
    A5MaliOperation *operation = [A5MaliOperation new];
    operation.kind = A5MaliKindCopy;
    operation.source = source;
    operation.destination = destination;
    operation.sourceRect = sourceRect;
    operation.destinationRect = destinationRect;
    [_operations addObject:operation];
    return YES;
}

- (BOOL)encodeTexturedQuad:(A5MaliSurface *)source
               sourceRect:(A5MaliRect)sourceRect
                       to:(A5MaliSurface *)destination
          destinationRect:(A5MaliRect)destinationRect
{
    if (_committed || _operations.count >= A5MaliCommandOperationLimit || source.device != _device ||
        destination.device != _device) return NO;
    A5MaliOperation *operation = [A5MaliOperation new];
    operation.kind = A5MaliKindTexturedQuad;
    operation.source = source;
    operation.destination = destination;
    operation.sourceRect = sourceRect;
    operation.destinationRect = destinationRect;
    [_operations addObject:operation];
    return YES;
}

- (BOOL)encodeReadSurf:(A5MaliSurface *)source
                   to:(A5MaliSurface *)destination
{
    if (_committed || _operations.count >= A5MaliCommandOperationLimit || source.device != _device ||
        destination.device != _device || ![_device supportsPrivateReadSurf])
        return NO;
    A5MaliOperation *operation = [A5MaliOperation new];
    operation.kind = A5MaliKindReadSurf;
    operation.source = source;
    operation.destination = destination;
    operation.sourceRect = (A5MaliRect){0, 0, source.width, source.height};
    operation.destinationRect = (A5MaliRect){0, 0,
        destination.width, destination.height};
    [_operations addObject:operation];
    return YES;
}

- (BOOL)commitAndWait:(NSError * _Nullable * _Nullable)error
{
    if (_committed) {
        if (error) *error = a5error(kIOReturnBadArgument);
        return NO;
    }
    _committed = YES;
    [[_device lock] lock];
    BOOL success=NO;
    @try{success=[self executeOperationsLocked:error];}
    @finally{[[_device lock] unlock];}
    if(success)[self retireTerminalWork];
    return success;
}

- (BOOL)executeOperationsLocked:(NSError * _Nullable * _Nullable)error
{
    A5MaliClient *client = [_device client];
    BOOL hasNative = NO;
    for (A5MaliOperation *operation in _operations)
        if (operation.kind == A5MaliKindNative) { hasNative = YES; break; }
    if (!hasNative && (client->supportedOperations & (1U << 6))) {
        for (NSUInteger start = 0; start < _operations.count;
             start += A5MaliBatchMaxCommands) {
            [_device beginResourceOperation];
            BOOL terminal=NO;
            @try{
            const uint32_t count = (uint32_t)MIN(
                _operations.count - start, A5MaliBatchMaxCommands);
            A5MaliResource source[A5MaliBatchMaxCommands] = {0};
            A5MaliResource destination[A5MaliBatchMaxCommands] = {0};
            A5MaliBatchCommand commands[A5MaliBatchMaxCommands] = {0};
            for (uint32_t i = 0; i < count; ++i) {
                A5MaliOperation *operation = _operations[start + i];
                destination[i] = operation.destination.resource;
                if (operation.source)
                    source[i] = operation.source.resource;
                commands[i] = (A5MaliBatchCommand){
                    operation.kind, operation.color,
                    operation.source ? &source[i] : NULL,
                    &destination[i], operation.sourceRect,
                    operation.destinationRect
                };
            }
            A5MaliBatchResult result = {0};
            kern_return_t kr = A5MaliSubmitBatchCommands(client, commands,
                count, &result);
            if (result.completedCount)
                _completedFence = result.items[
                    result.completedCount - 1].fence;
            terminal=kr==KERN_SUCCESS;
            if (kr != KERN_SUCCESS) {
                if (error) *error = a5error(kr);
                return NO;
            }
            }@finally{[_device endResourceOperation:terminal];}
        }
        return YES;
    }
    for (A5MaliOperation *operation in _operations) {
        [_device beginResourceOperation];
        BOOL terminal=NO;
        @try{
        A5MaliFence fence = {0};
        kern_return_t kr;
        if (operation.kind == A5MaliKindNative) {
            A5MaliBeginNativeSubmissionTracking();
            kr = operation.nativeWork ? operation.nativeWork(client, &fence) :
                kIOReturnBadArgument;
            if(kr)terminal=!A5MaliNativeSubmissionMayBeActive();
            else if(!fence.fragmentFence||fence.fragmentFence<fence.tilerFence)kr=kIOReturnError;
            else terminal=YES;
        } else if (operation.kind == A5MaliKindClear) {
            A5MaliResource destination = operation.destination.resource;
            kr = A5MaliClear([_device client], &destination,
                operation.destinationRect, operation.color, &fence);
        } else if (operation.kind == A5MaliKindCopy) {
            A5MaliResource source = operation.source.resource;
            A5MaliResource destination = operation.destination.resource;
            kr = A5MaliCopy([_device client], &source, operation.sourceRect,
                &destination, operation.destinationRect, &fence);
        } else if (operation.kind == A5MaliKindTexturedQuad) {
            A5MaliResource source = operation.source.resource;
            A5MaliResource destination = operation.destination.resource;
            kr = A5MaliDrawTexturedQuad([_device client], &source,
                operation.sourceRect, &destination,
                operation.destinationRect, &fence);
        } else {
            A5MaliResource source = operation.source.resource;
            A5MaliResource destination = operation.destination.resource;
            kr = A5MaliReadSurf([_device client], &source, &destination,
                &fence);
        }
        if(operation.kind!=A5MaliKindNative)terminal=kr==KERN_SUCCESS;
        if (kr != KERN_SUCCESS) {
            if (error) *error = a5error(kr);
            return NO;
        }
        _completedFence = fence;
        }@finally{[_device endResourceOperation:terminal];}
    }
    return YES;
}

- (BOOL)encodeNativeWork:(A5MaliNativeWork)work
{
    if (_committed || !work || _operations.count >= A5MaliCommandOperationLimit ||
        ![_device supportsNativePrograms]) return NO;
    A5MaliOperation *operation = [A5MaliOperation new];
    operation.kind = A5MaliKindNative;
    operation.nativeWork = work;
    [_operations addObject:operation];
    return YES;
}

- (void)retireTerminalWork
{
    /* Releases may reenter the device to unmap/drop an imported handle.
     * Callers are outside the transport lock and have terminal proof. */
    _committed=YES;
    [_operations removeAllObjects];
}
- (A5MaliFence)completedFence { return _completedFence; }
- (BOOL)usesLegacyGPUWork
{
    for(A5MaliOperation *operation in _operations)
        if(operation.kind!=A5MaliKindNative)return YES;
    return NO;
}

@end
