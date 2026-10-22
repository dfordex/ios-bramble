/* SPDX-License-Identifier: MIT
 * Opt-in iOS16 Metal provider for the bounded Mali backend. Unsupported
 * hardware/API features are not advertised as an Apple GPU family.
 */
#import "../A5MaliRestrictedDevice.h"
#import "../A5MaliMetalDeviceResources.h"
#import "A5MaliStockABI.h"
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

static NSError *unsupported(NSString *operation)
{
    return [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
        code:kIOReturnUnsupported userInfo:@{NSLocalizedDescriptionKey:
            [operation stringByAppendingString:@" is not supported by the bounded Mali backend"]}];
}

/* Verify every required instance selector exposed by the actual OS protocol.
 * This covers inherited superclass/category methods as well as this class;
 * protocol registration alone is not used as an implementation check.
 */
static unsigned missingRequiredMethods(Class cls, Protocol *protocol)
{
    unsigned count = 0, missing = 0;
    struct objc_method_description *methods =
        protocol_copyMethodDescriptionList(protocol, YES, YES, &count);
    for (unsigned i = 0; i < count; ++i)
        if (!class_getInstanceMethod(cls, methods[i].name)) {
            fprintf(stderr, "A5XELTE Metal: missing required selector %s\n",
                sel_getName(methods[i].name));
            ++missing;
        }
    free(methods);
    Protocol *__unsafe_unretained *parents = protocol_copyProtocolList(protocol, &count);
    for (unsigned i = 0; i < count; ++i)
        missing += missingRequiredMethods(cls, parents[i]);
    free(parents);
    return missing;
}

@interface A5MaliMetalDevice : A5MaliRestrictedDevice
@end

@implementation A5MaliMetalDevice {
    uint64_t _registryID;
    BOOL _limitsInitialized;
    BOOL _featuresInitialized;
}

+ (void)load
{
    Protocol *publicProtocol = objc_getProtocol("MTLDevice");
    Protocol *privateProtocol = objc_getProtocol("MTLDeviceSPI");
    if (!publicProtocol || !privateProtocol || !A5MaliStockLayoutMatches() ||
        missingRequiredMethods(self, privateProtocol)) {
        fprintf(stderr, "A5XELTE Metal: incompatible iOS provider ABI\n");
        return;
    }
    /* Use the OS's actual protocol objects. No private protocol is invented
     * and -conformsToProtocol: is never overridden to forge a result.
     */
    class_addProtocol(self, publicProtocol);
    class_addProtocol(self, privateProtocol);
    fprintf(stderr, "A5XELTE Metal: provider bundle loaded; stock protocols registered\n");
    const char *ignoreSendErrors=getenv("CA_IGNORE_MACH_SEND_ERRORS");
    if(ignoreSendErrors)fprintf(stderr,"A5XELTE Metal: CA_IGNORE_MACH_SEND_ERRORS=%u\n",
        atoi(ignoreSendErrors)!=0);
}

- (instancetype)initWithAcceleratorPort:(io_service_t)service
{
    if (!class_conformsToProtocol(object_getClass(self), objc_getProtocol("MTLDevice")) ||
        !class_conformsToProtocol(object_getClass(self), objc_getProtocol("MTLDeviceSPI")) ||
        !A5MaliStockLayoutMatches() || !service ||
        !IOObjectConformsTo(service, "A5XELTEGPUAccelerator"))
        return nil;
    io_registry_entry_t privateGPU = IO_OBJECT_NULL;
    if (IORegistryEntryGetParentEntry(service, kIOServicePlane,
                                     &privateGPU) != KERN_SUCCESS)
        return nil;
    uint64_t registryID = 0;
    IORegistryEntryGetRegistryEntryID(service, &registryID);
    BOOL isPrivateGPU = IOObjectConformsTo(privateGPU, "A5XELTEGPU");
    self = isPrivateGPU ? [super initWithAcceleratorPort:privateGPU] : nil;
    IOObjectRelease(privateGPU);
    if (self) {
        _registryID = registryID;
        fprintf(stderr, "A5XELTE Metal: device initialized; registry=%llu\n",
            (unsigned long long)registryID);
    } else {
        fprintf(stderr, "A5XELTE Metal: GPU client initialization failed\n");
    }
    return self;
}

