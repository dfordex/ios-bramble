/* SPDX-License-Identifier: MIT
 * Narrow Metal-selector adapter for the real typed Mali copy path.
 * These classes deliberately claim no Metal protocol conformance.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
#import "A5MaliNativeTextureOps.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliShaderCompileRequest.h"
#import "A5MaliShaderCompiledCache.h"
#import "A5MaliNative.h"
#import "A5MaliNativeUpload.h"
#include "../a5xelte-air-translation/families/runtime_encode.h"
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include "../a5xelte-air-translation/families/runtime_path_encode.h"
#include "../a5xelte-air-translation/families/runtime_clear.h"
#include <math.h>
#include <time.h>
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

/* Independent bounded receipt budgets: resource metadata only, never payloads. */
static BOOL diagnosticTake(atomic_uint *counter,unsigned limit)
{
    unsigned value=atomic_load_explicit(counter,memory_order_relaxed);
    while(value<limit){
        if(atomic_compare_exchange_weak_explicit(counter,&value,value+1,
            memory_order_relaxed,memory_order_relaxed))return YES;
    }
    return NO;
}
static atomic_uint encoderDiagnosticCount,commitDiagnosticCount,nativePhaseDiagnosticCount;
static atomic_uint commandDiagnosticNext,queueCreationDiagnosticCount,bufferCreationDiagnosticCount,unretainedDiagnosticCount;
static atomic_uint copyRejectionDiagnosticCount;
static atomic_uint protectionDiagnosticCount;
#if A5_MALI_NATIVE_RENDER
static atomic_uint indexedDrawDiagnosticCount;
#endif
static void logQueuePhase(const char *phase,unsigned bufferID,BOOL created,atomic_uint *counter,unsigned limit)
{
    if(diagnosticTake(counter,limit))fprintf(stderr,
        "A5XELTE Metal queue: phase=%s cb=%u created=%u\n",phase,bufferID,created);
}
static __attribute__((unused)) void logNativePhase(unsigned bufferID,const char *phase,uint32_t profile,kern_return_t result)
{
    if(diagnosticTake(&nativePhaseDiagnosticCount,128))fprintf(stderr,
        "A5XELTE Metal native phase: cb=%u phase=%s profile=%u result=%x\n",bufferID,phase,profile,(unsigned)result);
}

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
    profile:(const A5MaliCompiledProfile *)profile sourceOver:(BOOL)sourceOver
    compileRequestID:(nullable NSString *)requestID;
@end
@implementation A5MaliCompiledPipeline {
    const A5MaliCompiledProfile *_profile;
    BOOL _sourceOver;
    NSString *_compileRequestID;
    NSLock *_compiledCacheLock;
    A5MaliShaderCompiledCacheEntry *_compiledCacheEntry;
    double _nextCachePoll;
}
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
    profile:(const A5MaliCompiledProfile *)profile sourceOver:(BOOL)sourceOver
    compileRequestID:(NSString *)requestID
{
    if ((self = [super initWithDevice:device])) {
        _profile=profile;_sourceOver=sourceOver;
        _compileRequestID=(profile->profileID==602 || profile->profileID==603)?[requestID copy]:nil;
        _compiledCacheLock=[NSLock new];
    }
    return self;
}
- (const A5MaliCompiledProfile *)profile
{
    [_compiledCacheLock lock];
    struct timespec uptime;
    BOOL haveClock=!clock_gettime(CLOCK_MONOTONIC,&uptime);
    double now=haveClock?uptime.tv_sec+uptime.tv_nsec/1e9:0;
    if(_compileRequestID && !_compiledCacheEntry && (!haveClock || now>=_nextCachePoll)) {
        _nextCachePoll=now+5; /* Compilation is background work, never per-draw I/O. */
        A5MaliShaderCompiledCacheEntry *entry=A5MaliLoadShaderCompiledCache(_compileRequestID,_profile,NULL);
        if(entry) {
            _compiledCacheEntry=entry;_profile=entry.profile;
            fprintf(stderr,"A5XELTE Metal compile cache: bound profile=%u request=%s source=phone-compiled\n",
                _profile->profileID,_compileRequestID.UTF8String);
        }
    }
    const A5MaliCompiledProfile *profile=_profile;
    [_compiledCacheLock unlock];
    return profile;
}
- (BOOL)sourceOver { return _sourceOver; }
@end

@interface A5MaliSurface (NativeResourceAccess)
- (A5MaliResource)resource;
@end

static __attribute__((unused)) BOOL textureBackingAliases(A5MaliMetalTexture *a,A5MaliMetalTexture *b)
{
    if(a==b)return YES;
    if(a.buffer && a.buffer==b.buffer)return YES;
    uint64_t at=a.privateSurface.resource.token,bt=b.privateSurface.resource.token;
    return (at && at==bt) || (a.privateSurface.iosurface && b.privateSurface.iosurface &&
        IOSurfaceGetID(a.privateSurface.iosurface)==IOSurfaceGetID(b.privateSurface.iosurface));
}

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
    unsigned _diagnosticID;
    NSUInteger _renderEncoders,_blitEncoders,_drawCalls,_queuedDraws,_clearCommands,_blitCommands;
    NSCondition *_condition;
    NSMutableArray<MTLCommandBufferHandler> *_scheduled;
    NSMutableArray<MTLCommandBufferHandler> *_completed;
    NSMutableArray<A5MaliTexturePassBacking *> *_memorylessPassBackings;
}
- (instancetype)initWithQueue:(A5MaliMetalQueue *)queue
                privateBuffer:(A5MaliCommandBuffer *)buffer;
- (A5MaliCommandBuffer *)privateBuffer;
- (void)markEncodingError:(kern_return_t)code selector:(SEL)selector;
- (unsigned)diagnosticID;
- (void)noteDrawCall;
- (void)noteQueuedDraw;
- (void)noteBlitCommand;
- (void)finishEncoding;
- (BOOL)encodeNativeClear:(A5MaliMetalTexture *)target color:(MTLClearColor)color;
@end

@interface A5MaliMetalBlitEncoder () {
    A5MaliMetalBuffer *_buffer;
    BOOL _ended;
    NSMutableArray<NSString *> *_debugGroups;
}
- (instancetype)initWithBuffer:(A5MaliMetalBuffer *)buffer;
- (BOOL)validateActiveForSelector:(SEL)selector;
- (BOOL)validateTexture:(id)texture selector:(SEL)selector;
- (void)rejectUnsupportedOperationForSelector:(SEL)selector;
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
- (BOOL)encodeCompiledMiscDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count
    indexBinding:(nullable A5MaliBufferBinding *)indexBinding indexCount:(NSUInteger)indexCount
    indexSize:(NSUInteger)indexSize;
