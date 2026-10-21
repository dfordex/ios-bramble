/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalDeviceResources.h"
#include <assert.h>
#include <string.h>
typedef struct { uint32_t words[3]; } SampleBuffer;
struct MPSFunctionTable;
@interface A5MaliRestrictedDevice (SPIResourceTestDeclarations)
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
@end
@implementation SPIResourceFixture
- (A5MaliPrivateBuffer *)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{ (void)length; (void)options; ++self.bufferCalls; return nil; }
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
int main(void)
{
    @autoreleasepool {
        SPIResourceFixture *device = [SPIResourceFixture new];
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