- (void)initLimits
{
    A5MaliStockLimits *limits = A5MaliStockLimitsForDevice(self);
    if (!limits) [NSException raise:NSInternalInconsistencyException
        format:@"Mali provider limits ABI changed"];
    memset(limits, 0, sizeof(*limits));
    /* Logical API capacity for strictly registered sequential native passes.
     * Each physical v4 SFBD still has one color target. */
    limits->maxFramebufferStorageBits = 160;
    limits->maxColorAttachments = 3;
    /* These limits count original Metal binding slots, not the dense native
     * descriptor-table count. Blur/misc/path use Metal VB1..3/5, FB1/6/9 and textures3/4. */
    limits->maxVertexAttributes = 4;
    limits->maxVertexBuffers = 6;
    limits->maxVertexInlineDataSize = 4096;
    limits->maxFragmentBuffers = 10;
    limits->maxFragmentInlineDataSize = 4096;
    limits->maxVertexTextures = 0;
    limits->maxFragmentTextures = 5;
    limits->maxFragmentSamplers = 2;
    limits->maxInterpolants = 5;
    limits->maxInterpolatedComponents = 8;
    limits->maxConstantBufferArguments = 10;
    limits->maxLineWidth = 1.0f;
    limits->maxPointSize = 1.0f;
    limits->minConstantBufferAlignmentBytes = 16;
    limits->minBufferNoCopyAlignmentBytes = 4096;
    /* These are texture capacity limits, not panel dimensions. iOS16
     * QuartzCore uses maxTextureWidth2D for BOTH axes of its current surface
     * gate; advertising the portrait panel width rejects its 1920px height
     * before any texture factory or command buffer is reached. The resource
     * allocator already validates logical 2D dimensions up to 2048 per axis. */
    limits->maxTextureWidth2D = 2048;
    limits->maxTextureHeight2D = 2048;
    limits->maxTextureLayers = 1;
    limits->linearTextureAlignmentBytes = 64;
    limits->iosurfaceTextureAlignmentBytes = 64;
    limits->iosurfaceReadOnlyTextureAlignmentBytes = 64;
    limits->deviceLinearTextureAlignmentBytes = 64;
    limits->deviceLinearReadOnlyTextureAlignmentBytes = 64;
    limits->maxViewportCount = 1;
    limits->maxBufferLength = A5MaliMaxPrivateBufferLength;
    _limitsInitialized = YES;
    fprintf(stderr, "A5XELTE Metal: initLimits complete; registered profiles, FT slots=5 FB slots=10 private buffers=4x8MiB max2D=%u/%u\n",
        limits->maxTextureWidth2D, limits->maxTextureHeight2D);
}

- (void)initFeatureQueries
{
    if (!A5MaliInstallConservativeFeatureQueries(self))
        [NSException raise:NSInternalInconsistencyException
            format:@"Mali provider feature-query ABI changed"];
    _featuresInitialized = YES;
    fprintf(stderr, "A5XELTE Metal: initFeatureQueries complete; no Apple family advertised\n");
}

- (BOOL)a5MaliAcceptanceInitialized { return _limitsInitialized && _featuresInitialized; }
- (NSString *)name { return @"Mali-T720 (A5XELTE bounded backend)"; }
- (uint64_t)registryID { return _registryID; }
- (BOOL)isLowPower { return YES; }
- (BOOL)isHeadless { return NO; }
- (BOOL)isRemovable { return NO; }
- (BOOL)hasUnifiedMemory { return YES; }
/* Midgard supports native FP16 arithmetic. This individual capability is
 * independent of Apple GPU families and of FP16 derivative support. Stock
 * QuartzCore uses it to select its supplied lph shaders; advertising NO
 * selects fixed_frag_lpf_cpf, absent from the supplied iOS16 metallib. */
