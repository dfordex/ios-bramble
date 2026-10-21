/* SPDX-License-Identifier: MIT
 * Original path attachment/blend contract, actual compiled inline-blend stages,
 * actual caller buffer uploads; only the kernel transport is mocked.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
@interface A5MaliMetalTexture(PathBacking)
- (A5MaliSurface *)privateSurface;
@end
@interface PathTexture:A5MaliMetalTexture
@property(nonatomic,strong)A5MaliMetalTexture*backing;
@property(nonatomic)MTLPixelFormat format;
@end
@implementation PathTexture
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
typedef struct{const A5MaliCompiledProfile*profile;unsigned created,uploaded,queries,submits,released;uint8_t data[192];}State;
static kern_return_t wire(void*context,uint32_t selector,const void*input,size_t bytes,void*output,size_t*outBytes)
{
 State*s=context;
 if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==8){const Create*q=input;assert(bytes==sizeof(*q)&&q->bytes==4096&&!s->created);
  Created r={{1,sizeof(r),0,0},UINT64_C(0x100000101),q->bytes,q->usage};assert(*outBytes==sizeof(r));
  memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->created;return KERN_SUCCESS;}
 if(selector==A5NativeBulkWriteSelector){const A5NativeBulkWriteRequest*q=input;
  assert(bytes==sizeof(*q)+192&&q->length==192&&!q->offset&&q->handle==UINT64_C(0x100000101));
  assert(!memcmp((const uint8_t*)input+sizeof(*q),s->data,192));++s->uploaded;return KERN_SUCCESS;}
 if(selector==9){assert(s->submits==1);++s->released;return KERN_SUCCESS;}
 if(selector==A5NativeQuerySelector){const A5NativeQueryRequest*q=input;
  assert(bytes==sizeof(*q)&&q->surfaces[0]==0x100000001&&!q->surfaces[1]);
  assert(q->buffers[0]==UINT64_C(0x100000101)&&!q->buffers[1]);
  BOOL stroke=s->profile->profileID==302;uint32_t row=stroke?256:128;
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=67};
  r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,row*32,32,32,row,stroke?0x52476841:0x4c303066,A5MaliRead|A5MaliWrite};
  r.buffers[0]=(A5NativeSpan){q->buffers[0],0x13000000,4096,0,0,0,0,A5MaliRead|A5MaliWrite};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->queries;return KERN_SUCCESS;}
 assert(selector==A5NativeSubmitSelector);const A5NativeSubmitRequest*q=input;
 assert(bytes==sizeof(*q)+A5NativeJobBytes&&q->profileID==s->profile->profileID&&q->mappingEpoch==67);
 assert(q->readSurfaces==1&&q->writeSurfaces==1&&q->readBuffers==1);
 const uint8_t*d=(const uint8_t*)input+sizeof(*q);const A5MaliCompiledPass*p=s->profile->passes;
 assert(!memcmp(d+0x4000,p->vertex.bytes,p->vertex.byteCount));
 assert(!memcmp(d+0x6000,p->fragment.bytes,p->fragment.byteCount));
 uint64_t storage=0;memcpy(&storage,d+0x1000+96,8);assert(storage==0x13000000);
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=800,.fragmentFence=801};
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->submits;return KERN_SUCCESS;
}
static MTLRenderPipelineDescriptor*descriptor(const A5MaliCompiledProfile*p,A5MaliMetalLibrary*l)
{
 MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];
 d.vertexFunction=(id)[l newFunctionWithName:[NSString stringWithUTF8String:p->vertexName]];
 d.fragmentFunction=(id)[l newFunctionWithName:[NSString stringWithUTF8String:p->fragmentName]];
 for(unsigned i=0;i<8;++i)d.colorAttachments[i].pixelFormat=p->colorFormats[i];
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<p->attributeCount;++i){const A5MaliCompiledVertexAttribute*x=p->attributes+i;
  d.vertexDescriptor.attributes[x->index].format=x->format;d.vertexDescriptor.attributes[x->index].offset=x->offset;
  d.vertexDescriptor.attributes[x->index].bufferIndex=x->bufferIndex;}
 for(unsigned i=0;i<p->layoutCount;++i){const A5MaliCompiledVertexLayout*x=p->layouts+i;
  d.vertexDescriptor.layouts[x->index].stride=x->stride;d.vertexDescriptor.layouts[x->index].stepFunction=x->stepFunction;
  d.vertexDescriptor.layouts[x->index].stepRate=x->stepRate;}
    assert(p->attachmentContracts && p->attachmentContractCount);
    for(unsigned i=0;i<8;++i){const A5MaliCompiledAttachmentState *c=&p->attachmentContracts[0].attachments[i];
        MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[i];
        a.writeMask=c->writeMask;a.blendingEnabled=c->blendEnabled;
        a.rgbBlendOperation=c->rgbOperation;a.alphaBlendOperation=c->alphaOperation;
        a.sourceRGBBlendFactor=c->sourceRGB;a.destinationRGBBlendFactor=c->destinationRGB;
        a.sourceAlphaBlendFactor=c->sourceAlpha;a.destinationAlphaBlendFactor=c->destinationAlpha;}
 return d;
}
static void run(unsigned idNumber)
{
 State s={0};s.profile=A5MaliCompiledProfileForID(idNumber);assert(s.profile);
 assert(s.profile->passCount==1&&s.profile->passes[0].logicalTarget==(idNumber==302?0u:2u));
 assert(s.profile->colorFormats[0]==(idNumber==302?115u:80u));
 assert(s.profile->colorFormats[1]==s.profile->colorFormats[0]&&s.profile->colorFormats[2]==55);
 const A5MaliCompiledAttachmentState*c=s.profile->attachmentContracts[0].attachments;
 if(idNumber==302){
  assert(c[0].writeMask==MTLColorWriteMaskAll&&c[0].blendEnabled);
  assert(c[0].sourceRGB==MTLBlendFactorOne&&c[0].destinationRGB==MTLBlendFactorOneMinusSourceAlpha);
  assert(c[1].writeMask==MTLColorWriteMaskNone&&c[2].writeMask==MTLColorWriteMaskNone);
 }else{
  assert(c[0].writeMask==MTLColorWriteMaskNone&&!c[0].blendEnabled);
  /* Only cubic has Bsov: disabled RT0 retains its factors. Rect has no
   * blend token and retains destination factor Zero. */
  assert(c[0].sourceRGB==MTLBlendFactorOne&&c[0].destinationRGB==
   (idNumber==301?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero));
  assert(c[1].writeMask==MTLColorWriteMaskNone&&c[2].writeMask==MTLColorWriteMaskRed&&c[2].blendEnabled);
  assert(c[2].sourceRGB==MTLBlendFactorOne&&c[2].destinationRGB==MTLBlendFactorOne);
 }
 for(unsigned i=0;i<sizeof(s.data);++i)s.data[i]=(uint8_t)(33+i*13);
 @autoreleasepool{
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&s commandCapabilities:63 operationCapabilities:0x7ffff];
  const char*path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
  A5MaliMetalLibrary*l=[d newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]error:NULL];assert(l);
  NSError*error=nil;id pipeline=[d newRenderPipelineStateWithDescriptor:descriptor(s.profile,l)error:&error];assert(pipeline&&!error);
  PathTexture*t=[PathTexture new];unsigned target=idNumber==302?0:2,row=idNumber==302?256:128;
  t.backing=[d hostTestTextureWithResource:(A5MaliResource){0x100000001,32,32,row,A5MaliWrite}];t.format=idNumber==302?115:55;
  MTLRenderPassDescriptor*p=[MTLRenderPassDescriptor renderPassDescriptor];p.colorAttachments[target].texture=(id)t;
  p.colorAttachments[target].loadAction=MTLLoadActionLoad;p.colorAttachments[target].storeAction=MTLStoreActionStore;
  A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];A5MaliMetalRenderEncoder*e=[b renderCommandEncoderWithDescriptor:p];assert(e);
  [e setRenderPipelineState:pipeline];A5MaliPrivateBuffer*storage=[d newBufferWithLength:192 options:0];
  [e setVertexBuffer:storage offset:0 atIndex:1];uint8_t matrix[64];memset(matrix,0x34,64);
  [e setVertexBytes:matrix length:64 atIndex:2];uint8_t aux[24];memset(aux,0x28,24);
  [e setVertexBytes:aux length:idNumber==302?24:16 atIndex:5];
  [e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];
  memcpy(storage.contents,s.data,192);assert(!s.created);[b commit];[b waitUntilCompleted];
  assert(b.status==MTLCommandBufferStatusCompleted&&!b.error);
  assert(s.created==1&&s.uploaded==1&&s.queries==1&&s.submits==1&&s.released==1);
 }
}
int main(void){run(300);run(301);run(302);puts("native path: original RT2 additive coverage and RT0-only stroke contracts, genuine inline-blend code and caller uploads passed (mock transport)");return 0;}
