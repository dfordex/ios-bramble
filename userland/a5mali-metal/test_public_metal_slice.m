/* SPDX-License-Identifier: MIT
 * Public Metal copy-call smoke path with only the device/resources injected.
 */
#import <Metal/Metal.h>
#import "A5MaliRestrictedDevice.h"
#include <assert.h>
#include <string.h>

typedef struct { A5MaliHeader h; uint32_t count, reserved; uint8_t commands[448]; } BatchRequest;
typedef struct { uint32_t status, reserved; uint64_t tilerFence, fragmentFence; } BatchItem;
typedef struct {
    A5MaliHeader h; uint32_t count, completedCount, failedIndex, reserved;
    BatchItem items[8];
} BatchReply;
typedef struct { A5MaliHeader h; uint64_t token; } HandleRequest;
typedef struct { A5MaliHeader h; uint32_t port, usage; uint64_t reserved; } ImportRequest;
typedef struct {
    A5MaliHeader h; uint64_t handle; uint32_t width, height, rowBytes, format;
} ImportReply;
typedef struct { A5MaliHeader h; uint64_t token; uint32_t mappedBytes, flags; } MapReply;
typedef struct {
    uint32_t batches, releases, expectedOperation;
    uint32_t imports, importWidth, importHeight, importRow;
} Fake;

@interface NamedFunctionFixture : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) MTLFunctionType functionType;
@end
@implementation NamedFunctionFixture
@end

@interface A5MaliMetalTexture (TestBacking)
- (A5MaliSurface *)privateSurface;
@end
@interface TextureShapeFixture : A5MaliMetalTexture
@property (nonatomic, strong) A5MaliMetalTexture *backing;
@property (nonatomic, strong) A5MaliRestrictedDevice *fixtureDevice;
@property (nonatomic) NSUInteger fixtureLevels;
@end
@implementation TextureShapeFixture
- (A5MaliRestrictedDevice *)device { return self.fixtureDevice ?: self.backing.device; }
- (A5MaliSurface *)privateSurface { return [self.backing privateSurface]; }
- (NSUInteger)width { return self.backing.width; }
- (NSUInteger)height { return self.backing.height; }
- (NSUInteger)mipmapLevelCount { return self.fixtureLevels; }
@end

static kern_return_t mock(void *opaque, uint32_t selector, const void *input,
    size_t inputSize, void *output, size_t *outputSize)
{
    Fake *fake = opaque;
    if (selector == A5MaliImport) {
        assert(inputSize == sizeof(ImportRequest));
        const ImportRequest *request = input;
        assert(request->port && request->usage);
        ImportReply reply = {{1, sizeof(reply), 0, 0},
            0x100000100ULL + fake->imports, fake->importWidth,
            fake->importHeight, fake->importRow, 0x42475241};
        assert(output && *outputSize == sizeof(reply));
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        ++fake->imports;
        return KERN_SUCCESS;
    }
    if (selector == A5MaliMap) {
        assert(inputSize == sizeof(HandleRequest));
        const HandleRequest *request = input;
        MapReply reply = {{1, sizeof(reply), 0, 0}, request->token,
            fake->importRow * fake->importHeight, A5MaliRead | A5MaliWrite};
        assert(output && *outputSize == sizeof(reply));
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        return KERN_SUCCESS;
    }
    if (selector == A5MaliBatchSubmit) {
        assert(inputSize == 472 && output && *outputSize == 224);
        const BatchRequest *request = input;
        assert(request->count == 1);
        uint32_t operation = 0;
        memcpy(&operation, request->commands, sizeof(operation));
        assert(operation == fake->expectedOperation);
        BatchReply reply = {0};
        reply.h = (A5MaliHeader){1, sizeof(reply), 0, 0};
        reply.count = reply.completedCount = 1;
        reply.failedIndex = UINT32_MAX;
        reply.items[0].fragmentFence = 123;
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        ++fake->batches;
        return KERN_SUCCESS;
    }
    if (selector == A5MaliUnmap || selector == A5MaliRelease) {
        assert(inputSize == sizeof(HandleRequest) && !output);
        if (selector == A5MaliRelease) ++fake->releases;
        return KERN_SUCCESS;
    }
    assert(0 && "unexpected selector");
    return KERN_INVALID_ARGUMENT;
}

