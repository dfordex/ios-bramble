/* SPDX-License-Identifier: MIT
 * Real Metal wrappers, authenticated602 shaders and released v4 emitter.
 * Kernel transport is mocked; descriptor/fence evidence is not GPU pixels.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliNative.h"
#include "../a5xelte-air-translation/families/runtime_encode.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

@interface A5MaliMetalBuffer (Indexed602FenceTest)
- (A5MaliCommandBuffer *)privateBuffer;
@end
typedef struct {
    float position[4],texcoord0[2],texcoord1[2];
    uint16_t color[4];uint8_t padding[8];
} Vertex;
_Static_assert(sizeof(Vertex)==48,"stock packing0");
typedef struct {
    unsigned queries,submits,vertexCount,indexCount,indexSize;
    MTLPrimitiveType primitive;
    BOOL failSubmit;
    BOOL failPrivateRead,privateAllocated[4];
    unsigned privateCreates,privateReads,privateWrites,privateReleases;
    uint8_t privateBytes[4][8192];
    Vertex vertices[A5RuntimeMiscMaxVertices];
    float matrix[16];
    uint8_t indices[A5RuntimeMaxIndices*4];
    const A5MaliCompiledProfile *profile;
} State;
typedef struct {A5MaliHeader h;uint32_t bytes,usage;} Create;
typedef struct {A5MaliHeader h;uint64_t handle;uint32_t bytes,usage;} Created;
typedef struct {A5MaliHeader h;uint64_t handle;} Release;
typedef struct {A5MaliHeader h;uint64_t handle;uint32_t offset,length;uint8_t bytes[256];} Transfer;
typedef struct {A5MaliHeader h;uint32_t length,reserved;uint8_t bytes[256];} Read;
_Static_assert(sizeof(Create)==24&&sizeof(Created)==32&&sizeof(Transfer)==288&&sizeof(Read)==280,"actual private transfer ABI");
static uint32_t u32(const uint8_t *p){uint32_t n;memcpy(&n,p,4);return n;}
static uint64_t u64(const uint8_t *p){uint64_t n;memcpy(&n,p,8);return n;}
static BOOL contains(const uint8_t *p,size_t count,const void *value,size_t bytes)
{for(size_t i=0;i+bytes<=count;++i)if(!memcmp(p+i,value,bytes))return YES;return NO;}
static kern_return_t transport(void *context,uint32_t selector,const void *input,
    size_t inputBytes,void *output,size_t *outputBytes)
{
    State *s=context;
    if(selector==A5MaliRelease||selector==A5MaliUnmap)return KERN_SUCCESS;
    if(selector==8){
        const Create *q=input;assert(inputBytes==sizeof(*q)&&*outputBytes==sizeof(Created));
        assert(q->h.version==1&&q->h.size==sizeof(*q)&&q->usage==3&&q->bytes<=8192);
        unsigned slot=0;while(slot<4&&s->privateAllocated[slot])++slot;assert(slot<4);
        s->privateAllocated[slot]=YES;memset(s->privateBytes[slot],0,8192);++s->privateCreates;
        Created done={.h={1,sizeof(done),0,0},.handle=UINT64_C(0x100000101)+slot,.bytes=q->bytes,.usage=q->usage};
        memcpy(output,&done,sizeof(done));*outputBytes=sizeof(done);return KERN_SUCCESS;
    }
    if(selector==9){
        const Release *q=input;assert(inputBytes==sizeof(*q));
        unsigned slot=(unsigned)(q->handle-UINT64_C(0x100000101));assert(slot<4&&s->privateAllocated[slot]);
        s->privateAllocated[slot]=NO;++s->privateReleases;return KERN_SUCCESS;
    }
    if(selector==14||selector==15){
        const Transfer *q=input;assert(inputBytes==sizeof(*q)&&q->h.version==1&&q->h.size==sizeof(*q));
        unsigned slot=(unsigned)(q->handle-UINT64_C(0x100000101));assert(slot<4&&s->privateAllocated[slot]);
        assert(q->length&&q->length<=256&&q->offset<=8192&&q->length<=8192-q->offset);
        if(selector==14){++s->privateWrites;memcpy(s->privateBytes[slot]+q->offset,q->bytes,q->length);return KERN_SUCCESS;}
        ++s->privateReads;if(s->failPrivateRead)return kIOReturnError;
        assert(*outputBytes==sizeof(Read));Read done={.h={1,sizeof(done),0,0},.length=q->length};
        memcpy(done.bytes,s->privateBytes[slot]+q->offset,q->length);
        memcpy(output,&done,sizeof(done));*outputBytes=sizeof(done);return KERN_SUCCESS;
    }
    if(selector==A5NativeQuerySelector){
        const A5NativeQueryRequest *q=input;
        assert(inputBytes==sizeof(*q)&&*outputBytes==sizeof(A5NativeQueryResult));
        assert(q->surfaces[0]==UINT64_C(0x100000001));
        for(unsigned i=0;i<A5NativeSlots;++i){assert(!q->buffers[i]);if(i)assert(!q->surfaces[i]);}
        A5NativeQueryResult mapped={.header={1,sizeof(mapped),0,0},
            .jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=93};
        mapped.surfaces[0]=(A5NativeSpan){q->surfaces[0],UINT64_C(0x10000000),4096,
            32,32,128,UINT32_C(0x42475241),A5MaliRead|A5MaliWrite};
        memcpy(output,&mapped,sizeof(mapped));*outputBytes=sizeof(mapped);++s->queries;return KERN_SUCCESS;
    }
    assert(selector==A5NativeSubmitSelector);
    const A5NativeSubmitRequest *q=input;
    assert(inputBytes==sizeof(*q)+A5NativeJobBytes&&q->profileID==602&&q->mappingEpoch==93);
    assert(q->jobBytes==A5NativeJobBytes&&q->vertexOffset==0&&q->tilerOffset==0x100&&q->fragmentOffset==0x200);
    assert(q->readSurfaces==1&&q->writeSurfaces==1&&q->readBuffers==0);
    for(unsigned i=0;i<A5NativeSlots;++i)assert(!q->buffers[i]);
    const uint8_t *jobs=(const uint8_t *)input+sizeof(*q);
    float sy,oy;memcpy(&sy,jobs+0x1000+516,4);memcpy(&oy,jobs+0x1000+532,4);
    assert(sy+oy==0&&-sy+oy==32); /* Metal NDC +Y maps to top */
    const A5MaliCompiledPass *pass=s->profile->passes;
    assert(!memcmp(jobs+0x6000,pass->vertex.bytes,pass->vertex.byteCount));
    assert(!memcmp(jobs+0x8000,pass->fragment.bytes,pass->fragment.byteCount));
    /* Independently decode released Mesa26.2.4 v4 PRIMITIVE fields. The
     * 24-byte descriptor is at0x128: index_type bits8..10, zero baseVertex
     * word1, count-minus-one word3, actual indices GPUVA words4/5. */
    uint32_t primitive=u32(jobs+0x128);
    assert(((primitive>>8)&7)==(!s->indexCount?0u:s->indexSize==2?2u:3u));
    unsigned mode=s->primitive==MTLPrimitiveTypeLine?2:s->primitive==MTLPrimitiveTypeLineStrip?4:
        s->primitive==MTLPrimitiveTypeTriangle?8:10;
    assert((primitive&0xff)==mode);
    assert(((u32(jobs+0x140)>>8)&1)==(s->primitive==MTLPrimitiveTypeLine||s->primitive==MTLPrimitiveTypeLineStrip));
    assert(u32(jobs+0x12c)==0&&u32(jobs+0x130)==0);
    assert((uint64_t)u32(jobs+0x134)+1==(s->indexCount?s->indexCount:s->vertexCount));
    uint64_t address=u64(jobs+0x138);
    if(s->indexCount){
        assert(address>=A5NativeJobVA+0x20000&&address<A5NativeJobVA+0x30000&&!(address&63));
        size_t at=(size_t)(address-A5NativeJobVA),bytes=s->indexCount*s->indexSize;
        assert(bytes<=0x30000-at&&!memcmp(jobs+at,s->indices,bytes));
    }else assert(!address);
    assert(u32(jobs+0x20)==s->vertexCount-1&&u32(jobs+0x120)==s->vertexCount-1);
    assert(contains(jobs+0x20000,0x10000,s->vertices,s->vertexCount*sizeof(Vertex)));
    assert(contains(jobs+0x20000,0x10000,s->matrix,sizeof(s->matrix)));
    assert(A5NativeCheckJobChain(jobs,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,NO)==1);
    ++s->submits;if(s->failSubmit)return kIOReturnTimeout;
    A5NativeSubmitResult done={.header={1,sizeof(done),0,0},.tilerFence=1600+s->submits*2,
        .fragmentFence=1601+s->submits*2};
    assert(*outputBytes==sizeof(done));memcpy(output,&done,sizeof(done));*outputBytes=sizeof(done);return KERN_SUCCESS;
}
static MTLFunctionConstantValues *constants(BOOL vertex)
{
    size_t count=0;const A5MaliCompiledFunctionConstant *c=vertex?
        A5MaliCompiledVertexConstantsForProfile(602,&count):A5MaliCompiledConstantsForProfile(602,&count);
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
typedef NS_ENUM(unsigned,Fault){Good,WrongType,Unaligned,OutOfRange,TooLargeIndex,
    VertexOutOfRange,TooManyIndices,WrongDevice,ExtraInstances,BaseVertex,BaseInstance,PrivateGood,PrivateReadFailure};
static A5MaliMetalBuffer *encode(A5MaliRestrictedDevice *device,A5MaliRestrictedDevice *other,
    A5MaliReadSurfCandidate *p,A5MaliMetalTexture *target,State *s,MTLIndexType type,
    NSUInteger indexOffset,unsigned overload,Fault fault)
{
    A5MaliMetalBuffer *b=[[device newCommandQueue]commandBuffer];assert(b);
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=(id)target;pass.colorAttachments[0].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    A5MaliMetalRenderEncoder *r=[b renderCommandEncoderWithDescriptor:pass];assert(r);
    [r setRenderPipelineState:p];[r setViewport:(MTLViewport){0,0,32,32,0,1}];
    A5MaliPrivateBuffer *vb=[device newBufferWithLength:s->vertexCount*sizeof(Vertex) options:MTLResourceStorageModeShared];
    assert(vb&&vb.contents);memset(vb.contents,0xee,vb.length);[r setVertexBuffer:vb offset:0 atIndex:1];
    float matrix[16];memcpy(matrix,s->matrix,sizeof(matrix));[r setVertexBytes:matrix length:sizeof(matrix) atIndex:2];
    memset(matrix,0xff,sizeof(matrix));
    NSUInteger count=fault==TooManyIndices?A5RuntimeMaxIndices+3:s->indexCount;
    size_t indexBytes=count*s->indexSize;
    A5MaliRestrictedDevice *indexDevice=fault==WrongDevice?other:device;
    BOOL privateIndex=fault==PrivateGood||fault==PrivateReadFailure;
    A5MaliPrivateBuffer *indices=[indexDevice newBufferWithLength:indexOffset+indexBytes+32
        options:privateIndex?MTLResourceStorageModePrivate:MTLResourceStorageModeShared];
    assert(indices);
    if(privateIndex){
        assert(!indices.contents&&indices.privateKernelHandle);
        NSMutableData *zero=[NSMutableData dataWithLength:indices.length];
        assert([indices uploadBytes:zero.bytes offset:0 length:zero.length]==KERN_SUCCESS);
    }else{assert(indices.contents);memset(indices.contents,0,indices.length);}
    __weak A5MaliPrivateBuffer *heldIndex=indices;
    NSUInteger offset=fault==Unaligned?indexOffset+1:fault==OutOfRange?indices.length-1:indexOffset;
    MTLIndexType actual=fault==WrongType?(MTLIndexType)99:type;
    NSUInteger instances=fault==ExtraInstances?2:1;
    if(overload==0)[r drawIndexedPrimitives:s->primitive indexCount:count indexType:actual indexBuffer:indices indexBufferOffset:offset];
    else if(overload==1)[r drawIndexedPrimitives:s->primitive indexCount:count indexType:actual indexBuffer:indices indexBufferOffset:offset instanceCount:instances];
    else [r drawIndexedPrimitives:s->primitive indexCount:count indexType:actual indexBuffer:indices indexBufferOffset:offset
        instanceCount:instances baseVertex:fault==BaseVertex?1:0 baseInstance:fault==BaseInstance?1:0];
    A5MaliPrivateBuffer *replacement=[device newBufferWithLength:vb.length options:MTLResourceStorageModeShared];
    assert(replacement);memset(replacement.contents,0x99,replacement.length);
    [r setVertexBuffer:replacement offset:0 atIndex:1];[r endEncoding];
    /* Metal Shared index/vertex data are read at commit, not at draw encoding.
     * Original buffers and bindings must survive subsequent rebind/end. */
    memcpy(vb.contents,s->vertices,vb.length);
    if(privateIndex)assert([indices uploadBytes:s->indices offset:indexOffset length:indexBytes]==KERN_SUCCESS);
    else if(fault!=TooManyIndices)memcpy((uint8_t *)indices.contents+indexOffset,s->indices,indexBytes);
    if(fault==TooLargeIndex||fault==VertexOutOfRange){uint32_t bad=fault==TooLargeIndex?A5RuntimeMiscMaxVertices:s->vertexCount;
        memcpy((uint8_t *)indices.contents+indexOffset,&bad,s->indexSize);}
    indices=nil;
    if(fault==Good||privateIndex)assert(heldIndex); /* deferred snapshot owns the actual index object */
    assert(!b.privateBuffer.completedFence.tilerFence&&!b.privateBuffer.completedFence.fragmentFence);
    return b;
}
static void setIndices(State *s,const uint32_t *indices,unsigned count,unsigned size)
{
    s->indexCount=count;s->indexSize=size;memset(s->indices,0,sizeof(s->indices));
    for(unsigned i=0;i<count;++i)memcpy(s->indices+i*size,indices+i,size);
}
static A5MaliMetalBuffer *nonindexed(A5MaliRestrictedDevice *device,A5MaliReadSurfCandidate *pipeline,
    A5MaliMetalTexture *target,State *s)
{
    A5MaliMetalBuffer *cb=[[device newCommandQueue]commandBuffer];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=(id)target;pass.colorAttachments[0].loadAction=MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    A5MaliMetalRenderEncoder *encoder=[cb renderCommandEncoderWithDescriptor:pass];assert(encoder);
    [encoder setRenderPipelineState:pipeline];
    A5MaliPrivateBuffer *vertices=[device newBufferWithBytes:s->vertices
        length:s->vertexCount*sizeof(Vertex) options:MTLResourceStorageModeShared];assert(vertices);
    [encoder setVertexBuffer:vertices offset:0 atIndex:1];
    [encoder setVertexBytes:s->matrix length:sizeof(s->matrix) atIndex:2];
    [encoder drawPrimitives:s->primitive vertexStart:0 vertexCount:s->vertexCount];
    [encoder endEncoding];return cb;
}
int main(void)
{
    @autoreleasepool {
        State s={0};s.profile=A5MaliCompiledProfileForID(602);assert(s.profile);
        for(unsigned i=0;i<A5RuntimeMiscMaxVertices;++i){Vertex *v=&s.vertices[i];
            v->position[0]=(float)(i%32)+.125f;v->position[1]=(float)(i/32)+.375f;v->position[3]=1;
            v->color[0]=0x3400;v->color[1]=0x3800;v->color[2]=(uint16_t)(0x3800+i);v->color[3]=0x3c00;
            memset(v->padding,(int)(i+17),sizeof(v->padding));
        }
        s.matrix[0]=1.25f;s.matrix[5]=1.75f;s.matrix[10]=2;s.matrix[15]=1;s.matrix[12]=-.75f;s.matrix[13]=.25f;
        A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&s
            commandCapabilities:63 operationCapabilities:127|(1u<<7)|(1u<<8)|(1u<<13)|(1u<<14)|(1u<<16)|(1u<<17)];
        A5MaliRestrictedDevice *other=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&s
            commandCapabilities:63 operationCapabilities:127|(1u<<16)|(1u<<17)];
        A5MaliReadSurfCandidate *p=pipeline(device,&s);
        A5MaliMetalTexture *target=[device hostTestTextureWithResource:
            (A5MaliResource){UINT64_C(0x100000001),32,32,128,A5MaliRead|A5MaliWrite}];assert(target);
        const uint32_t triangles[6]={4,1,5,5,1,2},strip[4]={3,0,5,1};
        for(unsigned i=0;i<3;++i){s.vertexCount=6;s.primitive=i==1?MTLPrimitiveTypeTriangleStrip:MTLPrimitiveTypeTriangle;
            setIndices(&s,i==1?strip:triangles,i==1?4:6,i==1?4:2);
            unsigned before=s.submits;A5MaliMetalBuffer *b=encode(device,other,p,target,&s,
                i==1?MTLIndexTypeUInt32:MTLIndexTypeUInt16,i==1?12:6,i,Good);
            assert(s.submits==before);[b commit];[b waitUntilCompleted];
            assert(b.status==MTLCommandBufferStatusCompleted&&!b.error&&s.submits==before+1);
            assert(b.privateBuffer.completedFence.tilerFence==1600+s.submits*2&&
                b.privateBuffer.completedFence.fragmentFence==1601+s.submits*2);
        }
        /* Exercise the real maximum vertex and index-count boundaries too. */
        const uint32_t upper[6]={255,1,2,2,1,254};s.vertexCount=256;s.primitive=MTLPrimitiveTypeTriangle;
        setIndices(&s,upper,6,2);A5MaliMetalBuffer *b=encode(device,other,p,target,&s,MTLIndexTypeUInt16,6,0,Good);
        [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusCompleted);
        uint32_t many[A5RuntimeMaxIndices];for(unsigned i=0;i<A5RuntimeMaxIndices;++i)many[i]=(i*5)%6;
        s.vertexCount=6;setIndices(&s,many,A5RuntimeMaxIndices,4);
        b=encode(device,other,p,target,&s,MTLIndexTypeUInt32,12,1,Good);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusCompleted);
        const unsigned lineCounts[]={2,164,176,186,196,256,312,330,1024};
        for(unsigned i=0;i<sizeof(lineCounts)/sizeof(lineCounts[0]);i++){
            s.vertexCount=lineCounts[i];s.primitive=MTLPrimitiveTypeLine;s.indexCount=s.indexSize=0;
            unsigned previous=s.submits;b=nonindexed(device,p,target,&s);[b commit];[b waitUntilCompleted];
            assert(b.status==MTLCommandBufferStatusCompleted&&s.submits==previous+1);
            uint32_t line[]={s.vertexCount-1,0};setIndices(&s,line,2,i%2?4:2);
            previous=s.submits;b=encode(device,other,p,target,&s,i%2?MTLIndexTypeUInt32:MTLIndexTypeUInt16,
                i%2?12:6,0,Good);[b commit];[b waitUntilCompleted];
            assert(b.status==MTLCommandBufferStatusCompleted&&s.submits==previous+1);
        }
        s.vertexCount=331;s.primitive=MTLPrimitiveTypeLineStrip;s.indexCount=s.indexSize=0;
        b=nonindexed(device,p,target,&s);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusCompleted);
        s.vertexCount=165;s.primitive=MTLPrimitiveTypeLine;
        unsigned beforeInvalid=s.submits;b=nonindexed(device,p,target,&s);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&s.submits==beforeInvalid);
        for(Fault f=WrongType;f<=BaseInstance;++f){
            s.vertexCount=f==TooLargeIndex?A5RuntimeMiscMaxVertices:6;s.primitive=MTLPrimitiveTypeTriangle;setIndices(&s,triangles,6,2);
            unsigned before=s.submits,overload=(f==BaseVertex||f==BaseInstance)?2:f==ExtraInstances?1:0;
            b=encode(device,other,p,target,&s,MTLIndexTypeUInt16,6,overload,f);[b commit];[b waitUntilCompleted];
            assert(b.status==MTLCommandBufferStatusError&&b.error&&s.submits==before);
            assert(!b.privateBuffer.completedFence.tilerFence&&!b.privateBuffer.completedFence.fragmentFence);
        }
        /* UInt32 alignment and terminal transport failure are separate from
         * UInt16 validation and cannot fabricate a completion fence. */
        setIndices(&s,triangles,6,4);s.vertexCount=6;
        unsigned before=s.submits;b=encode(device,other,p,target,&s,MTLIndexTypeUInt32,12,0,Unaligned);
        [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusError&&s.submits==before);
        for(unsigned attempt=0;attempt<2;++attempt){
            unsigned queries=s.queries,submits=s.submits,reads=s.privateReads;
            b=encode(device,other,p,target,&s,MTLIndexTypeUInt32,12,0,attempt?PrivateReadFailure:PrivateGood);
            assert(s.privateCreates==attempt+1&&s.privateWrites>=2*(attempt+1));
            assert(s.privateReads==reads); /* no read occurs while encoding */
            s.failPrivateRead=attempt!=0;
            dispatch_semaphore_t done=dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                [b commit];[b waitUntilCompleted];dispatch_semaphore_signal(done);
            });
            /* A recursive connection NSLock in the private read path would
             * deadlock here, rather than pass on a synthetic fence. */
            assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
            assert(s.privateReads==reads+1);
            if(attempt){
                assert(b.status==MTLCommandBufferStatusError&&b.error.code==kIOReturnError);
                assert(s.queries==queries&&s.submits==submits);
                assert(!b.privateBuffer.completedFence.tilerFence&&!b.privateBuffer.completedFence.fragmentFence);
            }else{
                assert(b.status==MTLCommandBufferStatusCompleted&&s.queries==queries+1&&s.submits==submits+1);
                assert(b.privateBuffer.completedFence.fragmentFence);
            }
        }
        /* A timed-out GPU job quarantines the destination; test it last. */
        before=s.submits;
        s.failSubmit=YES;b=encode(device,other,p,target,&s,MTLIndexTypeUInt32,12,0,Good);[b commit];[b waitUntilCompleted];
        assert(b.status==MTLCommandBufferStatusError&&b.error.code==kIOReturnTimeout&&s.submits==before+1);
        assert(!b.privateBuffer.completedFence.fragmentFence);
        s.failSubmit=NO;
        puts("indexed602 Metal wrappers: u16/u32 ordered native indices, actual line/line-strip topology, 2..1024 vertices, late commit snapshots/rebind retention, bounds/device rejection and terminal fences PASS (mock transport; no GPU pixels)");
    }
    return 0;
}
