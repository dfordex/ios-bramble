/* SPDX-License-Identifier: MIT
 * iOS16 SPI entry points outside the bounded Mali renderer. Signatures follow
 * STOCK_ACCEPTANCE_ABI.md; opaque caller storage is never written speculatively.
 */
#import "A5MaliMetalDeviceResources.h"

typedef struct { uint32_t words[3]; } A5MaliShaderSampleBuffer;
typedef struct {
    BOOL enabled;
    uint64_t count;
    void *functions;
} A5MaliImageFilterFunctionInfo;
struct MPSFunctionTable;

static NSError *spiUnsupported(NSString *operation)
{
    return [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
        code:kIOReturnUnsupported userInfo:@{NSLocalizedDescriptionKey:
            [operation stringByAppendingString:@" is unsupported by the bounded Mali backend"]}];
}
static void rejectSPI(NSString *operation)
{
    [NSException raise:NSInvalidArgumentException format:@"%@",
        spiUnsupported(operation).localizedDescription];
}

@implementation A5MaliRestrictedDevice (UnsupportedStockSPI)

/* _MTLDevice's native builders dereference Apple compiler/target metadata.
 * This backend has neither. The exact library/render delegates below are the
 * only accepted compilation paths; unsupported calls must not reach super. */
- (id)newPipelineLibraryWithFilePath:(NSString *)path error:(NSError **)error
{
    (void)path;
    if (error) *error = spiUnsupported(@"precompiled pipeline libraries");
    return nil;
}
- (id)newLibraryWithFile:(NSString *)path error:(NSError **)error
{
    if (![path isKindOfClass:[NSString class]] || !path.length) {
        if (error) *error = [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
            code:kIOReturnBadArgument userInfo:@{NSLocalizedDescriptionKey:
                @"metallib file path must be a nonempty string"}];
        return nil;
    }
    return [self newLibraryWithURL:[NSURL fileURLWithPath:path] error:error];
}
- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options
    completionHandler:(MTLNewLibraryCompletionHandler)handler
{
    (void)source; (void)options;
    if (handler) handler(nil, spiUnsupported(@"source compilation"));
}
- (id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options reflection:(MTLRenderPipelineReflection **)reflection
    error:(NSError **)error
{
    if (reflection) *reflection = nil;
    if (options) {
        if (error) *error = spiUnsupported(@"render pipeline reflection options");
        return nil;
    }
    return [self newRenderPipelineStateWithDescriptor:descriptor error:error];
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    completionHandler:(MTLNewRenderPipelineStateCompletionHandler)handler
{
    if (!handler) return;
    NSError *error = nil;
    id pipeline = [self newRenderPipelineStateWithDescriptor:descriptor error:&error];
    handler(pipeline, error);
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewRenderPipelineStateWithReflectionCompletionHandler)handler
{
    if (!handler) return;
    if (options) {
        handler(nil, nil, spiUnsupported(@"render pipeline reflection options"));
        return;
    }
    NSError *error = nil;
    id pipeline = [self newRenderPipelineStateWithDescriptor:descriptor error:&error];
    handler(pipeline, nil, error);
}
- (id)newComputePipelineStateWithFunction:(id<MTLFunction>)function
    options:(MTLPipelineOption)options reflection:(MTLComputePipelineReflection **)reflection
    error:(NSError **)error
{
    (void)function; (void)options;
    if (reflection) *reflection = nil;
    if (error) *error = spiUnsupported(@"compute pipelines");
    return nil;
}
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)function
    completionHandler:(MTLNewComputePipelineStateCompletionHandler)handler
{
    (void)function;
    if (handler) handler(nil, spiUnsupported(@"compute pipelines"));
}
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)function
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)handler
{
    (void)function; (void)options;
    if (handler) handler(nil, nil, spiUnsupported(@"compute pipelines"));
}
- (void)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)handler
{
    (void)descriptor; (void)options;
    if (handler) handler(nil, nil, spiUnsupported(@"compute pipelines"));
}

- (id)copyIOSurfaceSharedTextureProperties:(id)properties
{ (void)properties; return nil; }
- (NSUInteger)featureProfile { return NSUIntegerMax; }
- (NSUInteger)doubleFPConfig { return 0; }
- (NSUInteger)halfFPConfig { return 0; }
- (NSUInteger)singleFPConfig { return 0; }
- (id)indirectArgumentBufferDecodingData { return nil; }
- (void)setIndirectArgumentBufferDecodingData:(id)data
{ if (data) rejectSPI(@"indirect argument decoding"); }
- (BOOL)mapShaderSampleBufferWithBuffer:(A5MaliShaderSampleBuffer *)buffer
    capacity:(NSUInteger)capacity size:(NSUInteger)size
{ (void)buffer; (void)capacity; (void)size; return NO; }
- (void)unmapShaderSampleBuffer {}