/* Only setup is private. The command path below uses public Metal calls. */
static void smoke(id<MTLDevice> device, id<MTLTexture> source,
    id<MTLTexture> destination)
{
    assert(source.width == 64 && destination.height == 64);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    assert(queue);
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    assert(buffer && buffer.status == MTLCommandBufferStatusNotEnqueued);
    __block uint32_t scheduled = 0, completed = 0;
    [buffer addScheduledHandler:^(id<MTLCommandBuffer> b) {
        assert(b.status == MTLCommandBufferStatusCompleted);
        ++scheduled;
    }];
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> b) {
        assert(b.status == MTLCommandBufferStatusCompleted);
        ++completed;
    }];
    id<MTLBlitCommandEncoder> blit = [buffer blitCommandEncoder];
    assert(blit);
    [blit copyFromTexture:source sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(2, 3, 0)
               sourceSize:MTLSizeMake(16, 16, 1)
                toTexture:destination destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(4, 5, 0)];
    [blit endEncoding];
    [buffer commit];
    [buffer waitUntilCompleted];
    assert(buffer.status == MTLCommandBufferStatusCompleted && !buffer.error);
    assert(scheduled == 1 && completed == 1);
}

static void unsupportedGeometry(id<MTLDevice> device, id<MTLTexture> source,
    id<MTLTexture> destination)
{
    id<MTLCommandBuffer> buffer = [[device newCommandQueue] commandBuffer];
    id<MTLBlitCommandEncoder> blit = [buffer blitCommandEncoder];
    [blit copyFromTexture:source sourceSlice:1 sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(4, 4, 1)
                toTexture:destination destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
    [buffer commit];
    assert(buffer.status == MTLCommandBufferStatusError && buffer.error);
}

static A5MaliReadSurfCandidate *inspectReadSurfCandidate(
    A5MaliRestrictedDevice *device)
{
    MTLRenderPipelineDescriptor *descriptor =
        [MTLRenderPipelineDescriptor new];
    NamedFunctionFixture *vertex = [NamedFunctionFixture new];
    vertex.name = @"read_surf_vert";
    vertex.functionType = MTLFunctionTypeVertex;
    NamedFunctionFixture *fragment = [NamedFunctionFixture new];
    fragment.name = @"read_surf_frag";
    fragment.functionType = MTLFunctionTypeFragment;
    descriptor.vertexFunction = (id<MTLFunction>)vertex;
    descriptor.fragmentFunction = (id<MTLFunction>)fragment;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
    assert(A5MaliInspectReadSurfPipelineDescriptor(descriptor) ==
        A5MaliPipelineShapeReadSurfCandidate);
    A5MaliReadSurfCandidate *candidate =
        [device newPrivateReadSurfCandidateWithDescriptor:descriptor];
    assert(candidate);
    NSError *error = nil;
    assert(![device newRenderPipelineStateWithDescriptor:descriptor
        error:&error] && error.code == kIOReturnUnsupported);
    assert([error.localizedDescription containsString:@"exact QuartzCore"]);
    descriptor.colorAttachments[0].blendingEnabled = YES;
    assert(A5MaliInspectReadSurfPipelineDescriptor(descriptor) ==
        A5MaliPipelineShapeUnsupported);
    error = nil;
    assert(![device newRenderPipelineStateWithDescriptor:descriptor
        error:&error] && error.code == kIOReturnUnsupported);
    return candidate;
}

static void renderCandidate(A5MaliRestrictedDevice *device,
    A5MaliReadSurfCandidate *pipeline, A5MaliMetalTexture *source,
    A5MaliMetalTexture *destination, BOOL supported)
{
    A5MaliMetalBuffer *buffer = [[device newCommandQueue] commandBuffer];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor new];
    pass.colorAttachments[0].texture = (id<MTLTexture>)destination;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    A5MaliMetalRenderEncoder *encoder =
        [buffer renderCommandEncoderWithDescriptor:pass];
    if (!supported) {
        assert(!encoder);
        [buffer commit];
        assert(buffer.status == MTLCommandBufferStatusError && buffer.error);
        return;
    }
    assert(encoder);
    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:source atIndex:0];
    [encoder setViewport:(MTLViewport){0, 0, 1080, 1920, 0, 1}];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
        vertexCount:3];
    [encoder endEncoding];
    [buffer commit];
    assert(buffer.status == MTLCommandBufferStatusCompleted && !buffer.error);
}