- (BOOL)supportsNativeHardwareFP16 { return YES; }
- (BOOL)isDepth24Stencil8PixelFormatSupported { return NO; }
- (BOOL)supportsFamily:(MTLGPUFamily)family { (void)family; return NO; }
- (BOOL)supportsFeatureSet:(NSUInteger)feature { (void)feature; return NO; }
- (BOOL)supportsTextureSampleCount:(NSUInteger)count { return count == 1; }
- (BOOL)supportsSampleCount:(NSUInteger)count { return count == 1; }
- (BOOL)supportsVertexAmplificationCount:(NSUInteger)count { return count == 1; }
- (BOOL)supportsCounterSampling:(MTLCounterSamplingPoint)point { (void)point; return NO; }
- (BOOL)areRasterOrderGroupsSupported { return NO; }
- (BOOL)areBarycentricCoordsSupported { return NO; }
- (BOOL)areProgrammableSamplePositionsSupported { return NO; }
- (BOOL)supportPriorityBand { return NO; }
- (BOOL)metalAssertionsEnabled { return NO; }
- (void)setMetalAssertionsEnabled:(BOOL)enabled { (void)enabled; }
- (NSUInteger)argumentBuffersSupport { return MTLArgumentBuffersTier1; }
- (NSUInteger)readWriteTextureSupport { return MTLReadWriteTextureTierNone; }
- (NSUInteger)maxBufferLength { return A5MaliMaxPrivateBufferLength; }
- (NSUInteger)currentAllocatedSize { return A5MaliAllocatedPrivateBufferBytes(self); }
- (uint64_t)recommendedMaxWorkingSetSize { return 4u * A5MaliMaxPrivateBufferLength + 4u * 0x2000000u; }
- (uint64_t)sharedMemorySize { return 0; }
- (uint64_t)dedicatedMemorySize { return 0; }
- (MTLSize)maxThreadsPerThreadgroup { return MTLSizeMake(0, 0, 0); }
- (NSUInteger)maxThreadgroupMemoryLength { return 0; }
- (NSUInteger)maxArgumentBufferSamplerCount { return 0; }
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)format
{ (void)format; return 4096; }
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)format
{ (void)format; return 64; }
- (NSArray *)counterSets { return @[]; }
- (id)newFence { return nil; }
- (id)newHeapWithDescriptor:(MTLHeapDescriptor *)descriptor { (void)descriptor; return nil; }
- (id)newIndirectCommandBufferWithDescriptor:(MTLIndirectCommandBufferDescriptor *)descriptor
    maxCommandCount:(NSUInteger)count options:(MTLResourceOptions)options
{ (void)descriptor; (void)count; (void)options; return nil; }
- (MTLSize)sparseTileSizeWithTextureType:(MTLTextureType)type pixelFormat:(MTLPixelFormat)format
    sampleCount:(NSUInteger)count
{ (void)type; (void)format; (void)count; return MTLSizeMake(0, 0, 0); }
- (MTLSize)sparseTileSizeWithTextureType:(MTLTextureType)type pixelFormat:(MTLPixelFormat)format
    sampleCount:(NSUInteger)count sparsePageSize:(MTLSparsePageSize)size
{ (void)size; return [self sparseTileSizeWithTextureType:type pixelFormat:format sampleCount:count]; }
- (A5MaliMetalQueue *)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)count
{ return count > 0 && count <= 8 ? [self newCommandQueue] : nil; }
- (id)newDefaultLibrary { return [self newDefaultLibraryWithBundle:NSBundle.mainBundle error:NULL]; }
- (id)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error
{ (void)source; (void)options; if (error) *error = unsupported(@"source compilation"); return nil; }
- (id)newComputePipelineStateWithFunction:(id)function error:(NSError **)error
{ (void)function; if (error) *error = unsupported(@"compute pipelines"); return nil; }
- (id)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor
    options:(MTLPipelineOption)options reflection:(MTLComputePipelineReflection **)reflection
    error:(NSError **)error
{ (void)descriptor; (void)options; if (reflection) *reflection=nil;
  if (error) *error=unsupported(@"compute pipelines"); return nil; }

@end
