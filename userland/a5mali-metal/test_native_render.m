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
#include <unistd.h>
#include <stdio.h>

@interface A5MaliMetalBuffer (StockSelectorForwardTest)
- (BOOL)commitAndWaitUntilSubmitted;
@end
@interface A5MaliMetalRenderEncoder (StockSelectorForwardTest)
- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atTextureIndex:(NSUInteger)textureIndex
    samplerState:(A5MaliSamplerState *)sampler atSamplerIndex:(NSUInteger)samplerIndex;
@end
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
        assert(q->surfaces[0]==0x100000001 && q->surfaces[1]==0x100000002 && !q->surfaces[2]);
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
    assert(p->attachmentContracts && p->attachmentContractCount);
    for(unsigned i=0;i<8;++i){const A5MaliCompiledAttachmentState *c=&p->attachmentContracts[0].attachments[i];
        MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[i];
        a.writeMask=c->writeMask;a.blendingEnabled=c->blendEnabled;
        a.rgbBlendOperation=c->rgbOperation;a.alphaBlendOperation=c->alphaOperation;
        a.sourceRGBBlendFactor=c->sourceRGB;a.destinationRGBBlendFactor=c->destinationRGB;
        a.sourceAlphaBlendFactor=c->sourceAlpha;a.destinationAlphaBlendFactor=c->destinationAlpha;}
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
    /* QuartzCore A2 keeps an actual disabled RT1 attachment. It must not
     * become a queried/submitted output just because it exists. */
    pass.colorAttachments[1].texture=(id)[device hostTestTextureWithResource:
        (A5MaliResource){0x100000003,32,32,128,A5MaliWrite}];
    pass.colorAttachments[1].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[1].storeAction=MTLStoreActionStore;
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
    if(samplerMissing)[r setFragmentTexture:source atIndex:3];
    else [r setFragmentTexture:source atTextureIndex:3 samplerState:[device newSamplerStateWithDescriptor:
        [MTLSamplerDescriptor new]] atSamplerIndex:0];
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
        assert(t.profile->colorFormats[1]==MTLPixelFormatBGRA8Unorm);
        assert(t.profile->attachmentContracts[0].attachments[1].writeMask==MTLColorWriteMaskNone);
        A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:
            descriptor(t.profile,library) error:&error];assert(pipeline&&!error);
        A5MaliRestrictedDevice *wrongDevice=[[A5MaliRestrictedDevice alloc]
            initWithTransport:transport context:&t commandCapabilities:63
            operationCapabilities:127|(1u<<16)|(1u<<17)];
        FILE *capture=tmpfile();assert(capture);
        int original=dup(STDERR_FILENO);assert(original>=0);
        fflush(stderr);assert(dup2(fileno(capture),STDERR_FILENO)>=0);
        for(unsigned attempt=0;attempt<40;++attempt){
            assert(![wrongDevice newRenderPipelineStateWithDescriptor:descriptor(t.profile,library) error:&error]);
            assert([error.localizedDescription containsString:@"same-device"]);
        }
        fflush(stderr);assert(dup2(original,STDERR_FILENO)>=0);close(original);
        assert(!fseek(capture,0,SEEK_END));long logBytes=ftell(capture);assert(logBytes>0&&logBytes<200000);
        rewind(capture);NSMutableData *log=[NSMutableData dataWithLength:(NSUInteger)logBytes];
        assert(fread(log.mutableBytes,1,log.length,capture)==log.length);fclose(capture);
        NSString *diagnostic=[[NSString alloc]initWithData:log encoding:NSUTF8StringEncoding];assert(diagnostic);
        NSUInteger lines=[[diagnostic componentsSeparatedByString:@"\n"]count]-1;
        assert(lines>0&&lines<=32); /* process bound survives a repeated reject loop */
        assert([diagnostic containsString:@"vertex=downsample_blur_vert_lph"]);
        assert([diagnostic containsString:@"RT1={f:80,w:0,b:0"]);
        assert([diagnostic containsString:@"VB1=48/1/1"]);
        assert([diagnostic containsString:@"reason=factory requires authenticated same-device"]);
        error=nil;
        A5MaliMetalTexture *source=[device hostTestTextureWithResource:
            (A5MaliResource){0x100000001,64,64,256,A5MaliRead}];
        A5MaliMetalTexture *destination=[device hostTestTextureWithResource:
            (A5MaliResource){0x100000002,32,32,128,A5MaliWrite}];
        A5MaliMetalBuffer *b=encode(device,pipeline,source,destination,&t,NO,NO);
        /* Actual QuartzCore start/completion SPI must preserve ordinary GPU
         * work, reject protection without transport, and keep terminal state. */
        b.protectionOptions=0;
        assert(b.protectionOptions==0);
        assert(t.queries==0&&t.submits==0);assert([b commitAndWaitUntilSubmitted]);[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusCompleted&&!b.error&&t.queries==1&&t.submits==1);
        assert(b.GPUStartTime==0&&b.GPUEndTime==0&&b.kernelStartTime==0&&b.kernelEndTime==0);
        BOOL threw=NO;
        @try { b.protectionOptions=0; }
        @catch (NSException *exception) { threw=[exception.name isEqual:NSInternalInconsistencyException]; }
        assert(threw&&b.status==MTLCommandBufferStatusCompleted&&!b.error);
        A5MaliMetalBuffer *protectedBuffer=encode(device,pipeline,source,destination,&t,NO,NO);
        protectedBuffer.protectionOptions=1;
        protectedBuffer.protectionOptions=0; /* rejection cannot be erased */
        assert(protectedBuffer.protectionOptions==0&&protectedBuffer.error.code==kIOReturnUnsupported);
        dispatch_semaphore_t protectedDone=dispatch_semaphore_create(0);
        [protectedBuffer addCompletedHandler:^(id<MTLCommandBuffer> completed){
            assert(completed.status==MTLCommandBufferStatusError&&completed.error.code==kIOReturnUnsupported);
            assert([(A5MaliMetalBuffer *)completed protectionOptions]==0);
            dispatch_semaphore_signal(protectedDone);
        }];
        assert(![protectedBuffer commitAndWaitUntilSubmitted]);[protectedBuffer waitUntilCompleted];
        assert(dispatch_semaphore_wait(protectedDone,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        assert(t.queries==1&&t.submits==1);
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
        t.badFormat=NO;t.badDestinationRead=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);
        [b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==3&&t.submits==1);
        /* The SPI waits for work on an independently configured async queue,
         * rather than returning a fabricated submission/completion status. */
        A5MaliMetalQueue *asyncQueue=[device newCommandQueue];
        [asyncQueue setSubmissionQueue:dispatch_queue_create("a5.stock-selector-test",DISPATCH_QUEUE_SERIAL)];
        A5MaliMetalBuffer *async=[asyncQueue commandBuffer];
        assert([async respondsToSelector:@selector(commitAndWaitUntilSubmitted)]);
        assert([async commitAndWaitUntilSubmitted]&&async.status==MTLCommandBufferStatusCompleted);
        /* Nil is a real unbind; invalid combined sampler slots retain the
         * existing explicit command error, with no native query/submission. */
        A5MaliMetalBuffer *combined=[asyncQueue commandBuffer];
        A5MaliMetalRenderEncoder *combinedEncoder=[combined renderCommandEncoderWithDescriptor:statePass];assert(combinedEncoder);
        [combinedEncoder setFragmentTexture:source atTextureIndex:3 samplerState:nil atSamplerIndex:0];
        [combinedEncoder setFragmentTexture:nil atTextureIndex:3 samplerState:nil atSamplerIndex:0];
        [combinedEncoder setFragmentTexture:source atTextureIndex:3 samplerState:nil atSamplerIndex:16];
        [combinedEncoder endEncoding];assert(![combined commitAndWaitUntilSubmitted]);
        assert(combined.status==MTLCommandBufferStatusError&&t.queries==3&&t.submits==1);
        /* Missing completion fences quarantine all referenced aliases. Run
         * this last; later commands must never reuse those GPU pages. */
        t.badDestinationRead=NO;t.badFence=YES;b=encode(device,pipeline,source,destination,&t,NO,NO);
        assert(![b commitAndWaitUntilSubmitted]);[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&t.queries==4&&t.submits==2);
        puts("native render: authenticated code, caller binding snapshots, mapping epoch, format checks, fences and unsupported state passed (mock transport)");
    }
    return 0;
}