static void renderRows(A5MaliRestrictedDevice *device,
    A5MaliReadSurfCandidate *pipeline, Fake *fake, uint32_t sourceRow,
    uint32_t destinationRow, BOOL accepted)
{
    A5MaliMetalTexture *source = [device hostTestTextureWithResource:
        (A5MaliResource){0x100000031ULL, 1080, 1920, sourceRow, A5MaliRead}];
    A5MaliMetalTexture *destination = [device hostTestTextureWithResource:
        (A5MaliResource){0x100000032ULL, 1080, 1920, destinationRow, A5MaliWrite}];
    A5MaliMetalBuffer *buffer = [[device newCommandQueue] commandBuffer];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor new];
    pass.colorAttachments[0].texture = (id<MTLTexture>)destination;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    A5MaliMetalRenderEncoder *encoder =
        [buffer renderCommandEncoderWithDescriptor:pass];
    assert(encoder);
    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:source atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    uint32_t before = fake->batches;
    [buffer commit];
    [buffer waitUntilCompleted];
    assert(buffer.status == (accepted ? MTLCommandBufferStatusCompleted :
        MTLCommandBufferStatusError));
    assert((buffer.error == nil) == accepted);
    assert(fake->batches == before + (accepted ? 1 : 0));
}

static void importPaddedRows(void)
{
    Fake fake = {.importWidth = 1080, .importHeight = 1920, .importRow = 4352};
    @autoreleasepool {
        A5MaliRestrictedDevice *device = [[A5MaliRestrictedDevice alloc]
            initWithTransport:mock context:&fake];
        NSDictionary *properties = @{
            (__bridge id)kIOSurfaceWidth: @1080,
            (__bridge id)kIOSurfaceHeight: @1920,
            (__bridge id)kIOSurfaceBytesPerElement: @4,
            (__bridge id)kIOSurfaceBytesPerRow: @4352,
            (__bridge id)kIOSurfacePixelFormat: @(0x42475241u),
        };
        IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
        assert(surface && IOSurfaceGetBytesPerRow(surface) == 4352);
        assert(IOSurfaceGetAllocSize(surface) >= 4352 * 1920);
        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
            width:1080 height:1920 mipmapped:NO];
        descriptor.storageMode = MTLStorageModeShared;
        descriptor.usage = MTLTextureUsageShaderRead;
        A5MaliMetalTexture *texture = [device newTextureWithDescriptor:descriptor
            iosurface:surface plane:0];
        assert(texture && [texture privateSurface].rowBytes == 4352);
        assert(fake.imports == 1);
        descriptor.width = 1081;
        assert(![device newTextureWithDescriptor:descriptor iosurface:surface plane:0]);
        assert(fake.imports == 1);
        CFRelease(surface);
    }
    assert(fake.releases == 1);
}

