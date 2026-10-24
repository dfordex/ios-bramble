/* SPDX-License-Identifier: MIT
 * Actual authenticated specialization, Metal wrappers and released native
 * emitter. Only the kernel transport is mocked: no GPU pixels are claimed.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

@interface A5MaliMetalBuffer (Generic600FenceTest)
- (A5MaliCommandBuffer *)privateBuffer;
@end
@interface A5MaliReadSurfCandidate (Generic602BlendTest)
- (BOOL)sourceOver;
@end

typedef struct {
    float position[4], texcoord0[2], texcoord1[2];
    uint16_t color[4];
    uint8_t padding[8];
} Vertex;
_Static_assert(sizeof(Vertex)==48,"actual QC packing0 stride");
typedef struct {
    unsigned queries,submits,releases;
    BOOL failSubmit;
    Vertex vertices[4];
    float matrix[16];
    const A5MaliCompiledProfile *profile;
} State;

static BOOL contains(const uint8_t *bytes,size_t count,const void *needle,size_t length)
{
    for(size_t i=0;i+length<=count;++i)
        if(!memcmp(bytes+i,needle,length))return YES;
    return NO;
}
static kern_return_t transport(void *context,uint32_t selector,const void *input,
    size_t inputBytes,void *output,size_t *outputBytes)
{
    State *s=context;
    if(selector==A5MaliUnmap)return KERN_SUCCESS;
    if(selector==A5MaliRelease){++s->releases;return KERN_SUCCESS;}
    if(selector==A5NativeQuerySelector){
        const A5NativeQueryRequest *q=input;
        assert(inputBytes==sizeof(*q)&&*outputBytes==sizeof(A5NativeQueryResult));
        assert(q->surfaces[0]==UINT64_C(0x100000001));
        for(unsigned i=1;i<A5NativeSlots;++i)assert(!q->surfaces[i]);
        for(unsigned i=0;i<A5NativeSlots;++i)assert(!q->buffers[i]);
        A5NativeQueryResult result={.header={1,sizeof(result),0,0},
            .jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=79};
        result.surfaces[0]=(A5NativeSpan){q->surfaces[0],UINT64_C(0x10000000),4096,
            32,32,128,UINT32_C(0x42475241),A5MaliRead|A5MaliWrite};
        memcpy(output,&result,sizeof(result));*outputBytes=sizeof(result);
        ++s->queries;return KERN_SUCCESS;
    }
    /* No private-BO create/upload/map may substitute for these CPU-backed
     * caller buffers: they must be snapshotted into the real job arena. */
    assert(selector==A5NativeSubmitSelector);
    const A5NativeSubmitRequest *q=input;
    assert(inputBytes==sizeof(*q)+A5NativeJobBytes&&q->header.version==1&&q->header.size==sizeof(*q));
    assert(q->profileID==s->profile->profileID&&q->mappingEpoch==79&&q->jobBytes==A5NativeJobBytes);
    assert(q->vertexOffset==0&&q->tilerOffset==0x100&&q->fragmentOffset==0x200);
    assert(q->readSurfaces==1&&q->writeSurfaces==1&&!q->readBuffers);
    assert(q->surfaces[0]==UINT64_C(0x100000001));
    for(unsigned i=1;i<A5NativeSlots;++i)assert(!q->surfaces[i]);
    for(unsigned i=0;i<A5NativeSlots;++i)assert(!q->buffers[i]);
    const uint8_t *jobs=(const uint8_t *)input+sizeof(*q);
    const A5MaliCompiledPass *pass=s->profile->passes;
    assert(pass->passID==s->profile->profileID&&pass->logicalTarget==0);
    assert(pass->vertex.byteCount==1808&&pass->fragment.byteCount==848);
    assert(!memcmp(jobs+0x6000,pass->vertex.bytes,pass->vertex.byteCount));
    assert(!memcmp(jobs+0x8000,pass->fragment.bytes,pass->fragment.byteCount));
    assert(contains(jobs+0x20000,0x10000,s->vertices,sizeof(s->vertices)));
    assert(contains(jobs+0x20000,0x10000,s->matrix,sizeof(s->matrix)));
    /* LoadActionLoad preserves pixels outside the actual draw via the real
     * destination preload chain; it is not a framebuffer-only no-op. */
    assert(A5NativeCheckJobChain(jobs,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,NO)==1);
    ++s->submits;
    if(s->failSubmit)return kIOReturnTimeout;
    A5NativeSubmitResult result={.header={1,sizeof(result),0,0},.tilerFence=1200,.fragmentFence=1201};
    assert(*outputBytes==sizeof(result));
    memcpy(output,&result,sizeof(result));*outputBytes=sizeof(result);return KERN_SUCCESS;
}

