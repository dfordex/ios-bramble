/* SPDX-License-Identifier: MIT */
#import "A5MaliDynamicPipeline.h"
#import "A5MaliDynamicShaderCache.h"
#include <assert.h>
#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
static kern_return_t noTransport(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*z){
 (void)c;(void)s;(void)i;(void)n;(void)o;(void)z;assert(!"factory/emitter test unexpectedly used IOKit");return kIOReturnUnsupported;
}
extern int A5MaliTestFramebufferFetchProfile(const A5MaliCompiledProfile *,int);
@interface A5MaliReadSurfCandidate (FetchTest)
- (const A5MaliCompiledProfile *)profile;
@end
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==3);NSError *error=nil;
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:
   [NSString stringWithUTF8String:argv[1]]] options:0 error:&error];assert(request&&!error);
 NSMutableDictionary *payload=[request mutableCopy];[payload removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 NSString *mode=[NSString stringWithUTF8String:argv[2]];
 NSString *identity=request[@"request_id"];assert(identity.length==64);
 assert([request[@"named_constants"] count]==58);
 if(![mode isEqual:@"good"]){
  assert(!A5MaliLoadDynamicShaderStage(identity,payload,&error)&&error);
  assert(error.code==([mode isEqual:@"bad-sampler"]?ENOTSUP:EINVAL));
  printf("PASS actual fetch cache rejects %s\n",mode.UTF8String);return 0;
 }
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:noTransport context:&argc commandCapabilities:63 operationCapabilities:0x7ffff];assert(device);
 const char *stock=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(stock);
 A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:stock]] error:&error];assert(library&&!error);
 MTLFunctionConstantValues *v=[MTLFunctionConstantValues new],*f=[MTLFunctionConstantValues new];
 size_t count=0;const A5MaliCompiledFunctionConstant *vc=A5MaliCompiledVertexConstantsForProfile(603,&count);assert(vc&&count==4);
 for(size_t i=0;i<count;i++)[v setConstantValue:vc[i].raw type:vc[i].dataType withName:[NSString stringWithUTF8String:vc[i].name]];
 for(NSDictionary *c in request[@"named_constants"]){
  NSString *raw=c[@"raw"];uint8_t bytes[16];unsigned n=(unsigned)raw.length/2;assert(n&&n<=sizeof(bytes));
  for(unsigned i=0;i<n;i++){unsigned x=0;assert(sscanf([[raw substringWithRange:NSMakeRange(i*2,2)]UTF8String],"%2x",&x)==1);bytes[i]=(uint8_t)x;}
  [f setConstantValue:bytes type:[c[@"type"] unsignedIntValue] withName:c[@"name"]];
 }
 MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
 d.vertexFunction=(id)[library newFunctionWithName:@"fixed_vert_lph_spc" constantValues:v error:&error];assert(d.vertexFunction&&!error);
 d.fragmentFunction=(id)[library newFunctionWithName:request[@"function"] constantValues:f error:&error];if(!d.fragmentFunction)NSLog(@"%@",error);assert(d.fragmentFunction&&!error);
 assert([(A5MaliMetalFunction*)d.fragmentFunction dynamicShader]);
 const A5MaliCompiledProfile *shape=A5MaliCompiledProfileForID(603);assert(shape);
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<shape->attributeCount;i++){const A5MaliCompiledVertexAttribute*a=shape->attributes+i;d.vertexDescriptor.attributes[a->index].format=a->format;d.vertexDescriptor.attributes[a->index].offset=a->offset;d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
 d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
 for(unsigned blend=0;blend<2;blend++){
  d.colorAttachments[0].blendingEnabled=blend;
  d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
  d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=blend?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero;
  error=nil;A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!pipeline)NSLog(@"%@",error);assert(pipeline&&!error);
  assert(A5MaliTestFramebufferFetchProfile([pipeline profile],blend));
 }
 printf("PASS exact 58-constant fetch: production MTLLibrary/newFunction -> dynamic pipeline -> real emitter; no GPU execution\n");
}return 0;}