static A5MaliReadSurfCandidate *authenticatedCandidate(
    A5MaliRestrictedDevice *device, const char *path)
{
    NSError *error = nil;
    A5MaliMetalLibrary *library = [device newLibraryWithURL:
        [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]
        error:&error];
    assert(library && !error);
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = (id<MTLFunction>)
        [library newFunctionWithName:@"read_surf_vert"];
    desc.fragmentFunction = (id<MTLFunction>)
        [library newFunctionWithName:@"read_surf_frag"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
    id result = [device newRenderPipelineStateWithDescriptor:desc error:&error];
    assert([result isKindOfClass:[A5MaliReadSurfCandidate class]] && !error);
    return result;
}

static void configuredDispatchQueue(A5MaliRestrictedDevice *device,
    A5MaliMetalTexture *source, A5MaliMetalTexture *destination, Fake *fake)
{
    static char completionKey;
    A5MaliMetalQueue *queue = [device newCommandQueue];
    dispatch_queue_t submit = dispatch_queue_create("a5.test.submit", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t completion = dispatch_queue_create("a5.test.complete", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(completion, &completionKey, &completionKey, NULL);
    dispatch_suspend(submit);
    [queue setSubmissionQueue:submit];
    [queue setCompletionQueue:completion];
    assert(queue.submissionQueue == submit && queue.completionQueue == completion);
    /* QuartzCore releases its references immediately after these setters. */
    submit = nil;
    completion = nil;
    dispatch_semaphore_t callbacks = dispatch_semaphore_create(0);
    __block NSUInteger completed = 0;
    uint32_t before = fake->batches;
    NSMutableArray *buffers = [NSMutableArray new];
    for (NSUInteger sequence = 0; sequence < 2; ++sequence) {
        A5MaliMetalBuffer *buffer = [queue commandBuffer];
        A5MaliMetalBlitEncoder *encoder = [buffer blitCommandEncoder];
        [encoder copyFromTexture:source sourceSlice:0 sourceLevel:0
            sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(16, 16, 1)
            toTexture:destination destinationSlice:0 destinationLevel:0
            destinationOrigin:MTLOriginMake(0, 0, 0)];
        [encoder endEncoding];
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> result) {
            assert(dispatch_get_specific(&completionKey) == &completionKey);
            assert(result.status == MTLCommandBufferStatusCompleted);
            assert(completed == sequence);
            ++completed;
            dispatch_semaphore_signal(callbacks);
        }];
        [buffer commit];
        assert(buffer.status == MTLCommandBufferStatusCommitted);
        [buffers addObject:buffer];
    }
    assert(fake->batches == before);
    dispatch_resume(queue.submissionQueue);
    for (NSUInteger i = 0; i < 2; ++i)
        assert(dispatch_semaphore_wait(callbacks,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    for (A5MaliMetalBuffer *buffer in buffers) [buffer waitUntilCompleted];
    assert(fake->batches == before + 2 && completed == 2);
    dispatch_sync(queue.completionQueue, ^{});
}

static void failedBlit(A5MaliRestrictedDevice *device, Fake *fake,
    void (^operation)(id<MTLBlitCommandEncoder>))
{
    uint32_t before = fake->batches;
    A5MaliMetalBuffer *buffer = [[device newCommandQueue] commandBuffer];
    id<MTLBlitCommandEncoder> encoder = (id)[buffer blitCommandEncoder];
    operation(encoder);
    [encoder endEncoding];
    [buffer commit];
    assert(buffer.status == MTLCommandBufferStatusError && buffer.error);
    assert(fake->batches == before);
}
static void blitFamily(A5MaliRestrictedDevice *device, A5MaliMetalTexture *source,
    A5MaliMetalTexture *destination, Fake *fake)
{
    uint32_t before = fake->batches;
    A5MaliMetalBuffer *buffer = [[device newCommandQueue] commandBuffer];
    id<MTLBlitCommandEncoder> encoder = (id)[buffer blitCommandEncoder];
    assert(encoder.device == (id)device);
    encoder.label = @"one-level texture initialization";
    assert([encoder.label isEqualToString:@"one-level texture initialization"]);
    [encoder pushDebugGroup:@"one-level group"];
    [encoder insertDebugSignpost:@"mipmap has no destination level"];
    [encoder generateMipmapsForTexture:(id)source];
    [encoder optimizeContentsForGPUAccess:(id)source];
    [encoder optimizeContentsForCPUAccess:(id)source slice:0 level:0];
    [encoder popDebugGroup];
    [encoder endEncoding];
    [buffer commit];
    assert(buffer.status == MTLCommandBufferStatusCompleted && !buffer.error);
    assert(fake->batches == before); /* no fake GPU mipmap or optimization job */

    id absentTexture = nil;
    id unsupportedResource = [NSObject new];
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e generateMipmapsForTexture:absentTexture];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e generateMipmapsForTexture:(id)[NSObject new]];
    });
    TextureShapeFixture *multiple = [TextureShapeFixture new];
    multiple.backing = source;
    multiple.fixtureLevels = 2;
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e generateMipmapsForTexture:(id)multiple];
    });
    TextureShapeFixture *foreign = [TextureShapeFixture new];
    foreign.backing = source;
    foreign.fixtureLevels = 1;
    foreign.fixtureDevice = [A5MaliRestrictedDevice new];
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e generateMipmapsForTexture:(id)foreign];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e endEncoding];
        [e generateMipmapsForTexture:(id)source];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e optimizeContentsForGPUAccess:(id)source slice:1 level:0];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e copyFromTexture:(id)source sourceSlice:0 sourceLevel:0
            toTexture:(id)destination destinationSlice:0 destinationLevel:0
            sliceCount:1 levelCount:2];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) { [e popDebugGroup]; });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e copyFromTexture:(id)source toTexture:(id)destination];
        [e fillBuffer:unsupportedResource range:NSMakeRange(NSUIntegerMax, NSUIntegerMax) value:42];
    }); /* An unsupported operation prevents submission of earlier recorded work. */
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e copyFromBuffer:unsupportedResource sourceOffset:0
            toBuffer:unsupportedResource destinationOffset:0 size:16];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e updateFence:unsupportedResource];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e waitForFence:unsupportedResource];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e copyFromBuffer:unsupportedResource sourceOffset:0 sourceBytesPerRow:4 sourceBytesPerImage:4
            sourceSize:MTLSizeMake(1, 1, 1) toTexture:(id)destination
            destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)
            options:MTLBlitOptionNone];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e copyFromTexture:(id)source sourceSlice:0 sourceLevel:0
            sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(1, 1, 1)
            toBuffer:unsupportedResource destinationOffset:0 destinationBytesPerRow:4
            destinationBytesPerImage:4 options:MTLBlitOptionNone];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e resetCommandsInBuffer:unsupportedResource withRange:NSMakeRange(0, 1)];
    });
    failedBlit(device, fake, ^(id<MTLBlitCommandEncoder> e) {
        [e sampleCountersInBuffer:unsupportedResource atSampleIndex:0 withBarrier:YES];
    });
    assert(fake->batches == before);
    for (NSUInteger variant = 0; variant < 2; ++variant) {
        buffer = [[device newCommandQueue] commandBuffer];
        encoder = (id)[buffer blitCommandEncoder];
        if (variant)
            [encoder copyFromTexture:(id)source sourceSlice:0 sourceLevel:0
                toTexture:(id)destination destinationSlice:0 destinationLevel:0
                sliceCount:1 levelCount:1];
        else [encoder copyFromTexture:(id)source toTexture:(id)destination];
        [encoder endEncoding];
        [buffer commit];
        assert(buffer.status == MTLCommandBufferStatusCompleted && !buffer.error);
    }
    assert(fake->batches == before + 2);

    /* iOS16 encoder entry points must reject unsupported work through the
     * command-buffer error channel rather than abort on a missing selector. */
    NSArray<NSString *> *selectors = @[
        @"copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:",
        @"copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:options:",
        @"copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:",
        @"copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:options:",
        @"synchronizeResource:", @"synchronizeTexture:slice:level:",
        @"getTextureAccessCounters:region:mipLevel:slice:resetCounters:countersBuffer:countersBufferOffset:",
        @"resetTextureAccessCounters:region:mipLevel:slice:",
        @"copyIndirectCommandBuffer:sourceRange:destination:destinationIndex:",
        @"optimizeIndirectCommandBuffer:withRange:",
        @"resolveCounters:inRange:destinationBuffer:destinationOffset:"
    ];
    for (NSString *selector in selectors)
        assert([(id)encoder respondsToSelector:NSSelectorFromString(selector)]);
}

