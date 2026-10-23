/* SPDX-License-Identifier: MIT
 * Load a real worker-published unknown fragment through the production cache
 * and pipeline composer, then pass that owned profile to the real C emitter.
 */
#import "../../a5mali-metal/A5MaliDynamicPipeline.h"
#import "../../a5mali-metal/A5MaliDynamicShaderCache.h"
#include "runtime_misc_encode.h"
#include <assert.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static kern_return_t unusedTransport(void *ctx,uint32_t sel,const void *in,size_t n,void *out,size_t *m){
 (void)ctx;(void)sel;(void)in;(void)n;(void)out;(void)m;return kIOReturnUnsupported;
}
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
extern int A5MaliBuildDynamicFixture(const A5MaliCompiledProfile *,void *,size_t,int);
@interface A5MaliReadSurfCandidate (DynamicFixture)
- (const A5MaliCompiledProfile *)profile;
@end
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==4);int blend=!strcmp(argv[3],"blend");assert(blend||!strcmp(argv[3],"copy"));
 NSData *capture=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
 NSDictionary *doc=[NSJSONSerialization JSONObjectWithData:capture options:0 error:NULL];assert(doc);
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:unusedTransport context:&argc commandCapabilities:63 operationCapabilities:0x7ffff];assert(device);
 const char *stock=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(stock);NSError *error=nil;
 A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:stock]] error:&error];assert(library&&!error);
 MTLFunctionConstantValues *v=[MTLFunctionConstantValues new],*f=[MTLFunctionConstantValues new];
 size_t count=0;const A5MaliCompiledFunctionConstant *constants=A5MaliCompiledVertexConstantsForProfile(603,&count);assert(constants&&count==4);
 for(size_t i=0;i<count;i++)[v setConstantValue:constants[i].raw type:constants[i].dataType withName:[NSString stringWithUTF8String:constants[i].name]];
 assert([doc[@"constants"] count]==58);
 for(NSString *name in doc[@"constants"]){NSDictionary *c=doc[@"constants"][name];NSString *raw=c[@"raw"];uint8_t bytes[16];unsigned n=(unsigned)raw.length/2;assert(n&&n<=sizeof(bytes));
  for(unsigned i=0;i<n;i++){unsigned x=0;assert(sscanf([[raw substringWithRange:NSMakeRange(i*2,2)] UTF8String],"%2x",&x)==1);bytes[i]=(uint8_t)x;}
  [f setConstantValue:bytes type:[c[@"type"] unsignedIntValue] withName:name];
 }
 MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
 d.vertexFunction=(id)[library newFunctionWithName:@"fixed_vert_lph_spc" constantValues:v error:&error];assert(d.vertexFunction&&!error);
 d.fragmentFunction=(id)[library newFunctionWithName:doc[@"function"] constantValues:f error:&error];assert(d.fragmentFunction&&!error);
 assert([(A5MaliMetalFunction *)d.fragmentFunction dynamicShader]);
 const A5MaliCompiledProfile *shape=A5MaliCompiledProfileForID(603);assert(shape);
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<shape->attributeCount;i++){const A5MaliCompiledVertexAttribute *a=shape->attributes+i;d.vertexDescriptor.attributes[a->index].format=a->format;d.vertexDescriptor.attributes[a->index].offset=a->offset;d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
 d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
 if(blend){d.colorAttachments[0].blendingEnabled=YES;d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;}
 A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!pipeline)NSLog(@"%@",error);assert(pipeline&&!error);
 const A5MaliCompiledProfile *profile=[pipeline profile];assert(profile&&profile->profileID==A5MaliDynamicProfileID);
 uint8_t *data=malloc(A5RuntimeJobBytes);assert(data&&A5MaliBuildDynamicFixture(profile,data,A5RuntimeJobBytes,blend));
 FILE *file=fopen(argv[2],"wb");assert(file&&fwrite(data,1,A5RuntimeJobBytes,file)==A5RuntimeJobBytes&&!fclose(file));free(data);
 printf("Dynamic profile%u %s actual root publication -> provider -> native emitter: PASS (device pixels pending)\n",profile->profileID,blend?"source-over":"copy");
}return 0;}
