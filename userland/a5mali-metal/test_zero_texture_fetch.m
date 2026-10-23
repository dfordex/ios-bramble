/* SPDX-License-Identifier: MIT */
#import "A5MaliDynamicPipeline.h"
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliMetalTexture.h"
#import "A5MaliNative.h"
extern void A5MaliCheckZeroFetchNative(const uint8_t *jobs);
#include <assert.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
typedef struct {unsigned queries,submits;BOOL failFence;} TransportState;
static kern_return_t transport(void*c,uint32_t selector,const void*input,size_t n,void*output,size_t*z){
 TransportState *s=c;
 if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==A5NativeQuerySelector){
  const A5NativeQueryRequest *q=input;assert(n==sizeof(*q)&&q->surfaces[0]==0x100000001);
  for(unsigned i=1;i<A5NativeSlots;i++)assert(!q->surfaces[i]);
  for(unsigned i=0;i<A5NativeSlots;i++)assert(!q->buffers[i]);
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=91};
  r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x13000000,4096,32,32,128,0x42475241,3};
  assert(*z==sizeof(r));memcpy(output,&r,sizeof(r));*z=sizeof(r);s->queries++;return KERN_SUCCESS;
 }
 assert(selector==A5NativeSubmitSelector);
 const A5NativeSubmitRequest *q=input;assert(n==sizeof(*q)+A5NativeJobBytes);
 assert(q->profileID==A5MaliDynamicProfileID&&q->mappingEpoch==91&&q->readSurfaces==1&&q->writeSurfaces==1&&!q->readBuffers);
 const uint8_t *jobs=(const uint8_t*)input+sizeof(*q);
 A5MaliCheckZeroFetchNative(jobs);
 s->submits++;if(s->failFence)return kIOReturnTimeout;
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=51,.fragmentFence=52};
 assert(*z==sizeof(r));memcpy(output,&r,sizeof(r));*z=sizeof(r);return KERN_SUCCESS;
}
extern int A5MaliTestZeroTextureFetch(const A5MaliCompiledProfile *,int);
@interface A5MaliReadSurfCandidate (FetchTest)
- (const A5MaliCompiledProfile *)profile;
@end
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==2);NSError *error=nil;
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:
   [NSString stringWithUTF8String:argv[1]]] options:0 error:&error];assert(request&&!error);
 NSMutableDictionary *payload=[request mutableCopy];[payload removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 NSString *identity=request[@"request_id"];assert(identity.length==64);
 assert([request[@"named_constants"] count]==58);
 TransportState state={0};
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&state commandCapabilities:63 operationCapabilities:0x7ffff];assert(device);
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
  const A5MaliCompiledProfile *profile=[pipeline profile];
  assert(A5MaliTestZeroTextureFetch(profile,blend));
  for(unsigned fail=0;fail<2;fail++){
   state=(TransportState){.failFence=fail};
   A5MaliMetalBuffer *buffer=[[device newCommandQueue]commandBuffer];
   MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
   pass.colorAttachments[0].texture=(id)[device hostTestTextureWithResource:(A5MaliResource){0x100000001,32,32,128,3}];
   pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
   A5MaliMetalRenderEncoder *encoder=[buffer renderCommandEncoderWithDescriptor:pass];assert(encoder);
   [encoder setRenderPipelineState:pipeline];
   uint8_t vertices[288]={0},uniform[4096]={0};
   [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:1];
   for(unsigned i=0;i<profile->resourceCount;i++){
    const A5MaliCompiledResource *r=profile->resources+i;
    if(r->kind!=A5MaliResourceBuffer)continue;
    if(r->stage==1)[encoder setVertexBytes:uniform length:r->uniformBytes atIndex:r->metalIndex];
    else [encoder setFragmentBytes:uniform length:r->uniformBytes atIndex:r->metalIndex];
   }
   /* No sampled texture or sampler is bound at any slot. */
   [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];[encoder endEncoding];
   [buffer commit];[buffer waitUntilCompleted];
   assert(state.queries==1&&state.submits==1);
   assert(buffer.status==(fail?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted));
  }
 }
 /* Native IO corruption must fail admission even when code/cache ownership
  * and the real Metal function identity are otherwise unchanged. */
 A5MaliDynamicShaderCacheEntry *entry=[(A5MaliMetalFunction*)d.fragmentFunction dynamicShader];
 NSDictionary *original=entry.nativeABI;
 for(unsigned fault=0;fault<5;fault++){
  NSMutableDictionary *abi=[original mutableCopy];
  if(fault==0)abi[@"inputs"]=@[@{@"location":@33,@"base":@1,@"component":@0,@"components":@4,@"bit_size":@32}];
  if(fault==1)abi[@"inputs"]=@[@{@"location":@32,@"base":@0,@"component":@0,@"components":@2,@"bit_size":@32}];
  if(fault==2)abi[@"framebuffer_fetch"]=@NO;
  if(fault==3){NSMutableDictionary *n=[abi[@"native_info"] mutableCopy];n[@"textures"]=@1;n[@"samplers"]=@1;abi[@"native_info"]=n;}
  if(fault==4)abi[@"outputs"]=@[@{@"location":@4,@"base":@0,@"component":@0,@"components":@3,@"bit_size":@32}];
  [entry setValue:abi forKey:@"nativeABI"];
  error=nil;assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);
 }
 [entry setValue:original forKey:@"nativeABI"];
 printf("PASS exact 58-constant zero-input fetch (4 native submissions, including 2 injected fence failures): production MTLLibrary/newFunction -> zero-input pipeline -> real emitter; no GPU execution\n");
}return 0;}
