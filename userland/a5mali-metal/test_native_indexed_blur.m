/* SPDX-License-Identifier: MIT
 * Real authenticated shader registry and real v4 descriptor encoder; only the
 * kernel transport is mocked. This tests submission, not hardware pixels.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#import "A5MaliMetalTexture.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

@interface A5MaliMetalBuffer (StockSelectorForwardTest)
- (BOOL)commitAndWaitUntilSubmitted;
@end
@interface A5MaliMetalRenderEncoder (StockSelectorForwardTest)
- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atTextureIndex:(NSUInteger)textureIndex
    samplerState:(A5MaliSamplerState *)sampler atSamplerIndex:(NSUInteger)samplerIndex;
@end
@interface A5MaliRestrictedDevice (PackedSourceTest)
- (A5MaliDevice *)privateDevice;
@end
@interface A5MaliMetalTexture (PackedSourceTest)
- (instancetype)initWithSurface:(A5MaliSurface *)surface device:(A5MaliRestrictedDevice *)device
    descriptor:(MTLTextureDescriptor *)descriptor layout:(A5MaliTextureAllocationLayout)layout external:(BOOL)external;
@end
typedef struct {
    unsigned queries,submits,releases,imports;
    IOSurfaceRef imported[32];
    BOOL badAuxSpan,badAuxAlias,failImport,providedAux;
    unsigned sourceFault;
    BOOL badFormat,badFence,badDestinationRead,linearSampler,packedSource;
    unsigned indexSize,indexFault,privateCreates,privateReads,privateReleases;
    BOOL privateIndex,failPrivateRead,privateLive;
    uint8_t privateBytes[4096],indices[24];
    uint8_t vertex[192],matrix[64],texmat[16],filter[72],edr[2];
    const A5MaliCompiledProfile *profile;
} Transport;
static BOOL contains(const uint8_t *haystack,size_t count,const void *needle,size_t bytes)
{ for(size_t i=0;i+bytes<=count;++i)if(!memcmp(haystack+i,needle,bytes))return YES;return NO; }
static kern_return_t transport(void *opaque,uint32_t selector,const void *input,
    size_t bytes,void *output,size_t *outBytes)
{
    Transport *t=opaque;
    if(selector==8){
        typedef struct {A5MaliHeader h;uint32_t bytes,usage;} Create;
        typedef struct {A5MaliHeader h;uint64_t handle;uint32_t bytes,usage;} Created;
        const Create *q=input;assert(bytes==sizeof(*q)&&q->bytes<=4096&&!t->privateLive);
        Created r={{1,sizeof(r),0,0},UINT64_C(0x200000101),q->bytes,q->usage};
        memset(t->privateBytes,0,sizeof(t->privateBytes));t->privateLive=YES;++t->privateCreates;
        assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));return KERN_SUCCESS;
    }
    if(selector==9){
        typedef struct {A5MaliHeader h;uint64_t handle;} Release;
        const Release*q=input;assert(bytes==sizeof(*q)&&q->handle==UINT64_C(0x200000101)&&t->privateLive);
        t->privateLive=NO;++t->privateReleases;return KERN_SUCCESS;
    }
    if(selector==14||selector==15){
        typedef struct {A5MaliHeader h;uint64_t handle;uint32_t offset,length;uint8_t data[256];} Transfer;
        typedef struct {A5MaliHeader h;uint32_t length,reserved;uint8_t data[256];} Read;
        const Transfer*q=input;assert(bytes==sizeof(*q)&&q->handle==UINT64_C(0x200000101)&&t->privateLive);
        assert(q->offset<=4096&&q->length<=4096-q->offset);
        if(selector==14){memcpy(t->privateBytes+q->offset,q->data,q->length);return KERN_SUCCESS;}
        ++t->privateReads;if(t->failPrivateRead)return kIOReturnError;
        Read r={{1,sizeof(r),0,0},q->length,0,{0}};
        memcpy(r.data,t->privateBytes+q->offset,q->length);
        assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));return KERN_SUCCESS;
    }
    if(selector==A5MaliImport){
        typedef struct {A5MaliHeader h;uint32_t port,usage;uint64_t reserved;} Import;
        typedef struct {A5MaliHeader h;uint64_t handle;uint32_t width,height,row,format;} Imported;
        const Import *q=input;assert(bytes==sizeof(*q));
        if(t->failImport)return kIOReturnNoMemory;
        assert(t->imports<32);IOSurfaceRef surface=IOSurfaceLookupFromMachPort(q->port);assert(surface);
        unsigned i=t->imports++;t->imported[i]=surface;
        assert(q->usage==(A5MaliRead|A5MaliWrite));
        assert(IOSurfaceGetWidth(surface)==32 && IOSurfaceGetHeight(surface)==32);
        Imported r={{1,sizeof(r),0,0},UINT64_C(0x100000010)+i,32,32,128,0x42475241};
        assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));return KERN_SUCCESS;
    }
    if(selector==A5MaliMap){
        typedef struct {A5MaliHeader h;uint64_t token;} Handle;
        typedef struct {A5MaliHeader h;uint64_t token;uint32_t bytes,flags;} Mapped;
        uint64_t token=((const Handle *)input)->token;
        unsigned i=(unsigned)(token-UINT64_C(0x100000010));assert(i<t->imports&&t->imported[i]);
        Mapped r={{1,sizeof(r),0,0},token,(uint32_t)IOSurfaceGetAllocSize(t->imported[i]),A5MaliRead|A5MaliWrite};
        assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));return KERN_SUCCESS;
    }
    if(selector==A5MaliRelease || selector==A5MaliUnmap){
        if(selector==A5MaliRelease){
            typedef struct {A5MaliHeader h;uint64_t token;} Handle;
            uint64_t token=((const Handle *)input)->token;
            if(token>=UINT64_C(0x100000010)){
                unsigned i=(unsigned)(token-UINT64_C(0x100000010));
                assert(i<t->imports && t->imported[i]);CFRelease(t->imported[i]);t->imported[i]=NULL;
            }
            ++t->releases;
        }return KERN_SUCCESS;
    }
    if(selector==A5NativeQuerySelector){
        assert(bytes==sizeof(A5NativeQueryRequest)&&*outBytes==sizeof(A5NativeQueryResult));
        const A5NativeQueryRequest *q=input;
        assert(q->surfaces[0]==0x100000001 && q->surfaces[1]==0x100000002 && q->surfaces[2] && q->surfaces[2]!=q->surfaces[0] && q->surfaces[2]!=q->surfaces[1]);
        for(unsigned i=0;i<4;++i)assert(!q->buffers[i]);
        A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,
            .jobBytes=A5NativeJobBytes,.flags=41};
        r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,16384,64,64,256,0x42475241,A5MaliRead};
        r.surfaces[1]=(A5NativeSpan){q->surfaces[1],0x11000000,4096,32,32,128,0x42475241,A5MaliRead|A5MaliWrite};
        r.surfaces[2]=(A5NativeSpan){q->surfaces[2],0x12000000,4096,32,32,128,0x42475241,A5MaliRead|A5MaliWrite};
        if(t->packedSource)r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,1048576,542,963,1088,0x42354131,A5MaliRead};
        if(t->sourceFault==1)r.surfaces[0].bytes=1047743;
        if(t->sourceFault==2)r.surfaces[0].rowBytes=1072;
        if(t->sourceFault==3)r.surfaces[0].pixelFormat=0x42475241;
        if(t->badAuxSpan)r.surfaces[2].bytes=128;
        if(t->badAuxAlias)r.surfaces[2].gpuVA=r.surfaces[1].gpuVA;
        if(t->badFormat)r.surfaces[0].pixelFormat=0x52476841;
        if(t->badDestinationRead)r.surfaces[1].usage=A5MaliWrite;
        memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++t->queries;return KERN_SUCCESS;
    }
    assert(selector==A5NativeSubmitSelector);
    assert(bytes==sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
    const A5NativeSubmitRequest *q=input;
    assert(q->header.version==1 && q->header.size==sizeof(*q));
    assert(q->mappingEpoch==41 && q->profileID==t->profile->profileID && q->jobBytes==A5NativeJobBytes);
    assert(q->vertexOffset==0 && q->tilerOffset==0x100 && q->fragmentOffset==0x200);
    assert(q->readSurfaces==7 && q->writeSurfaces==2 && !q->readBuffers);
    const uint8_t *jobs=(const uint8_t *)input+sizeof(*q);
    /* Released Mesa v4: magnify_nearest bit0, minify_nearest bit1.
     * These must reflect actual caller filtering, not hardcoded nearest. */
    uint32_t samplerWord;memcpy(&samplerWord,jobs+0x680,4);
    assert((samplerWord&3)==(t->linearSampler?0u:3u));
    if(t->packedSource){
        /* Hardware descriptor, not a format guard: RGB5_A1_UNORM enum=65
         * from released v4.xml; BGRA R/B swizzle0x60a, identity0x688. */
        uint32_t tex[8];memcpy(tex,jobs+0x600,sizeof(tex));
        assert((tex[2]&0x3fffff)==((65u<<12)|0x60a));
        uint64_t pointer;int32_t row;uint32_t span;
        memcpy(&pointer,jobs+0x620,8);memcpy(&row,jobs+0x628,4);memcpy(&span,jobs+0x62c,4);
        assert(pointer==0x10000000&&row==1088&&span==1047744);
    }
    uint32_t primitive,number,invocations;uint64_t address;
    memcpy(&primitive,jobs+0x128,4);memcpy(&number,jobs+0x134,4);
    memcpy(&address,jobs+0x138,8);memcpy(&invocations,jobs+0x20,4);
    assert(((primitive>>8)&7)==(t->indexSize==2?2u:3u));
    assert(number==5&&invocations==3&&address==A5NativeJobVA+0x3a000);
    assert(!memcmp(jobs+0x3a000,t->indices,6*t->indexSize));
    assert(A5NativeCheckJobChain(jobs,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,NO)==1);
    const A5MaliCompiledPass *p=t->profile->passes;
    assert(!memcmp(jobs+0x2000,p->vertex.bytes,p->vertex.byteCount));
    assert(!memcmp(jobs+0x4000,p->fragment.bytes,p->fragment.byteCount));
    /* No synthesized uniforms: the actual caller bytes, including odd binding
     * offset and post-encoding shared writes, must reach the uploaded arena. */
    assert(contains(jobs+0xc000,0x4000,t->vertex,sizeof(t->vertex)));
    assert(contains(jobs+0xc000,0x4000,t->matrix,sizeof(t->matrix)));
    assert(contains(jobs+0xc000,0x4000,t->texmat,sizeof(t->texmat)));
    assert(contains(jobs+0xc000,0x4000,t->filter,32));
    assert(contains(jobs+0xc000,0x4000,t->edr,sizeof(t->edr)));
    A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=200,.fragmentFence=201};
    if(t->badFence)r.fragmentFence=0;
    assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++t->submits;
    return KERN_SUCCESS;
}
static MTLRenderPipelineDescriptor *descriptor(const A5MaliCompiledProfile *p,A5MaliMetalLibrary *library)
{
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    d.vertexFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:p->vertexName]];
    d.fragmentFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:p->fragmentName]];
    for(unsigned i=0;i<8;++i)d.colorAttachments[i].pixelFormat=p->colorFormats[i];
    d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
    for(unsigned i=0;i<p->attributeCount;++i){const A5MaliCompiledVertexAttribute*a=p->attributes+i;
        d.vertexDescriptor.attributes[a->index].format=a->format;
        d.vertexDescriptor.attributes[a->index].offset=a->offset;
        d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
    for(unsigned i=0;i<p->layoutCount;++i){const A5MaliCompiledVertexLayout*l=p->layouts+i;
        d.vertexDescriptor.layouts[l->index].stride=l->stride;
        d.vertexDescriptor.layouts[l->index].stepFunction=l->stepFunction;
        d.vertexDescriptor.layouts[l->index].stepRate=l->stepRate;}
    assert(p->attachmentContracts && p->attachmentContractCount);
    for(unsigned i=0;i<8;++i){const A5MaliCompiledAttachmentState *c=&p->attachmentContracts[0].attachments[i];
        MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[i];
        a.writeMask=c->writeMask;a.blendingEnabled=c->blendEnabled;
        a.rgbBlendOperation=c->rgbOperation;a.alphaBlendOperation=c->alphaOperation;
        a.sourceRGBBlendFactor=c->sourceRGB;a.destinationRGBBlendFactor=c->destinationRGB;
        a.sourceAlphaBlendFactor=c->sourceAlpha;a.destinationAlphaBlendFactor=c->destinationAlpha;}
    return d;
}
static A5MaliMetalTexture *sourceTexture(A5MaliRestrictedDevice *device,Transport *t)
{
 if(!t->packedSource)return [device hostTestTextureWithResource:
     (A5MaliResource){0x100000001,64,64,256,A5MaliRead}];
 MTLTextureDescriptor*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
     MTLPixelFormatBGR5A1Unorm width:542 height:963 mipmapped:NO];
 d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
 A5MaliTextureAllocationLayout layout;assert(A5MaliBuildTextureAllocationLayout(d,&layout,NULL));
 layout.backingRowBytes=1088;layout.totalBytes=1047744;
 layout.levels[0].rowBytes=1088;layout.levels[0].byteLength=1047744;
 A5MaliSurface*surface=[[device privateDevice]hostTestSurfaceWithResource:
     (A5MaliResource){0x100000001,542,963,1088,A5MaliRead|A5MaliWrite}];
 return [[A5MaliMetalTexture alloc]initWithSurface:surface device:device descriptor:d layout:layout external:YES];
}
static A5MaliMetalBuffer *encode(A5MaliRestrictedDevice *device,A5MaliReadSurfCandidate *pipeline,
    A5MaliMetalTexture *source,A5MaliMetalTexture *destination,Transport *t,
    BOOL samplerMissing,BOOL undersized)
{
    A5MaliMetalBuffer *buffer=[[device newCommandQueue] commandBuffer];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=(id)destination;
    pass.colorAttachments[0].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    if(t->providedAux)pass.colorAttachments[1].texture=(id)[device hostTestTextureWithResource:
        (A5MaliResource){0x100000003,32,32,128,A5MaliRead|A5MaliWrite}];
    pass.colorAttachments[1].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[1].storeAction=MTLStoreActionStore;
    A5MaliMetalRenderEncoder *r=[buffer renderCommandEncoderWithDescriptor:pass];assert(r);
    /* Valid setter order: viewport precedes pipeline, even on a 32x32 FBO. */
    [r setViewport:(MTLViewport){0,0,1080,1920,0,1}];
    [r setRenderPipelineState:pipeline];
    A5MaliPrivateBuffer *vertices=[device newBufferWithLength:209 options:0];assert(vertices);
    memset(vertices.contents,0xa5,209);
    [r setVertexBuffer:vertices offset:17 atIndex:1];
    [r setVertexBytes:t->matrix length:64 atIndex:2];
    [r setVertexBytes:t->texmat length:16 atIndex:3];
    uint8_t inlineFilter[72];memcpy(inlineFilter,t->filter,72);
    [r setFragmentBytes:inlineFilter length:undersized?71:72 atIndex:1];
    memset(inlineFilter,0xff,sizeof(inlineFilter)); /* setBytes owns the old copy */
    [r setFragmentBytes:t->edr length:2 atIndex:6];
    if(samplerMissing)[r setFragmentTexture:source atIndex:3];
    else {
        MTLSamplerDescriptor *sampler=[MTLSamplerDescriptor new];
        sampler.minFilter=sampler.magFilter=t->linearSampler?MTLSamplerMinMagFilterLinear:MTLSamplerMinMagFilterNearest;
        [r setFragmentTexture:source atTextureIndex:3 samplerState:[device newSamplerStateWithDescriptor:sampler] atSamplerIndex:0];
    }
    NSUInteger offset=5*t->indexSize,length=6*t->indexSize;
    A5MaliPrivateBuffer *indices=[device newBufferWithLength:offset+length+16
        options:t->privateIndex?MTLResourceStorageModePrivate:MTLResourceStorageModeShared];assert(indices);
    if(t->privateIndex){NSMutableData*zero=[NSMutableData dataWithLength:indices.length];
        assert([indices uploadBytes:zero.bytes offset:0 length:zero.length]==KERN_SUCCESS);}
    else memset(indices.contents,0,indices.length);
    __weak A5MaliPrivateBuffer*heldIndices=indices;
    [r drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6
        indexType:t->indexSize==2?MTLIndexTypeUInt16:MTLIndexTypeUInt32 indexBuffer:indices
        indexBufferOffset:t->indexFault==3?offset+1:offset];
    /* Rebinding and writes after encoding must preserve binding identity and
     * read the contents at commit. Actual indices are not CPU-expanded. */
    A5MaliPrivateBuffer *other=[device newBufferWithLength:209 options:0];
    [r setVertexBuffer:other offset:17 atIndex:1];[r endEncoding];
    memcpy((uint8_t *)vertices.contents+17,t->vertex,192);
    uint8_t values[24];memcpy(values,t->indices,length);
    if(t->indexFault==1||t->indexFault==2){uint32_t bad=t->indexFault==1?256:4;memcpy(values,&bad,t->indexSize);}
    if(t->privateIndex)assert([indices uploadBytes:values offset:offset length:length]==KERN_SUCCESS);
    else memcpy((uint8_t *)indices.contents+offset,values,length);
    indices=nil;if(t->indexFault!=3&&!t->failImport&&!samplerMissing&&!undersized)assert(heldIndices);
    return buffer;
}
int main(void)
{
 for(unsigned packed=0;packed<=1;++packed)for(unsigned width=2;width<=4;width+=2)@autoreleasepool {
    Transport t={0};t.indexSize=width;t.packedSource=packed;t.profile=A5MaliCompiledProfileForID(packed?99:100);assert(t.profile);
    const uint32_t sequence[6]={2,0,1,2,1,3};
    for(unsigned i=0;i<6;++i)memcpy(t.indices+i*width,sequence+i,width);
    memset(t.vertex,0x31,sizeof(t.vertex));memset(t.matrix,0x42,sizeof(t.matrix));
    memset(t.texmat,0x53,sizeof(t.texmat));memset(t.filter,0x64,sizeof(t.filter));
    t.edr[0]=0x34;t.edr[1]=0x38;
    A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&t
        commandCapabilities:63 operationCapabilities:127|(1u<<7)|(1u<<8)|(1u<<13)|(1u<<14)|(1u<<16)|(1u<<17)];
    const char *path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
    A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:
        [NSString stringWithUTF8String:path]]error:NULL];assert(library);
    MTLRenderPipelineDescriptor *d=descriptor(t.profile,library);
    d.colorAttachments[1].pixelFormat=MTLPixelFormatInvalid;
    d.colorAttachments[1].writeMask=MTLColorWriteMaskAll;
    NSError *error=nil;
    A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];
    assert(pipeline&&!error);
    assert(d.colorAttachments[1].pixelFormat==MTLPixelFormatInvalid && d.colorAttachments[1].writeMask==MTLColorWriteMaskAll);
    MTLRenderPipelineDescriptor *bad=[d copy];bad.colorAttachments[1].pixelFormat=MTLPixelFormatRGBA16Float;
    assert(![device newRenderPipelineStateWithDescriptor:bad error:NULL]);
    bad=[d copy];bad.colorAttachments[1].writeMask=MTLColorWriteMaskRed;
    assert(![device newRenderPipelineStateWithDescriptor:bad error:NULL]);
    bad=[d copy];bad.colorAttachments[1].blendingEnabled=YES;
    assert(![device newRenderPipelineStateWithDescriptor:bad error:NULL]);
    bad=[d copy];bad.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA16Float;
    assert(![device newRenderPipelineStateWithDescriptor:bad error:NULL]);
    bad=[d copy];bad.vertexDescriptor.layouts[1].stride=47;
    assert(![device newRenderPipelineStateWithDescriptor:bad error:NULL]);
    bad=descriptor(A5MaliCompiledProfileForID(99),library);
    bad.colorAttachments[1].pixelFormat=MTLPixelFormatInvalid;
    assert([device newRenderPipelineStateWithDescriptor:bad error:NULL]); /* now metadata-normalized */
    A5MaliRestrictedDevice *wrong=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&t
        commandCapabilities:63 operationCapabilities:127|(1u<<7)|(1u<<8)|(1u<<13)|(1u<<14)|(1u<<16)|(1u<<17)];
    assert(![wrong newRenderPipelineStateWithDescriptor:d error:NULL]);
    @autoreleasepool {
      A5MaliMetalTexture *source=sourceTexture(device,&t);
      A5MaliMetalTexture *destination=[device hostTestTextureWithResource:
          (A5MaliResource){0x100000002,32,32,128,A5MaliWrite}];
      A5MaliMetalBuffer *b=encode(device,pipeline,source,destination,&t,NO,NO);
      assert(t.imports==1 && !t.queries);[b commit];[b waitUntilCompleted];
      assert(b.status==MTLCommandBufferStatusCompleted && !b.error && t.queries==1 && t.submits==1);
      /* Same compiled pipeline uses a real caller-provided RT1 without
       * allocating an internal replacement or granting it GPU write access. */
      t.providedAux=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);
      assert(t.imports==1);[b commit];[b waitUntilCompleted];
      assert(b.status==MTLCommandBufferStatusCompleted && t.queries==2 && t.submits==2);
      t.providedAux=NO;
      t.badAuxSpan=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);[b commit];[b waitUntilCompleted];
      assert(b.status==MTLCommandBufferStatusError && t.queries==3 && t.submits==2);t.badAuxSpan=NO;
      t.badAuxAlias=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);[b commit];[b waitUntilCompleted];
      assert(b.status==MTLCommandBufferStatusError && t.queries==4 && t.submits==2);t.badAuxAlias=NO;
      t.failImport=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);[b commit];[b waitUntilCompleted];
      assert(b.status==MTLCommandBufferStatusError && t.queries==4 && t.submits==2);t.failImport=NO;
    }
    @autoreleasepool {
      A5MaliMetalTexture *source=sourceTexture(device,&t);
      A5MaliMetalTexture *destination=[device hostTestTextureWithResource:
          (A5MaliResource){0x100000002,32,32,128,A5MaliWrite}];
      for(unsigned fault=1;fault<=3;++fault){t.indexFault=fault;
        unsigned before=t.queries,submitted=t.submits;
        A5MaliMetalBuffer*b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusError);
        assert(t.queries==before&&t.submits==submitted);
      }t.indexFault=0;
      t.privateIndex=YES;
      @autoreleasepool {
        A5MaliMetalBuffer*b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusCompleted);
      }
      t.failPrivateRead=YES;unsigned before=t.queries;
      @autoreleasepool {
        A5MaliMetalBuffer*b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusError&&t.queries==before);
      }
    }
    assert(t.privateCreates==2&&t.privateReleases==2&&!t.privateLive&&t.privateReads==2);
    for(unsigned i=0;i<t.imports;++i)assert(!t.imported[i]);
    t.privateIndex=NO;t.failPrivateRead=NO;t.linearSampler=YES;
    @autoreleasepool {
      A5MaliMetalTexture *source=sourceTexture(device,&t);
      A5MaliMetalTexture *destination=[device hostTestTextureWithResource:(A5MaliResource){0x100000002,32,32,128,A5MaliWrite}];
      unsigned before=t.queries,submitted=t.submits;
      A5MaliMetalBuffer *linear=encode(device,pipeline,source,destination,&t,NO,NO);
      [linear commit];[linear waitUntilCompleted];
      assert(linear.status==MTLCommandBufferStatusCompleted&&t.queries==before+1&&t.submits==submitted+1);
      if(t.packedSource)for(unsigned fault=1;fault<=3;++fault){
        t.sourceFault=fault;unsigned queried=t.queries,done=t.submits;
        A5MaliMetalBuffer *badSource=encode(device,pipeline,source,destination,&t,NO,NO);
        [badSource commit];[badSource waitUntilCompleted];
        assert(badSource.status==MTLCommandBufferStatusError&&t.queries==queried+1&&t.submits==done);
      }
      t.sourceFault=0;before=t.queries-1;submitted=t.submits-1;
      /* Last command for these aliases: an attempted GPU submission without
       * both terminal fences is quarantined, never immediately recycled. */
      t.badFence=YES;A5MaliMetalBuffer *failed=encode(device,pipeline,source,destination,&t,NO,NO);
      [failed commit];[failed waitUntilCompleted];
      assert(failed.status==MTLCommandBufferStatusError&&t.queries==before+2&&t.submits==submitted+2);
    }
    assert(t.imports>0);
    for(unsigned i=0;i+1<t.imports;++i)assert(!t.imported[i]);
    assert(t.imported[t.imports-1]);
    printf("profile%u source%u indexed u16/u32: actual native index descriptor, commit snapshots, private reads, exact vertex bounds, inactive RT1, allocation/alias/fence gates passed\n",t.profile->profileID,packed?43:80);
 }
 return 0;
}
