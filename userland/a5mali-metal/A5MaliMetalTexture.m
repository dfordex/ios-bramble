/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalTexture.h"
#import "A5MaliMetalDeviceResources.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>

@interface A5MaliRestrictedDevice (TextureDevice)
- (A5MaliDevice *)privateDevice;
@end
@interface A5MaliMetalTexture () {
    A5MaliSurface *_surface;
    A5MaliRestrictedDevice *_device;
    MTLTextureDescriptor *_descriptor;
    A5MaliTextureAllocationLayout _allocation;
    BOOL _external;
    A5MaliMetalTexture *_parent;
    A5MaliTexturePassBacking *_passBacking;
    NSLock *_cpuLock;
    A5MaliPrivateBuffer *_buffer;
    NSUInteger _bufferOffset,_bufferRow,_bufferImage;
    NSUInteger _parentLevel;
}
- (nullable instancetype)initWithSurface:(A5MaliSurface *)surface device:(A5MaliRestrictedDevice *)device
    descriptor:(MTLTextureDescriptor *)descriptor layout:(A5MaliTextureAllocationLayout)layout external:(BOOL)external;
- (instancetype)initWithSurface:(A5MaliSurface *)surface device:(A5MaliRestrictedDevice *)device
    usage:(MTLTextureUsage)usage storageMode:(MTLStorageMode)storageMode;
@end
@interface A5MaliTexturePassBacking () {
    A5MaliSurface *_surface;
    __weak A5MaliMetalTexture *_texture;
    NSUInteger _level;
    A5MaliTextureLevelLayout _layout;
    NSLock *_lock;
}
- (instancetype)initWithTexture:(A5MaliMetalTexture *)texture level:(NSUInteger)level
    surface:(A5MaliSurface *)surface layout:(A5MaliTextureLevelLayout)layout;
- (BOOL)matchesTexture:(A5MaliMetalTexture *)texture level:(NSUInteger)level;
@end

