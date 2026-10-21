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
typedef struct { uint32_t batches, releases, expectedOperation; } Fake;

@interface NamedFunctionFixture : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) MTLFunctionType functionType;
@end
@implementation NamedFunctionFixture
@end

static kern_return_t mock(void *opaque, uint32_t selector, const void *input,
    size_t inputSize, void *output, size_t *outputSize)
{
    Fake *fake = opaque;
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
    assert([error.localizedDescription containsString:@"unverified"]);
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
        A5MaliMetalTexture *source = [withShader hostTestTextureWithResource:
            (A5MaliResource){0x100000021ULL, 1080, 1920, 4320,
                A5MaliRead}];
        A5MaliMetalTexture *destination =
            [withShader hostTestTextureWithResource:
                (A5MaliResource){0x100000022ULL, 1080, 1920, 4320,
                    A5MaliWrite}];
        renderCandidate(withShader, candidate, source, destination, YES);
        assert(renderFake.batches == 1);
    }
    assert(renderFake.releases == 4);
    return 0;
}
