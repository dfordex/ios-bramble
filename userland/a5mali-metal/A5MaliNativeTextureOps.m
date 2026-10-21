/* SPDX-License-Identifier: MIT
 * Actual mapped subresource copies and mip generation, encoded in order on the
 * existing native queue. No CPU pixel computation or invented GPU completion.
 */
#import "A5MaliNativeTextureOps.h"
#include "../a5xelte-air-translation/families/runtime_resource_ops.h"
#include <stdatomic.h>
#include <stdio.h>
#if __has_include("A5MaliCompiledRegistryData.inc") || defined(A5_MALI_REQUIRE_COMPILED_REGISTRY)
#define A5_NATIVE_TEXTURE_OPS 1
#else
#define A5_NATIVE_TEXTURE_OPS 0
#endif
@interface A5MaliSurface (NativeTextureResource)
- (A5MaliResource)resource;
@end

BOOL A5MaliRuntimeImageForTexture(A5MaliMetalTexture *t,NSUInteger level,
    A5MaliSurface *surface,const A5NativeSpan *s,uint32_t usage,A5RuntimeImage *out)
{
    if(!t||!surface||!s||!out||!usage||(usage&~(A5MaliRead|A5MaliWrite)))return NO;
    A5MaliTextureLevelLayout l={0};
    if(surface!=[t surfaceForLevel:level memorylessLease:t.passBacking]||
        ![t getLevelLayout:&l level:level]||!l.width||!l.height||!l.byteLength||
        s->token!=surface.resource.token||!s->gpuVA||s->width!=surface.width||
        s->height!=surface.height||s->rowBytes!=surface.rowBytes||
        s->pixelFormat!=A5MaliTexturePixelCode(t.pixelFormat)||(s->usage&usage)!=usage||
        (uint64_t)s->rowBytes*s->height>s->bytes||
        l.byteOffset>s->bytes||l.byteLength>s->bytes-l.byteOffset||
        (uint64_t)l.rowBytes*l.height>l.byteLength||
        l.rowBytes<(uint64_t)l.width*A5MaliTexturePixelBytes(t.pixelFormat)||
        (l.rowBytes&15)||s->gpuVA>UINT64_MAX-l.byteOffset)return NO;
    *out=(A5RuntimeImage){s->gpuVA+l.byteOffset,l.byteLength,l.width,l.height,
        l.rowBytes,(uint32_t)t.pixelFormat};
    return YES;
}