- (A5MaliPrivateBuffer *)newBufferWithBytes:(const void *)bytes
    length:(NSUInteger)length options:(MTLResourceOptions)options
    gpuAddress:(uint64_t)address
{
    if (address) return nil;
    return [self newBufferWithBytes:bytes length:length options:options];
}
- (A5MaliPrivateBuffer *)newBufferWithBytesNoCopy:(void *)bytes
    length:(NSUInteger)length options:(MTLResourceOptions)options
    gpuAddress:(uint64_t)address
    deallocator:(void (^)(void *, NSUInteger))deallocator
{
    if (address) return nil;
    return [self newBufferWithBytesNoCopy:bytes length:length options:options
        deallocator:deallocator];
}
- (A5MaliPrivateBuffer *)newBufferWithLength:(NSUInteger)length
    options:(MTLResourceOptions)options gpuAddress:(uint64_t)address
{
    if (address) return nil;
    return [self newBufferWithLength:length options:options];
}
- (id)newBufferWithDescriptor:(id)descriptor
{ (void)descriptor; return nil; }
- (id)newBufferWithIOSurface:(IOSurfaceRef)surface
{ (void)surface; return nil; }
- (id)newIndirectArgumentBufferLayoutWithStructType:(id)type
{ (void)type; return nil; }
- (id)newIndirectArgumentEncoderWithArguments:(id)arguments
{ (void)arguments; return nil; }
- (id)newIndirectArgumentEncoderWithLayout:(id)layout
{ (void)layout; return nil; }
- (id)newIndirectCommandBufferWithDescriptor:(id)descriptor
    maxCount:(NSUInteger)count options:(MTLResourceOptions)options
{ (void)descriptor; (void)count; (void)options; return nil; }
- (id)newIndirectComputeCommandEncoderWithBuffer:(id)buffer
{ (void)buffer; return nil; }
- (id)newIndirectRenderCommandEncoderWithBuffer:(id)buffer
{ (void)buffer; return nil; }
- (id)newIntersectionFunctionTableWithDescriptor:(id)descriptor
{ (void)descriptor; return nil; }
- (id)newVisibleFunctionTableWithDescriptor:(id)descriptor
{ (void)descriptor; return nil; }
- (id)newLibraryWithCIFiltersForComputePipeline:(id)pipeline
    imageFilterFunctionInfo:(const A5MaliImageFilterFunctionInfo *)info
    error:(NSError **)error
{
    (void)pipeline; (void)info;
    if (error) *error = spiUnsupported(@"CoreImage compute libraries");
    return nil;
}
- (id)newLibraryWithGraphs:(id)graphs functions:(id)functions error:(NSError **)error
{
    (void)graphs; (void)functions;
    if (error) *error = spiUnsupported(@"graph libraries");
    return nil;
}
- (id)newLibraryWithGraphsSPI:(id)graphs functions:(id)functions error:(NSError **)error
{
    (void)graphs; (void)functions;
    if (error) *error = spiUnsupported(@"SPI graph libraries");
    return nil;
}
- (void)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    completionHandler:(MTLNewRenderPipelineStateCompletionHandler)handler
{
    (void)descriptor;
    if (handler) handler(nil, spiUnsupported(@"tile render pipelines"));
}
- (id)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    error:(NSError **)error
{
    (void)descriptor;
    if (error) *error = spiUnsupported(@"tile render pipelines");
    return nil;
}
- (id)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options reflection:(MTLRenderPipelineReflection **)reflection
    error:(NSError **)error
{
    (void)descriptor; (void)options;
    if (reflection) *reflection = nil;
    if (error) *error = spiUnsupported(@"tile render pipelines");
    return nil;
}
- (void)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewRenderPipelineStateWithReflectionCompletionHandler)handler
{
    (void)descriptor; (void)options;
    if (handler) handler(nil, nil, spiUnsupported(@"tile render pipelines"));
}
- (id)newResourceGroupFromResources:(const id *)resources count:(NSUInteger)count
{ (void)resources; (void)count; return nil; }
- (id)newTextureLayoutWithDescriptor:(id)descriptor isHeapOrBufferBacked:(BOOL)backed
{ (void)descriptor; (void)backed; return nil; }
- (id)newTextureWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
    descriptor:(MTLTextureDescriptor *)descriptor
    deallocator:(void (^)(void *, NSUInteger))deallocator
{
    /* Failed creation leaves both memory and deallocator ownership with caller. */
    (void)bytes; (void)length; (void)descriptor; (void)deallocator;
    return nil;
}
- (BOOL)reserveGPUAddressRange:(NSRange)range
{ (void)range; return NO; }
- (void)reserveResourceIndicesForResourceType:(NSUInteger)type
    indices:(NSUInteger *)indices indexCount:(NSUInteger)count
{
    (void)type; (void)indices;
    /* Do not invent resource indices, dereference an untrusted pointer or loop
     * over an unbounded caller count. Zero work needs no reservation. */
    if (count) rejectSPI(@"resource index reservation");
}
- (NSUInteger)resourcePatchingTypeForResourceType:(NSUInteger)type
{
    (void)type;
    rejectSPI(@"resource patching");
    return NSUIntegerMax;
}
- (void)setupMPSFunctionTable:(struct MPSFunctionTable *)table
{
    /* The SPI gives no size parameter. Clearing this unknown structure would
     * corrupt caller memory and falsely imply a usable MPS function table. */
    if (table) rejectSPI(@"MPS function tables");
}
- (MTLSize)tileSizeWithSparsePageSize:(MTLSparsePageSize)size
    textureType:(MTLTextureType)type pixelFormat:(MTLPixelFormat)format
    sampleCount:(NSUInteger)count
{ (void)size; (void)type; (void)format; (void)count; return MTLSizeMake(0, 0, 0); }

@end
