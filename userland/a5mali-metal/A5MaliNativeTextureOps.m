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
static __attribute__((unused)) BOOL rejectCopy(A5MaliMetalTexture *src,NSUInteger sl,A5MaliMetalTexture *dst,
    NSUInteger dl,MTLOrigin so,MTLSize size,MTLOrigin to,const char *reason)
{
    static atomic_uint count;
    unsigned n=atomic_load_explicit(&count,memory_order_relaxed);
    while(n<64){if(atomic_compare_exchange_weak_explicit(&count,&n,n+1,
        memory_order_relaxed,memory_order_relaxed)){
        fprintf(stderr,"A5XELTE Metal copy reject: reason=%s src={type:%lu fmt:%lu storage:%lu width:%lu height:%lu level:%lu origin:%lu,%lu,%lu} dst={type:%lu fmt:%lu storage:%lu width:%lu height:%lu level:%lu origin:%lu,%lu,%lu} size=%lu,%lu,%lu\n",
            reason,(unsigned long)src.textureType,(unsigned long)src.pixelFormat,
            (unsigned long)src.storageMode,(unsigned long)src.width,(unsigned long)src.height,
            (unsigned long)sl,(unsigned long)so.x,(unsigned long)so.y,(unsigned long)so.z,
            (unsigned long)dst.textureType,(unsigned long)dst.pixelFormat,
            (unsigned long)dst.storageMode,(unsigned long)dst.width,(unsigned long)dst.height,
            (unsigned long)dl,(unsigned long)to.x,(unsigned long)to.y,(unsigned long)to.z,
            (unsigned long)size.width,(unsigned long)size.height,(unsigned long)size.depth);break;}}
    return NO;
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
        so.x>UINT32_MAX||so.y>UINT32_MAX||to.x>UINT32_MAX||to.y>UINT32_MAX)
        return rejectCopy(src,sl,dst,dl,so,size,to,"contract");
    A5MaliTextureLevelLayout a={0},b={0};
    A5MaliSurface *source=[src surfaceForLevel:sl memorylessLease:nil];
    A5MaliSurface *destination=[dst surfaceForLevel:dl memorylessLease:nil];
    if(!source||!destination||![src getLevelLayout:&a level:sl]||![dst getLevelLayout:&b level:dl])
        return rejectCopy(src,sl,dst,dl,so,size,to,"backing-level");
    if(so.x>a.width||so.y>a.height||size.width>a.width-so.x||size.height>a.height-so.y||
        to.x>b.width||to.y>b.height||size.width>b.width-to.x||size.height>b.height-to.y)
        return rejectCopy(src,sl,dst,dl,so,size,to,"bounds");
    if(source==destination || (!source.iosurface&&!destination.iosurface&&
        source.resource.token==destination.resource.token) || (source.iosurface&&destination.iosurface&&
        IOSurfaceGetID(source.iosurface)==IOSurfaceGetID(destination.iosurface))){
        uint64_t ae=(uint64_t)a.byteOffset+a.byteLength,be=(uint64_t)b.byteOffset+b.byteLength;
        if(a.byteOffset<be&&b.byteOffset<ae){
            /* A same-level disjoint rectangle is a legal Metal blit, but the
             * Midgard emitter must never sample and render the same backing.
             * Preserve ordering with two real GPU copies through private RAM.
             * Different mip windows remain eligible for the direct path. */
            if(operation!=A5ResourceCopy || a.byteOffset!=b.byteOffset ||
                a.rowBytes!=b.rowBytes || a.width!=b.width || a.height!=b.height)
                return rejectCopy(src,sl,dst,dl,so,size,to,"alias-layout");
            if(so.x==to.x && so.y==to.y)return YES; /* exact self-copy */
            if(so.x<to.x+size.width && to.x<so.x+size.width &&
                so.y<to.y+size.height && to.y<so.y+size.height)
                return rejectCopy(src,sl,dst,dl,so,size,to,"overlapping-rectangles");
            MTLTextureDescriptor *descriptor=[MTLTextureDescriptor new];
            descriptor.textureType=src.textureType;descriptor.pixelFormat=src.pixelFormat;
            descriptor.width=size.width;descriptor.height=size.height;
            descriptor.depth=1;descriptor.arrayLength=1;descriptor.mipmapLevelCount=1;
            descriptor.storageMode=MTLStorageModePrivate;
            descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
            A5MaliMetalTexture *temporary=[src.device newTextureWithDescriptor:descriptor];
            if(!temporary)return rejectCopy(src,sl,dst,dl,so,size,to,"scratch-allocation");
            /* Queued blocks retain all backing. If either enqueue fails, the
             * public encoder records an error and does not submit this buffer. */
            return encode(commands,src,sl,temporary,0,so,size,MTLOriginMake(0,0,0),operation) &&
                encode(commands,temporary,0,dst,dl,MTLOriginMake(0,0,0),size,to,operation);
        }
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
