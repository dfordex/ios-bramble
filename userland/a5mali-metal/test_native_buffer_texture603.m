/* SPDX-License-Identifier: MIT
 * Buffer-backed Texture3 for the actual profile603 native path. The IOKit
 * transport is mocked; this checks upload, VA binding, fences and cleanup,
 * not GPU pixels or stock iOS execution.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
#import "A5MaliNative.h"
#import "A5MaliCompiledRegistry.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

@interface A5MaliMetalBuffer (BufferTexture603FenceTest)
- (A5MaliCommandBuffer *)privateBuffer;
@end
typedef struct {float position[4],uv[2],unused[2];uint16_t color[4];uint8_t pad[8];} Vertex;
_Static_assert(sizeof(Vertex)==48,"actual stock packing0");
typedef enum {Good,FailBulk,FailQuery,FailSubmit} Fault;
typedef struct {
    Fault fault;
    unsigned creates,bulkCalls,queries,submits,releases,deallocations;
    size_t length,uploaded;
    uint8_t *host,*expected,*actual;
    uint64_t handle;
    Vertex vertices[6];
    float matrix[16],transform[4],lod[2];
    const A5MaliCompiledProfile *profile;
} State;
typedef struct {A5MaliHeader header;uint32_t bytes,usage;} Create;
typedef struct {A5MaliHeader header;uint64_t handle;uint32_t bytes,usage;} Created;
typedef struct {A5MaliHeader header;uint64_t handle;} Release;
static uint32_t u32(const uint8_t*p){uint32_t n;memcpy(&n,p,4);return n;}
static uint64_t u64(const uint8_t*p){uint64_t n;memcpy(&n,p,8);return n;}
static BOOL contains(const uint8_t*p,size_t n,const void*v,size_t bytes)
{for(size_t i=0;i+bytes<=n;++i)if(!memcmp(p+i,v,bytes))return YES;return NO;}
static kern_return_t transport(void*context,uint32_t selector,const void*input,size_t bytes,void*output,size_t*outBytes)
{
    State*s=context;
    if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
    if(selector==8){
        const Create*q=input;assert(bytes==sizeof(*q)&&!s->creates&&q->bytes==s->length&&q->usage==3);
        Created r={{1,sizeof(r),0,0},UINT64_C(0x100000101),q->bytes,q->usage};
        assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);
        s->handle=r.handle;++s->creates;return KERN_SUCCESS;
    }
    if(selector==A5NativeBulkWriteSelector){
        const A5NativeBulkWriteRequest*q=input;
        assert(s->creates==1&&q->handle==s->handle&&bytes==sizeof(*q)+q->length);
        assert(q->offset==s->uploaded&&q->length<=A5NativeBulkWriteMax&&q->length<=s->length-s->uploaded);
        if(s->fault==FailBulk&&s->bulkCalls==1){++s->bulkCalls;return kIOReturnIOError;}
        memcpy(s->actual+q->offset,(const uint8_t*)input+sizeof(*q),q->length);
        s->uploaded+=q->length;++s->bulkCalls;
        /* A later CPU write cannot affect chunks already captured at COMMIT. */
        if(s->bulkCalls==1)s->host[s->length-1]^=0x5a;
        assert(!output&&(!outBytes||!*outBytes));return KERN_SUCCESS;
    }
    if(selector==9){
        const Release*q=input;assert(bytes==sizeof(*q)&&q->handle==s->handle);
        assert(s->releases==0);++s->releases;return KERN_SUCCESS;
    }
    if(selector==A5NativeQuerySelector){
        const A5NativeQueryRequest*q=input;
        assert(bytes==sizeof(*q)&&q->surfaces[0]==UINT64_C(0x100000001));
        assert(!q->surfaces[1]&&!q->surfaces[2]&&!q->surfaces[3]);
        assert(q->buffers[0]==s->handle);
        for(unsigned i=1;i<A5NativeSlots;++i)assert(!q->buffers[i]);
        assert(s->uploaded==s->length&&!memcmp(s->actual,s->expected,s->length));
        ++s->queries;if(s->fault==FailQuery)return kIOReturnBadArgument;
        A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,
            .jobBytes=A5NativeJobBytes,.flags=107};
        r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,4096,32,32,128,0x42475241,3};
        r.buffers[0]=(A5NativeSpan){q->buffers[0],0x13000000,(uint32_t)s->length,0,0,0,0,A5MaliRead|A5MaliWrite};
        assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;
    }
    assert(selector==A5NativeSubmitSelector);
    const A5NativeSubmitRequest*q=input;
    assert(bytes==sizeof(*q)+A5NativeJobBytes&&q->profileID==603&&q->mappingEpoch==107);
    assert(q->readSurfaces==1&&q->writeSurfaces==1&&q->readBuffers==1);
    assert(q->surfaces[0]==UINT64_C(0x100000001)&&!q->surfaces[1]&&q->buffers[0]==s->handle);
    assert(s->uploaded==s->length&&!memcmp(s->actual,s->expected,s->length));
    const uint8_t*j=(const uint8_t*)input+sizeof(*q);
    const A5MaliCompiledPass*p=s->profile->passes;
    assert(!memcmp(j+0x6000,p->vertex.bytes,p->vertex.byteCount));
    assert(!memcmp(j+0x8000,p->fragment.bytes,p->fragment.byteCount));
    assert(contains(j+0x20000,0x10000,s->vertices,sizeof(s->vertices)));
    assert(contains(j+0x20000,0x10000,s->matrix,sizeof(s->matrix)));
    assert(contains(j+0x20000,0x10000,s->transform,sizeof(s->transform)));
    assert(contains(j+0x20000,0x10000,s->lod,sizeof(s->lod)));
    assert(u32(j+0x600)==((16u-1)<<16|31u));
    assert(u64(j+0x620)==UINT64_C(0x13000080)&&u32(j+0x628)==256&&u32(j+0x62c)==4096);
    assert(u64(j+0x680)==A5NativeJobVA+0x600);
    assert(A5NativeCheckJobChain(j,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,NO)==1);
    ++s->submits;if(s->fault==FailSubmit)return kIOReturnTimeout;
    A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=1902,.fragmentFence=1903};
    assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;
}
static MTLFunctionConstantValues *constants(BOOL vertex)
{
    size_t count=0;const A5MaliCompiledFunctionConstant *c=vertex?
        A5MaliCompiledVertexConstantsForProfile(603,&count):A5MaliCompiledConstantsForProfile(603,&count);
    assert(c&&count==(vertex?4u:58u));MTLFunctionConstantValues *result=[MTLFunctionConstantValues new];
    for(size_t i=0;i<count;++i)[result setConstantValue:c[i].raw type:c[i].dataType
        withName:[NSString stringWithUTF8String:c[i].name]];
    return result;
}
static A5MaliReadSurfCandidate *pipeline(A5MaliRestrictedDevice *device,State *s)
{
    const char *path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
    NSError *error=nil;A5MaliMetalLibrary *library=[device newLibraryWithURL:
        [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]] error:&error];assert(library&&!error);
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    d.vertexFunction=(id)[library newFunctionWithName:@"fixed_vert_lph_spc" constantValues:constants(YES) error:&error];
    d.fragmentFunction=(id)[library newFunctionWithName:@"fixed_frag_lph_cph" constantValues:constants(NO) error:&error];
    assert(d.vertexFunction&&d.fragmentFunction&&!error);d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
    assert(s->profile->attributeCount==4&&s->profile->layoutCount==1);
    for(unsigned i=0;i<4;++i){const A5MaliCompiledVertexAttribute *a=s->profile->attributes+i;
        d.vertexDescriptor.attributes[a->index].format=a->format;
        d.vertexDescriptor.attributes[a->index].offset=a->offset;
        d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;
    }
    const A5MaliCompiledVertexLayout *l=s->profile->layouts;
    d.vertexDescriptor.layouts[l->index].stride=l->stride;
    d.vertexDescriptor.layouts[l->index].stepFunction=l->stepFunction;
    d.vertexDescriptor.layouts[l->index].stepRate=l->stepRate;
    for(unsigned i=0;i<8;++i){const A5MaliCompiledAttachmentState *a=&s->profile->attachmentContracts[0].attachments[i];
        MTLRenderPipelineColorAttachmentDescriptor *actual=d.colorAttachments[i];
        actual.pixelFormat=s->profile->colorFormats[i];actual.writeMask=a->writeMask;actual.blendingEnabled=a->blendEnabled;
        actual.rgbBlendOperation=a->rgbOperation;actual.alphaBlendOperation=a->alphaOperation;
        actual.sourceRGBBlendFactor=a->sourceRGB;actual.destinationRGBBlendFactor=a->destinationRGB;
        actual.sourceAlphaBlendFactor=a->sourceAlpha;actual.destinationAlphaBlendFactor=a->destinationAlpha;
    }
    A5MaliReadSurfCandidate *result=[device newRenderPipelineStateWithDescriptor:d error:&error];assert(result&&!error);return result;
}
static A5MaliMetalBuffer *encode(A5MaliRestrictedDevice*d,id pipelineState,
    A5MaliMetalTexture*target,A5MaliMetalTexture*source,State*s)
{
    A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];assert(b);
    MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=(id)target;
    pass.colorAttachments[0].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    A5MaliMetalRenderEncoder*r=[b renderCommandEncoderWithDescriptor:pass];assert(r);
    [r setRenderPipelineState:pipelineState];[r setViewport:(MTLViewport){0,0,32,32,0,1}];
    A5MaliPrivateBuffer*vb=[d newBufferWithLength:sizeof(s->vertices)+32 options:MTLResourceStorageModeShared];
    A5MaliPrivateBuffer*matrix=[d newBufferWithLength:80 options:MTLResourceStorageModeShared];
    A5MaliPrivateBuffer*uv=[d newBufferWithLength:32 options:MTLResourceStorageModeShared];
    A5MaliPrivateBuffer*lod=[d newBufferWithLength:24 options:MTLResourceStorageModeShared];
    assert(vb.contents&&matrix.contents&&uv.contents&&lod.contents);
    [r setVertexBuffer:vb offset:16 atIndex:1];[r setVertexBuffer:matrix offset:16 atIndex:2];
    [r setVertexBuffer:uv offset:16 atIndex:3];[r setFragmentBuffer:lod offset:16 atIndex:2];
    MTLSamplerDescriptor*sd=[MTLSamplerDescriptor new];
    sd.minFilter=MTLSamplerMinMagFilterNearest;sd.magFilter=sd.minFilter;
    sd.mipFilter=MTLSamplerMipFilterLinear;sd.lodMinClamp=.25f;sd.lodMaxClamp=4;
    A5MaliSamplerState*sampler=[d newSamplerStateWithDescriptor:sd];assert(sampler);
    [r setFragmentSamplerState:sampler atIndex:0];[r setFragmentTexture:source atIndex:3];
    [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [r setFragmentTexture:nil atIndex:3];[r endEncoding];
    memcpy((uint8_t*)vb.contents+16,s->vertices,sizeof(s->vertices));
    memcpy((uint8_t*)matrix.contents+16,s->matrix,sizeof(s->matrix));
    memcpy((uint8_t*)uv.contents+16,s->transform,sizeof(s->transform));
    memcpy((uint8_t*)lod.contents+16,s->lod,sizeof(s->lod));
    assert(!b.privateBuffer.completedFence.fragmentFence);return b;
}
static void runCase(Fault fault,BOOL useSPI)
{
    State s={.fault=fault,.length=0x101000};
    s.profile=A5MaliCompiledProfileForID(603);assert(s.profile);
    s.expected=malloc(s.length);s.actual=calloc(1,s.length);
    assert(s.expected&&s.actual);
    for(size_t i=0;i<s.length;++i)s.expected[i]=(uint8_t)(i*29u+7u);
    for(unsigned i=0;i<6;++i){s.vertices[i].position[0]=i+.25f;
        s.vertices[i].position[1]=i*.75f;s.vertices[i].position[3]=1;
        s.vertices[i].uv[0]=i*3+.5f;s.vertices[i].uv[1]=i+.125f;
        s.vertices[i].color[0]=0x3800;s.vertices[i].color[1]=0x3400;
        s.vertices[i].color[2]=0x3a00;s.vertices[i].color[3]=0x3c00;}
    s.matrix[0]=1.25f;s.matrix[5]=1.75f;s.matrix[10]=2;s.matrix[15]=1;
    s.transform[0]=.03125f;s.transform[1]=.0625f;
    s.lod[0]=.375f;s.lod[1]=.625f;
    @autoreleasepool{
        A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:transport
            context:&s commandCapabilities:63 operationCapabilities:0x7ffff];
        id p=pipeline(d,&s);assert(p);
        A5MaliMetalTexture*target=[d hostTestTextureWithResource:
            (A5MaliResource){0x100000001,32,32,128,3}];
        assert(!posix_memalign((void **)&s.host,4096,s.length));
        memcpy(s.host,s.expected,s.length);
        State *state=&s;
        A5MaliPrivateBuffer*buffer=[d newBufferWithBytesNoCopy:s.host length:s.length
            options:MTLResourceStorageModeShared deallocator:^(void*ptr,NSUInteger len){
                assert(ptr==state->host&&len==state->length);++state->deallocations;free(ptr);
            }];
        assert(buffer&&buffer.contents==s.host&&buffer.privateKernelHandle==0);
        MTLTextureDescriptor*desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
            MTLPixelFormatBGRA8Unorm width:32 height:16 mipmapped:NO];
        desc.usage=MTLTextureUsageShaderRead;desc.storageMode=MTLStorageModeShared;
        A5MaliMetalTexture*source=(id)(useSPI?
            [buffer newLinearTextureWithDescriptor:desc offset:128 bytesPerRow:256 bytesPerImage:4160]:
            [buffer newTextureWithDescriptor:desc offset:128 bytesPerRow:256]);
        assert(source&&source.buffer==buffer&&!source.privateSurface&&source.bufferOffset==128);
        assert(source.bufferBytesPerRow==256&&source.bufferBytesPerImage==(useSPI?4160u:4096u));
        A5MaliTextureLevelLayout l={0};assert([source getLevelLayout:&l level:0]);
        assert(l.byteOffset==128&&l.byteLength==4096&&l.rowBytes==256);
        /* Reject an out-of-bounds physical view instead of substituting an
         * independent IOSurface for the same public buffer. */
        assert(![buffer newTextureWithDescriptor:desc offset:s.length-128 bytesPerRow:256]);
        A5MaliMetalBuffer*b=encode(d,p,target,source,&s);
        buffer=nil;source=nil;
        assert(!s.creates&&!s.bulkCalls&&!s.queries&&!s.submits&&!s.deallocations);
        /* Shared and no-copy bytes change after encoding but before COMMIT. */
        s.host[128]=0xa5;s.expected[128]=0xa5;
        [b commit];[b waitUntilCompleted];
        assert(s.creates==1&&s.releases==1);
        if(fault==FailBulk){assert(s.bulkCalls==2&&!s.queries&&!s.submits);}
        else if(fault==FailQuery){assert(s.bulkCalls==2&&s.queries==1&&!s.submits);}
        else {assert(s.bulkCalls==2&&s.queries==1&&s.submits==1);}
        if(fault==Good){assert(b.status==MTLCommandBufferStatusCompleted&&!b.error);
            assert(b.privateBuffer.completedFence.tilerFence==1902&&b.privateBuffer.completedFence.fragmentFence==1903);}
        else {assert(b.status==MTLCommandBufferStatusError&&b.error);
            assert(!b.privateBuffer.completedFence.tilerFence&&!b.privateBuffer.completedFence.fragmentFence);}
        b=nil;
    }
    assert(s.deallocations==1);
    free(s.expected);free(s.actual);
}
int main(void)
{
    runCase(Good,NO);runCase(Good,YES);
    runCase(FailBulk,NO);runCase(FailQuery,NO);runCase(FailSubmit,NO);
    puts("buffer-backed native603: real no-copy Shared alias, commit snapshot, full bulk upload, bufferVA+offset, fences and cleanup PASS (mock transport; no GPU pixels)");
    return 0;
}
