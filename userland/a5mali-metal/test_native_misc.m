/* SPDX-License-Identifier: MIT
 * Actual authenticated misc shaders + released v4 emitter. Mock IOKit only:
 * two native output passes, full large SSBO upload and fence-ordered cleanup.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliCompiledRegistry.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

typedef struct{A5MaliHeader h;uint32_t bytes,usage;}Create;
typedef struct{A5MaliHeader h;uint64_t handle;uint32_t bytes,usage;}Created;
typedef struct{A5MaliHeader h;uint64_t handle;}BufferHandle;
typedef struct{
 unsigned creates,queries,submits,releases,bulkCalls;
 uint32_t allocation[2],uploaded[2];
 uint8_t *expected[2],*actual[2];
 uint32_t lengths[2];
 BOOL failSecond;
 const A5MaliCompiledProfile *profile;
}State;
static kern_return_t wire(void *context,uint32_t selector,const void *input,size_t bytes,void *output,size_t *outBytes)
{
 State*s=context;
 if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==8){const Create*q=input;assert(bytes==sizeof(*q)&&s->creates<2&&q->usage==3);
  unsigned i=s->creates++;s->allocation[i]=q->bytes;
  Created r={{1,sizeof(r),0,0},UINT64_C(0x100000101)+i,q->bytes,q->usage};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5NativeBulkWriteSelector){const A5NativeBulkWriteRequest*q=input;
  unsigned i=(unsigned)(q->handle-UINT64_C(0x100000101));assert(i<2);
  assert(bytes==sizeof(*q)+q->length&&q->offset==s->uploaded[i]);
  assert(q->offset<=s->lengths[i]&&q->length<=s->lengths[i]-q->offset);
  memcpy(s->actual[i]+q->offset,(const uint8_t*)input+sizeof(*q),q->length);
  s->uploaded[i]+=q->length;++s->bulkCalls;assert(!output);return KERN_SUCCESS;}
 if(selector==9){const BufferHandle*q=input;unsigned i=(unsigned)(q->handle-UINT64_C(0x100000101));
  assert(i<2&&s->submits==2);++s->releases;return KERN_SUCCESS;}
 if(selector==A5NativeQuerySelector){const A5NativeQueryRequest*q=input;
  assert(bytes==sizeof(*q)&&q->surfaces[0]==0x100000001&&q->surfaces[1]==0x100000002&&!q->surfaces[2]);
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,
   .jobBytes=A5NativeJobBytes,.flags=11+s->queries};
  for(unsigned i=0;i<2;++i){
   assert(q->buffers[i]==UINT64_C(0x100000101)+i);
   r.surfaces[i]=(A5NativeSpan){q->surfaces[i],0x10000000+i*0x01000000,4096,32,32,128,0x42475241,A5MaliRead|A5MaliWrite};
   r.buffers[i]=(A5NativeSpan){q->buffers[i],0x13000000+i*0x00800000,s->allocation[i],0,0,0,0,A5MaliRead|A5MaliWrite};
  }
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->queries;return KERN_SUCCESS;}
 assert(selector==A5NativeSubmitSelector);
 const A5NativeSubmitRequest*q=input;unsigned pass=s->submits;
 assert(pass<2&&bytes==sizeof(*q)+A5NativeJobBytes);
 assert(q->profileID==200+pass&&q->mappingEpoch==11+pass&&q->readBuffers==3);
 assert(q->readSurfaces==(1u<<pass)&&q->writeSurfaces==(1u<<pass));
 for(unsigned i=0;i<2;++i)assert(s->uploaded[i]==s->lengths[i]&&!memcmp(s->actual[i],s->expected[i],s->lengths[i]));
 const uint8_t*d=(const uint8_t*)input+sizeof(*q);
 assert(!memcmp(d+0x6000,s->profile->passes[pass].vertex.bytes,s->profile->passes[pass].vertex.byteCount));
 assert(!memcmp(d+0x8000,s->profile->passes[pass].fragment.bytes,s->profile->passes[pass].fragment.byteCount));
 uint64_t vsStorage=0,fsStorage=0;
 memcpy(&vsStorage,d+0x1000+96,8);memcpy(&fsStorage,d+0x1400+144,8);
 assert(vsStorage==0x13000000&&fsStorage==0x13800000);
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=400+2*pass,.fragmentFence=401+2*pass};
 if(s->failSecond&&pass==1)r.status=3;
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->submits;return KERN_SUCCESS;
}
static MTLRenderPipelineDescriptor *pipelineDescriptor(const A5MaliCompiledProfile*p,A5MaliMetalLibrary*library)
{
 MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];
 d.vertexFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:p->vertexName]];
 d.fragmentFunction=(id)[library newFunctionWithName:[NSString stringWithUTF8String:p->fragmentName]];
 for(unsigned i=0;i<8;++i)d.colorAttachments[i].pixelFormat=p->colorFormats[i];
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<p->attributeCount;++i){const A5MaliCompiledVertexAttribute*a=p->attributes+i;
  d.vertexDescriptor.attributes[a->index].format=a->format;d.vertexDescriptor.attributes[a->index].offset=a->offset;
  d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 for(unsigned i=0;i<p->layoutCount;++i){const A5MaliCompiledVertexLayout*l=p->layouts+i;
  d.vertexDescriptor.layouts[l->index].stride=l->stride;d.vertexDescriptor.layouts[l->index].stepFunction=l->stepFunction;
  d.vertexDescriptor.layouts[l->index].stepRate=l->stepRate;}
 return d;
}
static void run(BOOL failure)
{
 State s={.failSecond=failure,.lengths={192,131073}};s.profile=A5MaliCompiledProfileForID(200);assert(s.profile);
 for(unsigned i=0;i<2;++i){s.expected[i]=malloc(s.lengths[i]);s.actual[i]=calloc(1,s.lengths[i]);
  assert(s.expected[i]&&s.actual[i]);for(unsigned j=0;j<s.lengths[i];++j)s.expected[i][j]=(uint8_t)(29+i*17+j*11);}
 @autoreleasepool{
  A5MaliRestrictedDevice*device=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&s
   commandCapabilities:63 operationCapabilities:0x7ffff];
  const char*path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
  A5MaliMetalLibrary*library=[device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]error:NULL];assert(library);
  NSError*error=nil;id pipeline=[device newRenderPipelineStateWithDescriptor:pipelineDescriptor(s.profile,library)error:&error];assert(pipeline&&!error);
  A5MaliMetalBuffer*b=[[device newCommandQueue]commandBuffer];
  MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];
  for(unsigned i=0;i<2;++i){pass.colorAttachments[i].texture=(id)[device hostTestTextureWithResource:
   (A5MaliResource){0x100000001+i,32,32,128,A5MaliWrite}];
   pass.colorAttachments[i].loadAction=MTLLoadActionLoad;pass.colorAttachments[i].storeAction=MTLStoreActionStore;}
  A5MaliMetalRenderEncoder*r=[b renderCommandEncoderWithDescriptor:pass];assert(r&&r.device==device);
  r.label=@"two genuine outputs";assert([r.label isEqualToString:@"two genuine outputs"]);
  [r pushDebugGroup:@"actual resource submission"];[r insertDebugSignpost:@"two passes"];[r popDebugGroup];
  [r setCullMode:MTLCullModeNone];[r setTriangleFillMode:MTLTriangleFillModeFill];
  [r setDepthBias:0 slopeScale:0 clamp:0];[r setDepthStencilState:nil];
  [r setRenderPipelineState:pipeline];
  uint8_t matrix[64];memset(matrix,0x34,sizeof(matrix));[r setVertexBytes:matrix length:64 atIndex:2];
  uint8_t info[8]={4,3,2,1,8,7,6,5};[r setFragmentBytes:info length:8 atIndex:1];
  A5MaliPrivateBuffer*vertices=[device newBufferWithLength:s.lengths[0]+17 options:0];
  A5MaliPrivateBuffer*storage=[device newBufferWithLength:s.lengths[1]+31 options:0];assert(vertices&&storage);
  [r setVertexBuffer:vertices offset:17 atIndex:1];[r setFragmentBuffer:storage offset:31 atIndex:9];
  [r drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[r endEncoding];
  memcpy((uint8_t*)vertices.contents+17,s.expected[0],s.lengths[0]);
  memcpy((uint8_t*)storage.contents+31,s.expected[1],s.lengths[1]);
  assert(!s.creates&&!s.submits);[b commit];[b waitUntilCompleted];
  assert(b.status==(failure?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted));
  assert(s.creates==2&&s.queries==2&&s.submits==2&&s.releases==2&&s.bulkCalls==2);
 }
 for(unsigned i=0;i<2;++i){free(s.expected[i]);free(s.actual[i]);}
}
int main(void){@autoreleasepool{run(NO);run(YES);puts("native misc: two authenticated passes, full131073-byteSSBO, commit snapshots and post-fence cleanup passed (mock transport)");}return 0;}
