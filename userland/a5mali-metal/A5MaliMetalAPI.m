/* SPDX-License-Identifier: MIT
 * Narrow Metal-selector adapter for the real typed Mali copy path.
 * These classes deliberately claim no Metal protocol conformance.
 */
#import "A5MaliRestrictedDevice.h"

static NSError *metalError(kern_return_t code)
{
    return [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
                               code:code userInfo:nil];
}

static BOOL validBGRARow(NSUInteger width, NSUInteger height, NSUInteger rowBytes)
{
    /* The v4 linear texture/writeback paths accept 16-byte rows. Bound each
     * factor before multiplication and keep the same limits as the kernel. */
    return width > 0 && width <= 2048 && height > 0 && height <= 2048 &&
        rowBytes >= width * 4 && rowBytes <= 8192 && (rowBytes & 15) == 0;
}

A5MaliPipelineShape A5MaliInspectReadSurfPipelineDescriptor(
    MTLRenderPipelineDescriptor *descriptor)
{
    if (!descriptor ||
        ![descriptor.vertexFunction.name isEqualToString:@"read_surf_vert"] ||
        ![descriptor.fragmentFunction.name isEqualToString:@"read_surf_frag"] ||
        descriptor.vertexFunction.functionType != MTLFunctionTypeVertex ||
        descriptor.fragmentFunction.functionType != MTLFunctionTypeFragment ||
        descriptor.rasterSampleCount != 1 ||
        !descriptor.isRasterizationEnabled ||
        descriptor.isAlphaToCoverageEnabled || descriptor.isAlphaToOneEnabled ||
        descriptor.depthAttachmentPixelFormat != MTLPixelFormatInvalid ||
        descriptor.stencilAttachmentPixelFormat != MTLPixelFormatInvalid ||
        (descriptor.inputPrimitiveTopology !=
             MTLPrimitiveTopologyClassUnspecified &&
         descriptor.inputPrimitiveTopology !=
             MTLPrimitiveTopologyClassTriangle))
        return A5MaliPipelineShapeUnsupported;
    MTLRenderPipelineColorAttachmentDescriptor *color =
        descriptor.colorAttachments[0];
    if (color.pixelFormat != MTLPixelFormatBGRA8Unorm ||
        color.isBlendingEnabled || color.writeMask != MTLColorWriteMaskAll)
        return A5MaliPipelineShapeUnsupported;
    for (NSUInteger i = 1; i < 8; ++i)
        if (descriptor.colorAttachments[i].pixelFormat != MTLPixelFormatInvalid)
            return A5MaliPipelineShapeUnsupported;
    MTLVertexDescriptor *vertex = descriptor.vertexDescriptor;
    if (vertex)
        for (NSUInteger i = 0; i < 31; ++i)
            if (vertex.attributes[i].format != MTLVertexFormatInvalid)
                return A5MaliPipelineShapeUnsupported;
    return A5MaliPipelineShapeReadSurfCandidate;
}

@interface A5MaliRestrictedDevice (PrivateAccess)
- (A5MaliDevice *)privateDevice;
@end

@interface A5MaliReadSurfCandidate (PrivateInit)
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device;
@end

@interface A5MaliMetalTexture () {
    A5MaliSurface *_surface;
    A5MaliRestrictedDevice *_device;
    MTLTextureUsage _usage;
}
- (instancetype)initWithSurface:(A5MaliSurface *)surface
                        device:(A5MaliRestrictedDevice *)device
                         usage:(MTLTextureUsage)usage;
- (A5MaliSurface *)privateSurface;
@end

@interface A5MaliMetalQueue () {
    A5MaliRestrictedDevice *_device;
    NSLock *_configurationLock;
    dispatch_queue_t _submissionQueue;
    dispatch_queue_t _serialSubmissionQueue;
    dispatch_queue_t _completionQueue;
    BOOL _workStarted;
}
- (void)submitWork:(dispatch_block_t)work;
- (void)dispatchCompletion:(dispatch_block_t)work;
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device;
@end

@interface A5MaliMetalBuffer () {
    A5MaliMetalQueue *_queue;
    A5MaliCommandBuffer *_privateBuffer;
    MTLCommandBufferStatus _status;
    NSError *_error;
    BOOL _encoderOpen;
    NSCondition *_condition;
    NSMutableArray<MTLCommandBufferHandler> *_scheduled;
    NSMutableArray<MTLCommandBufferHandler> *_completed;
}
- (instancetype)initWithQueue:(A5MaliMetalQueue *)queue
                privateBuffer:(A5MaliCommandBuffer *)buffer;
