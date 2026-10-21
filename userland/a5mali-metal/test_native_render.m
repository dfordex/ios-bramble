/* SPDX-License-Identifier: MIT
 * Real authenticated shader registry and real v4 descriptor encoder; only the
 * kernel transport is mocked. This tests submission, not hardware pixels.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned queries,submits,releases;
    BOOL badFormat,badFence,badDestinationRead;
    uint8_t vertex[144],matrix[64],texmat[16],filter[72],edr[2];
    const A5MaliCompiledProfile *profile;
} Transport;
static BOOL contains(const uint8_t *haystack,size_t count,const void *needle,size_t bytes)
{ for(size_t i=0;i+bytes<=count;++i)if(!memcmp(haystack+i,needle,bytes))return YES;return NO; }
static kern_return_t transport(void *opaque,uint32_t selector,const void *input,
    size_t bytes,void *output,size_t *outBytes)
{
    Transport *t=opaque;
    if(selector==A5MaliRelease || selector==A5MaliUnmap){
        if(selector==A5MaliRelease)++t->releases;return KERN_SUCCESS;
    }
    if(selector==A5NativeQuerySelector){
        assert(bytes==sizeof(A5NativeQueryRequest)&&*outBytes==sizeof(A5NativeQueryResult));
        const A5NativeQueryRequest *q=input;
        assert(q->surfaces[0]==0x100000001 && q->surfaces[1]==0x100000002);
        for(unsigned i=0;i<4;++i)assert(!q->buffers[i]);
        A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,
            .jobBytes=A5NativeJobBytes,.flags=41};
        r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,16384,64,64,256,0x42475241,A5MaliRead};
        r.surfaces[1]=(A5NativeSpan){q->surfaces[1],0x11000000,4096,32,32,128,0x42475241,A5MaliRead|A5MaliWrite};
        if(t->badFormat)r.surfaces[0].pixelFormat=0x52476841;
        if(t->badDestinationRead)r.surfaces[1].usage=A5MaliWrite;
        memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++t->queries;return KERN_SUCCESS;
    }
    assert(selector==A5NativeSubmitSelector);
    assert(bytes==sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
    const A5NativeSubmitRequest *q=input;
    assert(q->header.version==1 && q->header.size==sizeof(*q));
    assert(q->mappingEpoch==41 && q->profileID==99 && q->jobBytes==A5NativeJobBytes);
    assert(q->vertexOffset==0 && q->tilerOffset==0x100 && q->fragmentOffset==0x200);
    assert(q->readSurfaces==3 && q->writeSurfaces==2 && !q->readBuffers);
    const uint8_t *jobs=(const uint8_t *)input+sizeof(*q);
    const A5MaliCompiledPass *p=t->profile->passes;
    assert(!memcmp(jobs+0x2000,p->vertex.bytes,p->vertex.byteCount));
    assert(!memcmp(jobs+0x4000,p->fragment.bytes,p->fragment.byteCount));
    /* No synthesized uniforms: the actual caller bytes, including odd binding
     * offset and post-encoding shared writes, must reach the uploaded arena. */
    assert(contains(jobs+0xc000,0x4000,t->vertex,sizeof(t->vertex)));
    assert(contains(jobs+0xc000,0x4000,t->matrix,sizeof(t->matrix)));
    assert(contains(jobs+0xc000,0x4000,t->texmat,sizeof(t->texmat)));
    assert(contains(jobs+0xc000,0x4000,t->filter,sizeof(t->filter)));
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
    return d;
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
    A5MaliMetalRenderEncoder *r=[buffer renderCommandEncoderWithDescriptor:pass];assert(r);
    /* Valid setter order: viewport precedes pipeline, even on a 32x32 FBO. */
    [r setViewport:(MTLViewport){0,0,1080,1920,0,1}];
    [r setRenderPipelineState:pipeline];
    A5MaliPrivateBuffer *vertices=[device newBufferWithLength:161 options:0];assert(vertices);
    memset(vertices.contents,0xa5,161);
    [r setVertexBuffer:vertices offset:17 atIndex:1];
    [r setVertexBytes:t->matrix length:64 atIndex:2];
    [r setVertexBytes:t->texmat length:16 atIndex:3];
    uint8_t inlineFilter[72];memcpy(inlineFilter,t->filter,72);
    [r setFragmentBytes:inlineFilter length:undersized?71:72 atIndex:1];
    memset(inlineFilter,0xff,sizeof(inlineFilter)); /* setBytes owns the old copy */
    [r setFragmentBytes:t->edr length:2 atIndex:6];
    [r setFragmentTexture:source atIndex:3];
    if(!samplerMissing)[r setFragmentSamplerState:[device newSamplerStateWithDescriptor:
        [MTLSamplerDescriptor new]] atIndex:0];
    [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [r endEncoding];
    memcpy((uint8_t *)vertices.contents+17,t->vertex,144); /* visible at commit */
    return buffer;
}
int main(void)
{
    @autoreleasepool{
        Transport t={0};t.profile=A5MaliCompiledProfileForID(99);assert(t.profile);
        for(unsigned i=0;i<144;++i)t.vertex[i]=(uint8_t)(17+i*3);
        for(unsigned i=0;i<64;++i)t.matrix[i]=(uint8_t)(42+i*5);
        for(unsigned i=0;i<16;++i)t.texmat[i]=(uint8_t)(96+i*7);
        for(unsigned i=0;i<72;++i)t.filter[i]=(uint8_t)(149+i*11);
        t.edr[0]=0x34;t.edr[1]=0x38;
        A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]
            initWithTransport:transport context:&t commandCapabilities:63
            operationCapabilities:127|(1u<<16)|(1u<<17)];
        const char *path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
        A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:
            [NSString stringWithUTF8String:path]] error:NULL];assert(library);
        NSError *error=nil;
        A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:
            descriptor(t.profile,library) error:&error];assert(pipeline&&!error);
        A5MaliMetalTexture *source=[device hostTestTextureWithResource:
            (A5MaliResource){0x100000001,64,64,256,A5MaliRead}];
        A5MaliMetalTexture *destination=[device hostTestTextureWithResource:
            (A5MaliResource){0x100000002,32,32,128,A5MaliWrite}];
        A5MaliMetalBuffer *b=encode(device,pipeline,source,destination,&t,NO,NO);
        assert(t.queries==0&&t.submits==0);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusCompleted&&!b.error&&t.queries==1&&t.submits==1);
        b=encode(device,pipeline,source,destination,&t,YES,NO);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==1&&t.submits==1);
        b=encode(device,pipeline,source,destination,&t,NO,YES);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==1&&t.submits==1);
        /* Unsupported raster state is an explicit command error, never a
         * selector crash or silently ignored state change. */
        MTLRenderPassDescriptor *statePass=[MTLRenderPassDescriptor renderPassDescriptor];
        statePass.colorAttachments[0].texture=(id)destination;
        statePass.colorAttachments[0].loadAction=MTLLoadActionLoad;
        statePass.colorAttachments[0].storeAction=MTLStoreActionStore;
        b=[[device newCommandQueue]commandBuffer];
        A5MaliMetalRenderEncoder *stateEncoder=[b renderCommandEncoderWithDescriptor:statePass];
        assert(stateEncoder.device==device);stateEncoder.label=@"checked raster state";
        [stateEncoder pushDebugGroup:@"state"];[stateEncoder insertDebugSignpost:@"explicit rejection"];
        [stateEncoder popDebugGroup];[stateEncoder setCullMode:MTLCullModeBack];
        [stateEncoder endEncoding];[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&b.error.code==kIOReturnUnsupported);
        assert(t.queries==1&&t.submits==1);
        t.badFormat=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==2&&t.submits==1);
        t.badFormat=NO;t.badFence=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==3&&t.submits==2);
        t.badFence=NO;t.badDestinationRead=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==4&&t.submits==2);
        puts("native render: authenticated code, caller binding snapshots, mapping epoch, format checks, fences and unsupported state passed (mock transport)");
    }
    return 0;
}