static MTLFunctionConstantValues *fragmentConstants(uint32_t profileID,BOOL changed)
{
    size_t count=0;
    const A5MaliCompiledFunctionConstant *values=A5MaliCompiledConstantsForProfile(profileID,&count);
    assert(values&&count==58);
    MTLFunctionConstantValues *result=[MTLFunctionConstantValues new];
    BOOL changedOne=NO;
    for(size_t i=0;i<count;++i){
        const A5MaliCompiledFunctionConstant *value=values+i;
        assert(value->name&&((value->dataType==MTLDataTypeUChar3&&value->byteCount==3)||
            ((value->dataType==MTLDataTypeUChar||value->dataType==MTLDataTypeBool)&&value->byteCount==1)));
        uint8_t raw[3];memcpy(raw,value->raw,sizeof(raw));
        if(changed&&!strcmp(value->name,"fc_framebuffer_fetch")){
            assert(value->dataType==MTLDataTypeBool&&raw[0]==1);raw[0]=0;changedOne=YES;
        }
        [result setConstantValue:raw type:value->dataType withName:[NSString stringWithUTF8String:value->name]];
    }
    assert(!changed||changedOne);return result;
}
/* The 602 vertex program is a separate real specialization. Test the four
 * exact typed values independently, including extra indexed/named entries. */
