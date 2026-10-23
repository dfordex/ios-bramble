/* SPDX-License-Identifier: MIT
 * Actual603 native shaders and Metal API wiring. IOKit transport is mocked;
 * this proves descriptors/snapshots/fences, not GPU pixels.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
#import "A5MaliNative.h"
#import "A5MaliCompiledRegistry.h"
#ifndef A5_TEST_TEXTURED_PROFILE
#define A5_TEST_TEXTURED_PROFILE 603
#endif
#if A5_TEST_TEXTURED_PROFILE == 603
#define A5_TEST_FRAGMENT_BYTES 880
#elif A5_TEST_TEXTURED_PROFILE == 604
#define A5_TEST_FRAGMENT_BYTES 1120
#elif A5_TEST_TEXTURED_PROFILE == 605
#define A5_TEST_FRAGMENT_BYTES 896
#else
#error "expected a real textured603/604/605 profile"
#endif
#include <assert.h>
#include <stdlib.h>
#include <string.h>
@interface A5MaliMetalBuffer (Textured603FenceTest)
- (A5MaliCommandBuffer *)privateBuffer;
@end
typedef struct {float position[4],uv[2],unused[2];uint16_t color[4];uint8_t pad[8];} Vertex;
_Static_assert(sizeof(Vertex)==48,"actual stock packing0");
/* A logical subresource over a larger physical backing, exercising actual
 * level offset addition rather than assuming every texture starts at VA. */
@interface SourceTexture:A5MaliMetalTexture
@property(nonatomic,strong)A5MaliMetalTexture *backing;
@property(nonatomic)BOOL wrongType;
@end
@implementation SourceTexture
- (A5MaliRestrictedDevice *)device{return self.backing.device;}
- (A5MaliSurface *)privateSurface{return self.backing.privateSurface;}
- (A5MaliSurface *)surfaceForLevel:(NSUInteger)level memorylessLease:(A5MaliTexturePassBacking *)lease
{return level==0&&!lease?self.backing.privateSurface:nil;}
- (A5MaliTexturePassBacking *)passBacking{return nil;}
- (NSUInteger)width{return 32;}
- (NSUInteger)height{return 16;}
- (MTLPixelFormat)pixelFormat{return MTLPixelFormatBGRA8Unorm;}
- (MTLTextureType)textureType{return self.wrongType?MTLTextureType1D:MTLTextureType2D;}
- (NSUInteger)mipmapLevelCount{return 1;}
- (NSUInteger)sampleCount{return 1;}
- (NSUInteger)arrayLength{return 1;}
- (MTLTextureUsage)usage{return MTLTextureUsageShaderRead;}
- (MTLStorageMode)storageMode{return MTLStorageModeShared;}
- (BOOL)getLevelLayout:(A5MaliTextureLevelLayout *)l level:(NSUInteger)level
{if(level)return NO;*l=(A5MaliTextureLevelLayout){32,16,256,128,4096};return YES;}
@end
/* Deliberately malformed externally supplied state must fail draw validation,
 * even if a foreign class bypasses the public sampler factory. */
@interface BadSampler:A5MaliSamplerState
@property(nonatomic,strong)A5MaliRestrictedDevice *owner;
@end
@implementation BadSampler
- (A5MaliRestrictedDevice *)device{return self.owner;}
- (MTLSamplerDescriptor *)descriptor{MTLSamplerDescriptor*d=[MTLSamplerDescriptor new];d.sAddressMode=MTLSamplerAddressModeRepeat;return d;}
@end
typedef struct {unsigned queries,submits,indexSize;BOOL linear,failSubmit;Vertex vertices[6];
 float matrix[16],transform[4],lod[2];uint32_t indices[6];const A5MaliCompiledProfile *profile;}State;
