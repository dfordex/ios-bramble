/* SPDX-License-Identifier: MIT
 * Actual typed stage publications through production Metal API. Only kernel
 * transport is mocked; no GPU or physical screen result is claimed here.
 */
#import "A5MaliDynamicPipeline.h"
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliMetalTexture.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
extern int A5MaliTestTwoTextureProfile(const A5MaliCompiledProfile*,unsigned);
extern int A5MaliWriteTwoTextureFixture(const A5MaliCompiledProfile*,const char*);
extern void A5MaliCheckTwoTextureNative(const uint8_t*,uint64_t);
@interface A5MaliReadSurfCandidate (TwoTextureTest)
- (const A5MaliCompiledProfile *)profile;
@end
typedef struct {unsigned queries,submits;BOOL badSpan;} TransportState;
static kern_return_t transport(void*c,uint32_t sel,const void*input,size_t n,void*output,size_t*z){
 TransportState *s=c;if(sel==A5MaliUnmap||sel==A5MaliRelease)return KERN_SUCCESS;
 if(sel==A5NativeQuerySelector){
  const A5NativeQueryRequest*q=input;assert(n==sizeof(*q));
  assert(q->surfaces[0]==0x100000001&&q->surfaces[1]==0x100000002&&q->surfaces[2]==0x100000003);
  for(unsigned i=3;i<A5NativeSlots;i++)assert(!q->surfaces[i]);
  for(unsigned i=0;i<A5NativeSlots;i++)assert(!q->buffers[i]);
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=171};
  for(unsigned i=0;i<3;i++)r.surfaces[i]=(A5NativeSpan){q->surfaces[i],0x13000000+0x01000000*i,4096,32,32,128,0x42475241,i?A5MaliRead:A5MaliRead|A5MaliWrite};
  if(s->badSpan)r.surfaces[2].bytes=4095;
  assert(*z==sizeof(r));memcpy(output,&r,sizeof(r));*z=sizeof(r);s->queries++;return KERN_SUCCESS;
 }
 assert(sel==A5NativeSubmitSelector);const A5NativeSubmitRequest*q=input;
 assert(n==sizeof(*q)+A5NativeJobBytes&&q->profileID==A5MaliDynamicProfileID&&q->mappingEpoch==171);
 assert(q->readSurfaces==7&&q->writeSurfaces==1&&!q->readBuffers);
 A5MaliCheckTwoTextureNative((const uint8_t*)input+sizeof(*q),A5NativeJobVA);s->submits++;
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=51,.fragmentFence=52};assert(*z==sizeof(r));memcpy(output,&r,sizeof(r));*z=sizeof(r);return KERN_SUCCESS;
}
static NSDictionary *request(const char*path){
 NSDictionary*r=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]]options:0 error:NULL];assert([r isKindOfClass:NSDictionary.class]);return r;
}
static id function(A5MaliMetalLibrary*l,NSDictionary*r){
 MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
 for(NSDictionary*c in r[@"named_constants"]){uint8_t b[16];NSString*raw=c[@"raw"];assert(raw.length&&raw.length/2<=16);
  for(unsigned i=0;i<raw.length/2;i++){unsigned x=0;assert(sscanf([[raw substringWithRange:NSMakeRange(2*i,2)]UTF8String],"%2x",&x)==1);b[i]=x;}
  [values setConstantValue:b type:[c[@"type"] unsignedIntValue]withName:c[@"name"]];
 }
 NSError*error=nil;id f=[l newFunctionWithName:r[@"function"]constantValues:values error:&error];if(!f)NSLog(@"%@",error);assert(f&&!error&&[(A5MaliMetalFunction*)f dynamicShader]);return f;
}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==3||argc==4);
 if(argc==4){
  NSMutableDictionary *payload=[request(argv[1]) mutableCopy];NSString *identity=payload[@"request_id"];
  [payload removeObjectsForKeys:@[@"request_id",@"owner_uid"]];NSError *error=nil;
  assert(!A5MaliLoadDynamicShaderStage(identity,payload,&error)&&error);
  puts("PASS rejected malformed/dead-blob native cache contract");return 0;
 }
 TransportState state={0};
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&state commandCapabilities:63 operationCapabilities:0x7ffff];
 const char*stock=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(stock);NSError*error=nil;
 A5MaliMetalLibrary*l=[device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:stock]]error:&error];assert(l&&!error);
 MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];d.vertexFunction=function(l,request(argv[2]));d.fragmentFunction=function(l,request(argv[1]));
 const A5MaliCompiledProfile*shape=A5MaliCompiledProfileForID(603);assert(shape);
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];for(unsigned i=0;i<shape->attributeCount;i++){const A5MaliCompiledVertexAttribute*a=shape->attributes+i;d.vertexDescriptor.attributes[a->index].format=a->format;d.vertexDescriptor.attributes[a->index].offset=a->offset;d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
 for(unsigned blend=0;blend<2;blend++){
  d.colorAttachments[0].blendingEnabled=blend;d.colorAttachments[0].sourceRGBBlendFactor=d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;d.colorAttachments[0].destinationRGBBlendFactor=d.colorAttachments[0].destinationAlphaBlendFactor=blend?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorZero;
  error=nil;A5MaliReadSurfCandidate*p=[device newRenderPipelineStateWithDescriptor:d error:&error];if(!p)NSLog(@"%@",error);assert(p&&!error);const A5MaliCompiledProfile*profile=[p profile];assert(A5MaliTestTwoTextureProfile(profile,blend));
  const char*fixture=getenv("A5_TWO_TEXTURE_FIXTURE");if(fixture&&!blend)assert(A5MaliWriteTwoTextureFixture(profile,fixture));
  for(unsigned fault=0;fault<4;fault++){
   state=(TransportState){.badSpan=fault==2};unsigned before=state.queries;
   A5MaliMetalTexture*images[3];for(unsigned i=0;i<3;i++)images[i]=[device hostTestTextureWithResource:(A5MaliResource){0x100000001+i,32,32,128,i?A5MaliRead:A5MaliRead|A5MaliWrite}];
   A5MaliMetalBuffer*buffer=[[device newCommandQueue]commandBuffer];MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=(id)images[0];pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
   A5MaliMetalRenderEncoder*e=[buffer renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:p];uint8_t vertices[288]={0},matrix[64]={0},uv[32]={0};float lod[]={.375f,.625f};
   [e setVertexBytes:vertices length:288 atIndex:1];[e setVertexBytes:matrix length:64 atIndex:2];[e setVertexBytes:uv length:32 atIndex:3];[e setFragmentBytes:lod length:8 atIndex:2];
   for(unsigned i=0;i<2;i++){MTLSamplerDescriptor*sampler=[MTLSamplerDescriptor new];sampler.minFilter=sampler.magFilter=i?MTLSamplerMinMagFilterLinear:MTLSamplerMinMagFilterNearest;if(fault==3&&i==1)sampler.normalizedCoordinates=NO;
    if(!(fault==1&&i==1))[e setFragmentSamplerState:[device newSamplerStateWithDescriptor:sampler]atIndex:i];[e setFragmentTexture:images[i+1]atIndex:i+3];}
   [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];[e endEncoding];[buffer commit];[buffer waitUntilCompleted];
   if(!fault)assert(buffer.status==MTLCommandBufferStatusCompleted&&state.queries==before+1&&state.submits==1);
   else assert(buffer.status==MTLCommandBufferStatusError&&state.queries==before+(fault==2)&&!state.submits);
  }
 }
 /* A one-UV vertex must not masquerade as the genuine dual-UV stage. */
 A5MaliDynamicShaderCacheEntry*vs=[(A5MaliMetalFunction*)d.vertexFunction dynamicShader];NSDictionary*original=vs.nativeABI;NSMutableDictionary*bad=[original mutableCopy];NSMutableDictionary*ni=[bad[@"native_info"]mutableCopy];ni[@"attributes"]=@3;bad[@"native_info"]=ni;[vs setValue:bad forKey:@"nativeABI"];error=nil;assert(!A5MaliComposeDynamicPipeline(d,&error)&&error);[vs setValue:original forKey:@"nativeABI"];
 /* Admission-only lane classification checks, not altered GPU execution:
  * old color.xy/color.zw must remain single-UV; scalar-split UV1 plus the
  * real color34 remains dual-UV. Both consume the already-supported VS4. */
 A5MaliDynamicShaderCacheEntry *fragment=[(A5MaliMetalFunction*)d.fragmentFunction dynamicShader];
 NSDictionary *fragmentOriginal=fragment.nativeABI;
 for(unsigned dual=0;dual<2;dual++){
  NSMutableDictionary *lanes=[fragmentOriginal mutableCopy];
  NSMutableArray *inputs=[NSMutableArray arrayWithObject:@{@"location":@32,@"base":@0,@"component":@0,@"components":@2,@"bit_size":@32}];
  if(dual){
   [inputs addObject:@{@"location":@33,@"base":@1,@"component":@0,@"components":@1,@"bit_size":@32}];
   [inputs addObject:@{@"location":@33,@"base":@1,@"component":@1,@"components":@1,@"bit_size":@32}];
  }
  for(unsigned component=0;component<4;component+=2)
   [inputs addObject:@{@"location":@(dual?34:33),@"base":@(dual?2:1),@"component":@(component),@"components":@2,@"bit_size":@32}];
  lanes[@"inputs"]=inputs;[fragment setValue:lanes forKey:@"nativeABI"];error=nil;
  A5MaliDynamicPipelineEntry *linked=A5MaliComposeDynamicPipeline(d,&error);assert(linked&&!error);
  assert(!!(linked.profile->flags&A5MaliProfileFragmentTwoUV)==dual);
  assert(linked.profile->flags&A5MaliProfileDynamicColorVarying);
 }
 [fragment setValue:fragmentOriginal forKey:@"nativeABI"];
 puts("PASS actual two-image dual-UV stage factory/API mapping/samplers/UBO bounds and malformed pairing; no GPU execution");
}return 0;}
