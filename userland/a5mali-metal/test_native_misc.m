/* SPDX-License-Identifier: MIT
 * Actual authenticated misc shaders + released v4 emitter. Mock IOKit only:
 * only the enabled native output pass, full large SSBO upload and fence-ordered cleanup.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

@interface A5MaliMetalTexture(MiscBacking)
- (A5MaliSurface *)privateSurface;
@end
@interface MiscTexture:A5MaliMetalTexture
@property(nonatomic,strong)A5MaliMetalTexture*backing;
@property(nonatomic)MTLPixelFormat format;
@end
@implementation MiscTexture
- (A5MaliRestrictedDevice*)device{return self.backing.device;}
- (A5MaliSurface*)privateSurface{return self.backing.privateSurface;}
- (NSUInteger)width{return self.backing.width;}
- (NSUInteger)height{return self.backing.height;}
- (MTLPixelFormat)pixelFormat{return self.format;}
- (MTLTextureUsage)usage{return MTLTextureUsageRenderTarget;}
- (IOSurfaceRef)iosurface{return NULL;}
@end
typedef struct{A5MaliHeader h;uint32_t bytes,usage;}Create;
typedef struct{A5MaliHeader h;uint64_t handle;uint32_t bytes,usage;}Created;
typedef struct{A5MaliHeader h;uint64_t handle;}BufferHandle;
typedef struct{
 unsigned creates,queries,submits,releases,bulkCalls;
 uint32_t allocation[2],uploaded[2];
 uint8_t *expected[2],*actual[2];
 uint32_t lengths[2];
 BOOL failSubmit;
 const A5MaliCompiledProfile *profile;
}State;
static kern_return_t wire(void *context,uint32_t selector,const void *input,size_t bytes,void *output,size_t *outBytes)
{
 State*s=context;
 if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==8){const Create*q=input;assert(bytes==sizeof(*q)&&s->creates<2&&q->usage==3);
  unsigned i=s->creates++;s->allocation[i]=q->bytes;
  Created r={{1,sizeof(r),0,0},UINT64_C(0x100000101)+i,q->bytes,q->usage};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5NativeBulkWriteSelector){const A5NativeBulkWriteRequest*q=input;
  unsigned i=(unsigned)(q->handle-UINT64_C(0x100000101));assert(i<2);
  assert(bytes==sizeof(*q)+q->length&&q->offset==s->uploaded[i]);
  assert(q->offset<=s->lengths[i]&&q->length<=s->lengths[i]-q->offset);
  memcpy(s->actual[i]+q->offset,(const uint8_t*)input+sizeof(*q),q->length);
  s->uploaded[i]+=q->length;++s->bulkCalls;assert(!output);return KERN_SUCCESS;}
 if(selector==9){const BufferHandle*q=input;unsigned i=(unsigned)(q->handle-UINT64_C(0x100000101));
  assert(i<2&&s->submits==1);++s->releases;return KERN_SUCCESS;}
 if(selector==A5NativeQuerySelector){const A5NativeQueryRequest*q=input;
  unsigned target=s->profile->passes[0].logicalTarget;
  assert(bytes==sizeof(*q)&&q->surfaces[0]==UINT64_C(0x100000001)+target);
  assert(!q->surfaces[1]&&!q->surfaces[2]); /* disabled attachments are not mapped */
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,
   .jobBytes=A5NativeJobBytes,.flags=11+s->queries};
  uint32_t row=s->profile->profileID==204?256:128;
  r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,row*32,32,32,row,
   s->profile->profileID==204?0x52476841u:0x42475241u,A5MaliRead|A5MaliWrite};
  unsigned buffers=s->profile->profileID==207?1:2;
  for(unsigned i=0;i<buffers;++i){
   assert(q->buffers[i]==UINT64_C(0x100000101)+i);
   r.buffers[i]=(A5NativeSpan){q->buffers[i],0x13000000+i*0x00800000,s->allocation[i],0,0,0,0,A5MaliRead|A5MaliWrite};
  }
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->queries;return KERN_SUCCESS;}
 assert(selector==A5NativeSubmitSelector);
 const A5NativeSubmitRequest*q=input;unsigned pass=s->submits;
 assert(pass==0&&bytes==sizeof(*q)+A5NativeJobBytes);
 unsigned buffers=s->profile->profileID==207?1:2;
 assert(q->profileID==s->profile->passes[0].passID&&q->mappingEpoch==11&&q->readBuffers==((1u<<buffers)-1));
 assert(q->readSurfaces==1&&q->writeSurfaces==1);
 for(unsigned i=0;i<buffers;++i)assert(s->uploaded[i]==s->lengths[i]&&!memcmp(s->actual[i],s->expected[i],s->lengths[i]));
 const uint8_t*d=(const uint8_t*)input+sizeof(*q);
 assert(!memcmp(d+0x6000,s->profile->passes[pass].vertex.bytes,s->profile->passes[pass].vertex.byteCount));
 assert(!memcmp(d+0x8000,s->profile->passes[pass].fragment.bytes,s->profile->passes[pass].fragment.byteCount));
 uint64_t vsStorage=0,fsStorage=0;
 memcpy(&vsStorage,d+0x1000+96,8);memcpy(&fsStorage,d+0x1400+144,8);
 assert(vsStorage==0x13000000);
 if(s->profile->profileID!=207)assert(fsStorage==0x13800000);
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=400+2*pass,.fragmentFence=401+2*pass};
 if(s->failSubmit)r.status=3;
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->submits;return KERN_SUCCESS;
}
static MTLRenderPipelineDescriptor *pipelineDescriptor(const A5MaliCompiledProfile*p,A5MaliMetalLibrary*library)
{
 MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];
 d.vertexFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:p->vertexName]];
 d.fragmentFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:p->fragmentName]];
 for(unsigned i=0;i<8;++i)d.colorAttachments[i].pixelFormat=p->colorFormats[i];
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<p->attributeCount;++i){const A5MaliCompiledVertexAttribute*a=p->attributes+i;
  d.vertexDescriptor.attributes[a->index].format=a->format;d.vertexDescriptor.attributes[a->index].offset=a->offset;
  d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 for(unsigned i=0;i<p->layoutCount;++i){const A5MaliCompiledVertexLayout*l=p->layouts+i;
  d.vertexDescriptor.layouts[l->index].stride=l->stride;d.vertexDescriptor.layouts[l->index].stepFunction=l->stepFunction;
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
static void run(unsigned profileID,BOOL failure)
{
 State s={.failSubmit=failure,.lengths={192,131073}};s.profile=A5MaliCompiledProfileForID(profileID);assert(s.profile);
 assert(s.profile->passCount==1&&s.profile->passes[0].logicalTarget==(profileID==207?1u:0u));
 /* Source-proven QC contracts, independent of the descriptor-copy helper:
  * A3/S0 blit writes RT0 only; A2/S1 clear writes RT1 only. */
 assert(s.profile->colorFormats[0]==(profileID==204?115u:80u));
 assert(s.profile->colorFormats[1]==s.profile->colorFormats[0]);
 if(profileID==200||profileID==204){
  assert(s.profile->colorFormats[2]==55&&s.profile->passes[0].passID==profileID);
  assert(s.profile->attachmentContracts[0].attachments[0].writeMask==MTLColorWriteMaskAll);
  assert(s.profile->attachmentContracts[0].attachments[1].writeMask==MTLColorWriteMaskNone);
  assert(s.profile->attachmentContracts[0].attachments[2].writeMask==MTLColorWriteMaskNone);
  if(profileID==204)assert((s.profile->flags&A5MaliProfileInlineSourceOver)&&
   s.profile->attachmentContracts[0].attachments[0].blendEnabled);
 }else{
  assert(profileID==207&&s.profile->colorFormats[2]==0&&s.profile->passes[0].passID==208);
  assert(s.profile->attachmentContracts[0].attachments[0].writeMask==MTLColorWriteMaskNone);
  assert(s.profile->attachmentContracts[0].attachments[1].writeMask==MTLColorWriteMaskAll);
 }
 for(unsigned i=0;i<2;++i){s.expected[i]=malloc(s.lengths[i]);s.actual[i]=calloc(1,s.lengths[i]);
  assert(s.expected[i]&&s.actual[i]);for(unsigned j=0;j<s.lengths[i];++j)s.expected[i][j]=(uint8_t)(29+i*17+j*11);}
 @autoreleasepool{
  A5MaliRestrictedDevice*device=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&s
   commandCapabilities:63 operationCapabilities:0x7ffff];
  const char*path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
  A5MaliMetalLibrary*library=[device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]error:NULL];assert(library);
  NSError*error=nil;id pipeline=[device newRenderPipelineStateWithDescriptor:pipelineDescriptor(s.profile,library)error:&error];assert(pipeline&&!error);
  A5MaliMetalBuffer*b=[[device newCommandQueue]commandBuffer];
  MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];
  for(unsigned i=0;i<2;++i){
   uint32_t row=profileID==204?256:128;
   A5MaliMetalTexture *backing=[device hostTestTextureWithResource:
    (A5MaliResource){0x100000001+i,32,32,row,A5MaliWrite}];
   if(profileID==204){MiscTexture *texture=[MiscTexture new];texture.backing=backing;texture.format=115;
    pass.colorAttachments[i].texture=(id)texture;}
   else pass.colorAttachments[i].texture=(id)backing;
   pass.colorAttachments[i].loadAction=MTLLoadActionLoad;pass.colorAttachments[i].storeAction=MTLStoreActionStore;}
  if(s.profile->colorFormats[2]){
   MiscTexture*unused=[MiscTexture new];unused.backing=[device hostTestTextureWithResource:
    (A5MaliResource){0x100000003,32,32,128,A5MaliWrite}];unused.format=s.profile->colorFormats[2];
   pass.colorAttachments[2].texture=(id)unused;pass.colorAttachments[2].loadAction=MTLLoadActionLoad;
   pass.colorAttachments[2].storeAction=MTLStoreActionStore;
  }
  A5MaliMetalRenderEncoder*r=[b renderCommandEncoderWithDescriptor:pass];assert(r&&r.device==device);
  r.label=@"one enabled output";assert([r.label isEqualToString:@"one enabled output"]);
  [r pushDebugGroup:@"actual resource submission"];[r insertDebugSignpost:@"enabled pass only"];[r popDebugGroup];
  [r setCullMode:MTLCullModeNone];[r setTriangleFillMode:MTLTriangleFillModeFill];
  [r setDepthBias:0 slopeScale:0 clamp:0];[r setDepthStencilState:nil];
  [r setRenderPipelineState:pipeline];
  uint8_t matrix[64];memset(matrix,0x34,sizeof(matrix));[r setVertexBytes:matrix length:64 atIndex:2];
  uint8_t info[8]={4,3,2,1,8,7,6,5};[r setFragmentBytes:info length:8 atIndex:1];
  A5MaliPrivateBuffer*vertices=[device newBufferWithLength:s.lengths[0]+17 options:0];
  A5MaliPrivateBuffer*storage=[device newBufferWithLength:s.lengths[1]+31 options:0];assert(vertices&&storage);
  [r setVertexBuffer:vertices offset:17 atIndex:1];[r setFragmentBuffer:storage offset:31 atIndex:9];
  [r drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[r endEncoding];
  memcpy((uint8_t*)vertices.contents+17,s.expected[0],s.lengths[0]);
  memcpy((uint8_t*)storage.contents+31,s.expected[1],s.lengths[1]);
  assert(!s.creates&&!s.submits);[b commit];[b waitUntilCompleted];
  assert(b.status==(failure?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted));
  unsigned buffers=profileID==207?1:2;
  assert(s.creates==buffers&&s.queries==1&&s.submits==1&&s.releases==buffers&&s.bulkCalls==buffers);
 }
 for(unsigned i=0;i<2;++i){free(s.expected[i]);free(s.actual[i]);}
}
int main(void){@autoreleasepool{run(200,NO);run(200,YES);run(204,NO);run(207,NO);puts("native misc: actual QC RT0-only, inline RGBA16 source-over and S1 RT1-only contracts, disabled-target exclusion, full131073-byteSSBO and cleanup passed (mock transport)");}return 0;}
