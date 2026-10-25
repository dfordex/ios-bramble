/* SPDX-License-Identifier: MIT
 * Real worker-published stock blur code through cache, Metal factory and v4 emitter.
 */
#import "A5MaliDynamicPipeline.h"
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliImmutableSampler.h"
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
static kern_return_t wire(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b){
 (void)c;(void)s;(void)i;(void)n;(void)o;(void)b;abort();
}
@interface A5MaliReadSurfCandidate(VariableBlurTest)
- (const A5MaliCompiledProfile*)profile;
@end
extern void A5MaliTestDynamicFormat43(const A5MaliCompiledProfile*,unsigned,unsigned);
extern void A5MaliTestVariableBlurDescriptors(const A5MaliCompiledProfile*);
static void samplerGuards(void){
 NSMutableDictionary*s=[@{@"mag_filter":@1,@"min_filter":@1,@"mipmap_mode":@0,
  @"address_mode_u":@3,@"address_mode_v":@3,@"address_mode_w":@3,@"mip_lod_bias":@0,
  @"max_anisotropy":NSNull.null,@"compare":NSNull.null,@"min_lod":@0,@"max_lod":@15,
  @"border_color":@0,@"reduction":@0,@"border_components":NSNull.null}mutableCopy];
 A5MaliCompiledSampler state;assert(A5MaliDecodeImmutableSampler(s,0,&state));
 assert(state.minFilter==1&&state.magFilter==1&&state.sAddressMode==4&&state.lodMaxClamp==15);
 NSArray*cases=@[@[@"compare",@0],@[@"max_lod",@16],@[@"min_lod",@16],
  @[@"border_color",@1],@[@"address_mode_u",@1],@[@"mag_filter",@2],
  @[@"mipmap_mode",@1],@[@"mip_lod_bias",@1],@[@"min_filter",@YES],
  @[@"max_anisotropy",@2],@[@"unexpected",@0]];
 for(NSArray*c in cases){NSMutableDictionary*bad=[s mutableCopy];bad[c[0]]=c[1];assert(!A5MaliDecodeImmutableSampler(bad,0,NULL));}
 assert(!A5MaliDecodeImmutableSampler(s,4,NULL));
}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==2);samplerGuards();unsigned ctx=0;
 A5MaliRestrictedDevice*device=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&ctx commandCapabilities:63 operationCapabilities:0x7ffff];
 NSError*error=nil;A5MaliMetalLibrary*l=[device newLibraryWithURL:[NSURL fileURLWithPath:@(argv[1])]error:&error];assert(l&&!error);
 A5MaliMetalFunction*vertex=[l newFunctionWithName:@"variable_blur_vert_lph"];
 A5MaliMetalFunction*fragment=[l newFunctionWithName:@"variable_blur_downsample_frag_lph"];
 assert(vertex.dynamicShader&&fragment.dynamicShader);
 assert(vertex.dynamicShader.shader->byteCount==2432&&fragment.dynamicShader.shader->byteCount==2000);
 for(unsigned extra=0;extra<2;extra++)for(unsigned packed=0;packed<2;packed++){
  MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];d.vertexFunction=(id)vertex;d.fragmentFunction=(id)fragment;
  d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
  unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
  for(unsigned i=0;i<3+extra;i++){d.vertexDescriptor.attributes[i].format=formats[i];d.vertexDescriptor.attributes[i].offset=offsets[i];d.vertexDescriptor.attributes[i].bufferIndex=1;}
  d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
  d.colorAttachments[0].pixelFormat=packed?MTLPixelFormatBGR5A1Unorm:MTLPixelFormatBGRA8Unorm;
  id pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!pipeline)NSLog(@"%@",error);assert(pipeline&&!error);
  const A5MaliCompiledProfile*p=[pipeline profile];assert(p&&p->profileID==A5MaliDynamicProfileID);
  assert((p->flags&(A5MaliProfileVertexTwoUV|A5MaliProfileVertexNoColor))==(A5MaliProfileVertexTwoUV|A5MaliProfileVertexNoColor));
  assert(!(p->flags&A5MaliProfileDynamicColorVarying));
  assert(p->immutableSamplerCount==1&&p->immutableSamplers[0].sAddressMode==4&&p->immutableSamplers[0].lodMaxClamp==15);
  unsigned seen=0;for(unsigned i=0;i<p->resourceCount;i++){const A5MaliCompiledResource*r=p->resources+i;
   if(r->kind==A5MaliResourceBuffer&&r->stage==2&&r->metalIndex==6){assert(r->uniformBytes==2&&(r->flags&A5MaliResourcePadUniformTail));seen++;}}
  assert(seen==1);A5MaliTestDynamicFormat43(p,packed?43:80,A5RuntimeBlendState);A5MaliTestVariableBlurDescriptors(p);
 }
 puts("Real variable blur: AIR/native -> cache -> Metal factory -> sampler/sysvals/two-UV/large descriptor tests PASS (physical pixels pending)");
 }return 0;}