- (A5MaliCommandBuffer *)privateBuffer;
- (void)markEncodingError:(kern_return_t)code;
- (void)finishEncoding;
@end

@interface A5MaliMetalBlitEncoder () {
    A5MaliMetalBuffer *_buffer;
    BOOL _ended;
    NSMutableArray<NSString *> *_debugGroups;
}
- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer;
- (BOOL)validateActive;
- (BOOL)validateTexture:(id)texture;
- (void)rejectUnsupportedOperation;
@end

@interface A5MaliMetalRenderEncoder () {
    A5MaliMetalBuffer *_buffer;
    A5MaliMetalTexture *_destination;
    A5MaliMetalTexture *_source;
    A5MaliReadSurfCandidate *_pipeline;
    BOOL _ended, _hasDraw, _hasViewport;
    MTLViewport _viewport;
}
- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer
                   destination:(A5MaliMetalTexture *)destination;
@end

@implementation A5MaliRestrictedDevice (LimitedMetalSelectors)

- (A5MaliMetalQueue *)newCommandQueue
{
    return [[A5MaliMetalQueue alloc] initWithDevice:self];
}

- (A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
{
    /* A standalone BGRA texture is backed by a real IOSurface so the kernel
     * import path owns its GPU mapping. Other formats and layouts fail closed. */
    if (!descriptor || descriptor.textureType != MTLTextureType2D ||
        descriptor.pixelFormat != MTLPixelFormatBGRA8Unorm ||
        descriptor.width == 0 || descriptor.width > 2048 ||
        descriptor.height == 0 || descriptor.height > 2048 ||
        descriptor.mipmapLevelCount != 1 || descriptor.arrayLength != 1 ||
        descriptor.sampleCount != 1 ||
        descriptor.storageMode != MTLStorageModeShared ||
        (descriptor.usage & ~(MTLTextureUsageShaderRead |
            MTLTextureUsageRenderTarget)) || !descriptor.usage)
        return nil;
    const NSUInteger rowBytes = (descriptor.width * 4 + 15) & ~(NSUInteger)15;
    NSDictionary *properties = @{
        (__bridge id)kIOSurfaceWidth: @(descriptor.width),
        (__bridge id)kIOSurfaceHeight: @(descriptor.height),
        (__bridge id)kIOSurfaceBytesPerElement: @4,
        (__bridge id)kIOSurfaceBytesPerRow: @(rowBytes),
        (__bridge id)kIOSurfacePixelFormat: @(0x42475241u),
    };
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!surface)
        return nil;
    A5MaliMetalTexture *texture =
        [self newTextureWithDescriptor:descriptor iosurface:surface plane:0];
    CFRelease(surface);
    return texture;
}