static __attribute__((unused)) void resourcePhase(unsigned operation,const char *phase,kern_return_t result)
{
    static atomic_uint count;
    unsigned n=atomic_load_explicit(&count,memory_order_relaxed);
    while(n<96){if(atomic_compare_exchange_weak_explicit(&count,&n,n+1,
        memory_order_relaxed,memory_order_relaxed)){
        fprintf(stderr,"A5XELTE Metal resource op: kind=%u phase=%s result=%x\n",
            operation,phase,(unsigned)result);break;}}
}
static BOOL encode(A5MaliCommandBuffer *commands,A5MaliMetalTexture *src,
    NSUInteger sl,A5MaliMetalTexture *dst,NSUInteger dl,MTLOrigin so,
    MTLSize size,MTLOrigin to,unsigned operation)
{
#if !A5_NATIVE_TEXTURE_OPS
    (void)commands;(void)src;(void)sl;(void)dst;(void)dl;(void)so;(void)size;(void)to;(void)operation;
    return NO;
#else
    if(!commands||!src||!dst||src.device!=dst.device||
        src.storageMode==MTLStorageModeMemoryless||dst.storageMode==MTLStorageModeMemoryless||
        src.pixelFormat!=dst.pixelFormat||so.z||to.z||size.depth!=1||
        !size.width||!size.height||size.width>UINT32_MAX||size.height>UINT32_MAX||
        so.x>UINT32_MAX||so.y>UINT32_MAX||to.x>UINT32_MAX||to.y>UINT32_MAX)return NO;
    A5MaliTextureLevelLayout a={0},b={0};
    A5MaliSurface *source=[src surfaceForLevel:sl memorylessLease:nil];
    A5MaliSurface *destination=[dst surfaceForLevel:dl memorylessLease:nil];
    if(!source||!destination||![src getLevelLayout:&a level:sl]||![dst getLevelLayout:&b level:dl])return NO;
    if(so.x>a.width||so.y>a.height||size.width>a.width-so.x||size.height>a.height-so.y||
        to.x>b.width||to.y>b.height||size.width>b.width-to.x||size.height>b.height-to.y)return NO;
    if(source.resource.token==destination.resource.token){
        uint64_t ae=(uint64_t)a.byteOffset+a.byteLength,be=(uint64_t)b.byteOffset+b.byteLength;
        if(a.byteOffset<be&&b.byteOffset<ae)return NO; /* no in-place overlapping copy */
    }
    return [commands encodeNativeWork:^kern_return_t(A5MaliClient *client,A5MaliFence *fence){
        A5NativeQueryRequest query={.header={1,sizeof(query),0,0}};
        query.surfaces[0]=source.resource.token;query.surfaces[1]=destination.resource.token;
        A5NativeQueryResult mapped={0};kern_return_t kr=A5MaliQueryNative(client,&query,&mapped);
        resourcePhase(operation,"query17",kr);if(kr)return kr;
        A5RuntimeResourceOp op={.descriptorGPUVA=mapped.jobVA,.operation=operation,
            .sourceType=(unsigned)src.textureType,.destinationType=(unsigned)dst.textureType,
            .sourceX=(unsigned)so.x,.sourceY=(unsigned)so.y,
            .destinationX=(unsigned)to.x,.destinationY=(unsigned)to.y,
            .width=(unsigned)size.width,.height=(unsigned)size.height};
        if(!A5MaliRuntimeImageForTexture(src,sl,source,&mapped.surfaces[0],A5MaliRead,&op.source)||
            !A5MaliRuntimeImageForTexture(dst,dl,destination,&mapped.surfaces[1],A5MaliRead|A5MaliWrite,&op.destination))
            return kIOReturnBadArgument;
        NSMutableData *jobs=[NSMutableData dataWithLength:A5RuntimeJobBytes];
        int emitted=A5MaliEncodeRuntimeResourceOp(&op,jobs.mutableBytes,jobs.length);
        resourcePhase(operation,"emitter",emitted);
        if(emitted)return emitted==A5RuntimeUnsupported?kIOReturnUnsupported:kIOReturnBadArgument;
        A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5RuntimeJobBytes,
            .vertexOffset=0,.tilerOffset=0x100,.fragmentOffset=0x200,
            .readSurfaces=3,.writeSurfaces=2,.profileID=operation==A5ResourceGenerateMip?
                A5ResourceMipProfile:A5ResourceCopyProfile,.mappingEpoch=mapped.flags};
        submit.surfaces[0]=query.surfaces[0];submit.surfaces[1]=query.surfaces[1];
        kr=A5MaliSubmitNative(client,&submit,jobs.bytes,fence);
        resourcePhase(operation,"submit18",kr);return kr;
    }];
#endif
}
BOOL A5MaliEncodeTextureCopy(A5MaliCommandBuffer *commands,A5MaliMetalTexture *src,
    NSUInteger sl,MTLOrigin so,MTLSize size,A5MaliMetalTexture *dst,NSUInteger dl,MTLOrigin to)
{ return encode(commands,src,sl,dst,dl,so,size,to,A5ResourceCopy); }
BOOL A5MaliEncodeTextureMipmaps(A5MaliCommandBuffer *commands,A5MaliMetalTexture *texture)
{
    if(!texture||texture.storageMode==MTLStorageModeMemoryless)return NO;
    if(texture.mipmapLevelCount==1)return YES;
    if(texture.textureType!=MTLTextureType2D||texture.pixelFormat!=MTLPixelFormatBGRA8Unorm)return NO;
    for(NSUInteger level=1;level<texture.mipmapLevelCount;++level){
        A5MaliTextureLevelLayout l={0};if(![texture getLevelLayout:&l level:level])return NO;
        if(!encode(commands,texture,level-1,texture,level,MTLOriginMake(0,0,0),
            MTLSizeMake(l.width,l.height,1),MTLOriginMake(0,0,0),A5ResourceGenerateMip))return NO;
    }
    return YES;
}
