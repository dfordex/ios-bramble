/* SPDX-License-Identifier: MIT
 * Real cached vertex/fragment pair through factory and native descriptor
 * emission. Metal indices stay sparse; no GPU execution is claimed. */
#import "../../a5mali-metal/A5MaliDynamicPipeline.h"
#import "../../a5mali-metal/A5MaliDynamicShaderCache.h"
#include "runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
extern void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile *,unsigned,unsigned);
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
@interface A5MaliMetalFunction (VertexLayoutTest)
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)l dynamicShader:(A5MaliDynamicShaderCacheEntry *)s;
@end
@interface A5MaliReadSurfCandidate (VertexLayoutTest)
- (const A5MaliCompiledProfile *)profile;
@end
static kern_return_t transport(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*z){
 (void)c;(void)s;(void)i;(void)n;(void)o;(void)z;return kIOReturnUnsupported;
}
static A5MaliDynamicShaderCacheEntry *load(const char *path){
 NSError *error=nil;
 NSMutableDictionary *body=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(path)] options:NSJSONReadingMutableContainers error:&error];assert(body&&!error);
 NSString *identity=body[@"request_id"];[body removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 A5MaliDynamicShaderCacheEntry *stage=A5MaliLoadDynamicShaderStage(identity,body,&error);
 if(!stage)NSLog(@"%@",error);assert(stage&&!error);return stage;
}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==3);NSError *error=nil;
 BOOL staticVertex=!strcmp(argv[1],"static603");
 A5MaliDynamicShaderCacheEntry *vs=staticVertex?nil:load(argv[1]),*fs=load(argv[2]);
 unsigned nativeInputs=staticVertex?3:[vs.nativeABI[@"native_info"][@"attributes"] unsignedIntValue];
 assert(nativeInputs>=2&&nativeInputs<=4);
 unsigned required=nativeInputs==2?0x9:nativeInputs==3?0xb:0xf;
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&argc commandCapabilities:63 operationCapabilities:0x7ffff];
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
 for(unsigned mask=0;mask<16;mask++)for(unsigned xy=0;xy<2;xy++)
 for(unsigned packed=0;packed<2;packed++)for(unsigned blend=0;blend<2;blend++){
  d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
  for(unsigned i=0;i<4;i++)if(mask&(1u<<i)){
   d.vertexDescriptor.attributes[i].format=i==0&&xy?29:formats[i];
   d.vertexDescriptor.attributes[i].offset=offsets[i];d.vertexDescriptor.attributes[i].bufferIndex=1;
  }
  d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
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
  d.vertexDescriptor.layouts[1].stride=40;error=nil;
  assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.layouts[1].stride=48;
 }
 printf("PASS real native vertex inputs=%u required Metal mask=%x: %u accepted/%u rejected layouts, exact shaders and native fetch descriptors; no GPU execution\n",nativeInputs,required,accepted,rejected);
}return 0;}
