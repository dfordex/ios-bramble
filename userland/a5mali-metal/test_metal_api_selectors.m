/* SPDX-License-Identifier: MIT
 * Public Metal selector and terminal-error coverage; no GPU success implied.
 */
#import "A5MaliRestrictedDevice.h"
#include <assert.h>
#include <stdio.h>

@interface A5MaliRestrictedDevice (SelectorTestTransport)
- (instancetype)initWithTransport:(A5MaliTransport)transport context:(void *)context
             commandCapabilities:(uint32_t)commands operationCapabilities:(uint32_t)operations;
@end

@interface A5MaliReadSurfCandidate (SelectorTestInit)
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device;
@end
@interface A5MaliMetalRenderEncoder (SelectorTestInit)
- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer
                   attachments:(NSDictionary *)attachments;
- (void)setViewports:(const MTLViewport *)viewports count:(NSUInteger)count;
- (void)setScissorRects:(const MTLScissorRect *)scissorRects count:(NSUInteger)count;
- (void)setMeshTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index;
@end

static kern_return_t noDeviceCall(void *context, uint32_t selector,
    const void *input, size_t inputBytes, void *output, size_t *outputBytes)
{
    (void)context; (void)selector; (void)input; (void)inputBytes;
    (void)output; (void)outputBytes;
    assert(!"selector test must not submit GPU work");
    return kIOReturnUnsupported;
}

static void assertRejected(A5MaliMetalBuffer *buffer)
{
    __block unsigned completions=0;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        assert((id)completed==(id)buffer);
        ++completions;
    }];
    [buffer commit];
    [buffer waitUntilCompleted];
    assert(buffer.status==MTLCommandBufferStatusError);
    assert(buffer.error && completions==1);
}

int main(void) { @autoreleasepool {
    int context=0;
    A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]
        initWithTransport:noDeviceCall context:&context commandCapabilities:0
        operationCapabilities:0];
    A5MaliMetalQueue *queue=[device newCommandQueue];
    assert(queue);
    MTLCommandBufferDescriptor *descriptor=[MTLCommandBufferDescriptor new];
    assert([queue commandBufferWithDescriptor:descriptor]);
    descriptor.retainedReferences=NO;
    assert(![queue commandBufferWithDescriptor:descriptor]);
    descriptor.retainedReferences=YES;
    descriptor.errorOptions=MTLCommandBufferErrorOptionEncoderExecutionStatus;
    assert(![queue commandBufferWithDescriptor:descriptor]);

    A5MaliMetalBuffer *blitBuffer=[queue commandBuffer];
    MTLBlitPassDescriptor *blitPass=[MTLBlitPassDescriptor blitPassDescriptor];
    A5MaliMetalBlitEncoder *blit=[blitBuffer blitCommandEncoderWithDescriptor:blitPass];
    assert(blit);
    [blit endEncoding];
    [blitBuffer pushDebugGroup:@"valid"];
    [blitBuffer popDebugGroup];
    assert(blitBuffer.errorOptions==MTLCommandBufferErrorOptionNone);
    assert(blitBuffer.logs==nil);
    assert(blitBuffer.debugSignposts.count==0);
    [blitBuffer commit]; [blitBuffer waitUntilCompleted];
    assert(blitBuffer.status==MTLCommandBufferStatusCompleted);

    A5MaliMetalBuffer *compute=[queue commandBuffer];
    assert(![compute computeCommandEncoder]);
    assertRejected(compute);
    A5MaliMetalBuffer *event=[queue commandBuffer];
    [event encodeSignalEvent:(id<MTLEvent>)[NSObject new] value:1];
    assertRejected(event);
    A5MaliMetalBuffer *present=[queue commandBuffer];
    [present presentDrawable:(id<MTLDrawable>)[NSObject new]];
    assertRejected(present);
    A5MaliMetalBuffer *unbalanced=[queue commandBuffer];
    [unbalanced popDebugGroup];
    assertRejected(unbalanced);
    A5MaliMetalBuffer *badBlit=[queue commandBuffer];
    assert(![badBlit blitCommandEncoderWithDescriptor:(id)[NSObject new]]);
    assertRejected(badBlit);
    A5MaliMetalBuffer *programTable=[queue commandBuffer];
    A5MaliMetalBlitEncoder *tableBlit=[programTable blitCommandEncoder];
    assert(tableBlit);
    assert(![tableBlit endEncodingAndRetrieveProgramAddressTable]);
    assertRejected(programTable);
    A5MaliMetalBuffer *renderBuffer=[queue commandBuffer];
    A5MaliMetalRenderEncoder *render=[[A5MaliMetalRenderEncoder alloc]
        initWithBuffer:renderBuffer attachments:@{}];
    MTLViewport viewport={0,0,32,32,0,1};
    [render setViewports:&viewport count:1];
    assert(!renderBuffer.error);
    MTLScissorRect rects[2]={{0,0,1,1},{1,1,1,1}};
    [render setScissorRects:rects count:2];
    [render setMeshTexture:(id<MTLTexture>)[NSObject new] atIndex:0];
    [render endEncoding];
    assertRejected(renderBuffer);

    A5MaliReadSurfCandidate *pipeline=[[A5MaliReadSurfCandidate alloc]
        initWithDevice:device];
    assert(pipeline.maxTotalThreadsPerThreadgroup==0);
    assert([pipeline imageblockMemoryLengthForDimensions:MTLSizeMake(8,8,1)]==0);
    assert(pipeline.maxTotalThreadsPerMeshThreadgroup==0);
    assert(pipeline.meshThreadExecutionWidth==0);
    assert(pipeline.gpuResourceID._impl==0);
    assert(![pipeline functionHandleWithFunction:(id<MTLFunction>)[NSObject new] stage:MTLRenderStageVertex]);
    assert(![pipeline newVisibleFunctionTableWithDescriptor:[MTLVisibleFunctionTableDescriptor new] stage:MTLRenderStageVertex]);
    assert(![pipeline newIntersectionFunctionTableWithDescriptor:[MTLIntersectionFunctionTableDescriptor new] stage:MTLRenderStageVertex]);
    NSError *error=nil;
    assert(![pipeline newRenderPipelineStateWithAdditionalBinaryFunctions:[MTLRenderPipelineFunctionsDescriptor new] error:&error]);
    assert(error);
    puts("Metal API selectors: unsupported commands reject at commit; metadata and debug groups respond");
} return 0; }
