/* SPDX-License-Identifier: MIT
 * Replay authenticated private pipeline snapshots; no captured payloads or GPU execution.
 */
#import "A5MaliDynamicPipeline.h"
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliShaderCompileRequest.h"
#include <assert.h>
#include <unistd.h>
#include <sys/stat.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
@interface A5MaliMetalFunction(Replay)
- (instancetype)initWithLibrary:(A5MaliMetalLibrary*)l dynamicShader:(A5MaliDynamicShaderCacheEntry*)e;
@end
static kern_return_t wire(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b){(void)c;(void)s;(void)i;(void)n;(void)o;(void)b;abort();}
static NSData*raw(NSString*s){NSMutableData*d=[NSMutableData dataWithLength:s.length/2];for(NSUInteger i=0;i<d.length;i++){unsigned v;assert(sscanf([s substringWithRange:NSMakeRange(i*2,2)].UTF8String,"%02x",&v)==1);((uint8_t*)d.mutableBytes)[i]=v;}return d;}
static id function(A5MaliMetalLibrary*l,NSDictionary*p){
 NSString*k=A5MaliShaderCompileRequestID(p,NULL);A5MaliDynamicShaderCacheEntry*e=A5MaliLoadDynamicShaderStage(k,p,NULL);
 if(e)return [[A5MaliMetalFunction alloc]initWithLibrary:l dynamicShader:e];
 size_t n=0;const A5MaliCompiledProfile*profiles=A5MaliCompiledProfiles(&n);
 for(size_t i=0;i<n;i++){
  BOOL vertex=[p[@"stage"]isEqual:@"vertex"];size_t count=0;
  const A5MaliCompiledFunctionConstant*c=vertex?A5MaliCompiledVertexConstantsForProfile(profiles[i].profileID,&count):A5MaliCompiledConstantsForProfile(profiles[i].profileID,&count);
  if(![p[@"function"]isEqual:@(vertex?profiles[i].vertexName:profiles[i].fragmentName)]||[p[@"named_constants"]count]!=count||[p[@"indexed_constants"]count])continue;
  BOOL same=YES;MTLFunctionConstantValues*v=[MTLFunctionConstantValues new];
  for(NSDictionary*r in p[@"named_constants"]){NSData*d=raw(r[@"raw"]);BOOL found=NO;
   for(size_t j=0;j<count;j++)if([r[@"name"]isEqual:@(c[j].name)]&&[r[@"type"]unsignedIntValue]==c[j].dataType&&d.length==c[j].byteCount&&!memcmp(d.bytes,c[j].raw,d.length))found=YES;
   if(!found){same=NO;break;}[v setConstantValue:d.bytes type:[r[@"type"]unsignedIntValue] withName:r[@"name"]];
  }
  if(same)return count?[l newFunctionWithName:p[@"function"] constantValues:v error:NULL]:[l newFunctionWithName:p[@"function"]];
 }
 const char*dst=getenv("A5_REPLAY_MISSING_REQUESTS");if(dst){
  NSString*dir=@(dst);assert([dir hasPrefix:@"/private/tmp/"]);
  NSMutableDictionary*body=[p mutableCopy];body[@"owner_uid"]=@(geteuid());body[@"request_id"]=k;
  NSData*data=[NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingSortedKeys error:NULL];assert(data);
  NSString*path=[dir stringByAppendingPathComponent:[k stringByAppendingString:@".request.json"]];
  if(![NSFileManager.defaultManager fileExistsAtPath:path]){assert([data writeToFile:path atomically:YES]);assert(!chmod(path.fileSystemRepresentation,0600));}
 }
 return nil;
}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==3);unsigned ctx=0;A5MaliRestrictedDevice*device=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&ctx commandCapabilities:63 operationCapabilities:0x7ffff];
 A5MaliMetalLibrary*l=[device newLibraryWithURL:[NSURL fileURLWithPath:@(argv[2])]error:NULL];assert(l);unsigned pass=0,fail=0,skip=0;
 for(NSString*name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:@(argv[1]) error:NULL]){
  NSDictionary*p=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[@(argv[1])stringByAppendingPathComponent:name]]options:0 error:NULL];
  if(![p[@"kind"]isEqual:@"pipeline"])continue;
  MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];d.vertexFunction=function(l,p[@"vertex"]);d.fragmentFunction=function(l,p[@"fragment"]);
  if(!d.vertexFunction||!d.fragmentFunction){skip++;continue;}NSDictionary*s=p[@"descriptor"];
  d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];for(NSDictionary*a in s[@"vertex_attributes"]){NSUInteger i=[a[@"index"]unsignedIntValue];d.vertexDescriptor.attributes[i].format=[a[@"format"]unsignedIntValue];d.vertexDescriptor.attributes[i].offset=[a[@"offset"]unsignedIntValue];d.vertexDescriptor.attributes[i].bufferIndex=[a[@"buffer_index"]unsignedIntValue];}
  for(NSDictionary*a in s[@"vertex_layouts"]){NSUInteger i=[a[@"index"]unsignedIntValue];d.vertexDescriptor.layouts[i].stride=[a[@"stride"]unsignedIntValue];d.vertexDescriptor.layouts[i].stepFunction=[a[@"step_function"]unsignedIntValue];d.vertexDescriptor.layouts[i].stepRate=[a[@"step_rate"]unsignedIntValue];}
  unsigned i=0;for(NSDictionary*a in s[@"color_attachments"]){MTLRenderPipelineColorAttachmentDescriptor*t=d.colorAttachments[i++];t.pixelFormat=[a[@"format"]unsignedIntValue];t.writeMask=[a[@"write_mask"]unsignedIntValue];t.blendingEnabled=[a[@"blend_enabled"]boolValue];t.rgbBlendOperation=[a[@"rgb_operation"]unsignedIntValue];t.alphaBlendOperation=[a[@"alpha_operation"]unsignedIntValue];t.sourceRGBBlendFactor=[a[@"source_rgb"]unsignedIntValue];t.sourceAlphaBlendFactor=[a[@"source_alpha"]unsignedIntValue];t.destinationRGBBlendFactor=[a[@"destination_rgb"]unsignedIntValue];t.destinationAlphaBlendFactor=[a[@"destination_alpha"]unsignedIntValue];}
  d.rasterSampleCount=[s[@"raster_sample_count"]unsignedIntValue];d.depthAttachmentPixelFormat=[s[@"depth_format"]unsignedIntValue];d.stencilAttachmentPixelFormat=[s[@"stencil_format"]unsignedIntValue];d.inputPrimitiveTopology=[s[@"input_primitive_topology"]unsignedIntValue];d.rasterizationEnabled=[s[@"rasterization_enabled"]boolValue];
  NSDictionary*roundtrip=A5MaliShaderCompilePipelinePayload(d,[(A5MaliMetalFunction*)d.vertexFunction compileRequestPayload],[(A5MaliMetalFunction*)d.fragmentFunction compileRequestPayload],NULL);assert([roundtrip[@"descriptor"]isEqual:s]);
  NSError*error=nil;id result=[device newRenderPipelineStateWithDescriptor:d error:&error];if(result){pass++;}else{fail++;printf("FAIL %s %s\n",name.UTF8String,error.localizedDescription.UTF8String);}
 }
 printf("COUNTS pass=%u fail=%u missing-stage=%u\n",pass,fail,skip);
}return 0;}
