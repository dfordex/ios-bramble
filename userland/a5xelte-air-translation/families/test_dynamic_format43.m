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
 for(unsigned f=0;f<2;f++)for(unsigned blend=0;blend<2;blend++){
  unsigned format=f?43:80;d.colorAttachments[0].pixelFormat=format;
  d.colorAttachments[0].blendingEnabled=blend;
  d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
  d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=blend?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero;
  error=nil;A5MaliReadSurfCandidate*p=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!p)NSLog(@"%@",error);assert(p&&!error);
  assert([p profile]->colorFormats[0]==format);A5MaliTestDynamicFormat43([p profile],format,blend);
 }
 for(NSNumber*f in @[@0,@70,@71,@81,@115,@999]){
  d.colorAttachments[0].pixelFormat=f.unsignedIntegerValue;error=nil;
  assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);
 }
 puts("PASS genuine dynamic target80/43 copy/blend factory, exact shader bytes, SFBD/preload tuples, row/span bounds and unsupported formats; GPU pixels pending");
}return 0;}
