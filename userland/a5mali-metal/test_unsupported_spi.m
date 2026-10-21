/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalDeviceResources.h"
#include <assert.h>
#include <string.h>
typedef struct { uint32_t words[3]; } SampleBuffer;
struct MPSFunctionTable;
@interface A5MaliRestrictedDevice (SPIResourceTestDeclarations)
- (id)newPipelineLibraryWithFilePath:(NSString *)path error:(NSError **)error;
- (id)newLibraryWithFile:(NSString *)path error:(NSError **)error;
- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options
    completionHandler:(MTLNewLibraryCompletionHandler)handler;
- (id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options reflection:(MTLRenderPipelineReflection **)reflection
    error:(NSError **)error;
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    completionHandler:(MTLNewRenderPipelineStateCompletionHandler)handler;
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewRenderPipelineStateWithReflectionCompletionHandler)handler;
- (id)newComputePipelineStateWithFunction:(id<MTLFunction>)function
    options:(MTLPipelineOption)options reflection:(MTLComputePipelineReflection **)reflection
    error:(NSError **)error;
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)function
    completionHandler:(MTLNewComputePipelineStateCompletionHandler)handler;
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)function
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)handler;
- (void)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)handler;
- (NSUInteger)featureProfile;
- (NSUInteger)doubleFPConfig;
- (NSUInteger)singleFPConfig;
- (NSUInteger)halfFPConfig;
- (id)copyIOSurfaceSharedTextureProperties:(id)properties;
- (id)indirectArgumentBufferDecodingData;
- (void)setIndirectArgumentBufferDecodingData:(id)data;
- (BOOL)mapShaderSampleBufferWithBuffer:(SampleBuffer *)buffer
    capacity:(NSUInteger)capacity size:(NSUInteger)size;
- (void)unmapShaderSampleBuffer;
- (id)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
    gpuAddress:(uint64_t)address;
- (id)newBufferWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
    options:(MTLResourceOptions)options gpuAddress:(uint64_t)address
    deallocator:(void (^)(void *, NSUInteger))deallocator;
- (id)newLibraryWithGraphs:(id)graphs functions:(id)functions error:(NSError **)error;
- (id)newLibraryWithGraphsSPI:(id)graphs functions:(id)functions error:(NSError **)error;
- (void)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    completionHandler:(MTLNewRenderPipelineStateCompletionHandler)handler;
- (id)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    error:(NSError **)error;
- (id)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options reflection:(MTLRenderPipelineReflection **)reflection
    error:(NSError **)error;