- (BOOL)validateActiveForSelector:(SEL)selector;
- (void)setBoundBuffer:(nullable A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset
    index:(NSUInteger)index vertex:(BOOL)vertex selector:(SEL)selector;
- (void)setBoundBytes:(const void * _Nullable)bytes length:(NSUInteger)length
    index:(NSUInteger)index vertex:(BOOL)vertex selector:(SEL)selector;
@end

@implementation A5MaliRestrictedDevice (LimitedMetalSelectors)

- (A5MaliMetalQueue *)newCommandQueue
{
    A5MaliMetalQueue *queue=[[A5MaliMetalQueue alloc] initWithDevice:self];
    logQueuePhase("newCommandQueue",0,queue!=nil,&queueCreationDiagnosticCount,16);
    return queue;
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
    /* Capture the actual complete pipeline, not an inferred state from one
     * fragment constant. The worker independently validates and compiles it. */
    NSString *compileRequestID=nil;
    if(authenticatedPair && [vertex compileRequestPayload] && [fragment compileRequestPayload]) {
        NSError *requestError=nil;
        NSDictionary *request=A5MaliShaderCompilePipelinePayload(descriptor,
            [vertex compileRequestPayload],[fragment compileRequestPayload],&requestError);
        A5MaliShaderForwardResult forwarded=request?A5MaliForwardShaderCompileRequest(request,&compileRequestID,&requestError):A5MaliShaderForwardFailed;
        static atomic_uint requestReceipts;
        if(atomic_fetch_add_explicit(&requestReceipts,1,memory_order_relaxed)<16)
            fprintf(stderr,"A5XELTE Metal compile request: pipeline vertex=%s fragment=%s result=%ld request=%s\n",
                [[vertex name]UTF8String],[[fragment name]UTF8String],(long)forwarded,compileRequestID.UTF8String?:"unavailable");
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
        profile->profileID==600 || profile->profileID==601 || profile->profileID==602 || profile->profileID==603 ||
        (profile->profileID>=300 && profile->profileID<=302));
    if(executable && [[self privateDevice]supportsNativePrograms]){
        if(error)*error=nil;
        logPipelineDecision(self,descriptor,profileID,YES,@"authenticated executable profile");
        return [[A5MaliCompiledPipeline alloc]initWithDevice:self profile:profile
            sourceOver:descriptor.colorAttachments[0].isBlendingEnabled compileRequestID:compileRequestID];
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
    A5MaliMetalBuffer *buffer=[[A5MaliMetalBuffer alloc] initWithQueue:self
        privateBuffer:[[_device privateDevice] newCommandBuffer]];
    logQueuePhase("commandBuffer",buffer.diagnosticID,buffer!=nil,&bufferCreationDiagnosticCount,64);
    return buffer;
}
- (A5MaliMetalBuffer *)commandBufferWithUnretainedReferences
{
    /* This adapter always retains imported IOSurfaces through completion. */
    logQueuePhase("commandBufferWithUnretainedReferences-unsupported",0,NO,&unretainedDiagnosticCount,32);
    return nil;
}

@end

@implementation A5MaliMetalBuffer

- (instancetype)initWithQueue:(A5MaliMetalQueue *)queue
                privateBuffer:(A5MaliCommandBuffer *)buffer
{
    if ((self = [super init])) {
        _queue = queue;
        _diagnosticID=atomic_fetch_add_explicit(&commandDiagnosticNext,1,memory_order_relaxed)+1;
        _privateBuffer = buffer;
        _scheduled = [NSMutableArray new];
        _completed = [NSMutableArray new];
        _memorylessPassBackings = [NSMutableArray new];
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
/* Stock Metal's protection setter emits a kernel protection command. This
 * driver has no protected allocations or protected submission mode: accepting
 * a nonzero request would misrepresent the isolation of its resources. Keep
 * that request as a sticky encoding error so commit never reaches the GPU.
 * QuartzCore also reads the property from its unconditional completion block. */
- (uint64_t)protectionOptions { return 0; }
- (void)setProtectionOptions:(uint64_t)options
{
    [_condition lock];
    BOOL committed = _status >= MTLCommandBufferStatusCommitted;
    if (!committed && options && !_error)
        _error = metalError(kIOReturnUnsupported);
    [_condition unlock];
    if (diagnosticTake(&protectionDiagnosticCount,64)) fprintf(stderr,
        "A5XELTE Metal protection: cb=%u requested=%llx supported=0 committed=%u result=%x\n",
        _diagnosticID,(unsigned long long)options,committed,
        (unsigned)(committed ? kIOReturnNotPermitted : options ? kIOReturnUnsupported : KERN_SUCCESS));
    /* Metal requires protection changes before commit. Preserve the terminal
     * result and callback state when a caller violates that contract. */
    if (committed) [NSException raise:NSInternalInconsistencyException
        format:@"Command-buffer protection cannot change after commit"];
}
/* The public timing contract uses zero while timestamps are unavailable.
 * CPU submission wall time would not be an honest GPU duration. */
- (NSTimeInterval)GPUStartTime { return 0; }
- (NSTimeInterval)GPUEndTime { return 0; }
- (NSTimeInterval)kernelStartTime { return 0; }
- (NSTimeInterval)kernelEndTime { return 0; }
- (unsigned)diagnosticID { return _diagnosticID; }
- (void)noteDrawCall { ++_drawCalls; }
- (void)noteQueuedDraw { ++_queuedDraws; }
- (void)noteBlitCommand { ++_blitCommands; }
- (void)markEncodingError:(kern_return_t)code selector:(SEL)selector
{
    [_condition lock];
    BOOL first=!_error;
    if (first) _error = metalError(code);
    [_condition unlock];
    if(first&&diagnosticTake(&encoderDiagnosticCount,64))fprintf(stderr,
        "A5XELTE Metal encoder: cb=%u first_error=%x selector=%s\n",
        _diagnosticID,(unsigned)code,sel_getName(selector));
}
- (void)finishEncoding { _encoderOpen = NO; }

- (A5MaliMetalBlitEncoder *)blitCommandEncoder
{
    [_condition lock];
    BOOL committed = _status >= MTLCommandBufferStatusCommitted;
    [_condition unlock];
    if (_encoderOpen || committed) return nil;
    _encoderOpen = YES;
    ++_blitEncoders;
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
        [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
    }
    NSMutableDictionary<NSNumber *,A5MaliMetalTexture *> *attachments=[NSMutableDictionary new];
    NSUInteger width=0,height=0;
    for(NSUInteger i=0;i<8;++i){
        MTLRenderPassColorAttachmentDescriptor *a=descriptor.colorAttachments[i];
        A5MaliMetalTexture *target=(id)a.texture;
        if(!target)continue;
        if(![target isKindOfClass:[A5MaliMetalTexture class]]||target.device!=_queue.device||
            !(target.usage&MTLTextureUsageRenderTarget)||target.textureType!=MTLTextureType2D||
            (!native&&(i||a.level||target.mipmapLevelCount!=1))||a.slice||a.depthPlane||a.resolveTexture||
            (a.storeAction!=MTLStoreActionStore&&(!native||a.storeAction!=MTLStoreActionDontCare))||
            (a.loadAction!=MTLLoadActionDontCare&&(!native||
                (a.loadAction!=MTLLoadActionLoad&&a.loadAction!=MTLLoadActionClear)))){
            [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
        }
        A5MaliTexturePassBacking *lease=nil;
        if(target.storageMode==MTLStorageModeMemoryless){
            if(!native||a.loadAction==MTLLoadActionLoad||a.storeAction!=MTLStoreActionDontCare){
                [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
            }
            lease=[target newMemorylessPassBackingForLevel:a.level error:NULL];
            if(!lease){[self markEncodingError:kIOReturnNoMemory selector:_cmd];return nil;}
            [_memorylessPassBackings addObject:lease];
        }
        target=[target newRenderViewForLevel:a.level memorylessLease:lease error:NULL];
        if(!target||(width&&(target.width!=width||target.height!=height))){
            [self markEncodingError:kIOReturnBadArgument selector:_cmd];return nil;
        }
        width=target.width;height=target.height;attachments[@(i)]=target;
        if(a.loadAction==MTLLoadActionClear){
            MTLClearColor c=a.clearColor;
            if(!isfinite(c.red)||!isfinite(c.green)||!isfinite(c.blue)||!isfinite(c.alpha)){
                [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
            }
            if(native){
                if(![self encodeNativeClear:target color:c]){[self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;}
                ++_clearCommands;
                continue;
            }
            if(target.pixelFormat!=MTLPixelFormatBGRA8Unorm ||
                c.red<0||c.red>1||c.green<0||c.green>1||c.blue<0||c.blue>1||c.alpha<0||c.alpha>1){
                [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
            }
            uint32_t color=(uint32_t)llround(c.blue*255)|((uint32_t)llround(c.green*255)<<8)|
                ((uint32_t)llround(c.red*255)<<16)|((uint32_t)llround(c.alpha*255)<<24);
            if(![_privateBuffer encodeClear:target.privateSurface
                rect:(A5MaliRect){0,0,(uint32_t)width,(uint32_t)height} bgra:color]){
                [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
            }
            ++_clearCommands;
        }
    }
    if(!attachments.count || (!native && !attachments[@0])){
        [self markEncodingError:kIOReturnUnsupported selector:_cmd];return nil;
    }
    _encoderOpen=YES;
    ++_renderEncoders;
    return [[A5MaliMetalRenderEncoder alloc] initWithBuffer:self attachments:attachments];
}

- (BOOL)encodeNativeClear:(A5MaliMetalTexture *)target color:(MTLClearColor)color
{
#if !A5_MALI_NATIVE_RENDER
    (void)target;(void)color;return NO;
#else
    unsigned diagnosticID=_diagnosticID;
    return [_privateBuffer encodeNativeWork:^kern_return_t(A5MaliClient*client,A5MaliFence*fence){
        A5NativeQueryRequest query={.header={1,sizeof(query),0,0}};
        query.surfaces[0]=target.privateSurface.resource.token;
        A5NativeQueryResult mapped={0};kern_return_t kr=A5MaliQueryNative(client,&query,&mapped);
        logNativePhase(diagnosticID,"clear-query17",0,kr);if(kr)return kr;
        A5NativeSpan s=mapped.surfaces[0];
        A5RuntimeImage destination={0};
        if(!A5MaliRuntimeImageForTexture(target,0,target.privateSurface,&s,A5MaliWrite,&destination))
            return kIOReturnBadArgument;
        A5RuntimeClear clear={.descriptorGPUVA=mapped.jobVA,.destination=destination,
            .color={color.red,color.green,color.blue,color.alpha}};
        NSMutableData *jobs=[NSMutableData dataWithLength:A5RuntimeJobBytes];
        int encoded=A5MaliEncodeRuntimeClear(&clear,jobs.mutableBytes,jobs.length);
        logNativePhase(diagnosticID,"clear-emitter",0,encoded);
        if(encoded)return encoded==A5RuntimeUnsupported?kIOReturnUnsupported:kIOReturnBadArgument;
        A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5RuntimeJobBytes,
            .vertexOffset=UINT32_MAX,.tilerOffset=UINT32_MAX,.fragmentOffset=0,
            .writeSurfaces=1,.profileID=0,.mappingEpoch=mapped.flags};
        submit.surfaces[0]=query.surfaces[0];
        kr=A5MaliSubmitNative(client,&submit,jobs.bytes,fence);
        logNativePhase(diagnosticID,"clear-submit18",0,kr);return kr;
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
    if (_encoderOpen) [self markEncodingError:kIOReturnNotReady selector:_cmd];
    [_condition lock];
    if (_status >= MTLCommandBufferStatusCommitted) {
        [_condition unlock];
        return;
    }
    _status = MTLCommandBufferStatusCommitted;
    BOOL submit = !_error;
    kern_return_t priorError=(kern_return_t)_error.code;
    [_condition unlock];
    BOOL diagnose=diagnosticTake(&commitDiagnosticCount,64);
    if(diagnose)fprintf(stderr,"A5XELTE Metal commit: cb=%u phase=begin submit=%u first_error=%x render_encoders=%lu blit_encoders=%lu draw_calls=%lu queued_draws=%lu clear_commands=%lu blit_commands=%lu\n",
        _diagnosticID,submit,(unsigned)priorError,(unsigned long)_renderEncoders,(unsigned long)_blitEncoders,
        (unsigned long)_drawCalls,(unsigned long)_queuedDraws,(unsigned long)_clearCommands,(unsigned long)_blitCommands);
    [_queue submitWork:^{
    NSError *submissionError = nil;
    if (submit) {
        if (![_privateBuffer commitAndWait:&submissionError])
            submissionError = submissionError ?: metalError(kIOReturnError);
    }
    for(A5MaliTexturePassBacking *lease in _memorylessPassBackings)[lease invalidateAfterCompletion];
    [_memorylessPassBackings removeAllObjects];
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
    MTLCommandBufferStatus resultStatus=_status;
    kern_return_t resultError=(kern_return_t)_error.code;
    [_condition unlock];
    if(diagnose)fprintf(stderr,"A5XELTE Metal commit: cb=%u phase=result status=%lu error=%x submitted=%u\n",
        _diagnosticID,(unsigned long)resultStatus,(unsigned)resultError,submit);
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

/* iOS16 Metal's private SPI returns BOOL after committing and asking the
 * queue to submit the buffer. Our kernel work is synchronous within the real
 * submission queue; wait on its actual status, never synthesize a GPU fence. */
- (BOOL)commitAndWaitUntilSubmitted
{
    [self commit];
    [self waitUntilScheduled];
    [_condition lock];
    BOOL submitted=_status>=MTLCommandBufferStatusScheduled &&
        _status!=MTLCommandBufferStatusError && !_error;
    [_condition unlock];
    return submitted;
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
- (BOOL)validateActiveForSelector:(SEL)selector
{
    if(_ended || _buffer.status>=MTLCommandBufferStatusCommitted){
        [_buffer markEncodingError:kIOReturnNotReady selector:selector];return NO;
    }
    return YES;
}
- (void)insertDebugSignpost:(NSString *)string
{ if([self validateActiveForSelector:_cmd] && ![string isKindOfClass:[NSString class]])[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd]; }
- (void)pushDebugGroup:(NSString *)string
{
    if(![self validateActiveForSelector:_cmd])return;
    if(![string isKindOfClass:[NSString class]])[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
    else [_debugGroups addObject:[string copy]];
}
- (void)popDebugGroup
{ if([self validateActiveForSelector:_cmd]){if(!_debugGroups.count)[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];else[_debugGroups removeLastObject];} }
- (void)setCullMode:(MTLCullMode)mode
{ if([self validateActiveForSelector:_cmd] && mode!=MTLCullModeNone)[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setFrontFacingWinding:(MTLWinding)winding
{
    /* With cull=None and no front/back stencil attachment, either winding
     * has identical emitted raster state. Other enum values are invalid. */
    if([self validateActiveForSelector:_cmd] && winding!=MTLWindingClockwise && winding!=MTLWindingCounterClockwise)
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
}
- (void)setTriangleFillMode:(MTLTriangleFillMode)mode
{ if([self validateActiveForSelector:_cmd] && mode!=MTLTriangleFillModeFill)[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setDepthClipMode:(MTLDepthClipMode)mode
{ if([self validateActiveForSelector:_cmd] && mode!=MTLDepthClipModeClip)[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setDepthBias:(float)bias slopeScale:(float)slope clamp:(float)clamp
{ if([self validateActiveForSelector:_cmd] && (bias!=0 || slope!=0 || clamp!=0))[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setDepthStencilState:(A5MaliDepthStencilState *)state
{
    if(![self validateActiveForSelector:_cmd] || !state)return;
    if(![state isKindOfClass:[A5MaliDepthStencilState class]] || state.device!=_buffer.device ||
        state.descriptor.depthCompareFunction!=MTLCompareFunctionAlways || state.descriptor.depthWriteEnabled ||
        state.descriptor.frontFaceStencil || state.descriptor.backFaceStencil)
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
}
- (void)setStencilReferenceValue:(uint32_t)value
{ if([self validateActiveForSelector:_cmd] && value)[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setStencilFrontReferenceValue:(uint32_t)front backReferenceValue:(uint32_t)back
{ if([self validateActiveForSelector:_cmd] && (front||back))[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{ if([self validateActiveForSelector:_cmd] && (red!=0||green!=0||blue!=0||alpha!=0))[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset
{ if([self validateActiveForSelector:_cmd] && (mode!=MTLVisibilityResultModeDisabled || offset))[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd]; }
- (void)setVertexBuffers:(A5MaliPrivateBuffer * const *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range
{
    if(![self validateActiveForSelector:_cmd])return;
    if(!buffers || !offsets || range.location>31 || range.length>31-range.location){[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setVertexBuffer:buffers[i] offset:offsets[i] atIndex:range.location+i];
}
- (void)setFragmentBuffers:(A5MaliPrivateBuffer * const *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range
{
    if(![self validateActiveForSelector:_cmd])return;
    if(!buffers || !offsets || range.location>31 || range.length>31-range.location){[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setFragmentBuffer:buffers[i] offset:offsets[i] atIndex:range.location+i];
}
- (void)setFragmentTextures:(A5MaliMetalTexture * const *)textures withRange:(NSRange)range
{
    if(![self validateActiveForSelector:_cmd])return;
    if(!textures || range.location>128 || range.length>128-range.location){[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setFragmentTexture:textures[i] atIndex:range.location+i];
}
- (void)setFragmentSamplerStates:(A5MaliSamplerState * const *)samplers withRange:(NSRange)range
{
    if(![self validateActiveForSelector:_cmd])return;
    if(!samplers || range.location>16 || range.length>16-range.location){[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;}
    for(NSUInteger i=0;i<range.length;++i)[self setFragmentSamplerState:samplers[i] atIndex:range.location+i];
}

- (void)setRenderPipelineState:(A5MaliReadSurfCandidate *)pipeline
{
    if (_ended || ![pipeline isKindOfClass:[A5MaliReadSurfCandidate class]] ||
        pipeline.device != _buffer.device || (_hasDraw &&
        [_pipeline isKindOfClass:[A5MaliCompiledPipeline class]]!=[pipeline isKindOfClass:[A5MaliCompiledPipeline class]]))
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
    else _pipeline = pipeline;
}

- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atIndex:(NSUInteger)index
{
    if (!texture && index<128 && !_ended) { [_textures removeObjectForKey:@(index)]; if(!index)_source=nil; return; }
    if (_ended || index >= 128 ||
        ![texture isKindOfClass:[A5MaliMetalTexture class]] ||
        texture.device != _buffer.device ||
        texture.storageMode == MTLStorageModeMemoryless ||
        !(texture.usage & MTLTextureUsageShaderRead))
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
    else { _textures[@(index)]=texture; if(!index)_source=texture; }
}

/* QuartzCore's combined SPI has the same binding semantics as the two
 * public setters. Delegate both so ownership, nil unbind and validation remain
 * identical; this is not a synthetic sampler or alternate resource path. */
- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atTextureIndex:(NSUInteger)textureIndex
    samplerState:(A5MaliSamplerState *)sampler atSamplerIndex:(NSUInteger)samplerIndex
{
    [self setFragmentTexture:texture atIndex:textureIndex];
    [self setFragmentSamplerState:sampler atIndex:samplerIndex];
}

- (void)setVertexBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index
{ [self setBoundBuffer:buffer offset:offset index:index vertex:YES selector:_cmd]; }
- (void)setFragmentBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index
{ [self setBoundBuffer:buffer offset:offset index:index vertex:NO selector:_cmd]; }
- (void)setBoundBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset
    index:(NSUInteger)index vertex:(BOOL)vertex selector:(SEL)selector
{
    if (_ended || index>=31) { [_buffer markEncodingError:kIOReturnBadArgument selector:selector]; return; }
    NSMutableDictionary *bindings=vertex?_vertexBindings:_fragmentBindings;
    if (!buffer && !offset) { [bindings removeObjectForKey:@(index)]; return; }
    if (![buffer isKindOfClass:[A5MaliPrivateBuffer class]] || offset>=buffer.length) {
        [_buffer markEncodingError:kIOReturnBadArgument selector:selector]; return;
    }
    A5MaliBufferBinding *binding=[A5MaliBufferBinding bindingWithBuffer:buffer offset:offset
        length:buffer.length-offset device:_buffer.device error:NULL];
    if (!binding) [_buffer markEncodingError:kIOReturnBadArgument selector:selector];
    else bindings[@(index)]=binding;
}
- (void)setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index
{ A5MaliBufferBinding *b=_vertexBindings[@(index)]; if(!b.buffer){[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;} [self setBoundBuffer:b.buffer offset:offset index:index vertex:YES selector:_cmd]; }
- (void)setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index
{ A5MaliBufferBinding *b=_fragmentBindings[@(index)]; if(!b.buffer){[_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;} [self setBoundBuffer:b.buffer offset:offset index:index vertex:NO selector:_cmd]; }
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{ [self setBoundBytes:bytes length:length index:index vertex:YES selector:_cmd]; }
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{ [self setBoundBytes:bytes length:length index:index vertex:NO selector:_cmd]; }
- (void)setBoundBytes:(const void *)bytes length:(NSUInteger)length index:(NSUInteger)index vertex:(BOOL)vertex selector:(SEL)selector
{
    if (_ended || index>=31) { [_buffer markEncodingError:kIOReturnBadArgument selector:selector]; return; }
    NSMutableDictionary *bindings=vertex?_vertexBindings:_fragmentBindings;
    if (!bytes && !length) { [bindings removeObjectForKey:@(index)]; return; }
    A5MaliBufferBinding *binding=[A5MaliBufferBinding bindingWithBytes:bytes length:length
        device:_buffer.device error:NULL];
    if(!binding)[_buffer markEncodingError:kIOReturnBadArgument selector:selector]; else bindings[@(index)]=binding;
}
- (void)setFragmentSamplerState:(A5MaliSamplerState *)sampler atIndex:(NSUInteger)index
{
    if (_ended || index>=16 || (sampler && (![sampler isKindOfClass:[A5MaliSamplerState class]] ||
        sampler.device!=_buffer.device))) { [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd]; return; }
    if(sampler)_samplers[@(index)]=sampler;else[_samplers removeObjectForKey:@(index)];
}
- (void)setScissorRect:(MTLScissorRect)rect
{
    if (_ended || !rect.width || !rect.height || rect.x>_destination.width ||
        rect.y>_destination.height || rect.width>_destination.width-rect.x ||
        rect.height>_destination.height-rect.y) [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
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
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
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
    unsigned diagnosticID=_buffer.diagnosticID;
    return [[_buffer privateBuffer] encodeNativeWork:^kern_return_t(A5MaliClient *client,A5MaliFence *fence) {
        __attribute__((objc_precise_lifetime)) A5MaliCompiledPipeline *retainedPipeline=pipeline;
        (void)retainedPipeline; /* Own cached native code until its terminal fence. */
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
        logNativePhase(diagnosticID,"blur-query17",profile->profileID,result);
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
            A5RuntimeImage image={0};
            if(!A5MaliRuntimeImageForTexture(t,0,t.privateSurface,&s,
                i?(A5MaliRead|A5MaliWrite):A5MaliRead,&image))return kIOReturnBadArgument;
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
        logNativePhase(diagnosticID,"blur-emitter",profile->profileID,encoded);
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
        result=A5MaliSubmitNative(client,&submit,jobs.bytes,fence);
        logNativePhase(diagnosticID,"blur-submit18",profile->profileID,result);return result;
    }];
#endif
}

- (BOOL)encodeCompiledMiscDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count
{
    return [self encodeCompiledMiscDraw:primitiveType vertexCount:count
        indexBinding:nil indexCount:0 indexSize:0];
}
- (BOOL)encodeCompiledMiscDraw:(MTLPrimitiveType)primitiveType vertexCount:(NSUInteger)count
    indexBinding:(A5MaliBufferBinding *)indexBinding indexCount:(NSUInteger)indexCount
    indexSize:(NSUInteger)indexSize
{
#if !A5_MALI_NATIVE_RENDER
    (void)primitiveType;(void)count;(void)indexBinding;(void)indexCount;(void)indexSize;return NO;
#else
    A5MaliCompiledPipeline *pipeline=(id)_pipeline;
    const A5MaliCompiledProfile *profile=pipeline.profile;
    BOOL indexed=indexBinding!=nil;
    NSUInteger primitiveCount=indexed?indexCount:count;
    if(!profile || !(profile->profileID==200 || profile->profileID==202 ||
        profile->profileID==204 || profile->profileID==206 || profile->profileID==207 ||
        profile->profileID==600 || profile->profileID==601 || profile->profileID==602 || profile->profileID==603 ||
        (profile->profileID>=300 && profile->profileID<=302)) ||
        !profile->passCount || profile->passCount>2 || primitiveCount<3 ||
        (!indexed && count>A5RuntimeMaxVertices) ||
        (indexed && ((profile->profileID!=602 && profile->profileID!=603) || indexCount>A5RuntimeMaxIndices ||
            (indexSize!=2 && indexSize!=4) || indexBinding.device!=_buffer.device ||
            indexBinding.length!=indexCount*indexSize || !indexBinding.buffer.readyForRead)) ||
        (primitiveType!=MTLPrimitiveTypeTriangle && primitiveType!=MTLPrimitiveTypeTriangleStrip) ||
        (primitiveType==MTLPrimitiveTypeTriangle && primitiveCount%3))return NO;
    BOOL path=profile->profileID>=300 && profile->profileID<=302;
    if(path && (count!=4 || primitiveType!=MTLPrimitiveTypeTriangleStrip))return NO;
    NSDictionary<NSNumber *,A5MaliMetalTexture *> *attachments=[_attachments copy];
    NSDictionary<NSNumber *,A5MaliMetalTexture *> *textures=[_textures copy];
    for(NSNumber *key in attachments)
        if(attachments[key].pixelFormat!=profile->colorFormats[key.unsignedIntegerValue])return NO;
    A5RuntimeSampler samplerSnapshot={0};
    NSMutableArray<A5MaliMetalTexture *> *mappedImages=[NSMutableArray new];
    NSMutableArray<NSNumber *> *imageSlots=[NSMutableArray new];
    uint32_t readImages=0;
    for(uint32_t i=0;i<profile->passCount;++i){
        uint32_t target=profile->passes[i].logicalTarget;
        A5MaliMetalTexture *image=attachments[@(target)];
        if(target>=8 || !image || !image.privateSurface || !(image.usage&MTLTextureUsageRenderTarget))return NO;
        for(A5MaliMetalTexture *old in mappedImages)
            if(textureBackingAliases(image,old))return NO;
        [mappedImages addObject:image];[imageSlots addObject:@(target)];
    }
    for(uint32_t i=0;i<profile->resourceCount;++i){
        const A5MaliCompiledResource *r=profile->resources+i;
        if(r->kind==A5MaliResourceSampler){
            if(r->flags&A5MaliResourceImmutableSampler)continue;
            A5MaliSamplerState *sampler=_samplers[@(r->metalIndex)];
            if(profile->profileID!=603 || r->stage!=A5MaliStageFragment || r->metalIndex ||
                ![sampler isKindOfClass:[A5MaliSamplerState class]] || sampler.device!=_buffer.device)return NO;
            MTLSamplerDescriptor *sd=sampler.descriptor;
            /* The compiled FS specializes address_s=ClampToEdge. Other
             * coordinates/address states cannot borrow that native variant.
             * Single-level images retain their actual min/mag filtering;
             * the native sampler clamps its effective LOD to base level. */
            if(sd.minFilter>MTLSamplerMinMagFilterLinear || sd.magFilter>MTLSamplerMinMagFilterLinear ||
                sd.mipFilter>MTLSamplerMipFilterLinear || !sd.normalizedCoordinates ||
                sd.sAddressMode!=MTLSamplerAddressModeClampToEdge ||
                sd.tAddressMode!=MTLSamplerAddressModeClampToEdge ||
                sd.rAddressMode!=MTLSamplerAddressModeClampToEdge || sd.maxAnisotropy!=1 ||
                sd.compareFunction!=MTLCompareFunctionNever || sd.supportArgumentBuffers ||
                !isfinite(sd.lodMinClamp) || !isfinite(sd.lodMaxClamp) ||
                sd.lodMinClamp<0 || sd.lodMaxClamp<sd.lodMinClamp)return NO;
            samplerSnapshot=(A5RuntimeSampler){.valid=1,.minFilter=(uint32_t)sd.minFilter,
                .magFilter=(uint32_t)sd.magFilter,.mipFilter=(uint32_t)sd.mipFilter,
                .sAddressMode=A5RuntimeSamplerClampEdge,.tAddressMode=A5RuntimeSamplerClampEdge,
                .rAddressMode=A5RuntimeSamplerClampEdge,.normalizedCoordinates=1,
                .maxAnisotropy=1,.compareEnabled=0,.lodMinClamp=sd.lodMinClamp,.lodMaxClamp=sd.lodMaxClamp};
            continue;
        }
        if(r->kind!=A5MaliResourceTexture)continue;
        if(r->stage!=A5MaliStageFragment || r->metalIndex>=31)return NO;
        A5MaliMetalTexture *image=textures[@(r->metalIndex)];
        if(!image || image.pixelFormat!=MTLPixelFormatBGRA8Unorm || !(image.usage&MTLTextureUsageShaderRead))return NO;
        if(profile->profileID==603 && (r->metalIndex!=3 || image.mipmapLevelCount!=1 ||
            image.textureType!=MTLTextureType2D || image.sampleCount!=1))return NO;
        if(image.buffer && (image.buffer.device!=_buffer.device ||
            image.buffer.storageMode!=MTLStorageModeShared || !image.buffer.readyForRead ||
            image.mipmapLevelCount!=1 || image.sampleCount!=1))return NO;
        if(!image.buffer && !image.privateSurface)return NO;
        for(NSUInteger j=0;j<mappedImages.count;++j){A5MaliMetalTexture *old=mappedImages[j];
            if(textureBackingAliases(image,old))return NO;
        }
        if(mappedImages.count==A5NativeSlots)return NO;
        readImages|=1u<<mappedImages.count;[mappedImages addObject:image];[imageSlots addObject:@(32+r->metalIndex)];
    }
    NSArray<NSDictionary<NSNumber *,A5MaliBufferBinding *> *> *bindings=@[[_vertexBindings copy],[_fragmentBindings copy]];
    NSMutableArray<NSMutableDictionary<NSNumber *,NSNumber *> *> *windows=
        [NSMutableArray arrayWithObjects:[NSMutableDictionary new],[NSMutableDictionary new],nil];
    NSMutableArray<NSMutableSet<NSNumber *> *> *storageSlots=
        [NSMutableArray arrayWithObjects:[NSMutableSet new],[NSMutableSet new],nil];
    if(profile->profileID==206 || profile->profileID==600 || profile->profileID==601 || profile->profileID==602 || profile->profileID==603)
        windows[0][@1]=@((indexed?1:count)*48);
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
    unsigned diagnosticID=_buffer.diagnosticID;
    return [[_buffer privateBuffer] encodeNativeWork:^kern_return_t(A5MaliClient *client,A5MaliFence*fence){
        __attribute__((objc_precise_lifetime)) A5MaliCompiledPipeline *retainedPipeline=pipeline;
        (void)retainedPipeline;
        NSMutableArray<NSNumber *> *temporaryHandles=[NSMutableArray new];
        kern_return_t (^execute)(void)=^kern_return_t{
            NSUInteger submittedVertexCount=count;
            __attribute__((objc_precise_lifetime)) NSMutableData *indices=nil;
            if(indexed){
                /* Index and vertex identities are retained at draw time;
                 * contents are captured under the connection's commit lock.
                 * Read private BOs through the already-locked transport to
                 * avoid recursively locking the public readBytes path. */
                indices=[NSMutableData dataWithLength:indexBinding.length];
                kern_return_t kr=[indexBinding.buffer readBytesForSubmission:indices.mutableBytes
                    offset:indexBinding.offset length:indexBinding.length client:client];
                if(kr)return kr;
                uint32_t maximum=0;
                for(NSUInteger i=0;i<indexCount;++i){
                    uint32_t value=0;memcpy(&value,(const uint8_t *)indices.bytes+i*indexSize,indexSize);
                    if(value>=A5RuntimeMaxVertices)return kIOReturnBadArgument;
                    maximum=MAX(maximum,value);
                }
                submittedVertexCount=(NSUInteger)maximum+1;
                A5MaliBufferBinding *vertices=bindings[0][@1];
                if(vertices.length<submittedVertexCount*48)return kIOReturnBadArgument;
                if(diagnosticTake(&indexedDrawDiagnosticCount,32))fprintf(stderr,
                    "A5XELTE Metal indexed: cb=%u profile=%u indices=%lu width=%lu offset=%lu vertices=%lu\n",
                    diagnosticID,profile->profileID,(unsigned long)indexCount,(unsigned long)indexSize,
                    (unsigned long)indexBinding.offset,(unsigned long)submittedVertexCount);
            }
            A5RuntimeMiscDraw command={.draw={.profile=profile,.vertexCount=(uint32_t)submittedVertexCount,
                .primitive=primitiveType==MTLPrimitiveTypeTriangle?A5RuntimeTriangle:A5RuntimeTriangleStrip,
                .blend=sourceOver?A5RuntimeBlendPremultipliedSourceOver:A5RuntimeBlendCopy,
                .scissorX=(uint32_t)scissor.x,.scissorY=(uint32_t)scissor.y,
                .scissorWidth=(uint32_t)scissor.width,.scissorHeight=(uint32_t)scissor.height,
                .viewportX=viewport.originX,.viewportY=viewport.originY,.viewportWidth=viewport.width,
                .viewportHeight=viewport.height,.viewportNear=viewport.znear,.viewportFar=viewport.zfar}};
            if(profile->profileID==603)command.fragmentSamplers[0]=samplerSnapshot;
            if(indexed){
                command.draw.indexBuffer=(A5RuntimeBuffer){0,(uint32_t)indices.length,0,indices.bytes};
                command.draw.indexCount=(uint32_t)indexCount;command.draw.indexSize=(uint32_t)indexSize;
            }
            A5NativeQueryRequest query={.header={1,sizeof(query),0,0}};
            for(NSUInteger i=0;i<mappedImages.count;++i)query.surfaces[i]=mappedImages[i].privateSurface.resource.token;
            NSMutableArray<NSData *> *snapshots=[NSMutableArray new];
            NSMutableArray<NSMutableDictionary<NSNumber *,NSNumber *> *> *handles=
                [NSMutableArray arrayWithObjects:[NSMutableDictionary new],[NSMutableDictionary new],nil];
            unsigned bufferCount=0;
            NSMutableDictionary<NSNumber *,NSNumber *> *imageBuffers=[NSMutableDictionary new];
            uint32_t surfaceReads=readImages;
            /* Buffer textures are true CPU aliases. Snapshot their current
             * parent bytes only now, under the commit lock, into a real GPU
             * BO. Preserve the logical offset/stride when mapping that BO;
             * never substitute a blank IOSurface or an upfront copy. */
            for(NSUInteger i=0;i<mappedImages.count;++i){
                A5MaliMetalTexture *image=mappedImages[i];
                A5MaliPrivateBuffer *backing=image.buffer;
                if(!backing)continue;
                if(!(readImages&(1u<<i)) || bufferCount==A5NativeSlots ||
                    !backing.readyForRead || backing.length>A5NativeBufferMax)return kIOReturnBadArgument;
                NSMutableData *bytes=[NSMutableData dataWithLength:backing.length];
                kern_return_t kr=[backing readBytesForSubmission:bytes.mutableBytes offset:0
                    length:bytes.length client:client];
                if(kr)return kr;
                uint64_t handle=0;
                kr=A5MaliCreateNativeBuffer(client,(uint32_t)bytes.length,bytes.bytes,
                    (uint32_t)bytes.length,&handle);
                if(handle)[temporaryHandles addObject:@(handle)];
                if(kr)return kr;
                query.buffers[bufferCount]=handle;imageBuffers[@(i)]=@(bufferCount++);
                surfaceReads&=~(1u<<i);
                [snapshots addObject:bytes];
            }
            for(NSUInteger stage=0;stage<2;++stage)
                for(NSNumber *slot in windows[stage]){
                    A5MaliBufferBinding *binding=bindings[stage][slot];
                    if(binding.buffer && !binding.buffer.readyForRead)return kIOReturnNotReady;
                    uint64_t handle=binding.privateKernelHandle;
                    A5RuntimeBuffer native={0};
                    if(!handle){
                        NSUInteger required=(indexed && !stage && slot.unsignedIntegerValue==1)?
                            submittedVertexCount*48:windows[stage][slot].unsignedIntegerValue;
                        NSData *data=[binding capturePrefixBytesForSubmission:required error:NULL];
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
                A5NativeQueryResult mapped={0};kern_return_t kr=A5MaliQueryNative(client,&query,&mapped);
                logNativePhase(diagnosticID,path?"path-query17":"misc-query17",profile->profileID,kr);if(kr)return kr;
                command.draw.descriptorGPUVA=mapped.jobVA;command.passIndex=pass;
                for(NSUInteger i=0;i<mappedImages.count;++i){
                    A5MaliMetalTexture *t=mappedImages[i];A5NativeSpan s=mapped.surfaces[i];
                    A5RuntimeImage image={0};
                    NSNumber *bufferIndex=imageBuffers[@(i)];
                    if(bufferIndex){
                        s=mapped.buffers[bufferIndex.unsignedIntegerValue];
                        A5MaliTextureLevelLayout l={0};
                        if(![t getLevelLayout:&l level:0] || !l.width || !l.height || !l.byteLength ||
                            !(s.usage&A5MaliRead) || !s.gpuVA ||
                            l.byteOffset!=t.bufferOffset || l.rowBytes!=t.bufferBytesPerRow ||
                            l.byteOffset>s.bytes || l.byteLength>s.bytes-l.byteOffset ||
                            l.byteOffset>t.buffer.length || l.byteLength>t.buffer.length-l.byteOffset ||
                            (uint64_t)l.rowBytes*l.height!=l.byteLength ||
                            l.rowBytes<(uint64_t)l.width*A5MaliTexturePixelBytes(t.pixelFormat) ||
                            (l.rowBytes&15) || s.gpuVA>UINT64_MAX-l.byteOffset ||
                            s.gpuVA+l.byteOffset>UINT64_MAX-l.byteLength)return kIOReturnBadArgument;
                        image=(A5RuntimeImage){s.gpuVA+l.byteOffset,l.byteLength,l.width,l.height,
                            l.rowBytes,(uint32_t)t.pixelFormat};
                    }else if(!query.surfaces[i]||!A5MaliRuntimeImageForTexture(t,0,t.privateSurface,&s,
                        (readImages&(1u<<i))?A5MaliRead:(A5MaliRead|A5MaliWrite),&image))return kIOReturnBadArgument;
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
                logNativePhase(diagnosticID,path?"path-emitter":"misc-emitter",profile->passes[pass].passID,encoded);
                if(encoded)return encoded==A5RuntimeUnsupported?kIOReturnUnsupported:kIOReturnBadArgument;
                A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5RuntimeJobBytes,
                    .vertexOffset=A5RuntimeVertexOffset,.tilerOffset=A5RuntimeTilerOffset,
                    .fragmentOffset=A5RuntimeFragmentOffset,.readSurfaces=surfaceReads|(1u<<pass),
                    .writeSurfaces=1u<<pass,.readBuffers=(1u<<bufferCount)-1u,
                    .profileID=profile->passes[pass].passID,.mappingEpoch=mapped.flags};
                memcpy(submit.surfaces,query.surfaces,sizeof(submit.surfaces));
                memcpy(submit.buffers,query.buffers,sizeof(submit.buffers));
                kr=A5MaliSubmitNative(client,&submit,jobs.bytes,fence);
                logNativePhase(diagnosticID,path?"path-submit18":"misc-submit18",profile->passes[pass].passID,kr);if(kr)return kr;
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
    [_buffer noteDrawCall];
    if ([_pipeline isKindOfClass:[A5MaliCompiledPipeline class]]) {
        if (_ended || vertexStart || ![self encodeCompiledDraw:primitiveType vertexCount:vertexCount])
            [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
        else { _hasDraw=YES; [_buffer noteQueuedDraw]; }
        return;
    }
    if (_ended || _hasDraw || primitiveType != MTLPrimitiveTypeTriangle ||
        vertexStart || vertexCount != 3)
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
    else _hasDraw = YES;
}
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start
    vertexCount:(NSUInteger)count instanceCount:(NSUInteger)instances
{ if(instances!=1){[_buffer noteDrawCall];[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];}else[self drawPrimitives:type vertexStart:start vertexCount:count]; }

- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)count
    indexType:(MTLIndexType)indexType indexBuffer:(A5MaliPrivateBuffer *)indexBuffer
    indexBufferOffset:(NSUInteger)offset
{
    [_buffer noteDrawCall];
    NSUInteger width=indexType==MTLIndexTypeUInt16?2:indexType==MTLIndexTypeUInt32?4:0;
    if(_ended || !width || offset%width || count>A5RuntimeMaxIndices ||
        ![indexBuffer isKindOfClass:[A5MaliPrivateBuffer class]] ||
        indexBuffer.device!=_buffer.device || !indexBuffer.readyForRead ||
        offset>indexBuffer.length || count>(indexBuffer.length-offset)/width){
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;
    }
    if(!count)return; /* Metal zero-count draw has no work or synthetic fence. */
    if(![_pipeline isKindOfClass:[A5MaliCompiledPipeline class]]){
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];return;
    }
    A5MaliBufferBinding *binding=[A5MaliBufferBinding bindingWithBuffer:indexBuffer
        offset:offset length:count*width device:_buffer.device error:NULL];
    if(!binding || ![self encodeCompiledMiscDraw:type vertexCount:0
        indexBinding:binding indexCount:count indexSize:width])
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
    else { _hasDraw=YES;[_buffer noteQueuedDraw]; }
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)count
    indexType:(MTLIndexType)indexType indexBuffer:(A5MaliPrivateBuffer *)indexBuffer
    indexBufferOffset:(NSUInteger)offset instanceCount:(NSUInteger)instances
{
    [self drawIndexedPrimitives:type indexCount:count indexType:indexType indexBuffer:indexBuffer
        indexBufferOffset:offset instanceCount:instances baseVertex:0 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)count
    indexType:(MTLIndexType)indexType indexBuffer:(A5MaliPrivateBuffer *)indexBuffer
    indexBufferOffset:(NSUInteger)offset instanceCount:(NSUInteger)instances
    baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance
{
    if(instances!=1 || baseVertex || baseInstance){
        [_buffer noteDrawCall];[_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];return;
    }
    [self drawIndexedPrimitives:type indexCount:count indexType:indexType
        indexBuffer:indexBuffer indexBufferOffset:offset];
}

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
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
    else [_buffer noteQueuedDraw];
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
- (BOOL)validateActiveForSelector:(SEL)selector
{
    if (_ended || _buffer.status >= MTLCommandBufferStatusCommitted) {
        [_buffer markEncodingError:kIOReturnNotReady selector:selector];
        return NO;
    }
    return YES;
}
- (BOOL)validateTexture:(id)texture selector:(SEL)selector
{
    if (![texture isKindOfClass:[A5MaliMetalTexture class]] ||
        ((A5MaliMetalTexture *)texture).device != _buffer.device ||
        ![(A5MaliMetalTexture *)texture privateSurface]) {
        [_buffer markEncodingError:kIOReturnBadArgument selector:selector];
        return NO;
    }
    A5MaliMetalTexture *t = texture;
    if ((t.textureType != MTLTextureType2D && t.textureType != MTLTextureType1D) ||
        !A5MaliTexturePixelBytes(t.pixelFormat) || !t.width || !t.height || !t.mipmapLevelCount ||
        t.arrayLength != 1 || t.sampleCount != 1 ||
        (t.storageMode != MTLStorageModeShared && t.storageMode != MTLStorageModePrivate)) {
        [_buffer markEncodingError:kIOReturnUnsupported selector:selector];
        return NO;
    }
    return YES;
}
- (void)rejectUnsupportedOperationForSelector:(SEL)selector
{
    if ([self validateActiveForSelector:selector]) [_buffer markEncodingError:kIOReturnUnsupported selector:selector];
}
- (void)generateMipmapsForTexture:(A5MaliMetalTexture *)texture
{
    if (![self validateActiveForSelector:_cmd] || ![self validateTexture:texture selector:_cmd]) return;
    if(texture.mipmapLevelCount>1 && !A5MaliEncodeTextureMipmaps([_buffer privateBuffer],texture))
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];
    else if(texture.mipmapLevelCount>1)[_buffer noteBlitCommand];
}
- (void)optimizeContentsForGPUAccess:(A5MaliMetalTexture *)texture
{
    /* This is a performance hint. The fixed IOSurface layout has no alternate
     * CPU/GPU swizzle to select, so preserving its layout is a valid choice. */
    if (![self validateActiveForSelector:_cmd] || ![self validateTexture:texture selector:_cmd]) return;
}
- (void)optimizeContentsForGPUAccess:(A5MaliMetalTexture *)texture
    slice:(NSUInteger)slice level:(NSUInteger)level
{
    if (![self validateActiveForSelector:_cmd] || ![self validateTexture:texture selector:_cmd]) return;
    if (slice || level>=texture.mipmapLevelCount) [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
}
- (void)optimizeContentsForCPUAccess:(A5MaliMetalTexture *)texture
{ [self optimizeContentsForGPUAccess:texture]; }
- (void)optimizeContentsForCPUAccess:(A5MaliMetalTexture *)texture
    slice:(NSUInteger)slice level:(NSUInteger)level
{ [self optimizeContentsForGPUAccess:texture slice:slice level:level]; }
- (void)insertDebugSignpost:(NSString *)string
{
    if (![self validateActiveForSelector:_cmd]) return;
    if (![string isKindOfClass:[NSString class]])
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
}
- (void)pushDebugGroup:(NSString *)string
{
    if (![self validateActiveForSelector:_cmd]) return;
    if (![string isKindOfClass:[NSString class]])
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
    else [_debugGroups addObject:[string copy]];
}
- (void)popDebugGroup
{
    if (![self validateActiveForSelector:_cmd]) return;
    if (!_debugGroups.count) [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
    else [_debugGroups removeLastObject];
}

- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
    toTexture:(A5MaliMetalTexture *)destinationTexture
{
    if(![self validateActiveForSelector:_cmd]||![self validateTexture:sourceTexture selector:_cmd]||
        ![self validateTexture:destinationTexture selector:_cmd])return;
    NSUInteger sl=0,dl=0;A5MaliTextureLevelLayout a={0},b={0};
    if(sourceTexture.width>=destinationTexture.width&&sourceTexture.height>=destinationTexture.height){
        while(sl<sourceTexture.mipmapLevelCount){
            [sourceTexture getLevelLayout:&a level:sl];
            if(a.width==destinationTexture.width&&a.height==destinationTexture.height)break;++sl;
        }
    }else{
        while(dl<destinationTexture.mipmapLevelCount){
            [destinationTexture getLevelLayout:&b level:dl];
            if(b.width==sourceTexture.width&&b.height==sourceTexture.height)break;++dl;
        }
    }
    if(sl>=sourceTexture.mipmapLevelCount||dl>=destinationTexture.mipmapLevelCount){
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;
    }
    [self copyFromTexture:sourceTexture sourceSlice:0 sourceLevel:sl toTexture:destinationTexture
        destinationSlice:0 destinationLevel:dl sliceCount:1
        levelCount:MIN(sourceTexture.mipmapLevelCount-sl,destinationTexture.mipmapLevelCount-dl)];
}
- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
    sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
    toTexture:(A5MaliMetalTexture *)destinationTexture
    destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
    sliceCount:(NSUInteger)sliceCount levelCount:(NSUInteger)levelCount
{
    if (![self validateActiveForSelector:_cmd] || ![self validateTexture:sourceTexture selector:_cmd] ||
        ![self validateTexture:destinationTexture selector:_cmd]) return;
    if(sourceSlice||destinationSlice||sliceCount!=1||!levelCount||
        sourceLevel>=sourceTexture.mipmapLevelCount||levelCount>sourceTexture.mipmapLevelCount-sourceLevel||
        destinationLevel>=destinationTexture.mipmapLevelCount||levelCount>destinationTexture.mipmapLevelCount-destinationLevel||
        sourceTexture.pixelFormat!=destinationTexture.pixelFormat){
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;
    }
    for(NSUInteger i=0;i<levelCount;++i){
        A5MaliTextureLevelLayout a={0},b={0};
        if(![sourceTexture getLevelLayout:&a level:sourceLevel+i]||
            ![destinationTexture getLevelLayout:&b level:destinationLevel+i]||a.width!=b.width||a.height!=b.height){
            [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;
        }
        [self copyFromTexture:sourceTexture sourceSlice:0 sourceLevel:sourceLevel+i
            sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(a.width,a.height,1)
            toTexture:destinationTexture destinationSlice:0 destinationLevel:destinationLevel+i
            destinationOrigin:MTLOriginMake(0,0,0)];
    }
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
    if (![self validateActiveForSelector:_cmd] || ![self validateTexture:sourceTexture selector:_cmd] ||
        ![self validateTexture:destinationTexture selector:_cmd]) return;
    if(sourceSlice||destinationSlice||sourceTexture.pixelFormat!=destinationTexture.pixelFormat){
        if(diagnosticTake(&copyRejectionDiagnosticCount,64))
            fprintf(stderr,"A5XELTE Metal copy: rejected reason=slice-or-format source_format=%lu destination_format=%lu source=%lux%lu source_mips=%lu source_slice=%lu source_level=%lu destination=%lux%lu destination_mips=%lu destination_slice=%lu destination_level=%lu\n",
                (unsigned long)sourceTexture.pixelFormat,(unsigned long)destinationTexture.pixelFormat,
                (unsigned long)sourceTexture.width,(unsigned long)sourceTexture.height,
                (unsigned long)sourceTexture.mipmapLevelCount,(unsigned long)sourceSlice,(unsigned long)sourceLevel,
                (unsigned long)destinationTexture.width,(unsigned long)destinationTexture.height,
                (unsigned long)destinationTexture.mipmapLevelCount,(unsigned long)destinationSlice,(unsigned long)destinationLevel);
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];return;
    }
    if([[_buffer.device privateDevice]supportsNativePrograms]){
        if(!A5MaliEncodeTextureCopy([_buffer privateBuffer],sourceTexture,sourceLevel,sourceOrigin,
            sourceSize,destinationTexture,destinationLevel,destinationOrigin))
            [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
        else [_buffer noteBlitCommand];
        return;
    }
    if(sourceLevel||destinationLevel||sourceTexture.mipmapLevelCount!=1||destinationTexture.mipmapLevelCount!=1||
        sourceTexture.pixelFormat!=MTLPixelFormatBGRA8Unorm||sourceOrigin.z||destinationOrigin.z||
        sourceSize.depth!=1||!sourceSize.width||!sourceSize.height||
        sourceOrigin.x>UINT32_MAX||sourceOrigin.y>UINT32_MAX||destinationOrigin.x>UINT32_MAX||
        destinationOrigin.y>UINT32_MAX||sourceSize.width>UINT32_MAX||sourceSize.height>UINT32_MAX){
        [_buffer markEncodingError:kIOReturnUnsupported selector:_cmd];return;
    }
    A5MaliRect source={(uint32_t)sourceOrigin.x,(uint32_t)sourceOrigin.y,(uint32_t)sourceSize.width,(uint32_t)sourceSize.height};
    A5MaliRect destination={(uint32_t)destinationOrigin.x,(uint32_t)destinationOrigin.y,source.width,source.height};
    if(![[_buffer privateBuffer]encodeCopy:sourceTexture.privateSurface sourceRect:source
        to:destinationTexture.privateSurface destinationRect:destination])
        [_buffer markEncodingError:kIOReturnBadArgument selector:_cmd];
    else [_buffer noteBlitCommand];
}

/* Required iOS16 blit operations not backed by a typed kernel operation fail
 * the command buffer. They never copy CPU shadow bytes or pretend a fence or
 * counter exists. Pointer/offset arguments are deliberately not dereferenced. */
- (void)copyFromBuffer:(id<MTLBuffer>)source sourceOffset:(NSUInteger)sourceOffset
    toBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)destinationOffset
    size:(NSUInteger)size
{ (void)source; (void)sourceOffset; (void)destination; (void)destinationOffset;
  (void)size; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value
{ (void)buffer; (void)range; (void)value; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)copyFromBuffer:(id<MTLBuffer>)source sourceOffset:(NSUInteger)offset
    sourceBytesPerRow:(NSUInteger)row sourceBytesPerImage:(NSUInteger)image
    sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)destination
    destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level
    destinationOrigin:(MTLOrigin)origin
{ (void)source; (void)offset; (void)row; (void)image; (void)size;
  (void)destination; (void)slice; (void)level; (void)origin;
  [self rejectUnsupportedOperationForSelector:_cmd]; }
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
  [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)copyFromTexture:(id<MTLTexture>)source sourceSlice:(NSUInteger)slice
    sourceLevel:(NSUInteger)level sourceOrigin:(MTLOrigin)origin sourceSize:(MTLSize)size
    toBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)offset
    destinationBytesPerRow:(NSUInteger)row destinationBytesPerImage:(NSUInteger)image
    options:(MTLBlitOption)options
{ (void)options; [self copyFromTexture:source sourceSlice:slice sourceLevel:level
    sourceOrigin:origin sourceSize:size toBuffer:destination destinationOffset:offset
    destinationBytesPerRow:row destinationBytesPerImage:image]; }
- (void)synchronizeResource:(id<MTLResource>)resource
{ (void)resource; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)synchronizeTexture:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level
{ (void)texture; (void)slice; (void)level; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)updateFence:(id<MTLFence>)fence
{ (void)fence; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)waitForFence:(id<MTLFence>)fence
{ (void)fence; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)getTextureAccessCounters:(id<MTLTexture>)texture region:(MTLRegion)region
    mipLevel:(NSUInteger)mipLevel slice:(NSUInteger)slice resetCounters:(BOOL)resetCounters
    countersBuffer:(id<MTLBuffer>)buffer countersBufferOffset:(NSUInteger)offset
{ (void)texture; (void)region; (void)mipLevel; (void)slice; (void)resetCounters;
  (void)buffer; (void)offset; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)resetTextureAccessCounters:(id<MTLTexture>)texture region:(MTLRegion)region
    mipLevel:(NSUInteger)mipLevel slice:(NSUInteger)slice
{ (void)texture; (void)region; (void)mipLevel; (void)slice; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>)buffer withRange:(NSRange)range
{ (void)buffer; (void)range; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)copyIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)source sourceRange:(NSRange)range
    destination:(id<MTLIndirectCommandBuffer>)destination destinationIndex:(NSUInteger)index
{ (void)source; (void)range; (void)destination; (void)index; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)optimizeIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)buffer withRange:(NSRange)range
{ (void)buffer; (void)range; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)buffer
    atSampleIndex:(NSUInteger)index withBarrier:(BOOL)barrier
{ (void)buffer; (void)index; (void)barrier; [self rejectUnsupportedOperationForSelector:_cmd]; }
- (void)resolveCounters:(id<MTLCounterSampleBuffer>)buffer inRange:(NSRange)range
    destinationBuffer:(id<MTLBuffer>)destination destinationOffset:(NSUInteger)offset
{ (void)buffer; (void)range; (void)destination; (void)offset; [self rejectUnsupportedOperationForSelector:_cmd]; }

- (void)endEncoding
{
    if (!_ended) {
        _ended = YES;
        [_buffer finishEncoding];
    }
}

@end