static uint32_t u32(const uint8_t*p){uint32_t n;memcpy(&n,p,4);return n;}
static uint64_t u64(const uint8_t*p){uint64_t n;memcpy(&n,p,8);return n;}
static BOOL contains(const uint8_t*p,size_t n,const void*v,size_t bytes)
{for(size_t i=0;i+bytes<=n;++i)if(!memcmp(p+i,v,bytes))return YES;return NO;}
static kern_return_t transport(void*context,uint32_t selector,const void*input,size_t bytes,void*output,size_t*outBytes)
{
 State*s=context;if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==A5NativeQuerySelector){const A5NativeQueryRequest*q=input;
  assert(bytes==sizeof(*q)&&*outBytes==sizeof(A5NativeQueryResult));
  assert(q->surfaces[0]==0x100000001&&q->surfaces[1]==0x100000002);
  for(unsigned i=0;i<A5NativeSlots;++i){assert(!q->buffers[i]);if(i>1)assert(!q->surfaces[i]);}
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=107};
  r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,4096,32,32,128,0x42475241,3};
  r.surfaces[1]=(A5NativeSpan){q->surfaces[1],0x12000000,8192,64,32,256,0x42475241,1};
  memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->queries;return KERN_SUCCESS;
 }
 assert(selector==A5NativeSubmitSelector);const A5NativeSubmitRequest*q=input;
 assert(bytes==sizeof(*q)+A5NativeJobBytes&&q->profileID==A5_TEST_TEXTURED_PROFILE&&q->mappingEpoch==107);
 assert(q->readSurfaces==3&&q->writeSurfaces==1&&!q->readBuffers);
 const uint8_t*j=(const uint8_t*)input+sizeof(*q);const A5MaliCompiledPass*p=s->profile->passes;
 assert(p->vertex.byteCount==2192&&p->fragment.byteCount==A5_TEST_FRAGMENT_BYTES);
 /* Nonzero origin and unequal dimensions distinguish a clip-space Y
  * correction from flipping texture UV or translating the whole image. */
 float sx,sy,ox,oy;
 memcpy(&sx,j+0x1000+512,4);memcpy(&sy,j+0x1000+516,4);
 memcpy(&ox,j+0x1000+528,4);memcpy(&oy,j+0x1000+532,4);
 assert(-sx+ox==3&&sx+ox==27);
 assert(sy+oy==5&&-sy+oy==25); /* NDC +Y top, -Y bottom */
 assert(!memcmp(j+0x6000,p->vertex.bytes,p->vertex.byteCount)&&!memcmp(j+0x8000,p->fragment.bytes,p->fragment.byteCount));
 assert(contains(j+0x20000,0x10000,s->vertices,sizeof(s->vertices)));
 assert(contains(j+0x20000,0x10000,s->matrix,sizeof(s->matrix)));
 assert(contains(j+0x20000,0x10000,s->transform,sizeof(s->transform)));
 assert(contains(j+0x20000,0x10000,s->lod,sizeof(s->lod)));
 /* Releasedv4 texture dimensions are minus-one halfwords. Surface pointer
  * includes actual logical level offset; row/surface strides remain physical. */
 assert(u32(j+0x600)==((16u-1)<<16|31u));
 assert(u64(j+0x620)==0x12000080&&u32(j+0x628)==256&&u32(j+0x62c)==4096);
 assert(u32(j+0x1400+352)==0&&u32(j+0x1400+356)==0&&u32(j+0x1400+360)==0);
 assert(u64(j+0x680)==A5NativeJobVA+0x600);
 /* SAMPLER: normalized and minify/magnify fields checked independently. */
 uint32_t sampler=u32(j+0x6a0);assert((sampler&3)==(s->linear?0u:3u));assert(sampler&(1u<<5));assert(u32(j+0x6a4)==0);
 if(s->indexSize){assert(((u32(j+0x128)>>8)&7)==(s->indexSize==2?2u:3u));
  assert(u32(j+0x134)==5);uint64_t a=u64(j+0x138);assert(a>=A5NativeJobVA+0x20000&&a<A5NativeJobVA+0x30000);
  for(unsigned i=0;i<6;++i){uint32_t v=0;memcpy(&v,j+(a-A5NativeJobVA)+i*s->indexSize,s->indexSize);assert(v==s->indices[i]);}
 }else{assert(((u32(j+0x128)>>8)&7)==0&&u32(j+0x134)==5);}
 assert(A5NativeCheckJobChain(j,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,NO)==1);
 ++s->submits;if(s->failSubmit)return kIOReturnTimeout;
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=1900+s->submits*2,.fragmentFence=1901+s->submits*2};
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;
}
static MTLFunctionConstantValues *constants(BOOL vertex)
{
    size_t count=0;const A5MaliCompiledFunctionConstant *c=vertex?
        A5MaliCompiledVertexConstantsForProfile(A5_TEST_TEXTURED_PROFILE,&count):A5MaliCompiledConstantsForProfile(A5_TEST_TEXTURED_PROFILE,&count);
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
typedef NS_ENUM(unsigned,Fault){Good,MissingSampler,MissingTexture,MissingUVTransform,WrongSamplerState,WrongSourceType,SourceAlias,WrongSourceDevice,ShortLOD};
static A5MaliMetalBuffer *encode(A5MaliRestrictedDevice*d,A5MaliRestrictedDevice*other,id p,
 A5MaliMetalTexture*target,SourceTexture*source,State*s,Fault fault)
{
 A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];
 MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];
 pass.colorAttachments[0].texture=(id)target;pass.colorAttachments[0].loadAction=MTLLoadActionLoad;
 pass.colorAttachments[0].storeAction=MTLStoreActionStore;
 A5MaliMetalRenderEncoder*r=[b renderCommandEncoderWithDescriptor:pass];assert(r);
 [r setRenderPipelineState:p];[r setViewport:(MTLViewport){3,5,24,20,0,1}];
 A5MaliPrivateBuffer*vb=[d newBufferWithLength:sizeof(s->vertices)+32 options:0];
 A5MaliPrivateBuffer*matrix=[d newBufferWithLength:80 options:0];
 A5MaliPrivateBuffer*uv=[d newBufferWithLength:32 options:0];
 A5MaliPrivateBuffer*lod=[d newBufferWithLength:24 options:0];
 assert(vb.contents&&matrix.contents&&uv.contents&&lod.contents);
 memset(vb.contents,0xee,vb.length);memset(matrix.contents,0xee,matrix.length);
 memset(uv.contents,0xee,uv.length);memset(lod.contents,0xee,lod.length);
 [r setVertexBuffer:vb offset:16 atIndex:1];[r setVertexBuffer:matrix offset:16 atIndex:2];
 if(fault!=MissingUVTransform)[r setVertexBuffer:uv offset:16 atIndex:3];
 if(fault==ShortLOD)[r setFragmentBytes:s->lod length:4 atIndex:2];
 else [r setFragmentBuffer:lod offset:16 atIndex:2];
 MTLSamplerDescriptor*sd=[MTLSamplerDescriptor new];
 sd.minFilter=s->linear?MTLSamplerMinMagFilterLinear:MTLSamplerMinMagFilterNearest;
 sd.magFilter=sd.minFilter;sd.mipFilter=MTLSamplerMipFilterLinear;
 sd.lodMinClamp=.25f;sd.lodMaxClamp=4;
 A5MaliSamplerState*sampler=[d newSamplerStateWithDescriptor:sd];assert(sampler);
 if(fault==WrongSamplerState){BadSampler*bad=[BadSampler new];bad.owner=d;sampler=bad;}
 if(fault!=MissingSampler)[r setFragmentSamplerState:sampler atIndex:0];
 sd.minFilter=!s->linear;sd.magFilter=!s->linear; /* originaldescriptor is not retained mutable */
 SourceTexture*actual=source;
 if(fault==WrongSourceDevice){actual=[SourceTexture new];actual.backing=[other hostTestTextureWithResource:
  (A5MaliResource){0x100000002,64,32,256,A5MaliRead}];}
 if(fault!=MissingTexture)[r setFragmentTexture:fault==SourceAlias?target:actual atIndex:3];
 source.wrongType=fault==WrongSourceType;
 A5MaliPrivateBuffer*indices=nil;
 if(s->indexSize){indices=[d newBufferWithLength:16+6*s->indexSize options:0];assert(indices.contents);
  memset(indices.contents,0,indices.length);
  [r drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6
   indexType:s->indexSize==2?MTLIndexTypeUInt16:MTLIndexTypeUInt32 indexBuffer:indices indexBufferOffset:16];
 }else [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
 /* All actual buffers are captured at commit; rebindings after draw must not
  * replace their identities. Sampler state is snapshotted at draw. */
 [r setVertexBuffer:uv offset:0 atIndex:1];[r setFragmentTexture:nil atIndex:3];
 [r setFragmentSamplerState:nil atIndex:0];[r endEncoding];
 memcpy((uint8_t*)vb.contents+16,s->vertices,sizeof(s->vertices));
 memcpy((uint8_t*)matrix.contents+16,s->matrix,sizeof(s->matrix));
 memcpy((uint8_t*)uv.contents+16,s->transform,sizeof(s->transform));
 memcpy((uint8_t*)lod.contents+16,s->lod,sizeof(s->lod));
 for(unsigned i=0;i<6&&indices;++i)memcpy((uint8_t*)indices.contents+16+i*s->indexSize,s->indices+i,s->indexSize);
 assert(!b.privateBuffer.completedFence.fragmentFence);return b;
}
int main(void)
{
 @autoreleasepool{
 State s={0};s.profile=A5MaliCompiledProfileForID(A5_TEST_TEXTURED_PROFILE);assert(s.profile);
 for(unsigned i=0;i<6;++i){s.vertices[i].position[0]=i+.25f;s.vertices[i].position[1]=i*.75f;
  s.vertices[i].position[3]=1;s.vertices[i].uv[0]=i*3+.5f;s.vertices[i].uv[1]=i+.125f;
  s.vertices[i].color[0]=0x3800;s.vertices[i].color[1]=0x3400;s.vertices[i].color[2]=0x3a00;s.vertices[i].color[3]=0x3c00;
  s.indices[i]=(uint32_t[]){4,1,5,5,1,2}[i];}
 s.matrix[0]=1.25f;s.matrix[5]=1.75f;s.matrix[10]=2;s.matrix[15]=1;s.matrix[12]=-.75f;
 s.transform[0]=.03125f;s.transform[1]=.0625f;s.transform[2]=.125f;s.transform[3]=.25f;
 s.lod[0]=.375f;s.lod[1]=.625f;
 A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&s commandCapabilities:63 operationCapabilities:0x7ffff];
 A5MaliRestrictedDevice*other=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&s commandCapabilities:63 operationCapabilities:0x7ffff];
 id p=pipeline(d,&s);assert(p);
 A5MaliMetalTexture*target=[d hostTestTextureWithResource:(A5MaliResource){0x100000001,32,32,128,3}];
 SourceTexture*source=[SourceTexture new];source.backing=[d hostTestTextureWithResource:(A5MaliResource){0x100000002,64,32,256,1}];
 for(unsigned i=0;i<3;++i){s.indexSize=i?i==1?2:4:0;s.linear=i!=0;unsigned before=s.submits;
  A5MaliMetalBuffer*b=encode(d,other,p,target,source,&s,Good);assert(s.submits==before);
  [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusCompleted&&!b.error&&s.submits==before+1);
  assert(b.privateBuffer.completedFence.tilerFence==1900+s.submits*2&&b.privateBuffer.completedFence.fragmentFence==1901+s.submits*2);
 }
 for(Fault f=MissingSampler;f<=ShortLOD;++f){s.indexSize=0;unsigned before=s.submits;
  A5MaliMetalBuffer*b=encode(d,other,p,target,source,&s,f);[b commit];[b waitUntilCompleted];
  assert(b.status==MTLCommandBufferStatusError&&b.error&&s.submits==before);
  assert(!b.privateBuffer.completedFence.tilerFence&&!b.privateBuffer.completedFence.fragmentFence);
 }
 source.wrongType=NO;s.failSubmit=YES;unsigned before=s.submits;
 A5MaliMetalBuffer*b=encode(d,other,p,target,source,&s,Good);[b commit];[b waitUntilCompleted];
 assert(b.status==MTLCommandBufferStatusError&&b.error.code==kIOReturnTimeout&&s.submits==before+1);
 assert(!b.privateBuffer.completedFence.tilerFence&&!b.privateBuffer.completedFence.fragmentFence);
 puts("textured603 Metal wrappers: actual native code, Texture3 subresource VA/dimensions, sampler snapshots, late VS/FS/indices buffers, indexed/nonindexed, strict rejection and genuine terminal fences PASS (mock transport; no GPU pixels)");
 }return 0;
}
