/* SPDX-License-Identifier: MIT
 * Genuine worker publication -> production factory -> production SFBD/preload.
 * Host-only descriptor/bounds checks. No GPU execution or substituted shader.
 */
#import "../../a5mali-metal/A5MaliDynamicPipeline.h"
#import "../../a5mali-metal/A5MaliDynamicShaderCache.h"
#include "runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
extern void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile *,unsigned,unsigned);
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
@interface A5MaliMetalFunction (Format43Test)
- (instancetype)initWithLibrary:(A5MaliMetalLibrary *)l dynamicShader:(A5MaliDynamicShaderCacheEntry *)s;
@end
@interface A5MaliReadSurfCandidate (Format43Test)
- (const A5MaliCompiledProfile *)profile;
@end
static kern_return_t transport(void*c,uint32_t sel,const void*i,size_t n,void*o,size_t*z){
 (void)c;(void)sel;(void)i;(void)n;(void)o;(void)z;return kIOReturnUnsupported;
}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==2);NSError*error=nil;
 NSDictionary*request=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])]options:0 error:&error];assert(request&&!error);
 NSMutableDictionary*payload=[request mutableCopy];[payload removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 A5MaliDynamicShaderCacheEntry*fs=A5MaliLoadDynamicShaderStage(request[@"request_id"],payload,&error);assert(fs&&!error);
 A5MaliRestrictedDevice*device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&argc commandCapabilities:63 operationCapabilities:0x7ffff];
 const char*stock=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(stock);
 A5MaliMetalLibrary*library=[device newLibraryWithURL:[NSURL fileURLWithPath:@(stock)]error:&error];assert(library&&!error);
 MTLFunctionConstantValues*values=[MTLFunctionConstantValues new];size_t n=0;
 const A5MaliCompiledFunctionConstant*c=A5MaliCompiledVertexConstantsForProfile(603,&n);assert(c&&n);
 for(size_t i=0;i<n;i++)[values setConstantValue:c[i].raw type:c[i].dataType withName:@(c[i].name)];
 MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];
 d.vertexFunction=(id)[library newFunctionWithName:@"fixed_vert_lph_spc"constantValues:values error:&error];assert(d.vertexFunction&&!error);
 d.fragmentFunction=(id)[[A5MaliMetalFunction alloc]initWithLibrary:library dynamicShader:fs];
 const A5MaliCompiledProfile*shape=A5MaliCompiledProfileForID(603);assert(shape);
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<shape->attributeCount;i++){
  const A5MaliCompiledVertexAttribute*a=shape->attributes+i;d.vertexDescriptor.attributes[a->index].format=a->format;
  d.vertexDescriptor.attributes[a->index].offset=a->offset;d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;
 }
 d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
 for(unsigned xy=0;xy<2;xy++)for(unsigned f=0;f<2;f++)for(unsigned blend=0;blend<2;blend++){
  d.vertexDescriptor.attributes[0].format=xy?29:31;
  unsigned format=f?43:80;d.colorAttachments[0].pixelFormat=format;
  d.colorAttachments[0].blendingEnabled=blend;
  d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
  d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=blend?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero;
  error=nil;A5MaliReadSurfCandidate*p=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!p)NSLog(@"%@",error);assert(p&&!error);
  assert([p profile]->colorFormats[0]==format);A5MaliTestDynamicFormat43([p profile],format,blend);
 }
 /* Static602..606 retain their exact profile ID, shader hashes and complete
  * original resource contract in a pipeline-owned packed storage profile. */
 NSMutableArray *owners=[NSMutableArray new];
 for(unsigned profileID=602;profileID<=606;profileID++){
  const A5MaliCompiledProfile*source=A5MaliCompiledProfileForID(profileID);assert(source&&source->colorFormats[0]==80);
  for(unsigned stage=0;stage<2;stage++){
   MTLFunctionConstantValues*constants=[MTLFunctionConstantValues new];size_t count=0;
   const A5MaliCompiledFunctionConstant*fields=stage?A5MaliCompiledConstantsForProfile(profileID,&count):A5MaliCompiledVertexConstantsForProfile(profileID,&count);assert(fields&&count);
   for(size_t i=0;i<count;i++)[constants setConstantValue:fields[i].raw type:fields[i].dataType withName:@(fields[i].name)];
   error=nil;id function=[library newFunctionWithName:@(stage?source->fragmentName:source->vertexName)constantValues:constants error:&error];assert(function&&!error);
   if(stage)d.fragmentFunction=function;else d.vertexFunction=function;
  }
  for(unsigned xy=0;xy<2;xy++)for(unsigned target=0;target<2;target++)for(unsigned blend=0;blend<2;blend++){
   d.vertexDescriptor.attributes[0].format=xy?29:31;
   unsigned format=target?43:80;d.colorAttachments[0].pixelFormat=format;
   d.colorAttachments[0].blendingEnabled=blend;
   d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
   d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=blend?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero;
   error=nil;A5MaliReadSurfCandidate*p=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!p)NSLog(@"static%u target%u: %@",profileID,format,error);assert(p&&!error);
   const A5MaliCompiledProfile*actual=[p profile];A5MaliCompiledProfile expected=*source;expected.colorFormats[0]=format;
   assert(actual->profileID==profileID&&source->colorFormats[0]==80&&source->attributes[0].format==31);
   if(xy){assert(actual->attributes!=source->attributes&&actual->attributes[0].format==29);expected.attributes=actual->attributes;}
   assert(!memcmp(actual,&expected,sizeof(expected)));
   if(format==43){assert(actual!=source);[owners addObject:p];}
   A5MaliTestDynamicFormat43(actual,format,blend);
  }
  d.vertexDescriptor.attributes[0].format=31;
  // Packing adaptation must preserve every other descriptor restriction.
  d.colorAttachments[0].pixelFormat=43;d.vertexDescriptor.layouts[1].stride=40;error=nil;
  assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.vertexDescriptor.layouts[1].stride=48;
  d.rasterSampleCount=4;error=nil;assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);d.rasterSampleCount=1;
  d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOne;error=nil;
  assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);
  d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
 }
 for(A5MaliReadSurfCandidate*p in owners)assert([p profile]->colorFormats[0]==43);
 for(NSNumber*f in @[@0,@70,@71,@81,@115,@999]){
  d.colorAttachments[0].pixelFormat=f.unsignedIntegerValue;error=nil;
  assert(![device newRenderPipelineStateWithDescriptor:d error:&error]&&error);
 }
 puts("PASS genuine dynamic and static602..606 target80/43 copy/blend factory, exact shader bytes, SFBD/preload tuples, row/span bounds and unsupported formats; GPU pixels pending");
}return 0;}