int main(void)
{
        Fake fake = {.expectedOperation = A5MaliCopyBGRA};
    @autoreleasepool {
        A5MaliRestrictedDevice *device = [[A5MaliRestrictedDevice alloc]
            initWithTransport:mock context:&fake];
        assert(device);
        A5MaliReadSurfCandidate *candidate =
            inspectReadSurfCandidate(device);
        assert(candidate);
        id source = [device hostTestTextureWithResource:
            (A5MaliResource){0x100000001ULL, 64, 64, 256, A5MaliRead}];
        id destination = [device hostTestTextureWithResource:
            (A5MaliResource){0x100000002ULL, 64, 64, 256, A5MaliWrite}];
        smoke((id<MTLDevice>)device, (id<MTLTexture>)source,
            (id<MTLTexture>)destination);
        unsupportedGeometry((id<MTLDevice>)device, (id<MTLTexture>)source,
            (id<MTLTexture>)destination);
        assert(fake.batches == 1);
        configuredDispatchQueue(device, source, destination, &fake);
        assert(fake.batches == 3);
        blitFamily(device, source, destination, &fake);
        assert(fake.batches == 5);
        source = nil;
        destination = nil;
        device = nil;
    }
    assert(fake.releases == 2);
    Fake renderFake = {.expectedOperation = A5MaliReadSurfBGRA};
    @autoreleasepool {
        A5MaliRestrictedDevice *noShader = [[A5MaliRestrictedDevice alloc]
            initWithTransport:mock context:&renderFake
            commandCapabilities:15];
        A5MaliReadSurfCandidate *candidate =
            inspectReadSurfCandidate(noShader);
        A5MaliMetalTexture *source = [noShader hostTestTextureWithResource:
            (A5MaliResource){0x100000011ULL, 1080, 1920, 4320,
                A5MaliRead}];
        A5MaliMetalTexture *destination =
            [noShader hostTestTextureWithResource:
                (A5MaliResource){0x100000012ULL, 1080, 1920, 4320,
                    A5MaliWrite}];
        renderCandidate(noShader, candidate, source, destination, NO);
        assert(renderFake.batches == 0);
    }
    assert(renderFake.releases == 2);
    @autoreleasepool {
        A5MaliRestrictedDevice *withShader = [[A5MaliRestrictedDevice alloc]
            initWithTransport:mock context:&renderFake
            commandCapabilities:31];
        A5MaliReadSurfCandidate *candidate =
            inspectReadSurfCandidate(withShader);
        const char *metallib = getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");
        if (metallib) candidate = authenticatedCandidate(withShader, metallib);
        A5MaliMetalTexture *source = [withShader hostTestTextureWithResource:
            (A5MaliResource){0x100000021ULL, 1080, 1920, 4320,
                A5MaliRead}];
        A5MaliMetalTexture *destination =
            [withShader hostTestTextureWithResource:
                (A5MaliResource){0x100000022ULL, 1080, 1920, 4320,
                    A5MaliWrite}];
        renderCandidate(withShader, candidate, source, destination, YES);
        assert(renderFake.batches == 1);
        renderRows(withShader, candidate, &renderFake, 4352, 4352, YES);
        renderRows(withShader, candidate, &renderFake, 4352, 4320, YES);
        renderRows(withShader, candidate, &renderFake, 4320, 4352, YES);
        renderRows(withShader, candidate, &renderFake, 4316, 4352, NO);
        renderRows(withShader, candidate, &renderFake, 4352, 4316, NO);
        renderRows(withShader, candidate, &renderFake, 4324, 4352, NO);
        renderRows(withShader, candidate, &renderFake, 4352, 8208, NO);
    }
    assert(renderFake.releases == 18);
    importPaddedRows();
    return 0;
}