static MTLFunctionConstantValues *vertexConstants(uint32_t profileID,
    int changedIndex,BOOL extraIndexed,BOOL extraNamed)
{
    size_t count=0;
    const A5MaliCompiledFunctionConstant *values=
        A5MaliCompiledVertexConstantsForProfile(profileID,&count);
    assert(profileID==602&&values&&count==4);
    MTLFunctionConstantValues *result=[MTLFunctionConstantValues new];
    for(size_t i=0;i<count;++i){
        const A5MaliCompiledFunctionConstant *value=values+i;
        assert(value->name&&value->byteCount==1&&value->raw[0]==0&&
            (value->dataType==MTLDataTypeBool||value->dataType==MTLDataTypeUChar));
        uint8_t raw=(int)i==changedIndex?1:0;
        [result setConstantValue:&raw type:value->dataType
            withName:[NSString stringWithUTF8String:value->name]];
    }
    uint8_t one=1;
    if(extraIndexed)[result setConstantValue:&one type:MTLDataTypeUChar atIndex:63];
    if(extraNamed)[result setConstantValue:&one type:MTLDataTypeUChar withName:@"fc_unknown_extra"];
    return result;
}
static MTLRenderPipelineDescriptor *descriptor(A5MaliMetalLibrary *library,
    const A5MaliCompiledProfile *profile,BOOL changed,NSError **error)
{
    assert((profile->profileID==600||profile->profileID==601||profile->profileID==602)&&
        !strcmp(profile->vertexName,profile->profileID==602?"fixed_vert_lph_spc":"std_vert0_lph")&&
        !strcmp(profile->fragmentName,profile->profileID==600?"fixed_frag_lph_cpf":"fixed_frag_lph_cph"));
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    if(profile->profileID==602)
        d.vertexFunction=(id)[library newFunctionWithName:@"fixed_vert_lph_spc"
            constantValues:vertexConstants(profile->profileID,-1,NO,NO) error:error];
    else d.vertexFunction=(id)[library newFunctionWithName:@"std_vert0_lph"];
    if(!d.vertexFunction)return nil;
    d.fragmentFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:profile->fragmentName]
        constantValues:fragmentConstants(profile->profileID,changed) error:error];
    if(!d.fragmentFunction)return nil;
    assert(d.vertexFunction&&profile->attributeCount==4&&profile->layoutCount==1);
    d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
    for(unsigned i=0;i<profile->attributeCount;++i){const A5MaliCompiledVertexAttribute *a=profile->attributes+i;
        d.vertexDescriptor.attributes[a->index].format=a->format;
        d.vertexDescriptor.attributes[a->index].offset=a->offset;
        d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;
    }
    for(unsigned i=0;i<profile->layoutCount;++i){const A5MaliCompiledVertexLayout *layout=profile->layouts+i;
        assert(layout->index==1&&layout->stride==48);
        d.vertexDescriptor.layouts[layout->index].stride=layout->stride;
        d.vertexDescriptor.layouts[layout->index].stepFunction=layout->stepFunction;
        d.vertexDescriptor.layouts[layout->index].stepRate=layout->stepRate;
    }
    assert(profile->attachmentContractCount==(profile->profileID==602?2u:1u)&&profile->colorFormats[0]==MTLPixelFormatBGRA8Unorm);
    for(unsigned i=0;i<8;++i){
        const A5MaliCompiledAttachmentState *state=&profile->attachmentContracts[0].attachments[i];
        MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[i];
        assert(!state->blendEnabled&&state->writeMask==MTLColorWriteMaskAll);
        if(i)assert(!profile->colorFormats[i]);
        a.pixelFormat=profile->colorFormats[i];a.writeMask=state->writeMask;
        a.blendingEnabled=state->blendEnabled;
        a.rgbBlendOperation=state->rgbOperation;a.alphaBlendOperation=state->alphaOperation;
        a.sourceRGBBlendFactor=state->sourceRGB;a.destinationRGBBlendFactor=state->destinationRGB;
        a.sourceAlphaBlendFactor=state->sourceAlpha;a.destinationAlphaBlendFactor=state->destinationAlpha;
    }
    return d;
}
static void verifyVertex602Factory(A5MaliMetalLibrary *library,State *state)
{
    NSString *name=@"fixed_vert_lph_spc";
    NSError *error=nil;
    assert(![library newFunctionWithName:name]); /* Four constants are mandatory. */
    assert([library newFunctionWithName:name
        constantValues:vertexConstants(602,-1,NO,NO) error:&error]&&!error);
    MTLFunctionDescriptor *d=[MTLFunctionDescriptor new];d.name=name;
    d.constantValues=vertexConstants(602,-1,NO,NO);
    assert([library newFunctionWithDescriptor:d error:&error]&&!error);
    for(int i=0;i<4;++i){
        error=nil;
        MTLFunctionConstantValues *wrong=vertexConstants(602,i,NO,NO);
        A5MaliMetalFunction *other=[library newFunctionWithName:name constantValues:wrong error:&error];
        size_t nc=0;const A5MaliCompiledFunctionConstant *vc=A5MaliCompiledVertexConstantsForProfile(602,&nc);
        BOOL sibling=A5MaliCompiledProfileForID(603)&&!strcmp(vc[i].name,"fc_texcoord_count0");
        if(sibling)assert(other&&!error);else assert(!other&&error);
        d.constantValues=wrong;error=nil;other=[library newFunctionWithDescriptor:d error:&error];
        if(sibling)assert(other&&!error);else assert(!other&&error);
    }
    for(int kind=0;kind<2;++kind){
        error=nil;
        MTLFunctionConstantValues *wrong=vertexConstants(602,-1,kind==0,kind==1);
        assert(![library newFunctionWithName:name constantValues:wrong error:&error]&&error);
    }
    assert(!state->queries&&!state->submits);
}
static A5MaliMetalBuffer *encode(A5MaliRestrictedDevice *device,A5MaliReadSurfCandidate *pipeline,
    A5MaliMetalTexture *destination,State *s)
{
    A5MaliMetalBuffer *command=[[device newCommandQueue]commandBuffer];assert(command);
    command.protectionOptions=0;
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=(id)destination;
    pass.colorAttachments[0].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    A5MaliMetalRenderEncoder *encoder=[command renderCommandEncoderWithDescriptor:pass];assert(encoder);
    [encoder setViewport:(MTLViewport){0,0,32,32,0,1}];
    [encoder setRenderPipelineState:pipeline];
    A5MaliPrivateBuffer *vertices=[device newBufferWithLength:sizeof(s->vertices) options:MTLResourceStorageModeShared];
    assert(vertices&&vertices.contents);memset(vertices.contents,0xcc,sizeof(s->vertices));
    [encoder setVertexBuffer:vertices offset:0 atIndex:1];
    float inlineMatrix[16];memcpy(inlineMatrix,s->matrix,sizeof(inlineMatrix));
    [encoder setVertexBytes:inlineMatrix length:sizeof(inlineMatrix) atIndex:2];
    memset(inlineMatrix,0xdd,sizeof(inlineMatrix)); /* setBytes must retain its own exact copy */
    /* The compiled profile has no surviving FSBuffer1 read. Do not fabricate
     * one solely to satisfy a descriptor shape from an unrelated profile. */
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    memcpy(vertices.contents,s->vertices,sizeof(s->vertices)); /* shared buffer captured at commit */
    return command;
}
static int run(uint32_t profileID,BOOL blend)
{
    State s={0};
    @autoreleasepool{
        s.profile=A5MaliCompiledProfileForID(profileID);assert(s.profile);
        const float xy[4][2]={{0,0},{32,0},{0,32},{32,32}};
        for(unsigned i=0;i<4;++i){
            s.vertices[i].position[0]=xy[i][0];s.vertices[i].position[1]=xy[i][1];
            s.vertices[i].position[3]=1;
            s.vertices[i].color[0]=0x3400;s.vertices[i].color[1]=0x3800;
            s.vertices[i].color[2]=0x3a00;s.vertices[i].color[3]=0x3c00;
        }
        s.matrix[0]=s.matrix[5]=2.0f/32;s.matrix[10]=s.matrix[15]=1;
        s.matrix[12]=s.matrix[13]=-1;
        A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport
            context:&s commandCapabilities:63 operationCapabilities:127|(1u<<16)|(1u<<17)];
        const char *path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
        NSError *error=nil;
        A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:
            [NSString stringWithUTF8String:path]]error:&error];assert(library&&!error);
        if(profileID==602)verifyVertex602Factory(library,&s);
        MTLRenderPipelineDescriptor *d=descriptor(library,s.profile,NO,&error);assert(d&&!error);
        if(blend){
            assert(profileID==602);
            MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[0];
            a.blendingEnabled=YES;a.destinationRGBBlendFactor=a.destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
            /* Reject superficially similar straight-alpha, additive, alpha-only,
             * reverse-subtract and unattached-target states before transport. */
            for(unsigned fault=0;fault<6;++fault){
                MTLRenderPipelineDescriptor *bad=[d copy];
                if(fault==0)bad.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;
                if(fault==1)bad.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOne;
                if(fault==2)bad.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorZero;
                if(fault==3)bad.colorAttachments[0].rgbBlendOperation=MTLBlendOperationReverseSubtract;
                if(fault==4)bad.colorAttachments[0].writeMask=MTLColorWriteMaskAlpha;
                if(fault==5)bad.colorAttachments[1].blendingEnabled=YES;
                error=nil;assert(![device newRenderPipelineStateWithDescriptor:bad error:&error]&&error);
            }
            error=nil;
        }
        A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];
        assert(pipeline.sourceOver==blend);
        assert(pipeline&&!error&&!s.queries&&!s.submits);
        A5MaliMetalTexture *target=[device hostTestTextureWithResource:
            (A5MaliResource){UINT64_C(0x100000001),32,32,128,A5MaliRead|A5MaliWrite}];assert(target);
        A5MaliMetalBuffer *command=encode(device,pipeline,target,&s);
        assert(!s.queries&&!s.submits);
        [command commit];[command waitUntilCompleted];
        assert(command.status==MTLCommandBufferStatusCompleted&&!command.error&&s.queries==1&&s.submits==1);
        assert(command.privateBuffer.completedFence.tilerFence==1200&&
            command.privateBuffer.completedFence.fragmentFence==1201);
        error=nil;
        assert(!descriptor(library,s.profile,YES,&error)&&error);
        assert(s.queries==1&&s.submits==1); /* Changed constants are rejected before transport. */
        s.failSubmit=YES;command=encode(device,pipeline,target,&s);
        [command commit];[command waitUntilCompleted];
        assert(command.status==MTLCommandBufferStatusError&&command.error.code==kIOReturnTimeout);
        assert(s.queries==2&&s.submits==2&&!command.privateBuffer.completedFence.fragmentFence);
        assert(!A5MaliResourceIsComplete(target)); /* Failed DMA storage remains quarantined. */
    }
    assert(s.releases==0); /* Timeout pages retained, matching kernel poison policy. */
    printf("native generic%u blend%u: exact fragment specialization, authenticated native pair, original packing0, CPU snapshots, RT0-only query/submit, constant rejection and terminal/error fences passed (mock transport; no GPU pixels claimed)\n",profileID,blend);
    return 0;
}

int main(void) { assert(!run(600,NO));assert(!run(601,NO));assert(!run(602,NO));assert(!run(602,YES));puts("generic CPF, CPH and specialized-vertex native wrapper paths passed; GPU pixels unverified");return 0; }
