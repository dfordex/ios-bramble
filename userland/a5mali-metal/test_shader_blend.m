/* SPDX-License-Identifier: MIT
 * Genuine AIR publications -> factory -> native descriptors. Host only;
 * kernel transport is never called, so this does not assert physical pixels. */
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliDynamicPipeline.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliShaderCompileRequest.h"
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"
#include <assert.h>
#include <unistd.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
extern void A5MaliCheckShaderBlend(const uint8_t*,const float*);
@interface A5MaliMetalFunction (BlendTest)
- (instancetype)initWithLibrary:(A5MaliMetalLibrary*)library dynamicShader:(A5MaliDynamicShaderCacheEntry*)entry;
@end
@interface A5MaliReadSurfCandidate (BlendTest)
- (const A5MaliCompiledProfile*)profile;
@end
static kern_return_t wire(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)b;assert(!"factory must not submit");return kIOReturnError;}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==4);NSError *error=nil;
 NSMutableDictionary *payload=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])]
  options:NSJSONReadingMutableContainers error:&error];assert(payload&&!error);
 NSString *key=payload[@"request_id"];[payload removeObjectsForKeys:@[@"request_id",@"owner_uid"]];
 A5MaliDynamicShaderCacheEntry *base=A5MaliLoadDynamicShaderStage(key,payload,&error);assert(base&&!error);
 unsigned context=0;A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&context commandCapabilities:63 operationCapabilities:0x7ffff];
 A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:@(argv[3])] error:&error];assert(library&&!error);
 A5MaliMetalFunction *fragment=[[A5MaliMetalFunction alloc]initWithLibrary:library dynamicShader:base];
 const A5MaliCompiledProfile *original=A5MaliCompiledProfileForID(603);assert(original);
 size_t n=0;const A5MaliCompiledFunctionConstant *constants=A5MaliCompiledVertexConstantsForProfile(603,&n);
 MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
 for(size_t i=0;i<n;i++)[values setConstantValue:constants[i].raw type:constants[i].dataType withName:@(constants[i].name)];
 A5MaliMetalFunction *vertex=[library newFunctionWithName:@(original->vertexName) constantValues:values error:&error];assert(vertex&&!error);
 unsigned tested=0;
 for(NSString *folder in [NSFileManager.defaultManager contentsOfDirectoryAtPath:@(argv[2]) error:&error]){
  NSString *path=[[@(argv[2]) stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"receipt.json"];
  NSData *bytes=[NSData dataWithContentsOfFile:path];if(!bytes)continue;
  NSDictionary *receipt=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:&error];assert(receipt&&!error);
  NSDictionary *blend=receipt[@"blend_state"];if(!blend)continue;
  NSMutableDictionary *request=[payload mutableCopy];request[@"blend_state"]=blend;
  NSString *variantKey=A5MaliShaderCompileRequestID(request,&error);assert([variantKey isEqual:folder]&&!error);
  A5MaliDynamicShaderCacheEntry *variant=A5MaliLoadDynamicShaderStage(variantKey,request,&error);
  if(!variant)NSLog(@"%@",error);assert(variant&&!error&&[variant.nativeABI[@"blend_lowered"] boolValue]);
  /* Identical code must never be accepted for a different pipeline state. */
  NSMutableDictionary *bad=[request mutableCopy],*badBlend=[blend mutableCopy];
  badBlend[@"write_mask"]=@([blend[@"write_mask"] unsignedIntValue]^1);bad[@"blend_state"]=badBlend;
  assert(!A5MaliLoadDynamicShaderStage(variantKey,bad,&error)&&error.code==EINVAL);
  MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=(id)vertex;d.fragmentFunction=(id)fragment;
  MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[0];
  a.pixelFormat=[blend[@"format"] unsignedIntValue];a.writeMask=[blend[@"write_mask"] unsignedIntValue];a.blendingEnabled=YES;
  a.rgbBlendOperation=[blend[@"rgb_operation"] unsignedIntValue];a.alphaBlendOperation=[blend[@"alpha_operation"] unsignedIntValue];
  a.sourceRGBBlendFactor=[blend[@"source_rgb"] unsignedIntValue];a.destinationRGBBlendFactor=[blend[@"destination_rgb"] unsignedIntValue];
  a.sourceAlphaBlendFactor=[blend[@"source_alpha"] unsignedIntValue];a.destinationAlphaBlendFactor=[blend[@"destination_alpha"] unsignedIntValue];
  d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
  for(unsigned i=0;i<original->attributeCount;i++){const A5MaliCompiledVertexAttribute *v=original->attributes+i;
   d.vertexDescriptor.attributes[v->index].format=v->format;d.vertexDescriptor.attributes[v->index].offset=v->offset;d.vertexDescriptor.attributes[v->index].bufferIndex=v->bufferIndex;}
  d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
  A5MaliReadSurfCandidate *pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];
  if(!pipeline)NSLog(@"%@",error);assert(pipeline&&!error);
  const A5MaliCompiledProfile *profile=[pipeline profile];assert(profile->flags&A5MaliProfileShaderBlend);
  assert(A5MaliDynamicRuntimeProfileSupported(profile));
  assert(profile->passes[0].fragment.byteCount==variant.shader->byteCount&&!memcmp(profile->passes[0].fragment.bytes,variant.shader->bytes,variant.shader->byteCount));
  A5RuntimeMiscDraw command={.draw={.profile=profile,.descriptorGPUVA=0x4000000,.vertexCount=3,.primitive=A5RuntimeTriangle,
   .blend=A5RuntimeBlendState,.scissorWidth=32,.scissorHeight=32,.viewportWidth=32,.viewportHeight=32,.viewportFar=1},
   .blendColor={.125f,.25f,.5f,.75f}};
  command.colorAttachments[0]=(A5RuntimeImage){0x10000000,4096,32,32,a.pixelFormat==43?64:128,(uint32_t)a.pixelFormat};
  uint8_t *storage=calloc(64,8192);assert(storage);
  for(unsigned i=0;i<profile->resourceCount;i++){const A5MaliCompiledResource *r=profile->resources+i;
   if(r->kind==A5MaliResourceBuffer){assert(r->metalIndex<31&&r->uniformBytes<=8192);
    A5RuntimeBuffer b={.bytes=8192,.cpuBytes=storage+8192*((r->stage-1)*31+r->metalIndex)};
    if(r->stage==1)command.draw.vertexBuffers[r->metalIndex]=b;else command.draw.fragmentBuffers[r->metalIndex]=b;
   }else if(r->kind==A5MaliResourceTexture)command.fragmentTextures[r->metalIndex]=(A5RuntimeImage){0x11000000,4096,32,32,128,80};
   else if(r->kind==A5MaliResourceSampler&&!(r->flags&A5MaliResourceImmutableSampler))command.fragmentSamplers[r->metalIndex]=(A5RuntimeSampler){.valid=1,.normalizedCoordinates=1,.maxAnisotropy=1};
  }
  command.draw.vertexBuffers[1]=(A5RuntimeBuffer){.bytes=144,.cpuBytes=storage+8192};
  uint8_t *jobs=calloc(1,A5RuntimeJobBytes);assert(jobs);
  int result=A5MaliEncodeRuntimeMiscPass(&command,jobs,A5RuntimeJobBytes);
  if(result)fprintf(stderr,"blend emitter result=%d\n",result);assert(result==A5RuntimeOK);
  assert(!memcmp(jobs+0x8000,variant.shader->bytes,variant.shader->byteCount));
  A5MaliCheckShaderBlend(jobs,command.blendColor);
  A5MaliCompiledProfile invalid=*profile;invalid.flags&=~A5MaliProfileRenderState;
  assert(!A5MaliDynamicRuntimeProfileSupported(&invalid));
  free(jobs);free(storage);tested++;
 }
 assert(tested>=2);printf("PASS %u genuine shader-blend publications: factory, state identity, copy RSD, preload and constant UBO (host only)\n",tested);
}return 0;}
