/* SPDX-License-Identifier: MIT
 * Narrow Metal-selector adapter for the real typed Mali copy path.
 * These classes deliberately claim no Metal protocol conformance.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#import "A5MaliNativeUpload.h"
#include "../a5xelte-air-translation/families/runtime_encode.h"
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include "../a5xelte-air-translation/families/runtime_path_encode.h"
#include "../a5xelte-air-translation/families/runtime_clear.h"
#include <math.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#include <stdio.h>
/* A build without authenticated compiled profiles exposes only the legacy
 * typed read_surf path and has no dependency on a native descriptor backend. */
#if __has_include("A5MaliCompiledRegistryData.inc") || defined(A5_MALI_REQUIRE_COMPILED_REGISTRY)
#define A5_MALI_NATIVE_RENDER 1
#else
#define A5_MALI_NATIVE_RENDER 0
#endif

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
static NSUInteger linearPixelBytes(MTLPixelFormat format)
{ switch(format){case MTLPixelFormatBGRA8Unorm:case MTLPixelFormatR32Float:return 4;
case MTLPixelFormatRGBA16Float:return 8;case MTLPixelFormatR8Unorm:return 1;
case MTLPixelFormatRG8Unorm:return 2;default:return 0;} }
static uint32_t linearPixelCode(MTLPixelFormat format)
{ switch(format){case MTLPixelFormatBGRA8Unorm:return 0x42475241u;
case MTLPixelFormatRGBA16Float:return 0x52476841u;case MTLPixelFormatR32Float:return 0x4c303066u;
case MTLPixelFormatR8Unorm:return 0x4c303038u;case MTLPixelFormatRG8Unorm:return 0x32433038u;default:return 0;} }
static BOOL defaultTextureSwizzle(MTLTextureDescriptor *d)
{
    MTLTextureSwizzleChannels sw=d.swizzle;
    return sw.red==MTLTextureSwizzleRed && sw.green==MTLTextureSwizzleGreen &&
        sw.blue==MTLTextureSwizzleBlue && sw.alpha==MTLTextureSwizzleAlpha;
}
static BOOL validLinearRow(NSUInteger width, NSUInteger height, NSUInteger rowBytes, MTLPixelFormat format)
{
    NSUInteger bytes = linearPixelBytes(format);
    return bytes && width && width <= 2048 && height && height <= 2048 &&
        rowBytes >= width * bytes && rowBytes <= 2048 * bytes &&
        !(rowBytes & 15) && rowBytes * height <= A5MaliSurfaceMaxBytes;
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

@interface A5MaliDevice (FactoryDiagnostics)
- (A5MaliClient *)client;
@end
/* Bound diagnostics per process, including failed warmup loops. Names/reasons
 * are flattened and truncated; descriptors contain metadata, never buffers. */
static NSString *pipelineLogText(NSString *value)
{
    if(!value)return @"(nil)";
    NSString *flat=[[value stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    return flat.length>160?[flat substringToIndex:160]:flat;
}
static void logPipelineDecision(A5MaliRestrictedDevice *device,
    MTLRenderPipelineDescriptor *descriptor,uint32_t profile,BOOL accepted,NSString *reason)
{
    static atomic_uint messages;
    if(atomic_fetch_add_explicit(&messages,1,memory_order_relaxed)>=32)return;
    A5MaliClient *client=[[device privateDevice] client];
    NSMutableString *line=[NSMutableString stringWithFormat:
        @"A5XELTE Metal pipeline: %@ profile=%u vertex=%@ fragment=%@ commands=%x operations=%x reason=%@",
        accepted?@"accepted":@"rejected",profile,
        pipelineLogText(descriptor.vertexFunction.name),pipelineLogText(descriptor.fragmentFunction.name),
        client?client->gpuCommandsSupported:0,client?client->supportedOperations:0,pipelineLogText(reason)];
    [line appendFormat:@" samples=%lu depth=%lu stencil=%lu raster=%u topology=%lu",
        (unsigned long)descriptor.rasterSampleCount,(unsigned long)descriptor.depthAttachmentPixelFormat,
        (unsigned long)descriptor.stencilAttachmentPixelFormat,descriptor.isRasterizationEnabled,
        (unsigned long)descriptor.inputPrimitiveTopology];
    for(NSUInteger i=0;i<8;++i){MTLRenderPipelineColorAttachmentDescriptor*a=descriptor.colorAttachments[i];
        [line appendFormat:@" RT%lu={f:%lu,w:%lu,b:%u,rgb:%lu/%lu/%lu,a:%lu/%lu/%lu}",
            (unsigned long)i,(unsigned long)a.pixelFormat,(unsigned long)a.writeMask,a.isBlendingEnabled,
            (unsigned long)a.rgbBlendOperation,(unsigned long)a.sourceRGBBlendFactor,(unsigned long)a.destinationRGBBlendFactor,
            (unsigned long)a.alphaBlendOperation,(unsigned long)a.sourceAlphaBlendFactor,(unsigned long)a.destinationAlphaBlendFactor];}
    MTLVertexDescriptor *v=descriptor.vertexDescriptor;
    [line appendFormat:@" vertexDescriptor=%@",v?@"present":@"nil"];
    if(v)for(NSUInteger i=0;i<31;++i){MTLVertexAttributeDescriptor*a=v.attributes[i];
        if(a.format!=MTLVertexFormatInvalid)[line appendFormat:@" A%lu=%lu/%lu/%lu",(unsigned long)i,
            (unsigned long)a.format,(unsigned long)a.offset,(unsigned long)a.bufferIndex];}
    if(v)for(NSUInteger i=0;i<31;++i){MTLVertexBufferLayoutDescriptor*l=v.layouts[i];
        if(l.stride)[line appendFormat:@" VB%lu=%lu/%lu/%lu",(unsigned long)i,
            (unsigned long)l.stride,(unsigned long)l.stepFunction,(unsigned long)l.stepRate];}
    fprintf(stderr,"%s\n",line.UTF8String);
}

@interface A5MaliReadSurfCandidate (PrivateInit)
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device;
@end
@interface A5MaliCompiledPipeline : A5MaliReadSurfCandidate
@property (nonatomic, readonly) const A5MaliCompiledProfile *profile;
@property (nonatomic, readonly) BOOL sourceOver;
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
    profile:(const A5MaliCompiledProfile *)profile sourceOver:(BOOL)sourceOver;
@end
@implementation A5MaliCompiledPipeline {
    const A5MaliCompiledProfile *_profile;
    BOOL _sourceOver;
}
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
    profile:(const A5MaliCompiledProfile *)profile sourceOver:(BOOL)sourceOver
{ if ((self = [super initWithDevice:device])) { _profile=profile; _sourceOver=sourceOver; } return self; }
- (const A5MaliCompiledProfile *)profile { return _profile; }
- (BOOL)sourceOver { return _sourceOver; }
@end

@interface A5MaliMetalTexture () {
    A5MaliSurface *_surface;
    A5MaliRestrictedDevice *_device;
    MTLTextureUsage _usage;
    MTLPixelFormat _pixelFormat;
    MTLStorageMode _storageMode;
}
- (instancetype)initWithSurface:(A5MaliSurface *)surface
                        device:(A5MaliRestrictedDevice *)device
                         usage:(MTLTextureUsage)usage storageMode:(MTLStorageMode)storageMode;
- (A5MaliSurface *)privateSurface;
@end
@interface A5MaliSurface (NativeResourceAccess)
- (A5MaliResource)resource;
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
- (BOOL)encodeNativeClear:(A5MaliMetalTexture *)target color:(MTLClearColor)color;
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
    NSDictionary<NSNumber *,A5MaliMetalTexture *> *_attachments;
    A5MaliMetalTexture *_source;
    A5MaliReadSurfCandidate *_pipeline;
    BOOL _ended, _hasDraw, _hasViewport;
    MTLViewport _viewport;
    MTLScissorRect _scissor;
    NSMutableDictionary<NSNumber *, A5MaliBufferBinding *> *_vertexBindings, *_fragmentBindings;
    NSMutableDictionary<NSNumber *, A5MaliMetalTexture *> *_textures;
    NSMutableDictionary<NSNumber *, A5MaliSamplerState *> *_samplers;
    NSMutableArray<NSString *> *_debugGroups;
}
- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer
                   attachments:(NSDictionary<NSNumber *,A5MaliMetalTexture *> *)attachments;
- (BOOL)encodeCompiledDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count;
- (BOOL)encodeCompiledMiscDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count;
- (BOOL)validateActive;
- (void)setBoundBuffer:(nullable A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset
    index:(NSUInteger)index vertex:(BOOL)vertex;
- (void)setBoundBytes:(const void * _Nullable)bytes length:(NSUInteger)length
    index:(NSUInteger)index vertex:(BOOL)vertex;
@end

@implementation A5MaliRestrictedDevice (LimitedMetalSelectors)

- (A5MaliMetalQueue *)newCommandQueue
{
    return [[A5MaliMetalQueue alloc] initWithDevice:self];
}

- (A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
{
    /* Both shareable and GPU-private one-level allocations own a real
     * internal IOSurface and kernel resource. Private storage is not exposed
     * through iosurface and has no CPU texture transfer API. */
    if (!descriptor || !defaultTextureSwizzle(descriptor) || descriptor.textureType != MTLTextureType2D ||
        !linearPixelBytes(descriptor.pixelFormat) || descriptor.depth != 1 ||
        descriptor.width == 0 || descriptor.width > 2048 ||
        descriptor.height == 0 || descriptor.height > 2048 ||
        descriptor.mipmapLevelCount != 1 || descriptor.arrayLength != 1 ||
        descriptor.sampleCount != 1 ||
        (descriptor.storageMode != MTLStorageModeShared && descriptor.storageMode != MTLStorageModePrivate) ||
        (descriptor.usage & ~(MTLTextureUsageShaderRead |
            MTLTextureUsageRenderTarget)) || !descriptor.usage)
        return nil;
    const NSUInteger rowBytes = (descriptor.width * linearPixelBytes(descriptor.pixelFormat) + 15) & ~(NSUInteger)15;
    if (!validLinearRow(descriptor.width, descriptor.height, rowBytes, descriptor.pixelFormat)) return nil;
    NSDictionary *properties = @{
        (__bridge id)kIOSurfaceWidth: @(descriptor.width),
        (__bridge id)kIOSurfaceHeight: @(descriptor.height),
        (__bridge id)kIOSurfaceBytesPerElement: @(linearPixelBytes(descriptor.pixelFormat)),
        (__bridge id)kIOSurfaceBytesPerRow: @(rowBytes),
        (__bridge id)kIOSurfacePixelFormat: @(linearPixelCode(descriptor.pixelFormat)),
    };
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!surface)
        return nil;
    uint32_t usage=0;
    if(descriptor.usage&MTLTextureUsageShaderRead)usage|=A5MaliRead;
    if(descriptor.usage&MTLTextureUsageRenderTarget)usage|=A5MaliRead|A5MaliWrite;
    A5MaliSurface *imported=[[self privateDevice] importSurface:surface usage:usage error:NULL];
    A5MaliMetalTexture *texture=imported?[[A5MaliMetalTexture alloc] initWithSurface:imported
        device:self usage:descriptor.usage storageMode:descriptor.storageMode]:nil;
    CFRelease(surface);
    return texture;
}

- (id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                      error:(NSError * _Nullable * _Nullable)error
{
    A5MaliPipelineShape shape=A5MaliInspectReadSurfPipelineDescriptor(descriptor);
    id vertex=descriptor.vertexFunction,fragment=descriptor.fragmentFunction;
    BOOL authenticatedPair=[vertex isKindOfClass:[A5MaliMetalFunction class]] &&
        [fragment isKindOfClass:[A5MaliMetalFunction class]] &&
        [vertex library]==[fragment library] && [vertex device]==self && [fragment device]==self;
    if(shape==A5MaliPipelineShapeReadSurfCandidate && authenticatedPair &&
        [[self privateDevice] supportsPrivateReadSurf]){
        if(error)*error=nil;
        logPipelineDecision(self,descriptor,0,YES,@"legacy read_surf operation4");
        return [[A5MaliReadSurfCandidate alloc]initWithDevice:self];
    }
    NSError *rejection=nil;
    uint32_t profileID=0;
#if A5_MALI_NATIVE_RENDER
    const A5MaliCompiledProfile *profile=NULL;
    if(!authenticatedPair)rejection=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
        code:kIOReturnUnsupported userInfo:@{NSLocalizedDescriptionKey:
        @"factory requires authenticated same-device functions from one library"}];
    else profile=A5MaliSelectCompiledProfile(descriptor,&rejection);
    if(profile)profileID=profile->profileID;
    BOOL executable=profile && ((profile->profileID>=99 && profile->profileID<=108) ||
        profile->profileID==200 || profile->profileID==202 || profile->profileID==204 ||
        profile->profileID==206 || profile->profileID==207 ||
        (profile->profileID>=300 && profile->profileID<=302));
    if(executable && [[self privateDevice]supportsNativePrograms]){
        if(error)*error=nil;
        logPipelineDecision(self,descriptor,profileID,YES,@"authenticated executable profile");
        return [[A5MaliCompiledPipeline alloc]initWithDevice:self profile:profile
            sourceOver:descriptor.colorAttachments[0].isBlendingEnabled];
    }
    if(profile)rejection=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali"
        code:kIOReturnUnsupported userInfo:@{NSLocalizedDescriptionKey:executable?
        @"native query/submit capability is unavailable":@"matched profile has no executable native route"}];
#endif
    if(!rejection){
        NSString *reason=shape==A5MaliPipelineShapeReadSurfCandidate?
            @"read_surf requires functions from the exact QuartzCore metallib and kernel operation 4":
            @"authenticated native profile registry is unavailable in this build";
        rejection=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:kIOReturnUnsupported
            userInfo:@{NSLocalizedDescriptionKey:reason}];
    }
    logPipelineDecision(self,descriptor,profileID,NO,rejection.localizedDescription);
    if(error)*error=rejection;
    return nil;
}

- (A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
                                         iosurface:(IOSurfaceRef)surface
                                             plane:(NSUInteger)plane
{
    if (!descriptor || !surface || plane != 0 || !defaultTextureSwizzle(descriptor) ||
        descriptor.textureType != MTLTextureType2D ||
        !linearPixelBytes(descriptor.pixelFormat) || descriptor.depth != 1 ||
        descriptor.mipmapLevelCount != 1 || descriptor.arrayLength != 1 ||
        descriptor.sampleCount != 1 ||
        descriptor.storageMode != MTLStorageModeShared ||
        descriptor.width != IOSurfaceGetWidth(surface) ||
        descriptor.height != IOSurfaceGetHeight(surface) ||
        IOSurfaceGetBytesPerElement(surface) != linearPixelBytes(descriptor.pixelFormat) ||
        !validLinearRow(descriptor.width, descriptor.height,
            IOSurfaceGetBytesPerRow(surface), descriptor.pixelFormat) ||
        IOSurfaceGetBytesPerRow(surface) * descriptor.height >
            IOSurfaceGetAllocSize(surface) ||
        IOSurfaceGetPixelFormat(surface) != linearPixelCode(descriptor.pixelFormat) ||
        (descriptor.usage & ~(MTLTextureUsageShaderRead |
            MTLTextureUsageRenderTarget)) || !descriptor.usage)
        return nil;
    uint32_t usage = 0;
    if (descriptor.usage & MTLTextureUsageShaderRead) usage |= A5MaliRead;
    if (descriptor.usage & MTLTextureUsageRenderTarget) usage |= A5MaliRead | A5MaliWrite;
    A5MaliSurface *imported = [[self privateDevice] importSurface:surface
                                                           usage:usage error:NULL];
    return imported ? [[A5MaliMetalTexture alloc] initWithSurface:imported
        device:self usage:descriptor.usage storageMode:MTLStorageModeShared] : nil;
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
        device:self usage:usage storageMode:MTLStorageModeShared];
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
                         usage:(MTLTextureUsage)usage storageMode:(MTLStorageMode)storageMode
{
    if ((self = [super init])) {
        _storageMode=storageMode;
        _surface = surface;
        _device = device;
        _usage = usage;
        uint32_t code=surface.iosurface?IOSurfaceGetPixelFormat(surface.iosurface):0x42475241u;
        switch(code){case 0x52476841u:_pixelFormat=MTLPixelFormatRGBA16Float;break;
        case 0x4c303038u:_pixelFormat=MTLPixelFormatR8Unorm;break;
        case 0x32433038u:_pixelFormat=MTLPixelFormatRG8Unorm;break;
        case 0x4c303066u:_pixelFormat=MTLPixelFormatR32Float;break;
        default:_pixelFormat=MTLPixelFormatBGRA8Unorm;break;}
    }
    return self;
}

- (A5MaliSurface *)privateSurface { return _surface; }
- (NSUInteger)width { return _surface.width; }
- (NSUInteger)height { return _surface.height; }
- (MTLPixelFormat)pixelFormat { return _pixelFormat; }
- (MTLTextureType)textureType { return MTLTextureType2D; }
- (MTLTextureSwizzleChannels)swizzle { return MTLTextureSwizzleChannelsDefault; }
- (NSUInteger)mipmapLevelCount { return 1; }
- (NSUInteger)arrayLength { return 1; }
- (NSUInteger)sampleCount { return 1; }
- (MTLTextureUsage)usage { return _usage; }
- (MTLStorageMode)storageMode { return _storageMode; }
- (IOSurfaceRef)iosurface { return _storageMode==MTLStorageModePrivate?NULL:_surface.iosurface; }
- (MTLResourceOptions)resourceOptions { return (MTLResourceOptions)(_storageMode<<MTLResourceStorageModeShift); }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (NSUInteger)allocatedSize { return _surface.iosurface?IOSurfaceGetAllocSize(_surface.iosurface):0; }
- (void)rejectCPUTransfer
{
    [NSException raise:NSInvalidArgumentException format:
        @"%@ texture CPU transfers are unsupported; use the actual GPU resource path",
        _storageMode==MTLStorageModePrivate?@"Private":@"Shared"];
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)row fromRegion:(MTLRegion)region
    mipmapLevel:(NSUInteger)level
{ (void)bytes;(void)row;(void)region;(void)level;[self rejectCPUTransfer]; }
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image
    fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice
{ (void)bytes;(void)row;(void)image;(void)region;(void)level;(void)slice;[self rejectCPUTransfer]; }
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level
    withBytes:(const void *)bytes bytesPerRow:(NSUInteger)row
{ (void)bytes;(void)row;(void)region;(void)level;[self rejectCPUTransfer]; }
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice
    withBytes:(const void *)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image
{ (void)bytes;(void)row;(void)image;(void)region;(void)level;(void)slice;[self rejectCPUTransfer]; }
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
    BOOL native=[[_queue.device privateDevice] supportsNativePrograms];
    if (_encoderOpen || committed || !descriptor ||
        (!native && ![[_queue.device privateDevice] supportsPrivateReadSurf]) ||
        descriptor.depthAttachment.texture || descriptor.stencilAttachment.texture) {
        [self markEncodingError:kIOReturnUnsupported];return nil;
    }
    NSMutableDictionary<NSNumber *,A5MaliMetalTexture *> *attachments=[NSMutableDictionary new];
    NSUInteger width=0,height=0;
    for(NSUInteger i=0;i<8;++i){
        MTLRenderPassColorAttachmentDescriptor *a=descriptor.colorAttachments[i];
        A5MaliMetalTexture *target=(id)a.texture;
        if(!target)continue;
        if(![target isKindOfClass:[A5MaliMetalTexture class]] || target.device!=_queue.device ||
            !(target.usage&MTLTextureUsageRenderTarget) || (!native && i) || a.level || a.slice || a.depthPlane ||
            a.resolveTexture ||
            (a.storeAction!=MTLStoreActionStore && (!native || a.storeAction!=MTLStoreActionDontCare)) ||
            (a.loadAction!=MTLLoadActionDontCare && (!native ||
                (a.loadAction!=MTLLoadActionLoad && a.loadAction!=MTLLoadActionClear))) ||
            (width && (target.width!=width || target.height!=height))) {
            [self markEncodingError:kIOReturnUnsupported];return nil;
        }
        width=target.width;height=target.height;attachments[@(i)]=target;
        if(a.loadAction==MTLLoadActionClear){
            MTLClearColor c=a.clearColor;
            if(!isfinite(c.red)||!isfinite(c.green)||!isfinite(c.blue)||!isfinite(c.alpha)){
                [self markEncodingError:kIOReturnUnsupported];return nil;
            }
            if(native){
                if(![self encodeNativeClear:target color:c]){[self markEncodingError:kIOReturnUnsupported];return nil;}
                continue;
            }
            if(target.pixelFormat!=MTLPixelFormatBGRA8Unorm ||
                c.red<0||c.red>1||c.green<0||c.green>1||c.blue<0||c.blue>1||c.alpha<0||c.alpha>1){
                [self markEncodingError:kIOReturnUnsupported];return nil;
            }
            uint32_t color=(uint32_t)llround(c.blue*255)|((uint32_t)llround(c.green*255)<<8)|
                ((uint32_t)llround(c.red*255)<<16)|((uint32_t)llround(c.alpha*255)<<24);
            if(![_privateBuffer encodeClear:target.privateSurface
                rect:(A5MaliRect){0,0,(uint32_t)width,(uint32_t)height} bgra:color]){
                [self markEncodingError:kIOReturnUnsupported];return nil;
            }
        }
    }
    if(!attachments.count || (!native && !attachments[@0])){
        [self markEncodingError:kIOReturnUnsupported];return nil;
    }
    _encoderOpen=YES;
    return [[A5MaliMetalRenderEncoder alloc] initWithBuffer:self attachments:attachments];
}

- (BOOL)encodeNativeClear:(A5MaliMetalTexture *)target color:(MTLClearColor)color
{
#if !A5_MALI_NATIVE_RENDER
    (void)target;(void)color;return NO;
#else
    return [_privateBuffer encodeNativeWork:^kern_return_t(A5MaliClient*client,A5MaliFence*fence){
        A5NativeQueryRequest query={.header={1,sizeof(query),0,0}};
        query.surfaces[0]=target.privateSurface.resource.token;
        A5NativeQueryResult mapped={0};kern_return_t kr=A5MaliQueryNative(client,&query,&mapped);if(kr)return kr;
        A5NativeSpan s=mapped.surfaces[0];
        if(s.width!=target.width || s.height!=target.height || s.rowBytes!=target.privateSurface.rowBytes ||
            s.pixelFormat!=linearPixelCode(target.pixelFormat) || !(s.usage&A5MaliWrite) ||
            !validLinearRow(s.width,s.height,s.rowBytes,target.pixelFormat) ||
            (uint64_t)s.rowBytes*s.height>s.bytes)return kIOReturnBadArgument;
        A5RuntimeClear clear={.descriptorGPUVA=mapped.jobVA,
            .destination={s.gpuVA,s.bytes,s.width,s.height,s.rowBytes,(uint32_t)target.pixelFormat},
            .color={color.red,color.green,color.blue,color.alpha}};
        NSMutableData *jobs=[NSMutableData dataWithLength:A5RuntimeJobBytes];
        int encoded=A5MaliEncodeRuntimeClear(&clear,jobs.mutableBytes,jobs.length);
        if(encoded)return encoded==A5RuntimeUnsupported?kIOReturnUnsupported:kIOReturnBadArgument;
        A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5RuntimeJobBytes,
            .vertexOffset=UINT32_MAX,.tilerOffset=UINT32_MAX,.fragmentOffset=0,
            .writeSurfaces=1,.profileID=0,.mappingEpoch=mapped.flags};
        submit.surfaces[0]=query.surfaces[0];
        return A5MaliSubmitNative(client,&submit,jobs.bytes,fence);
    }];
#endif
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
                   attachments:(NSDictionary<NSNumber *,A5MaliMetalTexture *> *)attachments
{
    if ((self = [super init])) {
        _buffer = buffer;
        _attachments=[attachments copy];
        _destination=attachments[@0]?:attachments.allValues.firstObject;
        _vertexBindings=[NSMutableDictionary new]; _fragmentBindings=[NSMutableDictionary new];
        _textures=[NSMutableDictionary new]; _samplers=[NSMutableDictionary new];
        _debugGroups=[NSMutableArray new];
        _scissor=(MTLScissorRect){0,0,_destination.width,_destination.height};
    }
    return self;
}

- (A5MaliRestrictedDevice *)device { return _buffer.device; }
- (BOOL)validateActive
{
    if(_ended || _buffer.status>=MTLCommandBufferStatusCommitted){
        [_buffer markEncodingError:kIOReturnNotReady];return NO;
    }
    return YES;
}
- (void)insertDebugSignpost:(NSString *)string
{ if([self validateActive] && ![string isKindOfClass:[NSString class]])[_buffer markEncodingError:kIOReturnBadArgument]; }
- (void)pushDebugGroup:(NSString *)string
{
    if(![self validateActive])return;
    if(![string isKindOfClass:[NSString class]])[_buffer markEncodingError:kIOReturnBadArgument];
    else [_debugGroups addObject:[string copy]];
}
- (void)popDebugGroup
{ if([self validateActive]){if(!_debugGroups.count)[_buffer markEncodingError:kIOReturnBadArgument];else[_debugGroups removeLastObject];} }
- (void)setCullMode:(MTLCullMode)mode
{ if([self validateActive] && mode!=MTLCullModeNone)[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setFrontFacingWinding:(MTLWinding)winding
{
    /* With cull=None and no front/back stencil attachment, either winding
     * has identical emitted raster state. Other enum values are invalid. */
    if([self validateActive] && winding!=MTLWindingClockwise && winding!=MTLWindingCounterClockwise)
        [_buffer markEncodingError:kIOReturnBadArgument];
}
- (void)setTriangleFillMode:(MTLTriangleFillMode)mode
{ if([self validateActive] && mode!=MTLTriangleFillModeFill)[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setDepthClipMode:(MTLDepthClipMode)mode
{ if([self validateActive] && mode!=MTLDepthClipModeClip)[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setDepthBias:(float)bias slopeScale:(float)slope clamp:(float)clamp
{ if([self validateActive] && (bias!=0 || slope!=0 || clamp!=0))[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setDepthStencilState:(A5MaliDepthStencilState *)state
{
    if(![self validateActive] || !state)return;
    if(![state isKindOfClass:[A5MaliDepthStencilState class]] || state.device!=_buffer.device ||
        state.descriptor.depthCompareFunction!=MTLCompareFunctionAlways || state.descriptor.depthWriteEnabled ||
        state.descriptor.frontFaceStencil || state.descriptor.backFaceStencil)
        [_buffer markEncodingError:kIOReturnUnsupported];
}
- (void)setStencilReferenceValue:(uint32_t)value
{ if([self validateActive] && value)[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setStencilFrontReferenceValue:(uint32_t)front backReferenceValue:(uint32_t)back
{ if([self validateActive] && (front||back))[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{ if([self validateActive] && (red!=0||green!=0||blue!=0||alpha!=0))[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset
{ if([self validateActive] && (mode!=MTLVisibilityResultModeDisabled || offset))[_buffer markEncodingError:kIOReturnUnsupported]; }
- (void)setVertexBuffers:(A5MaliPrivateBuffer * const *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range
{
    if(![self validateActive])return;
    if(!buffers || !offsets || range.location>31 || range.length>31-range.location){[_buffer markEncodingError:kIOReturnBadArgument];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setVertexBuffer:buffers[i] offset:offsets[i] atIndex:range.location+i];
}
- (void)setFragmentBuffers:(A5MaliPrivateBuffer * const *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range
{
    if(![self validateActive])return;
    if(!buffers || !offsets || range.location>31 || range.length>31-range.location){[_buffer markEncodingError:kIOReturnBadArgument];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setFragmentBuffer:buffers[i] offset:offsets[i] atIndex:range.location+i];
}
- (void)setFragmentTextures:(A5MaliMetalTexture * const *)textures withRange:(NSRange)range
{
    if(![self validateActive])return;
    if(!textures || range.location>128 || range.length>128-range.location){[_buffer markEncodingError:kIOReturnBadArgument];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setFragmentTexture:textures[i] atIndex:range.location+i];
}
- (void)setFragmentSamplerStates:(A5MaliSamplerState * const *)samplers withRange:(NSRange)range
{
    if(![self validateActive])return;
    if(!samplers || range.location>16 || range.length>16-range.location){[_buffer markEncodingError:kIOReturnBadArgument];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setFragmentSamplerState:samplers[i] atIndex:range.location+i];
}

- (void)setRenderPipelineState:(A5MaliReadSurfCandidate *)pipeline
{
    if (_ended || ![pipeline isKindOfClass:[A5MaliReadSurfCandidate class]] ||
        pipeline.device != _buffer.device || (_hasDraw &&
        [_pipeline isKindOfClass:[A5MaliCompiledPipeline class]]!=[pipeline isKindOfClass:[A5MaliCompiledPipeline class]]))
        [_buffer markEncodingError:kIOReturnBadArgument];
    else _pipeline = pipeline;
}

- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atIndex:(NSUInteger)index
{
    if (!texture && index<128 && !_ended) { [_textures removeObjectForKey:@(index)]; if(!index)_source=nil; return; }
    if (_ended || index >= 128 ||
        ![texture isKindOfClass:[A5MaliMetalTexture class]] ||
        texture.device != _buffer.device ||
        !(texture.usage & MTLTextureUsageShaderRead))
        [_buffer markEncodingError:kIOReturnBadArgument];
    else { _textures[@(index)]=texture; if(!index)_source=texture; }
}

- (void)setVertexBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index
{ [self setBoundBuffer:buffer offset:offset index:index vertex:YES]; }
- (void)setFragmentBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index
{ [self setBoundBuffer:buffer offset:offset index:index vertex:NO]; }
- (void)setBoundBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset
    index:(NSUInteger)index vertex:(BOOL)vertex
{
    if (_ended || index>=31) { [_buffer markEncodingError:kIOReturnBadArgument]; return; }
    NSMutableDictionary *bindings=vertex?_vertexBindings:_fragmentBindings;
    if (!buffer && !offset) { [bindings removeObjectForKey:@(index)]; return; }
    if (![buffer isKindOfClass:[A5MaliPrivateBuffer class]] || offset>=buffer.length) {
        [_buffer markEncodingError:kIOReturnBadArgument]; return;
    }
    A5MaliBufferBinding *binding=[A5MaliBufferBinding bindingWithBuffer:buffer offset:offset
        length:buffer.length-offset device:_buffer.device error:NULL];
    if (!binding) [_buffer markEncodingError:kIOReturnBadArgument];
    else bindings[@(index)]=binding;
}
- (void)setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index
{ A5MaliBufferBinding *b=_vertexBindings[@(index)]; if(!b.buffer){[_buffer markEncodingError:kIOReturnBadArgument];return;} [self setBoundBuffer:b.buffer offset:offset index:index vertex:YES]; }
- (void)setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index
{ A5MaliBufferBinding *b=_fragmentBindings[@(index)]; if(!b.buffer){[_buffer markEncodingError:kIOReturnBadArgument];return;} [self setBoundBuffer:b.buffer offset:offset index:index vertex:NO]; }
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{ [self setBoundBytes:bytes length:length index:index vertex:YES]; }
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{ [self setBoundBytes:bytes length:length index:index vertex:NO]; }
- (void)setBoundBytes:(const void *)bytes length:(NSUInteger)length index:(NSUInteger)index vertex:(BOOL)vertex
{
    if (_ended || index>=31) { [_buffer markEncodingError:kIOReturnBadArgument]; return; }
    NSMutableDictionary *bindings=vertex?_vertexBindings:_fragmentBindings;
    if (!bytes && !length) { [bindings removeObjectForKey:@(index)]; return; }
    A5MaliBufferBinding *binding=[A5MaliBufferBinding bindingWithBytes:bytes length:length
        device:_buffer.device error:NULL];
    if(!binding)[_buffer markEncodingError:kIOReturnBadArgument]; else bindings[@(index)]=binding;
}
- (void)setFragmentSamplerState:(A5MaliSamplerState *)sampler atIndex:(NSUInteger)index
{
    if (_ended || index>=16 || (sampler && (![sampler isKindOfClass:[A5MaliSamplerState class]] ||
        sampler.device!=_buffer.device))) { [_buffer markEncodingError:kIOReturnBadArgument]; return; }
    if(sampler)_samplers[@(index)]=sampler;else[_samplers removeObjectForKey:@(index)];
}
- (void)setScissorRect:(MTLScissorRect)rect
{
    if (_ended || !rect.width || !rect.height || rect.x>_destination.width ||
        rect.y>_destination.height || rect.width>_destination.width-rect.x ||
        rect.height>_destination.height-rect.y) [_buffer markEncodingError:kIOReturnBadArgument];
    else _scissor=rect;
}

- (void)setViewport:(MTLViewport)viewport
{
    /* Setters are independent. Draw-time profile validation decides which
     * genuine fixed or dynamic viewport the compiled shader can consume. */
    if (_ended || !isfinite(viewport.originX) || !isfinite(viewport.originY) ||
        !isfinite(viewport.width) || !isfinite(viewport.height) ||
        !isfinite(viewport.znear) || !isfinite(viewport.zfar) ||
        viewport.originX<0 || viewport.originY<0 || viewport.width<=0 || viewport.height<=0 ||
        viewport.width>4096-viewport.originX || viewport.height>4096-viewport.originY ||
        viewport.znear<0 || viewport.znear>viewport.zfar || viewport.zfar>1)
        [_buffer markEncodingError:kIOReturnUnsupported];
    else {
        _viewport = viewport;
        _hasViewport = YES;
    }
}

- (BOOL)encodeCompiledDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count
{
#if !A5_MALI_NATIVE_RENDER
    (void)primitiveType; (void)count; return NO;
#else
    A5MaliCompiledPipeline *pipeline=(id)_pipeline;
    const A5MaliCompiledProfile *profile=pipeline.profile;
    if (profile && profile->profileID>=200) return [self encodeCompiledMiscDraw:primitiveType vertexCount:count];
    if (!profile || count<3 || count>A5RuntimeMaxVertices ||
        (primitiveType!=MTLPrimitiveTypeTriangle && primitiveType!=MTLPrimitiveTypeTriangleStrip) ||
        (primitiveType==MTLPrimitiveTypeTriangle && count%3)) return NO;
    A5MaliMetalTexture *source=_textures[@3], *destination=_attachments[@0];
    A5MaliSamplerState *sampler=_samplers[@0];
    MTLSamplerDescriptor *sd=sampler.descriptor;
    MTLViewport viewport=_hasViewport?_viewport:
        (MTLViewport){0,0,destination.width,destination.height,0,1};
    for(NSNumber *key in _attachments)
        if(_attachments[key].pixelFormat!=profile->colorFormats[key.unsignedIntegerValue])return NO;
    if (!source || !destination || source==destination || source.device!=_buffer.device ||
        (source.privateSurface.iosurface && destination.privateSurface.iosurface &&
         IOSurfaceGetID(source.privateSurface.iosurface)==IOSurfaceGetID(destination.privateSurface.iosurface)) ||
        source.pixelFormat!=MTLPixelFormatBGRA8Unorm ||
        destination.pixelFormat!=profile->colorFormats[0] ||
        !(destination.usage&MTLTextureUsageRenderTarget) ||
        !sampler || sampler.device!=_buffer.device ||
        sd.minFilter!=MTLSamplerMinMagFilterNearest || sd.magFilter!=MTLSamplerMinMagFilterNearest ||
        sd.mipFilter!=MTLSamplerMipFilterNotMipmapped || !sd.normalizedCoordinates ||
        sd.sAddressMode!=MTLSamplerAddressModeClampToEdge ||
        sd.tAddressMode!=MTLSamplerAddressModeClampToEdge ||
        sd.rAddressMode!=MTLSamplerAddressModeClampToEdge || sd.maxAnisotropy!=1 ||
        sd.compareFunction!=MTLCompareFunctionNever || sd.lodMinClamp!=0 ||
        isnan(sd.lodMaxClamp) || sd.lodMaxClamp<0 ||
        ((profile->flags&A5MaliProfileFixedViewport) &&
         (viewport.originX!=0 || viewport.originY!=0 || viewport.width!=1080 ||
          viewport.height!=1920 || viewport.znear!=0 || viewport.zfar!=1))) return NO;

    /* Retain binding identity at draw time. Shared contents are deliberately
     * captured later, under the command buffer's commit lock. setBytes already
     * owns an immutable copy, and private buffers retain real kernel handles. */
    NSArray<NSDictionary<NSNumber *,A5MaliBufferBinding *> *> *bindings=
        @[[ _vertexBindings copy ],[ _fragmentBindings copy ]];
    NSMutableArray<NSMutableDictionary<NSNumber *,NSNumber *> *> *windows=
        [NSMutableArray arrayWithObjects:[NSMutableDictionary new],[NSMutableDictionary new],nil];
    windows[0][@1]=@(count*48);
    for (uint32_t i=0;i<profile->resourceCount;++i) {
        const A5MaliCompiledResource *r=profile->resources+i;
        if (r->kind!=A5MaliResourceBuffer) continue;
        if (r->metalIndex>=31 || !r->uniformBytes || r->windowOffset ||
            (r->flags&A5MaliResourceWrite) ||
            (r->stage!=A5MaliStageVertex && r->stage!=A5MaliStageFragment)) return NO;
        NSUInteger stage=r->stage==A5MaliStageFragment;
        NSUInteger required=MAX(windows[stage][@(r->metalIndex)].unsignedIntegerValue,r->uniformBytes);
        windows[stage][@(r->metalIndex)]=@(required);
    }
    for (NSUInteger stage=0;stage<2;++stage)
        for (NSNumber *slot in windows[stage]) {
            A5MaliBufferBinding *b=bindings[stage][slot];
            if (!b || b.device!=_buffer.device || b.length<windows[stage][slot].unsignedIntegerValue ||
                (b.buffer && !b.buffer.readyForRead)) return NO;
        }
    MTLScissorRect scissor=_scissor;
    BOOL sourceOver=pipeline.sourceOver;
    return [[_buffer privateBuffer] encodeNativeWork:^kern_return_t(A5MaliClient *client,A5MaliFence *fence) {
        A5NativeQueryRequest query={.header={1,sizeof(query),0,0}};
        query.surfaces[0]=source.privateSurface.resource.token;
        query.surfaces[1]=destination.privateSurface.resource.token;
        if (!query.surfaces[0] || !query.surfaces[1] || query.surfaces[0]==query.surfaces[1])
            return kIOReturnBadArgument;
        unsigned handleCount=0;
        for (NSUInteger stage=0;stage<2;++stage)
            for (NSNumber *slot in windows[stage]) {
                A5MaliBufferBinding *b=bindings[stage][slot];
                if (b.buffer && !b.buffer.readyForRead) return kIOReturnNotReady;
                uint64_t handle=b.privateKernelHandle;
                if (!handle) continue;
                unsigned i=0; for (;i<handleCount;++i) if(query.buffers[i]==handle)break;
                if(i==handleCount){if(handleCount==A5NativeSlots)return kIOReturnNoResources;
                    query.buffers[handleCount++]=handle;}
            }
        A5NativeQueryResult mapped={0};
        kern_return_t result=A5MaliQueryNative(client,&query,&mapped);
        if(result)return result;
        A5MaliMetalTexture *images[2]={source,destination};
        A5RuntimeDraw draw={.profile=profile,.descriptorGPUVA=mapped.jobVA,
            .vertexCount=(uint32_t)count,
            .primitive=primitiveType==MTLPrimitiveTypeTriangle?A5RuntimeTriangle:A5RuntimeTriangleStrip,
            .blend=sourceOver?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy,
            .scissorX=(uint32_t)scissor.x,.scissorY=(uint32_t)scissor.y,
            .scissorWidth=(uint32_t)scissor.width,.scissorHeight=(uint32_t)scissor.height,
            .viewportX=viewport.originX,.viewportY=viewport.originY,.viewportWidth=viewport.width,
            .viewportHeight=viewport.height,.viewportNear=viewport.znear,.viewportFar=viewport.zfar};
        for(unsigned i=0;i<2;++i){
            A5NativeSpan s=mapped.surfaces[i]; A5MaliMetalTexture *t=images[i];
            if(s.width!=t.width || s.height!=t.height || s.rowBytes!=t.privateSurface.rowBytes ||
                s.pixelFormat!=linearPixelCode(t.pixelFormat) ||
                !validLinearRow(s.width,s.height,s.rowBytes,t.pixelFormat) ||
                (uint64_t)s.rowBytes*s.height>s.bytes ||
                (s.usage&(i?(A5MaliRead|A5MaliWrite):A5MaliRead))!=
                    (i?(A5MaliRead|A5MaliWrite):A5MaliRead))return kIOReturnBadArgument;
            A5RuntimeImage image={s.gpuVA,s.bytes,s.width,s.height,s.rowBytes,(uint32_t)t.pixelFormat};
            if(i)draw.destination=image;else draw.source=image;
        }
        NSMutableArray<NSData *> *snapshots=[NSMutableArray new];
        for(NSUInteger stage=0;stage<2;++stage)
            for(NSNumber *slot in windows[stage]){
                A5MaliBufferBinding *b=bindings[stage][slot];
                A5RuntimeBuffer native={0};
                if(b.privateKernelHandle){
                    unsigned i=0;for(;i<handleCount;++i)if(query.buffers[i]==b.privateKernelHandle)break;
                    if(i==handleCount || b.buffer.length>mapped.buffers[i].bytes ||
                        b.offset>UINT32_MAX || b.buffer.length>UINT32_MAX)return kIOReturnBadArgument;
                    native=(A5RuntimeBuffer){mapped.buffers[i].gpuVA,(uint32_t)b.buffer.length,(uint32_t)b.offset,NULL};
                }else{
                    NSData *data=[b capturePrefixBytesForSubmission:windows[stage][slot].unsignedIntegerValue error:NULL];
                    if(!data)return kIOReturnBadArgument;
                    [snapshots addObject:data];
                    native=(A5RuntimeBuffer){0,(uint32_t)data.length,0,data.bytes};
                }
                if(stage)draw.fragmentBuffers[slot.unsignedIntegerValue]=native;
                else draw.vertexBuffers[slot.unsignedIntegerValue]=native;
            }
        NSMutableData *jobs=[NSMutableData dataWithLength:A5RuntimeJobBytes];
        int encoded=A5MaliEncodeRuntimeDraw(&draw,jobs.mutableBytes,jobs.length);
        /* Keep commit snapshots alive through descriptor upload and the
         * synchronous terminal fence, including optimized ARC builds. */
        __attribute__((objc_precise_lifetime)) NSArray *retainedSnapshots=snapshots;
        (void)retainedSnapshots;
        if(encoded!=A5RuntimeOK)return encoded==A5RuntimeUnsupported?kIOReturnUnsupported:kIOReturnBadArgument;
        A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5RuntimeJobBytes,
            .vertexOffset=A5RuntimeVertexOffset,.tilerOffset=A5RuntimeTilerOffset,
            .fragmentOffset=A5RuntimeFragmentOffset,.readSurfaces=3,.writeSurfaces=2,
            .readBuffers=(1u<<handleCount)-1u,.profileID=profile->profileID,.mappingEpoch=mapped.flags};
        memcpy(submit.surfaces,query.surfaces,sizeof(submit.surfaces));
        memcpy(submit.buffers,query.buffers,sizeof(submit.buffers));
        return A5MaliSubmitNative(client,&submit,jobs.bytes,fence);
    }];
#endif
}

- (BOOL)encodeCompiledMiscDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count
{
#if !A5_MALI_NATIVE_RENDER
    (void)primitiveType;(void)count;return NO;
#else
    A5MaliCompiledPipeline *pipeline=(id)_pipeline;
    const A5MaliCompiledProfile *profile=pipeline.profile;
    if(!profile || !(profile->profileID==200 || profile->profileID==202 ||
        profile->profileID==204 || profile->profileID==206 || profile->profileID==207 ||
        (profile->profileID>=300 && profile->profileID<=302)) ||
        !profile->passCount || profile->passCount>2 || count<3 || count>A5RuntimeMaxVertices ||
        (primitiveType!=MTLPrimitiveTypeTriangle && primitiveType!=MTLPrimitiveTypeTriangleStrip) ||
        (primitiveType==MTLPrimitiveTypeTriangle && count%3))return NO;
    BOOL path=profile->profileID>=300;
    if(path && (count!=4 || primitiveType!=MTLPrimitiveTypeTriangleStrip))return NO;
    NSDictionary<NSNumber *,A5MaliMetalTexture *> *attachments=[_attachments copy];
    NSDictionary<NSNumber *,A5MaliMetalTexture *> *textures=[_textures copy];
    for(NSNumber *key in attachments)
        if(attachments[key].pixelFormat!=profile->colorFormats[key.unsignedIntegerValue])return NO;
    NSMutableArray<A5MaliMetalTexture *> *mappedImages=[NSMutableArray new];
    NSMutableArray<NSNumber *> *imageSlots=[NSMutableArray new];
    uint32_t readImages=0;
    for(uint32_t i=0;i<profile->passCount;++i){
        uint32_t target=profile->passes[i].logicalTarget;
        A5MaliMetalTexture *image=attachments[@(target)];
        if(target>=8 || !image || !(image.usage&MTLTextureUsageRenderTarget))return NO;
        for(A5MaliMetalTexture *old in mappedImages)
            if(image==old || image.privateSurface.resource.token==old.privateSurface.resource.token ||
                (image.privateSurface.iosurface && old.privateSurface.iosurface && IOSurfaceGetID(image.privateSurface.iosurface)==IOSurfaceGetID(old.privateSurface.iosurface)))return NO;
        [mappedImages addObject:image];[imageSlots addObject:@(target)];
    }
    for(uint32_t i=0;i<profile->resourceCount;++i){
        const A5MaliCompiledResource *r=profile->resources+i;
        if(r->kind==A5MaliResourceSampler){
            if(!(r->flags&A5MaliResourceImmutableSampler))return NO;
            continue; /* Actual AIR constexpr state, not an ignored application sampler. */
        }
        if(r->kind!=A5MaliResourceTexture)continue;
        if(r->stage!=A5MaliStageFragment || r->metalIndex>=31)return NO;
        A5MaliMetalTexture *image=textures[@(r->metalIndex)];
        if(!image || image.pixelFormat!=MTLPixelFormatBGRA8Unorm || !(image.usage&MTLTextureUsageShaderRead))return NO;
        for(NSUInteger j=0;j<mappedImages.count;++j){A5MaliMetalTexture *old=mappedImages[j];
            if(image==old || image.privateSurface.resource.token==old.privateSurface.resource.token ||
                (image.privateSurface.iosurface && old.privateSurface.iosurface && IOSurfaceGetID(image.privateSurface.iosurface)==IOSurfaceGetID(old.privateSurface.iosurface)))return NO;
        }
        if(mappedImages.count==A5NativeSlots)return NO;
        readImages|=1u<<mappedImages.count;[mappedImages addObject:image];[imageSlots addObject:@(32+r->metalIndex)];
    }
    NSArray<NSDictionary<NSNumber *,A5MaliBufferBinding *> *> *bindings=@[[_vertexBindings copy],[_fragmentBindings copy]];
    NSMutableArray<NSMutableDictionary<NSNumber *,NSNumber *> *> *windows=
        [NSMutableArray arrayWithObjects:[NSMutableDictionary new],[NSMutableDictionary new],nil];
    NSMutableArray<NSMutableSet<NSNumber *> *> *storageSlots=
        [NSMutableArray arrayWithObjects:[NSMutableSet new],[NSMutableSet new],nil];
    if(profile->profileID==206)windows[0][@1]=@(count*48);
    for(uint32_t i=0;i<profile->resourceCount;++i){const A5MaliCompiledResource*r=profile->resources+i;
        if(r->kind!=A5MaliResourceBuffer)continue;
        if(r->metalIndex>=31 || r->windowOffset || (r->flags&A5MaliResourceWrite) ||
            (r->stage!=A5MaliStageVertex && r->stage!=A5MaliStageFragment))return NO;
        NSUInteger stage=r->stage==A5MaliStageFragment;NSNumber *slot=@(r->metalIndex);
        A5MaliBufferBinding *b=bindings[stage][slot];
        NSUInteger required=(r->flags&A5MaliResourceStorage)?b.length:r->uniformBytes;
        required=MAX(required,windows[stage][slot].unsignedIntegerValue);
        if(!b || !required || required>b.length || b.device!=_buffer.device ||
            (b.buffer && !b.buffer.readyForRead))return NO;
        windows[stage][slot]=@(required);
        if(r->flags&A5MaliResourceStorage)[storageSlots[stage] addObject:slot];
    }
    MTLViewport viewport=_hasViewport?_viewport:(MTLViewport){0,0,_destination.width,_destination.height,0,1};
    MTLScissorRect scissor=_scissor;BOOL sourceOver=pipeline.sourceOver;
    /* Preserve failed-release ownership until the connection closes. Kernel
     * references remain pinned when DMA completion is ambiguous; never claim
     * an allocation was freed merely because the command returned an error. */
    A5MaliRestrictedDevice *device=_buffer.device;
    return [[_buffer privateBuffer] encodeNativeWork:^kern_return_t(A5MaliClient *client,A5MaliFence*fence){
        NSMutableArray<NSNumber *> *temporaryHandles=[NSMutableArray new];
        kern_return_t (^execute)(void)=^kern_return_t{
            A5RuntimeMiscDraw command={.draw={.profile=profile,.vertexCount=(uint32_t)count,
                .primitive=primitiveType==MTLPrimitiveTypeTriangle?A5RuntimeTriangle:A5RuntimeTriangleStrip,
                .blend=sourceOver?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy,
                .scissorX=(uint32_t)scissor.x,.scissorY=(uint32_t)scissor.y,
                .scissorWidth=(uint32_t)scissor.width,.scissorHeight=(uint32_t)scissor.height,
                .viewportX=viewport.originX,.viewportY=viewport.originY,.viewportWidth=viewport.width,
                .viewportHeight=viewport.height,.viewportNear=viewport.znear,.viewportFar=viewport.zfar}};
            A5NativeQueryRequest query={.header={1,sizeof(query),0,0}};
            for(NSUInteger i=0;i<mappedImages.count;++i)query.surfaces[i]=mappedImages[i].privateSurface.resource.token;
            NSMutableArray<NSData *> *snapshots=[NSMutableArray new];
            NSMutableArray<NSMutableDictionary<NSNumber *,NSNumber *> *> *handles=
                [NSMutableArray arrayWithObjects:[NSMutableDictionary new],[NSMutableDictionary new],nil];
            unsigned bufferCount=0;
            for(NSUInteger stage=0;stage<2;++stage)
                for(NSNumber *slot in windows[stage]){
                    A5MaliBufferBinding *binding=bindings[stage][slot];
                    if(binding.buffer && !binding.buffer.readyForRead)return kIOReturnNotReady;
                    uint64_t handle=binding.privateKernelHandle;
                    A5RuntimeBuffer native={0};
                    if(!handle){
                        NSData *data=[binding capturePrefixBytesForSubmission:windows[stage][slot].unsignedIntegerValue error:NULL];
                        if(!data)return kIOReturnBadArgument;
                        [snapshots addObject:data];
                        if([storageSlots[stage] containsObject:slot]){
                            kern_return_t kr=A5MaliCreateNativeBuffer(client,(uint32_t)data.length,data.bytes,(uint32_t)data.length,&handle);
                            if(handle)[temporaryHandles addObject:@(handle)];
                            if(kr)return kr;
                            native.bytes=(uint32_t)data.length; /* actual snapshot, no truncated SSBO */
                        }else native=(A5RuntimeBuffer){0,(uint32_t)data.length,0,data.bytes};
                    }else{
                        native.bytes=(uint32_t)binding.buffer.length;native.offset=(uint32_t)binding.offset;
                    }
                    if(handle){
                        unsigned i=0;for(;i<bufferCount;++i)if(query.buffers[i]==handle)break;
                        if(i==bufferCount){if(bufferCount==A5NativeSlots)return kIOReturnNoResources;query.buffers[bufferCount++]=handle;}
                        handles[stage][slot]=@(i);
                    }
                    if(stage)command.draw.fragmentBuffers[slot.unsignedIntegerValue]=native;
                    else command.draw.vertexBuffers[slot.unsignedIntegerValue]=native;
                }
            __attribute__((objc_precise_lifetime)) NSArray *retainSnapshots=snapshots;(void)retainSnapshots;
            for(uint32_t pass=0;pass<profile->passCount;++pass){
                A5NativeQueryResult mapped={0};kern_return_t kr=A5MaliQueryNative(client,&query,&mapped);if(kr)return kr;
                command.draw.descriptorGPUVA=mapped.jobVA;command.passIndex=pass;
                for(NSUInteger i=0;i<mappedImages.count;++i){
                    A5MaliMetalTexture *t=mappedImages[i];A5NativeSpan s=mapped.surfaces[i];
                    if(!query.surfaces[i] || s.width!=t.width || s.height!=t.height ||
                        s.rowBytes!=t.privateSurface.rowBytes || s.pixelFormat!=linearPixelCode(t.pixelFormat) ||
                        !validLinearRow(s.width,s.height,s.rowBytes,t.pixelFormat) ||
                        (uint64_t)s.rowBytes*s.height>s.bytes ||
                        (s.usage&((readImages&(1u<<i))?A5MaliRead:(A5MaliRead|A5MaliWrite)))!=
                            ((readImages&(1u<<i))?A5MaliRead:(A5MaliRead|A5MaliWrite)))return kIOReturnBadArgument;
                    A5RuntimeImage image={s.gpuVA,s.bytes,s.width,s.height,s.rowBytes,(uint32_t)t.pixelFormat};
                    unsigned slot=imageSlots[i].unsignedIntValue;
                    if(slot<8)command.colorAttachments[slot]=image;else command.fragmentTextures[slot-32]=image;
                }
                for(NSUInteger stage=0;stage<2;++stage)
                    for(NSNumber *slot in handles[stage]){
                        unsigned i=handles[stage][slot].unsignedIntValue;
                        A5RuntimeBuffer *b=stage?&command.draw.fragmentBuffers[slot.unsignedIntegerValue]:
                            &command.draw.vertexBuffers[slot.unsignedIntegerValue];
                        if(b->bytes>mapped.buffers[i].bytes)return kIOReturnBadArgument;
                        b->gpuVA=mapped.buffers[i].gpuVA;
                    }
                NSMutableData *jobs=[NSMutableData dataWithLength:A5RuntimeJobBytes];
                int encoded;
                if(path){
                    A5RuntimePathDraw pathDraw={.draw=command.draw,.passIndex=pass};
                    pathDraw.draw.blend=(profile->flags&A5MaliProfileCoverageAdd)?
                        A5RuntimePathBlendCoverageAdd:A5RuntimeBlendPremultipliedSourceOver;
                    memcpy(pathDraw.colorAttachments,command.colorAttachments,sizeof(pathDraw.colorAttachments));
                    encoded=A5MaliEncodeRuntimePathPass(&pathDraw,jobs.mutableBytes,jobs.length);
                }else encoded=A5MaliEncodeRuntimeMiscPass(&command,jobs.mutableBytes,jobs.length);
                if(encoded)return encoded==A5RuntimeUnsupported?kIOReturnUnsupported:kIOReturnBadArgument;
                A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5RuntimeJobBytes,
                    .vertexOffset=A5RuntimeVertexOffset,.tilerOffset=A5RuntimeTilerOffset,
                    .fragmentOffset=A5RuntimeFragmentOffset,.readSurfaces=readImages|(1u<<pass),
                    .writeSurfaces=1u<<pass,.readBuffers=(1u<<bufferCount)-1u,
                    .profileID=profile->passes[pass].passID,.mappingEpoch=mapped.flags};
                memcpy(submit.surfaces,query.surfaces,sizeof(submit.surfaces));
                memcpy(submit.buffers,query.buffers,sizeof(submit.buffers));
                kr=A5MaliSubmitNative(client,&submit,jobs.bytes,fence);if(kr)return kr;
            }
            return KERN_SUCCESS;
        };
        kern_return_t result=execute();
        for(NSNumber *handle in temporaryHandles){
            kern_return_t released=A5MaliReleaseNativeBuffer(client,handle.unsignedLongLongValue);
            if(released){
                static char pendingKey;
                @synchronized(device){
                    NSMutableArray *pending=objc_getAssociatedObject(device,&pendingKey);
                    if(!pending){pending=[NSMutableArray new];objc_setAssociatedObject(device,&pendingKey,pending,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
                    [pending addObject:handle];
                }
                if(!result)result=released;
            }
        }
        return result;
    }];
#endif
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType
          vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount
{
    if ([_pipeline isKindOfClass:[A5MaliCompiledPipeline class]]) {
        if (_ended || vertexStart || ![self encodeCompiledDraw:primitiveType vertexCount:vertexCount])
            [_buffer markEncodingError:kIOReturnUnsupported];
        else _hasDraw=YES;
        return;
    }
    if (_ended || _hasDraw || primitiveType != MTLPrimitiveTypeTriangle ||
        vertexStart || vertexCount != 3)
        [_buffer markEncodingError:kIOReturnUnsupported];
    else _hasDraw = YES;
}
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start
    vertexCount:(NSUInteger)count instanceCount:(NSUInteger)instances
{ if(instances!=1)[_buffer markEncodingError:kIOReturnUnsupported];else[self drawPrimitives:type vertexStart:start vertexCount:count]; }

- (void)endEncoding
{
    if (_ended) return;
    _ended = YES;
    if(!_hasDraw){[_buffer finishEncoding];return;} /* A clear-only pass is valid. */
    if ([_pipeline isKindOfClass:[A5MaliCompiledPipeline class]]) {
        [_buffer finishEncoding]; return;
    }
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
        (_hasViewport && (_viewport.originX!=0 || _viewport.originY!=0 ||
            _viewport.width != _destination.width || _viewport.height != _destination.height ||
            _viewport.znear!=0 || _viewport.zfar!=1)) ||
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
        (t.storageMode != MTLStorageModeShared && t.storageMode != MTLStorageModePrivate)) {
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