- (id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                      error:(NSError * _Nullable * _Nullable)error
{
    A5MaliPipelineShape shape =
        A5MaliInspectReadSurfPipelineDescriptor(descriptor);
    id vertex = descriptor.vertexFunction;
    id fragment = descriptor.fragmentFunction;
    BOOL authenticatedPair =
        [vertex isKindOfClass:[A5MaliMetalFunction class]] &&
        [fragment isKindOfClass:[A5MaliMetalFunction class]] &&
        [vertex library] == [fragment library] &&
        [vertex device] == self && [fragment device] == self;
    if (shape == A5MaliPipelineShapeReadSurfCandidate &&
        authenticatedPair && [[self privateDevice] supportsPrivateReadSurf]) {
        if (error) *error = nil;
        return [[A5MaliReadSurfCandidate alloc] initWithDevice:self];
    }
    if (error) {
        NSString *reason = shape == A5MaliPipelineShapeReadSurfCandidate ?
            @"read_surf requires functions from the exact QuartzCore metallib and kernel operation 4" :
            @"render pipeline is outside the validated read_surf descriptor profile";
        *error = [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
            code:kIOReturnUnsupported
            userInfo:@{NSLocalizedDescriptionKey: reason}];
    }
    return nil;
}

- (A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
                                         iosurface:(IOSurfaceRef)surface
                                             plane:(NSUInteger)plane
{
    if (!descriptor || !surface || plane != 0 ||
        descriptor.textureType != MTLTextureType2D ||
        descriptor.pixelFormat != MTLPixelFormatBGRA8Unorm ||
        descriptor.mipmapLevelCount != 1 || descriptor.arrayLength != 1 ||
        descriptor.sampleCount != 1 ||
        descriptor.storageMode != MTLStorageModeShared ||
        descriptor.width != IOSurfaceGetWidth(surface) ||
        descriptor.height != IOSurfaceGetHeight(surface) ||
        IOSurfaceGetBytesPerElement(surface) != 4 ||
        !validBGRARow(descriptor.width, descriptor.height,
            IOSurfaceGetBytesPerRow(surface)) ||
        IOSurfaceGetBytesPerRow(surface) * descriptor.height >
            IOSurfaceGetAllocSize(surface) ||
        IOSurfaceGetPixelFormat(surface) != 0x42475241 ||
        (descriptor.usage & ~(MTLTextureUsageShaderRead |
            MTLTextureUsageRenderTarget)) || !descriptor.usage)
        return nil;
    uint32_t usage = 0;
    if (descriptor.usage & MTLTextureUsageShaderRead) usage |= A5MaliRead;
    if (descriptor.usage & MTLTextureUsageRenderTarget) usage |= A5MaliWrite;
    A5MaliSurface *imported = [[self privateDevice] importSurface:surface
                                                           usage:usage error:NULL];
    return imported ? [[A5MaliMetalTexture alloc] initWithSurface:imported
        device:self usage:descriptor.usage] : nil;
}

#ifdef A5_MALI_HOST_TEST
- (A5MaliMetalTexture *)hostTestTextureWithResource:(A5MaliResource)resource
{
    A5MaliSurface *surface = [[self privateDevice]
        hostTestSurfaceWithResource:resource];
    MTLTextureUsage usage = 0;
    if (resource.usage & A5MaliRead) usage |= MTLTextureUsageShaderRead;
    if (resource.usage & A5MaliWrite) usage |= MTLTextureUsageRenderTarget;
    return [[A5MaliMetalTexture alloc] initWithSurface:surface
        device:self usage:usage];
}
#endif

@end

@implementation A5MaliReadSurfCandidate {
    A5MaliRestrictedDevice *_device;
}
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
{
    if ((self = [super init])) _device = device;
    return self;
}
- (A5MaliRestrictedDevice *)device { return _device; }
@end

@implementation A5MaliMetalTexture

- (instancetype)initWithSurface:(A5MaliSurface *)surface
                        device:(A5MaliRestrictedDevice *)device
                         usage:(MTLTextureUsage)usage
{
    if ((self = [super init])) {
        _surface = surface;
        _device = device;
        _usage = usage;
    }
    return self;
}

- (A5MaliSurface *)privateSurface { return _surface; }
- (NSUInteger)width { return _surface.width; }
- (NSUInteger)height { return _surface.height; }
- (MTLPixelFormat)pixelFormat { return MTLPixelFormatBGRA8Unorm; }
- (MTLTextureType)textureType { return MTLTextureType2D; }
- (NSUInteger)mipmapLevelCount { return 1; }
- (NSUInteger)arrayLength { return 1; }
- (NSUInteger)sampleCount { return 1; }
- (MTLTextureUsage)usage { return _usage; }
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (IOSurfaceRef)iosurface { return _surface.iosurface; }
- (A5MaliRestrictedDevice *)device { return _device; }

@end

@implementation A5MaliMetalQueue

- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
{
    if ((self = [super init])) {
        _device = device;
        _configurationLock = [NSLock new];
    }
    return self;
}

- (A5MaliRestrictedDevice *)device { return _device; }
- (void)setSubmissionQueue:(dispatch_queue_t)queue
{
    [_configurationLock lock];
    if (queue == _submissionQueue) {
        [_configurationLock unlock];
        return;
    }
    if (_workStarted) {
        [_configurationLock unlock];
        [NSException raise:NSInvalidArgumentException
            format:@"Mali submission target cannot change after work starts"];
        return;
    }
    _submissionQueue = queue;
    _serialSubmissionQueue = queue ? dispatch_queue_create_with_target(
        "com.orhunnx.a5xelte.mali.submit", DISPATCH_QUEUE_SERIAL, queue) : nil;
    [_configurationLock unlock];
}
- (dispatch_queue_t)submissionQueue
{
    [_configurationLock lock];
    dispatch_queue_t queue = _submissionQueue;
    [_configurationLock unlock];
    return queue;
}
- (void)setCompletionQueue:(dispatch_queue_t)queue
{
    [_configurationLock lock];
    _completionQueue = queue;
    [_configurationLock unlock];
}
- (dispatch_queue_t)completionQueue
{
    [_configurationLock lock];
    dispatch_queue_t queue = _completionQueue;
    [_configurationLock unlock];
    return queue;
}
- (BOOL)setGPUPriority:(NSUInteger)priority { (void)priority; return NO; }
- (BOOL)setBackgroundGPUPriority:(NSUInteger)priority { (void)priority; return NO; }
- (void)submitWork:(dispatch_block_t)work
{
    [_configurationLock lock];
    _workStarted = YES;
    dispatch_queue_t queue = _serialSubmissionQueue;
    [_configurationLock unlock];
    if (queue) dispatch_async(queue, work);
    else work();
}
- (void)dispatchCompletion:(dispatch_block_t)work
{
    dispatch_queue_t queue = self.completionQueue;
    if (queue) dispatch_async(queue, work);
    else work();
}
- (A5MaliMetalBuffer *)commandBuffer
{
    return [[A5MaliMetalBuffer alloc] initWithQueue:self
        privateBuffer:[[_device privateDevice] newCommandBuffer]];
}
- (A5MaliMetalBuffer *)commandBufferWithUnretainedReferences
{
    /* This adapter always retains imported IOSurfaces through completion. */
    return nil;
}

@end

@implementation A5MaliMetalBuffer

- (instancetype)initWithQueue:(A5MaliMetalQueue *)queue
                privateBuffer:(A5MaliCommandBuffer *)buffer
{
    if ((self = [super init])) {
        _queue = queue;
        _privateBuffer = buffer;
        _scheduled = [NSMutableArray new];
        _completed = [NSMutableArray new];
        _condition = [NSCondition new];
        _status = MTLCommandBufferStatusNotEnqueued;
    }
    return self;
}

- (A5MaliCommandBuffer *)privateBuffer { return _privateBuffer; }
- (A5MaliRestrictedDevice *)device { return _queue.device; }
- (A5MaliMetalQueue *)commandQueue { return _queue; }
- (MTLCommandBufferStatus)status
{
    [_condition lock];
    MTLCommandBufferStatus status = _status;
    [_condition unlock];
    return status;
}
- (NSError *)error
{
    [_condition lock];
    NSError *error = _error;
    [_condition unlock];
    return error;
}
- (BOOL)retainedReferences { return YES; }
- (void)markEncodingError:(kern_return_t)code
{
    [_condition lock];
    if (!_error) _error = metalError(code);
    [_condition unlock];
}
- (void)finishEncoding { _encoderOpen = NO; }

- (A5MaliMetalBlitEncoder *)blitCommandEncoder
{
    [_condition lock];
    BOOL committed = _status >= MTLCommandBufferStatusCommitted;
    [_condition unlock];
    if (_encoderOpen || committed) return nil;
    _encoderOpen = YES;
    return [[A5MaliMetalBlitEncoder alloc] initWithBuffer:self];
}

- (A5MaliMetalRenderEncoder *)renderCommandEncoderWithDescriptor:
    (MTLRenderPassDescriptor *)descriptor
{
    [_condition lock];
    BOOL committed = _status >= MTLCommandBufferStatusCommitted;
    [_condition unlock];
    id target = descriptor.colorAttachments[0].texture;
    if (_encoderOpen || committed ||
        ![[_queue.device privateDevice] supportsPrivateReadSurf] ||
        ![target isKindOfClass:[A5MaliMetalTexture class]] ||
        ((A5MaliMetalTexture *)target).device != _queue.device ||
        descriptor.colorAttachments[0].loadAction != MTLLoadActionDontCare ||
        descriptor.colorAttachments[0].storeAction != MTLStoreActionStore ||
        descriptor.depthAttachment.texture ||
        descriptor.stencilAttachment.texture) {
        [self markEncodingError:kIOReturnUnsupported];
        return nil;
    }
    for (NSUInteger i = 1; i < 8; ++i)
        if (descriptor.colorAttachments[i].texture) {
            [self markEncodingError:kIOReturnUnsupported];
            return nil;
        }
    _encoderOpen = YES;
    return [[A5MaliMetalRenderEncoder alloc] initWithBuffer:self
        destination:(A5MaliMetalTexture *)target];
}

- (void)enqueue
{
    [_condition lock];
    if (_status == MTLCommandBufferStatusNotEnqueued)
        _status = MTLCommandBufferStatusEnqueued;
    [_condition unlock];
}

- (void)commit
{
    [_condition lock];
    if (_status >= MTLCommandBufferStatusCommitted) {
        [_condition unlock];
        return;
    }
    [_condition unlock];
    if (_encoderOpen) [self markEncodingError:kIOReturnNotReady];
    [_condition lock];
    if (_status >= MTLCommandBufferStatusCommitted) {
        [_condition unlock];
        return;
    }
    _status = MTLCommandBufferStatusCommitted;
    BOOL submit = !_error;
    [_condition unlock];
    [_queue submitWork:^{
    NSError *submissionError = nil;
    if (submit) {
        if (![_privateBuffer commitAndWait:&submissionError])
            submissionError = submissionError ?: metalError(kIOReturnError);
    }
    [_condition lock];
    if (submissionError) _error = submissionError;
    BOOL succeeded = !_error;
    _status = _error ? MTLCommandBufferStatusError :
        MTLCommandBufferStatusCompleted;
    NSArray<MTLCommandBufferHandler> *scheduled = [_scheduled copy];
    [_scheduled removeAllObjects];
    NSArray<MTLCommandBufferHandler> *completed = [_completed copy];
    [_completed removeAllObjects];
    [_condition broadcast];
    [_condition unlock];
    /* The kernel batch is synchronous; software scheduling and callbacks
     * obey the dispatch queues retained from QuartzCore. */
    [_queue dispatchCompletion:^{
    if (succeeded)
        for (MTLCommandBufferHandler handler in scheduled)
            handler((id<MTLCommandBuffer>)self);
    for (MTLCommandBufferHandler handler in completed)
        handler((id<MTLCommandBuffer>)self);
    }];
    }];
}

- (void)waitUntilScheduled
{
    [_condition lock];
    while (_status < MTLCommandBufferStatusScheduled)
        [_condition wait];
    [_condition unlock];
}
- (void)waitUntilCompleted
{
    [_condition lock];
    while (_status < MTLCommandBufferStatusCompleted)
        [_condition wait];
    [_condition unlock];
}
- (void)addScheduledHandler:(MTLCommandBufferHandler)handler
{
    if (!handler) return;
    [_condition lock];
    if (_status >= MTLCommandBufferStatusScheduled &&
        _status != MTLCommandBufferStatusError) {
        [_condition unlock];
        [_queue dispatchCompletion:^{ handler((id<MTLCommandBuffer>)self); }];
    } else if (_status < MTLCommandBufferStatusCompleted) {
        [_scheduled addObject:[handler copy]];
        [_condition unlock];
    } else [_condition unlock];
}
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler
{
    if (!handler) return;
    [_condition lock];
    if (_status == MTLCommandBufferStatusCompleted ||
        _status == MTLCommandBufferStatusError) {
        [_condition unlock];
        [_queue dispatchCompletion:^{ handler((id<MTLCommandBuffer>)self); }];
    } else {
        [_completed addObject:[handler copy]];
        [_condition unlock];
    }
}

@end

@implementation A5MaliMetalRenderEncoder

- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer
                   destination:(A5MaliMetalTexture *)destination
{
    if ((self = [super init])) {
        _buffer = buffer;
        _destination = destination;
    }
    return self;
}

- (void)setRenderPipelineState:(A5MaliReadSurfCandidate *)pipeline
{
    if (_ended || ![pipeline isKindOfClass:[A5MaliReadSurfCandidate class]] ||
        pipeline.device != _buffer.device)
        [_buffer markEncodingError:kIOReturnBadArgument];
    else _pipeline = pipeline;
}

- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atIndex:(NSUInteger)index
{
    if (_ended || index != 0 ||
        ![texture isKindOfClass:[A5MaliMetalTexture class]] ||
        texture.device != _buffer.device ||
        !(texture.usage & MTLTextureUsageShaderRead))
        [_buffer markEncodingError:kIOReturnBadArgument];
    else _source = texture;
}

- (void)setViewport:(MTLViewport)viewport
{
    if (_ended || viewport.originX != 0 || viewport.originY != 0 ||
        viewport.width != _destination.width ||
        viewport.height != _destination.height ||
        viewport.znear != 0 || viewport.zfar != 1)
        [_buffer markEncodingError:kIOReturnUnsupported];
    else {
        _viewport = viewport;
        _hasViewport = YES;
    }
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType
          vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount
{
    if (_ended || _hasDraw || primitiveType != MTLPrimitiveTypeTriangle ||
        vertexStart || vertexCount != 3)
        [_buffer markEncodingError:kIOReturnUnsupported];
    else _hasDraw = YES;
}

- (void)endEncoding
{
    if (_ended) return;
    _ended = YES;
    if (!_pipeline || !_source || !_hasDraw ||
        _source == _destination ||
        _source.width != _destination.width ||
        _source.height != _destination.height ||
        _source.width != 1080 || _source.height != 1920 ||
        !validBGRARow(_source.width, _source.height,
            _source.privateSurface.rowBytes) ||
        !validBGRARow(_destination.width, _destination.height,
            _destination.privateSurface.rowBytes) ||
        !(_destination.usage & MTLTextureUsageRenderTarget) ||
        (_hasViewport && (_viewport.width != _destination.width ||
            _viewport.height != _destination.height)) ||
        ![[_buffer privateBuffer] encodeReadSurf:[_source privateSurface]
            to:[_destination privateSurface]])
        [_buffer markEncodingError:kIOReturnUnsupported];
    [_buffer finishEncoding];
}

@end

@implementation A5MaliMetalBlitEncoder

- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer
{
    if ((self = [super init])) {
        _buffer = buffer;
        _debugGroups = [NSMutableArray new];
    }
    return self;
}
- (A5MaliRestrictedDevice *)device { return _buffer.device; }
- (BOOL)validateActive
{
    if (_ended || _buffer.status >= MTLCommandBufferStatusCommitted) {
        [_buffer markEncodingError:kIOReturnNotReady];
        return NO;
    }
    return YES;
}
- (BOOL)validateTexture:(id)texture
{
    if (![texture isKindOfClass:[A5MaliMetalTexture class]] ||
        ((A5MaliMetalTexture *)texture).device != _buffer.device ||
        ![(A5MaliMetalTexture *)texture privateSurface]) {
        [_buffer markEncodingError:kIOReturnBadArgument];
        return NO;
    }
    A5MaliMetalTexture *t = texture;
    if (t.textureType != MTLTextureType2D || t.pixelFormat != MTLPixelFormatBGRA8Unorm ||
        !t.width || !t.height || t.mipmapLevelCount != 1 ||
        t.arrayLength != 1 || t.sampleCount != 1 ||
        t.storageMode != MTLStorageModeShared) {
        [_buffer markEncodingError:kIOReturnUnsupported];
        return NO;
    }
    return YES;
}
- (void)rejectUnsupportedOperation
{
    if ([self validateActive]) [_buffer markEncodingError:kIOReturnUnsupported];
}
- (void)generateMipmapsForTexture:(A5MaliMetalTexture *)texture
{
    /* A genuine single-level texture has no lower mip to produce. Multiple
     * levels are not allocated or generated by this backend. In particular,
     * a rejected factory's nil result must not become a successful command. */
    if (![self validateActive] || ![self validateTexture:texture]) return;
}
- (void)optimizeContentsForGPUAccess:(A5MaliMetalTexture *)texture
{
    /* This is a performance hint. The fixed IOSurface layout has no alternate
     * CPU/GPU swizzle to select, so preserving its layout is a valid choice. */
    if (![self validateActive] || ![self validateTexture:texture]) return;
}
- (void)optimizeContentsForGPUAccess:(A5MaliMetalTexture *)texture
    slice:(NSUInteger)slice level:(NSUInteger)level
{
    if (![self validateActive] || ![self validateTexture:texture]) return;
    if (slice || level) [_buffer markEncodingError:kIOReturnBadArgument];
}
- (void)optimizeContentsForCPUAccess:(A5MaliMetalTexture *)texture
{ [self optimizeContentsForGPUAccess:texture]; }
- (void)optimizeContentsForCPUAccess:(A5MaliMetalTexture *)texture
    slice:(NSUInteger)slice level:(NSUInteger)level
{ [self optimizeContentsForGPUAccess:texture slice:slice level:level]; }
- (void)insertDebugSignpost:(NSString *)string
{
    if (![self validateActive]) return;
    if (![string isKindOfClass:[NSString class]])
        [_buffer markEncodingError:kIOReturnBadArgument];
}
- (void)pushDebugGroup:(NSString *)string
{
    if (![self validateActive]) return;
    if (![string isKindOfClass:[NSString class]])
        [_buffer markEncodingError:kIOReturnBadArgument];
    else [_debugGroups addObject:[string copy]];
}
- (void)popDebugGroup
{
    if (![self validateActive]) return;
    if (!_debugGroups.count) [_buffer markEncodingError:kIOReturnBadArgument];
    else [_debugGroups removeLastObject];
}

- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
    toTexture:(A5MaliMetalTexture *)destinationTexture
{
    [self copyFromTexture:sourceTexture sourceSlice:0 sourceLevel:0
        toTexture:destinationTexture destinationSlice:0 destinationLevel:0
        sliceCount:1 levelCount:1];
}
- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
    sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
    toTexture:(A5MaliMetalTexture *)destinationTexture
    destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
    sliceCount:(NSUInteger)sliceCount levelCount:(NSUInteger)levelCount
{
    if (![self validateActive] || ![self validateTexture:sourceTexture] ||
        ![self validateTexture:destinationTexture]) return;
    if (sourceSlice || sourceLevel || destinationSlice || destinationLevel ||
        sliceCount != 1 || levelCount != 1 ||
        sourceTexture.width != destinationTexture.width ||
        sourceTexture.height != destinationTexture.height) {
        [_buffer markEncodingError:kIOReturnUnsupported];
        return;
    }
    [self copyFromTexture:sourceTexture sourceSlice:0 sourceLevel:0
        sourceOrigin:MTLOriginMake(0, 0, 0)
        sourceSize:MTLSizeMake(sourceTexture.width, sourceTexture.height, 1)
        toTexture:destinationTexture destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
}

- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
            sourceSlice:(NSUInteger)sourceSlice
            sourceLevel:(NSUInteger)sourceLevel
           sourceOrigin:(MTLOrigin)sourceOrigin
             sourceSize:(MTLSize)sourceSize
              toTexture:(A5MaliMetalTexture *)destinationTexture
       destinationSlice:(NSUInteger)destinationSlice
       destinationLevel:(NSUInteger)destinationLevel
      destinationOrigin:(MTLOrigin)destinationOrigin
{
    if (![self validateActive] || ![self validateTexture:sourceTexture] ||
        ![self validateTexture:destinationTexture]) return;
    if (sourceSlice || sourceLevel || destinationSlice || destinationLevel ||
        sourceOrigin.z || destinationOrigin.z || sourceSize.depth != 1 ||
        !sourceSize.width || !sourceSize.height ||
        sourceOrigin.x > UINT32_MAX || sourceOrigin.y > UINT32_MAX ||
        destinationOrigin.x > UINT32_MAX ||
        destinationOrigin.y > UINT32_MAX ||
        sourceSize.width > UINT32_MAX || sourceSize.height > UINT32_MAX) {
        [_buffer markEncodingError:kIOReturnUnsupported];
        return;
    }
    A5MaliRect source = {(uint32_t)sourceOrigin.x, (uint32_t)sourceOrigin.y,
        (uint32_t)sourceSize.width, (uint32_t)sourceSize.height};
    A5MaliRect destination = {(uint32_t)destinationOrigin.x,
        (uint32_t)destinationOrigin.y, source.width, source.height};
    if (![[_buffer privateBuffer] encodeCopy:[sourceTexture privateSurface]
        sourceRect:source to:[destinationTexture privateSurface]
        destinationRect:destination])
        [_buffer markEncodingError:kIOReturnBadArgument];
}

/* Required iOS16 blit operations not backed by a typed kernel operation fail
 * the command buffer. They never copy CPU shadow bytes or pretend a fence or
 * counter exists. Pointer/offset arguments are deliberately not dereferenced. */
- (void)copyFromBuffer:(id<MTLBuffer>)source sourceOffset:(NSUInteger)sourceOffset
    toBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)destinationOffset
    size:(NSUInteger)size
{ (void)source; (void)sourceOffset; (void)destination; (void)destinationOffset;
  (void)size; [self rejectUnsupportedOperation]; }
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value
{ (void)buffer; (void)range; (void)value; [self rejectUnsupportedOperation]; }
- (void)copyFromBuffer:(id<MTLBuffer>)source sourceOffset:(NSUInteger)offset
    sourceBytesPerRow:(NSUInteger)row sourceBytesPerImage:(NSUInteger)image
    sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)destination
    destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level
    destinationOrigin:(MTLOrigin)origin
{ (void)source; (void)offset; (void)row; (void)image; (void)size;
  (void)destination; (void)slice; (void)level; (void)origin;
  [self rejectUnsupportedOperation]; }
- (void)copyFromBuffer:(id<MTLBuffer>)source sourceOffset:(NSUInteger)offset
    sourceBytesPerRow:(NSUInteger)row sourceBytesPerImage:(NSUInteger)image
    sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)destination
    destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level
    destinationOrigin:(MTLOrigin)origin options:(MTLBlitOption)options
{ (void)options; [self copyFromBuffer:source sourceOffset:offset sourceBytesPerRow:row
    sourceBytesPerImage:image sourceSize:size toTexture:destination
    destinationSlice:slice destinationLevel:level destinationOrigin:origin]; }
- (void)copyFromTexture:(id<MTLTexture>)source sourceSlice:(NSUInteger)slice
    sourceLevel:(NSUInteger)level sourceOrigin:(MTLOrigin)origin sourceSize:(MTLSize)size
    toBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)offset
    destinationBytesPerRow:(NSUInteger)row destinationBytesPerImage:(NSUInteger)image
{ (void)source; (void)slice; (void)level; (void)origin; (void)size;
  (void)destination; (void)offset; (void)row; (void)image;
  [self rejectUnsupportedOperation]; }
