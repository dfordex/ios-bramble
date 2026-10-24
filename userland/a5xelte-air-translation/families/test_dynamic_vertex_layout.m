/* SPDX-License-Identifier: MIT
 * Real cached vertex/fragment pair through factory and native descriptor
 * emission. Metal indices stay sparse; no GPU execution is claimed. */
#import "../../a5mali-metal/A5MaliDynamicPipeline.h"
#import "../../a5mali-metal/A5MaliDynamicShaderCache.h"
#import "../../a5mali-metal/A5MaliMetalTexture.h"
#import "../../a5mali-metal/A5MaliNative.h"
#import "../../a5mali-metal/A5MaliMetalDeviceResources.h"
#import "../../a5mali-metal/A5MaliShaderCompileRequest.h"
#include "runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
extern void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile *,unsigned,unsigned);
extern void A5MaliCheckPackedVertexUpload(const uint8_t *,const uint8_t *,unsigned,uint32_t);
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
@interface A5MaliMetalFunction (VertexLayoutTest)
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)l dynamicShader:(A5MaliDynamicShaderCacheEntry *)s;
@end
@interface A5MaliReadSurfCandidate (VertexLayoutTest)
- (const A5MaliCompiledProfile *)profile;
@end
typedef struct {unsigned queries,submits;uint8_t vertices[64];} Transport;
static kern_return_t transport(void*c,uint32_t selector,const void*input,size_t n,void*output,size_t*z){
 Transport *s=c;
 if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==A5NativeQuerySelector){
  const A5NativeQueryRequest *q=input;assert(n==sizeof(*q)&&q->surfaces[0]==0x100000001);
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=91};
  r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x13000000,4096,32,32,128,0x42475241,3};
  assert(*z==sizeof(r));memcpy(output,&r,sizeof(r));*z=sizeof(r);s->queries++;return KERN_SUCCESS;
 }
 assert(selector==A5NativeSubmitSelector&&n==sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
 const A5NativeSubmitRequest *q=input;assert(q->profileID==A5MaliDynamicProfileID&&q->mappingEpoch==91);
 A5MaliCheckPackedVertexUpload((const uint8_t*)input+sizeof(*q),s->vertices,sizeof(s->vertices),A5NativeJobVA);s->submits++;
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=51,.fragmentFence=52};
 assert(*z==sizeof(r));memcpy(output,&r,sizeof(r));*z=sizeof(r);return KERN_SUCCESS;
}
static A5MaliDynamicShaderCacheEntry *load(const char *path){
 NSError *error=nil;
 NSMutableDictionary *body=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(path)] options:NSJSONReadingMutableContainers error:&error];assert(body&&!error);
 NSString *identity=body[@"request_id"];[body removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 A5MaliDynamicShaderCacheEntry *stage=A5MaliLoadDynamicShaderStage(identity,body,&error);
 if(!stage)NSLog(@"%@",error);assert(stage&&!error);return stage;
}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==3||argc==4);NSError *error=nil;
 BOOL staticVertex=!strcmp(argv[1],"static603");
 A5MaliDynamicShaderCacheEntry *vs=staticVertex?nil:load(argv[1]),*fs=load(argv[2]);
 unsigned nativeInputs=staticVertex?3:[vs.nativeABI[@"native_info"][@"attributes"] unsignedIntValue];
 assert(nativeInputs>=2&&nativeInputs<=4);
 unsigned required=nativeInputs==2?0x9:nativeInputs==3?0xb:0xf;
 Transport state={0};
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&state commandCapabilities:63 operationCapabilities:0x7ffff];
 const char *stock=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(stock);
 A5MaliMetalLibrary *lib=[device newLibraryWithURL:[NSURL fileURLWithPath:@(stock)] error:&error];assert(lib&&!error);
 MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
 if(staticVertex){
  size_t count=0;const A5MaliCompiledFunctionConstant *c=A5MaliCompiledVertexConstantsForProfile(603,&count);assert(c&&count);
  MTLFunctionConstantValues *constants=[MTLFunctionConstantValues new];
  for(size_t i=0;i<count;i++)[constants setConstantValue:c[i].raw type:c[i].dataType withName:@(c[i].name)];
  d.vertexFunction=(id)[lib newFunctionWithName:@"fixed_vert_lph_spc" constantValues:constants error:&error];assert(d.vertexFunction&&!error);
 }else d.vertexFunction=(id)[[A5MaliMetalFunction alloc]initWithLibrary:lib dynamicShader:vs];
 d.fragmentFunction=(id)[[A5MaliMetalFunction alloc]initWithLibrary:lib dynamicShader:fs];
 const unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
 unsigned accepted=0,rejected=0;
 for(unsigned packing=0;packing<4;packing++)for(unsigned mask=0;mask<16;mask++)for(unsigned xy=0;xy<2;xy++)
 for(unsigned packed=0;packed<2;packed++)for(unsigned blend=0;blend<2;blend++){
  unsigned actualOffsets[4];memcpy(actualOffsets,offsets,sizeof(offsets));unsigned stride=48;
  if(packing==1){
   unsigned next=xy?8:16;
   for(unsigned i=1;i<4;i++){actualOffsets[i]=next;if(mask&(1u<<i))next+=8;}
   stride=next;
  }else if(packing==2){actualOffsets[0]=32;actualOffsets[1]=8;actualOffsets[2]=16;actualOffsets[3]=0;stride=64;}
  else if(packing==3)stride=2048;
  d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
  for(unsigned i=0;i<4;i++)if(mask&(1u<<i)){
   d.vertexDescriptor.attributes[i].format=i==0&&xy?29:formats[i];
   d.vertexDescriptor.attributes[i].offset=actualOffsets[i];d.vertexDescriptor.attributes[i].bufferIndex=1;
  }
  d.vertexDescriptor.layouts[1].stride=stride;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
  unsigned target=packed?43:80;d.colorAttachments[0].pixelFormat=target;
  d.colorAttachments[0].blendingEnabled=blend;
  d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
  d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=blend?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero;
  error=nil;A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];
  if((mask&required)!=required){assert(!pipeline&&error);rejected++;continue;}
  if(!pipeline)NSLog(@"mask%u: %@",mask,error);assert(pipeline&&!error);accepted++;
  const A5MaliCompiledProfile *profile=[pipeline profile];
  unsigned seen=0;for(unsigned i=0;i<profile->attributeCount;i++)seen|=1u<<profile->attributes[i].index;
  assert(seen==mask&&profile->attributes[0].index==0);
  A5MaliTestDynamicFormat43(profile,target,blend);
  /* Independent emitter gate must reject lost live fields and duplicates. */
  for(unsigned index=0;index<4;index++)if(required&(1u<<index)){
   A5MaliCompiledProfile bad=*profile;A5MaliCompiledVertexAttribute attrs[4];unsigned n=0;
   for(unsigned i=0;i<profile->attributeCount;i++)if(profile->attributes[i].index!=index)attrs[n++]=profile->attributes[i];
   bad.attributes=attrs;bad.attributeCount=n;assert(!A5MaliDynamicRuntimeProfileSupported(&bad));
  }
  /* Live and present-unused field packing remains exact. */
  for(unsigned i=0;i<4;i++)if(mask&(1u<<i)){
   d.vertexDescriptor.attributes[i].offset++;error=nil;
   assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.attributes[i].offset--;
   d.vertexDescriptor.attributes[i].bufferIndex=2;error=nil;
   assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.attributes[i].bufferIndex=1;
   unsigned saved=(unsigned)d.vertexDescriptor.attributes[i].format;
   d.vertexDescriptor.attributes[i].format=MTLVertexFormatUInt;error=nil;
   assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.attributes[i].format=saved;
  }
  d.vertexDescriptor.attributes[4].format=MTLVertexFormatFloat2;error=nil;
  assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.attributes[4].format=MTLVertexFormatInvalid;
  d.vertexDescriptor.layouts[1].stride=4;error=nil;
  assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.layouts[1].stride=stride;
 }
 if(argc==4){
  error=nil;
  NSDictionary *capture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[3])] options:0 error:&error];assert(capture&&!error);
  NSDictionary *descriptorState=capture[@"descriptor"];assert(descriptorState);
  d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
  for(NSDictionary *a in descriptorState[@"vertex_attributes"]){unsigned i=[a[@"index"] unsignedIntValue];assert(i<31);
   d.vertexDescriptor.attributes[i].format=[a[@"format"] unsignedIntegerValue];
   d.vertexDescriptor.attributes[i].offset=[a[@"offset"] unsignedIntegerValue];d.vertexDescriptor.attributes[i].bufferIndex=[a[@"buffer_index"] unsignedIntegerValue];}
  for(NSDictionary *a in descriptorState[@"vertex_layouts"]){unsigned i=[a[@"index"] unsignedIntValue];assert(i<31);
   d.vertexDescriptor.layouts[i].stride=[a[@"stride"] unsignedIntegerValue];d.vertexDescriptor.layouts[i].stepFunction=[a[@"step_function"] unsignedIntegerValue];d.vertexDescriptor.layouts[i].stepRate=[a[@"step_rate"] unsignedIntegerValue];}
  unsigned i=0;for(NSDictionary *a in descriptorState[@"color_attachments"]){assert(i<8);MTLRenderPipelineColorAttachmentDescriptor *c=d.colorAttachments[i++];
   c.pixelFormat=[a[@"format"] unsignedIntegerValue];c.writeMask=[a[@"write_mask"] unsignedIntegerValue];c.blendingEnabled=[a[@"blend_enabled"] boolValue];
   c.rgbBlendOperation=[a[@"rgb_operation"] unsignedIntegerValue];c.alphaBlendOperation=[a[@"alpha_operation"] unsignedIntegerValue];
   c.sourceRGBBlendFactor=[a[@"source_rgb"] unsignedIntegerValue];c.destinationRGBBlendFactor=[a[@"destination_rgb"] unsignedIntegerValue];
   c.sourceAlphaBlendFactor=[a[@"source_alpha"] unsignedIntegerValue];c.destinationAlphaBlendFactor=[a[@"destination_alpha"] unsignedIntegerValue];}
  error=nil;NSDictionary *replayed=A5MaliShaderCompilePipelinePayload(d,[(A5MaliMetalFunction *)d.vertexFunction compileRequestPayload],[(A5MaliMetalFunction *)d.fragmentFunction compileRequestPayload],&error);
  assert(replayed&&!error&&[replayed[@"descriptor"] isEqual:descriptorState]);
  error=nil;A5MaliReadSurfCandidate *p=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!p)NSLog(@"captured descriptor: %@",error);assert(p&&!error);
  assert([p profile]->layouts[0].stride==16&&[p profile]->attributeCount==2);
  A5MaliTestDynamicFormat43([p profile],(unsigned)d.colorAttachments[0].pixelFormat,d.colorAttachments[0].blendingEnabled);
  /* A 64-byte actual packed buffer must reach submission. Old count*48
   * producer snapshots would reject it before the emitter was called. */
  for(unsigned indexed=0;indexed<2;indexed++){
   state.queries=state.submits=0;for(unsigned i=0;i<64;i++)state.vertices[i]=(uint8_t)(i^0x5a);
   A5MaliMetalBuffer *cb=[[device newCommandQueue]commandBuffer];
   MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
   pass.colorAttachments[0].texture=(id)[device hostTestTextureWithResource:(A5MaliResource){0x100000001,32,32,128,3}];
   pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
   A5MaliMetalRenderEncoder *encoder=[cb renderCommandEncoderWithDescriptor:pass];assert(encoder);
   [encoder setRenderPipelineState:p];[encoder setVertexBytes:state.vertices length:64 atIndex:1];
   uint8_t uniform[4096]={0};const A5MaliCompiledProfile *profile=[p profile];
   for(unsigned j=0;j<profile->resourceCount;j++){const A5MaliCompiledResource *r=profile->resources+j;
    if(r->kind!=A5MaliResourceBuffer)continue;
    if(r->stage==1)[encoder setVertexBytes:uniform length:r->uniformBytes atIndex:r->metalIndex];
    else [encoder setFragmentBytes:uniform length:r->uniformBytes atIndex:r->metalIndex];}
   if(indexed){uint16_t indices[]={0,1,2,2,1,3};A5MaliPrivateBuffer *ib=[device newBufferWithBytes:indices length:sizeof(indices) options:MTLResourceStorageModeShared];assert(ib);
    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6 indexType:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0];
   }else [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
   [encoder endEncoding];[cb commit];[cb waitUntilCompleted];
   assert(cb.status==MTLCommandBufferStatusCompleted&&state.queries==1&&state.submits==1);
  }
  puts("PASS exact recovered 0226 descriptor: Float2 position0/Half4 color8/stride16 through real factory and native emitter");
 }
 printf("PASS real native vertex inputs=%u required Metal mask=%x: %u accepted/%u rejected layouts, exact shaders and native fetch descriptors; no GPU execution\n",nativeInputs,required,accepted,rejected);
}return 0;}
