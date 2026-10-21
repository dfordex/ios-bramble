/* SPDX-License-Identifier: MIT */
#import "A5MaliCommandBuffer.h"

static NSString *const A5MaliErrorDomain = @"com.orhunnx.a5xelte.mali";

static NSError *a5error(kern_return_t code)
{
    return [NSError errorWithDomain:A5MaliErrorDomain code:code userInfo:nil];
}

@interface A5MaliDevice () {
    A5MaliClient _client;
    NSLock *_lock;
}
- (A5MaliClient *)client;
- (NSLock *)lock;
@end

@interface A5MaliCommandBuffer (PrivateInit)
- (instancetype)initWithDevice:(A5MaliDevice *)device;
@end

@interface A5MaliSurface () {
    A5MaliDevice *_device;
    IOSurfaceRef _surface;
    A5MaliResource _resource;
}
- (instancetype)initWithDevice:(A5MaliDevice *)device
                       surface:(IOSurfaceRef)surface
                      resource:(A5MaliResource)resource;
- (A5MaliResource)resource;
- (A5MaliDevice *)device;
@end

typedef NS_ENUM(uint32_t, A5MaliKind) {
    A5MaliKindClear = A5MaliClearBGRA,
    A5MaliKindCopy = A5MaliCopyBGRA,
};

@interface A5MaliOperation : NSObject
@property (nonatomic) A5MaliKind kind;
@property (nonatomic, strong) A5MaliSurface *destination;
@property (nonatomic, strong, nullable) A5MaliSurface *source;
@property (nonatomic) A5MaliRect sourceRect;
@property (nonatomic) A5MaliRect destinationRect;
@property (nonatomic) uint32_t color;
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
        _lock = [NSLock new];
    }
    return self;
}

- (void)dealloc
{
    A5MaliClose(&_client);
}

- (A5MaliClient *)client { return &_client; }
- (NSLock *)lock { return _lock; }

- (A5MaliSurface *)importSurface:(IOSurfaceRef)surface
                           usage:(uint32_t)usage
                           error:(NSError * _Nullable * _Nullable)error
{
    if (!surface) {
        if (error) *error = a5error(kIOReturnBadArgument);
        return nil;
    }
    mach_port_t port = IOSurfaceCreateMachPort(surface);
    if (!MACH_PORT_VALID(port)) {
        if (error) *error = a5error(kIOReturnBadArgument);
        return nil;
    }
    A5MaliResource resource = {0};
    [_lock lock];
    kern_return_t kr = A5MaliImportSurface(&_client, port, usage, &resource);
    [_lock unlock];
    mach_port_deallocate(mach_task_self(), port);
    if (kr != KERN_SUCCESS) {
        if (error) *error = a5error(kr);
        return nil;
    }
    return [[A5MaliSurface alloc] initWithDevice:self surface:surface
                                         resource:resource];
}

- (A5MaliCommandBuffer *)newCommandBuffer
{
    return [[A5MaliCommandBuffer alloc] initWithDevice:self];
}

@end

@implementation A5MaliSurface

- (instancetype)initWithDevice:(A5MaliDevice *)device
                       surface:(IOSurfaceRef)surface
                      resource:(A5MaliResource)resource
{
    if ((self = [super init])) {
        _device = device;
        _surface = (IOSurfaceRef)CFRetain(surface);
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

- (A5MaliResource)resource { return _resource; }
- (A5MaliDevice *)device { return _device; }
- (uint32_t)width { return _resource.width; }
- (uint32_t)height { return _resource.height; }
- (uint32_t)rowBytes { return _resource.rowBytes; }

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
    if (_committed || _operations.count >= 64 ||
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
    if (_committed || _operations.count >= 64 || source.device != _device ||
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

- (BOOL)commitAndWait:(NSError * _Nullable * _Nullable)error
{
    if (_committed) {
        if (error) *error = a5error(kIOReturnBadArgument);
        return NO;
    }
    _committed = YES;
    [[_device lock] lock];
    for (A5MaliOperation *operation in _operations) {
        A5MaliFence fence = {0};
        kern_return_t kr;
        if (operation.kind == A5MaliKindClear) {
            A5MaliResource destination = operation.destination.resource;
            kr = A5MaliClear([_device client], &destination,
                operation.destinationRect, operation.color, &fence);
        } else {
            A5MaliResource source = operation.source.resource;
            A5MaliResource destination = operation.destination.resource;
            kr = A5MaliCopy([_device client], &source, operation.sourceRect,
                &destination, operation.destinationRect, &fence);
        }
        if (kr != KERN_SUCCESS) {
            [[_device lock] unlock];
            if (error) *error = a5error(kr);
            return NO;
        }
        _completedFence = fence;
    }
    [[_device lock] unlock];
    return YES;
}

- (A5MaliFence)completedFence { return _completedFence; }

@end