- (void)copyFromTexture:(id<MTLTexture>)source sourceSlice:(NSUInteger)slice
    sourceLevel:(NSUInteger)level sourceOrigin:(MTLOrigin)origin sourceSize:(MTLSize)size
    toBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)offset
    destinationBytesPerRow:(NSUInteger)row destinationBytesPerImage:(NSUInteger)image
    options:(MTLBlitOption)options
{ (void)options; [self copyFromTexture:source sourceSlice:slice sourceLevel:level
    sourceOrigin:origin sourceSize:size toBuffer:destination destinationOffset:offset
    destinationBytesPerRow:row destinationBytesPerImage:image]; }
- (void)synchronizeResource:(id<MTLResource>)resource
{ (void)resource; [self rejectUnsupportedOperation]; }
- (void)synchronizeTexture:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level
{ (void)texture; (void)slice; (void)level; [self rejectUnsupportedOperation]; }
- (void)updateFence:(id<MTLFence>)fence
{ (void)fence; [self rejectUnsupportedOperation]; }
- (void)waitForFence:(id<MTLFence>)fence
{ (void)fence; [self rejectUnsupportedOperation]; }
- (void)getTextureAccessCounters:(id<MTLTexture>)texture region:(MTLRegion)region
    mipLevel:(NSUInteger)mipLevel slice:(NSUInteger)slice resetCounters:(BOOL)resetCounters
    countersBuffer:(id<MTLBuffer>)buffer countersBufferOffset:(NSUInteger)offset
{ (void)texture; (void)region; (void)mipLevel; (void)slice; (void)resetCounters;
  (void)buffer; (void)offset; [self rejectUnsupportedOperation]; }