NSUInteger A5MaliTexturePixelBytes(MTLPixelFormat f)
{
    switch(f){
    case MTLPixelFormatR8Unorm:return 1;
    case MTLPixelFormatRG8Unorm:case MTLPixelFormatR16Uint:case MTLPixelFormatR16Float:
    case MTLPixelFormatBGR5A1Unorm:return 2;
    case MTLPixelFormatBGRA8Unorm:case MTLPixelFormatR32Float:return 4;
    case MTLPixelFormatRGBA16Float:case MTLPixelFormatRG32Float:return 8;
    default:return 0;}
}
uint32_t A5MaliTexturePixelCode(MTLPixelFormat f)
{
    switch(f){
    case MTLPixelFormatBGRA8Unorm:return 0x42475241;
    case MTLPixelFormatRGBA16Float:return 0x52476841;
    case MTLPixelFormatR8Unorm:return 0x4c303038;
    case MTLPixelFormatRG8Unorm:return 0x32433038;
    case MTLPixelFormatR32Float:return 0x4c303066;
    /* Integer, half and packed16 formats remain distinct. R16U and B5A1
     * are private allocation tags, never aliases of CV unorm formats. */
    case MTLPixelFormatR16Uint:return 0x52313655;
    case MTLPixelFormatR16Float:return 0x4c303068;
    case MTLPixelFormatBGR5A1Unorm:return 0x42354131;
    case MTLPixelFormatRG32Float:return 0x32433066;
    default:return 0;}
}
static MTLPixelFormat formatForCode(uint32_t code)
{
    const MTLPixelFormat formats[]={80,115,10,30,55,23,25,43,105};
    for(unsigned i=0;i<sizeof(formats)/sizeof(formats[0]);++i)
        if(A5MaliTexturePixelCode(formats[i])==code)return formats[i];
    return MTLPixelFormatInvalid;
}
static BOOL fail(NSString **reason,NSString *message)
{ if(reason)*reason=message;return NO; }
BOOL A5MaliBuildTextureAllocationLayout(MTLTextureDescriptor *d,
    A5MaliTextureAllocationLayout *out,NSString **reason)
{
    if(out)memset(out,0,sizeof(*out));if(reason)*reason=nil;
    if(!d||!out)return fail(reason,@"nil-descriptor-or-layout");
    MTLTextureSwizzleChannels sw=d.swizzle;
    if(sw.red!=MTLTextureSwizzleRed||sw.green!=MTLTextureSwizzleGreen||
       sw.blue!=MTLTextureSwizzleBlue||sw.alpha!=MTLTextureSwizzleAlpha)return fail(reason,@"swizzle");
    BOOL one=d.textureType==MTLTextureType1D;
    if(!one&&d.textureType!=MTLTextureType2D)return fail(reason,@"texture-type");
    NSUInteger pixel=A5MaliTexturePixelBytes(d.pixelFormat);
    if(!pixel)return fail(reason,@"pixel-format");
    if(d.compressionType!=MTLTextureCompressionTypeLossless)return fail(reason,@"compression-type");
    if(!d.width||d.width>(one?4096u:2048u)||!d.height||d.height>(one?1u:2048u))return fail(reason,@"dimensions");
    if(d.depth!=1)return fail(reason,@"depth");
    if(d.arrayLength!=1)return fail(reason,@"array-length");
    if(d.sampleCount!=1)return fail(reason,@"sample-count");
    if(d.storageMode!=MTLStorageModeShared&&d.storageMode!=MTLStorageModePrivate&&
       d.storageMode!=MTLStorageModeMemoryless)return fail(reason,@"storage-mode");
    if(d.cpuCacheMode!=MTLCPUCacheModeDefaultCache||d.hazardTrackingMode!=MTLHazardTrackingModeDefault)
        return fail(reason,@"resource-options");
    if(!d.usage||(d.usage&~(MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget)))return fail(reason,@"usage");
    if(d.storageMode==MTLStorageModeMemoryless&&(one||!(d.usage&MTLTextureUsageRenderTarget)))
        return fail(reason,@"memoryless-requires-2d-render-target");
    NSUInteger maximum=1,dimension=MAX(d.width,d.height);
    while(dimension>1){dimension>>=1;++maximum;}
    if(!d.mipmapLevelCount||d.mipmapLevelCount>maximum||d.mipmapLevelCount>A5MaliTextureMaxMipLevels)
        return fail(reason,@"mipmap-level-count");
    A5MaliTextureAllocationLayout l={.width=(uint32_t)d.width,.height=(uint32_t)d.height,
        .levelCount=(uint32_t)d.mipmapLevelCount,.bytesPerElement=(uint32_t)pixel,
        .backingWidth=(uint32_t)d.width,.backingRowBytes=(uint32_t)((d.width*pixel+15)&~(NSUInteger)15)};
    uint64_t cursor=0;NSUInteger width=d.width,height=d.height;
    for(NSUInteger level=0;level<d.mipmapLevelCount;++level){
        uint64_t row=(width*pixel+15)&~UINT64_C(15);
        cursor=(cursor+63)&~UINT64_C(63);
        uint64_t bytes=row*height;
        if(cursor>A5MaliSurfaceMaxBytes||bytes>A5MaliSurfaceMaxBytes-cursor)
            return fail(reason,@"mip-allocation-exceeds-32MiB");
        l.levels[level]=(A5MaliTextureLevelLayout){(uint32_t)width,(uint32_t)height,(uint32_t)row,(uint32_t)cursor,(uint32_t)bytes};
        cursor+=bytes;width=MAX((NSUInteger)1,width>>1);height=MAX((NSUInteger)1,height>>1);
    }
    uint64_t backingHeight=(cursor+l.backingRowBytes-1)/l.backingRowBytes;
    uint64_t allocated=backingHeight*l.backingRowBytes;
    if(!backingHeight||backingHeight>4096||allocated>A5MaliSurfaceMaxBytes)
        return fail(reason,@"physical-allocation-bounds");
    l.backingHeight=(uint32_t)backingHeight;l.totalBytes=(uint32_t)allocated;*out=l;return YES;
}
static void rejectLog(MTLTextureDescriptor*d,BOOL external,IOSurfaceRef surface,NSUInteger plane,NSString*reason,kern_return_t status)
{
    static atomic_uint count;unsigned n=atomic_load_explicit(&count,memory_order_relaxed);
    do {if(n>=64)return;}while(!atomic_compare_exchange_weak_explicit(&count,&n,n+1,memory_order_relaxed,memory_order_relaxed));
    MTLTextureSwizzleChannels sw={0};if(d)sw=d.swizzle;
    fprintf(stderr,"A5XELTE Metal texture: rejected phase=%s reason=%s status=%x type=%lu format=%lu width=%lu height=%lu depth=%lu mips=%lu array=%lu samples=%lu storage=%lu usage=%lu options=%lu swizzle=%lu/%lu/%lu/%lu plane=%lu surface=%u surface_width=%lu surface_height=%lu row=%lu bytes=%lu bpe=%lu surface_format=%x\n",
        external?"import":"allocate",reason.UTF8String,(unsigned)status,(unsigned long)d.textureType,
        (unsigned long)d.pixelFormat,(unsigned long)d.width,(unsigned long)d.height,(unsigned long)d.depth,
        (unsigned long)d.mipmapLevelCount,(unsigned long)d.arrayLength,(unsigned long)d.sampleCount,
        (unsigned long)d.storageMode,(unsigned long)d.usage,(unsigned long)d.resourceOptions,
        (unsigned long)sw.red,(unsigned long)sw.green,(unsigned long)sw.blue,(unsigned long)sw.alpha,
        (unsigned long)plane,surface!=NULL,(unsigned long)(surface?IOSurfaceGetWidth(surface):0),
        (unsigned long)(surface?IOSurfaceGetHeight(surface):0),(unsigned long)(surface?IOSurfaceGetBytesPerRow(surface):0),
        (unsigned long)(surface?IOSurfaceGetAllocSize(surface):0),(unsigned long)(surface?IOSurfaceGetBytesPerElement(surface):0),
        surface?IOSurfaceGetPixelFormat(surface):0);
}
static A5MaliSurface *newBacking(A5MaliRestrictedDevice*device,MTLTextureDescriptor*d,
    const A5MaliTextureAllocationLayout*l,NSError**error)
{
    IOSurfaceRef surface=IOSurfaceCreate((__bridge CFDictionaryRef)@{
        (__bridge id)kIOSurfaceWidth:@(l->backingWidth),(__bridge id)kIOSurfaceHeight:@(l->backingHeight),
        (__bridge id)kIOSurfaceBytesPerElement:@(l->bytesPerElement),(__bridge id)kIOSurfaceBytesPerRow:@(l->backingRowBytes),
        (__bridge id)kIOSurfacePixelFormat:@(A5MaliTexturePixelCode(d.pixelFormat))});
    if(!surface){if(error)*error=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:kIOReturnNoMemory userInfo:nil];return nil;}
    BOOL valid=IOSurfaceGetWidth(surface)==l->backingWidth&&IOSurfaceGetHeight(surface)==l->backingHeight&&
        IOSurfaceGetBytesPerRow(surface)==l->backingRowBytes&&IOSurfaceGetBytesPerElement(surface)==l->bytesPerElement&&
        IOSurfaceGetPixelFormat(surface)==A5MaliTexturePixelCode(d.pixelFormat)&&
        IOSurfaceGetAllocSize(surface)>=l->totalBytes&&IOSurfaceGetAllocSize(surface)<=A5MaliSurfaceMaxBytes;
    /* GPU blit initialization and mip generation are valid even when the
     * public usage is ShaderRead only. Internal allocation access is R/W. */
    uint32_t usage=A5MaliRead|A5MaliWrite;
    A5MaliSurface*result=valid?[[device privateDevice]importSurface:surface usage:usage error:error]:nil;
    if(!valid&&error)*error=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:kIOReturnBadArgument userInfo:nil];
    CFRelease(surface);return result;
}
@implementation A5MaliRestrictedDevice (TextureResources)
- (A5MaliMetalTexture*)newTextureWithDescriptor:(MTLTextureDescriptor*)d
{
    A5MaliTextureAllocationLayout layout;NSString*reason=nil;
    if(!A5MaliBuildTextureAllocationLayout(d,&layout,&reason)){
        rejectLog(d,NO,NULL,0,reason,kIOReturnUnsupported);return nil;}
    A5MaliSurface*backing=nil;NSError*error=nil;
    if(d.storageMode!=MTLStorageModeMemoryless){
        backing=newBacking(self,d,&layout,&error);
        if(!backing){rejectLog(d,NO,NULL,0,@"physical-allocation-or-kernel-import",(kern_return_t)error.code);return nil;}
    }
    return [[A5MaliMetalTexture alloc]initWithSurface:backing device:self descriptor:d layout:layout external:NO];
}
- (A5MaliMetalTexture*)newTextureWithDescriptor:(MTLTextureDescriptor*)d iosurface:(IOSurfaceRef)surface plane:(NSUInteger)plane
{
    A5MaliTextureAllocationLayout l;NSString*reason=nil;
    if(!surface||plane||!A5MaliBuildTextureAllocationLayout(d,&l,&reason)||
       d.storageMode!=MTLStorageModeShared||d.mipmapLevelCount!=1||d.textureType!=MTLTextureType2D||
       IOSurfaceGetWidth(surface)!=d.width||IOSurfaceGetHeight(surface)!=d.height||
       IOSurfaceGetBytesPerElement(surface)!=l.bytesPerElement||
       IOSurfaceGetPixelFormat(surface)!=A5MaliTexturePixelCode(d.pixelFormat)||
       IOSurfaceGetBytesPerRow(surface)<d.width*l.bytesPerElement||(IOSurfaceGetBytesPerRow(surface)&15)||
       IOSurfaceGetBytesPerRow(surface)>32768||IOSurfaceGetAllocSize(surface)>A5MaliSurfaceMaxBytes||
       (uint64_t)IOSurfaceGetBytesPerRow(surface)*d.height>IOSurfaceGetAllocSize(surface)){
        rejectLog(d,YES,surface,plane,reason?:@"external-iosurface-contract",kIOReturnUnsupported);return nil;}
    l.backingRowBytes=(uint32_t)IOSurfaceGetBytesPerRow(surface);l.totalBytes=l.backingRowBytes*l.height;
    l.levels[0].rowBytes=l.backingRowBytes;l.levels[0].byteLength=l.totalBytes;
    NSError*error=nil;uint32_t usage=(d.usage&MTLTextureUsageShaderRead)?A5MaliRead:0;
    if(d.usage&MTLTextureUsageRenderTarget)usage|=A5MaliRead|A5MaliWrite;
    A5MaliSurface*backing=[[self privateDevice]importSurface:surface usage:usage error:&error];
    if(!backing){rejectLog(d,YES,surface,plane,@"kernel-import",(kern_return_t)error.code);return nil;}
    return [[A5MaliMetalTexture alloc]initWithSurface:backing device:self descriptor:d layout:l external:YES];
}
#ifdef A5_MALI_HOST_TEST
- (A5MaliMetalTexture*)hostTestTextureWithResource:(A5MaliResource)resource
{
    A5MaliSurface*s=[[self privateDevice]hostTestSurfaceWithResource:resource];
    return [[A5MaliMetalTexture alloc]initWithSurface:s device:self usage:
        ((resource.usage&A5MaliRead)?MTLTextureUsageShaderRead:0)|((resource.usage&A5MaliWrite)?MTLTextureUsageRenderTarget:0)
        storageMode:MTLStorageModeShared];
}
#endif
@end
@implementation A5MaliMetalTexture
+ (A5MaliMetalTexture *)newBufferTextureWithBuffer:(A5MaliPrivateBuffer *)buffer
    descriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset
    bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image
{
    MTLTextureDescriptor *d=[descriptor copy];A5MaliTextureAllocationLayout l={0};
    NSString *reason=nil;A5MaliMetalTexture *result=nil;
    if(![buffer isKindOfClass:A5MaliSharedReadBuffer.class]||!buffer.device||!buffer.readyForRead)
        reason=@"requires-readable-shared-buffer";
    else if(!A5MaliBuildTextureAllocationLayout(d,&l,&reason)){}
    else if(d.storageMode!=MTLStorageModeShared||d.usage!=MTLTextureUsageShaderRead)
        reason=@"requires-shared-shader-read";
    else if(d.mipmapLevelCount!=1)reason=@"requires-single-mip";
    else if((offset&63)||(row&63)||!row||row>32768||row<(uint64_t)d.width*l.bytesPerElement)
        reason=@"linear-offset-or-row-alignment";
    else if(d.height>NSUIntegerMax/row)reason=@"linear-row-span-overflow";
    else {
        NSUInteger span=row*d.height,effectiveImage=image?:span;
        /* Metal's image length ends at the final active texel, not at the
         * end of that row's padding. Keep the real padded allocation span
         * for bounded native sampling, independently of caller image stride. */
        NSUInteger active=(d.height-1)*row+d.width*l.bytesPerElement;
        if(effectiveImage<active||effectiveImage>UINT32_MAX)
            reason=@"linear-image-stride";
        else if(offset>buffer.length||span>buffer.length-offset)
            reason=@"linear-buffer-span";
        else {
            l.levels[0]=(A5MaliTextureLevelLayout){(uint32_t)d.width,(uint32_t)d.height,
                (uint32_t)row,(uint32_t)offset,(uint32_t)span};
            l.totalBytes=(uint32_t)span;l.backingRowBytes=(uint32_t)row;
            result=[[self alloc]initWithSurface:nil device:buffer.device descriptor:d layout:l external:NO];
            if(result){result->_buffer=buffer;result->_bufferOffset=offset;result->_bufferRow=row;
                result->_bufferImage=effectiveImage;}
            else reason=@"linear-view-allocation";
        }
    }
    static atomic_uint count;unsigned n=atomic_load_explicit(&count,memory_order_relaxed);
    do {if(n>=64)return result;}while(!atomic_compare_exchange_weak_explicit(&count,&n,n+1,
        memory_order_relaxed,memory_order_relaxed));
    fprintf(stderr,"A5XELTE Metal linear texture: accepted=%u reason=%s type=%lu format=%lu width=%lu height=%lu mips=%lu usage=%lu storage=%lu offset=%lu row=%lu image=%lu buffer_bytes=%lu\n",
        result!=nil,reason?reason.UTF8String:"none",(unsigned long)d.textureType,(unsigned long)d.pixelFormat,
        (unsigned long)d.width,(unsigned long)d.height,(unsigned long)d.mipmapLevelCount,(unsigned long)d.usage,
        (unsigned long)d.storageMode,(unsigned long)offset,(unsigned long)row,(unsigned long)image,(unsigned long)buffer.length);
    return result;
}
- (instancetype)initWithSurface:(A5MaliSurface*)surface device:(A5MaliRestrictedDevice*)device
    descriptor:(MTLTextureDescriptor*)descriptor layout:(A5MaliTextureAllocationLayout)layout external:(BOOL)external
{
    if((self=[super init])){_surface=surface;_device=device;_descriptor=[descriptor copy];_allocation=layout;
        _external=external;_cpuLock=[NSLock new];}return self;
}
- (instancetype)initWithSurface:(A5MaliSurface*)surface device:(A5MaliRestrictedDevice*)device
    usage:(MTLTextureUsage)usage storageMode:(MTLStorageMode)storage
{
    MTLPixelFormat format=surface.iosurface?formatForCode(IOSurfaceGetPixelFormat(surface.iosurface)):MTLPixelFormatBGRA8Unorm;
    MTLTextureDescriptor*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:surface.width height:surface.height mipmapped:NO];
    d.usage=usage;d.storageMode=storage;A5MaliTextureAllocationLayout l={0};
    A5MaliBuildTextureAllocationLayout(d,&l,NULL);l.levels[0].rowBytes=surface.rowBytes;
    l.levels[0].byteLength=surface.rowBytes*surface.height;l.backingRowBytes=surface.rowBytes;l.totalBytes=l.levels[0].byteLength;
    return [self initWithSurface:surface device:device descriptor:d layout:l external:YES];
}
- (A5MaliRestrictedDevice*)device{return _device;}
- (NSUInteger)width{return _descriptor.width;}
- (NSUInteger)height{return _descriptor.height;}
- (NSUInteger)depth{return 1;}
- (MTLPixelFormat)pixelFormat{return _descriptor.pixelFormat;}
- (MTLTextureType)textureType{return _descriptor.textureType;}
- (MTLTextureSwizzleChannels)swizzle{return _descriptor.swizzle;}
- (NSUInteger)mipmapLevelCount{return _descriptor.mipmapLevelCount;}
- (NSUInteger)arrayLength{return 1;}
- (NSUInteger)sampleCount{return 1;}
- (MTLTextureUsage)usage{return _descriptor.usage;}
- (MTLStorageMode)storageMode{return _descriptor.storageMode;}
- (MTLResourceOptions)resourceOptions{return _descriptor.resourceOptions;}
- (MTLCPUCacheMode)cpuCacheMode{return _descriptor.cpuCacheMode;}
- (MTLHazardTrackingMode)hazardTrackingMode{return _descriptor.hazardTrackingMode;}
- (NSUInteger)allocatedSize{return _buffer?_buffer.allocatedSize:_surface.iosurface?IOSurfaceGetAllocSize(_surface.iosurface):0;}
- (A5MaliPrivateBuffer *)buffer{return _buffer;}
- (NSUInteger)bufferOffset{return _bufferOffset;}
- (NSUInteger)bufferBytesPerRow{return _bufferRow;}
- (NSUInteger)bufferBytesPerImage{return _bufferImage;}
- (id<MTLHeap>)heap{return nil;}
- (NSUInteger)heapOffset{return 0;}
- (BOOL)isAliasable{return NO;}
- (void)makeAliasable
{[NSException raise:NSInvalidArgumentException format:@"makeAliasable requires a heap-backed texture"];}
- (id<MTLResource>)rootResource
{return _buffer?(id)_buffer:_parent?(_parent.rootResource?:(id)_parent):nil;}
- (A5MaliMetalTexture *)parentTexture{return _parent;}
- (NSUInteger)parentRelativeLevel{return _parentLevel;}
- (NSUInteger)parentRelativeSlice{return 0;}
- (NSUInteger)iosurfacePlane{return 0;}
- (BOOL)isShareable{return NO;}
- (BOOL)isFramebufferOnly{return self.storageMode==MTLStorageModeMemoryless;}
- (BOOL)isSparse{return NO;}
- (NSUInteger)firstMipmapInTail{return 0;}
- (NSUInteger)tailSizeInBytes{return 0;}
- (BOOL)allowGPUOptimizedContents{return _descriptor.allowGPUOptimizedContents;}
- (MTLTextureCompressionType)compressionType{return _descriptor.compressionType;}
- (MTLResourceID)gpuResourceID{return (MTLResourceID){0};}
- (uint64_t)allocationID{return 0;}
- (uint64_t)gpuHandle{return 0;}
- (uint64_t)protectionOptions{return 0;}
- (uint64_t)unfilteredResourceOptions{return self.resourceOptions;}
- (BOOL)isCompressed{return NO;}
- (int64_t)compressionFeedback{return 0;}
- (uint64_t)compressionFootprint{return 0;}
- (BOOL)isDrawable{return NO;}
- (uint64_t)numFaces{return 1;}
- (uint64_t)rotation{return 0;}
- (uint32_t)swizzleKey
{
    /* ActualiOS16 MTLTextureSwizzleChannelsToKey/KeyToChannels are identity
     * functions (Metal181a3787c/181a36d68), preserving the four ABI bytes. */
    MTLTextureSwizzleChannels channels=self.swizzle;uint32_t key;
    _Static_assert(sizeof(channels)==sizeof(key),"iOS16 swizzle ABI");memcpy(&key,&channels,sizeof(key));return key;
}
- (int)responsibleProcess
{ @synchronized(self){NSNumber *hint=objc_getAssociatedObject(self,@selector(responsibleProcess));return hint?hint.intValue:getpid();} }
- (void)setResponsibleProcess:(int)process
{
    if(process<0)[NSException raise:NSInvalidArgumentException format:@"negative responsible process hint"];
    @synchronized(self){objc_setAssociatedObject(self,@selector(responsibleProcess),@(process),OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
}
- (kern_return_t)setOwnerWithIdentity:(uint32_t)identity
{(void)identity;return kIOReturnUnsupported;}
- (BOOL)isPurgeable{return [self setPurgeableState:MTLPurgeableStateKeepCurrent]!=MTLPurgeableStateNonVolatile;}
- (BOOL)isComplete{return NO;}
- (void)waitUntilComplete
{[NSException raise:NSInternalInconsistencyException format:@"resource-specific GPU completion tracking is unsupported; wait on the command buffer"];}
- (BOOL)doesAliasResource:(id)resource{return A5MaliResourcesAlias(self,resource);}
- (BOOL)doesAliasAnyResources:(id const __unsafe_unretained *)resources count:(NSUInteger)count
{
    if((count&&!resources)||count>4096)[NSException raise:NSInvalidArgumentException format:@"invalid resource alias array"];
    for(NSUInteger i=0;i<count;++i)if(A5MaliResourcesAlias(self,resources[i]))return YES;return NO;
}
- (BOOL)doesAliasAllResources:(id const __unsafe_unretained *)resources count:(NSUInteger)count
{
    if((count&&!resources)||count>4096)[NSException raise:NSInvalidArgumentException format:@"invalid resource alias array"];
    for(NSUInteger i=0;i<count;++i)if(!A5MaliResourcesAlias(self,resources[i]))return NO;return YES;
}
- (MTLSharedTextureHandle *)newSharedTextureHandle{return nil;}
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state
{
    if(state<MTLPurgeableStateKeepCurrent||state>MTLPurgeableStateEmpty)
        [NSException raise:NSInvalidArgumentException format:@"invalid texture purgeable state"];
    if(_buffer)return [_buffer setPurgeableState:state];
    if(_parent)return [_parent setPurgeableState:state];
    /* Kernel imports and memoryless leases currently retain their actual
     * backing until terminal DMA. No verified IOSurface purge selector is
     * exposed, so refuse discard rather than promise that bytes were freed. */
    if(state!=MTLPurgeableStateKeepCurrent&&state!=MTLPurgeableStateNonVolatile){
        static atomic_uint count;unsigned n=atomic_load_explicit(&count,memory_order_relaxed);
        do{if(n>=32)return MTLPurgeableStateNonVolatile;}
        while(!atomic_compare_exchange_weak_explicit(&count,&n,n+1,memory_order_relaxed,memory_order_relaxed));
        fprintf(stderr,"A5XELTE Metal texture purge: requested=%lu actual=%u reason=retained-surface-purge-unsupported\n",
            (unsigned long)state,(unsigned)MTLPurgeableStateNonVolatile);
    }
    return MTLPurgeableStateNonVolatile;
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)format
{return [self newTextureViewWithPixelFormat:format textureType:self.textureType
    levels:NSMakeRange(0,self.mipmapLevelCount) slices:NSMakeRange(0,1) swizzle:self.swizzle];}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)format textureType:(MTLTextureType)type
    levels:(NSRange)levels slices:(NSRange)slices
{return [self newTextureViewWithPixelFormat:format textureType:type levels:levels slices:slices swizzle:self.swizzle];}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)format textureType:(MTLTextureType)type
    levels:(NSRange)levels slices:(NSRange)slices swizzle:(MTLTextureSwizzleChannels)swizzle
{
    if(format!=self.pixelFormat||type!=self.textureType||!levels.length||levels.location>=self.mipmapLevelCount||
        levels.length>self.mipmapLevelCount-levels.location||slices.location||slices.length!=1||
        self.storageMode==MTLStorageModeMemoryless||swizzle.red!=MTLTextureSwizzleRed||
        swizzle.green!=MTLTextureSwizzleGreen||swizzle.blue!=MTLTextureSwizzleBlue||swizzle.alpha!=MTLTextureSwizzleAlpha)return nil;
    A5MaliTextureAllocationLayout l=_allocation;A5MaliTextureLevelLayout base=l.levels[levels.location];
    l.width=base.width;l.height=base.height;l.levelCount=(uint32_t)levels.length;
    for(NSUInteger i=0;i<levels.length;++i)l.levels[i]=_allocation.levels[levels.location+i];
    MTLTextureDescriptor *d=[_descriptor copy];d.width=l.width;d.height=l.height;d.mipmapLevelCount=levels.length;
    A5MaliMetalTexture *view=[[A5MaliMetalTexture alloc]initWithSurface:_surface device:_device descriptor:d layout:l external:_external];
    if(!view)return nil;
    view->_parent=self;view->_parentLevel=levels.location;view->_buffer=_buffer;
    view->_bufferOffset=_bufferOffset;view->_bufferRow=_bufferRow;view->_bufferImage=_bufferImage;
    return (id)view;
}
- (IOSurfaceRef)iosurface{return _external&&self.storageMode==MTLStorageModeShared?_surface.iosurface:NULL;}
- (A5MaliSurface*)privateSurface
{return self.storageMode==MTLStorageModeMemoryless?(_passBacking.valid?_passBacking.surface:nil):_surface;}
- (A5MaliTexturePassBacking*)passBacking{return _passBacking;}
- (A5MaliMetalTexture*)newRenderViewForLevel:(NSUInteger)level memorylessLease:(A5MaliTexturePassBacking*)lease error:(NSError**)error
{
    if(error)*error=nil;A5MaliTextureLevelLayout sub={0};
    A5MaliSurface*backing=[self surfaceForLevel:level memorylessLease:lease];
    if(!backing||![self getLevelLayout:&sub level:level]){
        if(error)*error=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:kIOReturnBadArgument userInfo:nil];return nil;}
    MTLTextureDescriptor*d=[_descriptor copy];d.width=sub.width;d.height=sub.height;d.mipmapLevelCount=1;
    A5MaliTextureAllocationLayout l=_allocation;l.width=sub.width;l.height=sub.height;l.levelCount=1;l.levels[0]=sub;
    A5MaliMetalTexture*view=[[A5MaliMetalTexture alloc]initWithSurface:backing device:_device descriptor:d layout:l external:NO];
    if(!view){if(error)*error=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:kIOReturnNoMemory userInfo:nil];return nil;}
    view->_parent=self;view->_parentLevel=level;view->_passBacking=lease;if(lease)view->_surface=nil;return view;
}
- (BOOL)getLevelLayout:(A5MaliTextureLevelLayout*)layout level:(NSUInteger)level
{
    if(!layout||level>=_allocation.levelCount)return NO;*layout=_allocation.levels[level];
    if(self.storageMode==MTLStorageModeMemoryless)layout->byteOffset=0;return YES;
}
- (A5MaliTexturePassBacking*)newMemorylessPassBackingForLevel:(NSUInteger)level error:(NSError**)error
{
    if(error)*error=nil;
    if(_parent||self.storageMode!=MTLStorageModeMemoryless||level>=_allocation.levelCount){
        if(error)*error=[NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:kIOReturnBadArgument userInfo:nil];return nil;}
    MTLTextureDescriptor*d=[_descriptor copy];d.storageMode=MTLStorageModePrivate;d.mipmapLevelCount=1;
    d.width=_allocation.levels[level].width;d.height=_allocation.levels[level].height;
    A5MaliTextureAllocationLayout l;if(!A5MaliBuildTextureAllocationLayout(d,&l,NULL))return nil;
    A5MaliSurface*surface=newBacking(_device,d,&l,error);if(!surface)return nil;
    return [[A5MaliTexturePassBacking alloc]initWithTexture:self level:level surface:surface layout:l.levels[0]];
}
- (A5MaliSurface*)surfaceForLevel:(NSUInteger)level memorylessLease:(A5MaliTexturePassBacking*)lease
{
    if(level>=_allocation.levelCount)return nil;
    if(self.storageMode==MTLStorageModeMemoryless){
        if(_parent)return level==0&&lease==_passBacking&&lease.valid?lease.surface:nil;
        return [lease matchesTexture:self level:level]?lease.surface:nil;
    }
    return lease?nil:_surface;
}
- (void)transferBytes:(void*)bytes row:(NSUInteger)row image:(NSUInteger)image region:(MTLRegion)r
    level:(NSUInteger)level slice:(NSUInteger)slice write:(BOOL)write
{
    A5MaliTextureLevelLayout l={0};BOOL one=self.textureType==MTLTextureType1D;
    if(self.storageMode!=MTLStorageModeShared||(!_buffer&&!_surface.iosurface)||slice||![self getLevelLayout:&l level:level]||
       r.origin.z||r.size.depth!=1||r.origin.x>l.width||r.size.width>l.width-r.origin.x||
       r.origin.y>l.height||r.size.height>l.height-r.origin.y||(one&&(r.origin.y||r.size.height!=1)))
        [NSException raise:NSInvalidArgumentException format:@"%@ texture CPU transfer storage/subresource bounds unsupported",
            self.storageMode==MTLStorageModePrivate?@"Private":self.storageMode==MTLStorageModeMemoryless?@"Memoryless":@"Shared"];
    NSUInteger line=r.size.width*_allocation.bytesPerElement;
    if(!r.size.width||!r.size.height)return;
    NSUInteger stride=one&&!row?line:row;
    if(!bytes||stride<line||(r.size.height>1&&stride>(NSUIntegerMax-line)/(r.size.height-1))||
       (image&&image<(r.size.height-1)*stride+line))
        [NSException raise:NSInvalidArgumentException format:@"texture CPU transfer source/destination row bounds invalid"];
    if(_buffer){
        uint64_t start=(uint64_t)l.byteOffset+r.origin.y*l.rowBytes+r.origin.x*_allocation.bytesPerElement;
        uint64_t last=start+(r.size.height-1)*l.rowBytes+line;
        if(last>_buffer.length)[NSException raise:NSInternalInconsistencyException format:@"linear buffer backing span invalid"];
        [_cpuLock lock];kern_return_t status=KERN_SUCCESS;
        for(NSUInteger y=0;y<r.size.height;++y){
            void *cpu=(uint8_t *)bytes+y*stride;
            status=write?[_buffer uploadBytes:cpu offset:(NSUInteger)start+y*l.rowBytes length:line]:
                [_buffer readBytes:cpu offset:(NSUInteger)start+y*l.rowBytes length:line];
            if(status)break;
        }
        [_cpuLock unlock];
        if(status)[NSException raise:NSInternalInconsistencyException format:@"linear buffer CPU transfer failed: %x",status];
        return;
    }
    [_cpuLock lock];IOSurfaceRef surface=_surface.iosurface;
    IOSurfaceLockOptions options=write?0:kIOSurfaceLockReadOnly;
    kern_return_t status=IOSurfaceLock(surface,options,NULL);
    if(status!=KERN_SUCCESS){[_cpuLock unlock];[NSException raise:NSInternalInconsistencyException format:@"IOSurfaceLock failed: %x",status];}
    uint8_t*base=IOSurfaceGetBaseAddress(surface);
    uint64_t start=(uint64_t)l.byteOffset+r.origin.y*l.rowBytes+r.origin.x*_allocation.bytesPerElement;
    uint64_t last=start+(r.size.height-1)*l.rowBytes+line;
    if(!base||last>IOSurfaceGetAllocSize(surface)){
        IOSurfaceUnlock(surface,options,NULL);[_cpuLock unlock];
        [NSException raise:NSInternalInconsistencyException format:@"IOSurface backing span invalid"];}
    for(NSUInteger y=0;y<r.size.height;++y){
        void*gpuBytes=base+start+y*l.rowBytes;void*cpuBytes=(uint8_t*)bytes+y*stride;
        if(write)memcpy(gpuBytes,cpuBytes,line);else memcpy(cpuBytes,gpuBytes,line);
    }
    status=IOSurfaceUnlock(surface,options,NULL);[_cpuLock unlock];
    if(status!=KERN_SUCCESS)[NSException raise:NSInternalInconsistencyException format:@"IOSurfaceUnlock failed: %x",status];
}
- (void)getBytes:(void*)bytes bytesPerRow:(NSUInteger)row fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level
{[self transferBytes:bytes row:row image:0 region:region level:level slice:0 write:NO];}
- (void)getBytes:(void*)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice
{[self transferBytes:bytes row:row image:image region:region level:level slice:slice write:NO];}
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void*)bytes bytesPerRow:(NSUInteger)row
{[self transferBytes:(void*)bytes row:row image:0 region:region level:level slice:0 write:YES];}
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice withBytes:(const void*)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image
{[self transferBytes:(void*)bytes row:row image:image region:region level:level slice:slice write:YES];}
@end
@implementation A5MaliTexturePassBacking
- (instancetype)initWithTexture:(A5MaliMetalTexture*)texture level:(NSUInteger)level surface:(A5MaliSurface*)surface layout:(A5MaliTextureLevelLayout)layout
{if((self=[super init])){_texture=texture;_level=level;_surface=surface;_layout=layout;_lock=[NSLock new];}return self;}
- (A5MaliSurface*)surface{[_lock lock];A5MaliSurface*s=_surface;[_lock unlock];return s;}
- (A5MaliTextureLevelLayout)layout{return _layout;}
- (BOOL)valid{return self.surface!=nil;}
- (BOOL)matchesTexture:(A5MaliMetalTexture*)texture level:(NSUInteger)level
{[_lock lock];BOOL match=_surface&&_texture==texture&&_level==level;[_lock unlock];return match;}
- (void)invalidateAfterCompletion{[_lock lock];_surface=nil;_texture=nil;[_lock unlock];}
@end