- (void)newRenderPipelineStateWithTileDescriptor:(MTLTileRenderPipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options
    completionHandler:(MTLNewRenderPipelineStateWithReflectionCompletionHandler)handler;
- (id)newTextureWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
    descriptor:(MTLTextureDescriptor *)descriptor deallocator:(void (^)(void *, NSUInteger))deallocator;
- (BOOL)reserveGPUAddressRange:(NSRange)range;
- (void)reserveResourceIndicesForResourceType:(NSUInteger)type indices:(NSUInteger *)indices
    indexCount:(NSUInteger)count;
- (NSUInteger)resourcePatchingTypeForResourceType:(NSUInteger)type;
- (void)setupMPSFunctionTable:(struct MPSFunctionTable *)table;
- (MTLSize)tileSizeWithSparsePageSize:(MTLSparsePageSize)size textureType:(MTLTextureType)type
    pixelFormat:(MTLPixelFormat)format sampleCount:(NSUInteger)count;
@end
@interface SPIResourceFixture : A5MaliRestrictedDevice
@property (nonatomic) NSUInteger bufferCalls;
@property (nonatomic) NSUInteger libraryCalls;
@property (nonatomic) NSUInteger pipelineCalls;
@property (nonatomic, strong) NSURL *lastLibraryURL;
@property (nonatomic, strong) MTLRenderPipelineDescriptor *lastRenderDescriptor;
@property (nonatomic, strong) id fixtureResult;
@property (nonatomic, strong) NSError *fixtureError;
@end
@implementation SPIResourceFixture
- (A5MaliPrivateBuffer *)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{ (void)length; (void)options; ++self.bufferCalls; return nil; }
- (A5MaliMetalLibrary *)newLibraryWithURL:(NSURL *)url error:(NSError **)error
{
    ++self.libraryCalls;
    self.lastLibraryURL = url;
    if (error) *error = self.fixtureError;
    return self.fixtureError ? nil : self.fixtureResult;
}
- (id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
    error:(NSError **)error
{
    ++self.pipelineCalls;
    self.lastRenderDescriptor = descriptor;
    if (error) *error = self.fixtureError;
    return self.fixtureError ? nil : self.fixtureResult;
}
@end

static void expectUnsupported(void (^action)(void))
{
    BOOL raised = NO;
    @try { action(); }
    @catch (NSException *exception) {
        assert([exception.name isEqualToString:NSInvalidArgumentException]);
        assert([exception.reason containsString:@"unsupported"]);
        raised = YES;
    }
    assert(raised);
}
static void nativeBuilderGuards(SPIResourceFixture *device)
{
    NSError *error = nil;
    assert(![device newPipelineLibraryWithFilePath:@"/pipeline.metallib" error:&error]);
    assert(error.code == kIOReturnUnsupported && !device.libraryCalls);
    assert(![device newPipelineLibraryWithFilePath:nil error:NULL]);
    device.fixtureResult = [NSObject new];
    error = nil;
    assert(![device newLibraryWithFile:nil error:&error]);
    assert(error.code == kIOReturnBadArgument && !device.libraryCalls);
    assert(![device newLibraryWithFile:@"" error:NULL] && !device.libraryCalls);
    id result = [device newLibraryWithFile:@"/tmp/exact-library.metallib" error:&error];
    assert(result == device.fixtureResult && !error && device.libraryCalls == 1);
    assert([device.lastLibraryURL.path isEqualToString:@"/tmp/exact-library.metallib"]);
    device.fixtureError = [NSError errorWithDomain:@"fixture-authentication-failure"
        code:42 userInfo:nil];
    assert(![device newLibraryWithFile:@"/tmp/wrong.metallib" error:&error]);
    assert(error == device.fixtureError && device.libraryCalls == 2);
    __block NSUInteger callbacks = 0;
    [device newLibraryWithSource:@"kernel void x() {}" options:nil
        completionHandler:^(id<MTLLibrary> library, NSError *failure) {
            assert(!library && failure.code == kIOReturnUnsupported);
            ++callbacks;
        }];
    assert(callbacks == 1 && device.libraryCalls == 2);
    [device newLibraryWithSource:@"" options:nil completionHandler:nil];

    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    MTLRenderPipelineReflection *reflection = (id)[NSObject new];
    device.fixtureError = nil;
    result = [device newRenderPipelineStateWithDescriptor:descriptor options:0
        reflection:&reflection error:&error];
    assert(result == device.fixtureResult && !error && !reflection);
    assert(device.pipelineCalls == 1 && device.lastRenderDescriptor == descriptor);
    reflection = (id)[NSObject new];
    assert(![device newRenderPipelineStateWithDescriptor:descriptor
        options:MTLPipelineOptionBindingInfo reflection:&reflection error:&error]);
    assert(!reflection && error.code == kIOReturnUnsupported && device.pipelineCalls == 1);
    callbacks = 0;
    [device newRenderPipelineStateWithDescriptor:descriptor
        completionHandler:^(id<MTLRenderPipelineState> state, NSError *failure) {
            assert(state == device.fixtureResult && !failure); ++callbacks;
        }];
    assert(callbacks == 1 && device.pipelineCalls == 2);
    callbacks = 0;
    [device newRenderPipelineStateWithDescriptor:descriptor options:0
        completionHandler:^(id<MTLRenderPipelineState> state,
            MTLRenderPipelineReflection *details, NSError *failure) {
            assert(state == device.fixtureResult && !details && !failure); ++callbacks;
        }];
    assert(callbacks == 1 && device.pipelineCalls == 3);
    callbacks = 0;
    [device newRenderPipelineStateWithDescriptor:descriptor options:MTLPipelineOptionBindingInfo
        completionHandler:^(id<MTLRenderPipelineState> state,
            MTLRenderPipelineReflection *details, NSError *failure) {
            assert(!state && !details && failure.code == kIOReturnUnsupported); ++callbacks;
        }];
    assert(callbacks == 1 && device.pipelineCalls == 3);
    device.fixtureError = [NSError errorWithDomain:@"fixture-unsupported-pipeline"
        code:43 userInfo:nil];
    callbacks = 0;
    [device newRenderPipelineStateWithDescriptor:descriptor options:0
        completionHandler:^(id<MTLRenderPipelineState> state,
            MTLRenderPipelineReflection *details, NSError *failure) {
            assert(!state && !details && failure == device.fixtureError); ++callbacks;
        }];
    assert(callbacks == 1 && device.pipelineCalls == 4);
    [device newRenderPipelineStateWithDescriptor:descriptor completionHandler:nil];
    assert(device.pipelineCalls == 4);

    MTLComputePipelineReflection *computeReflection = (id)[NSObject new];
    assert(![device newComputePipelineStateWithFunction:nil options:0
        reflection:&computeReflection error:&error]);
    assert(!computeReflection && error.code == kIOReturnUnsupported);
    callbacks = 0;
    [device newComputePipelineStateWithFunction:nil
        completionHandler:^(id<MTLComputePipelineState> state, NSError *failure) {
            assert(!state && failure.code == kIOReturnUnsupported); ++callbacks;
        }];
    assert(callbacks == 1);
    callbacks = 0;
    [device newComputePipelineStateWithFunction:nil options:0
        completionHandler:^(id<MTLComputePipelineState> state,
            MTLComputePipelineReflection *details, NSError *failure) {
            assert(!state && !details && failure.code == kIOReturnUnsupported); ++callbacks;
        }];
    assert(callbacks == 1);
    callbacks = 0;
    [device newComputePipelineStateWithDescriptor:[MTLComputePipelineDescriptor new] options:0
        completionHandler:^(id<MTLComputePipelineState> state,
            MTLComputePipelineReflection *details, NSError *failure) {
            assert(!state && !details && failure.code == kIOReturnUnsupported); ++callbacks;
        }];
    assert(callbacks == 1);
    MTLTileRenderPipelineDescriptor *tile = [MTLTileRenderPipelineDescriptor new];
    reflection = (id)[NSObject new];
    assert(![device newRenderPipelineStateWithTileDescriptor:tile options:0
        reflection:&reflection error:&error]);
    assert(!reflection && error.code == kIOReturnUnsupported);
    callbacks = 0;
    [device newRenderPipelineStateWithTileDescriptor:tile options:0
        completionHandler:^(id<MTLRenderPipelineState> state,
            MTLRenderPipelineReflection *details, NSError *failure) {
            assert(!state && !details && failure.code == kIOReturnUnsupported); ++callbacks;
        }];
    assert(callbacks == 1);
}
int main(void)
{
    @autoreleasepool {
        SPIResourceFixture *device = [SPIResourceFixture new];
        nativeBuilderGuards(device);
        assert(device.featureProfile == NSUIntegerMax &&
            !device.doubleFPConfig && !device.halfFPConfig && !device.singleFPConfig);
        assert(![device copyIOSurfaceSharedTextureProperties:@{}]);
        assert(!device.indirectArgumentBufferDecodingData);
        [device setIndirectArgumentBufferDecodingData:nil];
        expectUnsupported(^{ [device setIndirectArgumentBufferDecodingData:@{}]; });
        SampleBuffer sample = {{0x123, 0x456, 0x789}}, original = sample;
        assert(![device mapShaderSampleBufferWithBuffer:&sample
            capacity:NSUIntegerMax size:NSUIntegerMax]);
        assert(!memcmp(&sample, &original, sizeof(sample)));
        [device unmapShaderSampleBuffer];
        assert(![device newBufferWithLength:4096 options:MTLResourceStorageModePrivate
            gpuAddress:0x12345000]);
        assert(!device.bufferCalls);
        assert(![device newBufferWithLength:4096 options:MTLResourceStorageModePrivate
            gpuAddress:0]);
        assert(device.bufferCalls == 1);
        uint8_t bytes[8] = {0};
        __block NSUInteger deallocatorCalls = 0;
        assert(![device newBufferWithBytesNoCopy:bytes length:sizeof(bytes)
            options:0 gpuAddress:0x12345000 deallocator:^(void *p, NSUInteger n) {
                (void)p; (void)n; ++deallocatorCalls;
            }]);
        assert(![device newTextureWithBytesNoCopy:bytes length:sizeof(bytes)
            descriptor:[MTLTextureDescriptor new] deallocator:^(void *p, NSUInteger n) {
                (void)p; (void)n; ++deallocatorCalls;
            }]);
        assert(!deallocatorCalls);
        NSError *error = nil;
        assert(![device newLibraryWithGraphs:@[] functions:@[] error:&error]);
        assert(error.code == kIOReturnUnsupported &&
            [error.localizedDescription containsString:@"graph"]);
        error = nil;
        assert(![device newLibraryWithGraphsSPI:@[] functions:@[] error:&error]);
        assert(error.code == kIOReturnUnsupported);
        error = nil;
        MTLTileRenderPipelineDescriptor *tile = [MTLTileRenderPipelineDescriptor new];
        assert(![device newRenderPipelineStateWithTileDescriptor:tile error:&error]);
        assert(error.code == kIOReturnUnsupported);
        __block NSUInteger callbacks = 0;
        [device newRenderPipelineStateWithTileDescriptor:tile
            completionHandler:^(id<MTLRenderPipelineState> state, NSError *failure) {
                assert(!state && failure.code == kIOReturnUnsupported);
                ++callbacks;
            }];
        assert(callbacks == 1);
        assert(![device reserveGPUAddressRange:NSMakeRange(0, NSUIntegerMax)]);
        NSUInteger indices[2] = {0x123, 0x456};
        NSUInteger *indexPointer = indices;
        expectUnsupported(^{ [device reserveResourceIndicesForResourceType:0
            indices:indexPointer indexCount:NSUIntegerMax]; });
        assert(indices[0] == 0x123 && indices[1] == 0x456);
        [device reserveResourceIndicesForResourceType:0 indices:NULL indexCount:0];
        expectUnsupported(^{ (void)[device resourcePatchingTypeForResourceType:0]; });
        uint8_t table[8];
        memset(table, 0x5a, sizeof(table));
        struct MPSFunctionTable *tablePointer = (struct MPSFunctionTable *)table;
        expectUnsupported(^{ [device setupMPSFunctionTable:tablePointer]; });
        for (NSUInteger i = 0; i < sizeof(table); ++i) assert(table[i] == 0x5a);
        [device setupMPSFunctionTable:NULL];
        MTLSize size = [device tileSizeWithSparsePageSize:MTLSparsePageSize16
            textureType:MTLTextureType2D pixelFormat:MTLPixelFormatBGRA8Unorm sampleCount:1];
        assert(!size.width && !size.height && !size.depth);
    }
    puts("unsupported SPI: rejection, callback-once, caller ownership and no-write tests passed");
    return 0;
}