- (void)resetTextureAccessCounters:(id<MTLTexture>)texture region:(MTLRegion)region
    mipLevel:(NSUInteger)mipLevel slice:(NSUInteger)slice
{ (void)texture; (void)region; (void)mipLevel; (void)slice; [self rejectUnsupportedOperation]; }
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>)buffer withRange:(NSRange)range
{ (void)buffer; (void)range; [self rejectUnsupportedOperation]; }
- (void)copyIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)source sourceRange:(NSRange)range
    destination:(id<MTLIndirectCommandBuffer>)destination destinationIndex:(NSUInteger)index
{ (void)source; (void)range; (void)destination; (void)index; [self rejectUnsupportedOperation]; }
- (void)optimizeIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)buffer withRange:(NSRange)range
{ (void)buffer; (void)range; [self rejectUnsupportedOperation]; }
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)buffer
    atSampleIndex:(NSUInteger)index withBarrier:(BOOL)barrier
{ (void)buffer; (void)index; (void)barrier; [self rejectUnsupportedOperation]; }
- (void)resolveCounters:(id<MTLCounterSampleBuffer>)buffer inRange:(NSRange)range
    destinationBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)offset
{ (void)buffer; (void)range; (void)destination; (void)offset; [self rejectUnsupportedOperation]; }

- (void)endEncoding
{
    if (!_ended) {
        _ended = YES;
        [_buffer finishEncoding];
    }
}

@end
